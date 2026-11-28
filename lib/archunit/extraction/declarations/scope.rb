# frozen_string_literal: true

module ArchUnit
  module Extraction
    module Declarations
      # Immutable lexical state for a single node; nothing is inferred from runtime loading.
      Scope = Data.define(:nesting, :owner, :context, :singleton) do
        def self.root
          new(nesting: [].freeze, owner: nil, context: :direct, singleton: :none)
        end

        def qualify(written)
          return unless written
          return written.delete_prefix('::').freeze if written.start_with?('::')
          return if unknown_lexical_owner?
          return written if nesting.empty?
          return if written.include?('::')

          "#{nesting.first}::#{written}".freeze
        end

        def inside(namespace)
          with(nesting: [namespace.name, *nesting].freeze, owner: namespace.site, singleton: :none)
        end

        def within_singleton(expression)
          if singleton == :none && expression.is_a?(Prism::SelfNode)
            with(singleton: :self)
          else
            with(singleton: :other, context: :dynamic)
          end
        end

        def conditional
          context == :dynamic ? self : with(context: :conditional)
        end

        def method_scope(receiver)
          return :unknown unless owner
          return :unknown if singleton == :other
          return singleton == :self ? :singleton : :instance unless receiver
          return :singleton if singleton == :none && receiver.is_a?(Prism::SelfNode)

          :unknown
        end

        private

        def unknown_lexical_owner?
          singleton != :none || (owner && nesting.first.nil?)
        end
      end
      private_constant :Scope
    end
  end
end
