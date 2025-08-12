# frozen_string_literal: true

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
        background_job = case job["class"]
        in "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper"
          job["args"][0]["job_class"]
        in klass
          klass
        end
        Waldit.with_context((deserialize_context(job) || {}).merge(background_job:), &block)
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
