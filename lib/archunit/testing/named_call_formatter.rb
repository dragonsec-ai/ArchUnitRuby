# frozen_string_literal: true

require_relative 'test_violation'

module ArchUnit
  module Testing
    # Presents precise source coordinates without claiming what Ruby dispatches at runtime.
    module NamedCallFormatter
      private

      def named_call(violation)
        call = violation.call
        TestViolation.new(
          message: "Forbidden method call '#{call.name}'",
          details: "#{call.file}:#{call.line}:#{call.column} (#{call.receiver} receiver)."
        )
      end
    end
  end
end
