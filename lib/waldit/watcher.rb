# frozen_string_literal: true

require "wal"

module Waldit
  class Watcher < Wal::StreamingWatcher
    include Wal

    def audit_event(event)
      return unless event.primary_key

      audit = [event.transaction_id, event.lsn, event.table, event.primary_key, event.context.to_json]

      case event
      when InsertEvent
        new_attributes = clean_attributes(event.table, event.new)
        @connection.exec_prepared("waldit_insert", audit + [new_attributes.to_json])

      when UpdateEvent
        return if event.diff.without(ignored_columns(event.table)).empty?
        old_attributes = clean_attributes(event.table, event.old)
        new_attributes = clean_attributes(event.table, event.new)

        @connection.exec_prepared("waldit_update", audit + [old_attributes.to_json, new_attributes.to_json])

      when DeleteEvent
        case @connection.exec_prepared("waldit_delete_cleanup", [event.transaction_id, event.table, event.primary_key]).values
        in [["update", previous_old]]
          @connection.exec_prepared("waldit_delete", audit + [previous_old])
        in []
          @connection.exec_prepared("waldit_delete", audit + [clean_attributes(event.table, event.old).to_json])
        else
          # Don't need to audit anything on this case
        end
      end
    end

    def on_transaction_events(events)
      record.transaction do
        @connection = record.connection.raw_connection
        tables = Set.new
        insert_prepared = false
        update_prepared = false
        delete_prepared = false

        events.each do |event|
          case event
          when CommitTransactionEvent
            record.where(transaction_id: event.transaction_id).update_all(commited_at: event.timestamp)

            changes = [:old, :new, :diff]
              .map { |diff| [diff, tables.filter { |table| Waldit.store_changes.call(table).include? diff }] }
              .to_h

            log_new = (changes[:new] || []).map { |table| "'#{table}'" }.join(",")
            log_old = (changes[:old] || []).map { |table| "'#{table}'" }.join(",")
            log_diff = (changes[:diff] || []).map { |table| "'#{table}'" }.join(",")

            record.where(transaction_id: event.transaction_id, action: "update").update_all(<<~SQL)
              new = CASE WHEN table_name = ANY (ARRAY[#{log_new}]::varchar[]) THEN new ELSE null END,
              old = CASE WHEN table_name = ANY (ARRAY[#{log_old}]::varchar[]) THEN old ELSE null END,
              diff =
                CASE WHEN table_name = ANY (ARRAY[#{log_diff}]::varchar[]) THEN (
                  SELECT
                    jsonb_object_agg(
                      coalesce(old_kv.key, new_kv.key),
                      jsonb_build_array(old_kv.value, new_kv.value)
                    )
                  FROM jsonb_each(old) AS old_kv
                  FULL OUTER JOIN jsonb_each(new) AS new_kv ON old_kv.key = new_kv.key
                  WHERE old_kv.value IS DISTINCT FROM new_kv.value
                )
                ELSE null
                END
            SQL

          when InsertEvent
            tables << event.table
            unless insert_prepared
              prepare_insert
              insert_prepared = true
            end
            audit_event(event)

          when UpdateEvent
            tables << event.table
            unless update_prepared
              prepare_update
              update_prepared = true
            end
            audit_event(event)

          when DeleteEvent
            tables << event.table
            unless delete_prepared
              prepare_delete
              prepare_delete_cleanup
              delete_prepared = true
            end
            audit_event(event)
          end
        end
      end
    end

    def should_watch_table?(table)
      Waldit.watched_tables.call(table)
    end

    def valid_context_prefix?(prefix)
      prefix == Waldit.context_prefix
    end

    def ignored_columns(table)
      Waldit.ignored_columns.call(table)
    end

    def clean_attributes(table, attributes)
      attributes.without(ignored_columns(table))
    end

    def max_transaction_size
      Waldit.max_transaction_size
    end

    def record
      Waldit.model
    end

    private

    def prepare_insert
      @connection.prepare("waldit_insert", <<~SQL)
        INSERT INTO #{record.table_name} (transaction_id, lsn, table_name, primary_key, action, context, new)
        VALUES ($1, $2, $3, $4, 'insert'::waldit_action, $5, $6)
        ON CONFLICT (table_name, primary_key, transaction_id)
        DO UPDATE SET new = #{record.table_name}.new
      SQL
    end

    def prepare_update
      @connection.prepare("waldit_update", <<~SQL)
        INSERT INTO #{record.table_name} (transaction_id, lsn, table_name, primary_key, action, context, old, new)
        VALUES ($1, $2, $3, $4, 'update'::waldit_action, $5, $6, $7)
        ON CONFLICT (table_name, primary_key, transaction_id)
        DO UPDATE SET new = excluded.new
      SQL
    end

    def prepare_delete
      @connection.prepare("waldit_delete", <<~SQL)
        INSERT INTO #{record.table_name} (transaction_id, lsn, table_name, primary_key, action, context, old)
        VALUES ($1, $2, $3, $4, 'delete'::waldit_action, $5, $6)
        ON CONFLICT (table_name, primary_key, transaction_id)
        DO UPDATE SET old = #{record.table_name}.old
      SQL
    end

    def prepare_delete_cleanup
      @connection.prepare("waldit_delete_cleanup", <<~SQL)
        DELETE FROM #{record.table_name}
        WHERE
          transaction_id = $1
          AND table_name = $2
          AND primary_key = $3
          AND action IN ('insert'::waldit_action, 'update'::waldit_action)
        RETURNING action, old
      SQL
    end
  end
end
