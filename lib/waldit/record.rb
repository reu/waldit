# frozen_string_literal: true

module Waldit
  module Record
    def self.included(base)
      base.class_eval do
        scope :from_table, -> table { order(:committed_at).where(table_name: table) }
        scope :from_model, -> model { from_table(model.table_name) }
        scope :for, -> record { from_model(record.class).where(primary_key: record.id) }
        scope :with_context, -> ctx { order(:committed_at).where("context @> ?", ctx.to_json) }
      end
    end

    def new
      return self[:new] if self[:new]
      (self[:diff] || {}).transform_values { |_old, new| new }
    end

    def old
      return self[:old] if self[:old]
      (self[:diff] || {}).transform_values { |old, _new| old }
    end

    def diff
      return self[:diff] if self[:diff]
      (old.keys | new.keys).reduce({}) do |diff, key|
        old[key] != new[key] ? diff.merge(key => [old[key], new[key]]) : diff
      end
    end
  end
end
