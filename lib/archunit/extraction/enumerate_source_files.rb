# frozen_string_literal: true

require 'pathname'
require_relative '../error/technical_error'
require_relative '../error/user_error'
require_relative 'arch_ignore'
require_relative 'source_identifier'
require_relative 'source_walker'
require_relative '../common/fluentapi/check_options'

module ArchUnit
  # Ruby-specific project discovery and source extraction.
  module Extraction
    DEFAULT_EXCLUDED_DIRECTORIES = %w[
      .bundle
      .cache
      .git
      .hg
      .ruby-lsp
      .svn
      .yardoc
      build
      coverage
      dist
      log
      node_modules
      pkg
      tmp
      vendor
    ].freeze
    SourceDiscovery = Data.define(:root, :patterns, :files)
    private_constant :SourceDiscovery

    module_function

    def enumerate_source_files(project_root, exclude_patterns: nil, options: nil)
      discover_source_files(project_root, exclude_patterns:, options:).files
    end

    # @api private
    def discover_source_files(project_root, exclude_patterns: nil, options: nil)
      options = Common::FluentApi::CheckOptions.resolve(options)
      root = source_root(project_root)
      patterns = resolve_project_exclude_patterns(
        root, exclude_patterns, source_exclusions: options.source_exclusions
      )
      SourceDiscovery.new(root: root.freeze, patterns:,
                          files: enumerate_source_files_with_patterns(root, patterns))
    end

    def enumerate_source_files_with_patterns(root, patterns)
      source_files_under(root, patterns).sort.freeze
    rescue UserError, TechnicalError
      raise
    rescue SystemCallError => e
      raise TechnicalError, "could not enumerate Ruby source files: #{e.message}"
    end
    private_class_method :enumerate_source_files_with_patterns

    def resolve_project_exclude_patterns(root, value, source_exclusions: [])
      configured = resolve_exclude_patterns(value)
      resolve_exclude_patterns([*configured, *ArchIgnore.patterns(root), *source_exclusions])
    end
    private_class_method :resolve_project_exclude_patterns

    def source_files_under(root, exclude_patterns)
      SourceWalker.new(root, exclude_patterns).files
    end
    private_class_method :source_files_under

    def resolve_exclude_patterns(value)
      patterns = value.nil? ? DEFAULT_EXCLUDED_DIRECTORIES : value
      validate_exclude_patterns(patterns)

      normalized = patterns.map { |pattern| normalize_exclude_pattern(pattern) }
      raise_invalid_exclude_patterns if normalized.any?(&:empty?)

      normalized.uniq.freeze
    end
    private_class_method :resolve_exclude_patterns

    def validate_exclude_patterns(patterns)
      return if patterns.is_a?(Array) && patterns.all? { |pattern| valid_exclude_pattern?(pattern) }

      raise_invalid_exclude_patterns
    end
    private_class_method :validate_exclude_patterns

    def raise_invalid_exclude_patterns
      raise UserError, 'exclude_patterns must be an Array of non-empty Strings'
    end
    private_class_method :raise_invalid_exclude_patterns

    def valid_exclude_pattern?(pattern)
      pattern.is_a?(String) && !pattern.empty?
    end
    private_class_method :valid_exclude_pattern?

    def normalize_exclude_pattern(pattern)
      pattern.tr('\\', '/').delete_prefix('./').delete_suffix('/').freeze
    end
    private_class_method :normalize_exclude_pattern

    def source_root(value)
      value = value.to_path if value.respond_to?(:to_path)
      unless value.is_a?(String) && !value.empty?
        raise UserError, 'project_root must be a non-empty path'
      end

      root = Pathname.new(value).expand_path
      raise UserError, 'project_root must be an existing directory' unless root.directory?

      Pathname.new(SourceIdentifier.root(root.realpath))
    rescue SystemCallError => e
      raise TechnicalError, "could not enumerate Ruby source files: #{e.message}"
    end
    private_class_method :source_root
  end
end
