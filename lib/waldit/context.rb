# frozen_string_literal: true
# typed: true

module Waldit
  module Context
    extend T::Sig

    Context = T.type_alias { T::Hash[T.any(String, Symbol), T.untyped] }

    sig do
      type_parameters(:U)
        .params(context: Context, block: T.proc.returns(T.type_parameter(:U)))
        .returns(T.type_parameter(:U))
    end
    def with_context(context, &block)
      current_context = self.context || {}
      Thread.current[:waldit_context] ||= []
      Thread.current[:waldit_context].push(current_context.merge(context.as_json))
      block.call
    ensure
      Thread.current[:waldit_context].pop
    end

    sig { returns(T.nilable(Context)) }
    def context
      Thread.current[:waldit_context]&.last
    end

    sig { params(added_context: Context).void }
    def add_context(added_context)
      if (context = self.context)
        context.merge!(added_context.as_json)
      else
        new_context(added_context)
      end
    end

    sig { params(context: Context).void }
    def new_context(context = {})
      Thread.current[:waldit_context] ||= []
      Thread.current[:waldit_context].push(context.as_json)
    end
  end
end
