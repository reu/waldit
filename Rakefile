# frozen_string_literal: true

require "bundler/gem_tasks"

task(:test) { sh "bundle exec rspec" }

task default: %i[build]

task("sig/waldit.rbi") { sh "bundle exec parlour" }
task("rbi/waldit.rbs" => "sig/waldit.rbi") { sh "rbs prototype rbi rbi/waldit.rbi > sig/waldit.rbs" }

Rake::Task["build"].enhance(["sig/waldit.rbi", "rbi/waldit.rbs"])
