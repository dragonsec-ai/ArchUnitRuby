# Analysis diagnostics evidence (#82)

Validated against Discourse at commit `2de9c9be4f89e392fe500dd27f928d6b1184bf09` using the
production-source view from the 50-repository audit. No application source, Gemfile, or gemspec
was executed, no target dependencies were installed, and target Git status remained unchanged.
This is a reproducibility record, not a claim that this static subset models all of Discourse.

## Scope

The sparse checkout included `/lib/**/*.rb`, `/app/**/*.rb`, `/config/**/*.rb`, `/src/**/*.rb`,
root `/*.rb`, `/*.gemspec`, `/Gemfile`, `/.archignore`, `/LICENSE*`, and `/README*`, excluding
all `fixtures`, `spec`, `test`, and `tests` directory contents. The library's default source
exclusions remained enabled; no extra source exclusions, Rails helper opt-in, or explicit load
paths were supplied. It contains 2,510 analyzed Ruby files. A full checkout is a different scope
and need not produce these numbers.

## Result

Two intentionally permissive maintainer-owned rules were loaded from outside the target:

```ruby
rule('all Ruby files') { project_files.should.have_name('*.rb') }
rule('same files cached') { project_files.should.have_name('*.rb') }
```

Both passed with exit 0 in both modes. In each CLI invocation, JSON contained exactly one
`dependency_graph` scope, `observations: 2`, `cache_hits: 1`, both rule names, and matching
per-rule scope IDs. Each non-null counter was checked against a separate cold extraction's
`ExtractionProfile`, not merely against the other rule's cached result.

| Counter | `imports` | `imports_and_constants` |
| --- | ---: | ---: |
| Source files | 2,510 | 2,510 |
| Accepted static import expressions | 640 | 640 |
| Unresolved import expressions | 13 | 13 |
| Unresolved constant-reference observations | unavailable | 21,507 |
| Ambiguous constant-reference observations | unavailable | 2,095 |

These are the counts after #79/#80, not the earlier audit's pre-fix numbers. No semantic-coverage
percentage is derived. External symbols, unsupported lookup, and cross-file reopenings contribute
to uncertainty; these are not counts of confirmed missed internal dependencies. The permissive
policy deliberately passes even with unknowns.

## Reproduce the diagnostics

Use a trusted configuration outside a checkout with the scope above, and run from this library's
development bundle (do not run Bundler in the untrusted target):

```sh
bundle exec archunit check --project /path/to/pinned/discourse \
  --config /path/to/trusted-rules.rb --format json \
  --dependency-analysis imports_and_constants
```

For the independent profile comparison:

```ruby
require 'archunit'
profile = ArchUnit::Extraction::ExtractionProfile.new
options = ArchUnit::CheckOptions.new(dependency_analysis: :imports_and_constants)
ArchUnit.clear_graph_cache
ArchUnit::Extraction.extract_graph('/path/to/pinned/discourse', options: options, profile: profile)
puts profile.counters
```

Small deterministic controls live in `spec/extraction/analysis_observer_spec.rb` and
`spec/cli/analysis_spec.rb`. They cover unsupported import expressions, unresolved and ambiguous
constants, inherited vs. explicit-root lookup, empty source universes, errors, warm profiles,
multiple roots/settings, cache refresh, metric-only/custom checks, and observer isolation.
`scripts/check_analysis_diagnostics.rb` exercises a real CLI subprocess in the compatibility
matrix and again against the isolated installed gem.
