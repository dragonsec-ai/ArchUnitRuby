# frozen_string_literal: true

module ArchUnit
  module Layers
    module FluentApi
      # Small opinionated policies, not a claim to recognize an application's architecture.
      # @api private
      module PresetDefinitions
        FOLDERS = {
          layered: { 'presentation' => 'app/api/**', 'application' => 'app/services/**',
                     'persistence' => 'app/db/**' }.freeze,
          hexagonal: { 'domain' => 'app/domain/**', 'application' => 'app/application/**',
                       'adapters' => 'app/adapters/**' }.freeze,
          rails: { 'controllers' => 'app/controllers/**', 'services' => 'app/services/**',
                   'models' => 'app/models/**' }.freeze
        }.freeze
        ALLOWED = {
          layered: { 'presentation' => %w[application].freeze,
                     'application' => %w[persistence].freeze, 'persistence' => [].freeze }.freeze,
          hexagonal: { 'domain' => [].freeze, 'application' => %w[domain].freeze,
                       'adapters' => %w[application domain].freeze }.freeze,
          rails: { 'controllers' => %w[services models].freeze, 'services' => %w[models].freeze,
                   'models' => [].freeze }.freeze
        }.freeze

        def self.folders(name, overrides)
          defaults = FOLDERS.fetch(name) do
            raise ArgumentError, "unknown architecture preset: #{name}"
          end
          unknown = overrides.keys - defaults.keys
          raise ArgumentError, "unknown preset layers: #{unknown.join(', ')}" unless unknown.empty?

          defaults.merge(overrides)
        end
      end
      private_constant :PresetDefinitions
    end
  end
end
