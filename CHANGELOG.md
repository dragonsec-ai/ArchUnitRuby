# Changelog

## 1.1.1 (unreleased)

- Reuse one source-entry status, compile exclusion matching once, and build relative identifiers
  from directory children in a pruned iterative source walker, preserving sorted graph inputs.
- Fail closed on unreadable/disappearing included directory listings instead of inheriting Find's
  silent listing-error skip. Excluded trees are still pruned without opening their descendants.
- Extend the existing extraction benchmark with allocation counts, full graph/evidence digests,
  and excluded-tree workloads; retain generous CI timing ceilings.

## 1.1.0 - 2026-11-23

Additive release over 1.0.0. Import-only analysis remains the default; the CLI and Rails helpers
are opt-in. Existing RSpec/Minitest rules keep the 1.x API contract. Correctness fixes can reveal
previously missed dependencies, so review newly detected violations rather than suppressing them.

- Rework getting-started documentation with a concise README, preserved user guide, explicit
  published/development availability, canonical organization URLs and executable example/link checks.

- Compose layered, hexagonal and Rails folder presets from existing layer rules, with immutable
  pattern overrides, CLI integration, overlap errors and unchanged empty/source-analysis defenses.

- Add explicit CLI accepted-debt baselines with versioned structured fingerprints, one-to-one
  occurrence matching, stale-entry failures, strict JSON validation and safe explicit output.

- Expose additive CLI analysis scopes with source/uncertainty counts, truthful warm-cache reuse,
  unavailable values for unperformed/failed analysis, and explicit static-analysis limitations.

- Add immutable caller-owned source exclusions and CLI `--exclude-source`, applied consistently
  to graphs, source/coupling metrics and reports without editing target repositories.

- Add explicit static Rails `require_dependency` imports, separate helper search-root priority,
  and CLI `--rails-imports` / repeatable `--load-path` options without booting Rails.

- Fold a bounded, source-aware whitelist of file-relative import expressions without evaluating
  source, including RestClient-style `File.dirname(__FILE__) + '/feature'` imports.

- Record namespace-owner dependencies in qualified class/module declarations and constant writes
  in expanded analysis, preserving lexical lookup, ambiguity handling, and source evidence.

- Recognize `load(path, wrap)` dependencies and count dynamic/variadic wrapped paths as unresolved,
  without reusing stale local strings across effectful wrap expressions or block conversions.

- Add an opt-in `archunit` executable with non-destructive configuration initialization, named
  Checkable rules, check/explain commands, text or versioned JSON diagnostics, and explicit
  success/violation/error exit codes.

- Add isolated Linux performance studies and a bounded semantic evaluation for maintainers;
  these do not add a runtime analyzer dependency or claim full method/protocol semantics.

## 1.0.0 - 2026-10-26

First stable API baseline. The previously unreleased 0.0.2 development work is included here;
0.0.1 remains the preceding published version. See the user guide's migration notes before upgrading.

- Fail closed on malformed included Ruby in dependency graphs and AST metrics, with structured
  source diagnostics and profile counters instead of silently treating incomplete analysis as clean.

- Add development-only locked dependency scanning with advisory refresh, fail-closed health checks,
  Windows path normalization, and retained CI reports.

- Avoid stack overflows in strongly-connected-component detection, elementary-cycle traversal,
  and blocked-vertex propagation on deep dependency graphs.
- Skip symlinked source entries and enforce canonical project boundaries for direct file metadata.
- Reuse source-entry file status instead of repeating separate directory and file probes.
- Validate version/changelog/lock consistency in CI and require prepared release metadata before
  RubyGems publication.
- Enforce the unchanged coverage thresholds on runtime library source only, with a real-report
  regression check that excludes loaded specs, benchmarks, and scripts from the denominator.

- Apply bounded project-root `.archignore` exclusions consistently to dependency graphs and metrics,
  with cache invalidation, cross-platform glob handling, and configuration safety checks.

- Add immutable `.because(...)` explanations to every executable rule and shared assertion output.

- Add opt-in debug inspection of project roots, graphs, and selected files on cold and cached checks.
- Log passing metric values without repeating custom calculations.
- Document verbosity, CI log artifacts, and existing colored violation reports.

- Add opt-in project constant-reference dependencies with lexical lookup and conservative ambiguity handling.
- Index lexical, qualified, and root-qualified `||=` declarations in expanded analysis without
  executing source or changing import-only mode.
- Infer import paths from safely known local literal strings without evaluating application code.
- Preserve dependency source evidence in expanded mode through graph merging and JSON reporting,
  while keeping import-only edge values compatible with existing consumers.
- Support check options on metric measurements and add installed-gem extraction regression checks.
- Make trailing folder globs such as `app/api/**` include the named folder itself.
- Validate the README quickstart as a passing and failing end-to-end architecture test.
- Add a curated API guide, reliable Markdown rendering, responsive documentation navigation, and
  documentation quality checks.
- Add the ArchUnitRuby family logo, social preview, and repository community health files.
- Discover adjacent `lib` directories in multi-gemspec repositories without evaluating gemspecs.
- Support validated, project-local custom load paths through `CheckOptions`.
- Add cold/warm extraction profiling, a reproducible benchmark, and resolution caching.

## 0.0.1 - 2026-08-11

Initial executable prototype.

- Analyze Ruby dependencies expressed with `require`, `require_relative`, `autoload`, and `load`.
- Enforce file, layer, slice, PlantUML, and custom-predicate architecture rules.
- Measure count, cohesion, coupling, instability, abstractness, and main-sequence metrics.
- Export dependency graphs and metric reports in machine-readable and visual formats.
- Integrate with RSpec, Minitest, or framework-neutral assertions.
- Provide per-check logging, selector exclusions, generated API documentation, and Ruby 3.3+
  compatibility.
