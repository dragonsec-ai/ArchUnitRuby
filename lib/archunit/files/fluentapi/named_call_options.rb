# frozen_string_literal: true

module ArchUnit
  module Files
    module FluentApi
      # Controls whether a named-call restriction considers all receiver forms or only bare calls.
      NamedCallOptions = Data.define(:receiver) do
        # @param receiver [Symbol] :any or :bare (excluding every explicit receiver, even self)
        def initialize(receiver: :any)
          unless %i[any bare].include?(receiver)
            raise ArgumentError, 'receiver must be :any or :bare'
          end

          super
        end

        def self.resolve(options)
          return new if options.nil?
          return options if options.is_a?(self)

          raise ArgumentError, 'options must be a NamedCallOptions value or nil'
        end
      end
    end
  end
end
