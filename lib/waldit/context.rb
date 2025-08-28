# frozen_string_literal: true

module Waldit
  module Context
    def with_context(context, &block)
      current_context = self.context || {}
      Thread.current[:waldit_context] ||= []
      Thread.current[:waldit_context].push(current_context.merge(context.as_json))
      block.call
    ensure
      Thread.current[:waldit_context].pop
    end

    def context
      Thread.current[:waldit_context]&.last
    end

    def add_context(added_context)
      context&.merge!(added_context.as_json)
    end

    def new_context(context = {})
      Thread.current[:waldit_context] ||= []
      Thread.current[:waldit_context].push(context.as_json)
    end
  end
end
