# frozen_string_literal: true

require_relative 'preset_options'
require_relative 'preset_definitions'
require_relative 'preset_rule'

# Public preset entry point composed from the existing named-layer vocabulary.
module ArchUnit
  module Layers
    module FluentApi
      # Composes named-layer builders, so presets share all existing extraction/assertion semantics.
      # @api private
      module ArchitecturePreset
        def self.build(name, options = nil)
          options = PresetOptions.resolve(options)
          folders = PresetDefinitions.folders(name, options.folders)
          architecture = define_layers(folders, options.project_locator)
          policy = apply_policy(architecture, name)
          PresetRule.new(name:, architecture: policy)
        end

        def self.apply_policy(architecture, name)
          dependencies = PresetDefinitions::ALLOWED.fetch(name)
          dependencies.reduce(architecture) do |rule, (source, targets)|
            rule.where_layer(source).may_only_depend_on_layers(*targets)
          end
        end

        def self.define_layers(folders, locator)
          architecture = LayeredArchitecture.new(project_locator: locator)
          folders.reduce(architecture) do |rule, (name, patterns)|
            Array(patterns).reduce(rule) do |current, pattern|
              current.layer(name).defined_by(pattern)
            end
          end
        end
        private_class_method :define_layers, :apply_policy
      end
    end
  end

  # Starts a completed layered, hexagonal, or Rails folder policy.
  # @param name [Symbol] :layered, :hexagonal or :rails
  # @param options [Layers::FluentApi::PresetOptions, nil] source locator/pattern overrides
  # @return [Layers::FluentApi::PresetRule] lazy, immutable Checkable
  def self.architecture_preset(name, options = nil)
    Layers::FluentApi::ArchitecturePreset.build(name, options)
  end
end
