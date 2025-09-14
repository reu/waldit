# typed: strong
module Waldit
  extend T::Sig
  extend Waldit::Context
  VERSION = "0.0.18"

  class << self
    sig { returns(String) }
    attr_accessor :context_prefix

    sig { returns(T.proc.params(table: String).returns(T::Boolean)) }
    attr_reader :watched_tables

    sig { returns(T.proc.params(table: String).returns(T::Array[Symbol])) }
    attr_reader :store_changes

    sig { returns(T.proc.params(table: String).returns(T::Array[String])) }
    attr_accessor :ignored_columns

    sig { returns(T.class_of(ActiveRecord::Base)) }
    attr_accessor :model
  end

  sig { params(tables: T.any(T::Array[String], T.proc.params(table: String).returns(T::Boolean))).void }
  def self.watched_tables=(tables); end

  sig { params(changes: T.any(Symbol, T::Array[Symbol], T.proc.params(table: String).returns(T::Array[Symbol]))).void }
  def self.store_changes=(changes); end

  sig { params(block: T.proc.params(config: T.class_of(Waldit)).void).void }
  def self.configure(&block); end

  module Context
    extend T::Sig
    Context = T.type_alias { T::Hash[T.any(String, Symbol), T.untyped] }

    sig { type_parameters(:U).params(context: Context, block: T.proc.returns(T.type_parameter(:U))).returns(T.type_parameter(:U)) }
    def with_context(context, &block); end

    sig { returns(T.nilable(Context)) }
    def context; end

    sig { params(added_context: Context).void }
    def add_context(added_context); end

    sig { params(context: Context).void }
    def new_context(context = {}); end
  end

  class Railtie < Rails::Railtie
  end

  module Record
    abstract!

    extend T::Sig
    extend T::Helpers

    sig { abstract.returns(T::Hash[T.any(String, Symbol), T.untyped]) }
    def new; end

    sig { abstract.returns(T::Hash[T.any(String, Symbol), T.untyped]) }
    def old; end

    sig { returns(T::Hash[T.any(String, Symbol), [T.untyped, T.untyped]]) }
    def diff; end
  end

  module Sidekiq
    class SaveContext
      include ::Sidekiq::ClientMiddleware

      sig do
        params(
          job_class: T.untyped,
          job: T.untyped,
          queue: T.untyped,
          redis: T.untyped
        ).returns(T.untyped)
      end
      def call(job_class, job, queue, redis); end
    end

    class LoadContext
      include ::Sidekiq::ServerMiddleware

      sig do
        params(
          job_instance: T.untyped,
          job: T.untyped,
          queue: T.untyped,
          block: T.untyped
        ).returns(T.untyped)
      end
      def call(job_instance, job, queue, &block); end

      sig { params(job: T.untyped).returns(T.untyped) }
      def deserialize_context(job); end
    end
  end

  class Watcher < Wal::StreamingWatcher
    extend T::Sig

    sig { params(event: T.any(InsertEvent, UpdateEvent, DeleteEvent)).void }
    def audit_event(event); end

    sig { override.params(events: T::Enumerator[Event]).void }
    def on_transaction_events(events); end

    sig { params(table: String).returns(T::Boolean) }
    def should_watch_table?(table); end

    sig { params(prefix: String).returns(T::Boolean) }
    def valid_context_prefix?(prefix); end

    sig { params(table: String).returns(T::Array[String]) }
    def ignored_columns(table); end

    sig { returns(T.class_of(ActiveRecord::Base)) }
    def record; end
  end
end
