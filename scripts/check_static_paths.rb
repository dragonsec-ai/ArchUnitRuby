# frozen_string_literal: true

require 'archunit'
require 'fileutils'
require 'tmpdir'

expressions = ["File.dirname(__FILE__) + '/../db/store'",
               "File.expand_path('../db/store', __dir__)", "__dir__ + '/../db/store'"].freeze
Dir.mktmpdir('archunit-installed-static-paths') do |root|
  %w[api db].each { |folder| FileUtils.mkdir_p(File.join(root, 'app', folder)) }
  File.write(File.join(root, 'Gemfile'), "raise 'must not execute project source'\n")
  File.write(File.join(root, 'app/db/store.rb'), "raise 'must not execute dependency'\n")
  source = File.join(root, 'app/api/request.rb')
  scope = ArchUnit.project_files(root).in_path('app/api/**')
  forbidden = scope.should_not.depend_on_files.in_path('app/db/**')
  %i[imports imports_and_constants].each do |mode|
    options = ArchUnit::CheckOptions.new(dependency_analysis: mode, clear_cache: true)
    expressions.each do |expression|
      File.write(source, "require #{expression}\n")
      unless forbidden.check(options).length == 1
        abort "static path missing: #{mode}, #{expression}"
      end
      ArchUnit.assert_passes(scope.should.depend_on_files.in_path('app/db/**'), options)
    end
  end
  puts 'Bounded file-relative paths passed in both modes without executing source.'
ensure
  ArchUnit.clear_graph_cache
end
