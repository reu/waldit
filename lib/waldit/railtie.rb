# frozen_string_literal: true

require "rails/railtie"

module Waldit
  class Railtie < Rails::Railtie
    config.before_configuration do
      ["waldit", "postgresqlwaldit"].each do |adapter_name|
        ActiveRecord::ConnectionAdapters.register(
          adapter_name,
          "Waldit::PostgreSQLAdapter",
          "waldit/postgresql_adapter",
        )
      end
    end
  end
end
