# frozen_string_literal: true

require 'pathname'
require_relative '../common/extraction/edge'
require_relative '../common/extraction/graph'
require_relative '../common/fluentapi/check_options'
require_relative '../common/logging/inspection'
require_relative 'enumerate_source_files'
require_relative 'extract_dependencies'
require_relative 'extraction_profile'
require_relative 'locate_project'
require_relative 'resolve_load_paths'
require_relative 'graph_cache_key'
require_relative 'analysis_profile'
require_relative 'analysis_snapshot'
require_relative 'analysis_observer'
require_relative 'graph_assembly'
require_relative 'graph_views'
require_relative 'named_call_analysis'

module ArchUnit
  # Assembles the normalized dependency graph for a Ruby project.
  module Extraction
    GRAPH_CACHE_MUTEX = Mutex.new
    CachedGraph = Data.define(:graph, :analysis, :views)
    private_constant :CachedGraph

    module_function

    def extract_graph(
      locator = nil, exclude_patterns: nil, options: nil, working_directory: Dir.pwd,
      profile: nil
    )
      extract_graph_entry(locator, exclude_patterns:, options:, working_directory:, profile:).graph
    end

    # @api private
    def extract_graph_views(locator = nil, options: nil, exclude_patterns: nil)
      extract_graph_entry(locator, options:, exclude_patterns:).views
    end

    def extract_graph_entry(
      locator = nil, exclude_patterns: nil, options: nil, working_directory: Dir.pwd, profile: nil
    )
      ExtractionProfile.validate(profile)
      options = Common::FluentApi::CheckOptions.resolve(options)
      ExtractionProfile.measure(profile, :total) do
        root = ExtractionProfile.measure(profile, :project_discovery) do
          Pathname.new(locate_project(locator, working_directory:))
        end
        resolved_graph(root, exclude_patterns, options, profile)
      end
    end
    private_class_method :extract_graph_entry

    def clear_graph_cache
      GRAPH_CACHE_MUTEX.synchronize { graph_cache.clear }
      clear_named_calls
      nil
    end

    def resolved_graph(root, exclude_patterns, options, profile)
      patterns = resolve_project_exclude_patterns(
        root, exclude_patterns, source_exclusions: options.source_exclusions
      )
      key = GraphCacheKey.build(root, patterns, options)
      entry, cache_hit = fetch_graph(root, patterns, options, key, profile)
      AnalysisObserver.record(entry.analysis, cache_hit:)
      Common::Logging::Inspection.graph(entry.graph, root:)
      entry
    end
    private_class_method :resolved_graph

    def fetch_graph(root, patterns, options, cache_key, profile)
      GRAPH_CACHE_MUTEX.synchronize do
        cached_graph(root, patterns, options, cache_key, profile)
      end
    rescue StandardError
      AnalysisObserver.record(AnalysisSnapshot.graph(root, patterns, options, status: 'error'))
      raise
    end
    private_class_method :fetch_graph

    def cached_graph(root, patterns, options, cache_key, profile)
      graph_cache.delete(cache_key) if options.clear_cache?
      if (cached = graph_cache[cache_key])
        profile&.record_cache_hit
        return [cached, true]
      end

      entry = build_graph_entry(root, patterns, options, profile)
      graph_cache[cache_key] = entry
      [entry, false]
    end
    private_class_method :cached_graph

    def build_graph_entry(root, patterns, options, profile)
      recorder = AnalysisProfile.new(profile)
      graph = extract_graph_uncached(root, patterns, options, recorder)
      analysis = AnalysisSnapshot.graph(root, patterns, options, counters: recorder.counters)
      CachedGraph.new(graph:, analysis:, views: GraphViews.new(graph))
    end
    private_class_method :build_graph_entry

    def extract_graph_uncached(root, exclude_patterns, options, profile)
      source_files = ExtractionProfile.measure(profile, :source_enumeration) do
        enumerate_source_files_with_patterns(root, exclude_patterns)
      end
      profile&.increment(:source_files, source_files.length)
      load_paths = ExtractionProfile.measure(profile, :load_path_discovery) do
        LoadPaths.resolve(root, explicit_paths: options.load_paths, source_files:)
      end
      edges = extraction_edges(root, source_files, load_paths, options, profile)
      GraphAssembly.build(edges, profile)
    end
    private_class_method :extract_graph_uncached

    def extraction_edges(root, source_files, load_paths, options, profile)
      edges = self_edges(source_files) + extract_dependencies_from(
        root, source_files, load_paths:, profile:, options:
      )
      profile&.increment(:raw_edges, edges.length)
      edges
    end
    private_class_method :extraction_edges

    def graph_cache
      @graph_cache ||= {}
    end
    private_class_method :graph_cache

    def self_edges(source_files)
      source_files.map do |source|
        Common::Extraction::Edge.new(source: source, target: source, external: false)
      end
    end
    private_class_method :self_edges
  end
end
