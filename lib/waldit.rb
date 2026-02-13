# frozen_string_literal: true

require_relative "waldit/version"
require_relative "waldit/context"
require_relative "waldit/railtie"
require_relative "waldit/record"
require_relative "waldit/watcher"

module Waldit
  extend Waldit::Context

  class << self
    attr_reader :watched_tables

    def watched_tables=(tables)
      case tables
      when Array
        @watched_tables = -> table { tables.include? table }
      else
        @watched_tables = tables
      end
    end

    attr_reader :store_changes

    def store_changes=(changes)
      case changes
      when Symbol
        changes = [changes].to_set
        @store_changes = -> table { changes }
      when Array
        changes = changes.map(&:to_sym).to_set
        @store_changes = -> table { changes }
      else
        @store_changes = changes
      end
    end

    attr_accessor :ignored_columns
    attr_accessor :model
    attr_accessor :context_prefix
    attr_accessor :large_transaction_threshold
  end

  def self.configure(&block)
    yield self
  end

  configure do |config|
    config.context_prefix = "waldit_context"

    config.watched_tables = -> table { table != "waldit" }

    config.store_changes = -> table { %i[old new] }

    config.ignored_columns = -> table { %w[created_at updated_at] }

    config.large_transaction_threshold = 10_000_000

    config.model = Class.new(ActiveRecord::Base) do
      include Waldit::Record
      self.table_name = "waldit"
    end
  end
end
