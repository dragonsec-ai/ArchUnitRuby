# Declaration facts and selectors (#103)

This is an amendment to [the semantic-boundaries decision](semantic-boundaries.md). It does not
change file graph identity, import/constant modes, existing rule fingerprints, or the parser
dependency. No app, load path setup, reflection, or target configuration is evaluated.

## First slice: facts, not runtime classes

Read Prism declarations once from an already parsed source. Keep each version of a namespace
declaration, even when names coincide. The stable evidence key is project-relative file, line
and byte column, not traversal order or the last file to reopen a constant. Record class vs
module, written constant path, bounded qualified name, enclosing lexical declarations, and
`direct`, `conditional` or `dynamic` context. Context applies to the enclosing syntax, not to
whether Ruby would have loaded a file. A method records its enclosing declaration site, not an
invented merged runtime owner. When the method receiver is dynamic, the enclosing site stays
known independently from the method's unknown ownership.

- Simple declarations use lexical nesting. Root-qualified paths stay rooted. A qualified path
  written at top level keeps its explicit path. A relative qualified path inside another
  declaration is **unknown** until the owner can be established; never assume the root.
- Reopens with one name do not replace earlier facts. A class/module collision is not resolved
  by input order. Conditional facts and facts under a receiver whose identity is unknown
  must remain inspectable; they are not proof of a single runtime class.
- `def`, `def self.name` and `class << self` record literal method positions, with parameters
  classified by written shape. Explicit receivers other than self have unknown method scope.
  Default expressions are not evaluated. Superclass and literal mixin arguments are facts
  about written expressions, not resolved edges. Non-constant expressions are retained as
  unresolved source sites, not treated as absent.
- Mixin observations cover bare or explicit-`self` calls inside a named class/module's lexical
  scope, outside singleton-class bodies. They are not an inventory of every possible mixin.
- The opt-in project collector uses the existing project locator, exclusions and fail-closed
  parser. It parses each included file once per inventory request and retains facts, not ASTs.
  The ordinary `require 'archunit'` path does not load the collector at all.

## Proposed selector contract (next slice)

The sentence is “project classes in namespace Billing, with constant name Billing::Invoice,
should ...”. A classes scope is separate from the file scope and does not introduce class
nodes in the file graph. Following the siblings' scope grammar, propose
`project_classes(root).in_namespace('Billing').with_constant_name('Billing::Invoice')`.
The exact selector normalizes a leading `::`; the namespace selector includes descendants by
segment (`Billing::Invoice`, not `BillingTools::Invoice` or `Billing` itself). A source filter
would select contributing declaration sites, not authorize reading excluded reopens.

A bounded ancestry selector would report **matched**, **not matched in the declared graph**, or
**unknown**. External, dynamic, cyclic and conflicting ancestry cannot be returned as a
proved nonmatch. Transitive decisions must be iterative and derived from known declarations;
no implicit runtime/mixin/effective method claims. A later rule terminal must propagate unknowns
and keep the normal empty-selector failure. Inspection results themselves are not rule passes.

Keep the inventory opt-in, reuse the common source-discovery/parser policy, and cache by
canonical root and effective exclusions once a project consumer exists. Add a distinct analysis
scope identifier before any rule consumes these facts or accepts baseline debt. The fact
collector may accept an already parsed AST so later features need not reparse per selector.

The first slice covers internal extraction and provenance only. Public selectors, ancestry
resolution, warm project inventory, and rule/baseline integration are not shipped by it.
