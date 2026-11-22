# frozen_string_literal: true

require 'archunit'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'

# Subprocess checks also run against the isolated installed package in CI.
module AnalysisDiagnosticsSmoke
  module_function

  def run
    Dir.mktmpdir('archunit-analysis-smoke') do |base|
      root, config = prepare(base)
      %w[imports imports_and_constants].each do |mode|
        payload = check(root, config, mode, expected: 0)
        verify_scope(payload, mode)
      end
      verify_parse_failure(root, config)
    end
    puts 'Cache-aware CLI analysis diagnostics passed without executing target code.'
  end

  def prepare(base)
    root = File.join(base, 'project')
    FileUtils.mkdir_p(root)
    File.write(File.join(root, 'Gemfile'), "raise 'do not run Gemfile'")
    File.write(File.join(root, 'app.rb'), "require plugin_path\nMissing\nDb\nraise 'do not run'")
    %w[one two].each { |name| File.write(File.join(root, "#{name}.rb"), 'module Db; end') }
    config = File.join(base, 'trusted.rb')
    write_config(config)
    [root, config]
  end

  def write_config(config)
    File.write(config, <<~RUBY)
      rule('first') { project_files.should.have_name('*.rb') }
      rule('second') { project_files.should.have_no_cycles }
    RUBY
  end

  def verify_parse_failure(root, config)
    File.write(File.join(root, 'broken.rb'), 'class Broken <')
    failure = check(root, config, 'imports', expected: 2)
    abort 'parse error lost diagnostics' if failure.dig('error', 'diagnostics').to_a.empty?
    scope = failure.fetch('analysis').fetch('scopes').first
    abort 'failed analysis pretended to measure zero' unless scope['counters'].values.all?(&:nil?)
  end

  def check(root, config, mode, expected:)
    arguments = [Gem.bin_path('archunit', 'archunit'), 'check', '--format', 'json',
                 '--project', root, '--config', config, '--dependency-analysis', mode]
    out, err, status = Open3.capture3(RbConfig.ruby, *arguments)
    unless status.exitstatus == expected && err.empty?
      abort "diagnostics expected #{expected}, got #{status.exitstatus}: #{out}#{err}"
    end
    JSON.parse(out)
  end

  def verify_scope(payload, mode)
    scopes = payload.fetch('analysis').fetch('scopes')
    abort 'cached graph was double counted' unless scopes.one?
    scope = scopes.first
    abort 'warm reuse not recorded' unless scope.values_at('observations', 'cache_hits') == [2, 1]
    expected_constants = mode == 'imports' ? nil : 1
    expected = { 'source_files' => 3, 'imports' => 0, 'unresolved_imports' => 1,
                 'unresolved_constant_references' => expected_constants,
                 'ambiguous_constant_references' => expected_constants }
    abort "wrong analysis counters: #{scope['counters']}" unless scope['counters'] == expected
    abort 'schema changed' unless payload['schema_version'] == 1
  end
end

AnalysisDiagnosticsSmoke.run
