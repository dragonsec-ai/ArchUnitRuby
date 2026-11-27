# frozen_string_literal: true

require_relative 'analysis_observer'
require_relative 'analysis_snapshot'
require_relative 'enumerate_source_files'
require_relative 'extract_imports'
require_relative 'locate_project'
require_relative 'named_call_visitor'

module ArchUnit
  # Ruby-specific extraction of source facts for file policies.
  module Extraction
    # Independent, on-demand source facts; graph-only checks never collect or cache them.
    NamedCalls = Data.define(:by_file, :snapshot)
    NAMED_CALL_MUTEX = Mutex.new
    private_constant :NamedCalls, :NAMED_CALL_MUTEX

    module_function

    # @api private
    def extract_named_calls(locator, options:)
      root = Pathname.new(locate_project(locator))
      patterns = resolve_project_exclude_patterns(
        root, nil, source_exclusions: options.source_exclusions
      )
      entry, cache_hit = fetch_named_calls(root, patterns.sort.freeze, options)
      AnalysisObserver.record(entry.snapshot, cache_hit:)
      entry.by_file
    end

    def clear_named_calls
      NAMED_CALL_MUTEX.synchronize { @named_call_cache&.clear }
    end
    private_class_method :clear_named_calls

    def fetch_named_calls(root, patterns, options)
      key = [root.to_s, patterns]
      NAMED_CALL_MUTEX.synchronize do
        named_call_cache.delete(key) if options.clear_cache?
        entry = named_call_cache[key]
        return [entry, true] if entry

        [named_call_cache[key] = build_named_calls(root, patterns), false]
      end
    rescue StandardError
      AnalysisObserver.record(call_snapshot(root, patterns, nil, 'error'))
      raise
    end
    private_class_method :fetch_named_calls

    def build_named_calls(root, patterns)
      files = enumerate_source_files_with_patterns(root, patterns)
      by_file = files.to_h { |file| [file, calls_in_file(root, file)] }.freeze
      NamedCalls.new(by_file:, snapshot: call_snapshot(root, patterns, files.length, 'analyzed'))
    end
    private_class_method :build_named_calls

    def calls_in_file(root, file)
      visitor = NamedCallVisitor.new(file)
      visitor.visit(parse_source(root.join(file), nil).value)
      visitor.calls.sort_by { |call| [call.line, call.column] }.freeze
    end
    private_class_method :calls_in_file

    def call_snapshot(root, patterns, count, status)
      discovery = SourceDiscovery.new(root:, patterns:, files: [])
      AnalysisSnapshot.source(discovery, count:, status:, kind: 'source_calls')
    end
    private_class_method :call_snapshot

    def named_call_cache
      @named_call_cache ||= {}
    end
    private_class_method :named_call_cache
  end
end
