# frozen_string_literal: true
# typed: false

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
