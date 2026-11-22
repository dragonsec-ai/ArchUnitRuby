# frozen_string_literal: true

module SemanticStudy
  # Optional exact published comparator. Never added to production gem dependencies.
  module Comparator
    def self.load
      gem 'archspec', '= 1.1.0'
      gem 'rubydex', '= 0.4.0'
      require 'archspec'
    end

    def self.facts(root, specification)
      kind = specification.fetch('comparator_policy')
      definition = definition(kind, specification['selector'])
      graph = ArchSpec::Analyzer.analyze(definition, root:)
      diagnostics = ArchSpec::Evaluator.evaluate(definition, graph)
      { policy: kind, selector: specification['selector'], rules: diagnostics.map(&:rule),
        version: ArchSpec::VERSION, rubydex: Gem.loaded_specs.fetch('rubydex').version.to_s }
    end

    def self.definition(kind, selector)
      settings = component_settings(selector)
      definition = ArchSpec.define do
        source '**/*.rb'
        component :api, **settings
        component :db, in: 'app/db/**/*.rb'
      end
      attach_policy(definition.api, kind)
      definition
    end

    def self.attach_policy(api, kind)
      case kind
      when 'method' then api.cannot_call :delete_all, receiver: 'Db::Store'
      when 'method_name' then api.cannot_call :delete_all
      when 'protocol' then api.must_implement :call, arity: 1, keywords: [:context]
      else api.cannot_use :db
      end
    end

    def self.component_settings(selector)
      case selector
      when 'namespace' then { namespace: 'Api' }
      when 'constant' then { constants: ['Api::Request'] }
      when 'descendant' then { descendants_of: 'Base' }
      else { in: 'app/api/**/*.rb' }
      end
    end
    private_class_method :definition, :attach_policy, :component_settings
  end
end
