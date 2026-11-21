# frozen_string_literal: true

require 'archunit'
require 'archunit/cli'
require 'fileutils'
require 'json'
require 'stringio'
require 'tmpdir'

SOURCE_POLICY_FIXTURE = {
  'Gemfile' => "raise 'must not execute Gemfile'\n",
  'app/api/request.rb' => "require_relative '../db/store'\nclass Request; end\n",
  'app/db/store.rb' => "class Store; end\nraise 'must not execute source'\n",
  'lib/templates/bad.rb' => '<%= not_ruby %>',
  'lib/templates/real.rb' => 'class RealRuby; end'
}.freeze

def write_source_policy_fixture(root)
  SOURCE_POLICY_FIXTURE.each do |path, code|
    file = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, code)
  end
end

def verify_source_policy(root, mode)
  rule = ArchUnit.project_files(root).in_path('app/api/**')
                 .should_not.depend_on_files.in_path('app/db/**')
  options = ArchUnit::CheckOptions.new(dependency_analysis: mode,
                                       source_exclusions: ['lib/templates/bad.rb'])
  abort 'expected architecture dependency missing' unless rule.check(options).length == 1
  verify_source_policy_metrics(root, options)
  abort 'target policy was modified' if File.exist?(File.join(root, '.archignore'))
end

def verify_source_policy_metrics(root, options)
  counts = ArchUnit.metrics(root).count.classes.measure(options)
  abort 'graph/metric source policies disagree' unless counts.length == 3
end

def verify_source_policy_cli(root, config)
  output = StringIO.new
  status = ArchUnit::CLI.run(
    ['check', '--project', root, '--config', config, '--format', 'json',
     '--exclude-source', 'lib/templates/bad.rb'], out: output, err: StringIO.new, cwd: root
  )
  abort 'read-only CLI exclusions failed' unless status.zero?
  abort 'CLI source policy missing' unless JSON.parse(output.string).fetch('source_exclusions').one?
end

Dir.mktmpdir('archunit-installed-source-policy') do |base|
  root = File.join(base, 'project')
  write_source_policy_fixture(root)
  %i[imports imports_and_constants].each { |mode| verify_source_policy(root, mode) }
  config = File.join(base, 'trusted.rb')
  File.write(config, "rule('Ruby files') { project_files.should.have_name('*.rb') }\n")
  verify_source_policy_cli(root, config)
  begin
    ArchUnit.project_graph(root).to_json
    abort 'included malformed source was silently ignored'
  rescue ArchUnit::SourceParseError
    puts 'Caller source exclusions passed; malformed included source remains fatal.'
  end
ensure
  ArchUnit.clear_graph_cache
end
