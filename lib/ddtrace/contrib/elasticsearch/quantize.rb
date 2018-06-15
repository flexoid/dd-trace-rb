module Datadog
  module Contrib
    module Elasticsearch
      # Quantize contains ES-specific resource quantization tools.
      module Quantize
        PLACEHOLDER = '?'.freeze
        EXCLUDE_KEYS = [].freeze
        SHOW_KEYS = [:_index, :_type, :_id].freeze
        DEFAULT_OPTIONS = { exclude: EXCLUDE_KEYS, show: SHOW_KEYS }.freeze

        # Based on regexp from https://github.com/DataDog/dd-trace-java/blob/master/dd-trace-ot/src/main/java/datadog/opentracing/decorators/URLAsResourceName.java#L16
        # Matches any path segments with numbers in them.
        CAPTURE_PATH_SEGMENTS_WITH_NUMBERS_REGEXP = %r{(?<=/)(?:[^\?/\d]*[\d]+[^\?/]*)}

        module_function

        def format_url(url)
          sanitize_index_in_url(url)
            .gsub(CAPTURE_PATH_SEGMENTS_WITH_NUMBERS_REGEXP, PLACEHOLDER)
        end

        def format_body(body, options = {})
          format_body!(body, options)
        rescue StandardError
          PLACEHOLDER
        end

        def format_body!(body, options = {})
          options = merge_options(DEFAULT_OPTIONS, options)

          # Determine if bulk query or not, based on content
          statements = body.end_with?("\n") ? body.split("\n") : [body]

          # Parse each statement and quantize them.
          statements.collect do |string|
            reserialize_json(string) do |obj|
              format_statement(obj, options)
            end
          end.join("\n")
        end

        def format_statement(statement, options = {})
          return statement if options[:show] == :all

          case statement
          when Hash
            statement.each_with_object({}) do |(key, value), quantized|
              if options[:show].include?(key.to_sym)
                quantized[key] = value
              elsif !options[:exclude].include?(key.to_sym)
                quantized[key] = format_value(value, options)
              end
            end
          else
            format_value(statement, options)
          end
        end

        def format_value(value, options = {})
          return value if options[:show] == :all

          case value
          when Hash
            format_statement(value, options)
          when Array
            # If any are objects, format them.
            if value.any? { |v| v.class <= Hash || v.class <= Array }
              value.collect { |i| format_value(i, options) }
            # Otherwise short-circuit and return single placeholder
            else
              PLACEHOLDER
            end
          else
            PLACEHOLDER
          end
        end

        def merge_options(original, additional)
          {}.tap do |options|
            # Show
            # If either is :all, value becomes :all
            options[:show] = if original[:show] == :all || additional[:show] == :all
                               :all
                             else
                               (original[:show] || []).dup.concat(additional[:show] || []).uniq
                             end

            # Exclude
            options[:exclude] = (original[:exclude] || []).dup.concat(additional[:exclude] || []).uniq
          end
        end

        # Parses a JSON object from a string, passes its value
        # to the block provided, and dumps its result back to JSON.
        # If JSON parsing fails, it prints fail_value.
        def reserialize_json(string, fail_value = PLACEHOLDER)
          return string unless block_given?
          begin
            JSON.dump(yield(JSON.parse(string)))
          rescue JSON::ParserError
            # If it can't parse/dump, don't raise an error.
            fail_value
          end
        end

        def sanitize_index_in_url(url)
          index_end = url.index('/'.freeze, 1)
          return url unless index_end

          index_part = url.slice(0, index_end)
          index_part.gsub!(/\d+/, PLACEHOLDER)

          index_part << url.slice(index_end..-1)
        end
      end
    end
  end
end
