# ArchUnitRuby

<p align="center">
  <img src="assets/logo-rounded.png" width="160" alt="ArchUnitRuby">
</p>

<p align="center">
  <a href="https://github.com/dragonsec-ai/ArchUnitRuby/actions/workflows/ci.yml"><img alt="Build and tests" src="https://img.shields.io/github/actions/workflow/status/dragonsec-ai/ArchUnitRuby/ci.yml?branch=main&amp;label=build%20%26%20tests"></a>
  <a href="https://rubygems.org/gems/archunit"><img alt="RubyGems version" src="https://img.shields.io/gem/v/archunit.svg"></a>
  <a href="https://clickgems.clickhouse.com/dashboard/archunit"><img alt="Gem downloads" src="https://img.shields.io/gem/dt/archunit.svg"></a>
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <img alt="Ruby 3.3 or newer" src="https://img.shields.io/badge/Ruby-3.3%2B-CC342D?logo=ruby&amp;logoColor=white">
</p>

**Architecture rules for Ruby, enforced in your tests.**

Keep dependency boundaries explicit, catch cycles, enforce conventions, measure code quality,
and generate architecture diagrams—with readable rules in RSpec, Minitest, or plain Ruby.

~~~ruby
ArchUnit.project_files.in_folder('app/api/**')
        .should_not.depend_on_files.in_folder('app/database/**')
        .because('Keep persistence behind the service boundary')
~~~

ArchUnitRuby analyzes source with Prism without booting your application. It is the Ruby member
of the [ArchUnitEverything family](#community), inspired by—but not affiliated with—ArchUnit.

[Quickstart](#quickstart) · [Capabilities](#capabilities) · [User guide](GUIDE.md) ·
[API contract](API.md) · [Documentation site](https://dragonsec-ai.github.io/ArchUnitRuby/) ·
[Example project](#example-project) · [Limitations](#limitations)

<a id="availability"></a>

## Release status

| Track | Available today |
| --- | --- |
| Published `archunit 1.0.0` | Fluent file/layer/slice rules, cycles and naming, metrics, graph/diagram exports, RSpec/Minitest integrations, opt-in constant-file analysis |
| `main` — unreleased 1.1 development | CLI, analysis diagnostics, accepted-debt baselines, architecture presets, Rails helper imports, caller-owned source exclusions, and further extraction fixes |

Install the published 1.0 series with the quickstart below. The documentation site follows
`main` and includes explicitly labeled development features; **installing 1.0.0 does not provide
the CLI or other 1.1 additions**. See [RubyGems](https://rubygems.org/gems/archunit),
the [changelog](CHANGELOG.md), and the [compatibility contract](API.md#compatibility).
Nothing on this page implies that 1.1 has been released.

<a id="quickstart"></a>

## Quickstart

### 1. Install

Ruby 3.3+ is required. Add ArchUnitRuby to your test dependencies:

~~~ruby
# Gemfile
group :test do
  gem 'archunit', '~> 1.0.0'
  gem 'rspec' # Omit this line if RSpec is already in your bundle.
end
~~~

~~~sh
bundle install
~~~

RSpec and Minitest are optional integrations, not runtime dependencies of the gem.
Already using Minitest? Keep your existing setup and use `assert_passes(rule)`.

### 2. Write your first architecture test

For this example, use two ordinary source files:

~~~text
app/
  api/request.rb       # class Request; end
  database/store.rb    # class Store; end
spec/
  architecture_spec.rb
~~~

Create `spec/architecture_spec.rb`. Change the folder patterns to match your project.

<!-- example:quickstart-spec -->
~~~ruby
require 'archunit'

RSpec.describe 'Architecture' do
  it 'keeps the API away from the database' do
    rule = ArchUnit.project_files.in_folder('app/api/**')
                   .should_not.depend_on_files.in_folder('app/database/**')
                   .because('Keep persistence behind the service boundary')

    expect(rule).to pass
  end
end
~~~

~~~sh
bundle exec rspec spec/architecture_spec.rb
~~~

No special CI service is required: run architecture specifications with your normal tests.

### 3. See it catch a dependency

Add this line to `app/api/request.rb` and rerun the test:

~~~ruby
require_relative '../database/store'
~~~

The test fails with concrete file evidence:

~~~text
File dependency violation
File 'app/api/request.rb' depends on forbidden file 'app/database/store.rb'.
~~~

Remove that dependency in this small fixture to return to green. In an application, refactor
the interaction through your intended service boundary instead of merely suppressing the test.
In a long-lived process, clear the graph cache after source edits; separate RSpec runs start fresh.

[Complete workflows](GUIDE.md) · [Watch the recorded demo](https://github.com/user-attachments/assets/9b7305a0-deee-454d-b99e-f8fac63d06ab)

<a id="capabilities"></a>

## What you can enforce and explore

| Capability | Public entry point | Details |
| --- | --- | --- |
| File boundaries, external modules, naming, locations, custom predicates | `project_files` | [File rules](API.md#file-rules) |
| Directed dependency cycles | `project_files.should.have_no_cycles` | [Rule recipes](GUIDE.md#recipes) |
| Named-layer allowlists and blocklists | `project_layers` | [Layer rules](API.md#layer-rules) |
| Component slices and PlantUML conformance | `project_slices` | [Slices and diagrams](API.md#slices) |
| Mermaid, DOT, D2, JSON, CSV, and offline HTML reports | `project_graph` | [Graph reports](API.md#graph-reports) |
| Counts, cohesion, coupling, distance, and custom thresholds | `metrics` | [Metrics](API.md#metrics) |
| Layered, hexagonal, and Rails presets | `architecture_preset` — **unreleased 1.1** | [Preset contract](API.md#presets) |

Builders are immutable and lazy: assembling a rule does not scan the project. Terminal calls
such as `check`, `measure`, `snapshot`, and exports perform the work.
`check` returns structured violations; framework integrations turn them into test failures.

| Integration | Assertion |
| --- | --- |
| RSpec | `expect(rule).to pass` |
| Minitest | `assert_passes(rule)` |
| Plain Ruby | `ArchUnit.assert_passes(rule)` |

### More than dependency boundaries

A cycle rule:

<!-- example:cycle-rule -->
~~~ruby
rule = ArchUnit.project_files.in_path('app/**/*.rb').should.have_no_cycles
ArchUnit.assert_passes(rule)
~~~

An architecture report:

<!-- example:graph-report -->
~~~ruby
report = ArchUnit.project_graph.collapse_to_folder_depth(2).titled('Application dependencies')
report.export_as_html('reports/architecture.html')
puts report.to_mermaid
~~~

A metric threshold:

<!-- example:metric-rule -->
~~~ruby
rule = ArchUnit.metrics.in_path('app/services/**/*.rb')
               .count.method_count.should_be_below_or_equal(20)
ArchUnit.assert_passes(rule)
~~~

See the [user guide](GUIDE.md#recipes) for layer/slice policies, custom predicates, logging,
report queries, and complete examples.

<a id="analysis"></a>

## Choosing the analysis mode

The default `:imports` mode recognizes supported static `require`, `require_relative`,
`autoload`, and `load` calls. It does not infer the runtime behavior of Ruby.

For autoloaded code, explicitly add the supported static constant-reference model:

<!-- example:expanded-options -->
~~~ruby
rule = ArchUnit.project_files.in_folder('app/api/**')
               .should_not.depend_on_files.in_folder('app/database/**')
options = ArchUnit::CheckOptions.new(dependency_analysis: :imports_and_constants)
violations = rule.check(options)
~~~

Expanded analysis maps known project constants to definition files and retains evidence.
It is still bounded: ambiguous, inherited, or dynamic lookup can remain unresolved.
[Resolution details](GUIDE.md#analysis) · [Options and caching](API.md#check-options)

<a id="development-cli"></a>

## CLI and gradual adoption — unreleased 1.1

These commands require this repository's development checkout and bundle, or a future 1.1 release.
They are **not available in the published 1.0.0 gem**.

~~~sh
bundle exec archunit init
# Review and customize the generated .archunit.rb before running it.
bundle exec archunit check
bundle exec archunit check --format json --dependency-analysis imports_and_constants
bundle exec archunit explain
~~~

The CLI composes the same rules as your tests. It reports source/uncertainty diagnostics without
turning unknowns into a semantic-coverage percentage. `explain` lists configuration; it does not
prove that rules passed.

For gradual adoption, explicitly record reviewed violations:

~~~sh
bundle exec archunit baseline --output .archunit-baseline.json
bundle exec archunit check --baseline .archunit-baseline.json
~~~

Every rule still runs. New violations and stale entries for fixed debt fail the check.
An `accepted` result is not a clean `passed` result. Review baseline changes; do not regenerate
them blindly in CI. Presets compose existing layer rules and retain empty-layer and overlap guards.

**Trust boundary:** `.archunit.rb` is executable Ruby, including during `explain`. For an untrusted
repository, use your own trusted `--config` file. The analyzer does not automatically execute
target source, Gemfiles/gemspecs, tests, or Rails boot; your own Bundler/configuration code still
has normal Ruby behavior.

[CLI contract](API.md#cli) · [Baseline contract](API.md#baselines) · [Presets](GUIDE.md#presets)

<a id="limitations"></a>

## Important boundaries

- Empty subject selections fail by default; they are usually a typo, not a clean architecture.
- Malformed included Ruby raises `SourceParseError`. Exclude identified generator templates
  explicitly; a rule selector does not narrow whole-project source discovery.
- Runtime-derived imports, ambiguous constants, inherited lookup, and metaprogramming can stay
  unresolved. Passing a policy describes the resolved static model—not complete runtime behavior.
- Whole-project exclusions and rule selectors serve different purposes. Source symlinks are skipped;
  cached graphs require explicit clearing after edits in a long-lived process.
- Full method-call/signature protocols and semantic component selectors are **not shipped**.
  The [semantic evaluation](https://github.com/dragonsec-ai/ArchUnitRuby/blob/main/design/semantic-boundaries.md)
  is a decision record, not feature parity. Dense cycle enumeration can still be expensive.

[Full analysis contract](GUIDE.md#analysis) · [Errors and troubleshooting](API.md#errors)

<a id="example-project"></a>

## Example project and validation

The [Ruby RAG example](https://github.com/TristanKruse/ArchUnitRuby-TestRepo-RAG) is a small layered
application with intentional architecture violations. Use it for a hands-on walkthrough;
its tests also run against the current checkout in our CI.

The library dogfoods its own architecture. CI checks Ruby 3.3/3.4/4.0 on Linux and Ruby 4.0 on
Windows, gates runtime-library coverage at 98% line / 90% branch, validates docs and package
installation, and runs security checks. Coverage measures executed test paths, not Ruby semantic
completeness or a guarantee that no bugs remain.

Four pinned production-library canaries—Rack, Rake, RSpec Core, and RestClient—exercise passing
and deliberately failing policies. A broader 50-repository source audit and the separate
[Linux performance study](https://github.com/dragonsec-ai/ArchUnitRuby/blob/main/benchmark/study/README.md)
provide bounded evidence, not upstream architecture/security judgments or a universal speed claim.

<a id="documentation"></a>

## Documentation and development

- [User guide](GUIDE.md): recipes, project discovery, exclusions, Ruby analysis, CLI, and migration.
- [API contract](API.md): exact behavior, options, report formats, and errors.
- [Online documentation](https://dragonsec-ai.github.io/ArchUnitRuby/): getting started, guides,
  and searchable source-generated reference; follows `main`.
- [Changelog](CHANGELOG.md), [contributing](CONTRIBUTING.md), [security](SECURITY.md),
  [support](SUPPORT.md), and [release process](https://github.com/dragonsec-ai/ArchUnitRuby/blob/main/.github/RELEASING.md).

To work on the library:

~~~sh
git clone https://github.com/dragonsec-ai/ArchUnitRuby.git
cd ArchUnitRuby
bundle install
bundle exec rake
bundle exec rake docs
~~~

<a id="community"></a>

## Community and license

Maintained by [Tristan Kruse](https://github.com/TristanKruse) and
[Lukas Niessen](https://github.com/LukasNiessen), with our
[contributors](https://github.com/dragonsec-ai/ArchUnitRuby/graphs/contributors).

Part of the ArchUnitEverything family alongside
[ArchUnitTS](https://github.com/LukasNiessen/ArchUnitTS) and
[ArchUnitPython](https://github.com/LukasNiessen/ArchUnitPython).
Questions and feature requests belong in [GitHub Issues](https://github.com/dragonsec-ai/ArchUnitRuby/issues);
report vulnerabilities through [SECURITY.md](SECURITY.md).

[MIT license](LICENSE). [Download analytics](https://clickgems.clickhouse.com/dashboard/archunit)
count package fetches, not unique users.
