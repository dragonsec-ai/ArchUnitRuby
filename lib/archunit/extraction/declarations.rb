# frozen_string_literal: true

require_relative 'declarations/collector'
require_relative 'declarations/cache'
require_relative 'analysis_observer'
require_relative 'analysis_snapshot'
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
      root = Pathname.new(locate_project(locator))
      options = Common::FluentApi::CheckOptions.resolve(options)
      patterns = resolve_project_exclude_patterns(
        root, nil, source_exclusions: options.source_exclusions
      ).sort.freeze
      cached_declarations(root, patterns, options).first
    end

    def cached_declarations(root, patterns, options)
      key = [root.to_s.freeze, patterns].freeze
      bundle, hit = Declarations::Cache.fetch(key, refresh: options.clear_cache?) do
        declaration_bundle(root, patterns)
      end
      AnalysisObserver.record(bundle.last, cache_hit: hit)
      bundle
    rescue StandardError
      AnalysisObserver.record(declaration_snapshot(root, patterns, nil, 'error'))
      raise
    end
    private_class_method :cached_declarations

    def declaration_bundle(root, patterns)
      files = enumerate_source_files_with_patterns(root, patterns)
      inventories = files.map do |file|
        Declarations.collect(parse_source(root.join(file), nil), file:)
      end
      snapshot = declaration_snapshot(root, patterns, files.length, 'analyzed')
      [Declarations.combine(inventories), snapshot].freeze
    end
    private_class_method :declaration_bundle

    def declaration_snapshot(root, patterns, count, status)
      discovery = SourceDiscovery.new(root:, patterns:, files: [].freeze)
      AnalysisSnapshot.source(discovery, count:, status:).merge(kind: 'source_declarations').freeze
    end
    private_class_method :declaration_snapshot

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
