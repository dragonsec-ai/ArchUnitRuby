# frozen_string_literal: true

module ArchUnit
  module Classes
    module FluentApi
      CONSTANT_NAME = /\A(?:::)?\p{Lu}[\p{L}\p{M}\p{N}_]*(?:::\p{Lu}[\p{L}\p{M}\p{N}_]*)*\z/u
      private_constant :CONSTANT_NAME

      # Lexical inputs, not Ruby expressions or paths.
      ClassFilters = Data.define(:constants, :namespaces, :ancestors) do
        def self.empty
          new(constants: [].freeze, namespaces: [].freeze, ancestors: [].freeze)
        end

        def add(kind, raw)
          name = normalized_name(raw)
          case kind
          when :constant then with(constants: append(constants, name))
          when :namespace then with(namespaces: append(namespaces, name))
          when :ancestor then with(ancestors: append(ancestors, name))
          end
        end

        def matches_name?(name)
          (constants.empty? || constants.all? { |exact| exact == name }) &&
            namespaces.all? { |prefix| name.start_with?("#{prefix}::") }
        end

        def possible?
          return false if constants.size > 1
          return matches_name?(constants.first) unless constants.empty?

          deepest = namespaces.max_by(&:length)
          namespaces.all? { |prefix| deepest == prefix || deepest.start_with?("#{prefix}::") }
        end

        def unresolved_name_possible?(written)
          return true if written.nil? || constants.empty?

          constant_leaf(written) == constant_leaf(constants.first)
        end

        private

        def constant_leaf(name)
          name.split('::').last
        end

        def normalized_name(raw)
          value = raw.encode(Encoding::UTF_8) if raw.is_a?(String)
          return value.delete_prefix('::').freeze if value&.valid_encoding? &&
                                                     CONSTANT_NAME.match?(value)

          raise ArgumentError, 'expected a qualified constant name such as Billing::Invoice'
        rescue EncodingError => e
          raise ArgumentError, "invalid constant name encoding: #{e.message}"
        end

        def append(values, name)
          [*values, name].uniq.freeze
        end
      end
      private_constant :ClassFilters
    end
  end
end
