# frozen_string_literal: true

require "wal"

module Waldit
  class Watcher < Wal::StreamingWatcher
    include Wal

    def initialize(*)
      super
      initialize_connection
      @retry = false
    end

    def on_transaction_events(events)
      events.each do |event|
        case event
        when BeginTransactionEvent
          if event.estimated_size < Waldit.large_transaction_threshold
            process_in_memory(event, events)
          else
            process_streaming(event, events)
          end
          return
        end
      end
    rescue PG::ConnectionBad
      raise if @retry
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
      (@ignored_columns_cache ||= {})[table] ||= Waldit.ignored_columns.call(table)
    end

    def store_changes(table)
      (@store_changes_cache ||= {})[table] ||= Waldit.store_changes.call(table)
    end

    def clean_attributes(table, attributes)
      attributes.without(ignored_columns(table))
    end

    def record
      Waldit.model
    end

    private

    def process_in_memory(begin_event, events)
      records = {}

      events.each do |event|
        case event
        when InsertEvent
          next unless event.primary_key
          key = [event.full_table_name, event.primary_key.to_json]
          records[key] = event

        when UpdateEvent
          next unless event.primary_key
          next if event.diff.without(ignored_columns(event.table)).empty?
          key = [event.full_table_name, event.primary_key.to_json]
          records[key] = case (existing_event = records[key])
          when InsertEvent
            # A record inserted on this transaction is being updated, which means it should still reflect as a insert
            # event, we just change the information to reflect the most current data that was just updated.
            existing_event.with(new: event.new)
          when UpdateEvent
            # We are updating again a event that was already updated on this transaction.
            # Same as the insert, we keep the old data from the previous update and the new data from the new one.
            existing_event.with(new: event.new)
          else
            event
          end

        when DeleteEvent
          next unless event.primary_key
          key = [event.full_table_name, event.primary_key.to_json]
          records[key] = case (existing_event = records[key])
          when InsertEvent
            # We are removing a record that was inserted on this transaction, we should not even report this change, as
            # this record never existed outside this transaction anyways.
            nil
          when UpdateEvent
            # Deleting a record that was previously updated by this transaction. Just store the previous data while
            # keeping the record as deleted.
            event.with(old: existing_event.old)
          else
            event
          end

        when CommitTransactionEvent
          rows = records.compact.values.filter_map do |evt|
            table = evt.full_table_name
            store = store_changes(table)

            rec = {
              committed_at: event.timestamp,
              transaction_id: event.transaction_id,
              lsn: evt.lsn,
              table_name: table,
              primary_key: evt.primary_key.to_json,
              context: evt.context,
            }

            case evt
            when InsertEvent
              { **rec, action: "insert", new: clean_attributes(table, evt.new) }
            when UpdateEvent
              rec = {
                **rec,
                action: "update",
                old: evt.old&.then { |attrs| clean_attributes(table, attrs) } || {},
                new: evt.new&.then { |attrs| clean_attributes(table, attrs) } || {},
              }
              next if rec[:old] == rec[:new]
              rec[:old] = nil unless store.include? :old
              rec[:new] = nil unless store.include? :new
              rec[:diff] = clean_attributes(table, evt.diff) if store.include? :diff
              rec
            when DeleteEvent
              { **rec, action: "delete", old: clean_attributes(table, evt.old) }
            end
          end
          persist_batch(rows) unless rows.empty?
          @retry = false
        end
      end
    end

    def persist_batch(records)
      return if records.empty?

      cols = %w[
        transaction_id
        lsn
        table_name
        primary_key
        action
        context
        committed_at
        old
        new
        diff
      ]

      rows = records.each_with_index.map do |_, i|
        o = i * cols.size
        row = [
          "$#{o + 1}",
          "$#{o + 2}",
          "$#{o + 3}",
          "$#{o + 4}",
          "$#{o + 5}::waldit_action",
          "$#{o + 6}::jsonb",
          "$#{o + 7}",
          "$#{o + 8}::jsonb",
          "$#{o + 9}::jsonb",
          "$#{o + 10}::jsonb",
        ].join(",")
        "(#{row})"
      end

      params = records.flat_map do |r|
        [
          r[:transaction_id],
          r[:lsn],
          r[:table_name],
          r[:primary_key],
          r[:action],
          r[:context]&.to_json,
          r[:committed_at],
          r[:old]&.to_json,
          r[:new]&.to_json,
          r[:diff]&.to_json,
        ]
      end

      @connection.exec_params(<<~SQL, params)
        INSERT INTO #{record.table_name} (#{cols.join(",")})
        VALUES #{rows.join(",")}
        ON CONFLICT (table_name, primary_key, transaction_id)
        DO NOTHING
      SQL
    end

    def process_streaming(begin_event, events)
      ensure_streaming_statements_prepared

      @connection.transaction do
        tables = Set.new

        events.each do |event|
          case event
          when CommitTransactionEvent
            unless tables.empty?
              changes = [:old, :new, :diff]
                .map { |diff| [diff, tables.filter { |table| store_changes(table).include? diff }] }
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
            end

            @retry = false

          when InsertEvent
            tables << event.table if audit_event(event)

          when UpdateEvent
            tables << event.table if audit_event(event)

          when DeleteEvent
            tables << event.table if audit_event(event)
          end
        end
      end
    end

    def audit_event(event)
      return unless event.primary_key
      primary_key = event.primary_key.to_json

      audit = [event.transaction_id, event.lsn, event.table, primary_key, event.context.to_json]

      case event
      when InsertEvent
        new_attributes = clean_attributes(event.table, event.new)
        @connection.exec_prepared("waldit_insert", audit + [new_attributes.to_json])
        true

      when UpdateEvent
        return if event.diff.without(ignored_columns(event.table)).empty?
        old_attributes = clean_attributes(event.table, event.old)
        new_attributes = clean_attributes(event.table, event.new)

        @connection.exec_prepared("waldit_update", audit + [old_attributes.to_json, new_attributes.to_json])
        true

      when DeleteEvent
        case @connection.exec_prepared("waldit_delete_cleanup", [event.transaction_id, event.table, primary_key]).values
        in [["update", previous_old]]
          @connection.exec_prepared("waldit_delete", audit + [previous_old])
        in []
          @connection.exec_prepared("waldit_delete", audit + [clean_attributes(event.table, event.old).to_json])
        else
          # Don't need to audit anything on this case
        end
        true
      end
    end

    def initialize_connection
      @connection = record.connection_pool.checkout.raw_connection
      @streaming_statements_prepared = false
    end

    def ensure_streaming_statements_prepared
      return if @streaming_statements_prepared

      prepare_insert
      prepare_update
      prepare_delete
      prepare_delete_cleanup
      prepare_finish
      prepare_cleanup
      @streaming_statements_prepared = true
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
