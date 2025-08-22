# frozen_string_literal: true

module Waldit
  module Migration
    def create_waldit_table(name = "waldit", &block)
      reversible do |dir|
        dir.up { execute "CREATE TYPE waldit_action AS ENUM ('insert', 'update', 'delete')" }
        dir.down { execute "DROP TYPE waldit_action" }
      end

      create_table :waldit do |t|
        t.column :action, :waldit_action, null: false
        t.string :table_name, null: false
        t.string :primary_key
        t.bigint :transaction_id, null: false
        t.decimal :lsn, null: false, precision: 20, scale: 0
        t.timestamptz :commited_at
        t.jsonb :context, null: false, default: {}
        t.jsonb :old, null: true
        t.jsonb :new, null: true
        t.jsonb :diff, null: true
        block.call(t)
      end

      add_index :waldit, [:table_name, :primary_key, :transaction_id], unique: true
      add_index :waldit, [:transaction_id, :lsn]
      add_index :waldit, :commited_at
      add_index :waldit, :context, using: :gin, opclass: :jsonb_path_ops
    end

    def create_waldit_publication
      reversible do |dir|
        dir.up { execute "CREATE PUBLICATION waldit" }
        dir.down { execute "DROP PUBLICATION waldit" }
      end
    end

    def add_table_to_waldit(table)
      reversible do |dir|
        dir.up do
          execute "ALTER TABLE #{table} REPLICA IDENTITY FULL"
          execute "ALTER PUBLICATION waldit ADD TABLE #{table}"
        end
        dir.down do
          execute "ALTER PUBLICATION waldit DROP TABLE #{table}"
          execute "ALTER TABLE #{table} REPLICA IDENTITY DEFAULT"
        end
      end
    end

    def remove_table_from_waldit(table)
      reversible do |dir|
        dir.up do
          execute "ALTER PUBLICATION waldit DROP TABLE #{table}"
          execute "ALTER TABLE #{table} REPLICA IDENTITY DEFAULT"
        end
        dir.down do
          execute "ALTER TABLE #{table} REPLICA IDENTITY FULL"
          execute "ALTER PUBLICATION waldit ADD TABLE #{table}"
        end
      end
    end
  end
end
