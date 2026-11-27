# frozen_string_literal: true

module ArchUnit
  module Classes
    # All contributing in-scope sites for one class constant, not its runtime method table.
    DeclaredClass = Data.define(:name, :declarations, :method_declarations, :relationships)
    # What prevents a fact or class from being selected decisively.
    UncertainClass = Data.define(:name, :declarations, :reason, :ancestor)

    # Inspection result. An unknown selection may include some definite matches.
    ClassSelection = Data.define(:matches, :uncertainties) do
      def status
        return :unknown unless uncertainties.empty?

        matches.empty? ? :empty : :complete
      end
    end
  end
end
