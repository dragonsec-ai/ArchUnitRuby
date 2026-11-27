# frozen_string_literal: true

require_relative '../static_constant_name'
require_relative 'parameters'
require_relative 'scope'

module ArchUnit
  module Extraction
    # Opt-in, read-only extraction over accepted Prism parse results.
    module Declarations
      # Records written declarations without resolving what Ruby defines at runtime.
      class Collector
        include StaticConstantName

        Facts = Common::Extraction::DeclarationFacts
        CONDITIONAL = %i[
          if_node unless_node while_node until_node for_node case_node case_match_node
          rescue_node rescue_modifier_node else_node ensure_node and_node or_node
        ].freeze
        DYNAMIC = %i[block_node lambda_node].freeze
        MIXINS = %i[include prepend extend].freeze
        private_constant :Facts, :CONDITIONAL, :DYNAMIC, :MIXINS

        def initialize(file)
          @file = file.dup.freeze
          @namespaces = []
          @methods = []
          @relationships = []
        end

        def collect(tree)
          pending = [[tree, Scope.root]]
          until pending.empty?
            node, scope = pending.pop
            advance(node, scope, pending)
          end
          Facts::Inventory.new(namespaces: @namespaces.freeze, method_declarations: @methods.freeze,
                               relationships: @relationships.freeze)
        end

        private

        def advance(node, scope, pending)
          case node
          when Prism::ClassNode, Prism::ModuleNode
            add_body(pending, node.body, collect_namespace(node, scope))
          when Prism::DefNode
            add_body(pending, node.body, method_body_scope(node, scope))
          when Prism::SingletonClassNode
            add_body(pending, node.body, scope.within_singleton(node.expression))
          else
            advance_children(node, scope, pending)
          end
        end

        def add_body(pending, body, scope)
          pending << [body, scope] if body
        end

        def advance_children(node, scope, pending)
          collect_mixins(node, scope) if node.is_a?(Prism::CallNode)
          scope = nested_context(node, scope)
          node.compact_child_nodes.reverse_each { |child| pending << [child, scope] }
        end

        def nested_context(node, scope)
          return scope.with(context: :dynamic) if DYNAMIC.include?(node.type)
          return scope.conditional if CONDITIONAL.include?(node.type)

          scope
        end

        def collect_namespace(node, scope)
          namespace = namespace_fact(node, scope)
          @namespaces << namespace
          inner = scope.inside(namespace)
          superclass = node.superclass if namespace.kind == :class
          relationship(:superclass, superclass, inner) if superclass
          inner
        end

        def namespace_fact(node, scope)
          kind = node.is_a?(Prism::ClassNode) ? :class : :module
          written = static_name(node.constant_path)&.freeze
          Facts::Namespace.new(
            kind:, name: scope.qualify(written), written_name: written,
            nesting: scope.nesting, context: scope.context, site: site(node.constant_path.location)
          )
        end

        def method_body_scope(node, scope)
          @methods << Facts::Method.new(
            name: node.name, scope: scope.method_scope(node.receiver), owner: scope.owner,
            context: scope.context, site: site(node.name_loc),
            parameters: Parameters.collect(node.parameters)
          )
          scope.with(context: :dynamic)
        end

        def collect_mixins(node, scope)
          return unless scope.owner && scope.singleton == :none && mixin_call?(node)

          node.arguments&.arguments&.each { |argument| relationship(node.name, argument, scope) }
        end

        def mixin_call?(node)
          MIXINS.include?(node.name) && (node.receiver.nil? || node.receiver.is_a?(Prism::SelfNode))
        end

        def relationship(kind, node, scope)
          @relationships << Facts::Relationship.new(
            kind:, written_target: static_name(node)&.freeze, owner: scope.owner,
            context: scope.context, site: site(node.location)
          )
        end

        def site(location)
          Facts::Site.new(file: @file, line: location.start_line, column: location.start_column + 1)
        end
      end
      private_constant :Collector
    end
  end
end
