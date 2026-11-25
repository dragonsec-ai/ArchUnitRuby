# frozen_string_literal: true

require_relative 'rails_association_options'

module ArchUnit
  module Extraction
    # Collects direct Active Record-style class-body calls without walking into other receivers.
    class RailsAssociationCalls
      MACROS = %i[belongs_to has_one has_many has_and_belongs_to_many].freeze
      BASES = %w[ActiveRecord::Base ApplicationRecord].freeze
      Site = Data.define(:model, :name, :line_number, :end_line)
      private_constant :MACROS, :BASES, :Site

      attr_reader :sites

      def initialize
        @sites = []
      end

      def collect(model, superclass, body)
        return unless BASES.include?(superclass&.delete_prefix('::'))
        return unless body.is_a?(Prism::StatementsNode)

        body.body.each do |statement|
          next unless macro_call?(statement)

          @sites << site(model, statement)
        end
      end

      private

      def macro_call?(node)
        return false unless node.is_a?(Prism::CallNode) && MACROS.include?(node.name)

        !node.safe_navigation? && (node.receiver.nil? || node.receiver.is_a?(Prism::SelfNode))
      end

      def site(model, node)
        literal = RailsAssociationOptions.explicit_literal(node.arguments&.arguments || [])
        Site.new(model:, name: literal&.unescaped, line_number: node.message_loc.start_line,
                 end_line: (literal || node).location.end_line)
      end
    end
    private_constant :RailsAssociationCalls
  end
end
