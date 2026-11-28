# frozen_string_literal: true

module ArchUnit
  module Classes
    module Assertion
      # Checks call compatibility using only a method's written parameter shapes.
      module CallableShape
        REQUIRED = %i[required post destructured].freeze
        private_constant :REQUIRED

        def self.matches?(parameters, signature)
          groups = parameters.group_by(&:kind)
          accepts_positionals?(groups, signature.positional) &&
            accepts_keywords?(groups, signature.keywords) &&
            accepts_block?(groups, signature.block)
        end

        def self.accepts_positionals?(groups, count)
          minimum = REQUIRED.sum { |key| groups.fetch(key, []).size }
          return false if count < minimum
          return true if groups.key?(:rest) || groups.key?(:forwarding)

          count <= minimum + groups.fetch(:optional, []).size
        end

        def self.accepts_keywords?(groups, requested)
          return requested.empty? if groups.key?(:no_keywords)

          required = names(groups, :required_keyword)
          return false unless (required - requested).empty?
          return true if groups.key?(:keyword_rest) || groups.key?(:forwarding)

          (requested - required - names(groups, :optional_keyword)).empty?
        end

        def self.names(groups, kind)
          groups.fetch(kind, []).map { |parameter| parameter.name.to_s.encode(Encoding::UTF_8) }
        end

        def self.accepts_block?(groups, policy)
          policy == :any || groups.key?(:block) || groups.key?(:forwarding)
        end
        private_class_method :accepts_positionals?, :accepts_keywords?, :names, :accepts_block?
      end
      private_constant :CallableShape
    end
  end
end
