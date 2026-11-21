# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

RSpec.describe 'wrapped load dependency analysis' do
  around do |example|
    Dir.mktmpdir('archunit-wrapped-load') do |directory|
      @root = File.realpath(directory)
      source('Gemfile', "raise 'must not execute'\n")
      source('app/db/store.rb', "raise 'must not execute'\n")
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

  def imports(code, profile: nil)
    source('app/api/request.rb', code)
    ArchUnit::Extraction.extract_imports(
      File.join(@root, 'app/api/request.rb'), project_root: @root, profile:
    )
  end

  def forbidden
    ArchUnit.project_files(@root).in_path('app/api/**')
            .should_not.depend_on_files.in_path('app/db/**')
  end

  %w[load Kernel.load ::Kernel.load].product(%w[true false nil]).each do |call, wrap|
    it "resolves #{call} with literal path and #{wrap} wrapping" do
      expect(imports("#{call} 'app/db/store.rb', #{wrap}")).to contain_exactly(
        have_attributes(module_name: 'app/db/store.rb', import_kind: :load, line_number: 1,
                        resolved_path: File.join(@root, 'app/db/store.rb'))
      )
    end
  end

  %w[true false nil wrap].each do |wrap|
    it "resolves a known local path with side-effect-free #{wrap} wrapping" do
      code = "path = 'app/db/store.rb'\nwrap = true\nload path, #{wrap}\n"
      expect(imports(code).map(&:module_name)).to eq(['app/db/store.rb'])
    end
  end

  it 'counts dynamic wrapped paths instead of silently skipping them' do
    profile = ArchUnit::Extraction::ExtractionProfile.new
    expect(imports("Kernel.load compute_path, true\n", profile:)).to be_empty
    expect(profile.counters.fetch(:unresolved_imports)).to eq(1)
  end

  [
    "path.replace('other.rb')",
    "(path = 'other.rb'; true)",
    "eval(\"path.replace('other.rb')\")",
    'mutate_through_binding(binding)',
    'WrapModule'
  ].each do |wrap|
    it "does not invent a known path when the wrap expression is #{wrap}" do
      profile = ArchUnit::Extraction::ExtractionProfile.new
      expect(imports("path = 'app/db/store.rb'\nload path, #{wrap}\n", profile:)).to be_empty
      expect(profile.counters.fetch(:unresolved_imports)).to eq(1)
    end
  end

  it 'recovers later fresh literal assignments after an effectful wrap' do
    code = <<~RUBY
      path = 'app/db/store.rb'
      load path, mutate(path)
      path = 'app/db/store.rb'
      load path, true
    RUBY
    expect(imports(code)).to contain_exactly(have_attributes(line_number: 4))
  end

  ['&mutate(path)', '&converter', "&(path.replace('other.rb'); nil)"].each do |block|
    it "does not reuse a path across an effectful block conversion #{block}" do
      profile = ArchUnit::Extraction::ExtractionProfile.new
      code = "path = 'app/db/store.rb'\nconverter = make_converter\nload(path, true, #{block})"
      expect(imports(code, profile:)).to be_empty
      expect(profile.counters.fetch(:unresolved_imports)).to eq(1)
    end
  end

  it 'does not treat a passed block body as an executed wrap expression' do
    code = "path = 'app/db/store.rb'\nload(path, true) { path.replace('other.rb') }"
    expect(imports(code).map(&:module_name)).to eq(['app/db/store.rb'])
  end

  it 'retains a literal first path and traverses nested imports in a dynamic wrap' do
    code = "load 'app/db/store.rb', (require 'json'; compute_wrap)\n"
    expect(imports(code).map { |item| [item.module_name, item.import_kind] }).to eq(
      [['app/db/store.rb', :load], ['json', :require]]
    )
  end

  ["load 'app/db/store.rb', *wraps", 'load(*paths)',
   'def forward(...); Kernel.load(...); end'].each do |code|
    it "counts unknown positional arity without inventing an edge: #{code}" do
      profile = ArchUnit::Extraction::ExtractionProfile.new
      expect(imports(code, profile:)).to be_empty
      expect(profile.counters.fetch(:unresolved_imports)).to eq(1)
    end
  end

  it 'does not recognize invalid fixed arities or custom receivers as Kernel imports' do
    code = <<~RUBY
      load
      load 'app/db/store.rb', true, false
      loader.load 'app/db/store.rb', true
      Object.load 'app/db/store.rb', true
      self.load 'app/db/store.rb', true
    RUBY
    profile = ArchUnit::Extraction::ExtractionProfile.new
    expect(imports(code, profile:)).to be_empty
    expect(profile.counters.fetch(:unresolved_imports, 0)).to eq(0)
  end

  it 'preserves multiline source spans and ignore directives' do
    code = <<~RUBY
      load(
        'app/db/store.rb',
        true
      )
      # archunit: ignore app/db
      load 'app/db/store.rb', false
      load(
        'app/db/store.rb', # archunit: ignore
        true
      )
    RUBY
    expect(imports(code)).to contain_exactly(have_attributes(line_number: 1, end_line: 4))
  end

  %i[imports imports_and_constants].each do |mode|
    it "enforces public rules and reports evidence in #{mode} mode without executing source" do
      source('app/api/request.rb', "load 'app/db/store.rb', true\n")
      options = ArchUnit::CheckOptions.new(dependency_analysis: mode)
      violations = forbidden.check(options)
      expect(violations.length).to eq(1)
      edge = violations.first.dependency.cumulated_edges.first
      expect(edge.import_kinds).to eq([:load])
      if mode == :imports_and_constants
        expect(edge.evidence).to contain_exactly(have_attributes(kind: :load, line_number: 1))
      else
        expect(edge.evidence).to be_empty
      end
      positive = ArchUnit.project_files(@root).in_path('app/api/**')
                         .should.depend_on_files.in_path('app/db/**')
      ArchUnit.assert_passes(positive, options)
    end
  end
end
