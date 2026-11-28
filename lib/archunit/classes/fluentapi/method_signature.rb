# frozen_string_literal: true

module ArchUnit
  # Immutable expected call shape for a declared-method rule.
  MethodSignature = Data.define(:name, :positional, :keywords, :scope, :block) do
    # @param name [String, Symbol] exact Ruby method name
    # @param positional [Integer] number of positional arguments passed
    # @param keywords [Array<String, Symbol>] exact keyword names passed
    # @param scope [Symbol] :instance or :singleton
    # @param block [Symbol] :any or :declared block parameter/forwarding shape
    def initialize(name:, positional: 0, keywords: [], scope: :instance, block: :any)
      name = normalized_name(name)
      keywords = normalized_keywords(keywords)
      validate_shape(positional, scope, block)
      super
    end

    private

    def normalized_name(value)
      name = value.to_s if value.is_a?(String) || value.is_a?(Symbol)
      return name.dup.freeze if valid_name?(name)

      raise ArgumentError, 'method and keyword names must be non-blank Strings or Symbols'
    end

    def valid_name?(name)
      name&.encoding&.ascii_compatible? && name.valid_encoding? &&
        !name.strip.empty? && !name.match?(/[[:cntrl:]]/)
    end

    def normalized_keywords(values)
      raise ArgumentError, 'keywords must be an Array of names' unless values.is_a?(Array)

      values.map { |value| normalized_name(value) }.uniq.sort.freeze
    end

    def validate_shape(count, scope, block)
      unless count.is_a?(Integer) && count >= 0
        raise ArgumentError, 'positional must be a non-negative Integer'
      end
      unless %i[instance singleton].include?(scope)
        raise ArgumentError, 'scope must be :instance or :singleton'
      end
      return if %i[any declared].include?(block)

      raise ArgumentError, 'block must be :any or :declared'
    end
  end
end
