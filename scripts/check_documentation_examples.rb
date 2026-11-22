# frozen_string_literal: true

gem 'archunit', ENV.fetch('DOC_GEM_VERSION') if ENV.key?('DOC_GEM_VERSION')
require 'archunit'
require_relative 'documentation_examples'

ArchUnitDocumentationExamples.run
puts "README library examples passed with archunit #{ArchUnit::VERSION}."
