# frozen_string_literal: true

require 'archunit'
require 'fileutils'
require 'tmpdir'

def check_uncertain_path(source, root)
  File.write(source, "path = 'app/db/store.rb'\nload path, (path.replace('other.rb'); true)\n")
  profile = ArchUnit::Extraction::ExtractionProfile.new
  extracted = ArchUnit::Extraction.extract_imports(source, project_root: root, profile:)
  abort 'stale wrapped path invented' unless extracted.empty?
  abort 'uncertainty silently skipped' unless profile.counters.fetch(:unresolved_imports) == 1
end

# Run both with Bundler and after installing the built gem into a clean GEM_HOME.
Dir.mktmpdir('archunit-installed-wrapped-loads') do |root|
  %w[api db].each { |folder| FileUtils.mkdir_p(File.join(root, 'app', folder)) }
  File.write(File.join(root, 'Gemfile'), "raise 'must not execute project source'\n")
  File.write(File.join(root, 'app/db/store.rb'), "raise 'must not execute loaded source'\n")
  source = File.join(root, 'app/api/request.rb')
  scope = ArchUnit.project_files(root).in_path('app/api/**')
  forbidden = scope.should_not.depend_on_files.in_path('app/db/**')
  allowed = scope.should.depend_on_files.in_path('app/db/**')
  %i[imports imports_and_constants].each do |mode|
    options = ArchUnit::CheckOptions.new(dependency_analysis: mode, clear_cache: true)
    %w[load Kernel.load ::Kernel.load].product(%w[true false nil]).each do |call, wrap|
      File.write(source, "path = 'app/db/store.rb'\n#{call} path, #{wrap}\n")
      violations = forbidden.check(options)
      abort "wrapped load missing: #{call}, #{wrap}, #{mode}" unless violations.length == 1
      edge = violations.first.dependency.cumulated_edges.first
      abort 'wrong import kind' unless edge.import_kinds == [:load]
      if mode == :imports_and_constants && edge.evidence.first.line_number != 2
        abort 'wrong load evidence'
      end
      ArchUnit.assert_passes(allowed, options)
    end
  end
  check_uncertain_path(source, root)
  puts 'Wrapped loads passed in both dependency modes without executing source.'
ensure
  ArchUnit.clear_graph_cache
end
