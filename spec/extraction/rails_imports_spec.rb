# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tmpdir'

RSpec.describe 'explicit Rails import analysis' do
  around do |example|
    Dir.mktmpdir('archunit-rails-imports') do |directory|
      @root = File.realpath(directory)
      source('Gemfile', "raise 'must not evaluate Gemfile'\n")
      source('config/application.rb', "raise 'must not boot Rails'\n")
      source('app/models/item.rb', "class Item; end\nraise 'must not execute target'\n")
      source('app/controllers/request.rb', "require_dependency 'item'\n")
      ArchUnit.clear_graph_cache
      example.run
    ensure
      ArchUnit.clear_graph_cache
    end
  end

  def source(path, code)
    file = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, code)
    file
  end

  def options(mode = :imports, rails: true)
    ArchUnit::CheckOptions.new(rails_imports: rails, dependency_analysis: mode,
                               load_paths: ['app/models'])
  end

  def scope
    ArchUnit.project_files(@root).in_path('app/controllers/**')
  end

  def dependencies(options, profile: nil)
    ArchUnit::Extraction.extract_graph(@root, options:, profile:).reject do |edge|
      edge.source == edge.target
    end
  end

  %i[imports imports_and_constants].product(['', 'self.']).each do |mode, receiver|
    it "opts into #{receiver}require_dependency in #{mode} without executing Rails or source" do
      source('app/controllers/request.rb', "#{receiver}require_dependency 'item'\n")
      forbidden = scope.should_not.depend_on_files.in_path('app/models/**')
      expect(forbidden.check(options(mode, rails: false))).to be_empty
      expect(forbidden.check(options(mode)).length).to eq(1)
      ArchUnit.assert_passes(scope.should.depend_on_files.in_path('app/models/**'), options(mode))
      attributes = {
        source: 'app/controllers/request.rb', target: 'app/models/item.rb',
        import_kinds: [:require_dependency]
      }
      expect(dependencies(options(mode))).to contain_exactly(have_attributes(attributes))
      if mode == :imports_and_constants
        evidence = dependencies(options(mode)).first.evidence
        expect(evidence).to contain_exactly(have_attributes(kind: :require_dependency, name: 'item',
                                                            line_number: 1))
      else
        expect(dependencies(options(mode)).first.evidence).to be_empty
      end
    end
  end

  it 'keeps helper calls and dynamic operands completely outside the default vocabulary' do
    source('app/controllers/request.rb', "require_dependency compute_path\n")
    profile = ArchUnit::Extraction::ExtractionProfile.new
    expect(dependencies(ArchUnit::CheckOptions.new, profile:)).to be_empty
    expect(profile.counters.fetch(:imports)).to eq(0)
    expect(profile.counters.fetch(:unresolved_imports)).to eq(0)
  end

  it 'supports safely known locals and the bounded file-relative expression whitelist' do
    source('app/controllers/request.rb', <<~RUBY)
      path = 'item'
      require_dependency path
      require_dependency File.expand_path('../models/item', __dir__)
    RUBY
    edges = dependencies(options(:imports_and_constants))
    expect(edges.length).to eq(1)
    expect(edges.first.evidence.map(&:line_number)).to eq([2, 3])
  end

  [
    'compute_path', "Rails.root.join('app/models/item')", '"#{ENV.fetch(\'MODEL\')}"',
    '*paths', "'item', *extra"
  ].each do |argument|
    it "counts unsupported helper operand/arity #{argument} as unresolved under the opt-in" do
      source('app/controllers/request.rb', "require_dependency(#{argument})\n")
      profile = ArchUnit::Extraction::ExtractionProfile.new
      expect(dependencies(options, profile:)).to be_empty
      expect(profile.counters.fetch(:unresolved_imports)).to eq(1)
    end
  end

  it 'counts a forwarded helper call as unresolved rather than assuming an argument count' do
    source('app/controllers/request.rb', 'def forward(...); require_dependency(...); end')
    profile = ArchUnit::Extraction::ExtractionProfile.new
    expect(dependencies(options, profile:)).to be_empty
    expect(profile.counters.fetch(:unresolved_imports)).to eq(1)
  end

  %w[custom Object Kernel ActiveSupport::Dependencies].each do |receiver|
    it "does not classify #{receiver}.require_dependency as a Rails helper" do
      source('app/controllers/request.rb', "#{receiver}.require_dependency 'item'\n")
      profile = ArchUnit::Extraction::ExtractionProfile.new
      expect(dependencies(options, profile:)).to be_empty
      expect(profile.counters.fetch(:unresolved_imports)).to eq(0)
    end
  end

  [
    'def require_dependency(path); raise "custom implementation"; end',
    'def self.require_dependency(path); path; end',
    'define_method(:require_dependency) { |path| path }',
    'alias require_dependency custom_import',
    'eval(dynamic_definition)'
  ].each do |override|
    it "does not invent a helper edge in a source containing #{override}" do
      source('app/controllers/request.rb', "#{override}\nrequire_dependency 'item'\n")
      profile = ArchUnit::Extraction::ExtractionProfile.new
      expect(dependencies(options, profile:)).to be_empty
      expect(profile.counters.fetch(:unresolved_imports)).to eq(1)
    end
  end

  it 'preserves invalid arity handling and literal-path validation' do
    source('app/controllers/request.rb', <<~'RUBY')
      require_dependency
      require_dependency 'item', 'other'
      require_dependency ''
      require_dependency "\0"
    RUBY
    profile = ArchUnit::Extraction::ExtractionProfile.new
    expect(dependencies(options, profile:)).to be_empty
    expect(profile.counters.fetch(:unresolved_imports)).to eq(2)
  end

  it 'preserves ignore directives, source spans and local mutation safety' do
    source('app/controllers/request.rb', <<~RUBY)
      require_dependency(
        'item'
      )
      # archunit: ignore
      require_dependency 'item'
      path = 'item'
      path.replace('other')
      require_dependency path
    RUBY
    profile = ArchUnit::Extraction::ExtractionProfile.new
    edges = dependencies(options(:imports_and_constants), profile:)
    evidence = contain_exactly(have_attributes(kind: :require_dependency, line_number: 1,
                                               end_line: 3))
    expect(edges).to contain_exactly(have_attributes(evidence:))
    expect(profile.counters.fetch(:unresolved_imports)).to eq(1)
  end

  it 'keeps opt-in cache identity distinct and reuses the graph within each mode' do
    plain = ArchUnit::Extraction.extract_graph(@root, options: options(rails: false))
    enabled = ArchUnit::Extraction.extract_graph(@root, options: options)
    expect(enabled).not_to equal(plain)
    expect(ArchUnit::Extraction.extract_graph(@root, options: options)).to equal(enabled)
    cached_plain = ArchUnit::Extraction.extract_graph(@root, options: options(rails: false))
    expect(cached_plain).to equal(plain)
  end

  it 'prioritizes explicit helper search roots without changing ordinary require resolution' do
    source('lib/item.rb', 'class LibraryItem; end')
    source('app/controllers/request.rb', "require 'item'\nrequire_dependency 'item'\n")
    expect(dependencies(options)).to contain_exactly(
      have_attributes(target: 'lib/item.rb', import_kinds: [:require]),
      have_attributes(target: 'app/models/item.rb', import_kinds: [:require_dependency])
    )
  end

  it 'shares helper edges with layers, slices and JSON reports' do
    layers = ArchUnit.project_layers(@root)
                     .layer('controllers').defined_by('app/controllers/**')
                     .layer('models').defined_by('app/models/**')
                     .where_layer('controllers').may_not_depend_on_layers('models')
    expect(layers.check(options).length).to eq(1)
    slices = ArchUnit.project_slices(@root).defined_by('app/(**)/')
    slice_rule = slices.should_not.contain_dependency('controllers', 'models')
    expect(slice_rule.check(options).length).to eq(1)
    report = JSON.parse(ArchUnit.project_graph(@root).with_check_options(options).to_json)
    expect(report.fetch('edges').first.fetch('import_kinds')).to eq(['require_dependency'])
  end

  it 'does not turn an excluded helper target into an internal graph dependency' do
    graph = ArchUnit::Extraction.extract_graph(
      @root, options:, exclude_patterns: ['app/models/**']
    )
    expect(graph.reject { |edge| edge.source == edge.target }).to contain_exactly(
      have_attributes(external: true, import_kinds: [:require_dependency])
    )
  end

  it 'supports direct extraction with an explicit helper opt-in and resolved search roots' do
    file = File.join(@root, 'app/controllers/request.rb')
    result = ArchUnit::Extraction.extract_imports(
      file, project_root: @root, load_paths: [File.join(@root, 'app/models')], rails_imports: true
    )
    attributes = { import_kind: :require_dependency,
                   resolved_path: File.join(@root, 'app/models/item.rb') }
    expect(result).to contain_exactly(have_attributes(attributes))
    expect { ArchUnit::Extraction.extract_imports(file, project_root: @root, rails_imports: 'yes') }
      .to raise_error(ArgumentError, /rails_imports/)
  end

  it 'models the pinned Discourse guarded literal call without executing the guard or target' do
    # Discourse 2de9c9be4f89e392fe500dd27f928d6b1184bf09:
    # lib/freedom_patches/safe_migrations.rb:9 (adapted conditional/call shape).
    source('lib/migration/safe_migrate.rb', "raise 'must not execute migration'\n")
    source('app/controllers/request.rb', <<~RUBY)
      if ENV['RAILS_ENV'] != 'production'
        require_dependency 'migration/safe_migrate'
      end
    RUBY
    expect(dependencies(options)).to contain_exactly(
      have_attributes(target: 'lib/migration/safe_migrate.rb', import_kinds: [:require_dependency])
    )
    rule = scope.should_not.depend_on_files.in_path('lib/migration/**')
    expect(rule.check(options).length).to eq(1)
  end

  it 'counts the pinned Forem runtime-glob call sites without expanding or executing them' do
    # Forem 18f7eaa0e62efba3b5b7d7e44330ed9c1141286a:
    # config/initializers/liquid.rb:5,12 (adapted call structure, not runtime iteration counts).
    source('app/controllers/request.rb', <<~RUBY)
      Rails.application.config.to_prepare do
        Rails.root.glob('lib/liquid/*.rb').each { |filename| require_dependency filename }
        Rails.root.glob('app/liquid_tags/*.rb').each { |filename| require_dependency filename }
      end
    RUBY
    profile = ArchUnit::Extraction::ExtractionProfile.new
    expect(dependencies(options, profile:)).to be_empty
    expect(profile.counters.fetch(:unresolved_imports)).to eq(2)
  end
end
