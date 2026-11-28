# frozen_string_literal: true

require 'prism'

module ArchUnit
  module Classes
    module FluentApi
      ASCII_CONSTANT = /\A[A-Z][A-Za-z0-9_]*\z/
      private_constant :ASCII_CONSTANT

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
            namespaces.all? { |prefix| in_namespace?(name, prefix) }
        end

        def possible?
          return false if constants.size > 1
          return matches_name?(constants.first) unless constants.empty?

          deepest = namespaces.max_by(&:length)
          namespaces.all? { |prefix| deepest == prefix || in_namespace?(deepest, prefix) }
        end

        def unresolved_name_possible?(written)
          return true if written.nil? || constants.empty?

          constant_leaf(written) == constant_leaf(constants.first)
        end

        private

        def in_namespace?(name, prefix)
          Encoding.compatible?(name, prefix) && name.start_with?("#{prefix}::")
        end

        def constant_leaf(name)
          name.split('::').last
        end

        def normalized_name(raw)
          if raw.is_a?(String) && raw.encoding.ascii_compatible? && raw.valid_encoding?
            value = raw.delete_prefix('::')
            segments = value.split('::', -1)
            return value.freeze if !segments.empty? && segments.all? { |part| constant?(part) }
          end

          raise ArgumentError, 'expected a qualified constant name such as Billing::Invoice'
        end

        def constant?(part)
          return ASCII_CONSTANT.match?(part) if part.ascii_only?

          # Ruby accepts some Unicode identifiers a category regex cannot describe.
          result = Prism.lex(part, encoding: part.encoding)
          result.success? && result.value.size == 2 &&
            whole_constant?(result.value.first.first, part)
        end

        def whole_constant?(token, part)
          token.type == :CONSTANT && token.location.start_offset.zero? &&
            token.location.length == part.bytesize
        end

        def append(values, name)
          [*values, name].uniq.freeze
        end
      end
      private_constant :ClassFilters
    end
  end
end
