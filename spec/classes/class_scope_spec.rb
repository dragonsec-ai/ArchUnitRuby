# frozen_string_literal: true

require 'archunit/cli'
require 'pathname'
require 'stringio'
require 'tmpdir'

RSpec.describe 'Declaration-backed class selectors' do
  around do |example|
    Dir.mktmpdir('archunit-class-selectors') do |dir|
      @root = Pathname.new(dir)
      @root.join('Gemfile').write("raise 'must not boot target'")
      example.run
    ensure
      ArchUnit.clear_graph_cache
    end
  end

  def write(relative, source)
    file = @root.join(relative)
    file.dirname.mkpath
    file.write(source)
  end

  def classes
    ArchUnit.project_classes(@root)
  end

  it 'selects exact classes, not modules or similarly prefixed namespaces, across files' do
    write('not_billing/a.rb', 'module Billing; class Invoice; def call(a); end; end; end')
    write('not_billing/b.rb', 'class Billing::Invoice; def self.build; end; end')
    write('edge.rb', 'module BillingTools; class Invoice; end; end; module Billing::Reports; end')
    write('deep.rb', 'module Billing::Reports; class Export; end; end')
    result = classes.in_namespace('::Billing').selection
    expect(result.status).to eq(:complete)
    expect(result.matches.map(&:name)).to eq(%w[Billing::Invoice Billing::Reports::Export])
    invoice = classes.with_constant_name('::Billing::Invoice').in_namespace('Billing').selection
    match = invoice.matches.first
    expect(match.declarations.map { |decl| decl.site.file })
      .to eq(%w[not_billing/a.rb not_billing/b.rb])
    expect(match.method_declarations.map(&:name)).to eq(%i[call build])
    expect([invoice, match, match.declarations, match.method_declarations]).to all(be_frozen)
    expect(classes.with_constant_name('Billing').selection.status).to eq(:empty)
  end

  it 'retains ambiguous, conditional and unresolved declarations rather than passing them' do
    write('mixed.rb', <<~RUBY)
      class Known; end
      class Mixed; end
      module Mixed; end
      class Conditional; end if feature?
      module Outer; class Relative::Unclear; end; end
    RUBY
    result = classes.selection
    expect(result.status).to eq(:unknown)
    expect(result.matches.map(&:name)).to eq(['Known'])
    expect(result.uncertainties.map { |value| [value.name, value.reason] }).to eq(
      [['Conditional', :conditional_or_dynamic_declaration],
       ['Mixed', :conflicting_declaration_kind], [nil, :unresolved_owner]]
    )
    expect(classes.with_constant_name('Tester::Unclear').selection.status).to eq(:unknown)
    expect(classes.with_constant_name('Tester::Unrelated').selection.status).to eq(:empty)
    expect(classes.with_constant_name('Known').with_constant_name('Mixed').selection.status)
      .to eq(:empty)
  end

  it 'selects bounded transitive superclass links without using mixins or inferring Object' do
    write('relations.rb', <<~RUBY)
      class Root < ::Outside; end
      class Independent; end
      module App
        class Base < ::Root; end
        class Middle < Base; end
        class Leaf < ::App::Middle; end
        class Unrelated; include ::Root; end
      end
    RUBY
    result = classes.in_namespace('App').descendants_of('::Root').selection
    expect(result.status).to eq(:complete)
    expect(result.matches.map(&:name)).to eq(%w[App::Base App::Leaf App::Middle])
    expect(result.matches.first.relationships.first.written_target).to eq('::Root')
    expect(classes.with_constant_name('Independent').descendants_of('Object').selection.status)
      .to eq(:empty)
    expect(classes.with_constant_name('Root').descendants_of('Outside').selection.status)
      .to eq(:unknown)
  end

  it 'does not turn an unknown superclass, conflicting reopens or cycles into ancestry matches' do
    write('edges.rb', <<~RUBY)
      class Target; end
      class Other; end
      class Dynamic < select_base; end
      class Conflict < Target; end
      class Conflict < Other; end
      class CycleA < CycleB; end
      class CycleB < CycleA; end
      class ChildOfCycle < CycleA; end
      module App
        module Target; end
        class Masked < Target; end
        class Missing < Other; end
      end
    RUBY
    result = classes.descendants_of('Target').selection
    expect(result.matches).to be_empty
    expect(result.status).to eq(:unknown)
    expected = [
      ['App::Masked', :unresolved_ancestry], ['App::Missing', :unresolved_ancestry],
      ['ChildOfCycle', :cyclic_ancestry], ['Conflict', :unresolved_ancestry],
      ['CycleA', :cyclic_ancestry], ['CycleB', :cyclic_ancestry],
      ['Dynamic', :unresolved_ancestry]
    ]
    expect(result.uncertainties.map { |fact| [fact.name, fact.reason] }).to eq(expected)
    cycle = classes.with_constant_name('ChildOfCycle').descendants_of('CycleA').selection
    expect(cycle.uncertainties.map(&:reason)).to eq([:cyclic_ancestry])
  end

  it 'keeps construction lazy and rejects patterns in exact selectors' do
    write('billing.rb', 'module Billing; class Invoice; end; end')
    base = classes
    expect(ArchUnit::Extraction).not_to receive(:extract_declarations)
    selection = base.in_namespace('Billing')
    expect(base).to be_frozen
    expect(selection).to be_frozen
    expect(selection).not_to equal(base)
    expect { base.with_constant_name('Billing::*') }.to raise_error(ArgumentError)
    expect { base.in_namespace('::') }.to raise_error(ArgumentError)
    expect { base.descendants_of(nil) }.to raise_error(ArgumentError)
  end

  it 'uses only in-scope source sites to establish a superclass' do
    write('base.rb', 'class Parent; end')
    write('child.rb', 'class Child < ::Parent; end')
    scope = classes.with_constant_name('Child').descendants_of('Parent')
    expect(scope.selection.matches.map(&:name)).to eq(['Child'])
    options = ArchUnit::CheckOptions.new(source_exclusions: ['base.rb'])
    result = scope.selection(options)
    expect(result.status).to eq(:unknown)
    expect(result.uncertainties.map(&:ancestor)).to eq(['Parent'])
  end

  it 'does not resolve ancestry through a class or namespace rebound by a constant write' do
    write('bindings.rb', <<~RUBY)
      class Direct; end
      Direct = replacement
      module Billing
        class Base; end
      end
      ::Billing = other_namespace
      class Child < ::Billing::Base; end
    RUBY
    direct = classes.with_constant_name('Direct').selection
    expect(direct.uncertainties.first.reason).to eq(:conflicting_constant_write)
    base = classes.with_constant_name('Billing::Base').selection
    expect(base.uncertainties.first.reason).to eq(:uncertain_namespace_owner)
    child = classes.with_constant_name('Child').descendants_of('Billing::Base').selection
    expect(child.uncertainties.first.reason).to eq(:unresolved_ancestry)
  end

  it 'uses the same warm inventory between selectors and separates exclusions and refreshes' do
    write('class.rb', 'class Alpha; end')
    scope = classes
    name = +'Alpha'
    alpha = scope.with_constant_name(name)
    name.replace('Beta')
    expect(Prism).to receive(:parse).exactly(3).times.and_call_original
    expect(alpha.selection.matches.map(&:name)).to eq(['Alpha'])
    expect(scope.with_constant_name('Beta').selection.status).to eq(:empty)
    write('class.rb', 'class Beta; end')
    expect(alpha.selection.status).to eq(:complete)
    excluded = ArchUnit::CheckOptions.new(source_exclusions: ['class.rb'])
    expect(alpha.selection(excluded).status).to eq(:empty)
    expect(alpha.selection(ArchUnit::CheckOptions.new(clear_cache: true)).status).to eq(:empty)
    ArchUnit.clear_graph_cache
    expect(scope.selection.matches.map(&:name)).to eq(['Beta'])
  end

  it 'records its own cache-aware analysis scope and never caches a failed analysis' do
    write('broken.rb', 'class Broken <')
    report = ArchUnit::CLI::AnalysisReport.new
    ArchUnit::Extraction::AnalysisObserver.capture(report) do
      expect { classes.selection }.to raise_error(ArchUnit::SourceParseError)
      write('broken.rb', 'class Fixed; end')
      expect(classes.selection.status).to eq(:complete)
      expect(classes.with_constant_name('Fixed').selection.status).to eq(:complete)
    end
    expect(report.to_h[:scopes]).to contain_exactly(
      include(kind: 'source_declarations', status: 'error', cache_hits: 0),
      include(kind: 'source_declarations', status: 'analyzed', cache_hits: 1, observations: 2)
    )
    output = StringIO.new
    ArchUnit::CLI::AnalysisText.write(report.to_h, output)
    expect(output.string).to include('source declarations (dependency analysis unavailable)')
  end
end
