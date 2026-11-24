# Extraction performance benchmark

For repeated Linux shared-policy comparisons, fresh-process startup/memory, source changes and
pinned Rails production-source evidence, see the [representative study](study/README.md).

For pinned production-library compatibility checks, public passing/failing rule witnesses, and
real-world timing artifacts, see the [static canary guide](canary/README.md).

## Source-discovery follow-up (#100)

The same extraction benchmark now reports `cold.memory_growth.allocated_objects` and a
`graph_sha256` covering ordered edges and their structured source evidence. Allocation counts
are work performed during cold analysis, not retained-memory measurements. `--excluded-files N`
adds a deliberately malformed `vendor/` tree; source counts must still be requested files + 1
(the generator's shared source), and no excluded file may be parsed.

`retained` reports Ruby-heap growth after an explicit GC following both timed operations; this
extra GC is outside the cold/warm timers. Peak RSS remains a whole-process high-water mark,
including fixture generation, and pre-GC cold heap growth can vary with collection timing.

For example:

```sh
bundle exec ruby benchmark/extraction.rb --files 10000 --gems 2 --imports-per-file 0 --constants
bundle exec ruby benchmark/extraction.rb --files 1000 --excluded-files 3000 --constants
```

Manually dispatch `performance-study.yml` on the candidate ref to run three alternating fresh
baseline/candidate pairs for sparse 5k/10k, import-heavy and excluded-tree cases on Linux and
Windows. The discovery job uses the normal production bundle, v1.1.0 library baseline and the
identical updated `benchmark/extraction.rb` harness in both checkouts. It checks full graph/evidence
digests, actual source inventories and cached graph identity, and retains every JSON result.
No competitor backend is involved in these paired measurements. Normal PRs do not run the heavy
discovery matrix; existing generous extraction-smoke ceilings stay unchanged.

Local Windows x64 / Ruby 4.0.6 medians (2026-11-24; three pairs per case):

| Case | Before cold | After cold | Before discovery | After discovery | Before allocations | After allocations |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Sparse 5,000 (+1 shared) | 6.891 s | 4.263 s | 3.494 s | 1.172 s | 5,209,871 | 2,627,199 |
| Sparse 10,000 (+1 shared) | 13.830 s | 7.839 s | 7.253 s | 1.948 s | 10,414,873 | 5,252,199 |
| 1,000 / three imports | 2.221 s | 1.490 s | 0.425 s | 0.126 s | 1,466,479 | 947,810 |
| 1,000 / 3,000 excluded | 1.420 s | 0.831 s | 0.774 s | 0.200 s | 1,046,126 | 527,204 |

[Every local sample](study/discovery-windows.json) is retained. All pairs have identical graph
and evidence digests, including source ordering. Timings depend on filesystem cache, host and
load; fixtures are freshly generated outside profiled analysis, not a cold-disk experiment.
Windows peak RSS is unavailable, not zero. Heap snapshots are not post-GC retained memory.
Do not turn these local medians into portable timing gates or a universal speed claim.

Hosted Linux/Windows verification (Ruby 4.0.10, three pairs per case) is retained in
[discovery-ci.json](study/discovery-ci.json), including separate post-GC measurements:

| 10,000-file case | Before cold | After cold | Before discovery | After discovery | Before allocations | After allocations |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Linux | 1.750 s | 1.078 s | 0.716 s | 0.030 s | 8,453,786 | 4,891,912 |
| Windows | 5.922 s | 3.688 s | 3.228 s | 0.962 s | 9,064,085 | 5,102,011 |

Post-GC Ruby-heap growth for this case is essentially unchanged: Linux 8,417,117 to 8,414,189
bytes; Windows 8,414,189 to 8,414,077 bytes. This supports lower transient work, not a new claim
that every memory measure improves. Linux whole-process peak RSS drops from 97,212 to 83,144 KiB
at 10k, but rises from 58,760 to 64,408 KiB at 5k despite similar retained heap. Pre-GC growth is
similarly mixed; Windows RSS is unavailable. Warm lookup medians remain below 1.3 ms in these
samples, with one small Linux excluded-tree case increasing from 0.117 to 0.902 ms despite
confirmed graph reuse. Keep these tradeoffs visible rather than optimizing to a single number.

The benchmark generates a deterministic multi-gem Ruby repository, then measures one cold graph
build and one same-process cached lookup. Target application code and generated gemspecs are never
executed.

Run the default 1,000-file corpus:

```bash
bundle exec ruby benchmark/extraction.rb
```

The corpus includes a declared class and a cross-file constant use per generated source. Compare
import-only extraction against expanded indexing on identical source with:

```bash
bundle exec ruby benchmark/extraction.rb --constants
```

Both runs report cold/warm timing and memory. Expanded runs also report `constant_indexing`,
unresolved/ambiguous-reference counters, and the same-process graph cache reuse result.

Use a smaller CI smoke corpus with deliberately generous, non-flaky limits:

```bash
bundle exec ruby benchmark/extraction.rb \
  --files 200 --gems 4 --imports-per-file 3 \
  --max-cold-seconds 30 --max-warm-seconds 2
```

The JSON output reports wall-clock time for project discovery, source enumeration, load-path
discovery, file reads, Prism parsing, import extraction, target resolution, edge merging, and the
complete run. Internal-target indexing and edge classification are reported separately so hidden
filesystem work cannot disappear between the larger stages. Counters expose source/import/edge
totals and feature-resolution cache hits. Memory
output includes Ruby heap growth on every platform and process peak RSS where `/proc` exposes it.

`--output path.json` also saves the complete result. Hosted CI only uses the smoke corpus and broad
regression ceilings; performance decisions should use several local runs of the default corpus or a
non-blocking real-world canary.

## Constant-analysis measurement

On 2026-10-15, Ruby 4.0.6 on Windows x64, three fresh-process runs per mode on the updated
1,000-file / 10-gem corpus produced these medians:

| Measurement | Imports | Imports and constants |
| --- | ---: | ---: |
| Cold graph build | 1.706 s | 1.533 s |
| Warm graph lookup | 1.93 ms | 1.95 ms |
| Constant indexing/resolution | — | 32.0 ms |
| Merged graph edges | 4,001 | 4,001 |

All runs reused the identical cached graph on their warm lookup. The corpus references the same
next file by import and constant, so expanded mode merges 5,001 raw edges into 4,001 edges while
retaining both evidence forms. Every source is parsed once per cold graph. Cold samples ranged from
1.45 to 1.86 seconds across modes. Filesystem and run-order noise prevent deriving a meaningful
overhead percentage from this small sample; the separately measured indexing stage is more useful
here than the difference between total medians.

Heap-growth samples ranged from 3.07–5.49 MB for imports and 6.13–9.90 MB for expanded analysis;
these pre-GC snapshots are sensitive to collection timing and do not establish retained or peak
memory. Windows does not expose the Linux peak-RSS counter. ASTs and indexing structures are
temporary; the cached graph retains immutable edges and evidence only.

## Reference baseline and target

### Pre-v1 source-walk audit (2026-10-20)

Three alternating fresh-process pairs compared commit `d5f3e36` with the audit's status-reusing,
symlink-skipping walker on the same 1,000-file / 10-gem / 3-import corpus. Ruby 4.0.6, Windows x64:

| Pair | Before cold | After cold | Before enumeration | After enumeration |
| --- | ---: | ---: | ---: | ---: |
| 1 | 3.772 s | 3.472 s | 0.938 s | 0.673 s |
| 2 | 7.445 s | 6.373 s | 2.126 s | 1.002 s |
| 3 | 7.810 s | 7.754 s | 2.155 s | 1.975 s |

Every pair retained 4,001 graph edges and reused its cached graph. Warm lookups ranged from
3.6–11.0 ms. Enumeration improved in each pair, but the large run-to-run variation makes an exact
speedup claim inappropriate. This is evidence against an obvious regression, not a portable speed
guarantee. That audit used one explicit `lstat` result for its own type/symlink decisions;
Ruby's `Find` traversal still performed its own metadata checks at that revision.

### Original extraction baseline

On 2026-08-14, Ruby 4.0.6 on the Windows development machine produced the following default-corpus
results. The optimized values are the median of three fresh processes:

| Measurement | Before indexed/cached canonicalization | Current |
| --- | ---: | ---: |
| Cold extraction | 25.841 s | 6.388 s |
| Warm graph lookup | 9.95 ms | 6.17 ms |
| Ruby heap growth | 4.94 MB | 3.08 MB |
| Graph edges | 4,001 | 4,001 |

The cold improvement is approximately 75.3%, with identical graph semantics. The local regression
target for this corpus is therefore a three-run median below 15 seconds cold and 50 milliseconds
warm on comparable hardware. These are reference targets, not portable promises; CI deliberately
uses the much broader 200-file ceilings shown above.

As a real-world diagnostic, Rails at commit `ef8d960` contained 3,444 analyzed Ruby files and 6,560
literal imports. On the same Windows development checkout, profiled extraction took 33.6 seconds
and produced 9,913 graph edges. Source enumeration (11.7 seconds), target resolution (7.1 seconds),
and Prism parsing (6.7 seconds) dominated; the resolution cache served 4,872 repeated lookups. A
first pass against a completely cold Windows filesystem was much slower, so this is diagnostic data,
not a portable regression threshold. Native or safely pruned source enumeration is the clearest
next performance investigation.
