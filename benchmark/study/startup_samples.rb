# frozen_string_literal: true

require 'json'
require 'open3'
require 'rbconfig'
require_relative 'measurements'

module PerformanceStudy
  # Fresh-process wall time includes Ruby boot, library load, analysis and one policy check.
  module StartupSamples
    def self.run(tool, fixture, policy)
      started = Measurements.clock
      output, errors, status = Open3.capture3(*arguments(tool, fixture, policy))
      seconds = Measurements.clock - started
      raise "startup failed: #{output}#{errors}" unless status.success? && errors.empty?

      JSON.parse(output).merge('wall_seconds' => seconds)
    end

    def self.arguments(tool, fixture, policy)
      expected = policy == 'forbidden' ? fixture.oracle.length : 0
      [RbConfig.ruby, '-I', File.expand_path('../../lib', __dir__),
       File.join(__dir__, 'startup.rb'), tool, fixture.root, policy, expected.to_s]
    end
    private_class_method :arguments
  end
end
