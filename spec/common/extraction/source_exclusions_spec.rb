# frozen_string_literal: true

RSpec.describe 'immutable source-exclusion options' do
  it 'normalizes separators, anchors, directory globs and duplicates without mutation' do
    patterns = ['lib\\templates\\', './bad.rb', '/app/generated/', 'bad.rb']
    original = patterns.map(&:dup)
    options = ArchUnit::CheckOptions.new(source_exclusions: patterns)
    expect(options.source_exclusions).to eq(['/app/generated/**', 'bad.rb', 'lib/templates/**'])
    expect(options.source_exclusions).to be_frozen
    expect(options.source_exclusions).to all(be_frozen)
    expect(patterns).to eq(original)
    expect(patterns).not_to be_frozen
    expect(options.with(clear_cache: true).source_exclusions).to eq(options.source_exclusions)
    expect(ArchUnit::CheckOptions.new.source_exclusions).to eq([])
  end

  it 'uses recursive directory matching for an unanchored directory basename' do
    expect(ArchUnit::CheckOptions.new(source_exclusions: ['templates/']).source_exclusions)
      .to eq(['**/templates/**'])
  end

  [nil, 'templates', [''], ['  '], ['/'], ['./'], ['../bad.rb'], ['app/../bad.rb'],
   ['C:/absolute.rb'], ['//server/share'], ['!keep.rb'],
   ["bad\0.rb"], ["bad\n.rb"], [123]].each do |value|
    it "rejects invalid/non-additive caller policy #{value.inspect}" do
      expect { ArchUnit::CheckOptions.new(source_exclusions: value) }
        .to raise_error(ArgumentError, /source_exclusions/)
    end
  end
end
