# frozen_string_literal: true

require 'prism'
require_relative '../common/extraction/call_site'

module ArchUnit
  module Extraction
    # Collects syntactic calls. Generated and dynamically dispatched names are not inferred.
    class NamedCallVisitor < Prism::Visitor
      attr_reader :calls

      def initialize(file)
        super()
        @file = file
        @calls = []
      end

      def visit_call_node(node)
        @calls << call_site(node) if node.message_loc
        super
      end

      private

      def call_site(node)
        location = node.message_loc
        Common::Extraction::CallSite.new(
          file: @file, name: node.name.to_s.encode(Encoding::UTF_8).freeze,
          receiver: receiver_form(node.receiver), safe_navigation: node.safe_navigation?,
          line: location.start_line, column: location.start_column + 1
        )
      end

      def receiver_form(receiver)
        return :bare if receiver.nil?

        receiver.is_a?(Prism::SelfNode) ? :self : :explicit
      end
    end
    private_constant :NamedCallVisitor
  end
end
