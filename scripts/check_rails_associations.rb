# frozen_string_literal: true

require 'archunit'
require 'archunit/cli'
require 'json'
require 'pathname'
require 'stringio'
require 'tmpdir'

def write_association_fixture(root)
  root.join('Gemfile').write("raise 'do not evaluate Gemfile'")
  root.join('client.rb').write(<<~RUBY)
    class Client < ApplicationRecord
      belongs_to :store, class_name: 'Storage::Store'
      has_many :items
    end
    raise 'do not execute model source'
  RUBY
  root.join('store.rb').write("module Storage; class Store; end; end\nraise 'do not execute'")
  write_association_config(root)
end

def write_association_config(root)
  root.join('.archunit.rb').write(<<~RUBY)
    rule('Storage is private') do
      project_files.in_path('client.rb').should_not.depend_on_files.in_path('store.rb')
    end
  RUBY
end

def run_association_cli(root, *flags, format: 'json')
  output = StringIO.new
  errors = StringIO.new
  status = ArchUnit::CLI.run(['check', '--format', format, *flags],
                             out: output, err: errors, cwd: root.to_s)
  abort errors.string unless errors.string.empty?
  [status, format == 'json' ? JSON.parse(output.string) : output.string]
end

def verify_association_cli(root)
  code, old = run_association_cli(root, '--rails-associations', '--no-rails-associations')
  abort 'association analysis silently enabled' unless code.zero? && !old.key?('rails_associations')

  code, report = run_association_cli(root, '--rails-associations')
  abort 'expected a violation' unless code == 1 && report.fetch('rails_associations')

  verify_association_counters(report.dig('analysis', 'scopes', 0))
  _, text = run_association_cli(root, '--rails-associations', format: 'text')
  abort 'text diagnostics missing' unless text.include?('association class names: enabled')
end

def verify_association_counters(scope)
  expected = { 'rails_association_sites' => 2, 'unresolved_rails_associations' => 1,
               'ambiguous_rails_associations' => 0, 'unresolved_constant_references' => nil }
  counters = scope.fetch('counters').slice(*expected.keys)
  return if scope.fetch('rails_associations') && counters == expected

  abort "unexpected association counters: #{scope.inspect}"
end

Dir.mktmpdir('archunit-installed-rails-associations') do |directory|
  root = Pathname.new(directory)
  write_association_fixture(root)
  verify_association_cli(root)
  puts 'Explicit Rails association check and diagnostics passed without booting Rails or source.'
ensure
  ArchUnit.clear_graph_cache
end
