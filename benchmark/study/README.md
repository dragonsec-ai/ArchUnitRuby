# Representative performance study (#92)

This research bundle is separate from the production gem. Comparison pins: ArchSpec 1.1.0,
RubyDEX 0.4.0, Prism 1.9.0, JSON 2.21.2 and CSV 3.3.7. Its lock contains Linux/Windows native
package checksums without changing root dependencies. The candidate is the checkout revision,
not necessarily the published gem.

For the separate source-discovery optimization follow-up (#100), see the
[root extraction benchmark](../README.md#source-discovery-follow-up-100) and its paired-sample
JSON. The manual performance workflow also runs that unchanged generator/harness against the
v1.1.0 and candidate libraries on Linux/Windows, using only the normal production bundle.

## Repeated-rule follow-up (#101)

`rule_suite.rb` reuses this study's generated four-engine fixture, oracle, clock and memory helpers.
It needs only the root production bundle; it does not install or execute any target dependencies.
Run each workload in a fresh process, alternating baseline/candidate order across at least three
trials. Compare against `e2d347e14e0f8d06489582bcb7c5473295a7df4b` (merged #100), copying only
`fixture.rb`, `rule_policies.rb`, `rule_samples.rb` and `rule_suite.rb` into the baseline's study
directory so both runtime libraries receive the identical measurement harness.

```sh
STUDY_PAIRS=5000 bundle exec ruby benchmark/study/rule_suite.rb graph pkg/rules-graph.json
STUDY_PAIRS=5000 bundle exec ruby benchmark/study/rule_suite.rb one pkg/rules-one.json
STUDY_PAIRS=5000 bundle exec ruby benchmark/study/rule_suite.rb identical pkg/rules-identical.json
STUDY_PAIRS=5000 bundle exec ruby benchmark/study/rule_suite.rb varied pkg/rules-varied.json
```

Workloads use 10,000 sources and 5,000 independently known API-to-database dependencies.
`one` checks one nonempty passing boundary; `identical` repeats it twenty times; `varied` runs
seven file, seven layer and six different slice policies. All must pass, while separate forbidden
dependency and empty-selector controls must fail with the expected data/counts. The ordered graph
and evidence digest must match across checkouts. A fast incorrect check aborts the run.

- `cold_graph`: actual graph extraction only, after explicit clearing.
- `cold_plus_suite`: a separate cold graph plus the entire policy suite. Cache clearing and GC
  occur before, outside the timer. This does not include Ruby startup, fixture generation or cold disk.
- `warm_rules`: individual public checks after that complete suite; include normal graph lookup,
  rule-specific selection and assertion. Their sum is warm suite time, not CLI/process startup.
- Every timed stage records allocated objects. Post-GC Ruby heap is recorded before analysis, after
  graph extraction, and after the cold suite. It excludes native memory; Linux peak RSS is a
  process-lifetime high-water mark (including both cold stages), not an individual stage's peak.
  Windows unavailable RSS is null. Controls run after retained-memory measurements.

Only three built-in graph-invariant views are lazy/shared per existing cached analysis entry:
nodes, internal edges and external edges. Storage grows with that analysis's graph, not the number
of rules. This adds retained O(V+E) memory when requested; raw graph consumers do not eagerly build
indexes. There is no new graph-keyed global query cache. The existing graph snapshot cache still
retains entries until explicit clearing; it is not a content-watching or LRU cache. Per-entry/global
clearing drops the associated views. Rules already running may finish on their original snapshot.

Selectors, callbacks, FileInfo reads, cycle enumeration, logging and arbitrary custom projections
still run per check. Slice labeler closures may capture mutable state, even when the Proc is frozen;
their outputs are intentionally not memoized. Thus varied-suite measurements include unchanged
slice work and do not imply that all policy types benefit equally.

The manual workflow runs three alternating paired trials for all four workloads on Linux/Windows
with pinned actions, read-only permissions, a 25-minute timeout and raw JSON artifacts. Ordinary PR
tests run a four-pair correctness version without speed gates. Timings are observations, not promises
or grounds for changing the existing correctness/coverage thresholds.

### Recorded results

[Run 45446554405](https://github.com/dragonsec-ai/ArchUnitRuby/actions/runs/45446554405)
passed all five jobs. [Raw samples and medians](rule-views-ci.json) preserve all 48 paired samples,
exact revisions, Ruby 4.0.10 platforms, controls and ordered graph/evidence digests. Candidate
`7d73b3e` contains the runtime/harness change; later evidence/documentation commits do not change it.
Three-trial medians at 10,000 sources (seconds; allocations are summed over the warm suite):

| Host / suite | Cold graph + suite, old → new | Warm suite, old → new | Warm allocations, old → new |
|---|---:|---:|---:|
| Linux / one | 1.983 → 2.010 | 0.0767 → 0.0255 | 255,209 → 70,193 |
| Linux / 20 identical | 3.637 → 2.552 | 1.765 → 0.530 | 5,104,180 → 1,403,860 |
| Linux / 20 varied | 3.669 → 2.995 | 1.815 → 0.939 | 5,541,790 → 3,236,581 |
| Windows / one | 5.183 → 5.136 | 0.0867 → 0.0317 | 255,235 → 70,219 |
| Windows / 20 identical | 7.041 → 5.790 | 1.915 → 0.643 | 5,104,700 → 1,404,380 |
| Windows / 20 varied | 7.205 → 6.124 | 1.889 → 1.084 | 5,542,310 → 3,237,101 |

Warm varied suites improve ~48% on Linux / ~43% on Windows, with ~42% fewer allocations; twenty
identical checks improve ~70% / ~66%, with ~72% fewer allocations. Cold varied suites improve
~18% / ~15%. These are three shared-runner trials, not universal promises or competitor rankings.
Cold single-rule timing is ~1.3% higher on Linux and ~0.9% lower on Windows; its allocations are
essentially unchanged. Raw graph-only cold timings also remain similar, with only five extra
allocations in the Linux second cold stage and one extra in Windows.

The cost is retained memory: indexed suites grow post-GC Ruby heap by ~9.83 MiB versus ~6.66 MiB
before (~3.17 MiB extra). Graph-only retained growth differs by only a few hundred bytes. Peak RSS
is not uniformly lower: Linux identical-suite medians rise 139,448 → 154,672 KiB, while varied-suite
medians are 150,124 → 148,852 KiB. Even graph-only RSS varies 118,360 → 128,600 KiB despite nearly
identical retained Ruby heap; do not attribute every high-water change to the indexes. Windows RSS
remains unavailable/null. There is no memory-reduction claim.

## Explicit Rails association opt-in cost (#102)

Run `bundle exec ruby benchmark/study/rails_association_cost.rb pkg/association-cost.json` from the
library root. The study reuses the synthetic fixture generator and measurement helpers, replacing
the API files with models containing explicit `class_name:` strings. It alternates five pairs
of imports-only checks with the feature disabled/enabled across the same 2,000 files. It verifies
zero cross-file edges off and exactly 1,000 expected, evidenced association edges on, and checks
snapshot reuse in both modes. No target source, dependencies, or Rails boot are executed.

[Raw Windows samples](rails-association-windows.json), Ruby 4.0.6, five-trial medians:

| Opt-in | Cold graph | Cold allocated objects | Warm graph lookup |
| --- | ---: | ---: | ---: |
| Off | 1.614 s | 629,466 | 3.42 ms |
| On | 1.860 s | 926,503 | 2.64 ms |

In this fixture the opt-in adds about 0.25 s cold and 0.50 MiB of post-GC Ruby heap growth; the
two graphs have different dependency coverage. Warm samples are small lookup timings, not evidence
that enabling the option is faster. These local samples are not performance guarantees, and
there is no machine-speed gate. Windows peak RSS is unavailable.

## Shared-policy study

`run.rb` generates Rails-like and four-engine layouts with 200 Ruby files by default. Density
1 and 3, each with allowed/forbidden policies, give eight cases. Unique API/database classes,
explicit imports and root-qualified references provide known expected counts. Every measurement
validates its result; a source edit adds one deterministic edge and forbidden diagnostic.
Unexpected results abort the study, rather than recording an apparently fast incorrect run.
Fixtures raise if executed; their source, Gemfile, tests or dependencies are never run/installed.

Five alternating trials per tool retain raw samples and medians:

- `cold`: libraries/definitions preloaded, graph rebuilt plus check. This is not fresh-process
  startup or cold disk; OS file caches are not flushed.
- `warm`: same in-memory graph. Our public check performs discovery/cache lookup; ArchSpec uses
  its public evaluator on the returned graph. Useful workflows, not identical internal operations.
- `after_change`: rewrite one source, explicitly rebuild, check, restore before the next tool.
  Allowed policies remain zero; forbidden policies gain one diagnostic. Stale results are rejected.
- `startup`: fresh Ruby processes loading only their chosen analyzer. `wall_seconds` includes
  launch/load/analysis/check; child `seconds` isolates post-load analysis/check. Order alternates.
- Memory: ObjectSpace Ruby-heap bytes/growth exclude native memory. Fresh-child Linux `VmHWM`
  is peak process RSS; Windows unavailable values are null, not zero. Parent heaps include both
  preloaded libraries, GC and small retained result objects, not independent process peaks.

The analyzers do different semantic work. Counts validate only shared fixture policies, not equal
Ruby coverage. Engine shapes are generated, not full monorepo/Rails applications. Do not derive
a universal winner or optimize to a leaderboard. Shared-runner times are observations, not hard
timing gates; no graph baseline is auto-updated. Existing correctness canaries stay separate.

## Opt-in class declaration selection

From the root, run `bundle exec ruby benchmark/study/declaration_selection.rb`. The fixture
contains 500 single-class files in an explicit superclass chain. Every sample checks that it
selects the 499 descendants of the root. On Windows / Ruby 4.0.6, five trials gave median
end-to-end selector times of **253 ms cold** and **15.9 ms warm**, with **104,109** and **15,548**
Ruby allocations respectively. The median post-GC heap increase after the cold check was
**273,792 bytes** (Ruby object storage, not RSS). The script separately reports the ordinary
gem require and first opt-in scope setup, and verifies the default require did not load
declaration extraction. These are fixture measurements, not timing ceilings.

## Real production source

`real_project.rb` checks pinned Discourse `2de9c9be4f89e392fe500dd27f928d6b1184bf09`, with three
cold/warm pairs per mode. It verifies the revision and pristine Git status, requires the reviewed
2,510-source view, asserts warm graph identity and zero repeated cold counters, and checks status
unchanged afterward. Source/graph/uncertainty facts accompany timing/memory. Source-count changes
fail instead of silently blessing another corpus.

Sparse patterns in the workflow include production `lib/app/config/src` and root Ruby/markers,
excluding test/spec/fixture contents. This is not full Discourse, an upstream architecture/security
verdict, or a shared semantic-policy comparison against ArchSpec. Its RSS is explicitly a
process-lifetime high-water mark, not per-mode allocation. No target source, tests, configuration,
Gemfile/gemspec or Rails boot is executed. Evidence outputs go to our own `pkg`.

## Linux CI and reproduction

`Representative performance study` is manually dispatchable and runs on relevant study PRs,
not a timer or every code change. It uses immutable action/source pins, read-only permissions,
no persisted checkout credentials, a separate frozen/checksum-locked bundle, 15-minute timeout,
concurrency cancellation and 14-day artifacts. It also repeats the 14 semantic probes on Linux.

From this trusted research directory, never from the target application:

```sh
bundle install
STUDY_PAIRS=100 STUDY_TRIALS=5 bundle exec ruby run.rb --archspec ../../pkg/study.json
bundle exec ruby ../semantic/probes.rb --archspec ../../pkg/semantic.json
bundle exec ruby real_project.rb /path/to/pinned-sparse-discourse ../../pkg/discourse.json
```

The root RSpec study test is candidate-only, with four pairs and one trial, no native comparator
or startup workers. The comparator is optional research tooling. Failed installation/controls are
study failures, never measured zeroes or evidence of superiority.

## Bounded file cycle reporting

From the repository root, run `bundle exec ruby benchmark/study/cycle_witnesses.rb`. Each fixture
contains every forward edge and one closing edge, so there are exactly `2**(vertices - 2)` simple
cycles. The script checks this count and the deterministic witness path. It compares the two
projection/reporting modes only, excluding discovery, parsing, and serialization. Three alternating
runs per mode; medians below from Ruby 4.0.6 on Windows. These are observations, not CI timing gates.

| Vertices | Exhaustive → witness paths | Median time (ms) | Allocated Ruby objects |
| ---: | ---: | ---: | ---: |
| 10 | 256 → 1 | 2.47 → 0.40 | 7,944 → 927 |
| 14 | 4,096 → 1 | 46.96 → 0.61 | 128,866 → 1,745 |
| 18 | 65,536 → 1 | 1,710.71 → 0.86 | 2,296,780 → 2,835 |

In the last case the exhaustive paths contain 655,360 edge entries versus three in the witness.
Witness mode classifies all components; it bounds report size to one path per cyclic component,
not a fixed number of paths across the project.
