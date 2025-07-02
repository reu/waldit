# Waldit

[![Gem Version](https://badge.fury.io/rb/waldit.svg)](https://badge.fury.io/rb/waldit)

Waldit is a Ruby gem that provides a simple and extensible way to audit changes to your ActiveRecord models. It leverages PostgreSQL's logical replication capabilities to capture changes directly from your database with 100% consistency.

## Features

- **Automatic Auditing:** Automatically track `create`, `update`, and `delete` operations on your models.
- **Contextual Auditing:** Add custom context to your audit records to understand who made the change and why.
- **Flexible Configuration:** Configure which tables and columns to watch, and how to store audit information.
- **High Performance:** Built on top of [`wal`](https://github.com/reu/wal), which uses PostgreSQL's logical replication for minimal overhead.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "waldit"
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install waldit

## Usage

1.  **Configure your database adapter:**

    First step is to configure in your `config/database.yml` and change your adapter to `postgresqlwaldit`, which is a special adapter that allows injecting `waldit` contextual information on your transactions:

    ```yaml
    default: &default
      adapter: postgresqlwaldit
      # ...
    ```

2.  **Create an audit table:**

    Generate a migration to create the `waldit` table:

    ```bash
    rails generate migration create_waldit
    ```

    And then add the following to your migration file:

    ```ruby
    class CreateWalditTable < ActiveRecord::Migration[7.0]
      def change
        create_table :waldit do |t|
          t.bigint :transaction_id, null: false
          t.bigint :lsn, null: false
          t.string :action, null: false
          t.jsonb :context, default: {}
          t.string :table_name, null: false
          t.string :primary_key, null: false
          t.jsonb :old, default: {}
          t.jsonb :new, default: {}
          t.timestamp :commited_at

          t.index [:table_name, :primary_key, :transaction_id], unique: true
        end
      end
    end
    ```

3.  **Configure Waldit:**

    Create an initializer file at `config/initializers/waldit.rb`:

    ```ruby
    Waldit.configure do |config|
      # A callback that returns true if a table should be watched.
      config.watched_tables = ->(table) { table != "waldit" }

      # A callback that returns an array of columns to ignore for a given table.
      config.ignored_columns = ->(table) { %w[created_at updated_at] }
    end
    ```

4.  **Add context to your changes:**

    Use the `with_context` method to add context to your database operations:

    ```ruby
    Waldit.with_context(user_id: 1, reason: "User updated their profile") do
      user.update(name: "New Name")
    end
    ```

5.  **Start the watcher:**

    To process the events, you need to start a WAL watcher. The recommended way is to have a config/waldit.yml

    ```yml
    slots:
      audit:
        publications: [waldit_publication]
        watcher: Waldit::Watcher
    ```

    And then run:

    ```bash
    bundle exec wal start config/waldit.yml
    ```

## How it Works

Waldit uses a custom PostgreSQL adapter to set the `waldit_context` session variable before each transaction. This context is then captured by the logical replication slot and stored in the `waldit` table by the `Waldit::Watcher`.

The `Waldit::Watcher` is a streaming watcher that listens for changes in the logical replication slot and creates audit records in the `waldit` table. It processes events in batches to minimize the number of database transactions.
