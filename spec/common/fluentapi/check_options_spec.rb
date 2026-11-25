# frozen_string_literal: true

RSpec.describe ArchUnit::Common::FluentApi::CheckOptions do
  it 'keeps explicit Rails association analysis separately opt-in and boolean' do
    options = described_class.new
    expect(options).not_to be_rails_associations
    expect(options.with(rails_associations: true)).to be_rails_associations
    expect(options.with(rails_imports: true)).not_to be_rails_associations
    expect { described_class.new(rails_associations: 'yes') }
      .to raise_error(ArgumentError, 'rails_associations must be true or false')
  end

  it 'defaults to strict empty tests with logging disabled and cache reuse' do
    options = described_class.new

    expect(options).to have_attributes(
      allow_empty_tests: false,
      logging: nil,
      clear_cache: false,
      load_paths: [],
      dependency_analysis: :imports,
      rails_imports: false
    )
    expect(options.allow_empty_tests?).to be(false)
    expect(options.clear_cache?).to be(false)
    expect(options).to be_frozen
  end

  it 'accepts explicit cross-cutting options' do
    logging = ArchUnit::LoggingOptions.new(io: nil)
    options = described_class.new(
      allow_empty_tests: true,
      logging:,
      clear_cache: true,
      load_paths: ['components\\billing\\lib', 'components/billing/lib/']
    )

    expect(options.allow_empty_tests?).to be(true)
    expect(options.logging).to equal(logging)
    expect(options.clear_cache?).to be(true)
    expect(options.load_paths).to eq(['components/billing/lib'])
    expect(options.load_paths).to be_frozen
  end

  it 'resolves an omitted value to defaults and preserves existing options' do
    options = described_class.new(clear_cache: true)

    expect(described_class.resolve(nil)).to eq(described_class.new)
    expect(described_class.resolve(options)).to equal(options)
  end

  it 'rejects invalid option and boolean values' do
    expect { described_class.resolve({}) }
      .to raise_error(ArgumentError, 'options must be a CheckOptions value or nil')
    expect { described_class.new(allow_empty_tests: nil) }
      .to raise_error(ArgumentError, 'allow_empty_tests must be true or false')
    expect { described_class.new(clear_cache: nil) }
      .to raise_error(ArgumentError, 'clear_cache must be true or false')
    expect { described_class.new(logging: Object.new) }
      .to raise_error(ArgumentError, 'logging must be a LoggingOptions value or nil')
    expect { described_class.new(load_paths: 'lib') }
      .to raise_error(ArgumentError, 'load_paths must be an Array of non-empty paths')
    expect { described_class.new(load_paths: ['']) }
      .to raise_error(ArgumentError, 'load_paths must be an Array of non-empty paths')
  end

  it 'is exposed from the gem public surface' do
    expect(ArchUnit::CheckOptions).to equal(described_class)
    expect(ArchUnit::LoggingOptions).to equal(ArchUnit::Common::Logging::LoggingOptions)
  end

  it 'supports explicit constant analysis and rejects unknown analysis modes' do
    expect(described_class.new).not_to be_constant_references
    expanded = described_class.new(dependency_analysis: :imports_and_constants)
    expect(expanded).to be_constant_references
    expect { described_class.new(dependency_analysis: :dynamic) }
      .to raise_error(ArgumentError, /dependency_analysis/)
  end

  it 'requires an explicit boolean Rails import opt-in and preserves immutable copies' do
    original = described_class.new
    expect(original).not_to be_rails_imports
    enabled = original.with(rails_imports: true)
    expect(enabled).to be_rails_imports
    expect(original.rails_imports).to be(false)
    expect { described_class.new(rails_imports: 'yes') }
      .to raise_error(ArgumentError, 'rails_imports must be true or false')
  end
end
