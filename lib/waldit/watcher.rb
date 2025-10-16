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

    def initialize(*)
      super
      initialize_connection
      @retry = false
    end

    def on_transaction_events(events)
      @connection.transaction do
        tables = Set.new

        events.each do |event|
          case event
          when CommitTransactionEvent
            changes = [:old, :new, :diff]
              .map { |diff| [diff, tables.filter { |table| Waldit.store_changes.call(table).include? diff }] }
              .to_h

            log_new = (changes[:new] || []).map { |table| "#{table}" }
            log_old = (changes[:old] || []).map { |table| "#{table}" }
            log_diff = (changes[:diff] || []).map { |table| "#{table}" }

            @connection.exec_prepared("waldit_finish", [
              event.transaction_id,
              event.timestamp,
              "{#{log_new.join(",")}}",
              "{#{log_old.join(",")}}",
              "{#{log_diff.join(",")}}",
            ])

            @connection.exec_prepared("waldit_cleanup", [
              event.transaction_id,
              "{#{(log_new + log_old).join(",")}}",
              "{#{log_diff.join(",")}}",
            ])

            # We sucessful retried a connection, let's reset our retry state
            @retry = false

          when InsertEvent
            tables << event.table
            audit_event(event)

          when UpdateEvent
            tables << event.table
            audit_event(event)

          when DeleteEvent
            tables << event.table
            audit_event(event)
          end
        end
      end
    rescue PG::ConnectionBad
      raise if @retry
      # Let's try to fetch a new connection and reprocess the transaction
      initialize_connection
      @retry = true
      retry
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

    def record
      Waldit.model
    end

    private

    def initialize_connection
      @connection = record.connection_pool.checkout.raw_connection
      prepare_insert
      prepare_update
      prepare_delete
      prepare_delete_cleanup
      prepare_finish
      prepare_cleanup
    end

    def prepare_insert
      @connection.prepare("waldit_insert", <<~SQL)
        INSERT INTO #{record.table_name} (transaction_id, lsn, table_name, primary_key, action, context, new)
        VALUES ($1, $2, $3, $4, 'insert'::waldit_action, $5, $6)
        ON CONFLICT (table_name, primary_key, transaction_id)
        DO UPDATE SET new = #{record.table_name}.new
      SQL
    rescue PG::DuplicatePstatement
    end

    def prepare_update
      @connection.prepare("waldit_update", <<~SQL)
        INSERT INTO #{record.table_name} (transaction_id, lsn, table_name, primary_key, action, context, old, new)
        VALUES ($1, $2, $3, $4, 'update'::waldit_action, $5, $6, $7)
        ON CONFLICT (table_name, primary_key, transaction_id)
        DO UPDATE SET new = excluded.new
      SQL
    rescue PG::DuplicatePstatement
    end

    def prepare_delete
      @connection.prepare("waldit_delete", <<~SQL)
        INSERT INTO #{record.table_name} (transaction_id, lsn, table_name, primary_key, action, context, old)
        VALUES ($1, $2, $3, $4, 'delete'::waldit_action, $5, $6)
        ON CONFLICT (table_name, primary_key, transaction_id)
        DO UPDATE SET old = #{record.table_name}.old
      SQL
    rescue PG::DuplicatePstatement
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
    rescue PG::DuplicatePstatement
    end

    def prepare_finish
      @connection.prepare("waldit_finish", <<~SQL)
        UPDATE #{record.table_name}
        SET
          committed_at = $2,
          new = CASE WHEN action = 'insert' OR table_name = ANY ($3::varchar[]) THEN new ELSE null END,
          old = CASE WHEN action = 'delete' OR table_name = ANY ($4::varchar[]) THEN old ELSE null END,
          diff =
            CASE WHEN action = 'update' AND table_name = ANY ($5::varchar[]) THEN (
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
        WHERE transaction_id = $1
      SQL
    rescue PG::DuplicatePstatement
    end

    def prepare_cleanup
      @connection.prepare("waldit_cleanup", <<~SQL)
        DELETE FROM #{record.table_name}
        WHERE
          transaction_id = $1
          AND action = 'update'::waldit_action
          AND (
            (diff IS NULL AND table_name = ANY ($3::varchar[]))
            OR
            (new = old AND table_name = ANY ($2::varchar[]))
          )
      SQL
    rescue PG::DuplicatePstatement
    end
  end
end
