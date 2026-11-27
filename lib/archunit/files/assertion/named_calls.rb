# frozen_string_literal: true

require_relative '../../common/assertion/violation'
require_relative '../../common/extraction/call_site'

module ArchUnit
  module Files
    # Rules and violations over already extracted call sites.
    module Assertion
      # One forbidden direct call site, with its coordinates and receiver form.
      class NamedCallViolation < Common::Assertion::Violation
        attr_reader :call

        def initialize(call:)
          unless call.is_a?(Common::Extraction::CallSite)
            raise ArgumentError, 'call must be a CallSite'
          end

          @call = call
          super()
        end

        def ==(other)
          other.is_a?(self.class) && call == other.call
        end
        alias eql? ==

        def hash
          [self.class, call].hash
        end
      end

      module_function

      def gather_named_call_violations(calls, names, receiver:)
        calls.filter_map do |call|
          next unless names.include?(call.name) && (receiver == :any || call.receiver == :bare)

          NamedCallViolation.new(call:)
        end
      end
    end
  end
end
