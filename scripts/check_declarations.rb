# frozen_string_literal: true

require 'archunit'
require 'pathname'
require 'tmpdir'

loaded = ArchUnit::Extraction.respond_to?(:extract_declarations)
abort 'default load unexpectedly loaded declaration analysis' if loaded
require 'archunit/extraction/declarations'

Dir.mktmpdir('archunit-declaration-smoke') do |directory|
  root = Pathname.new(directory)
  root.join('Gemfile').write("raise 'must not boot'")
  root.join('a.rb').write(<<~RUBY)
    module Orders
      class Create < ::Base
        def call(amount, auth:); end
      end
    end
    raise 'must not execute'
  RUBY
  root.join('b.rb').write('class Orders::Create; def self.build(...); end; end')
  root.join('base.rb').write('class Base; end')

  facts = ArchUnit::Extraction.extract_declarations(root)
  files = facts.namespaces.select { |item| item.name == 'Orders::Create' }.map { |item| item.site.file }
  abort 'reopened declaration lost ownership' unless files == %w[a.rb b.rb]
  scopes = facts.method_declarations.map(&:scope)
  abort 'wrong method scopes' unless scopes == %i[instance singleton]
  abort 'wrong written superclass' unless facts.relationships.first.written_target == '::Base'
  scope = ArchUnit.project_classes(root).in_namespace('Orders').descendants_of('::Base')
  result = scope.selection
  abort 'lost installed class selection' unless result.status == :complete &&
                                                result.matches.map(&:name) == ['Orders::Create']
end
puts 'Declaration facts passed read-only extraction and installed-gem smoke.'
