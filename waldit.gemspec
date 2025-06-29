# frozen_string_literal: true

require_relative "lib/waldit/version"

Gem::Specification.new do |spec|
  spec.name = "waldit"
  spec.version = Waldit::VERSION
  spec.authors = ["Rodrigo Navarro"]
  spec.email = ["rnavarro@rnavarro.com.br"]

  spec.summary = "Postgres based audit trail for Rails."
  spec.description = "Postgres based audit trail for your Active Records, with 100% consistency."
  spec.homepage = "https://github.com/reu/waldit"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ sorbet/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "wal", ">= 0.0.2"
  spec.add_dependency "activerecord", ">= 7"

  spec.add_development_dependency "rbs"
  spec.add_development_dependency "sorbet"
  spec.add_development_dependency "tapioca"
  spec.add_development_dependency "parlour"
end
