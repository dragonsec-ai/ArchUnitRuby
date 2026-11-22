# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'tmpdir'

# Executes only named, maintainer-owned README examples against a generated project.
module ArchUnitDocumentationExamples
  ROOT = Pathname.new(__dir__).parent

  module_function

  def example(name)
    source = ROOT.join('README.md').read
    pattern = /<!-- example:#{Regexp.escape(name)} -->\s*~~~ruby\n(.*?)\n~~~/m
    match = source.match(pattern)
    raise "README example missing: #{name}" unless match

    match[1]
  end

  def prepare(root)
    fixture_sources.each do |name, contents|
      path = root.join(name)
      path.dirname.mkpath
      path.write("#{contents}\nraise 'target source must not execute'")
    end
  end

  def fixture_sources
    {
      'Gemfile' => "raise 'target Gemfile must not execute'",
      'app/api/request.rb' => 'class Request; end',
      'app/database/store.rb' => 'class Store; end',
      'app/services/query_service.rb' => 'class QueryService; def call; end; end'
    }
  end

  def run
    Dir.mktmpdir('archunit-readme') do |directory|
      root = Pathname.new(directory)
      prepare(root)
      Dir.chdir(root) { verify_examples(root) }
    end
  ensure
    ArchUnit.clear_graph_cache
  end

  def verify_examples(root)
    %w[cycle-rule graph-report metric-rule].each { |name| evaluate(name) }
    raise 'README graph export missing' unless root.join('reports/architecture.html').file?

    root.join('app/api/request.rb').write("::Store.new\nraise 'must not execute source'")
    ArchUnit.clear_graph_cache
    violations = evaluate('expanded-options')
    return if violations.one? && violations.first.is_a?(ArchUnit::FileDependencyViolation)

    raise 'README expanded-mode example missed the constant dependency'
  end

  def evaluate(name)
    context = Object.new
    context.define_singleton_method(:puts) { |*_arguments| nil }
    context.instance_eval(example(name), "README:#{name}", 1)
  end
end
