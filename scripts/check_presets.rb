# frozen_string_literal: true

require 'archunit'
require 'archunit/cli'
require 'fileutils'
require 'json'
require 'stringio'
require 'tmpdir'

# Shared acceptance for the source bundle and the isolated installed gem.
module PresetSmoke
  module_function

  def run
    Dir.mktmpdir('archunit-preset-smoke') do |base|
      %i[layered hexagonal rails].each { |name| verify(base, name) }
    end
    puts 'Layered, hexagonal and Rails presets passed allowed/forbidden controls in both modes.'
  end

  def verify(base, name)
    root, folders = fixture(base, name)
    rule = ArchUnit.architecture_preset(name, ArchUnit::PresetOptions.new(project_locator: root))
    verify_allowed(rule)
    verify_cli(base, root, name)
    target = File.basename(folders.first)
    File.write(File.join(root, folders.last, 'unit.rb'), "require_relative '../#{target}/unit'")
    verify_forbidden(rule)
  ensure
    ArchUnit.clear_graph_cache
  end

  def verify_allowed(rule)
    %i[imports imports_and_constants].each do |mode|
      options = ArchUnit::CheckOptions.new(dependency_analysis: mode, clear_cache: true)
      abort 'preset rejected allowed direction' unless rule.check(options).empty?
    end
  end

  def fixture(base, name)
    folders = { layered: %w[api services db], hexagonal: %w[adapters application domain],
                rails: %w[controllers services models] }.fetch(name)
    root = File.join(base, name.to_s)
    folders.each { |folder| FileUtils.mkdir_p(File.join(root, 'app', folder)) }
    File.write(File.join(root, 'Gemfile'), "raise 'target must not boot'")
    folders.each_with_index do |folder, index|
      code = index < 2 ? "require_relative '../#{folders[index + 1]}/unit'" : '# core'
      File.write(File.join(root, 'app', folder, 'unit.rb'), "#{code}\nraise 'do not run source'")
    end
    [root, folders.map { |folder| "app/#{folder}" }]
  end

  def verify_forbidden(rule)
    %i[imports imports_and_constants].each do |mode|
      options = ArchUnit::CheckOptions.new(dependency_analysis: mode, clear_cache: true)
      abort 'preset missed forbidden direction' unless rule.check(options).length == 1
    end
  end

  def verify_cli(base, root, name)
    config = File.join(base, "#{name}-trusted.rb")
    File.write(config, "rule('preset') { architecture_preset(:#{name}) }")
    output = StringIO.new
    arguments = ['check', '--project', root, '--config', config, '--format', 'json']
    status = ArchUnit::CLI.run(arguments, out: output, err: StringIO.new)
    abort 'CLI preset failed' unless status.zero? && JSON.parse(output.string)['status'] == 'passed'
  end
end

PresetSmoke.run
