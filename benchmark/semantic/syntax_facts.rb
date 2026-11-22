# frozen_string_literal: true

require 'prism'

module SemanticStudy
  # Probe-only syntax inventory: deliberately no receiver/type/ancestry inference.
  class SyntaxFacts < Prism::Visitor
    attr_reader :calls, :methods, :superclasses

    def initialize
      super
      @calls = []
      @methods = []
      @superclasses = []
    end

    def visit_call_node(node)
      calls << { name: node.name, receiver_node: node.receiver&.class&.name,
                 resolved_runtime_receiver: nil }
      super
    end

    def visit_def_node(node)
      methods << { name: node.name, parameters_node: node.parameters&.class&.name }
      super
    end

    def visit_class_node(node)
      superclasses << node.superclass.slice if node.superclass
      super
    end
  end
end
