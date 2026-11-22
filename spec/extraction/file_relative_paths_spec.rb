# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tmpdir'

RSpec.describe 'bounded file-relative import expressions' do
  around do |example|
    Dir.mktmpdir('archunit-static-paths') do |directory|
      @root = File.realpath(directory)
      source('Gemfile', "raise 'must not evaluate Gemfile'\n")
      source('app/db/store.rb', "raise 'must not execute imported source'\n")
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

  def imports(code, profile: nil)
    file = source('app/api/request.rb', code)
    ArchUnit::Extraction.extract_imports(file, project_root: @root, profile:)
  end

  [
    "File.dirname(__FILE__) + '/../db/store'",
    "::File.dirname(__FILE__) + '/../db/store'",
    "__dir__ + '/../db/store'",
    "File.expand_path('../db/store', __dir__)",
    "::File.expand_path('../db/store', File.dirname(__FILE__))",
    "File.expand_path(__dir__ + '/../db/store')",
    "File.dirname(File.expand_path('../db/unused.rb', __dir__)) + '/store'"
  ].each do |expression|
    it "resolves #{expression} without executing source" do
      result = imports("require #{expression}\n")
      attributes = {
        resolved_path: File.join(@root, 'app/db/store.rb'), import_kind: :require,
        line_number: 1, end_line: 1
      }
      expect(result).to contain_exactly(have_attributes(attributes))
    end
  end

  it 'accepts literal string composition and the source filename keyword' do
    result = imports("require 'app/' + 'db/store'\nload __FILE__, false\n")
    expect(result.map(&:resolved_path)).to eq(
      [File.join(@root, 'app/db/store.rb'), File.join(@root, 'app/api/request.rb')]
    )
  end

  %w[require require_relative load].each do |call|
    it "tracks a completed file-relative assignment for #{call}" do
      code = "path = File.expand_path('../db/store.rb', __dir__)\n#{call} path\n"
      expected_path = File.join(@root, 'app/db/store.rb')
      attributes = { resolved_path: expected_path, import_kind: call.to_sym }
      expect(imports(code)).to contain_exactly(have_attributes(attributes))
    end
  end

  it 'supports computed autoload paths and wrapped loads with unchanged kinds and locations' do
    code = <<~RUBY
      autoload :Store, File.expand_path('../db/store', __dir__)
      load File.expand_path('../db/store.rb', __dir__), true
    RUBY
    expect(imports(code).map { |item| [item.import_kind, item.line_number] })
      .to eq([[:autoload, 1], [:load, 2]])
  end

  [
    "Custom.dirname(__FILE__) + '/../db/store'",
    "custom.dirname(__FILE__) + '/../db/store'",
    "Other::File.dirname(__FILE__) + '/../db/store'",
    "File.join(__dir__, '../db/store')",
    "File.expand_path('../db/store')",
    "File.expand_path('~/private', __dir__)",
    "File.expand_path('C:private', __dir__)",
    "File.expand_path('../db/store', ENV.fetch('BASE'))",
    "File.dirname(__FILE__, 2) + '/db/store'",
    'File.expand_path(dynamic_path, __dir__)',
    'File.expand_path(*args)',
    "File.dirname(__FILE__) { raise 'must not execute' }",
    'File&.dirname(__FILE__)',
    "File.expand_path('../db/store', __dir__) + dynamic_suffix",
    "base + '/../db/store'"
  ].each do |expression|
    it "counts unsupported/unknown expression #{expression} as unresolved" do
      profile = ArchUnit::Extraction::ExtractionProfile.new
      expect(imports("base = __dir__\nrequire #{expression}\n", profile:)).to be_empty
      expect(profile.counters.fetch(:unresolved_imports)).to eq(1)
    end
  end

  [
    'File = Object.new',
    '::File = Object.new',
    'module Outer; File = Object.new; end',
    'class File; end',
    "def File.dirname(path); raise 'must not execute'; end",
    'class << File; def dirname(path); path; end; end',
    'File.define_singleton_method(:dirname) { |path| path }',
    'Object.const_set(:File, Object.new)',
    'using CustomPathRefinement',
    'eval(dynamic_code)'
  ].each do |shadow|
    it "does not assume core File semantics in a source containing #{shadow}" do
      profile = ArchUnit::Extraction::ExtractionProfile.new
      code = "#{shadow}\nrequire File.dirname(__FILE__) + '/../db/store'\n"
      expect(imports(code, profile:)).to be_empty
      expect(profile.counters.fetch(:unresolved_imports)).to eq(1)
    end
  end

  it 'does not assume core __dir__ semantics when the method is redefined in the source' do
    code = "def __dir__; '/somewhere/else'; end\nrequire __dir__ + '/../db/store'\n"
    expect(imports(code)).to be_empty
  end

  it 'does not fold string addition when the source reopens String' do
    expect(imports("class String; def +(other); other; end; end\nrequire 'app/' + 'db/store'"))
      .to be_empty
  end

  it 'does not fold string addition after a mixin can replace its implementation' do
    expect(imports("String.prepend(CustomStrings)\nrequire 'app/' + 'db/store'"))
      .to be_empty
  end

  it 'treats aliasing and undefining directory methods as source-local uncertainty' do
    ['alias __dir__ somewhere_else', 'undef __dir__'].each do |change|
      expect(imports("#{change}\nrequire __dir__ + '/../db/store'\n")).to be_empty
    end
  end

  it 'recognizes shadowing through constant targets and autoloads' do
    ['File, Other = objects', '::File, Other = objects', "autoload :File, 'custom_file'",
     'autoload unknown_name, dynamic_path'].each do |change|
      result = imports("#{change}\nrequire File.dirname(__FILE__) + '/../db/store'\n")
      expect(result.none? { |item| item.import_kind == :require }).to be(true)
    end
  end

  it 'does not carry computed values across mutation, aliases, capture, or uncertain flow' do
    code = <<~RUBY
      path = File.expand_path('../db/store', __dir__)
      path.replace('wrong')
      require path
      path = File.expand_path('../db/store', __dir__)
      alias_path = path
      require path
      if unknown_condition
        require File.expand_path('../db/store', __dir__)
      end
      callback = -> { path.replace('wrong') }
      path = File.expand_path('../db/store', __dir__)
      require path
    RUBY
    profile = ArchUnit::Extraction::ExtractionProfile.new
    expect(imports(code, profile:)).to be_empty
    expect(profile.counters.fetch(:unresolved_imports)).to eq(4)
  end

  it 'preserves multiline spans and unscoped ignore directives' do
    code = <<~RUBY
      require File.expand_path(
        '../db/store', __dir__
      )
      # archunit: ignore
      require File.expand_path('../db/store', __dir__)
    RUBY
    expect(imports(code)).to contain_exactly(have_attributes(line_number: 1, end_line: 3))
  end

  %w[require require_relative].each do |call|
    it "does not reuse a computed local across #{call} block-argument side effects" do
      code = "path = File.expand_path('../db/store.rb', __dir__)\n" \
             "#{call}(path, &(path.replace('wrong'); nil))\n"
      profile = ArchUnit::Extraction::ExtractionProfile.new
      expect(imports(code, profile:)).to be_empty
      expect(profile.counters.fetch(:unresolved_imports)).to eq(1)
    end
  end

  it 'does not reuse a path that an earlier autoload name expression can mutate' do
    code = "path = File.expand_path('../db/store', __dir__)\n" \
           "autoload((path.replace('wrong'); :Store), path)\n"
    profile = ArchUnit::Extraction::ExtractionProfile.new
    expect(imports(code, profile:)).to be_empty
    expect(profile.counters.fetch(:unresolved_imports)).to eq(1)
  end

  it 'does not fold arbitrarily deep or oversized generated expressions' do
    expression = "#{'File.dirname(' * 20}__FILE__#{')' * 20}"
    profile = ArchUnit::Extraction::ExtractionProfile.new
    expect(imports("require #{expression}\nrequire __dir__ + '#{'x' * 17_000}'", profile:))
      .to be_empty
    expect(profile.counters.fetch(:unresolved_imports)).to eq(2)
  end

  %i[imports imports_and_constants].each do |mode|
    it "preserves rules, reports, caching and exclusions in #{mode} mode" do
      source('app/api/request.rb', "require File.dirname(__FILE__) + '/../db/store'\n")
      options = ArchUnit::CheckOptions.new(dependency_analysis: mode)
      scope = ArchUnit.project_files(@root).in_path('app/api/**')
      forbidden = scope.should_not.depend_on_files.in_path('app/db/**')
      expect(forbidden.check(options).length).to eq(1)
      ArchUnit.assert_passes(scope.should.depend_on_files.in_path('app/db/**'), options)
      first = ArchUnit::Extraction.extract_graph(@root, options:)
      expect(ArchUnit::Extraction.extract_graph(@root, options:)).to equal(first)
      report = JSON.parse(ArchUnit.project_graph(@root).with_check_options(options).to_json)
      expect(report.fetch('edges').first.fetch('import_kinds')).to eq(['require'])
      if mode == :imports_and_constants
        expect(report.fetch('edges').first.fetch('evidence').first.fetch('line_number')).to eq(1)
      end
      excluded = ArchUnit::Extraction.extract_graph(
        @root, options:, exclude_patterns: ['app/db/**']
      )
      expect(excluded.reject { |edge| edge.source == edge.target }.map(&:external)).to eq([true])
    end
  end
end
