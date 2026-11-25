# frozen_string_literal: true

require 'pathname'
require 'json'

module ArchUnit
  module CLI
    # Scope settings prevent an imports-only acceptance from hiding expanded-analysis findings.
    # @api private
    module BaselineContext
      def self.for(name, analysis, project_root)
        scopes = analysis[:scopes].select { |scope| scope[:rule_names].include?(name) }
        return if scopes.empty? || scopes.any? { |scope| scope[:status] != 'analyzed' }

        contexts = scopes.map { |scope| settings(scope, project_root) }.uniq
        contexts.sort_by { |item| JSON.generate(item) }
      end

      def self.settings(scope, root)
        context = {
          'root' => relative(scope[:project_root], root), 'kind' => scope[:kind],
          'dependency_analysis' => scope[:dependency_analysis],
          'rails_imports' => scope[:rails_imports], 'load_paths' => load_paths(scope),
          'source_exclusions' => scope[:effective_source_exclusions]
        }
        context['rails_associations'] = true if scope[:rails_associations]
        context
      end

      def self.relative(path, root)
        Pathname.new(path).relative_path_from(Pathname.new(root).realpath).to_s.tr('\\', '/')
      end

      def self.load_path(path, root)
        Pathname.new(path).absolute? ? relative(path, root) : path
      end

      def self.load_paths(scope)
        scope[:load_paths]&.map { |path| load_path(path, scope[:project_root]) }&.sort
      end
      private_class_method :settings, :relative, :load_path, :load_paths
    end
  end
end
