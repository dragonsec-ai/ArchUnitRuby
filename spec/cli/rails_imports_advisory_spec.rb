# frozen_string_literal: true

require 'archunit/cli'
require 'json'
require 'pathname'
require 'stringio'
require 'tmpdir'

RSpec.describe ArchUnit::CLI, 'Rails imports-only advisory' do
  around do |example|
    Dir.mktmpdir('archunit-advisory') do |dir|
      @root = Pathname.new(dir)
      write('Gemfile', "raise 'do not boot'")
      write('app/controllers/orders_controller.rb', 'class OrdersController; end')
      write('app/services/order_service.rb', 'class OrderService; end')
      write('app/models/order.rb', 'class Order; def controller; ::OrdersController; end; end')
      config("rule('boundaries') { architecture_preset(:rails) }")
      example.run
    ensure
      ArchUnit.clear_graph_cache
    end
  end

  def write(path, contents)
    file = @root.join(path)
    file.dirname.mkpath
    file.write(contents)
  end

  def config(source)
    write('.archunit.rb', source)
  end

  def invoke(*args, format: 'json', command: 'check')
    out = StringIO.new
    code = described_class.run([command, '--format', format, *args],
                               out:, err: StringIO.new, cwd: @root.to_s)
    [code, format == 'json' ? JSON.parse(out.string) : out.string]
  end

  it 'explains a passing default, while expanded mode reports the actual forbidden direction' do
    code, payload = invoke
    expect(code).to eq(0)
    expect(payload.dig('summary', 'violation_count')).to eq(0)
    hint = payload.fetch('analysis').fetch('advisories').fetch(0)
    expect(hint).to include('code' => 'rails_no_scoped_imports', 'rule_names' => ['boundaries'])
    expect(hint.fetch('message')).to include('--dependency-analysis imports_and_constants')
    expect(invoke(format: 'text').last).to include(hint.fetch('message'), 'boundaries')

    code, payload = invoke('--dependency-analysis', 'imports_and_constants')
    expect(code).to eq(1)
    expect(payload.dig('summary', 'violation_count')).to eq(1)
    expect(payload.fetch('analysis')).not_to have_key('advisories')
  end

  it 'ignores self, external and out-of-scope edges and deduplicates just the affected rules' do
    write('app/controllers/orders_controller.rb', <<~RUBY)
      require 'json'
      require_relative 'orders_controller'
      require_relative '../../lib/helper'
      class OrdersController; end
    RUBY
    write('lib/helper.rb', "require_relative '../app/models/order'")
    config(<<~RUBY)
      rule('one') { architecture_preset(:rails) }
      rule('ordinary') { project_files.should.have_no_cycles }
      rule('two') { architecture_preset(:rails) }
    RUBY
    hints = invoke.last.fetch('analysis').fetch('advisories')
    expect(hints).to contain_exactly(include('rule_names' => %w[one two]))
    expect(invoke(format: 'text').last.scan(hints.first.fetch('message')).size).to eq(1)
  end

  it 'uses the actual override folders, and counts a same-layer cross-file import' do
    config(<<~RUBY)
      rule('custom') do
        architecture_preset(:rails, ArchUnit::PresetOptions.new(folders: { models: 'domain/**' }))
      end
    RUBY
    write('domain/entity.rb', '# no imports')
    write('domain/order.rb', "require_relative 'entity'")
    expect(invoke.last.fetch('analysis')).not_to have_key('advisories')
    write('domain/order.rb', '# no imports')
    expect(invoke.last.dig('analysis', 'advisories')).not_to be_empty
  end

  it 'does not advise on missing layers, failed parses, explain or non-Rails rules' do
    expect(invoke(command: 'explain').last.fetch('analysis')).not_to have_key('advisories')
    config("rule('plain') { project_files.should.have_no_cycles }")
    expect(invoke.last.fetch('analysis')).not_to have_key('advisories')
    config("rule('rails') { architecture_preset(:rails) }")
    code, payload = invoke('--exclude-source', 'app/models/**')
    expect(code).to eq(1)
    expect(payload.fetch('analysis')).not_to have_key('advisories')
    write('app/models/order.rb', 'class Broken <')
    code, payload = invoke
    expect(code).to eq(2)
    expect(payload.fetch('analysis')).not_to have_key('advisories')
  end

  it 'counts an explicitly enabled Rails import but does not index constants to decide' do
    expect(ArchUnit::Extraction.const_get(:ConstantIndex)).not_to receive(:new)
    write('app/services/order_service.rb', "require_dependency 'order'")
    expect(invoke('--load-path', 'app/models').last.dig('analysis', 'advisories')).not_to be_empty
    result = invoke('--rails-imports', '--load-path', 'app/models')
    expect(result.first).to eq(0)
    expect(result.last.fetch('analysis')).not_to have_key('advisories')
  end

  it 'does not treat a hint as baseline debt or change its exit status' do
    path = @root.join('debt.json').to_s
    code, payload = invoke('--output', path, command: 'baseline')
    expect(code).to eq(0)
    expect(payload.dig('baseline', 'accepted_count')).to eq(0)
    expect(JSON.parse(File.read(path)).fetch('entries')).to eq([])
    expect(invoke('--baseline', path).first).to eq(0)
  end

  it 'does not collect or emit advisories in a direct library check' do
    rule = ArchUnit.architecture_preset(:rails, ArchUnit::PresetOptions.new(project_locator: @root))
    expect(ArchUnit::Layers::FluentApi.const_get(:RailsImportCoverage)).not_to receive(:new)
    expect(ArchUnit::Extraction.const_get(:ConstantIndex)).not_to receive(:new)
    expect(rule.check).to eq([])
  end
end
