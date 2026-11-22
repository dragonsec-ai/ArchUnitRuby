# frozen_string_literal: true

module ArchUnit
  module Layers
    module FluentApi
      # Immutable source-pattern overrides for an architecture preset; no I/O during construction.
      PresetOptions = Data.define(:project_locator, :folders) do
        def initialize(project_locator: nil, folders: {})
          project_locator = immutable_locator(project_locator)
          folders = immutable_folders(folders)
          super
        end

        def self.resolve(value)
          return new if value.nil?
          return value if value.is_a?(self)

          raise ArgumentError, 'options must be a PresetOptions value or nil'
        end

        private

        def immutable_locator(value)
          return if value.nil?

          value = value.to_path if value.respond_to?(:to_path)
          return value.dup.freeze if value.is_a?(String) && !value.empty?

          raise ArgumentError, 'project_locator must be a non-empty path or nil'
        end

        def immutable_folders(value)
          unless value.is_a?(Hash)
            raise ArgumentError,
                  'folders must map layer names to source globs'
          end

          entries = value.map { |name, patterns| folder_entry(name, patterns) }
          if entries.map(&:first).uniq.length != entries.length
            raise ArgumentError, 'duplicate normalized preset layer names'
          end

          entries.to_h.freeze
        end

        def folder_entry(name, patterns)
          unless name.is_a?(Symbol) || (name.is_a?(String) && !name.empty?)
            raise ArgumentError, 'preset layer names must be Symbols or non-empty Strings'
          end

          [name.to_s.dup.freeze, immutable_patterns(patterns)]
        end

        def immutable_patterns(value)
          patterns = value.is_a?(Array) ? value : [value]
          unless !patterns.empty? && patterns.all? { |item| valid_pattern?(item) }
            raise ArgumentError, 'preset folders must contain non-empty source globs'
          end

          patterns.map { |pattern| pattern.tr('\\', '/').freeze }.uniq.freeze
        end

        def valid_pattern?(value)
          value.is_a?(String) && !value.strip.empty?
        end
      end
    end
  end
end
