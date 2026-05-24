# Review Log: grid-map-system.md

> **Amendment — 2026-05-18:** The Manhattan distance function (`get_manhattan_distance`) documented in this GDD is still used in the production system, but its consumer has changed. Previously, Building System Formulas 3–5 used distance to reduce output quantity and extend cycle duration. Under the Transportation System model, distance now drives **carrier travel time** (`carrier_travel_ticks = floor(distance × ticks_per_tile)`) for the Transportation System's carrier NPCs. The Grid/Map System's distance API is unchanged — only who calls it and why has changed. No re-review of the grid GDD is required; this note serves as a cross-reference amendment.

## Review — 2026-05-08 — Verdict: APPROVED
Scope signal: M
Specialists: (lean mode — no subagents)
Blocking items: 0 | Recommended: 3
Summary: All prior blockers resolved. User's re-review found 5 new issues (B1–B5) and 3 remaining recommendations (R1–R5, R7 obsolete). All fixed in revision pass. GDD is structurally sound and internally consistent.
Prior verdict resolved: Yes — all 9 prior blockers + all 5 new issues + 5 of 6 remaining recommendations addressed

---

## Design Review: Grid/Map System

**Review mode:** lean (single-session structural analysis)
**Re-review:** Yes — prior verdict was NEEDS REVISION on 2026-05-08

### Completeness: 8/8 sections present

All required sections present plus bonus sections: States and Transitions, Visual/Audio, UI Requirements, Open Questions (resolved items documented), and explicit UX flag.

### Dependency Graph

| Declared Dependency | Status |
|---------------------|--------|
| Resource System | `design/gdd/resource-system.md` — **exists** |

All declared dependencies exist on disk.

**Bidirectional check:** Grid/Map no longer has a Tick System dependency (regrowth removed). The Grid → Resource System dependency is bidirectionally consistent.

### Prior Blocking Items — Resolution Status

| # | Prior Blocker | Status |
|---|---------------|--------|
| **B1** | Placement validation contradicts edge case | **RESOLVED** — Clearable resources (tree/berry/grass) allow placement; non-clearable (stone) blocks placement |
| **B2** | Depleted tile behavior unspecified | **RESOLVED** — Resources are infinite Anno-style spatial anchors, no amount tracking |
| **B3** | Moisture threshold mismatch | **RESOLVED** — Table shows `Low (< 0.5)` for berry vs grass |
| **B4** | PerlinNoise API misrepresentation | **RESOLVED** — Formula 4 shows instance property configuration |
| **B5** | Missing YSort requirement | **RESOLVED** — Section 7 mandates YSort as non-negotiable pattern |
| **B6** | Grid arrays vs. TileMapLayer ownership | **RESOLVED** — Section 7 defines unidirectional data flow |
| **B7** | Square bounding box vs. Euclidean radius | **RESOLVED** — Documented in grid query API |
| **B8** | Regeneration policy not stated | **RESOLVED** — Explicit: single map per game |
| **B9** | Acceptance criteria need tightening | **RESOLVED** — ACs enumerate enum values, include epsilon, provide GIVEN clauses |

### Revision Pass — Issues Found and Applied Fixes

| # | Issue | Severity | Fix Applied |
|---|-------|----------|-------------|
| **B1** | AC duplicate numbering (AC 11 appears twice) | HIGH | ✅ AC 11→12, 12→13, 13→14, all subsequent ACs shifted by +1 (26 total ACs) |
| **B2** | Depleted tile edge case contradicts infinite resource model | MEDIUM | ✅ All `amount` references removed. Resource Harvesting Edge Cases section deleted. Only remaining edge case: building removal during production (infinite model compatible) |
| **B3** | `regrow_resource` method + all regrowth references | MEDIUM | ✅ `regrow_resource` removed from API table. Tick System dependency from Grid upstream removed. `regrowth_rate` removed from Tuning Knobs. All 4 remaining "regrow" references now only say "resources never regrow" |
| **B4** | Transport time float → int conversion unspecified | LOW | ✅ Formula updated to `ceil(d_manhattan * TICKS_PER_TILE * (1 - road_bonus))`. `d_manhattan` max corrected 56→58. Output Range corrected to [5, 2900] |
| **B5** | `find_nearest` AC 17 missing max_radius in GIVEN | LOW | ✅ GIVEN clause now includes "AND a valid `max_radius` of 30 (sufficient to reach all tiles)" |
| **R1** | Smoothing removes ~85% of noise diversity | — | ✅ Cross-knob note added: "at 0.6 × 2, ~84% of original noise diversity is lost — maps are very smooth and homogenized. For more varied terrain, use 0.5 × 2 or 0.6 × 1." |
| **R2** | `road_bonus` has no runtime clamp | — | ✅ "Enforced by UI — value is clamped to [0.0, 0.5] on the settings slider. No runtime clamp in formula." added to Tuning Knobs row |
| **R5** | `get_tiles_in_radius` square→circular post-filter not explicit | — | ✅ "**IMPORTANT**" → "**IMPORTANT** ... Callers requiring a true **CIRCULAR** radius must..." — made more visible |
| **R3** | Output range off by factor of 10 | — | ✅ Superseded by B4 fix (transport_ticks corrected to [5, 2900]) |
| **R4** | `regrow_resource` ownership ambiguity | — | ✅ Superseded by B3 fix (method + all references removed) |
| **R6** | Finite-resource edge case scope ambiguity | — | ✅ Superseded by B2 fix (entire section deleted) |

---

### Scope Signal

**Rough scope signal: M** (producer should verify before sprint planning)

Moderate complexity: 6 formulas, 2 cross-system dependencies, procedural generation algorithm, layer-based data model. No new ADRs required — Godot 4.6 TileMapLayer and PerlinNoise are well-documented.

### Verdict: APPROVED

All blocking and medium items resolved. All remaining recommendations addressed. GDD is structurally sound and internally consistent.

---

## Review — 2026-05-08 (Revision Pass) — NEEDS REVISION (Superseded)

**Review mode:** lean (single-session analysis)
**Re-review:** Yes — prior verdict was NEEDS REVISION on 2026-05-08

Prior blocking items resolved: B1 placement validation, B2 depleted tile behavior, B3 moisture threshold, B4 PerlinNoise API, B5 YSort, B6 data ownership, B7 square bounding box, B8 regeneration policy, B9 AC tightening.

New findings (5 issues + 6 recommendations): All fixed in revision pass. See Revision Pass table above.

---

## Review — 2026-05-08 (First Review) — NEEDS REVISION (Superseded)

*This review is superseded by the re-review above. Kept for historical reference only.*

Scope signal: M
Specialists: game-designer, systems-designer, qa-lead, godot-specialist, creative-director
Blocking items: 7 | Recommended: 8

### Summary

Placement validation contradicts edge case (B1), moisture threshold code/table mismatch (B3), PerlinNoise API misrepresentation (B4), missing YSort/depth sorting (B5), unclear dual-state ownership (B6), unspecified depleted tile behavior in radius checks (B2). Acceptance criteria need tightening (B9). All fixable in single revision pass.

Prior verdict resolved: First review
