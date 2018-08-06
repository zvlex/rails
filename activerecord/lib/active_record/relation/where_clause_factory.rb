module ActiveRecord
  class Relation
    class WhereClauseFactory # :nodoc:
      attr_accessor :is_custom_method

      def initialize(klass, predicate_builder)
        @klass = klass
        @predicate_builder = predicate_builder
      end

      def build(opts, other)
        case opts
        when Array
          parts = [klass.send(:sanitize_sql, other.empty? ? opts : ([opts] + other))]
        when String
          if is_custom_method
            params = other.first

            opts.gsub!(/([a-zA-Z_]+\s*[IN|in]\s*\((:[a-zA-Z_]+)\)+)+/).each do |attr|
              key = $2.sub(":", '').to_sym
              value = params[key].is_a?(Array) ? params[key].join(', ') : params[key]

              "IN (#{ value })"
            end

            parts = [opts]
            params = params.stringify_keys

            attributes, binds = predicate_builder.create_binds(params)
          else
            parts = [klass.send(:sanitize_sql, other.empty? ? opts : ([opts] + other))]
          end
        when Hash
          attributes = predicate_builder.resolve_column_aliases(opts)
          attributes = klass.send(:expand_hash_conditions_for_aggregates, attributes)
          attributes.stringify_keys!

          if perform_case_sensitive?(options = other.last)
            parts, binds = build_for_case_sensitive(attributes, options)
          else
            attributes, binds = predicate_builder.create_binds(attributes)
            parts = predicate_builder.build_from_hash(attributes)
          end
        when Arel::Nodes::Node
          parts = [opts]
        else
          raise ArgumentError, "Unsupported argument type: #{opts} (#{opts.class})"
        end

        WhereClause.new(parts, binds || [])
      end

      # TODO Change this to private once we've dropped Ruby 2.2 support.
      # Workaround for Ruby 2.2 "private attribute?" warning.
      protected

        attr_reader :klass, :predicate_builder

      private

        def perform_case_sensitive?(options)
          options && options.key?(:case_sensitive)
        end

        def build_for_case_sensitive(attributes, options)
          parts, binds = [], []
          table = klass.arel_table

          attributes.each do |attribute, value|
            if reflection = klass._reflect_on_association(attribute)
              attribute = reflection.foreign_key.to_s
              value = value[reflection.klass.primary_key] unless value.nil?
            end

            if value.nil?
              parts << table[attribute].eq(value)
            else
              column = klass.column_for_attribute(attribute)

              binds << predicate_builder.send(:build_bind_param, attribute, value)
              value = Arel::Nodes::BindParam.new

              predicate = if options[:case_sensitive]
                klass.connection.case_sensitive_comparison(table, attribute, column, value)
              else
                klass.connection.case_insensitive_comparison(table, attribute, column, value)
              end

              parts << predicate
            end
          end

          [parts, binds]
        end
    end
  end
end
