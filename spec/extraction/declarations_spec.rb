# frozen_string_literal: true

require 'archunit/extraction/declarations'
require 'tmpdir'

RSpec.describe ArchUnit::Extraction::Declarations do
  def collect(source, file: 'app/billing.rb')
    described_class.collect(Prism.parse(source), file:)
  end

  it 'distinguishes syntactic lexical nesting, explicit paths, and ambiguous relative owners' do
    facts = collect(<<~RUBY)
      module Billing
        class Invoice; end
        class ::Shared::Adapter; end
        class Commands::Import
          class Detail; end
        end
      end
      class Billing::Invoice; end
      class Commands::Query; end
    RUBY
    observations = facts.namespaces.map { |fact| [fact.kind, fact.name, fact.nesting] }
    expect(observations).to eq([
                                 [:module, 'Billing', []],
                                 [:class, 'Billing::Invoice', ['Billing']],
                                 [:class, 'Shared::Adapter', ['Billing']],
                                 [:class, nil, ['Billing']],
                                 [:class, nil, [nil, 'Billing']],
                                 [:class, 'Billing::Invoice', []],
                                 [:class, 'Commands::Query', []]
                               ])
    expect(facts.namespaces[3].written_name).to eq('Commands::Import')
    expect(facts.namespaces[2].site.to_h).to eq(file: 'app/billing.rb', line: 3, column: 9)
  end

  it 'records conditional and block-based declarations without treating them as certain' do
    facts = collect(<<~RUBY)
      if enabled?
        class Optional; end
      else
        class Alternative; end
      end
      register do
        module Dynamic
          class Nested; end
        end
      end
      module Features
        class lookup()::Extension; end
      end
    RUBY
    expected = [
      ['Optional', :conditional], ['Alternative', :conditional], ['Dynamic', :dynamic],
      ['Dynamic::Nested', :dynamic], ['Features', :direct], [nil, :direct]
    ]
    expect(facts.namespaces.map { |fact| [fact.name, fact.context] }).to eq(expected)
    expect(facts.namespaces.last.written_name).to be_nil
  end

  it 'keeps exact declaration sites on written class, instance and unknown-scope methods' do
    facts = collect(<<~RUBY)
      def top_level; end
      module Billing
        def instance; end
        def self.singleton; end
        def other.unknown; end
        class << self
          def on_metaclass; end
          def self.not_on_billing; end
        end
        class << other
          def not_owned; end
        end
      end
    RUBY
    expected = [
      %i[top_level unknown direct], %i[instance instance direct],
      %i[singleton singleton direct], %i[unknown unknown direct],
      %i[on_metaclass singleton direct], %i[not_on_billing unknown direct],
      %i[not_owned unknown dynamic]
    ]
    expect(facts.method_declarations.map { |m| [m.name, m.scope, m.context] }).to eq(expected)
    expect(facts.method_declarations.first.owner).to be_nil
    expect(facts.method_declarations.drop(1).map(&:owner)).to all(eq(facts.namespaces.first.site))
  end

  it 'represents parameter shapes without running expressions or expanding forwarding' do
    facts = collect(<<~RUBY)
      class Command
        def call(a, b = raise, *extra, tail, force:, limit: raise, **opts, &block); end
        def forward(...); end
        def no_keywords(**nil); end
        def destructure((left, right)); end
        def anonymous(*, **, &); end
        def plain; end
      end
    RUBY
    signatures = facts.method_declarations.to_h do |method|
      [method.name, method.parameters.map { |param| [param.kind, param.name] }]
    end
    expect(signatures).to eq(
      call: [%i[required a], %i[optional b], %i[rest extra], %i[post tail],
             %i[required_keyword force], %i[optional_keyword limit], %i[keyword_rest opts],
             %i[block block]],
      forward: [[:forwarding, nil]], no_keywords: [[:no_keywords, nil]],
      destructure: [[:destructured, nil]], anonymous: [[:rest, nil], [:keyword_rest, nil],
                                                       [:block, nil]],
      plain: []
    )
  end

  it 'retains static and unresolved written relationships instead of resolving targets' do
    facts = collect(<<~RUBY)
      class Invoice < build_parent()
        include ::Billing::Audit, build_mixin()
        self.prepend Decorator
        extend OwnClassMethods if enabled?
        another.include Ignored
        class Entry < ::Record
        end
      end
    RUBY
    expected = [
      [:superclass, nil, :direct], [:include, '::Billing::Audit', :direct],
      [:include, nil, :direct], [:prepend, 'Decorator', :direct],
      [:extend, 'OwnClassMethods', :conditional], [:superclass, '::Record', :direct]
    ]
    observed = facts.relationships.map { |ref| [ref.kind, ref.written_target, ref.context] }
    expect(observed).to eq(expected)
    expect(facts.relationships.last.owner).to eq(facts.namespaces.last.site)
  end

  it 'rejects malformed parse results rather than returning a partial inventory' do
    expect { collect("class Known; end\nclass Broken <") }
      .to raise_error(ArchUnit::SourceParseError, %r{app/billing.rb:2})
  end

  it 'returns immutable nested provenance without keeping the caller’s identifier by reference' do
    file = +'app/foo.rb'
    facts = collect('class C < B; def x(arg); end; end', file:)
    file.replace('altered.rb')
    expect(facts).to be_frozen
    expect(facts.to_h.values).to all(be_frozen)
    namespace = facts.namespaces.first
    expect([namespace, namespace.name, namespace.nesting, namespace.site.file]).to all(be_frozen)
    expect(namespace.site.file).to eq('app/foo.rb')
    expect(facts.method_declarations.first.parameters).to be_frozen
    expect(facts.relationships.first.written_target).to be_frozen
  end

  it 'walks multiple roots separately and preserves all reopens and conflicting definitions' do
    Dir.mktmpdir('archunit-declarations') do |base|
      root = Pathname.new(base)
      first = fixture(root.join('first'), 'module Billing; class Invoice; end; end')
      second = fixture(root.join('second'), 'class Unrelated; end')
      first.join('b.rb').write('class Billing::Invoice; def call; end; end')
      first.join('c.rb').write('module Billing::Invoice; end')
      expect(Prism).to receive(:parse).exactly(5).times.and_call_original
      facts = ArchUnit::Extraction.extract_declarations(first)
      invoices = facts.namespaces.select { |item| item.name == 'Billing::Invoice' }
      expect(invoices.map { |item| [item.kind, item.site.file] })
        .to eq([[:class, 'a.rb'], [:class, 'b.rb'], [:module, 'c.rb']])
      options = ArchUnit::CheckOptions.new(source_exclusions: %w[b.rb c.rb])
      limited = ArchUnit::Extraction.extract_declarations(first, options:)
      expect(limited.namespaces.map(&:name)).to eq(%w[Billing Billing::Invoice])
      expect(limited.method_declarations).to be_empty
      expect(ArchUnit::Extraction.extract_declarations(second).namespaces.map(&:name))
        .to eq(['Unrelated'])
    end
  end

  def fixture(root, source)
    root.mkpath
    root.join('Gemfile').write("raise 'do not run the project Gemfile'")
    root.join('a.rb').write("#{source}\nraise 'do not run the project source'")
    root
  end
end
