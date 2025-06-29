# frozen_string_literal: true
# typed: true

require "wal"

module Waldit
  class Watcher < Wal::StreamingWatcher
    extend T::Sig

    sig { params(event: T.any(InsertEvent, UpdateEvent, DeleteEvent)).void }
    def audit_event(event)
      return unless event.primary_key

      audit = {
        transaction_id: event.transaction_id,
        lsn: event.lsn,
        context: event.context,
        table_name: event.table,
        primary_key: event.primary_key,
      }

      unique_by = %i[table_name primary_key transaction_id]

      case event
      when InsertEvent
        record.upsert(
          audit.merge(action: "insert", new: event.new),
          unique_by:,
          on_duplicate: :update,
        )

      when UpdateEvent
        return if event.diff.without(ignored_columns(event.table)).empty?
        record.upsert(
          audit.merge(action: "update", old: event.old, new: event.new),
          unique_by:,
          on_duplicate: :update,
          update_only: %w[new],
        )

      when DeleteEvent
        case record.where(audit.slice(*unique_by)).pluck(:action, :old).first
        in ["insert", _]
          # We are deleting a record that was inserted on this transaction, which means we don't need to audit anything,
          # as the record was never commited
          record.where(audit.slice(*unique_by)).delete_all

        in ["update", old]
          # We are deleting a record we updated on this transaction. Here we are making sure we keep the correct previous
          # state, and not the state at the moment of the deletion
          record.upsert(
            audit.merge(action: "delete", old:, new: {}),
            unique_by:,
            on_duplicate: :update,
          )

        in ["delete", _]
          # This should never happend, we wouldn't be able to delete a record that was already deleted on this transaction

        else
          # Finally the most common case: just deleting a record not created or updated on this transaction
          record.upsert(
            audit.merge(action: "delete", old:),
            unique_by:,
            on_duplicate: :update,
          )
        end
      end
    end

    sig { override.params(events: T::Enumerator[Event]).void }
    def on_transaction_events(events)
      counter = 0
      catch :finish do
        loop do
          record.transaction do
            events.each do |event|
              case event
              when CommitTransactionEvent
                record
                  .where(transaction_id: event.transaction_id)
                  .update_all(commited_at: event.timestamp) if counter > 0
                # Using throw to break the outside loop and finish the thread gracefully
                throw :finish

              when InsertEvent, UpdateEvent, DeleteEvent
                audit_event(event)

                counter += 1
                # We break here to force a commit, so we don't keep a single big transaction pending
                break if counter % max_transaction_size == 0
              end
            end
          end
        end
      end
    end

    sig { params(table: String).returns(T::Boolean) }
    def should_watch_table?(table)
      Waldit.watched_tables.call(table)
    end

    sig { params(prefix: String).returns(T::Boolean) }
    def valid_context_prefix?(prefix)
      prefix == Waldit.context_prefix
    end

    sig { params(table: String).returns(T::Array[String]) }
    def ignored_columns(table)
      Waldit.ignored_columns.call(table)
    end

    sig { returns(Integer) }
    def max_transaction_size
      Waldit.max_transaction_size
    end

    sig { returns(T.class_of(ActiveRecord::Base)) }
    def record
      Waldit.model
    end
  end
end
