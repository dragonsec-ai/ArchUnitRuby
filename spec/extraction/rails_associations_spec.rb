# frozen_string_literal: true

require 'json'
require 'pathname'
require 'tmpdir'

RSpec.describe 'Explicit Rails associations' do
  around do |example|
    Dir.mktmpdir('archunit-associations') do |directory|
      @root = Pathname.new(directory)
      write('Gemfile', "raise 'do not load Gemfile'")
      example.run
    ensure
      ArchUnit.clear_graph_cache
    end
  end

  def write(path, contents)
    path = @root.join(path)
    path.dirname.mkpath
    path.write(contents)
  end

  def model(code, superclass: '::ActiveRecord::Base')
    write('packs/api/app/models/requests/order.rb', <<~RUBY)
      class Requests::Order < #{superclass}
        #{code}
      end
    RUBY
  end

  def graph(**settings)
    ArchUnit::Extraction.extract_graph(@root, options: ArchUnit::CheckOptions.new(**settings))
  end

  def association_edges(graph)
    graph.select { |edge| edge.import_kinds.include?(:rails_association) }
  end

  def associations
    association_edges(graph(rails_associations: true))
  end

  def counted_graph(**settings)
    profile = ArchUnit::Extraction::ExtractionProfile.new
    options = ArchUnit::CheckOptions.new(rails_associations: true, **settings)
    graph = ArchUnit::Extraction.extract_graph(@root, options:, profile:)
    [graph, profile.counters]
  end

  it 'detects the issue probe only with the new setting and uses the existing rule' do
    model("belongs_to :store, class_name: 'Retrieval::Store'")
    store = 'packs/storage/app/models/retrieval/store.rb'
    write(store, "module Retrieval; class Store; end; end\nraise 'do not execute target'")
    rule = ArchUnit.files(@root).in_path('packs/api/**').should_not
                   .depend_on_files.in_path('packs/storage/**')

    expect(rule.check).to be_empty
    legacy = ArchUnit::CheckOptions.new(dependency_analysis: :imports_and_constants,
                                        rails_imports: true)
    expect(rule.check(legacy)).to be_empty
    [ArchUnit::CheckOptions.new, legacy].each do |options|
      violations = rule.check(options.with(rails_associations: true))
      expect(violations.length).to eq(1)
      edge = violations.first.dependency.cumulated_edges.first
      expect(edge.target).to eq(store)
      expect(edge.import_kinds).to eq([:rails_association])
      expect(edge.evidence.first.to_h).to include(
        kind: :rails_association, name: 'Retrieval::Store', line_number: 2, target_line_number: 1
      )
    end
  end

  it 'recognizes all four macros, a lambda scope, self, and literal symbol values' do
    model(<<~RUBY, superclass: 'ApplicationRecord')
      belongs_to :account, class_name: 'Account'
      has_one :item, "class_name": :Account
      self.has_many :items, -> { where(current: true) }, class_name: 'Account'
      has_and_belongs_to_many :others, :class_name => 'Account'
    RUBY
    write('lib/account.rb', 'class Account; end')

    expect(associations.map(&:target)).to eq(['lib/account.rb'])
    edge = associations.first
    expect(edge.evidence.map(&:line_number)).to eq([2, 3, 4, 5])
    expect(edge.evidence.map(&:name)).to eq(%w[Account Account Account Account])
  end

  it 'tries full model-name prefixes, honors root qualification, and falls back across roots' do
    model(<<~RUBY)
      belongs_to :local, class_name: 'Store'
      belongs_to :root, class_name: '::Store'
      belongs_to :otherwise, class_name: 'Services::Widget'
    RUBY
    write('packs/api/names.rb', 'module Requests; module Services; end; class Store; end; end')
    write('packs/other/root.rb', 'class Store; end')
    write('packs/other/service.rb', 'module Services; class Widget; end; end')
    expect(associations.map(&:target)).to contain_exactly(
      'packs/api/names.rb', 'packs/other/root.rb', 'packs/other/service.rb'
    )
  end

  it 'keeps evidence from the macro line through the literal, not unrelated option lines' do
    model(<<~RUBY)
      belongs_to :account,
        class_name: 'Account',
        optional: true
    RUBY
    write('lib/account.rb', "class Account\nend")
    expect(associations.first.evidence.first.to_h).to include(
      name: 'Account', line_number: 2, end_line: 3, target_line_number: 1
    )
  end

  it 'prefers model-local targets except that the model basename tries root first' do
    model(<<~RUBY)
      belongs_to :nested, class_name: 'Store'
      belongs_to :same_basename, class_name: 'Order'
      class Store; end
    RUBY
    write('lib/root.rb', 'class Order; end')
    write('lib/fallback.rb', 'module Requests; class Store; end; end')
    expect(associations.map(&:target)).to eq(['lib/root.rb'])
  end

  it 'does not guess past ambiguous or non-class candidates and counts unsupported sites' do
    model(<<~'RUBY')
      belongs_to :dup, class_name: 'Duplicate'
      belongs_to :missing, class_name: 'Missing'
      belongs_to :unknown, class_name: "Thing#{ENV.fetch('TYPE')}"
      has_many :indirect, class_name: 'Target', through: :joins
      belongs_to :indirect, class_name: 'Target', polymorphic: true
      has_many :polymorphic_children, class_name: 'Target', as: :owner
      has_many :inferred
      has_many :duplicate, class_name: 'Target', :"class_name" => 'Other'
      has_many :expanded, **{ class_name: 'Target' }
      has_many :bad_key, "class_name" => 'Target'
      has_many :bad_name, class_name: 'Target.call'
      has_many :path_shadow, class_name: 'Target'
      has_many :expression, class_name: Target
      has_many :binary, class_name: "\xff"
    RUBY
    write('lib/one.rb', "module Requests; class Duplicate; end; Target = 'not a class'; end")
    write('lib/two.rb', 'module Requests; class Duplicate; end; end')
    write('lib/fallback.rb', 'class Duplicate; end; class Target; end')

    edges, counts = counted_graph
    expect(association_edges(edges)).to be_empty
    expect(counts).to include(rails_association_sites: 14, unresolved_rails_associations: 13,
                              ambiguous_rails_associations: 1)
  end

  it 'ignores ordinary strings, comments, unrelated classes/receivers and indirect calls' do
    model(<<~RUBY)
      OPTIONS = { class_name: 'Target' }
      # belongs_to :comment, class_name: 'Target'
      unrelated.has_many :other, class_name: 'Target'
      self&.has_many :safe, class_name: 'Target'
      custom_association :extension, class_name: 'Target'
      def call
        belongs_to :nested_call, class_name: 'Target'
      end
      configure { has_many :inside_block, class_name: 'Target' }
    RUBY
    write('lib/other.rb', "class Other; has_many :target, class_name: 'Target'; end")
    write('lib/empty.rb', 'class Empty < ApplicationRecord; end')
    write('lib/target.rb', 'class Target; end')
    expect(associations).to be_empty
    expect(counted_graph(clear_cache: true).last).to include(rails_association_sites: 0)
  end

  it 'merges repeated sites, ordinary references and imports with stable evidence' do
    model(<<~RUBY)
      require_relative 'store'
      belongs_to :store, class_name: '::Store', polymorphic: false
      has_one :second, class_name: '::Store'
      def build
        ::Store.new
      end
    RUBY
    write('packs/api/app/models/requests/store.rb', "class Store\nend")
    options = ArchUnit::CheckOptions.new(
      rails_associations: true, dependency_analysis: :imports_and_constants
    )
    report = ArchUnit.project_graph(@root).with_check_options(options)
    edges = JSON.parse(report.to_json).fetch('edges').select do |item|
      item['import_kinds'].include?('rails_association')
    end
    expect(edges.length).to eq(1)
    edge = edges.first
    expect(edge['import_kinds']).to eq(%w[constant_reference rails_association require_relative])
    expect(edge['evidence'].map { |item| item['line_number'] }).to eq([2, 6, 3, 4])
    expect(edge['evidence'].map { |item| item['target_line_number'] }).to eq([nil, 1, 1, 1])
  end

  it 'partitions cache identity and excludes unavailable definition files' do
    model("belongs_to :store, class_name: 'Store'")
    write('packs/storage/store.rb', 'class Store; end')
    plain = graph
    enabled = graph(rails_associations: true)
    expect(enabled).not_to equal(plain)
    expect(graph(rails_associations: true)).to equal(enabled)
    expect(graph(rails_associations: true, clear_cache: true)).not_to equal(enabled)
    expect(graph).to equal(plain)
    edges, counters = counted_graph(source_exclusions: ['packs/storage/**'])
    expect(edges.none?(&:external)).to be(true)
    expect(association_edges(edges)).to be_empty
    expect(counters).to include(unresolved_rails_associations: 1)
  end

  it 'enforces both rules when an excluded import and an included model share a label' do
    write('app/models/client.rb', <<~RUBY)
      require_relative 'db/store.rb'
      class Client < ApplicationRecord
        belongs_to :store, class_name: '::Store'
      end
    RUBY
    write('app/models/db/store.rb', '# excluded')
    write('db/store.rb', 'class Store < ApplicationRecord; end')
    options = ArchUnit::CheckOptions.new(rails_associations: true,
                                         source_exclusions: ['app/models/db/**'])
    rule = ArchUnit.files(@root).in_path('app/models/client.rb').should_not
    internal = rule.depend_on_files.in_path('db/**')
    external = rule.depend_on_external_modules.matching('db/store.rb')
    { internal => :rails_association, external => :require_relative }.each do |check, kind|
      violations = check.check(options)
      expect(violations.size).to eq(1)
      raw = violations.first.dependency.cumulated_edges
      expect(raw.size).to eq(1)
      expect(raw.first.import_kinds).to eq([kind])
      expect(raw.first.evidence.map(&:kind)).to eq([kind])
    end
  end
end
