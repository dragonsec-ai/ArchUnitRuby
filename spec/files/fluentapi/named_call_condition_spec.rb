# frozen_string_literal: true

require 'pathname'
require 'minitest'
require 'tmpdir'

RSpec.describe ArchUnit::Files::FluentApi::NamedCallCondition do
  around do |example|
    Dir.mktmpdir('archunit-named-calls') do |directory|
      @root = Pathname.new(directory)
      write('Gemfile', "raise 'do not load'")
      example.run
    ensure
      ArchUnit.clear_graph_cache
    end
  end

  def write(path, content)
    file = @root.join(path)
    file.dirname.mkpath
    file.write(content)
  end

  def scope
    ArchUnit.files(@root).in_path('queries/**')
  end

  def rule(names = :delete_all, options = nil)
    scope.should_not.contain_calls_named(names, options)
  end

  it 'distinguishes calls from definitions, comments, strings, and dynamic invocation' do
    write('queries/search.rb', <<~RUBY)
      class Search
        def delete_all; end
        def self.run(store)
          # delete_all
          "delete_all"
          store.send(:delete_all)
          store.read
        end
      end
      raise 'do not execute the source'
    RUBY
    expect(rule).to pass
    expect(scope.should).not_to respond_to(:contain_calls_named)
  end

  it 'records explicit, implicit, self, safe navigation and nested calls in source order' do
    write('queries/search.rb', <<~RUBY)
      class Search
        def delete_all; end
        def self.run(store)
          delete_all
          self.delete_all()
          store&.delete_all
          [store].each { |item| item.delete_all }
        end
      end
    RUBY
    results = rule.check.map(&:call)
    expect(results.map { |site| [site.line, site.column, site.receiver, site.safe_navigation] })
      .to eq([[4, 5, :bare, false], [5, 10, :self, false], [6, 12, :explicit, true],
              [7, 32, :explicit, false]])
    expect(results.map(&:file).uniq).to eq(['queries/search.rb'])
    bare = ArchUnit::NamedCallOptions.new(receiver: :bare)
    expect(rule(:delete_all, bare).check.map(&:call)).to eq([results.first])
  end

  it 'matches operator calls and repeated and nested names without altering the dependency graph' do
    write('queries/search.rb', 'store.update(store.update(1 + 2)); store[:key] = 42')
    original = ArchUnit::Extraction.extract_graph(@root)
    expected = %w[update update + []=]
    expect(rule(expected).check.map { |item| item.call.name }).to eq(expected)
    expect(ArchUnit::Extraction.extract_graph(@root)).to equal(original)
  end

  it 'validates the rule lazily and freezes independently owned names' do
    names = [+'delete_all', :delete_all]
    expect(ArchUnit::Extraction).not_to receive(:extract_named_calls)
    condition = rule(names)
    names.first.replace('safe')
    expect(condition.names.to_a).to eq(['delete_all'])
    expect(condition).to be_frozen
    expect(condition.names).to be_frozen
    expect { rule([]) }.to raise_error(ArgumentError, /at least one/)
    expect { rule(' ') }.to raise_error(ArgumentError, /method names/)
    expect { rule('read', :bare) }.to raise_error(ArgumentError, /NamedCallOptions/)
    expect { ArchUnit::NamedCallOptions.new(receiver: :self) }.to raise_error(ArgumentError)
  end

  it 'reuses parsing across rules and refreshes facts with clear_cache or global clearing' do
    write('queries/search.rb', 'store.delete_all')
    expect(Prism).to receive(:parse).exactly(3).times.and_call_original
    expect(rule.check.size).to eq(1)
    expect(rule(:read).check).to be_empty
    write('queries/search.rb', 'store.read')
    expect(rule.check.size).to eq(1)
    expect(rule.check(ArchUnit::CheckOptions.new(clear_cache: true))).to be_empty
    ArchUnit.clear_graph_cache
    expect(rule(:read).check.size).to eq(1)
  end

  it 'keeps non-selected syntax errors fatal and respects source exclusions and empty scopes' do
    write('queries/search.rb', 'store.delete_all')
    write('unrelated.rb', 'class Broken <')
    expect { rule.check }.to raise_error(ArchUnit::SourceParseError)
    covered = ArchUnit::CheckOptions.new(source_exclusions: ['unrelated.rb'])
    expect(rule.check(covered).size).to eq(1)
    excluded = covered.with(source_exclusions: %w[unrelated.rb queries/**])
    expect(rule.check(excluded).first).to be_a(ArchUnit::EmptyTestViolation)
    expect(rule.check(excluded.with(allow_empty_tests: true))).to eq([])
  end

  it 'gives the shared assertion formatter source coordinates and the method name' do
    write('queries/search.rb', 'store.delete_all')
    expect { ArchUnit.assert_passes(rule) }
      .to raise_error(%r{Forbidden method call 'delete_all'.*queries/search.rb:1:7}m)
    expect(rule).not_to pass
  end

  it 'uses the same evidence in Minitest assertions' do
    write('queries/search.rb', 'store.delete_all')
    ArchUnit::Testing::MinitestAdapter.install!
    context = Class.new do
      include Minitest::Assertions

      attr_accessor :assertions
    end.new
    context.assertions = 0
    expect { context.assert_passes(rule) }.to raise_error(Minitest::Assertion, /delete_all/)
  end
end
