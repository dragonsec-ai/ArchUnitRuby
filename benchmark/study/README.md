# Representative performance study (#92)

This research bundle is separate from the production gem. Comparison pins: ArchSpec 1.1.0,
RubyDEX 0.4.0, Prism 1.9.0, JSON 2.21.2 and CSV 3.3.7. Its lock contains Linux/Windows native
package checksums without changing root dependencies. The candidate is the checkout revision,
not necessarily the published gem.

For the separate source-discovery optimization follow-up (#100), see the
[root extraction benchmark](../README.md#source-discovery-follow-up-100) and its paired-sample
JSON. The manual performance workflow also runs that unchanged generator/harness against the
v1.1.0 and candidate libraries on Linux/Windows, using only the normal production bundle.

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
