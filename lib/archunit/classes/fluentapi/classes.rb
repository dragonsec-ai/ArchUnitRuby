# frozen_string_literal: true

# Public entry to declaration inspection alongside the existing file and graph APIs.
module ArchUnit
  # Starts an immutable class declaration scope without reading the project.
  # @param project_locator [String, Pathname, nil]
  # @return [Classes::FluentApi::ClassScope]
  def self.project_classes(project_locator = nil)
    require_relative 'class_scope'
    Classes::FluentApi::ClassScope.new(project_locator)
  end
end
