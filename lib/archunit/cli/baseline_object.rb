# frozen_string_literal: true

module ArchUnit
  module CLI
    # JSON duplicate members are ambiguous configuration, not a last-key-wins policy.
    # @api private
    class BaselineObject < Hash
      def []=(key, value)
        raise ArgumentError, "duplicate baseline JSON member: #{key}" if key?(key)

        super
      end
    end
  end
end
