# Waldit

Waldit is a Postgres-based audit trail for Rails.

It hooks into [Postgres logical replication](https://www.postgresql.org/docs/current/logical-replication.html) via the [`wal`](https://github.com/reu/wal) gem to capture every `insert`, `update`, and `delete` directly from the WAL. Unlike ActiveRecord callbacks, these events are guaranteed by Postgres to be 100% consistent -- even changes that bypass Rails entirely are captured.

## Getting started

### Installation

Add `waldit` to your application's Gemfile:

```ruby
gem "waldit"
```

### Database adapter

Waldit ships a custom database adapter that injects audit context into your transactions. Update your `config/database.yml`:

```yaml
default: &default
  adapter: waldit
  # ... rest of your config
```

### Migrations

Waldit provides migration helpers. First, create the audit table and publication:

```ruby
class SetupWaldit < ActiveRecord::Migration[7.0]
  def change
    create_waldit_table
    create_waldit_publication
  end
end
```

Then, for each table you want to audit:

```ruby
class AuditUsers < ActiveRecord::Migration[7.0]
  def change
    add_table_to_waldit :users
  end
end
```

This sets `REPLICA IDENTITY FULL` on the table and adds it to the Waldit publication.

### Running the watcher

Create a `config/waldit.yml`:

```yaml
slots:
  audit:
    publications: [waldit_publication]
    watcher: Waldit::Watcher
```

Then start the process:

```bash
bundle exec wal start config/waldit.yml
```

That's it. Every change to your audited tables is now being recorded.

## Adding context

Wrap your operations with `Waldit.with_context` to record who made the change and why:

```ruby
Waldit.with_context(user_id: current_user.id, reason: "Profile update") do
  user.update(name: "New Name")
end
```

Context can be nested and updated mid-transaction:

```ruby
Waldit.with_context(user_id: current_user.id) do
  user.update(name: "New Name")

  Waldit.with_context(via: "admin_panel") do
    account.update(plan: "premium")  # context: { user_id: 1, via: "admin_panel" }
  end

  Waldit.add_context(batch: true)
  other_user.update(name: "Other")  # context: { user_id: 1, batch: true }
end
```

### Sidekiq integration

Waldit can propagate context into background jobs:

```ruby
# config/initializers/sidekiq.rb
Sidekiq.configure_client do |config|
  config.client_middleware do |chain|
    chain.add Waldit::Sidekiq::SaveContext
  end
end

Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add Waldit::Sidekiq::LoadContext
  end
end
```

## Querying the audit trail

Waldit provides scopes on the audit model:

```ruby
# All audit records for a specific record
Waldit.model.for(user)

# All audit records for a table
Waldit.model.from_model(User)

# All audit records with a specific context
Waldit.model.with_context(user_id: 1)
```

Each audit record exposes:

```ruby
audit = Waldit.model.for(user).last

audit.action       # "insert", "update", or "delete"
audit.old          # previous attributes (updates and deletes)
audit.new          # new attributes (inserts and updates)
audit.diff         # changed attributes as { "name" => ["old", "new"] }
audit.context      # the context hash
audit.committed_at # when the transaction was committed
audit.primary_key  # the record's primary key
```

The `old`, `new`, and `diff` accessors are smart -- if you only store `:diff`, calling `.old` or `.new` will compute the values from the diff, and vice versa.

## Configuration

```ruby
# config/initializers/waldit.rb
Waldit.configure do |config|
  # Which tables to watch (default: all except "waldit")
  config.watched_tables = -> table { table != "waldit" }

  # Columns to exclude from audit records (default: created_at, updated_at)
  config.ignored_columns = -> table { %w[created_at updated_at] }

  # What to store per table (default: [:old, :new])
  # Options: :old, :new, :diff (any combination)
  config.store_changes = [:old, :new]

  # WAL byte threshold for switching to streaming mode (default: 10MB)
  # Transactions smaller than this are processed in memory for better performance
  config.large_transaction_threshold = 10_000_000
end
```

### Storage policies

By default, Waldit stores both `old` and `new` attributes for every change. You can reduce storage by only keeping what you need:

```ruby
# Only store diffs for updates (most compact)
config.store_changes = :diff

# Per-table policies
config.store_changes = -> table {
  case table
  when "events" then [:new]
  when "logs"   then [:diff]
  else               [:old, :new]
  end
}
```

### Per-table ignored columns

```ruby
config.ignored_columns = -> table {
  case table
  when "users" then %w[created_at updated_at last_sign_in_at]
  else              %w[created_at updated_at]
  end
}
```

### Custom audit model

You can provide your own model class if you need custom methods or a different table name:

```ruby
class AuditRecord < ApplicationRecord
  include Waldit::Record
  self.table_name = "waldit"
end

Waldit.configure do |config|
  config.model = AuditRecord
end
```

## How it works

Waldit uses Postgres logical replication to stream changes from the WAL (Write-Ahead Log). The flow is:

1. The custom database adapter sets a `waldit_context` session variable before each write operation
2. Postgres captures the change and the context in the WAL
3. `Waldit::Watcher` receives the events via a replication slot
4. Events are deduplicated per-transaction (multiple updates to the same record produce a single audit entry)
5. The final audit records are persisted to the `waldit` table

For small transactions, events are accumulated in memory and persisted in a single batch insert. For large transactions (configurable via `large_transaction_threshold`), events are streamed and persisted individually to avoid memory pressure.

### Transaction-level deduplication

Within a single database transaction, Waldit collapses events intelligently:

- **Insert then update** -- recorded as a single `insert` with the final state
- **Multiple updates** -- recorded as a single `update` with the original `old` and final `new`
- **Insert then delete** -- not recorded (the record never existed outside the transaction)
- **Update then delete** -- recorded as a `delete` with the original `old` values
- **Update that reverts to original** -- not recorded (no net change)
