# frozen_string_literal: true

require 'archunit'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'

# Exercise the real executable from the source bundle and the isolated installed gem.
module BaselineSmoke
  module_function

  def run
    Dir.mktmpdir('archunit-baseline-smoke') do |base|
      root, config, baseline = prepare(base)
      check(root, config, 'check', expected: 1)
      created = check(root, config, 'baseline', '--output', baseline, expected: 0)
      abort 'baseline creation pretends to pass' unless created['status'] == 'baseline_created'
      verify_accepted(root, config, baseline)
      verify_stale_and_error(root, config, baseline)
    end
    puts 'Explicit baseline creation, accepted/new/stale debt, and parse failures passed.'
  end

  def prepare(base)
    root = File.join(base, 'project')
    FileUtils.mkdir_p(root)
    File.write(File.join(root, 'Gemfile'), "raise 'do not run target Gemfile'")
    File.write(File.join(root, 'api.rb'), "require_relative 'store'\nraise 'do not run target'")
    File.write(File.join(root, 'store.rb'), 'class Store; end')
    config = File.join(base, 'trusted.rb')
    write_config(config)
    [root, config, File.join(base, 'debt.json')]
  end

  def write_config(path)
    File.write(path, <<~RUBY)
      rule('boundary') do
        project_files.in_path('api.rb').should_not.depend_on_files.in_path('store.rb')
      end
    RUBY
  end

  def verify_accepted(root, config, baseline)
    accepted = check(root, config, 'check', '--baseline', baseline, expected: 0)
    abort 'accepted debt hidden' unless accepted['status'] == 'accepted'
    abort 'raw violation lost' unless accepted.dig('summary', 'violation_count') == 1
    check(root, config, 'baseline', '--output', baseline, expected: 2)
  end

  def verify_stale_and_error(root, config, baseline)
    File.write(File.join(root, 'api.rb'), '# fixed')
    stale = check(root, config, 'check', '--baseline', baseline, expected: 1)
    abort 'fixed debt not stale' unless stale.dig('baseline', 'stale_count') == 1
    before = File.binread(baseline)
    File.write(File.join(root, 'api.rb'), 'class Broken <')
    check(root, config, 'baseline', '--output', baseline, '--force', expected: 2)
    abort 'parse failure changed accepted debt' unless File.binread(baseline) == before
  end

  def check(root, config, *arguments, expected:)
    executable = Gem.bin_path('archunit', 'archunit')
    args = [executable, *arguments, '--project', root, '--config', config, '--format', 'json']
    output, errors, status = Open3.capture3(RbConfig.ruby, *args)
    unless status.exitstatus == expected && errors.empty?
      abort "baseline CLI expected #{expected}, got #{status.exitstatus}: #{output}#{errors}"
    end
    JSON.parse(output)
  end
end

BaselineSmoke.run
