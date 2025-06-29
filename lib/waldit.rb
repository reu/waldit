# frozen_string_literal: true
# typed: true

require_relative "waldit/version"
require_relative "waldit/context"
require_relative "waldit/railtie"
require_relative "waldit/record"
require_relative "waldit/watcher"

module Waldit
  extend T::Sig
  extend Waldit::Context

  class << self
    extend T::Sig

    sig { returns(String) }
    attr_accessor :context_prefix

    sig { returns(T.proc.params(table: String).returns(T::Boolean)) }
    attr_reader :watched_tables

    sig { params(tables: T.any(T::Array[String], T.proc.params(table: String).returns(T::Boolean))).void }
    def watched_tables=(tables)
      case tables
      when Array
        @watched_tables = -> table { tables.include? table }
      else
        @watched_tables = tables
      end
    end

    sig { returns(T.proc.params(table: String).returns(T::Array[String])) }
    attr_accessor :ignored_columns

    sig { returns(Integer) }
    attr_accessor :max_transaction_size

    sig { returns(T.class_of(ActiveRecord::Base)) }
    attr_accessor :model
  end

  sig { params(block: T.proc.params(config: T.class_of(Waldit)).void).void }
  def self.configure(&block)
    yield self
  end

  configure do |config|
    config.context_prefix = "waldit_context"

    config.watched_tables = -> table { table != "waldit" }

    config.ignored_columns = -> table { %w[created_at updated_at] }

    config.max_transaction_size = 10_000

    config.model = Class.new(ActiveRecord::Base) do
      include Waldit::Record
      self.table_name = "waldit"
    end
  end
end
