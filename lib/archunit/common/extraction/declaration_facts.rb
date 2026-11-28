# frozen_string_literal: true

module ArchUnit
  module Common
    module Extraction
      # Internal immutable syntax facts. A location, rather than a name, owns method facts.
      # @api private
      module DeclarationFacts
        Site = Data.define(:file, :line, :column)
        Namespace = Data.define(:kind, :name, :written_name, :nesting, :context, :site)
        Method = Data.define(:name, :scope, :owner, :context, :site, :parameters)
        Parameter = Data.define(:kind, :name)
        Relationship = Data.define(:kind, :written_target, :owner, :context, :site)
        Inventory = Data.define(:namespaces, :method_declarations, :relationships)
      end
    end
  end
end
