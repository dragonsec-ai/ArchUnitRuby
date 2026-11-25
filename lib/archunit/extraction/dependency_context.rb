# frozen_string_literal: true

require_relative 'resolve_load_paths'

module ArchUnit
  module Extraction
    # Per-graph extraction state; keeps helper search roots separate from ordinary Ruby imports.
    DependencyContext = Data.define(
      :root, :targets, :load_paths, :profile, :cache, :include_evidence,
      :rails_imports, :helper_load_paths
    ) do
      def self.build(root:, targets:, load_paths:, profile:, options:)
        helpers = if options.rails_imports?
                    LoadPaths.with_explicit_first(root, load_paths, options.load_paths)
                  else
                    load_paths
                  end
        new(root:, targets:, load_paths:, profile:, cache: {},
            include_evidence: options.constant_references? || options.rails_associations?,
            rails_imports: options.rails_imports,
            helper_load_paths: helpers)
      end

      def extractor_options
        { project_root: root, load_paths:, profile:, resolution_cache: cache,
          rails_imports:, helper_load_paths: }
      end
    end
    private_constant :DependencyContext
  end
end
