# frozen_string_literal: true

require 'fileutils'
require 'find'
require 'tmpdir'

RSpec.describe 'Pruned source discovery' do
  around do |example|
    Dir.mktmpdir('archunit-walk-oracle') do |directory|
      @root = Pathname.new(directory).realpath
      example.run
    end
  end

  def write_source(name)
    file = @root.join(name)
    file.dirname.mkpath
    file.write("raise 'source must not execute'\n")
  end

  def legacy_sources(patterns)
    Find.find(@root.to_s).filter_map { |entry| legacy_source(entry, patterns) }.sort
  end

  def legacy_source(entry, patterns)
    stat = File.lstat(entry)
    return if stat.symlink? || entry == @root.to_s

    relative = Pathname.new(entry).relative_path_from(@root).to_s.tr('\\', '/')
    excluded = legacy_excluded?(patterns, relative, File.basename(entry))
    Find.prune if stat.directory? && excluded
    relative if legacy_source_file?(entry, stat) && !excluded
  end

  def legacy_source_file?(entry, stat)
    stat.file? && File.extname(entry) == '.rb'
  end

  def legacy_excluded?(patterns, relative, name)
    patterns.any? do |pattern|
      candidate = pattern.delete_prefix('/')
      target = pattern.start_with?('/') || candidate.include?('/') ? relative : name
      File.fnmatch?(candidate, target, File::FNM_DOTMATCH | File::FNM_PATHNAME)
    end
  end

  it 'matches the previous Find implementation across mixed tree and exclusion shapes' do
    names = %w[root.rb .rb upper.RB .hidden/kept.rb vendor/ignored.rb nested/vendor/ignored.rb
               lib/.private.rb lib/generated/source.rb lib/a_model.rb lib/b[1].rb
               lib/ümlaut.rb looks.rb/child.rb lib/README] + ['lib/space name.rb']
    names.each { |name| write_source(name) }
    @root.join('.archignore').write("lib/generated/\n")
    [nil, [], ['/vendor'], ['vendor'], ['**/*_model.rb'], ['lib/[ab]*.rb'],
     ['lib\\generated\\', '.hidden'], ['**/.private.rb'], ['looks.rb']].each do |patterns|
      discovery = ArchUnit::Extraction.discover_source_files(@root, exclude_patterns: patterns)
      expect(discovery.files).to eq(legacy_sources(discovery.patterns))
    end
  end

  it 'prunes an excluded large tree even when none of its files are readable Ruby' do
    120.times { |index| write_source("vendor/deep/tree/file_#{index}.rb") }
    write_source('lib/kept.rb')
    allow(Dir).to receive(:children).and_call_original
    expect(Dir).not_to receive(:children).with(@root.join('vendor').to_s, any_args)
    expect(ArchUnit::Extraction.enumerate_source_files(@root)).to eq(['lib/kept.rb'])
  end

  it 'never reinterprets a literal backslash in a directory entry as a file separator' do
    name = 'actual\\name.rb'
    allow(Dir).to receive(:children).with(@root.to_s, any_args).and_return([name])
    source = instance_double(File::Stat, symlink?: false, directory?: false, file?: true)
    allow(File).to receive(:lstat).and_call_original
    allow(File).to receive(:lstat).with(File.join(@root, name)).and_return(source)
    expect { ArchUnit::Extraction.enumerate_source_files(@root, exclude_patterns: ['actual/**']) }
      .to raise_error(ArchUnit::TechnicalError, /literal backslash/)
    expect(ArchUnit::Extraction.enumerate_source_files(@root, exclude_patterns: ['*.rb'])).to eq([])
  end

  it 'rejects two native POSIX paths that would otherwise identify the same Ruby file' do
    skip 'backslash is a native path separator' if File::ALT_SEPARATOR

    write_source('normal/nested/item.rb')
    write_source('normal\\nested/item.rb')
    expect { ArchUnit::Extraction.extract_graph(@root) }
      .to raise_error(ArchUnit::TechnicalError, /literal backslash/)
    expect(ArchUnit::Extraction.enumerate_source_files(@root, exclude_patterns: ['*nested']))
      .to be_empty
  end

  [Errno::EACCES, Errno::ENOENT, Errno::ENOTDIR].each do |error|
    it "fails closed when an included directory listing raises #{error}" do
      write_source('lib/source.rb')
      allow(Dir).to receive(:children).and_call_original
      allow(Dir).to receive(:children).with(@root.join('lib').to_s, any_args).and_raise(error)
      expect { ArchUnit::Extraction.enumerate_source_files(@root) }
        .to raise_error(ArchUnit::TechnicalError, /could not enumerate Ruby source files/)
    end
  end

  it 'fails closed if an entry disappears after listing instead of inventing a clean snapshot' do
    write_source('source.rb')
    allow(File).to receive(:lstat).and_call_original
    allow(File).to receive(:lstat).with(@root.join('source.rb').to_s).and_raise(Errno::ENOENT)
    expect { ArchUnit::Extraction.enumerate_source_files(@root) }
      .to raise_error(ArchUnit::TechnicalError, /could not enumerate Ruby source files/)
  end

  it 'never enters symlinked directories, including portable mocked-link controls' do
    write_source('alias/hidden.rb')
    write_source('keep.rb')
    link = @root.join('alias').to_s
    status = File.lstat(link)
    allow(status).to receive(:symlink?).and_return(true)
    allow(File).to receive(:lstat).and_call_original
    allow(File).to receive(:lstat).with(link).and_return(status)
    allow(Dir).to receive(:children).and_call_original
    expect(Dir).not_to receive(:children).with(link, any_args)
    expect(ArchUnit::Extraction.enumerate_source_files(@root)).to eq(['keep.rb'])
  end

  it 'ignores nonregular entries without treating them as source or directories' do
    write_source('pipe.rb')
    status = instance_double(File::Stat, symlink?: false, directory?: false, file?: false)
    allow(File).to receive(:lstat).and_call_original
    allow(File).to receive(:lstat).with(@root.join('pipe.rb').to_s).and_return(status)
    expect(ArchUnit::Extraction.enumerate_source_files(@root)).to eq([])
  end

  ['C:/MixedCase/project', '//server/share/project'].each do |root|
    it "builds relative identifiers from children under #{root} without prefix slicing" do
      directory = instance_double(File::Stat, symlink?: false, directory?: true)
      source = instance_double(File::Stat, symlink?: false, directory?: false, file?: true)
      library = File.join(root, 'lib')
      allow(Dir).to receive(:children).with(root, any_args).and_return(['lib'])
      allow(Dir).to receive(:children).with(library, any_args).and_return(['Ünicode.rb'])
      allow(File).to receive(:lstat).with(library).and_return(directory)
      allow(File).to receive(:lstat).with(File.join(root, 'lib', 'Ünicode.rb')).and_return(source)
      walker = ArchUnit::Extraction.const_get(:SourceWalker).new(root, [])
      expect(walker.files).to eq(['lib/Ünicode.rb'])
    end
  end

  it 'uses filesystem encoding for an ASCII-encoded root without losing Unicode child names' do
    root = @root.to_s.dup.force_encoding(Encoding::US_ASCII)
    source = instance_double(File::Stat, symlink?: false, directory?: false, file?: true)
    encoding = Encoding.find('filesystem')
    allow(Dir).to receive(:children).with(root, encoding:).and_return(['Ünicode.rb'])
    allow(File).to receive(:lstat).with(File.join(root, 'Ünicode.rb')).and_return(source)
    expect(ArchUnit::Extraction.const_get(:SourceWalker).new(root, []).files).to eq(['Ünicode.rb'])
  end

  it 'walks a deep synthetic tree iteratively without depending on native path-length limits' do
    root = @root.to_s
    depth = 1200
    directory = instance_double(File::Stat, symlink?: false, directory?: true)
    source = instance_double(File::Stat, symlink?: false, directory?: false, file?: true)
    allow(Dir).to receive(:children) do |path, **_options|
      path.count('/') - root.count('/') < depth ? ['d'] : ['leaf.rb']
    end
    allow(File).to receive(:lstat) { |path| path.end_with?('.rb') ? source : directory }
    walker = ArchUnit::Extraction.const_get(:SourceWalker).new(root, [])
    expect(walker.files).to eq(["#{'d/' * depth}leaf.rb"])
  end

  it 'retains canonical root validation for a symlinked project root' do
    write_source('lib/kept.rb')
    Dir.mktmpdir('archunit-root-alias') do |directory|
      link = File.join(directory, 'alias')
      File.symlink(@root, link)
      expect(ArchUnit::Extraction.enumerate_source_files(link)).to eq(['lib/kept.rb'])
    end
  rescue NotImplementedError, Errno::EACCES
    skip 'creating symlinks is not available for this user or platform'
  end
end

RSpec.describe 'Compiled source exclusion matching' do
  it 'matches legacy literal, anchored, recursive, Unicode and malformed globs' do
    patterns = %w[vendor Vendor /vendor **/generated/** *.rb .hidden lib/[ab]?.rb lib/ümlaut.rb
                  a{b,c} bad[ x] /lib/**/*]
    paths = %w[vendor Vendor VENDOR nested/vendor keep.rb .hidden lib/ab.rb lib/ümlaut.rb
               lib/Upper.rb a{b,c} bad[ x]]
    patterns.each do |pattern|
      matcher = ArchUnit::Extraction.const_get(:SourcePatternMatcher).new([pattern])
      paths.each do |path|
        candidate = pattern.delete_prefix('/')
        target = pattern.start_with?('/') || candidate.include?('/') ? path : File.basename(path)
        expected = File.fnmatch?(candidate, target, File::FNM_DOTMATCH | File::FNM_PATHNAME)
        expect(matcher.excluded?(path, File.basename(path))).to eq(expected)
      end
      expect(matcher).to be_frozen
    end
  end

  it 'does not invoke glob matching for exact default basenames' do
    type = ArchUnit::Extraction.const_get(:SourcePatternMatcher)
    matcher = type.new(ArchUnit::Extraction::DEFAULT_EXCLUDED_DIRECTORIES)
    expect(File).not_to receive(:fnmatch?)
    expect(matcher.excluded?('nested/vendor', 'vendor')).to be(true)
    expect(matcher.excluded?('lib/source.rb', 'source.rb')).to be(false)
  end
end
