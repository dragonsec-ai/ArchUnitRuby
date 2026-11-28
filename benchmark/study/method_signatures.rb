# frozen_string_literal: true

require_relative 'declaration_selection'

# Compares one shared index with deliberately refreshing it before each rule.
module MethodSignatureStudy
  STUDY = DeclarationSelectionStudy
  RULES = 20
  private_constant :STUDY, :RULES

  module_function

  def run
    startup = STUDY.measure_default_load
    Dir.mktmpdir('archunit-signature-bench') do |directory|
      root = Pathname.new(directory)
      STUDY.fixture(root)
      rules = fixtures(root)
      result = measurements(rules).merge(ruby: RUBY_DESCRIPTION, startup:, rules: RULES,
                                         files: STUDY::FILES, trials: STUDY::TRIALS)
      puts JSON.pretty_generate(result)
    end
  end

  def fixtures(root)
    scope = ArchUnit.project_classes(root).descendants_of('Node0')
    Array.new(RULES) do |index|
      signature = ArchUnit::MethodSignature.new(name: :call, positional: index.even? ? 1 : 2)
      scope.should.declare_method(signature)
    end
  end

  def measurements(rules)
    shared, refresh, retained = Array.new(STUDY::TRIALS) { paired_sample(rules) }.transpose
    { shared_median: STUDY.median(shared), refreshed_median: STUDY.median(refresh),
      retained_heap_bytes: retained.sort.fetch(STUDY::TRIALS / 2) }
  end

  def paired_sample(rules)
    ArchUnit.clear_graph_cache
    before = STUDY.heap_bytes
    shared = STUDY.measure { verify(rules) }
    retained = STUDY.heap_bytes - before
    clear = ArchUnit::CheckOptions.new(clear_cache: true)
    refreshed = STUDY.measure { verify(rules, clear) }
    [shared, refreshed, retained]
  end

  def verify(rules, options = nil)
    rules.each_with_index do |rule, index|
      results = rule.check(options)
      expected = index.even? ? 0 : STUDY::FILES - 1
      raise 'wrong number of findings' unless results.size == expected && results.none?(&:unknown?)
    end
  end
end

MethodSignatureStudy.run
