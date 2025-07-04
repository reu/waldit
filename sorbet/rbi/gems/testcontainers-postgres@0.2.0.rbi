# typed: true

# DO NOT EDIT MANUALLY
# This is an autogenerated file for types exported from the `testcontainers-postgres` gem.
# Please instead update this file by running `bin/tapioca gem testcontainers-postgres`.


# source://testcontainers-postgres//lib/testcontainers/postgres/version.rb#3
module Testcontainers
  class << self
    # source://testcontainers-core/0.2.0/lib/testcontainers.rb#30
    def logger; end

    # source://testcontainers-core/0.2.0/lib/testcontainers.rb#28
    def logger=(_arg0); end
  end
end

# source://testcontainers-postgres//lib/testcontainers/postgres/version.rb#4
module Testcontainers::Postgres; end

# source://testcontainers-postgres//lib/testcontainers/postgres/version.rb#5
Testcontainers::Postgres::VERSION = T.let(T.unsafe(nil), String)

# PostgresContainer class is used to manage containers that runs a PostgresQL database
#
# @attr_reader username [String] used by the container
# @attr_reader password [String] used by the container
# @attr_reader database [String] used by the container
#
# source://testcontainers-postgres//lib/testcontainers/postgres.rb#11
class Testcontainers::PostgresContainer < ::Testcontainers::DockerContainer
  # Initializes a new instance of PostgresContainer
  #
  # @param image [String] the image to use
  # @param username [String] the username to use
  # @param password [String] the password to use
  # @param database [String] the database to use
  # @param port [String] the port to use
  # @param kwargs [Hash] the options to pass to the container. See {DockerContainer#initialize}
  # @return [PostgresContainer] a new instance of PostgresContainer
  #
  # source://testcontainers-postgres//lib/testcontainers/postgres.rb#33
  def initialize(image = T.unsafe(nil), username: T.unsafe(nil), password: T.unsafe(nil), database: T.unsafe(nil), port: T.unsafe(nil), **kwargs); end

  # used by the container
  #
  # @return [String] the current value of database
  #
  # source://testcontainers-postgres//lib/testcontainers/postgres.rb#22
  def database; end

  # Returns the database url (e.g. postgres://user:password@host:port/database)
  #
  # @param protocol [String] the protocol to use in the string (default: "postgres")
  # @param database [String] the database to use in the string (default: @database)
  # @param options [Hash] the options to use in the query string (default: {})
  # @raise [ConnectionError] If the connection to the Docker daemon fails.
  # @raise [ContainerNotStartedError] If the container has not been started.
  # @return [String] the database url
  #
  # source://testcontainers-postgres//lib/testcontainers/postgres.rb#66
  def database_url(protocol: T.unsafe(nil), username: T.unsafe(nil), password: T.unsafe(nil), database: T.unsafe(nil), options: T.unsafe(nil)); end

  # used by the container
  #
  # @return [String] the current value of password
  #
  # source://testcontainers-postgres//lib/testcontainers/postgres.rb#22
  def password; end

  # Returns the port used by the container
  #
  # @return [Integer] the port used by the container
  #
  # source://testcontainers-postgres//lib/testcontainers/postgres.rb#54
  def port; end

  # Starts the container
  #
  # @return [PostgresContainer] self
  #
  # source://testcontainers-postgres//lib/testcontainers/postgres.rb#45
  def start; end

  # used by the container
  #
  # @return [String] the current value of username
  #
  # source://testcontainers-postgres//lib/testcontainers/postgres.rb#22
  def username; end

  # Sets the database to use
  #
  # @param database [String] the database to use
  # @return [PostgresContainer] self
  #
  # source://testcontainers-postgres//lib/testcontainers/postgres.rb#79
  def with_database(database); end

  # Sets the password to use
  #
  # @param password [String] the password to use
  # @return [PostgresContainer] self
  #
  # source://testcontainers-postgres//lib/testcontainers/postgres.rb#97
  def with_password(password); end

  # Sets the username to use
  #
  # @param username [String] the username to use
  # @return [PostgresContainer] self
  #
  # source://testcontainers-postgres//lib/testcontainers/postgres.rb#88
  def with_username(username); end

  private

  # @raise [ContainerLaunchException]
  #
  # source://testcontainers-postgres//lib/testcontainers/postgres.rb#104
  def _configure; end

  # source://testcontainers-postgres//lib/testcontainers/postgres.rb#114
  def _default_healthcheck_options; end
end

# source://testcontainers-postgres//lib/testcontainers/postgres.rb#20
Testcontainers::PostgresContainer::POSTGRES_DEFAULT_DATABASE = T.let(T.unsafe(nil), String)

# Default image used by the container
#
# source://testcontainers-postgres//lib/testcontainers/postgres.rb#16
Testcontainers::PostgresContainer::POSTGRES_DEFAULT_IMAGE = T.let(T.unsafe(nil), String)

# source://testcontainers-postgres//lib/testcontainers/postgres.rb#19
Testcontainers::PostgresContainer::POSTGRES_DEFAULT_PASSWORD = T.let(T.unsafe(nil), String)

# Default port used by the container
#
# source://testcontainers-postgres//lib/testcontainers/postgres.rb#13
Testcontainers::PostgresContainer::POSTGRES_DEFAULT_PORT = T.let(T.unsafe(nil), Integer)

# source://testcontainers-postgres//lib/testcontainers/postgres.rb#18
Testcontainers::PostgresContainer::POSTGRES_DEFAULT_USERNAME = T.let(T.unsafe(nil), String)
