# frozen_string_literal: true

require 'archunit/extraction/declarations'
require 'archunit/classes/assertion/callable_shape'

RSpec.describe 'Declared callable shapes' do
  def accepts?(params, positional, keywords = [], block: :any)
    source = "class Command; def call(#{params}); end; end"
    facts = ArchUnit::Extraction::Declarations.collect(Prism.parse(source), file: 'command.rb')
    shape = ArchUnit::Classes::Assertion.const_get(:CallableShape)
    expected = ArchUnit::MethodSignature.new(name: :call, positional:, keywords:, block:)
    shape.matches?(facts.method_declarations.first.parameters, expected)
  end

  it 'accepts optional, destructured, rest and post positional parameters' do
    expect(accepts?('first, second = nil', 1)).to be(true)
    expect(accepts?('first, second = nil', 2)).to be(true)
    expect(accepts?('first, second = nil', 3)).to be(false)
    expect(accepts?('(left, right)', 1)).to be(true)
    expect(accepts?('head, *items, tail', 1)).to be(false)
    expect(accepts?('head, *items, tail', 12)).to be(true)
  end

  it 'requires all required keyword arguments and does not invent a named keyword interface' do
    expect(accepts?('x, actor:, request_id: nil', 1, %i[actor request_id])).to be(true)
    expect(accepts?('x, actor:, required:', 1, [:actor])).to be(false)
    expect(accepts?('x, **kwargs', 1, [:actor])).to be(true)
    expect(accepts?('x, **nil', 1, [:actor])).to be(false)
    expect(accepts?('x, **nil', 1)).to be(true)
    expect(accepts?('options', 0, [:actor])).to be(false)
    expect(accepts?('x, actor:', 1, %i[actor extra])).to be(false)
  end

  it 'recognizes explicit block capture and bounded shape forwarding' do
    expect(accepts?('head, ...', 0, [:actor])).to be(false)
    expect(accepts?('head, ...', 2, [:actor], block: :declared)).to be(true)
    expect(accepts?('a, &', 1, block: :declared)).to be(true)
    expect(accepts?('a', 1, block: :declared)).to be(false)
    expect(accepts?('a', 1)).to be(true)
  end
end
