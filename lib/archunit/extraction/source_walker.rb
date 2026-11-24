# frozen_string_literal: true

require_relative 'source_pattern_matcher'

module ArchUnit
  module Extraction
    # Pruned iterative traversal of an already canonical, validated project root.
    # Identifiers come from child components, never unchecked absolute-prefix slicing.
    # @api private
    class SourceWalker
      def initialize(root, patterns)
        @root = root.to_s
        @encoding = @root.encoding
        @encoding = Encoding.find('filesystem') if @encoding == Encoding::US_ASCII
        @matcher = SourcePatternMatcher.new(patterns)
      end

      def files
        files = []
        pending = [[@root, '']]
        until pending.empty?
          directory, prefix = pending.pop
          collect_directory(directory, prefix, pending, files)
        end
        files
      end

      private

      def collect_directory(directory, prefix, pending, files)
        Dir.children(directory, encoding: @encoding).each do |name|
          collect_child(directory, prefix, name, pending, files)
        end
      end

      def collect_child(directory, prefix, name, pending, files)
        path = File.join(directory, name)
        kind = source_kind(path, name)
        return unless kind

        identifier = child_identifier(prefix, name)
        return if @matcher.excluded?(identifier, name)

        collect_path(kind, path, identifier, pending, files)
      end

      def source_kind(path, name)
        stat = File.lstat(path)
        return if stat.symlink?
        return :directory if stat.directory?

        :source if stat.file? && File.extname(name) == '.rb'
      end

      def child_identifier(prefix, name)
        name = name.tr('\\', '/')
        prefix.empty? ? name : "#{prefix}/#{name}"
      end

      def collect_path(kind, path, identifier, pending, files)
        if kind == :directory
          pending << [path, identifier]
        else
          files << identifier.freeze
        end
      end
    end
    private_constant :SourceWalker
  end
end
