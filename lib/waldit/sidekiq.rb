# frozen_string_literal: true
# typed: false

module Waldit
  module Sidekiq
    class SaveContext
      include ::Sidekiq::ClientMiddleware

      def call(job_class, job, queue, redis)
        if (context = Waldit.context)
          job["waldit_context"] = context.to_json
        end
        yield
      end
    end

    class LoadContext
      include ::Sidekiq::ServerMiddleware

      def call(job_instance, job, queue, &block)
        context = deserialize_context(job) || {}
        Waldit.with_context(context.merge(background_job: job_instance.class.to_s), &block)
      end

      private

      def deserialize_context(job)
        if (serialized_context = job["waldit_context"]) && serialized_context.is_a?(String)
          context = JSON.parse(serialized_context)
          context if context.is_a? Hash
        end
      rescue JSON::ParserError
        nil
      end
    end
  end
end
