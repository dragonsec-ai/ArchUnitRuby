# frozen_string_literal: true

require 'archunit'
require 'fileutils'
require 'tmpdir'

def check_namespace_violation(rule, options)
  violations = rule.check(options)
  abort 'namespace receiver dependency missing' unless violations.length == 1
  edge = violations.first.dependency.cumulated_edges.first
  abort 'wrong namespace kind' unless edge.import_kinds == [:constant_reference]
  abort 'namespace definition evidence missing' unless edge.evidence.first.target_line_number == 2
end

declarations = ['class %s::Service; end', 'module %s::Service; end', '%s::VALUE = 42',
                '%s::VALUE ||= 42'].product(%w[Db ::Db]).map { |form, name| format(form, name) }
options = ArchUnit::CheckOptions.new(dependency_analysis: :imports_and_constants, clear_cache: true)
Dir.mktmpdir('archunit-installed-namespace-receivers') do |root|
  %w[api db].each { |folder| FileUtils.mkdir_p(File.join(root, 'app', folder)) }
  File.write(File.join(root, 'Gemfile'), "raise 'must not execute project source'\n")
  File.write(File.join(root, 'app/db/namespace.rb'), "\nmodule Db; end\nraise 'must not execute'\n")
  source = File.join(root, 'app/api/request.rb')
  scope = ArchUnit.project_files(root).in_path('app/api/**')
  forbidden = scope.should_not.depend_on_files.in_path('app/db/**')
  declarations.each do |declaration|
    File.write(source, "#{declaration}\nraise 'must not execute declared source'\n")
    check_namespace_violation(forbidden, options)
    ArchUnit.assert_passes(scope.should.depend_on_files.in_path('app/db/**'), options)
    abort 'import-only behavior changed' unless forbidden.check.empty?
  end
  puts 'Qualified declaration namespace dependencies passed without executing source.'
ensure
  ArchUnit.clear_graph_cache
end
