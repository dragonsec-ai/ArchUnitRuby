# ArchUnitRuby API Guide

This guide is the stable map of ArchUnitRuby's public fluent API. The
[class and method reference](https://dragonsec-ai.github.io/ArchUnitRuby/class_list.html)
is generated from the source, while this page explains
which entry point to choose and how the stages fit together.

All rule builders are immutable and lazy. Constructing a rule does not read the project; `check`,
`measure`, `snapshot`, and export methods are the terminals that perform work.

This reference follows `main` and documents the 1.x API. Additions requiring 1.1 are labeled;
see [release status](README.md#availability) and check your installed version before copying them.
For recipes use the [user guide](GUIDE.md); for a first rule use the [quickstart](README.md#quickstart).

[1.x compatibility contract](#compatibility) · [Common rule shape](#grammar) · [File rules](#file-rules) · [Layer rules](#layer-rules) · [Slices and diagrams](#slices) · [Dependency graph reports](#graph-reports) · [Metrics](#metrics) · [Checking and test frameworks](#frameworks) · [Check options and logging](#check-options) · [Architecture presets (1.1+)](#presets) · [CLI contract (1.1+)](#cli) · [Errors and support](#errors)

<a id="compatibility"></a>

## 1.x compatibility contract

This guide defines the supported 1.x public surface: documented entry points, fluent methods,
options, public data/error types, and report formats. Additive capabilities can arrive in minor
versions; incompatible public API changes require a major version and migration notes. Private
helpers and classes marked as implementation details are not part of that compatibility promise.
Correctness fixes can change detected violations; compatibility is not a promise to preserve missed
dependencies or misleading clean results.

Static extraction remains bounded and does not execute the target application's source or gemspecs.
Import-only is the default; expanded constant analysis is explicit opt-in. The documented unresolved
lookup cases, project source/exclusion policy, strict parser failures, and explicit cache-clearing
behavior remain important when upgrading. See the [migration guide](GUIDE.md#migration) for changes from 0.0.1.

<a id="grammar"></a>

## Common rule shape

~~~ruby
rule = ArchUnit.project_files
               .in_folder('app/api/**')
               .should_not.depend_on_files
               .in_folder('app/database/**')

violations = rule.check
~~~

| Stage | Public vocabulary | Result |
| --- | --- | --- |
| Entry | `project_files`, `project_layers`, `project_slices`, `project_graph`, `metrics` | Immutable builder |
| Scope | `with_name`, `in_folder`, `in_path`, `in_file`, `for_classes_matching` | Narrower builder |
| Mood | `should`, `should_not` | Positive or negated predicate builder |
| Predicate | File, layer, slice, or metric policy | Checkable rule |
| Terminal | `check`, `measure`, `snapshot`, `to_*`, `export_as_*` | Data or an artifact |

String patterns are anchored globs. `*` stays inside one path segment, `**` crosses zero or more
segments, and `?` matches one non-separator character. A trailing folder glob such as
`app/api/**` includes the `app/api` folder itself and every descendant folder. Regular expressions
are accepted by all pattern selectors except the exact `in_file` selector.

Every pattern selector accepts `except:`. Pass a pattern, an array of patterns, or explicit selector
keys such as `{ in_folder: 'generated', with_name: '*_spec.rb' }`.

<a id="file-rules"></a>

## File rules

Every completed rule implementing `ArchUnit::Checkable` supports `.because(reason)`. Append it
after all selectors and modifiers to get a distinct frozen rule of the same type, with a trimmed,
immutable `rationale` string. Non-string or blank reasons raise `ArgumentError`. The original rule,
violations, graph cache, and `check` options are unchanged. The shared result formatter adds
`Because: ...` exactly once to failed framework-neutral, RSpec, and Minitest assertions, including
failed negated RSpec expectations. Successful assertions and raw violation formatting omit it.

Start with `ArchUnit.project_files(project_locator = nil)`; `ArchUnit.files` is its short alias.
Without a locator, ArchUnitRuby searches upward for a `Gemfile` or gemspec.

Discovery skips symlinked source files and directories, including aliases inside the project root.
Direct `FileInfo` extraction validates canonical as well as lexical containment before reading.
The source walker owns a pruned iterative traversal and reuses one status per entry. Identifiers
come from directory child components under the canonical root, not unchecked absolute-prefix
slicing; the final source list is sorted once. Included entry/listing failures raise
`TechnicalError`, including unreadable or disappearing directories; they are not silently skipped.
This stricter listing-error handling is part of unreleased 1.1.1. Excluded directories are pruned
before their children are listed. Concurrent hostile filesystem mutation is not sandboxed.

The detected root's `.archignore` is applied centrally to graphs and file-based metrics. It accepts
blank lines, full-line `#` comments, basename globs, root-relative path globs, leading `/` anchors,
and trailing `/` directory patterns. Backslashes normalize to `/`. Bare names match at any depth;
patterns containing a separator match from the project root. A directory pattern excludes its
descendants but not a similarly named regular file. Nested ignore files are not read.

Repository patterns combine with defaults or explicit `exclude_patterns:`. An explicit `[]` only
disables defaults, never repository patterns. The normalized effective pattern set participates in
graph cache identity; changing the file is noticed on the next check without `clear_cache`.
Changing source contents still requires explicit cache clearing. Reads are bounded to 1 MiB; UTF-8
BOMs are accepted and invalid bytes replaced. Symlinks (including project-local ones), non-regular
files, negation, NUL characters, and a bare `/` are rejected. No Ruby or gemspec code is evaluated.

Since 1.1, `CheckOptions.new(source_exclusions: ['lib/templates/migration.rb'])` adds
immutable caller-owned globs without changing the target repository. These combine with defaults
and repository policy; legacy `exclude_patterns: []` still disables only defaults. The effective
normalized set determines graph-cache identity, including when API and legacy inputs express the
same policy. Source selectors do not narrow the discovery universe. Included invalid Ruby remains
fatal; no template directories are implicitly skipped. CLI uses repeatable `--exclude-source GLOB`.
Globs are project-relative (optional leading `/`); negation, traversal, drive/UNC paths, NUL/newlines
and empty/root-only patterns are rejected. Counts/cohesion/distance accept the same check options.
For metric HTML, pass `MetricsExportOptions.new(check_options: options)` to `export_as_html`.

| Scope or predicate | Purpose |
| --- | --- |
| `with_name(pattern)` | Select or require a filename pattern |
| `in_folder(pattern)` | Select or require a project-relative directory |
| `in_path(pattern)` | Select or require a complete project-relative path |
| `in_file(path)` | Select one exact project-relative file |
| `have_no_cycles` | Reject cycles among selected project files |
| `depend_on_files` | Allow or reject dependencies matching target selectors |
| `depend_on_external_modules` | Allow or reject standard-library or gem imports |
| `adhere_to(callable, message)` | Evaluate a custom predicate over immutable `FileInfo` values |

~~~ruby
service_scope = ArchUnit.project_files.in_folder('app/services/**')

rules = [
  service_scope.should.have_name('*_service.rb'),
  service_scope.should_not.depend_on_files.in_folder('app/controllers/**'),
  service_scope.should_not.depend_on_external_modules.matching('net/http'),
  service_scope.should.adhere_to(
    ->(file) { file.lines_of_code < 300 },
    'services must stay below 300 non-blank lines'
  )
]
~~~

Positive dependency rules are allowlists: every selected dependency must match at least one target.
Negated dependency rules are blocklists: matching dependencies become violations.

Cycle projection uses iterative traversals. By default, it enumerates all elementary cycles; dense
graphs can have exponentially many results. To report one reproducible closed path per cyclic group,
pass `CheckOptions.new(cycle_reporting: :witness)` to the check. Both modes decide whether the
entire selected file graph is acyclic; the witness list is not a count of all paths.
`CycleViolation#witness?` distinguishes a witness from an exhaustive result.

<a id="layer-rules"></a>

### Named method calls (unreleased)

Use `should_not.contain_calls_named(:delete_all)` or pass a nonempty array of exact names. The
optional `ArchUnit::NamedCallOptions.new(receiver: :bare)` limits the rule to calls with no
explicit receiver. The default `:any` includes explicit `self`, other receivers, and safe
navigation. The positive mood is not supported.

This is a syntactic check. A call to a locally defined method with the same name also matches;
Prism distinguishes method definitions, comments, strings, and local variable reads from calls.
Ordinary operators and attribute/index assignments are included when parsed as explicit calls.
Implicit sends in compound assignments, `receiver.()`, and targets of `send` or `public_send`
are not inferred. Neither alias expansion nor runtime receiver types are checked.

CLI violations add a `call` object with `file`, `name`, `receiver` (`bare`, `self` or
`explicit`), `safe_navigation`, and one-based `line` and byte `column` of the call token.
The `source_calls` analysis scope has no dependency counts. A baseline matches occurrences by
file, method name, receiver form and safe-navigation flag, not receiver identity or line number.
It accepts at most the previously recorded number of matching calls.

Named-call rules share a cached source inventory per project and effective source exclusions. They
don't change or reuse the dependency graph: a mixed graph and call suite has separate source passes.
Use `clear_cache: true` or `ArchUnit.clear_graph_cache` after source edits in a long-lived process.
Included parse errors fail the check, even when the malformed file isn't selected by the rule.

## Layer rules

Use `ArchUnit.project_layers(project_locator = nil)` to name architectural layers and then declare
their allowed or forbidden relationships.

~~~ruby
rule = ArchUnit.project_layers
               .layer('api').defined_by('app/api/**/*.rb')
               .layer('services').defined_by_folder('app/services/**')
               .layer('database').defined_by('app/database/**/*.rb')
               .where_layer('api').may_only_depend_on_layers('services')
               .where_layer('services').may_only_depend_on_layers('database')
               .where_layer('database').may_only_depend_on_layers
~~~

`may_only_depend_on_layers` creates an allowlist. Calling it without targets seals the layer.
`may_not_depend_on_layers` creates a blocklist and requires at least one target. Dependencies inside
one layer are allowed; edges with an unassigned endpoint are ignored.

<a id="slices"></a>

## Slices and diagrams

Use `ArchUnit.project_slices(project_locator = nil)` to capture one segment from project paths.
`(**)` is the glob capture; `defined_by_regex` uses the first regular-expression capture.

~~~ruby
slices = ArchUnit.project_slices.defined_by('lib/my_app/(**)/')

dependency_rule = slices.should_not.contain_dependency('api', 'database')
diagram_rule = slices.should
                     .ignoring_external_slices
                     .ignoring_orphan_slices
                     .adhere_to_diagram_in_file('docs/architecture.puml')

plantuml = slices.to_plantuml
slices.export_as_plantuml('reports/architecture.puml')
~~~

`adhere_to_diagram` accepts inline PlantUML. The supported subset includes components, directed
dependencies, comments, `@startuml`, and `@enduml`.

<a id="graph-reports"></a>

## Dependency graph reports

Use `ArchUnit.project_graph(project_locator = nil)` for queryable snapshots and reports.

~~~ruby
report = ArchUnit.project_graph
                 .include_external_dependencies
                 .focus_on('app/services/**', 2)
                 .collapse_to_folder_depth(2)
                 .titled('Service dependencies')

summary = report.summary
snapshot = report.snapshot
report.export_as_mermaid('reports/services.mmd')
report.export_as_html('reports/services.html')
~~~

Query modifiers are `focus_on(pattern, depth)`, `reachable_from(pattern)`, and
`dependents_of(pattern)`. Group nodes with `collapse_to_folder_depth` or
`collapse_by_pattern(pattern, replacement)`. Formats are DOT, Mermaid, D2, CSV, JSON, and
self-contained HTML; each provides both `to_<format>` and `export_as_<format>`.

<a id="metrics"></a>

## Metrics

Start with `ArchUnit.metrics(project_locator = nil)`. Select files with the standard file selectors
and classes with `for_classes_matching`.

~~~ruby
services = ArchUnit.metrics
                   .in_path('app/services/**/*.rb')
                   .for_classes_matching('*Service')

rules = [
  services.count.method_count.should_be_below_or_equal(20),
  services.lcom.lcom4.should_be(1),
  services.distance.instability.should_be_below(0.8)
]

measurements = services.count.method_count.measure
services.count.export_as_html('reports/service-counts')
~~~

Count metrics cover methods, fields, lines, statements, imports, classes, and top-level functions.
Cohesion provides LCOM96a, LCOM96b, LCOM1-5, and LCOM*. Distance metrics include abstractness,
instability, main-sequence distance, normalized distance, and coupling factor.

Thresholds use exactly `should_be_below`, `should_be_above`, `should_be`,
`should_be_below_or_equal`, `should_be_above_or_equal`, and `should_satisfy`. Use `custom_metric`
for a calculation over `ClassInfo`; zone guards are `not_in_zone_of_pain` and
`not_in_zone_of_uselessness`.

<a id="frameworks"></a>

## Class declaration selection (unreleased)

~~~ ruby
selection = ArchUnit.project_classes(root)
                    .in_namespace('Billing')
                    .descendants_of('::Commands::Base')
                    .selection
~~~

`with_constant_name('Billing::Invoice')` selects an exact class name. `in_namespace` matches
namespace segments, and chained filters use AND. Non-ASCII names retain their Ruby source
encoding; use a selector string in the same encoding as its declaration. Builders are lazy
and immutable. `selection` returns matched classes with contributing declaration locations,
written methods and relationships, plus a separate list of uncertainties.
Its status is `:complete` (matches and no uncertainties),
`:empty` (no match and no uncertainty), or `:unknown` (uncertainties may coexist with matches).
This is inspection, not a test assertion or a baseline-supported rule.

Ancestry uses only known, explicit superclass links. A missing external parent, conflicting reopens,
rebinding, relative lookup we cannot prove, or a cyclic chain can leave selection unknown. No
runtime reflection, effective methods, implicit `Object`, or mixin ancestry is inferred. The
selector covers all in-scope declaration sites for a class, not a particular folder or load order.
Use `CheckOptions.new(source_exclusions: ...)` to limit the source set. Cached declaration facts
refresh with `clear_cache: true` or `ArchUnit.clear_graph_cache`.

### Declared method signatures (unreleased)

~~~ ruby
shape = ArchUnit::MethodSignature.new(name: :call, positional: 1, keywords: %i[actor request_id])
rule = ArchUnit.project_classes(root).in_namespace('Commands').should.declare_method(shape)
ArchUnit.assert_passes(rule)
~~~

The rule requires an ordinary `def` on each selected class that accepts the specified call.
`positional` is the number passed, not the number written. `keywords` is the exact set passed:
omitting a required keyword fails, and a keyword-rest parameter accepts extras. Implicit conversion
to a positional Hash is not a named keyword interface. `scope: :singleton` checks `def self.call`
and `class << self`; `block: :declared` requires explicit block capture or forwarding syntax.
The default is `scope: :instance, block: :any`.
Use method and keyword names in their declared source encoding for non-ASCII identifiers.

This is declaration-only: methods inherited or supplied by mixins, aliasing, or metaprogramming
do not satisfy it. It does not prove public visibility, receiver behavior, or return types.
Conditional definitions, ambiguous class selection, or conflicting signatures fail as unknown.
Multiple known declarations satisfy the rule if they all accept the requested call. Empty scopes
fail unless explicitly allowed; that option does not suppress unknown results. The negative mood
is not offered.

The same scope is available as `project_classes` in a named CLI rule. JSON adds a
`method_signature` object carrying the expected shape, observed candidates and source locations.
Non-ASCII identifiers in legacy encodings are reported with `text`, `encoding`, and hex
`bytes` rather than a bare string; this preserves distinct Ruby names with the same spelling.
Confirmed failures can use baselines; the fingerprint includes the normalized selector and
expected shape. Unknowns fail a plain CLI check (exit 1) and reject baseline creation or use
before any accepted-debt write (exit 2).

## Checking and test frameworks

Every architecture rule includes `ArchUnit::Checkable` and exposes `check(options = nil)`. It returns
an array of structured `Violation` values; an architecture disagreement is not an exception until
an assertion adapter translates it at the test boundary.

~~~ruby
violations = rule.check

expect(rule).to pass         # RSpec
assert_passes(rule)          # Minitest
ArchUnit.assert_passes(rule) # Framework-neutral
~~~

Use `ArchUnit.format_violations` or `ArchUnit::ResultFactory` when integrating with another test
framework or command-line interface.

<a id="check-options"></a>

## Check options and logging

`ArchUnit::CheckOptions` keeps optional execution behavior out of the fluent sentence:

~~~ruby
logging = ArchUnit::LoggingOptions.new(
  level: :debug,
  output_directory: 'tmp/archunit-logs'
)

options = ArchUnit::CheckOptions.new(
  allow_empty_tests: false,
  clear_cache: false,
  load_paths: ['components/billing/lib'],
  dependency_analysis: :imports,
  logging: logging
)

violations = rule.check(options)
~~~

Zero selected subjects produce `EmptyTestViolation` by default. Set `allow_empty_tests: true` only
when an empty scope is intentionally valid. Set `clear_cache: true` after modifying the analyzed
project during one process. `load_paths` adds project-contained source roots without evaluating
gemspecs or running application code.

`dependency_analysis` defaults to `:imports`. Imports accept literal arguments and preceding local
literal-string assignments in supported straight-line scopes. Aliases, mutation/escape, closures,
reflection, and unsupported control flow invalidate inferred values; runtime paths are not guessed.

Since 1.1, the bounded file-relative whitelist also accepts `__FILE__`, implicit `__dir__`, literal/static
string `+`, `File.dirname(absolute_expression)` and `File.expand_path(path, absolute_base)`
(also `::File`, or one absolute operand for `expand_path`). Operands cannot contain local-variable
reads or arbitrary calls; the completed result may be assigned to a local. No source is evaluated.
Source-local core overrides/reflection disable affected inference; arbitrary cross-file core
monkey-patching is not modeled. See the [resolution guide](GUIDE.md#analysis) for exact limits.

Since 1.1, `rails_imports: true` separately opts into implicit/`self.require_dependency`
calls. Accepted paths use the same literal/local/static contract, and edges use
`:require_dependency`. Explicit `load_paths` are searched first for this helper only; ordinary
`require` resolution is unchanged. Custom receivers are ignored; local helper overrides/reflection
and unknown operands remain unresolved. No Rails boot or automatic autoload-root discovery occurs.
The option is immutable, validated and part of graph-cache identity; it composes with either
dependency-analysis mode. Cross-file method replacement and dynamic Rails/glob values are not modeled.

### Explicit Rails associations (unreleased)

`CheckOptions.new(rails_associations: true)` independently enables dependencies from supported
Rails model calls such as `belongs_to :store, class_name: '::Storage::Store'`. It can be combined
with either analysis mode and with `rails_imports`; neither previously shipped option enables it.
A unique known class declaration contributes a `:rails_association` edge with call-site and
definition lines. It shares an edge with any import or constant reference to the same file.

Use `--rails-associations` or `--no-rails-associations` in the CLI. Enabled scopes have separate
baseline identities and report candidate, unresolved and ambiguous counts; disabled output and
fingerprints stay unchanged. See [supported syntax and limitations](GUIDE.md#rails-associations).

For autoloaded projects, opt into known project constant references alongside imports:

~~~ruby
options = ArchUnit::CheckOptions.new(dependency_analysis: :imports_and_constants)
violations = rule.check(options)
json = ArchUnit.project_graph.with_check_options(options).to_json
values = ArchUnit.metrics.distance.instability.measure(options)
~~~

Expanded analysis resolves supported lexical, compact, and root-qualified references to their
definition files. Explicit superclass and mixin references also contribute edges. Missing or
ambiguous definitions, inherited-member lookup, and dynamic metaprogramming stay unresolved under
the bounded contract in the main guide. Namespaces that fail to stabilize within eight index passes
fall back to import-only results. Unknown third-party constants do not create architecture violations.

Declarations include ordinary `=` and conditional `||=`, with lexical/qualified/root-qualified
ownership and definition evidence. This does not predict runtime execution or load order. Multiple
definition files remain ambiguous; update-only compound and multiple-assignment forms are not
inferred as new declaration owners.

Expanded edges include `:constant_reference` in `import_kinds` and retain `DependencyEvidence` with
names and source lines in `edge.evidence` and JSON reports. An import and a constant use supporting
the same file pair merge into one edge. Import-only edge evidence stays empty for compatibility;
`ArchUnit::Extraction.extract_imports` retains import call locations in both modes. The analysis
mode participates in graph-cache identity, and `clear_cache: true` rebuilds the symbol index.

### Semantic boundaries

Method-call restrictions, effective method/signature protocols, and semantic component selectors
are not provided by the current file graph or metric method facts. The bounded
[semantic evaluation](https://github.com/dragonsec-ai/ArchUnitRuby/blob/main/design/semantic-boundaries.md)
records exact comparator pins, executable probes and the compatibility/unknowns required before
adding such APIs. This is a technical evaluation, not a newly shipped semantic backend.

<a id="presets"></a>

## Architecture presets (1.1+)

`ArchUnit.architecture_preset(name, options = nil)` returns an immutable Checkable `PresetRule`.
`ArchUnit::PresetOptions.new(project_locator: nil, folders: {})` is its options bag. Names are
`:layered`, `:hexagonal`, or `:rails`; unknown names and malformed/duplicate override layer keys fail
at construction. Each folder override is a non-empty String or Array of source globs; multiple
patterns are ORed within one layer. No project reads occur until check.

Layered maps presentation/application/persistence to `app/api/**`, `app/services/**`, `app/db/**`,
allowing only presentation→application and application→persistence across layers. Hexagonal maps
domain/application/adapters to `app/domain/**`, `app/application/**`, `app/adapters/**`, allowing
application→domain and adapters→application/domain. Rails maps controllers/services/models to
their `app/` folders, allowing controllers→services/models and services→models. Same-layer edges
are allowed; the innermost layer has no allowed outgoing cross-layer edge. All mappings are
overridable. Unmapped files/external modules are outside this policy, not excluded from extraction.

Presets construct `LayeredArchitecture` rules and use existing assertion code. The guard rejects
observed files matching multiple layers with UserError; empty layers use the normal
EmptyTestViolation defense unless explicitly permitted. CheckOptions controls analysis, exclusions,
cache and logging as usual; source parse errors remain fatal. `.because` and framework matchers
work normally. Rails conventions do not boot Rails or automatically turn on expanded/helper modes.
For an autoloaded Rails app, pass
`CheckOptions.new(dependency_analysis: :imports_and_constants)` to `check` or `assert_passes`
(CLI: `--dependency-analysis imports_and_constants`). Otherwise, a check can pass without seeing
references between mapped layers that have no imports. See [choosing a mode](README.md#analysis).
These presets are not complete architecture/cycle/protocol verification; compose more rules or
build arbitrary policies with `project_layers`.

Trusted CLI configurations have `architecture_preset(name, options = nil)`, defaulting the locator
to their selected project root. This preserves the public locator/auto-discovery distinction.

<a id="cli"></a>

## CLI contract (1.1+)

The executable requires 1.1 or newer; it is not included in 1.0.0. It wraps
Checkable rules without changing RSpec/Minitest or the library's default analysis mode.

~~~sh
archunit init --project .
archunit check --project . --format json
archunit check --dependency-analysis imports_and_constants
archunit check --rails-imports --load-path app/models --load-path app/services
archunit explain --config ./trusted-architecture.rb
~~~

`init` checks the filesystem entry itself and uses exclusive creation to reject existing paths,
including dangling symlinks on Windows. This is not a sandbox against a hostile process concurrently
replacing filesystem entries. The default configuration is
`PROJECT/.archunit.rb`; an explicit `--config` path is relative to the invocation directory. The
project defaults to that working directory. Named declarations are
`rule('unique name') { completed_checkable }`; the configuration helpers `project_files` / `files`,
`project_layers` / `layers`, `project_slices`, and `metrics` use the selected root. Rules must be
non-empty and uniquely named. Every `check` command starts with a fresh graph cache, then shares
that cache across its rules.

Configuration is trusted executable Ruby, not an isolation boundary. `explain` loads the same Ruby
configuration but never calls its rules' `check` methods. It reports `configured` and per-rule
`not_checked`, not an architecture pass. It lists rule names/rationale and settings, not a full
semantic explanation or focused-path report. Avoid stdout writes in configuration when requesting
machine-readable output. No target source, Gemfile, or gemspec is automatically executed by the CLI;
the caller's own Bundler/configuration code retains its normal Ruby behavior.

Exit codes: **0** for a successful informational/init/explain command or all checked rules passing;
**1** for architecture violations; **2** for argument/configuration/analysis errors. Empty selectors
remain violations. Text errors go to stderr; JSON diagnostics go to stdout without color. The
format option applies to init/check/explain and errors; help/version remain plain text.

`--format json` produces one document with `schema_version: 1`, `archunit_version`, `command`,
`project_root`, `config_path`, `dependency_analysis`, `rails_imports`, `load_paths`, `source_exclusions`,
`status`, `rules`, `analysis`, and `summary`. The new settings/diagnostics are additive schema-1 fields.
With `check --cycle-reporting witness`, the report adds `cycle_reporting: "witness"` at the top
level and on each witness violation. The default (`exhaustive`) omits these fields. The summary
counts reported violations, not all possible cycles. Witness mode cannot generate or use a baseline.
Rule entries carry `name`, nullable `rationale`, `status`, `analysis`, and `violations`;
each violation carries its `type`,
shared formatter `message`, and `details`. Summary counts describe completed/listed rules and their
violations; an analysis error may stop later rules, so a partial summary is never a pass. An error
adds `error.type`, `error.message`, and nullable `error.rule_name`; a `SourceParseError` also adds
`error.diagnostics` with path, one-based line/column, and message. Messages/details are for people,
not stable violation fingerprints. The CLI implementation classes are not a new fluent API.

### Analysis diagnostics

`analysis` contains `status` (`available`, `partial`, or `unavailable`), `scopes`, and a limitations
`notice`. Each scope contains:

- `id`, `project_root`, `kind` (`dependency_graph` or `source_metrics`), and `status`
  (`analyzed` or `error`). IDs are local to one invocation, not stable fingerprints.
- The actual `dependency_analysis`, `rails_imports`, explicit `load_paths`, and sorted
  `effective_source_exclusions` (defaults + repository policy + caller exclusions).
  Dependency settings are null for source-only metrics, which do not construct a dependency graph.
- `counters`: `source_files`, `imports`, `unresolved_imports`, `unresolved_constant_references`,
  and `ambiguous_constant_references`. Constant counters are null in imports-only mode;
  all counts are null when extraction fails, rather than presenting a partial parse as success.
- `observations`, `cache_hits`, and the `rule_names` using that snapshot. Cached graphs retain their
  original measured counts, even if first extracted without a timing profile. Refreshed graphs
  become separate snapshots; roots, policies, and modes are not conflated.

Each rule's `analysis` contains an availability `status` and its `scope_ids`. `explain`, `init`,
and custom checks doing no built-in extraction have unavailable diagnostics, not zero counts.
Mixed measured/unobserved rules produce partial availability. Analysis scopes are not summed:
multiple roots can overlap, and a metric pass and a graph pass can inspect the same files.
`source_files` counts all included sources before fluent selectors, not matched rule subjects.
Scopes describe synchronous built-in extraction in the current check, not arbitrary user work
started in other threads/fibers.

In the development version, `analysis.advisories` is an optional schema-1 array. Each entry has
a stable `code`, affected `rule_names`, and the same `message` as the text report. The
`rails_no_scoped_imports` hint applies only to passing, populated Rails presets in imports mode
with zero cross-file imports among their selected files. It does not count skipped constants or
affect violations, baselines or exit codes. No advisory field is emitted when there is no hint.

`imports` counts accepted static import expressions, including external imports.
Unresolved imports count unsupported/dynamic import expressions; literal external gem imports are
not counted as unresolved expressions. Unresolved/ambiguous constant observations can include
external symbols, unsupported Ruby lookup, or definitions reopened across files. They are neither
proven missed internal dependencies nor a semantic-completeness percentage. They do not change
exit status; included parse failures remain errors. A passing policy only describes the statically
resolved graph, not proof of complete runtime architecture. Warm timing profiles still measure
actual work (zero repeated cold counters); diagnostic snapshots are separate from those profiles.

<a id="baselines"></a>

### Explicit violation baselines (1.1+)

`archunit baseline --output FILE.json` evaluates every rule and atomically writes an explicitly
reviewable accepted-debt document. It refuses existing output without `--force`, non-JSON output
names, empty-selection violations, custom/unknown violation types, and unobserved scopes. No output
is written until all rules finish; parse/configuration failures never replace existing debt.
`archunit check --baseline FILE` remains read-only. All sources/rules are still checked; it returns
0 only when there are no new violations or stale entries. A run with accepted violations has
`status: accepted`, not `passed`. Baseline creation has `status: baseline_created`, not an
architecture pass. Without either flag/command normal strict checks are unchanged.

The document has `schema_version: 1`, `fingerprint_version: 1`, and `entries`. Each entry contains
`fingerprint` (SHA256 of canonical rule/type/data/context), positive occurrence `count`, `rule`,
`type`, structured `data`, and scope `context`. Input validates schema, duplicate fingerprints,
counts, fingerprint/data consistency, size (2 MB), nesting (32) and entry limit (10,000). Paths are
project-relative; regex source/options are data. Line evidence, formatter wording, object identity,
graph counters/cache state and checkout absolute paths are not identity. Actual source policies and
dependency-analysis settings are included, so a different mode/policy cannot silently reuse debt.
Deleted/renamed rules leave stale entries. Counts are matched one-to-one, not set membership.

Built-in file/external dependencies, patterns, simple directed cycles, layer/slice dependencies,
and numeric metric thresholds have explicit adapters. Metric predicates/zones, custom violations,
empty selectors and unsupported types are never auto-recorded; under an existing baseline they
remain new violations. There is no generic `inspect`/formatted-message fallback. Public Checkable
results are unchanged; this first delivery is CLI-only.

Schema-1 CLI output adds `baseline` metadata. During check it contains `status: checked`, `path`,
`accepted_count`, `new_count`, `stale_count` and `stale_entries`; every raw violation retains its
original type/message/details and adds `baseline.status` (`accepted` / `new`) and nullable
`baseline.fingerprint`. Per-rule status can be `accepted`. Existing summary violation counts remain
raw counts, not just new debt. Invalid input/IO/analysis exits 2, new/stale debt exits 1. Atomic
creation uses a same-directory hard link (unsupported filesystems fail closed); force replacement
uses rename after rejecting non-regular paths. Concurrent hostile filesystem mutation is outside
this library's isolation guarantees. Do not blindly regenerate baselines in CI.

<a id="errors"></a>

## Errors and support

Invalid API input raises `ArchUnit::UserError` or `ArgumentError`; library or environment failures
raise `ArchUnit::TechnicalError`. Rule failures remain violation data.

Malformed included Ruby raises `ArchUnit::SourceParseError`, a `TechnicalError`, during graph or
AST-metric extraction. No partial graph is returned or cached. `error.diagnostics` is an immutable
array of `ArchUnit::ParseDiagnostic` values with `path`, one-based `line`/`column`, and `message`;
each value supports `to_h`. RSpec/Minitest assertions propagate this technical failure instead of
reporting a pass or an ordinary architecture violation. Excluded files are not parsed. The profile's
`malformed_files` counter records a rejected file; existing cache-clearing rules still apply.

See the [quickstart](README.md#quickstart) and [user guide](GUIDE.md) for complete examples, [SUPPORT.md](https://github.com/dragonsec-ai/ArchUnitRuby/blob/main/SUPPORT.md)
for help, and [SECURITY.md](https://github.com/dragonsec-ai/ArchUnitRuby/blob/main/SECURITY.md) for
responsible vulnerability reporting.
