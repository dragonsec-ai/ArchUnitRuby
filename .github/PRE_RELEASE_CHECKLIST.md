# Stable-release readiness

The original feature backlog (#47, #48, #54, #55) and the correctness/QA audit fixes (#63-65) are
merged. PRs #68-70 were reviewed and merged on 2026-10-26; the resulting `main` passed CI, security
scanning, and documentation deployment. The 1.0.0 preparation and publication below are historical:
1.0.0 was published and verified in #71. The old evidence counts below are historical, not the
current suite or authorization to publish a new version.

## 1.1.0 release candidate - 2026-11-23

- [x] Merge the roadmap follow-ups (#93–96) and professional documentation (#97).
- [x] Keep version and local-gem lock at 1.1.0; date the changelog and target 1.1 in installation
  instructions. Label additive features as 1.1+ without claiming publication before registry proof.
- [x] Run strict release metadata validation, full coverage/lint/dogfood checks and documentation.
- [x] Refresh advisory data and pass the locked dependency scanner and vulnerable-fixture control.
- [x] Strictly build and install the candidate in an isolated gem home; run the installed API/CLI,
  baseline, preset and documented-example acceptance scripts.
- [ ] Pass GitHub's compatibility/package/security and pinned real-world canary checks.
- [ ] Verify the RubyGems trusted publisher uses `dragonsec-ai/ArchUnitRuby`, `release.yml`,
  environment `release`; never use a publish attempt merely to inspect credentials.
- [ ] Merge through the normal PR process and verify the exact release `main` revision is green.
- [ ] Dispatch `Release` for 1.1.0 with maintainer authorization; verify its tag, registry checksum,
  and a clean RubyGems installation with passing/failing checks before announcing publication.

Preparation is not publication. Until RubyGems lists 1.1.0, 1.0.0 remains the published version.
The release environment currently has no required approval rules; do not weaken protections or
bypass review. Repository write permission and RubyGems ownership are separate permissions.

Local candidate evidence (2026-11-23, Windows/Ruby 4.0.6): 898 examples, zero failures, ten native
symlink skips; 98.69% library line / 92.16% branch coverage; 342 lint-clean files; 204 validated
documentation pages; 1,411 refreshed advisories with zero findings and the vulnerable-fixture
control passing. All twelve installed-gem regression/acceptance scripts pass from a fresh gem
home, including CLI init/check/explain, diagnostics, baselines, presets and README examples.

## 1.0.0 preparation

- [x] Merge the reviewed extraction, source-boundary, cycle, parser-diagnostic, conditional-constant,
  and coverage fixes without bypassing protections.
- [x] Document the import-only default, explicit expanded mode, stable public surface, and migration
  from 0.0.1. Unknown runtime behavior and ambiguous or unsupported names remain analysis limits.
- [x] Synchronize version 1.0.0, local lock entry, dated changelog, and installation instructions.
- [x] Run `bundle exec ruby scripts/check_release_metadata.rb --release` on the candidate.
- [x] Run the full coverage/lint/dogfood suite, build/link-check docs, and check both public-API
  smoke scripts. Native symlink skips on Windows must also be exercised in Linux CI.
- [x] Refresh advisory data and pass `bundle exec rake security`, including scanner-health checks.
- [x] Check passing/failing rules and both dependency modes on the pinned Rack/Rake/RSpec corpus.
- [x] Build with `gem build --strict`, install that exact artifact in an isolated gem home, confirm
  its version/path, and exercise the installed API from a clean project without the source checkout.

Preparation evidence (2026-10-26): 614 examples, zero failures, eight native-symlink skips on Windows;
98.48% library line and 91.51% branch coverage; 267 Ruby files lint-clean; 179 validated documentation
pages; 1,269 fresh advisories with no findings and the vulnerable-fixture health check passing.
All six pinned corpus/mode baselines matched. The isolated installed 1.0.0 artifact passed a clean
rule, an intentionally failing one-line import change, conditional-constant policies, exclusion
refresh, and strict malformed-source diagnostics, plus both dependency-analysis smoke scripts.

## Publication remains a separate approval

- [x] Review and merge the preparation PR, then verify the full matrix on that exact `main` revision:
  supported Ruby versions, Windows/Linux, library-only coverage, lint, dogfooding, docs, packaging,
  installed-gem checks, security, and the downstream RAG fixture.
- [x] Confirm the changelog date at publication and explicitly authorize the trusted-publisher
  `Release` workflow for version `1.0.0` on `main`. Verify the RubyGems account and configured release
  environment still belong to the intended maintainers. Never publish merely to run checks.
- [x] Verify the published 1.0.0 gem and generated tag, install from RubyGems in a clean project,
  and rerun passing/failing architecture examples before announcing availability.

Publication evidence: #71 (registry checksum, tag and clean-project acceptance verified).
CLI execution/diagnostics (#73, #88), baselines (#89), presets (#90), bounded semantic evaluation
(#91), and representative Linux performance studies (#92) are merged; roadmap #66 is complete.
These additions belong to 1.1, not the historical 1.0 API baseline, and do not claim that full
method/protocol semantics are implemented. The 1.1 release has its own readiness and publication
gates above.

## Audit coverage added

- 10,000-node chains, directed rings, and unblock cascades; deterministic mutual-reachability and
  exhaustive small-graph oracles protect the iterative algorithms' correctness.
- Source symlinks inside/outside the project, broken links, directory links, canonical file boundaries,
  and incompatible-volume errors. Native-link tests run on Linux; portable boundary tests also run
  on Windows hosts without symlink privileges.
- Metadata consistency and strict release gating, inspired by ArchUnitPython's existing metadata
  validation. Unlike automatic sibling publishing, Ruby publication remains a deliberate dispatch.

These are targeted regression tests, not a claim that every bug has been found or a security
certification. Analysis does not execute application code, but it is not an OS-level sandbox for
an actively changing or hostile filesystem. Dense graphs can have exponentially many cycles.

## Next useful improvements

- The pinned real-world canary is implemented with manually triggered/relevant-PR checks, reviewed
  graph fingerprints, and cold/warm/memory evidence. Review its stability and cost before scheduling
  it or tightening thresholds; the small lib-only corpus is not a full Rails benchmark.
- Dependency vulnerability scanning is available as a separate task/workflow. Consider mutation
  testing as another measured addition; high line coverage is not proof of semantic correctness.
