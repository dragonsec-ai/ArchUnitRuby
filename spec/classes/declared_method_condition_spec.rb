# frozen_string_literal: true

require 'minitest'
require 'pathname'
require 'tmpdir'

RSpec.describe 'Declared method rules' do
  around do |example|
    Dir.mktmpdir('archunit-declared-method') do |directory|
      @root = Pathname.new(directory)
      @root.join('Gemfile').write("raise 'do not boot'")
      example.run
    ensure
      ArchUnit.clear_graph_cache
    end
  end

  def write(path, source)
    @root.join(path).write(source)
  end

  def scope
    ArchUnit.project_classes(@root).in_namespace('Commands')
  end

  def contract(**options)
    defaults = { name: :call, positional: 1, keywords: %i[actor request_id] }
    ArchUnit::MethodSignature.new(**defaults, **options)
  end

  def verify(**options)
    scope.should.declare_method(contract(**options))
  end

  it 'requires every selected class to declare a compatible shape, independent of file layout' do
    write('flat.rb', <<~RUBY)
      module Commands
        class Good; def call(id, actor:, request_id: nil); end; end
        class Missing; end
        class Wrong; def call(id, actor:, required:); end; end
      end
      raise 'do not execute target'
    RUBY
    findings = verify.check.map(&:finding)
    expect(findings.map { |f| [f.owner, f.reason] }).to eq(
      [['Commands::Missing', :missing_declaration], ['Commands::Wrong', :incompatible_signature]]
    )
    wrong = findings.last
    expect(wrong.candidates.first.site.file).to eq('flat.rb')
    expect(wrong.candidates.first.site.line).to eq(4)
    expect(ArchUnit.format_violations(verify.check)).to include('Commands::Wrong#call')
    expect(scope.with_constant_name('Commands::Good').should.declare_method(contract)).to pass
  end

  it 'can require either singleton syntax and does not equate an instance def with a singleton' do
    write('singleton.rb', <<~RUBY)
      module Commands
        class First; def self.call(*args, **kwargs); end; end
        class Second
          class << self
            def call(id, actor:, request_id:); end
          end
        end
      end
    RUBY
    expect(verify(scope: :singleton)).to pass
    reasons = verify.check.map { |violation| violation.finding.reason }
    expect(reasons).to all(eq(:missing_declaration))
  end

  it 'does not accept inherited, mixed-in, aliased or generated substitutes for a def' do
    write('dynamic.rb', <<~RUBY)
      class Parent; def call(...); end; end
      module Helpers; def call(...); end; end
      module Commands
        class Inherited < ::Parent; end
        class Mixed; include ::Helpers; end
        class Aliased; def invoke(...); end; alias call invoke; end
        class Generated; define_method(:call) { |*args, **keywords| }; end
        class CatchAll; def method_missing(...); end; end
      end
    RUBY
    findings = verify.check.map(&:finding)
    expected = %w[Aliased CatchAll Generated Inherited Mixed].map { |name| "Commands::#{name}" }
    expect(findings.map(&:owner)).to eq(expected)
    expect(findings.map(&:reason)).to all(eq(:missing_declaration))
  end

  it 'fails on conflicting reopens and conditional or receiver-unknown method candidates' do
    write('original.rb', <<~RUBY)
      module Commands
        class Reopened; def call(*, **); end; end
        class Conditional; def call(*, **); end if features?; end
        class Foreign; def target.call(*, **); end; end
      end
    RUBY
    write('reopen.rb', 'class Commands::Reopened; def call; end; end')
    results = verify.check(ArchUnit::CheckOptions.new(allow_empty_tests: true))
    expect(results).to all(be_unknown)
    expect(results.map { |result| result.finding.reason })
      .to eq(%i[uncertain_method_declaration uncertain_method_declaration conflicting_signatures])
    expect(results.last.finding.candidates.map { |method| method.site.file })
      .to eq(%w[original.rb reopen.rb])
  end

  it 'does not need reopen order when all written shapes accept the requested call' do
    write('original.rb', <<~RUBY)
      module Commands; class Run; def call(id, actor:, request_id:); end; end; end
    RUBY
    write('reopen.rb', 'class Commands::Run; def call(*, **); end; end')
    expect(verify).to pass
  end

  it 'uses opt-out only for known empty selection and keeps unresolved class selection failing' do
    write('first.rb', 'module Commands; class Child < ::Missing; end; end')
    empty = scope.with_constant_name('Commands::Other').should.declare_method(contract)
    allow_empty = ArchUnit::CheckOptions.new(allow_empty_tests: true)
    expect(empty.check.first).to be_a(ArchUnit::EmptyTestViolation)
    expect(ArchUnit::EmptyTestViolation.new(filters: [])).not_to eq(empty.check.first)
    expect(ArchUnit.format_violations(empty.check)).to include('No classes matched')
    expect(empty.check(allow_empty)).to be_empty
    unknown = scope.descendants_of('Missing').should.declare_method(contract)
    result = unknown.check(allow_empty).first
    expect(result).to be_unknown
    expect(result.finding).to have_attributes(reason: :unresolved_ancestry, ancestor: 'Missing')
  end

  it 'shares the declaration snapshot across rules and does no analysis while building them' do
    write('class.rb', 'module Commands; class Run; def call(*, **); end; end; end')
    expect(Prism).to receive(:parse).once.and_call_original
    first = verify
    second = scope.should.declare_method(contract(positional: 4))
    expect([scope, first, second, contract]).to all(be_frozen)
    expect(scope.class.instance_methods(false)).not_to include(:should_not)
    expect(first).to pass
    expect(second).to pass
  end

  it 'reports missing written methods through the shared Minitest assertion' do
    ArchUnit::Testing::MinitestAdapter.install!
    context = Class.new do
      include Minitest::Assertions

      attr_accessor :assertions
    end.new
    context.assertions = 0
    write('class.rb', 'module Commands; class Run; end; end')
    expect { context.assert_passes(verify) }.to raise_error(Minitest::Assertion, /Commands::Run#call/)
  end

  it 'owns validated signature values and normalizes keyword ordering' do
    key = +'actor'
    expected = contract(keywords: [:request_id, key, :actor])
    key.replace('user')
    expect(expected.keywords).to eq(%w[actor request_id])
    expect(expected.keywords).to be_frozen
    expect(expected.keywords).to all(be_frozen)
    [{ positional: -1 }, { keywords: :actor }, { name: '' }, { scope: :class },
     { block: true }].each do |invalid|
      expect { contract(**invalid) }.to raise_error(ArgumentError)
    end
    expect { scope.should.declare_method(:call) }.to raise_error(ArgumentError, /MethodSignature/)
  end
end
