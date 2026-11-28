# frozen_string_literal: true

require_relative '../../common/assertion/empty_test_violation'

module ArchUnit
  module Classes
    module Assertion
      # The ordinary empty-test defense with the actual class selector attached.
      class EmptyClassSelectionViolation < Common::Assertion::EmptyTestViolation
        attr_reader :scope

        def initialize(scope)
          @scope = scope
          super(filters: [])
        end

        def ==(other)
          other.instance_of?(self.class) && scope == other.scope
        end
        alias eql? ==

        def hash
          [self.class, scope].hash
        end
      end
    end
  end
end
