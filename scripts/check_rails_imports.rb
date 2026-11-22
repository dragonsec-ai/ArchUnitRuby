# frozen_string_literal: true

require 'archunit'
require 'archunit/cli'
require 'fileutils'
require 'json'
require 'stringio'
require 'tmpdir'

RAILS_IMPORT_FIXTURE = {
  'Gemfile' => "raise 'must not evaluate Gemfile'\n",
  'app/models/item.rb' => "raise 'must not execute model'\n",
  'lib/item.rb' => "raise 'must not execute library'\n",
  'app/controllers/request.rb' => "require 'item'\nrequire_dependency 'item'\n",
  '.archunit.rb' => "rule('model boundary') { project_files.in_path('app/controllers/**')" \
                    ".should_not.depend_on_files.in_path('app/models/**') }\n"
}.freeze

def write_rails_fixture(root)
  RAILS_IMPORT_FIXTURE.each do |path, code|
    file = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, code)
  end
end

def verify_rails_rules(scope, mode)
  plain = ArchUnit::CheckOptions.new(dependency_analysis: mode, load_paths: ['app/models'])
  forbidden = scope.should_not.depend_on_files.in_path('app/models/**')
  abort 'Rails helper enabled by default' unless forbidden.check(plain).empty?
  enabled = plain.with(rails_imports: true)
  verify_helper_violation(forbidden, enabled)
  ArchUnit.assert_passes(scope.should.depend_on_files.in_path('**/*.rb'), enabled)
end

def verify_helper_violation(rule, options)
  violations = rule.check(options)
  abort 'helper dependency missing' unless violations.length == 1
  edge = violations.first.dependency.cumulated_edges.first
  abort 'wrong helper kind' unless edge.import_kinds == [:require_dependency]
end

def verify_rails_cli(root)
  output = StringIO.new
  errors = StringIO.new
  status = ArchUnit::CLI.run(
    %w[check --rails-imports --load-path app/models --format json],
    cwd: root, out: output, err: errors
  )
  abort 'helper CLI rule did not fail' unless status == 1 && errors.string.empty?
  payload = JSON.parse(output.string)
  abort 'helper CLI settings missing' unless payload.fetch('rails_imports')
end

Dir.mktmpdir('archunit-installed-rails-imports') do |root|
  write_rails_fixture(root)
  scope = ArchUnit.project_files(root).in_path('app/controllers/**')
  %i[imports imports_and_constants].each { |mode| verify_rails_rules(scope, mode) }
  verify_rails_cli(root)
  puts 'Opt-in Rails imports, root priority and CLI passed without booting Rails or source.'
ensure
  ArchUnit.clear_graph_cache
end
