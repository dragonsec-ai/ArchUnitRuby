# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tmpdir'

RSpec.describe 'qualified declaration namespace dependencies' do
  let(:options) { ArchUnit::CheckOptions.new(dependency_analysis: :imports_and_constants) }

  around do |example|
    Dir.mktmpdir('archunit-namespace-receivers') do |directory|
      @root = File.realpath(directory)
      source('Gemfile', "raise 'must not execute'\n")
      ArchUnit.clear_graph_cache
      example.run
    ensure
      ArchUnit.clear_graph_cache
    end
  end

  def source(path, contents)
    file = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, contents)
  end

  def edges(profile: nil)
    ArchUnit::Extraction.extract_graph(@root, options:, profile:).reject do |edge|
      edge.source == edge.target
    end
  end

  def scope
    ArchUnit.project_files(@root).in_path('app/api/**')
  end

  ['class %s::Service; end', 'module %s::Service; end', '%s::VALUE = 42',
   '%s::VALUE ||= 42'].product(%w[Db ::Db]).each do |form, receiver|
    it "models the namespace read in #{format(form, receiver)}" do
      source('app/db/namespace.rb', "\nmodule Db; end\nraise 'must not execute'\n")
      source('app/api/request.rb', "\n#{format(form, receiver)}\nraise 'must not execute'\n")
      attributes = {
        source: 'app/api/request.rb', target: 'app/db/namespace.rb',
        import_kinds: [:constant_reference],
        evidence: contain_exactly(have_attributes(name: receiver, line_number: 2,
                                                  end_line: 2, target_line_number: 2))
      }
      expect(edges).to contain_exactly(have_attributes(attributes))
      forbidden = scope.should_not.depend_on_files.in_path('app/db/**')
      expect(forbidden.check(options).length).to eq(1)
      ArchUnit.assert_passes(scope.should.depend_on_files.in_path('app/db/**'), options)
      expect(forbidden.check).to be_empty
    end
  end

  it 'reads only the direct namespace receiver, not the newly declared constant or every prefix' do
    source('app/db/namespace.rb', "module Db\n  module Nested; end\nend\n")
    source('app/api/request.rb', 'class ::Db::Nested::Service; end')
    evidence = contain_exactly(have_attributes(name: '::Db::Nested', target_line_number: 2))
    expect(edges).to contain_exactly(have_attributes(evidence:))
  end

  it 'resolves the receiver in the enclosing lexical scope before entering the new namespace' do
    source('app/db/namespace.rb', 'module Outer; module Db; end; end')
    source('lib/root_db.rb', 'module Db; end')
    source('app/api/request.rb', 'module Outer; class Db::Service; end; end')
    expect(edges).to contain_exactly(have_attributes(target: 'app/db/namespace.rb'))
  end

  it 'preserves root qualification when an enclosing lexical owner shadows the name' do
    source('app/db/namespace.rb', 'module Db; end')
    source('lib/nested_db.rb', 'module Outer; module Db; end; end')
    source('app/api/request.rb', 'module Outer; class ::Db::Service; end; end')
    expect(edges).to contain_exactly(have_attributes(target: 'app/db/namespace.rb'))
  end

  it 'counts an unknown namespace without inventing a file target' do
    source('app/api/request.rb', 'class Missing::Service; end')
    profile = ArchUnit::Extraction::ExtractionProfile.new
    expect(edges(profile:)).to be_empty
    expect(profile.counters.fetch(:unresolved_constant_references)).to eq(1)
  end

  it 'counts a reopened namespace as ambiguous instead of selecting an arbitrary owner file' do
    source('app/db/namespace.rb', 'module Db; end')
    source('lib/another_db.rb', 'module Db; end')
    source('app/api/request.rb', 'Db::VALUE = 42')
    profile = ArchUnit::Extraction::ExtractionProfile.new
    expect(edges(profile:)).to be_empty
    expect(profile.counters.fetch(:ambiguous_constant_references)).to eq(1)
  end

  it 'does not create a cross-file dependency for a same-file namespace owner' do
    source('app/api/request.rb', "module Db; end\nclass Db::Service; end\nDb::VALUE = 42\n")
    profile = ArchUnit::Extraction::ExtractionProfile.new
    expect(edges(profile:)).to be_empty
    expect(profile.counters.fetch(:unresolved_constant_references)).to eq(0)
    expect(profile.counters.fetch(:ambiguous_constant_references)).to eq(0)
  end

  it 'does not treat unqualified or root-only declaration names as reads of prior definitions' do
    source('app/db/namespace.rb', 'module Db; end; VALUE = 1')
    source('app/api/request.rb', 'module Db; end; class ::Service; end; ::VALUE = 42')
    profile = ArchUnit::Extraction::ExtractionProfile.new
    expect(edges(profile:)).to be_empty
    expect(profile.counters.fetch(:ambiguous_constant_references)).to eq(0)
  end

  it 'retains inherited-scope conservatism rather than guessing a root namespace' do
    source('app/db/namespace.rb', 'module Db; end')
    source('lib/base.rb', 'class Base; end')
    source('app/api/request.rb', 'class Child < Base; class Db::Service; end; end')
    expect(edges).to contain_exactly(have_attributes(target: 'lib/base.rb'))
  end

  it 'does not invent static ownership for a runtime namespace expression' do
    source('app/db/namespace.rb', 'module Db; end')
    source('app/api/request.rb', 'class registry::Db::Service; end')
    expect(edges).to be_empty
  end

  it 'merges import, receiver and assignment-value evidence without duplicate graph pairs' do
    source('app/db/namespace.rb', 'module Db; SEED = 42; end')
    source('app/api/request.rb', "require_relative '../db/namespace'\nDb::VALUE = Db::SEED\n")
    attributes = {
      import_kinds: contain_exactly(:require_relative, :constant_reference),
      evidence: contain_exactly(have_attributes(name: '../db/namespace'),
                                have_attributes(name: 'Db'), have_attributes(name: 'Db::SEED'))
    }
    expect(edges).to contain_exactly(have_attributes(attributes))
    report = JSON.parse(ArchUnit.project_graph(@root).with_check_options(options).to_json)
    expect(report.fetch('edges').first.fetch('evidence').map { |item| item.fetch('name') })
      .to contain_exactly('../db/namespace', 'Db', 'Db::SEED')
    layers = ArchUnit.project_layers(@root)
                     .layer('api').defined_by('app/api/**')
                     .layer('db').defined_by('app/db/**')
                     .where_layer('api').may_not_depend_on_layers('db')
    expect(layers.check(options).length).to eq(1)
    slices = ArchUnit.project_slices(@root).defined_by('app/(**)/')
    expect(slices.should_not.contain_dependency('api', 'db').check(options).length).to eq(1)
  end
end
