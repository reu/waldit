# frozen_string_literal: true
# typed: true

module Waldit
  module Record
    extend T::Sig
    extend T::Helpers
    abstract!

    sig { abstract.returns(T::Hash[T.any(String, Symbol), T.untyped]) }
    def new; end

    sig { abstract.returns(T::Hash[T.any(String, Symbol), T.untyped]) }
    def old; end

    sig { returns(T::Hash[T.any(String, Symbol), [T.untyped, T.untyped]]) }
    def diff
      (old.keys | new.keys).reduce({}.with_indifferent_access) do |diff, key|
        old[key] != new[key] ? diff.merge(key => [old[key], new[key]]) : diff
      end
    end
  end
end
