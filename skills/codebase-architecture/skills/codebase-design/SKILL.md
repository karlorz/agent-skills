---
name: codebase-design
description: Use when designing or improving a module interface, finding deepening opportunities, deciding seam placement, making code more testable or AI-navigable, or when another architecture skill needs deep-module vocabulary.
metadata:
  upstream: https://github.com/mattpocock/skills/tree/main/skills/engineering/codebase-design
  upstream_license: MIT
---

# Codebase Design

Design **deep modules**: a lot of behaviour behind a small interface, placed at a clean seam, testable through that interface. Shared vocabulary for the whole `codebase-architecture` chain (analyze → improve → to-spec).

## Glossary

Use these terms exactly — don't substitute "component," "service," "API," or "boundary." Consistent language is the whole point.

**Module** — anything with an interface and an implementation. Scale-agnostic: function, class, package, or tier-spanning slice. _Avoid_: unit, component, service.

**Interface** — everything a caller must know to use the module correctly: type signature, invariants, ordering constraints, error modes, required configuration, performance characteristics. _Avoid_: API, signature (too narrow).

**Implementation** — what's inside a module. Distinct from **Adapter**: small adapter + large implementation (Postgres repo) or large adapter + small implementation (in-memory fake). Reach for "adapter" when the seam is the topic; "implementation" otherwise.

**Depth** — leverage at the interface: behaviour a caller or test can exercise per unit of interface they learn. **Deep** = large behaviour behind small interface; **shallow** = interface nearly as complex as implementation.

**Seam** _(Michael Feathers)_ — place where you can alter behaviour without editing there; the location of the module's interface. Where to put the seam is its own design decision. _Avoid_: boundary (DDD overload).

**Adapter** — concrete thing that satisfies an interface at a seam. Role, not substance.

**Leverage** — capability per unit of interface callers learn. One implementation pays back across N call sites and M tests.

**Locality** — change, bugs, knowledge, and verification concentrate in one place. Fix once, fixed everywhere.

**C4 Component (exception):** only as the C4 *diagram level* name. Not a synonym for module in design prose or extract filenames.

## Deep vs shallow

**Deep** = small interface + lots of implementation. **Shallow** = large interface + thin pass-through.

When designing an interface, ask: fewer methods? simpler params? more complexity hidden inside?

## Principles

- **Depth is a property of the interface, not the implementation.** Internal seams may exist for tests; they are not the external interface.
- **The deletion test.** Delete the module: if complexity vanishes, it was pass-through; if it reappears across N callers, it earned its keep.
- **The interface is the test surface.** Callers and tests cross the same seam.
- **One adapter = hypothetical seam. Two adapters = real seam.** Don't invent ports for a single adapter.

## Designing for testability

Good interfaces make testing natural:

1. **Accept dependencies, don't create them.**

   ```typescript
   // Testable
   function processOrder(order, paymentGateway) {}

   // Hard to test
   function processOrder(order) {
     const gateway = new StripeGateway();
   }
   ```

2. **Return results, don't bury side effects when pure is enough.**

   ```typescript
   // Testable
   function calculateDiscount(cart): Discount {}

   // Hard to test
   function applyDiscount(cart): void {
     cart.total -= discount;
   }
   ```

3. **Small surface area** — fewer methods and params.

## Relationships

- Module → exactly one Interface.
- Depth measured against that Interface.
- Seam = where the Interface lives.
- Adapter sits at a Seam.
- Depth → Leverage (callers) + Locality (maintainers).

## Rejected framings

- Depth as implementation-LOC / interface-LOC (Ousterhout-ratio misuse) — rewards padding. Prefer depth-as-leverage.
- "Interface" as only a language `interface` keyword.
- "Boundary" for this vocabulary — say seam or interface.

## Going deeper

- Dependency categories and replace-don't-layer testing → [deepening.md](../../references/deepening.md)
- Parallel interface exploration → [design-it-twice.md](../../references/design-it-twice.md)
- Full analyze/extract playbook → skill `codebase-architecture-analyze`
- Chain router → skill `codebase-architecture`
