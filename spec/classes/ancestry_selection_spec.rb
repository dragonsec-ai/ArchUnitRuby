# frozen_string_literal: true

require 'archunit/classes/projection/ancestry_selection'

RSpec.describe 'Bounded ancestry traversal' do
  it 'classifies a deep chain iteratively and reuses its already visited suffix' do
    names = Array.new(15_000) { |index| "Node#{index}" }
    parents = names.each_cons(2).to_h.merge(names.last => nil)
    type = ArchUnit::Classes::Projection.const_get(:AncestrySelection)
    traversal = type.new(parents, names.last)
    expect(traversal.status(names.first)).to eq(:matched)
    expect(traversal.status(names.fetch(7000))).to eq(:matched)
    expect(traversal.status(names.last)).to eq(:not_matched)
  end
end
