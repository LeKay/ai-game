# Story 006: Example Resource Definitions (Wood, Stone, Berry)

> **Epic**: Resource System
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Config/Data
> **Manifest Version**: 2026-05-14

## Context

**GDD**: `design/gdd/resource-system.md`
**Requirement**: `TR-res-002` (Resource definition schema — required and optional attributes)
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0002: Resource Data Registry Format and Loading
**ADR Decision Summary**: Resource definitions live in `res://data/resources.json`. Designers add new resource types by editing this JSON file — no code changes required. Required fields: id, display_name, category, stack_limit, icon_path.

**Engine**: Godot 4.6 | **Risk**: LOW (data file only — no engine API calls)
**Engine Notes**: N/A — this story modifies only the JSON data file.

**Control Manifest Rules (this layer)**:
- Required: All entries must have id, display_name, category, stack_limit, icon_path
- Forbidden: Hardcoding resource IDs in code (use registry)
- Guardrail: IDs are permanent — never rename or delete (use deprecated flag instead)

---

## Acceptance Criteria

*From GDD `design/gdd/resource-system.md` and sprint definition:*

- [x] **AC-1**: `data/resources.json` contains a "wood" entry with category "production_good", stack_limit 99, all required fields present
- [x] **AC-2**: `data/resources.json` contains a "stone" entry with category "production_good", stack_limit 99, all required fields present
- [x] **AC-3**: `data/resources.json` contains a "berry" entry with category "consumable", stack_limit 50, all required fields present
- [x] **AC-4**: All three resources loadable via `ResourceRegistry.get_definition()` after `load_from_file()` succeeds (registry passes validation with these entries present)
- [x] **AC-5**: Berry is category "consumable" (supports Hunger System daily consumption); Wood and Stone are category "production_good" (support building cost deductions)

---

## Implementation Notes

*Config/Data story — no code changes required. Data was created as part of Story 001 implementation per ADR-0002 Migration Plan.*

`data/resources.json` contains the full initial resource set as of 2026-05-17:
- **wood** — production_good, raw_material, stack_limit 99, weight 2.5 kg, base_value 2, tags: burnable, construction_material
- **stone** — production_good, raw_material, stack_limit 99, weight 3.0 kg, base_value 1, tags: construction_material
- **fiber** — production_good, raw_material, stack_limit 99, weight 0.5 kg, base_value 1
- **berry** — consumable, food, stack_limit 50, weight 0.1 kg, base_value 1, tags: food
- **bread** — consumable, food, stack_limit 50, weight 0.3 kg, base_value 3, tags: food
- **plank** — production_good, intermediate, stack_limit 99, weight 1.5 kg, base_value 4, tags: construction_material
- **tool** — production_good, tool, stack_limit 10, weight 2.0 kg, base_value 30, max_charge 100.0, tags: tool

---

## Out of Scope

- Icon art assets — placeholder paths acceptable for Vertical Slice
- Design-time validation pre-commit script — separate tooling story
- New resources beyond the initial VS set

---

## Test Evidence

**Story Type**: Config/Data
**Required evidence**: `data/resources.json` verified to contain all required entries; schema validates via existing integration test suite (res-01 through res-05 tests cover load path)

**Status**: [x] Complete — data present and validated by existing test coverage

---

## Dependencies

- Depends on: Story 001 (ResourceRegistry loads the JSON file) — DONE
- Unlocks: Hunger System stories (Berry = 1 food unit), Building System stories (Wood/Stone build costs), Player Character manual action costs

---

## Completion Notes

**Completed**: 2026-05-28
**Criteria**: 5/5 ACs satisfied
**Deviations**: None
**Implementation Note**: Data was pre-created during Story 001 implementation per ADR-0002 Migration Plan. Story file retroactively created to close the sprint tracking gap.
