# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'tmpdir'
require 'archunit/cli'

PRESET_FIXTURES = {
  layered: %w[app/api app/services app/db],
  hexagonal: %w[app/adapters app/application app/domain],
  rails: %w[app/controllers app/services app/models]
}.freeze

RSpec.describe 'Architecture presets' do
  around do |example|
    Dir.mktmpdir('archunit-presets') do |directory|
      @root = Pathname.new(directory).realpath
      @root.join('Gemfile').write("raise 'must not boot target project'")
      example.run
    ensure
      ArchUnit.clear_graph_cache
    end
  end

  def source(path, text)
    file = @root.join(path)
    file.dirname.mkpath
    file.write(text)
  end

  def fixture(folders)
    folders.each_with_index do |folder, index|
      next_folder = folders[index + 1]
      dependency = next_folder ? import(folder, next_folder) : ''
      source("#{folder}/unit.rb", "#{dependency}\nraise 'must not execute target source'")
    end
  end

  def import(from, to)
    relative = Pathname.new("#{to}/unit").relative_path_from(Pathname.new(from))
    "require_relative #{relative.to_s.tr('\\', '/').dump}"
  end

  PRESET_FIXTURES.each do |name, folders|
    %i[imports imports_and_constants].each do |mode|
      it "enforces #{name} allowed/forbidden directions in #{mode} without executing source" do
        fixture(folders)
        rule = ArchUnit.architecture_preset(name,
                                            ArchUnit::PresetOptions.new(project_locator: @root))
        options = ArchUnit::CheckOptions.new(dependency_analysis: mode)
        expect(rule).to be_frozen
        expect(rule.check(options)).to eq([])
        source("#{folders.last}/unit.rb", import(folders.last, folders.first))
        violations = rule.check(options.with(clear_cache: true))
        expect(violations.length).to eq(1)
        expect(violations.first).to be_a(ArchUnit::LayerDependencyViolation)
        expect(violations.first.dependency.source_label).to eq("#{folders.last}/unit.rb")
        reason = 'keep the core independent'
        expect(rule.because(reason).rationale).to eq(reason)
      end
    end
  end

  it 'constructs policies lazily and shares the existing named-layer assertion engine' do
    expect(ArchUnit::Extraction).not_to receive(:extract_graph)
    rule = ArchUnit.architecture_preset(:hexagonal)
    expect(rule).to be_a(ArchUnit::Checkable)
    expect(rule.architecture).to be_a(ArchUnit::Layers::FluentApi::LayeredArchitecture)
    expect(rule.architecture.allowed_dependencies).to eq(
      'domain' => [], 'application' => ['domain'], 'adapters' => %w[application domain]
    )
  end

  it 'defensively copies all override values without freezing caller-owned names or patterns' do
    name = +'domain'
    pattern = +'src/core/**'
    folders = { name => [pattern] }
    options = ArchUnit::PresetOptions.new(project_locator: @root, folders:)
    pattern.replace('changed/**')
    expect(name).not_to be_frozen
    expect(options.folders).to eq('domain' => ['src/core/**'])
    expect(options.folders).to be_frozen
    expect(options.folders['domain']).to be_frozen
    expect(options.folders['domain'].first).to be_frozen
    rule = ArchUnit.architecture_preset(:hexagonal, options)
    default = ArchUnit.architecture_preset(:hexagonal)
    expect(rule.architecture.layer_definitions.first.filters)
      .not_to eq(default.architecture.layer_definitions.first.filters)
  end

  it 'supports multiple patterns per layer and keeps unmapped sources visible' do
    folders = { domain: ['core/**', 'shared/**'], application: 'use_cases/**', adapters: 'web/**' }
    fixture(%w[web use_cases core])
    source('shared/other.rb', '# another domain source')
    source('unmapped.rb', '# not part of this preset policy')
    rule = ArchUnit.architecture_preset(:hexagonal,
                                        ArchUnit::PresetOptions.new(project_locator: @root,
                                                                    folders:))
    expect(rule.check).to eq([])
    graph = ArchUnit::Extraction.extract_graph(@root)
    expect(graph.map(&:source)).to include('unmapped.rb')
  end

  it 'rejects ambiguous observed layer membership instead of silently taking the first layer' do
    fixture(PRESET_FIXTURES[:hexagonal])
    options = ArchUnit::PresetOptions.new(project_locator: @root, folders: { domain: 'app/**' })
    rule = ArchUnit.architecture_preset(:hexagonal, options)
    expect { rule.check }.to raise_error(ArchUnit::UserError, /matches multiple layers/)
  end

  it 'rebuilds only once when clear_cache is requested and reuses that graph for the layer check' do
    fixture(PRESET_FIXTURES[:hexagonal])
    options = ArchUnit::PresetOptions.new(project_locator: @root)
    rule = ArchUnit.architecture_preset(:hexagonal, options)
    report = ArchUnit::CLI::AnalysisReport.new
    ArchUnit::Extraction::AnalysisObserver.capture(report) do
      expect(rule.check(ArchUnit::CheckOptions.new(clear_cache: true))).to eq([])
    end
    scopes = report.to_h[:scopes]
    expect(scopes.length).to eq(1)
    expect(scopes.first).to include(observations: 2, cache_hits: 1)
  end

  it 'keeps empty-layer and malformed-source defenses and forwards CheckOptions' do
    rule = ArchUnit.architecture_preset(:layered,
                                        ArchUnit::PresetOptions.new(project_locator: @root))
    expect(rule.check.length).to eq(3)
    expect(rule.check).to all(be_a(ArchUnit::EmptyTestViolation))
    expect(rule.check(ArchUnit::CheckOptions.new(allow_empty_tests: true))).to eq([])
    source('lib/broken.rb', 'class Broken <')
    expect { rule.check(ArchUnit::CheckOptions.new(clear_cache: true)) }
      .to raise_error(ArchUnit::SourceParseError)
    expect(rule.check(ArchUnit::CheckOptions.new(source_exclusions: ['lib/broken.rb'],
                                                 allow_empty_tests: true))).to eq([])
  end

  it 'integrates with trusted CLI configuration using its selected project root' do
    fixture(PRESET_FIXTURES[:rails])
    config = @root.dirname.join("#{@root.basename}-trusted.rb")
    begin
      config.write("rule('Rails layers') { architecture_preset(:rails) }")
      configuration = ArchUnit::CLI::Configuration.new(@root.to_s)
      rule = configuration.load(config.to_s).first.checkable
      expect(rule.architecture.project_locator).to eq(@root.to_s)
      expect(rule.check).to eq([])
    ensure
      File.unlink(config) if config.exist?
    end
  end

  it 'rejects unknown presets, duplicate names and malformed overrides' do
    expect { ArchUnit.architecture_preset(:unknown) }.to raise_error(ArgumentError, /unknown/)
    options = ArchUnit::PresetOptions.new(folders: { typo: '**' })
    expect do
      ArchUnit.architecture_preset(:rails, options)
    end.to raise_error(ArgumentError, /unknown/)
    expect do
      ArchUnit.architecture_preset(:rails, {})
    end.to raise_error(ArgumentError, /PresetOptions/)
    expect { ArchUnit::PresetOptions.new(folders: { domain: 'x', 'domain' => 'y' }) }
      .to raise_error(ArgumentError, /duplicate/)
    [nil, [], { nil => 'app/**' }, { domain: [] }, { domain: [''] },
     { domain: [42] }].each do |value|
      expect { ArchUnit::PresetOptions.new(folders: value) }.to raise_error(ArgumentError)
    end
    expect { ArchUnit::PresetOptions.new(project_locator: 123) }.to raise_error(ArgumentError)
    expect do
      ArchUnit::Layers::FluentApi::PresetRule.new(name: 'rails', architecture: nil)
    end.to raise_error(ArgumentError)
  end
end
