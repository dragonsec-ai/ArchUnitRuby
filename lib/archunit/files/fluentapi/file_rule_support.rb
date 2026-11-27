# frozen_string_literal: true

require_relative '../../common/pattern_matching'
require_relative '../../common/logging/inspection'
require_relative '../../common/projection/project_to_nodes'

module ArchUnit
  module Files
    module FluentApi
      # Shared file selection for executable rule terminals.
      module FileRuleSupport
        module_function

        def selected_nodes(views, filters)
          nodes = views.nodes
          selected = filters.empty? ? nodes : matching_nodes(nodes, filters)
          Common::Logging::Inspection.selection(
            'selected file', selected, &:label
          )
        end

        def selected_paths(paths, filters)
          selected = paths.select do |path|
            Common::PatternMatching.matches_all_patterns?(path, filters)
          end
          Common::Logging::Inspection.selection('selected file', selected) { |path| path }
        end

        def matching_nodes(nodes, filters)
          nodes.select do |node|
            Common::PatternMatching.matches_all_patterns?(node.label, filters)
          end
        end
        private_class_method :matching_nodes
      end
    end
  end
end
