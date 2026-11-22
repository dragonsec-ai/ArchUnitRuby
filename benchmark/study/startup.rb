# frozen_string_literal: true

require 'json'
require_relative 'adapters'
require_relative 'measurements'

tool, root, policy, expected = ARGV
if tool == 'archspec'
  gem 'archspec', '= 1.1.0'
  gem 'rubydex', '= 0.4.0'
  require 'archspec'
else
  require 'archunit'
end
adapter = PerformanceStudy::Adapters.build(tool, root, policy)
result = PerformanceStudy::Measurements.sample(adapter, :cold, Integer(expected))
puts JSON.generate(result.merge(peak_rss_kb: PerformanceStudy::Measurements.peak_rss_kb))
