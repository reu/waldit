# frozen_string_literal: true

require "rails/railtie"

module Waldit
  class Railtie < Rails::Railtie
    config.before_configuration do
      ActiveRecord::ConnectionAdapters.register(
        "postgresqlwaldit",
        "Waldit::PostgreSQLAdapter",
        "waldit/postgresql_adapter",
      )
    end
  end
end
