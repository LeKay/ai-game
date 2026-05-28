# Story 004: Category System and Filtering

> **Epic**: Resource System
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Logic
> **Manifest Version**: 2026-05-14

## Context

**GDD**: `design/gdd/resource-system.md`
**Requirement**: `TR-res-005`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0002: Resource Data Registry Format and Loading
**ADR Decision Summary**: Two resource categories are modelled as a GDScript `enum ResourceCategory { CONSUMABLE, PRODUCTION_GOOD }`. `get_all_by_category(cat)` returns a fresh Array of definitions matching the given category — O(n) filter, acceptable for startup-only queries. Callers must not mutate the returned Array.

**Engine**: Godot 4.6 | **Risk**: HIGH (engine version beyond LLM training data)
**Engine Notes**: GDScript `enum` at class scope is accessible from outside via `ResourceRegistry.ResourceCategory.CONSUMABLE`. Typed `Array[_ResourceDefinition]` return is preferred for downstream type safety. Verify typed Array support with inner class type in Godot 4.6 — if problematic, return untyped `Array`.

**Control Manifest Rules (this layer)**:
- Required: Category enum exposed at class scope for consumers; `get_all_by_category()` returns fresh Array (not the internal cache reference)
- Forbidden: Callers filtering `_definitions` directly — must use `get_all_by_category()`
- Guardrail: `get_all_by_category()` is O(n) — document as startup-only; callers that need repeated category queries should cache the result themselves

---

## Acceptance Criteria

*From GDD `design/gdd/resource-system.md`:*

- [ ] **AC-1**: Given the registry is loaded with mixed categories, when `get_all_by_category(ResourceCategory.CONSUMABLE)` is called, then it returns only resources with category `consumable` and no `production_good` entries
- [ ] **AC-2**: Given the registry is loaded with mixed categories, when `get_all_by_category(ResourceCategory.PRODUCTION_GOOD)` is called, then it returns only resources with category `production_good` and no `consumable` entries
- [ ] **AC-3**: Given all resources have category `production_good`, when `get_all_by_category(ResourceCategory.CONSUMABLE)` is called, then it returns an empty Array (not null, not a crash)
- [ ] **AC-4**: Given resources with `base_value > 0` and `base_value == 0`, when the Trading System calls `get_all_by_category()` and filters for non-zero base_value, then only tradeable resources are returned (this is a caller-side filter; `get_all_by_category()` returns all in category, caller filters by base_value)
- [ ] **AC-5**: Given `get_all_by_category()` returns an Array, when the caller mutates the Array (append, erase), then the internal `_definitions` cache is not affected

---

## Implementation Notes

*Derived from ADR-0002 Implementation Guidelines:*

Add the enum and `get_all_by_category()` to ResourceRegistry:

```gdscript
enum ResourceCategory { CONSUMABLE, PRODUCTION_GOOD }

func get_all_by_category(category: ResourceCategory) -> Array:
	var result: Array = []
	for def in _definitions.values():
		if def.category == category:
			result.append(def)
	return result  # Fresh Array — callers cannot affect internal cache by mutating this
```

The `ResourceCategory` enum must be defined at class scope (not inside a function) so consumers can reference it as `ResourceRegistry.ResourceCategory.CONSUMABLE`.

**Tradeable resource query** (GDD AC-9 / AC-4 here): `get_all_by_category()` does NOT filter by `base_value`. The Trading System is responsible for filtering the returned Array by `base_value > 0`. This keeps the API single-purpose — category is the only axis ResourceRegistry filters on.

If a future performance concern arises (> 500 resources), maintain a secondary `_by_category: Dictionary` index populated during `_cache_resource()`. For Vertical Slice scale (~20-30 resources) this is unnecessary.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 003: `get_definition()` and `is_valid_id()` — the lookup API this story builds on
- Story 005: Deprecated resources — `get_all_by_category()` returns deprecated resources too; callers filter by `def.deprecated` if needed

---

## QA Test Cases

*QL-STORY-READY skipped — Lean mode. Test cases written from GDD acceptance criteria.*

- **AC-1**: CONSUMABLE filter returns only consumables
  - Given: Registry has berry (consumable), wood (production_good), bread (consumable)
  - When: `get_all_by_category(ResourceRegistry.ResourceCategory.CONSUMABLE)` called
  - Then: returns Array of length 2 containing berry and bread; wood not present

- **AC-2**: PRODUCTION_GOOD filter returns only production goods
  - Given: Same registry as AC-1
  - When: `get_all_by_category(ResourceRegistry.ResourceCategory.PRODUCTION_GOOD)` called
  - Then: returns Array of length 2 containing wood and stone; berry and bread not present

- **AC-3**: Empty category returns empty Array (not null)
  - Given: Registry has only production_good resources
  - When: `get_all_by_category(ResourceRegistry.ResourceCategory.CONSUMABLE)` called
  - Then: returns Array of length 0; result is not null; no crash

- **AC-4**: Caller-side tradeable filtering
  - Given: Registry has wood (base_value:2), stone (base_value:0), bread (base_value:5)
  - When: caller gets all PRODUCTION_GOOD then filters by `def.base_value > 0`
  - Then: caller result contains only wood; stone excluded

- **AC-5**: Returned Array mutation does not affect cache
  - Given: Registry loaded with 3 resources
  - When: Caller appends a dummy entry to the returned Array
  - Then: `_definitions.size()` still equals 3; subsequent `get_all_by_category()` call still returns 3 entries

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/resource/category_filter_test.gd` — must exist and pass

**Status**: [x] PASSED — 7/7 tests (2026-05-25)

---

## Dependencies

- Depends on: Story 003 must be DONE (cache populated; category parsed and stored in definitions)
- Unlocks: Story 005 (deprecated filtering via the same API), downstream epics (Hunger System uses CONSUMABLE filter; Trading uses PRODUCTION_GOOD + base_value)

---

## Completion Notes
**Completed**: 2026-05-25
**Criteria**: 5/5 passing
**Deviations**: Untyped `Array` return (pre-approved, Godot 4.6 inner class typed array edge case). Cross-cutting bug fixed: `stack_limit` validator now accepts `float` for Godot 4.6 JSON parser compatibility (was `is int` only).
**Test Evidence**: Logic — `tests/unit/resource/category_filter_test.gd` — 7/7 PASSED
**Code Review**: APPROVED (lean mode — LP-CODE-REVIEW skipped)
