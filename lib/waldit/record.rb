# frozen_string_literal: true

module Waldit
  module Record
    def diff
      (old.keys | new.keys).reduce({}.with_indifferent_access) do |diff, key|
        old[key] != new[key] ? diff.merge(key => [old[key], new[key]]) : diff
      end
    end
  end
end
