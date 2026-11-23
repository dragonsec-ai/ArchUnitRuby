# frozen_string_literal: true

require 'open3'
require 'rbconfig'
require 'tmpdir'
require_relative '../../scripts/documentation_examples'
require_relative '../../scripts/documentation_links'

RSpec.describe 'README and documentation workflows' do
  it 'runs the exact library examples without executing the generated target project' do
    expect { ArchUnitDocumentationExamples.run }.not_to raise_error
  end

  it 'runs the exact RSpec quickstart through passing, failing and repaired states' do
    Dir.mktmpdir('archunit-readme-rspec') do |directory|
      root = Pathname.new(directory)
      ArchUnitDocumentationExamples.prepare(root)
      spec = root.join('spec/architecture_spec.rb')
      spec.dirname.mkpath
      spec.write(ArchUnitDocumentationExamples.example('quickstart-spec'))
      expect(run_quickstart(root, spec).last.exitstatus).to eq(0)
      root.join('app/api/request.rb').write("require_relative '../database/store'")
      output, _errors, status = run_quickstart(root, spec)
      expect(status.exitstatus).to eq(1)
      expect(output).to include('app/api/request.rb', 'app/database/store.rb')
      expect(output).to include('File dependency violation')
      root.join('app/api/request.rb').write("raise 'source must not execute'")
      expect(run_quickstart(root, spec).last.exitstatus).to eq(0)
    end
  end

  def run_quickstart(root, spec)
    trusted_gemfile = File.expand_path('../../Gemfile', __dir__)
    executable = Gem.bin_path('rspec-core', 'rspec')
    Open3.capture3({ 'BUNDLE_GEMFILE' => trusted_gemfile }, RbConfig.ruby,
                   '-rbundler/setup', executable, spec.to_s, chdir: root.to_s)
  end

  it 'resolves source document anchors and rejects missing destinations' do
    root = Pathname.new(File.expand_path('../..', __dir__))
    expect(ArchUnitDocumentationLinks.source_errors(root)).to eq([])
    Dir.mktmpdir('archunit-document-links') do |directory|
      page = Pathname.new(directory).join('index.html')
      page.write('<a id="valid"></a><a href="#missing">broken</a><a href="#valid">good</a>')
      expect(ArchUnitDocumentationLinks.rendered_errors(page))
        .to eq(['Missing document anchor: #missing'])
    end
  end

  it 'rejects Markdown headings that were not rendered after HTML anchors' do
    Dir.mktmpdir('archunit-heading-links') do |directory|
      page = Pathname.new(directory).join('index.html')
      page.write("<p><a id=\"quickstart\"></a>\n## Quickstart</p>")
      expect(ArchUnitDocumentationLinks.rendered_errors(page))
        .to eq(['Unrendered Markdown heading'])
    end
  end

  it 'includes the guide and support documents in package metadata with canonical destinations' do
    root = File.expand_path('../..', __dir__)
    gemspec = Gem::Specification.load(File.join(root, 'archunit.gemspec'))
    expect(gemspec.homepage).to eq('https://github.com/dragonsec-ai/ArchUnitRuby')
    expect(gemspec.metadata['documentation_uri']).to eq('https://dragonsec-ai.github.io/ArchUnitRuby/')
    expect(gemspec.files).to include('README.md', 'GUIDE.md', 'API.md', 'SECURITY.md', 'SUPPORT.md')
  end
end
