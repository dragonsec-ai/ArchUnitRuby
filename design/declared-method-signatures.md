# Declared method signatures (#105)

The first rule reads “project classes in Commands should declare method call with this signature”:

~~~ruby
signature = ArchUnit::MethodSignature.new(name: :call, positional: 1, keywords: %i[actor request_id])
rule = ArchUnit.project_classes.in_namespace('Commands').should.declare_method(signature)
~~~

This is the **declared-here** milestone: an ordinary `def` on each selected class must accept the
given call shape. Inheritance, mixins, aliases, `define_method`, and `method_missing` do not count as
direct declarations. The rule does not claim runtime visibility, method behavior, or effective API
coverage. A separate effective-lookup feature needs precedence, alias, reflection, and uncertainty
decisions before it can share any public meaning of “implements”. Negative mood is not exposed.

Positional options describe the number passed (optional/rest parameters may accept it).
Keywords describe the exact named arguments passed: extra required keywords invalidate the
contract, `**kwargs` accepts extras, and `**nil` accepts no nonempty keyword set. Implicit Ruby
conversion of keywords to a positional Hash is not a declared keyword interface.
`scope: :singleton` matches methods written as `def self.name` or `class << self`.
`block: :declared` requires `&block`, anonymous `&`, or forwarding `...`; this does not prove
that code invokes a block. Without that option, no explicit block-capture parameter is required.

Conditional declarations, ambiguous ownership and mixed compatible/incompatible reopens are
unknown. If all direct candidates accept the shape, a compatible shape is known without choosing
load order. If none accepts it, the signature is incompatible. Missing written declarations,
incompatible shapes, and unknowns are distinct findings; all fail the check. A known empty
selection follows the standard empty-test guard. Unknowns cannot be suppressed with
`allow_empty_tests` or written to or accepted by an accepted-debt baseline.

Confirmed failures use a structured identity covering the normalized selector, policy version,
expected shape, class name, and observed shape/file evidence without line numbers. The observed
source snapshot has its own `source_declarations` context and the same exclusions/refresh rules as
class selection. The dependency graph does not change.
