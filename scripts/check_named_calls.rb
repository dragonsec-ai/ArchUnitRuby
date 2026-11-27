# frozen_string_literal: true

require 'archunit'
require 'archunit/cli'
require 'json'
require 'pathname'
require 'stringio'
require 'tmpdir'

def check_named_call(root, expected_status:)
  output = StringIO.new
  error = StringIO.new
  status = ArchUnit::CLI.run(%w[check --format=json], cwd: root.to_s, out: output, err: error)
  abort "unexpected named-call exit: #{status}: #{error.string}" unless status == expected_status

  JSON.parse(output.string)
end

Dir.mktmpdir('archunit-named-call-smoke') do |dir|
  root = Pathname.new(dir)
  root.join('Gemfile').write("raise 'never boot target'")
  root.join('.archunit.rb').write(<<~RUBY)
    rule('query boundaries') do
      project_files.in_path('query.rb').should_not.contain_calls_named(:delete_all)
    end
  RUBY
  file = root.join('query.rb')
  file.write("store.delete_all\nraise 'never execute target'")
  report = check_named_call(root, expected_status: 1)
  call = report.dig('rules', 0, 'violations', 0, 'call')
  evidence = call&.values_at('name', 'line', 'column')
  abort 'missing named-call evidence' unless evidence == ['delete_all', 1, 7]
  file.write("store.read\nraise 'never execute target'")
  check_named_call(root, expected_status: 0)
end
puts 'Named call rule passed the CLI red-to-green smoke without executing target code.'
