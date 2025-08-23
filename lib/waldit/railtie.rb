# frozen_string_literal: true

require "rails/railtie"

module Waldit
  class Railtie < Rails::Railtie
    config.before_configuration do
      ActiveRecord::ConnectionAdapters.register(
        "waldit",
        "Waldit::PostgreSQLAdapter",
        "waldit/postgresql_adapter",
      )

      ActiveRecord::Tasks::DatabaseTasks.register_task(
        "waldit",
        "ActiveRecord::Tasks::PostgreSQLDatabaseTasks",
      )

      require_relative "migration"
      ActiveRecord::Migration.include Waldit::Migration
      ActiveRecord::Schema.include Waldit::Migration
    end
  end
end
