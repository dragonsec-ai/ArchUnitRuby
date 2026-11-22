# frozen_string_literal: true

require_relative '../../benchmark/semantic/probes'

RSpec.describe SemanticStudy::Probes do
  it 'records bounded facts without claiming method semantics or executing probe code' do
    observations = described_class.run
    expect(observations.length).to eq(14)
    expect(observations.map { |item| item[:has_semantic_method_edges] }).to all(be(false))
    expect(observations.map do |item|
      item[:metric_method_fields]
    end).to all(eq(%i[name accessed_fields]))
    dynamic = observations.find { |item| item[:name] == 'dynamic_parameter_receiver' }
    expect(dynamic[:syntax][:calls]).to include(include(name: :delete_all,
                                                        resolved_runtime_receiver: nil))
    inherited = observations.find { |item| item[:name] == 'inherited_unqualified_constant' }
    expect(inherited[:direct_file_boundary_violations]).to eq(0)
    expect(inherited[:counters][:unresolved_constant_references]).to be_positive
    reopened = observations.find { |item| item[:name] == 'reopened_ambiguous_constant' }
    expect(reopened[:counters][:ambiguous_constant_references]).to be_positive
  end
end
