## Review — 2026-05-09 — Verdict: NEEDS REVISION

**Scope signal:** S (single system, 3 simple formulas, no new ADRs, ~7 downstream dependencies)
**Specialists:** (lean mode — no subagents)
**Blocking items:** 3 | **Recommended:** 5

### Completeness: 8/8 sections present

All 8 required sections present plus bonus sections: States and Transitions, Interactions with Other Systems, Visual/Audio Requirements, UI Requirements, Open Questions.

### Dependency Graph

| System | Status |
|--------|--------|
| Tick System | EXISTS (Approved) |
| Player Character System | NOT FOUND (undesigned) |
| Camera System | NOT FOUND (undesigned) |
| UI Systems | NOT FOUND (fragmented into HUD, Building Menu UI, Settings/Pause Menu UI) |
| Settings System | NOT FOUND (undesigned) |
| Building System | NOT FOUND (undesigned) |
| Manual Labor System | NOT FOUND (undesigned) |
| HUD System | NOT FOUND (undesigned) |

**Cross-check finding:** Action IDs reference `pause_toggle`, `speed_increase`, `speed_decrease` for Tick System — consistent with Tick System's time control actions. However, Input System lists 3x in speed cycling while the Tick System GDD only defines 0.5x, 1x, 2x.

---

### Required Before Implementation

| # | Issue | Severity |
|---|-------|----------|
| **B1** | **Speed cycling references 3x, but game only supports 0.5x, 1x, 2x.** Line 63: "Cycle speed down (3x → 2x → 1x → 0.5x)" and line 64: "Cycle speed up (0.5x → 1x → 2x → 3x)". The Tick System GDD's SPEED_OPTIONS only contains 0.5, 1.0, 2.0. If a programmer implements 3x based on this GDD, it conflicts with the Tick System. | CRITICAL |
| **B2** | **Mouse World Position formula is underspecified.** `world_pos = camera_offset + (screen_pos / camera_zoom)` produces a pixel-space result, but the variable table declares `world_pos` in tile coordinates (0-30 range). The example acknowledges the gap: "Convert to tile space: (405 / tile_size, 305 / tile_size)" — but this conversion is NOT in the formula. The note "Actual formula depends on engine coordinate system. This is conceptual." is hand-waving — a programmer cannot implement mouse-to-tile conversion from this doc alone. | HIGH |
| **B3** | **Redundant zoom actions.** `camera_zoom_in` (+ key) and `camera_zoom_out` (- key) are defined alongside scroll wheel zoom. This isn't wrong, but creates input bloat for a relaxation-focused game (Submission aesthetic). Having 3 ways to zoom (scroll, +, -) adds cognitive load without meaningful benefit. | MEDIUM |

### Recommended Revisions

| # | Issue | Severity |
|---|-------|----------|
| **R1** | Input Context transition matrix incomplete: PAUSED → UI_ACTIVE (does Escape work while paused?), UI_ACTIVE → PAUSED (deferred vs immediate) not fully documented in the transition table. | MEDIUM |
| **R2** | `mouse_edge_pan_threshold` notes say "(if implemented)" — Vertical Slice GDD should not have implementation qualifiers. | LOW |
| **R3** | Gamepad warning mechanism not assigned to any system. | LOW |
| **R4** | Non-QWERTY edge case references a future feature — belongs in Open Questions, not Edge Cases. | LOW |
| **R5** | Open Questions says "None" but the 3x speed conflict with Tick System should be listed. | LOW |

---

### Verdict: NEEDS REVISION

B1 (3x speed conflict) is the most critical issue — it directly conflicts with the Tick System GDD. B2 (mouse conversion formula) is a documentation gap that will require the Grid/Map System to fill in. B3 (redundant zoom inputs) is a design-elegance concern.

---

## Review — 2026-05-10 (Re-review) — Verdict: APPROVED

**Prior verdict:** NEEDS REVISION (2026-05-09)
**Prior blocking items:** 3 | **Prior recommended:** 5
**All prior items addressed.**

### Issues Addressed from Prior Review

| # | Issue | Status | Fix Applied |
|---|-------|--------|-------------|
| **B1** | Speed cycling references 3x (conflicts with Tick System) | RESOLVED | Removed 3x from both speed cycling descriptions. Now cycles 0.5x → 1x → 2x. |
| **B2** | Mouse World Position formula underspecified | RESOLVED | Added `tile_size` as variable (defined by Grid/Map System). Updated formula, variable table, example, and added dependency note. |
| **B3** | Redundant +/- zoom keys alongside scroll wheel | RESOLVED | Removed `camera_zoom_in`/`camera_zoom_out`. Unified to single `camera_zoom` action via scroll wheel. |
| **R1** | Context transition matrix incomplete | RESOLVED | Fixed state diagram — clarified Space during UI_ACTIVE is deferred (not direct PAUSED transition). |
| **R2** | `mouse_edge_pan_threshold` has "(if implemented)" qualifier | RESOLVED | Removed qualifier. |
| **R3** | Gamepad warning mechanism not assigned | RESOLVED | Assigned to HUD System. |
| **R4** | Non-QWERTY edge case references future feature | RESOLVED | Removed "(future feature)" reference from Edge Cases. |
| **R5** | Open Questions says "None" despite 3x conflict | RESOLVED | Added pending decision about 3x speed (cross-ref to Tick System OQ1). |

### Bonus Issues Found During Revision

| # | Issue | Severity | Fix Applied |
|---|-------|----------|-------------|
| **R6** | AC6 referenced removed `camera_zoom_in` action ID | LOW | Updated to reference `camera_pan` instead. |

### Verdict: APPROVED

All blocking and recommended items resolved. The Input System GDD is consistent with the Tick System (speed cycling, zoom range), the mouse conversion formula now includes all necessary variables (tile_size from Grid/Map), and the context transition state machine is correctly documented.

---

### Scope Signal

**Rough scope signal: S (single system, 3 simple formulas, no new ADRs, ~7 downstream dependencies)**

The Input System is primarily an event broadcaster — the heaviest part is the action mapping config file and the context state machine. Formula 1 (mouse conversion) is engine-specific and will be trivial to implement with any engine's built-in coordinate system.

**Producer should verify before sprint planning:** The 7 downstream dependencies mean the Input System's interface (action IDs, event signatures) becomes a shared contract. All downstream GDDs must reference the same action ID names. This is a coordination concern, not a complexity concern.
