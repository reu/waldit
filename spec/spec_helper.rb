require "rspec/sorbet"
require "testcontainers/postgres"
require "debug"
require "waldit"

RSpec.configure do |config|
  config.expect_with :minitest

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  config.add_setting :postgres_container, default: nil
  config.add_setting :pg_config, default: nil

  config.before(:suite) do
    pg_container = config.postgres_container = Testcontainers::PostgresContainer
      .new
      .with_command(["-cwal_level=logical", "-cmax_wal_senders=500", "-cmax_replication_slots=500"])
      .start

    pg_config = config.pg_config = {
      database: pg_container.username,
      host: pg_container.host,
      username: pg_container.username,
      password: pg_container.password,
      port: pg_container.first_mapped_port,
    }

    ActiveRecord::ConnectionAdapters.register(
      "postgresqlwaldit",
      "Waldit::PostgreSQLAdapter",
      "waldit/postgresql_adapter",
    )

    ActiveRecord::Base.establish_connection(**pg_config.merge(adapter: "postgresqlwaldit"))
    ActiveRecord::Schema.define do
      execute "CREATE TYPE waldit_action AS ENUM ('insert', 'update', 'delete')"

      create_table :waldit do |t|
        t.column :action, :waldit_action, null: false
        t.string :table_name, null: false
        t.bigint :primary_key
        t.bigint :transaction_id, null: false
        t.decimal :lsn, null: false, precision: 20, scale: 0
        t.timestamptz :commited_at
        t.jsonb :old, null: false, default: {}
        t.jsonb :new, null: false, default: {}
        t.jsonb :context, null: false, default: {}
      end

      add_index :waldit, [:table_name, :primary_key, :transaction_id], unique: true
      add_index :waldit, [:transaction_id, :lsn]
      add_index :waldit, :commited_at

      create_table :records, force: true do |t|
        t.string :name
      end

      execute "ALTER TABLE records REPLICA IDENTITY FULL"
      execute "CREATE PUBLICATION waldit FOR TABLE records"
    end

    class Record < ActiveRecord::Base
      self.table_name = "records"
    end
  end

  config.after(:suite) do
    config.postgres_container&.stop
    config.postgres_container&.remove
  end

  module ReplicationHelpers
    def create_testing_wal_replication(watcher, db_config: nil)
      Wal::Replicator
        .new(
          replication_slot: "waldit_test_#{SecureRandom.alphanumeric(8)}",
          use_temporary_slot: true,
          db_config: db_config || RSpec.configuration.pg_config,
        )
        .replicate(watcher, publications: ["waldit"])
    end

    def replicate_single_transaction(replication_stream)
      Enumerator::Lazy
        .new(replication_stream) do |yielder, event|
          yielder.yield(event)
          raise StopIteration if event.is_a? Wal::CommitTransactionEvent
        end
        .force
    end
  end

  config.include ReplicationHelpers
end
