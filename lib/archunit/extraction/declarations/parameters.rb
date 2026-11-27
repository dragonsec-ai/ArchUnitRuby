# frozen_string_literal: true

require 'prism'
require_relative '../../common/extraction/declaration_facts'

module ArchUnit
  module Extraction
    module Declarations
      # Represents written parameter shape, not Ruby argument binding or a runtime API.
      module Parameters
        FIELDS = {
          requireds: :required, optionals: :optional, rest: :rest, posts: :post,
          keywords: :keyword, keyword_rest: :keyword_rest, block: :block
        }.freeze
        private_constant :FIELDS

        def self.collect(parameters)
          return [].freeze unless parameters

          FIELDS.flat_map do |field, kind|
            Array(parameters.public_send(field)).map { |node| parameter(node, kind) }
          end.freeze
        end

        def self.parameter(node, kind)
          name = node.respond_to?(:name) ? node.name : nil
          Common::Extraction::DeclarationFacts::Parameter.new(kind: parameter_kind(node, kind),
                                                              name:)
        end
        private_class_method :parameter

        def self.parameter_kind(node, kind)
          case node.type
          when :forwarding_parameter_node then :forwarding
          when :no_keywords_parameter_node then :no_keywords
          when :required_keyword_parameter_node then :required_keyword
          when :optional_keyword_parameter_node then :optional_keyword
          when :multi_target_node then :destructured
          else kind
          end
        end
        private_class_method :parameter_kind
      end
      private_constant :Parameters
    end
  end
end
