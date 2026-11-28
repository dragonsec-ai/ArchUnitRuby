# frozen_string_literal: true

require 'archunit'
require 'archunit/cli'
require 'json'
require 'pathname'
require 'stringio'
require 'tmpdir'

def signature_check(root, *flags, expected:)
  output = StringIO.new
  args = [*flags, '--format=json']
  status = ArchUnit::CLI.run(args, cwd: root.to_s, out: output, err: StringIO.new)
  abort "expected #{expected}, got #{status}: #{output.string}" unless status == expected

  JSON.parse(output.string)
end

Dir.mktmpdir('archunit-signature-smoke') do |dir|
  root = Pathname.new(dir)
  root.join('Gemfile').write("raise 'must not boot target'")
  root.join('.archunit.rb').write(<<~RUBY)
    rule('commands') do
      shape = ArchUnit::MethodSignature.new(name: :call, positional: 1, keywords: [:actor])
      project_classes.in_namespace('Commands').should.declare_method(shape)
    end
  RUBY
  source = root.join('command.rb')
  source.write("module Commands; class Run; def call; end; end; end\nraise 'do not execute'")
  failure = signature_check(root, 'check', expected: 1)
  reason = failure.dig('rules', 0, 'violations', 0, 'method_signature', 'reason')
  abort 'missing structured signature evidence' unless reason == 'incompatible_signature'
  source.write('module Commands; class Run; def call(id, actor:); end; end; end')
  signature_check(root, 'check', expected: 0)
  source.write('module Commands; class Run; def call(id, actor:); end if flag?; end; end')
  refused = signature_check(root, 'baseline', '--output', 'debt.json', expected: 2)
  message = refused.dig('error', 'message')
  abort 'baseline did not reject an unknown shape' unless message&.include?('unknown method')
  abort 'unknown signature created an accepted-debt baseline' if root.join('debt.json').exist?
end
puts 'Declared method rule passed the CLI red-to-green and baseline safety smoke.'
