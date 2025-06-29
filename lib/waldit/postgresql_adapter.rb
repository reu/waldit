# frozen_string_literal: true
# typed: ignore

require "active_record/connection_adapters/postgresql_adapter"

module Waldit
  class PostgreSQLAdapter < ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
    READ_QUERY_REGEXP = build_read_query_regexp(%i[close declare fetch move set show])

    def raw_execute(sql, ...)
      return super if READ_QUERY_REGEXP.match? sql
      return super if @current_waldit_context == Waldit.context.hash

      if transaction_open?
        set_waldit_context!
        super

      elsif Waldit.context
        # We are trying to execute a query with waldit context while not in a transaction, so we start one
        transaction do
          set_waldit_context!
          super
        end

      else
        super
      end
    end

    def begin_db_transaction(...)
      @current_waldit_context = nil.hash
      super
    end

    def begin_isolated_db_transaction(...)
      @current_waldit_context = nil.hash
      super
    end

    def commit_db_transaction
      @current_waldit_context = nil.hash
      super
    end

    private

    def set_waldit_context!
      context = Waldit.context
      prefix = Waldit.context_prefix
      context_hash = context.hash
      set_wal_watcher_context(context, prefix:) if context_hash != @current_waldit_context
      @current_waldit_context = context_hash
    end
  end
end
