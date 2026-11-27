# frozen_string_literal: true

require_relative 'declarations/collector'
require_relative '../error/source_parse_error'
require_relative 'enumerate_source_files'
require_relative 'extract_imports'
require_relative 'locate_project'

module ArchUnit
  # Ruby-specific extraction of declaration facts from the existing source inventory.
  module Extraction
    module_function

    # Returns facts from one project without changing file-graph analysis or cache identity.
    # @api private
    def extract_declarations(locator = nil, options: nil)
      root = locate_project(locator)
      discovery = discover_source_files(root, options:)
      inventories = discovery.files.map do |file|
        Declarations.collect(parse_source(discovery.root.join(file), nil), file:)
      end
      Declarations.combine(inventories)
    end

    # Internal entry point for facts from an already parsed Ruby file.
    # @api private
    module Declarations
      def self.collect(result, file:)
        tree = SourceParseError.validate!(result, path: file).value
        Collector.new(file).collect(tree)
      end

      def self.combine(inventories)
        type = Common::Extraction::DeclarationFacts::Inventory
        fields = type.members.to_h do |attribute|
          [attribute, inventories.flat_map { |inventory| inventory.public_send(attribute) }.freeze]
        end
        type.new(**fields)
      end
    end
  end
end
