# frozen_string_literal: true

require 'archunit/cli'
require 'fileutils'
require 'json'
require 'pathname'
require 'stringio'
require 'tmpdir'

RSpec.describe ArchUnit::CLI, 'accepted-debt baselines' do
  around do |example|
    Dir.mktmpdir('archunit-baseline') do |base|
      @base = Pathname.new(base)
      @root = @base.join('project')
      @root.join('app/db').mkpath
      @root.join('Gemfile').write("raise 'never run target Gemfile'")
      @root.join('app/api.rb').write("require_relative 'db/store'\nraise 'never run target source'")
      @root.join('app/db/store.rb').write('class Store; end')
      @root.join('app/db/other.rb').write('class Other; end')
      @config = @base.join('trusted.rb')
      @baseline = @base.join('debt.json')
      @config.write(<<~RUBY)
        rule('API boundary') do
          project_files.in_path('app/api.rb').should_not.depend_on_files.in_path('app/db/**')
        end
      RUBY
      example.run
    ensure
      ArchUnit.clear_graph_cache
    end
  end

  def invoke(command = 'check', *arguments, root: @root, format: 'json')
    output = StringIO.new
    errors = StringIO.new
    status = described_class.run(
      [command, '--project', root.to_s, '--config', @config.to_s, '--format', format, *arguments],
      out: output, err: errors, cwd: @base.to_s
    )
    [status, format == 'json' ? JSON.parse(output.string) : output.string, errors.string]
  end

  def create(*arguments)
    invoke('baseline', '--output', @baseline.to_s, *arguments)
  end

  def check(*arguments, **keywords)
    invoke('check', '--baseline', @baseline.to_s, *arguments, **keywords)
  end

  it 'explicitly creates reviewed debt without turning raw violations into a clean result' do
    expect(invoke.first).to eq(1)
    code, report = create
    expect(code).to eq(0)
    expect(report[:error]).to be_nil
    expect(report['status']).to eq('baseline_created')
    expect(report['summary']['violation_count']).to eq(1)
    expect(report.dig('rules', 0, 'status')).to eq('failed')
    document = JSON.parse(@baseline.read)
    expect(document).to include('schema_version' => 1, 'fingerprint_version' => 1)
    expect(document['entries'].first).to include('rule' => 'API boundary', 'count' => 1)
    expect(document['entries'].first['fingerprint']).to match(/\A[a-f0-9]{64}\z/)
    expect(@root.join('.archignore')).not_to exist
    expect(invoke.first).to eq(1)
  end

  it 'retains accepted violation data and never writes during check' do
    create
    bytes = @baseline.binread
    code, report = check
    expect(code).to eq(0)
    expect(report['status']).to eq('accepted')
    expect(report['summary']).to eq('rule_count' => 1, 'violation_count' => 1)
    expect(report['baseline']).to include('accepted_count' => 1, 'new_count' => 0,
                                          'stale_count' => 0)
    violation = report.dig('rules', 0, 'violations', 0)
    expect(violation['details']).to include('app/api.rb', 'app/db/store.rb')
    expect(violation['baseline']['status']).to eq('accepted')
    expect(@baseline.binread).to eq(bytes)
    expect(check(format: 'text')[1]).to include('1 accepted, 0 new, 0 stale',
                                                '[accepted] API boundary')
  end

  it 'keeps fingerprints stable across relocation and irrelevant source line changes' do
    create
    @root.join('app/api.rb').write("# new line\n\nrequire_relative 'db/store'")
    expect(check.first).to eq(0)
    relocated = @base.join('relocated')
    FileUtils.cp_r(@root, relocated)
    code, report = check(root: relocated)
    expect(code).to eq(0)
    expect(report['baseline']['accepted_count']).to eq(1)
  end

  it 'reports new violations and stale fixed debt separately and fails for either' do
    create
    @root.join('app/api.rb').write("require_relative 'db/store'\nrequire_relative 'db/other'")
    code, report = check
    expect(code).to eq(1)
    expect(report['baseline']).to include('accepted_count' => 1, 'new_count' => 1,
                                          'stale_count' => 0)
    @root.join('app/api.rb').write('# fixed architecture')
    code, report = check
    expect(code).to eq(1)
    expect(report['baseline']).to include('accepted_count' => 0, 'new_count' => 0,
                                          'stale_count' => 1)
    expect(check(format: 'text')[1]).to include('Stale: API boundary')
  end

  it 'does not match renamed rules or changed analysis mode/settings' do
    create
    code, report = check('--dependency-analysis', 'imports_and_constants')
    expect(code).to eq(1)
    expect(report['baseline']).to include('new_count' => 1, 'stale_count' => 1)
    @config.write(@config.read.sub('API boundary', 'renamed rule'))
    expect(check.first).to eq(1)
  end

  def repeated_rule(count)
    @config.write(<<~RUBY)
      rule('repeated') do
        base = project_files.in_path('app/api.rb').should_not.depend_on_files.in_path('app/db/**')
        Class.new do
          include ArchUnit::Checkable
          define_method(:perform_check) { |options| base.check(options) * #{count} }
        end.new
      end
    RUBY
  end

  it 'does not reuse debt with association analysis on but preserves disabled fingerprints' do
    create
    expect(check('--no-rails-associations').first).to eq(0)
    code, report = check('--rails-associations')
    expect(code).to eq(1)
    expect(report['baseline']).to include(
      'accepted_count' => 0, 'new_count' => 1, 'stale_count' => 1
    )
  end

  it 'consumes duplicate fingerprints one occurrence at a time' do
    repeated_rule(2)
    expect(create.first).to eq(0)
    expect(JSON.parse(@baseline.read)['entries'].first['count']).to eq(2)
    repeated_rule(3)
    expect(check[1]['baseline']).to include('accepted_count' => 2, 'new_count' => 1)
    repeated_rule(1)
    expect(check[1]['baseline']).to include('accepted_count' => 1, 'stale_count' => 1)
  end

  it 'makes removed rules stale and can explicitly record a healthy empty baseline' do
    create
    @config.write("rule('healthy') { project_files.should.have_name('*.rb') }")
    expect(check.first).to eq(1)
    expect(create('--force').first).to eq(0)
    expect(JSON.parse(@baseline.read)['entries']).to eq([])
    expect(check.first).to eq(0)
  end

  it 'never overwrites existing output without explicit force' do
    @baseline.write('original')
    expect(create.first).to eq(2)
    expect(@baseline.read).to eq('original')
    expect(create('--force').first).to eq(0)
    expect(check.first).to eq(0)
    expect(@base.glob('.archunit-baseline-*')).to eq([])
  end

  ['class Broken <', 'exit 0'].each do |failure|
    it "never creates or changes accepted debt after failure: #{failure}" do
      create
      bytes = @baseline.binread
      if failure.start_with?('class')
        @root.join('broken.rb').write(failure)
      else
        @config.write(failure)
      end
      expect(create('--force').first).to eq(2)
      expect(@baseline.binread).to eq(bytes)
      expect(check.first).to eq(2)
    end
  end

  it 'refuses empty selections and unsupported custom violation identities' do
    @config.write("rule('empty') { project_files.in_path('missing/**').should.have_no_cycles }")
    expect(create.first).to eq(2)
    expect(@baseline).not_to exist
    custom = "rule('custom') { project_files.should.adhere_to(->(_file) { false }, 'custom') }"
    @config.write(custom)
    expect(create.first).to eq(2)
    expect(@baseline).not_to exist
  end

  it 'rejects malformed, tampered, unsupported and missing documents' do
    expect(check.first).to eq(2)
    invalid_json = ['not json', '[]', '{}', '{"schema_version": 2}', '{"entries": null}',
                    '{"schema_version":1,"schema_version":2}']
    invalid_json.each do |invalid|
      @baseline.write(invalid)
      expect(check.first).to eq(2)
    end
    create('--force')
    document = JSON.parse(@baseline.read)
    document['entries'].first['rule'] = 'tampered'
    @baseline.write(JSON.generate(document))
    expect(check.first).to eq(2)
  end

  it 'rejects duplicate entries, oversize files, directories and nonsensical counts' do
    create
    original = JSON.parse(@baseline.read)
    duplicate = Marshal.load(Marshal.dump(original))
    duplicate['entries'] *= 2
    @baseline.write(JSON.generate(duplicate))
    expect(check.first).to eq(2)
    [0, -1, 1.5, '1', 1_000_001].each do |count|
      original['entries'].first['count'] = count
      @baseline.write(JSON.generate(original))
      expect(check.first).to eq(2)
    end
    @baseline.write(' ' * 2_000_001)
    expect(check.first).to eq(2)
    expect(invoke('check', '--baseline', @root.to_s).first).to eq(2)
  end

  it 'requires explicit write flags only on the baseline command and JSON output names' do
    expect(invoke('baseline').first).to eq(2)
    expect(invoke('check', '--force').first).to eq(2)
    expect(invoke('explain', '--baseline', @baseline.to_s).first).to eq(2)
    expect(invoke('baseline', '--output', @config.to_s, '--force').first).to eq(2)
    expect(@config.read).to include('API boundary')
  end

  it 'rejects symlink inputs and outputs, including dangling outputs on supported platforms' do
    create
    link = @base.join('link.json')
    begin
      File.symlink(@baseline, link)
    rescue NotImplementedError, SystemCallError
      skip 'creating symlinks is not available for this user or platform'
    end
    expect(invoke('check', '--baseline', link.to_s).first).to eq(2)
    expect(invoke('baseline', '--output', link.to_s, '--force').first).to eq(2)
    dangling = @base.join('dangling.json')
    File.symlink(@base.join('absent.json'), dangling)
    expect(invoke('baseline', '--output', dangling.to_s, '--force').first).to eq(2)
    expect(@base.join('absent.json')).not_to exist
  end
end
