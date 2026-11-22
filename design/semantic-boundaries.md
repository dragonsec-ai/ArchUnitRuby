# Semantic rule/selector evaluation — #91

Status: evaluated on the unreleased 1.1 candidate after #93/#94, 2026-11-22.
This is a technical decision record, not a shipped method/protocol API or a claim of competitor parity.

## Decision

Retain Prism and the existing import-only/default versus opt-in constant-file graph contract.
Do not add RubyDEX as a mandatory production dependency or advertise regex/AST receiver spelling
as semantic call resolution. The graph's file identities, evidence, uncertainty counters, cache
settings, no-target-execution guarantee and baseline contract remain unchanged.

The method/protocol and component-selector gaps remain meaningful. A future first semantic delivery
should introduce explicit declaration facts (constant ownership, declared methods/signatures and
known ancestry) and bounded declaration-based selectors before claiming arbitrary receiver/method
dispatch. A syntactic method-name restriction can also be useful if honestly named/documented as
such. Full inherited/effective protocols, aliases, reopened classes and runtime receiver inference
need a separately designed semantic model and confidence/unknown contract, not another file glob.
No such public API is silently added by this evaluation.

Maintainer testing/request (#66 and this follow-up) establishes interest. We have no measured user
adoption/request counts and do not invent demand data. Baselines and composed presets are lower-risk
adoption improvements; they do not remove the semantic gap.

## Reproducible evidence

`benchmark/semantic/cases.json` defines 14 small fixtures. The default harness runs against our
library without optional dependencies; `--archspec` runs the exact published comparator. Fixtures
raise if their source or Gemfile is executed. No target configuration or dependency installation
is used. `syntax_facts.rb` is a probe-only Prism visitor, **not** a new production resolver.

The checked-in `benchmark/semantic/evidence-windows.json` records Ruby 4.0.6, Prism 1.9.0 and current
unreleased ArchUnit 1.1, with ArchSpec 1.1.0 / RubyDEX 0.4.0. Official immutable source pins:

- [ArchSpec 1.1.0](https://github.com/crmne/archspec/tree/1d321d3585a86672e65b2488681393f9d52656a9)
  (`v1.1.0`), including its `protocol_rules.rb`, `component_spec.rb` and `rubydex_index.rb`.
- [RubyDEX 0.4.0](https://github.com/Shopify/rubydex/tree/e0ed5e7d722a0c37c0534878a722d7b67f4b63ac)
  (`v0.4.0`). This is not a statement about newer releases or master.

Verified cached package SHA256s match the earlier lock: ArchSpec
`861d4869c81617139ea9e42e6de1456ba00d0538f3994476073829de223a754d`;
RubyDEX Windows x64 UCRT
`7becaee5f1d89bdbea031daecbd46137f03e30e9e218f19cc03a538865830ba5`.

| Bounded control | Our result / boundary | Pinned comparator observation |
| --- | --- | --- |
| Explicit `Db::Store.delete_all` vs `Db::Store.read` | A no-DB-file rule rejects both; it cannot express a method-name policy | Unqualified `cannot_call :delete_all` rejects the former only |
| Same explicit call with receiver-qualified restriction | File edge remains visible, no method target API | `receiver: 'Db::Store'` emitted no diagnostic in this fixture |
| Method parameter receiver `store.delete_all` | Name is visible syntactically, runtime receiver is unknown | Receiver-qualified policy emitted no diagnostic |
| Unqualified inherited constant vs explicit-root control | Inherited form stays unresolved; explicit root produces the direct DB edge | Direct dependency policy catches the root control, not the unqualified form |
| Alias-member lookup | No direct DB edge is inferred; uncertainty remains | No direct DB diagnostic in this fixture |
| Correct/wrong explicit method signature | Metric methods expose name/field facts, not arity/keyword protocols | Protocol accepts the correct signature and flags the wrong one |
| `define_method` matching the runtime protocol | Probe sees syntax but does not execute/infer a runtime API | Protocol still flags this fixture; do not infer complete metaprogramming support |
| Namespace/constant/descendant component selection | No first-class file/component selector based on those semantics | Each selects the fixture class for a missing-protocol diagnostic |
| Reopened constant definitions | Kept ambiguous rather than selecting a definition | Direct dependency policy reports a DB dependency in this fixture |

These observations compare particular policies, not a universal correctness oracle. Especially the
first rows do **not** compare equivalent policies: an architectural file dependency is broader
than a method restriction. A zero diagnostic is not proof that a runtime behavior is safe. No
global semantic-coverage percentage or performance winner is derived.

## Backend tradeoffs

Prism already gives explicit class/module/def/call/parameter syntax without executing applications.
It does not by itself resolve dynamic dispatch, included/inherited method lookup, alias expansion,
load order or reflection. Our current metric `MethodInfo` is only `name` / `accessed_fields`; its
class selection is a metric selector, not a semantic component selector or protocol check.

ArchSpec's published adapter combines a RubyDEX resolved index with a Prism syntax overlay;
its method model includes signatures, effective ancestry and alias information. Reusing a semantic
index could avoid reimplementing all Ruby lookup rules, but does not eliminate unknowns demonstrated
above. The pinned RubyDEX package is native/Rust and declares Ruby `>= 3.2, < 4.1.dev`, narrower
than simply depending on our current Ruby 3.3+ parser toolchain. A mandatory switch would couple
installation/platform availability, Ruby-version upgrades, native-parser failure modes, indexing
time and memory to every user, including those only using imports/metrics. No unmeasured resource
or platform support claim is made; #92 evaluates representative timing/memory separately.

If an optional semantic adapter is later chosen, isolate its dependency/version/platform contract,
label its facts/confidence and cache identity explicitly, preserve old-mode graph fingerprints,
and test it on Linux and Windows. Native indexing must not gain authority to boot applications;
resource limits and process isolation should be evaluated for hostile/large inputs. This is a
design consideration, not a claim of a discovered native vulnerability.

## Acceptance boundaries for any subsequent semantic delivery

1. Specify a sentence-like API and structured fact/violation model; choose declaration-only versus
   effective/runtime behavior explicitly. No method/protocol predicates inferred from formatted text.
2. Keep imports and imports_and_constants behavior unchanged when semantic features are off. New
   options must participate in cache/scope identity and accepted-debt fingerprints.
3. Report unsupported/ambiguous facts as unknown; distinguish an absent declaration from a proven
   absent runtime method. Decide strictness per documented rule, not a default false clean pass.
4. Cover singleton/instance methods, positional/optional/rest/keyword/block/forward signatures,
   aliases, mixins/inheritance, reopened/conditional declarations, dynamic `define_method`,
   `method_missing`, reflective mutation, descendant cycles and multiple source roots.
5. Verify installed-package/platform support, no target boot, startup/index/reuse/memory costs and
   passing **and** failing controls before claiming shipped semantic capability.

Run current-only probes from the library's bundle:

```sh
bundle exec ruby benchmark/semantic/probes.rb output.json
```

For the exact comparator, use a separate trusted benchmark environment containing ArchSpec 1.1.0,
RubyDEX 0.4.0 and Prism 1.9.0, with this checkout on the load path; then add `--archspec`. Never
install or evaluate the target fixture's Gemfile to run these checks.
