# frozen_string_literal: true

module Waldit
  module Record
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
