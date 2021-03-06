require 'thread'
require 'ddtrace/ext/cache'

module Datadog
  module Contrib
    module Rails
      # Code used to create and handle 'rails.cache' spans.
      module ActiveSupport
        include Datadog::Patcher

        def self.instrument
          do_once(:instrument) do
            # patch Rails core components
            Datadog::RailsCachePatcher.patch_cache_store
          end
        end

        def self.start_trace_cache(payload)
          tracer = Datadog.configuration[:rails][:tracer]

          # In most of the cases Rails ``fetch()`` and ``read()`` calls are nested.
          # This check ensures that two reads are not nested since they don't provide
          # interesting details.
          # NOTE: the ``finish_trace_cache()`` is fired but it already has a safe-guard
          # to avoid any kind of issue.
          current_span = tracer.active_span
          return if payload[:action] == 'GET'.freeze &&
                    current_span.try(:name) == 'rails.cache'.freeze &&
                    current_span.try(:resource) == 'GET'.freeze

          tracing_context = payload.fetch(:tracing_context)

          # create a new ``Span`` and add it to the tracing context
          service = Datadog.configuration[:rails][:cache_service]
          type = Datadog::Ext::CACHE::TYPE
          span = tracer.trace('rails.cache'.freeze, service: service, span_type: type)
          span.resource = payload.fetch(:action)
          tracing_context[:dd_cache_span] = span
        rescue StandardError => e
          Datadog::Tracer.log.debug(e.message)
        end

        def self.finish_trace_cache(payload)
          # retrieve the tracing context and continue the trace
          tracing_context = payload.fetch(:tracing_context)
          span = tracing_context[:dd_cache_span]
          return unless span && !span.finished?

          begin
            # discard parameters from the cache_store configuration
            store, = *Array.wrap(::Rails.configuration.cache_store).flatten
            span.set_tag('rails.cache.backend'.freeze, store)
            cache_key = Datadog::Utils.truncate(payload.fetch(:key), Ext::CACHE::MAX_KEY_SIZE)
            span.set_tag('rails.cache.key'.freeze, cache_key)
            span.set_error(payload[:exception]) if payload[:exception]
          ensure
            span.finish
          end
        rescue StandardError => e
          Datadog::Tracer.log.debug(e.message)
        end
      end
    end
  end
end
