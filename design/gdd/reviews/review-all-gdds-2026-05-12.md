# Cross-GDD Review Report — "From Scratch" Vertical Slice

> **Date:** 2026-05-12
> **Skill:** `/review-all-gdds` (full — consistency + design theory)
> **GDDs Reviewed:** 13 (11 Vertical Slice + game-concept + systems-index)
> **Systems Covered:** Tick, Resource, Input, Grid/Map, Inventory/Storage, Player Character, Camera, Building, NPC, Hunger, HUD (+ Recipe Database MVP)

---

## Verdict: ✅ PASS — All 8 Blocking Issues resolved (2026-05-13). W1–W6 fixed, W7 deferred to Population Tier GDD.

---

## Blocking Issues

### ~~B1: Building System depends on Production System (undocumented)~~ ✅ RESOLVED 2026-05-12

**Files:** `building-system.md` lines 208–216, `systems-index.md` row 14
**Phase:** 2 — Consistency

Building System defines `on_building_ready()`, `get_recipe()`, and `get_available_npcs()` as hard dependencies on "Production System." The Production System does not exist in `systems-index.md` or as a GDD. It is referenced as a future system but used as a hard architectural contract in Building System's core rules and interaction table.

**Fix:** Add a Production System GDD to the Vertical Slice scope, or merge its responsibilities into the Building System, before architecture begins. The `on_building_ready()` signal contract must not be specified without a receiving system.

---

### ~~B2: NPC death/removal is entirely undefined~~ ✅ RESOLVED 2026-05-12

**Files:** `hunger-system.md`, `npc-system.md`, `building-system.md`
**Phase:** 4 — Scenario Walkthrough (Scenario 2)

Hunger System states "no death, no game-over" — hunger only applies a -50% debuff. But if NPC loss was ever intended as a consequence, there is no mechanism for it anywhere. NPC System's state machine has no "dead" or "removed" state. Building System has no `remove_npc()` interface. The starvation path ends in a permanent debuff with no recovery or exit.

Either consequence model (death / no-death) is valid — but neither is fully specified. A permanent debuff with no death and no recovery path means the player can be stuck in a degraded state indefinitely.

**Fix:** Define NPC death as an explicit mechanic (permanent workforce loss, rebuild cost), or formalize the no-death design and specify how the HUNGRY debuff eventually resolves.

---

### ~~B3: 0 Energy hard lockout contradicts PC System design intent~~ ✅ RESOLVED 2026-05-12

**Files:** `player-character-system.md` Rules 2 and 5, `building-system.md` Formula 7
**Phase:** 4 — Scenario Walkthrough (Scenario 3)

PC System Rule 5 states: "manual actions CAN be started at 0 energy (not locked out — energy is an hourglass, not a wall)." But Rule 2's upfront energy check (`current_energy >= action_energy_cost`) blocks all actions at 0 energy, since the minimum action cost is 5 energy (Pick Berries). Building placement is also blocked (Formula 7 minimum = 1 energy). At 0 energy, the player can only move the camera.

This creates a catch-22: can't gather food because energy is 0, can't eat if food is only in storage, can't place buildings to fix production.

**Fix:** Either allow 0-energy actions with a debuff (design matches statement), or correct the design statement to acknowledge the hard lockout and define how the player escapes it.

---

### ~~B4: NPC WAITING state has no timeout matching Building System STALLED threshold~~ ✅ RESOLVED 2026-05-12

**Files:** `npc-system.md`, `building-system.md` Rule 7, Tuning Knob T5
**Phase:** 4 — Scenario Walkthrough (Scenario 4)

Building System discards STALLED output after 24,000 ticks. NPC System's WAITING state (NPC stuck at full storage) has no matching timeout. If the building discards its held output, the NPC is left in WAITING with no output to deposit and no defined transition — it can wait indefinitely.

**Fix:** Add a WAITING timeout to the NPC System set to match the Building System's STALLED threshold (24,000 ticks), with a defined exit transition (return to IDLE, building re-enters BLOCKED).

---

### ~~B5: Storage Building upgrade mechanic ownership is unresolved~~ ✅ RESOLVED 2026-05-13

**Files:** `inventory-storage-system.md` line 70, `building-system.md` production table
**Phase:** 2 — Consistency

**Resolution:** Upgrade mechanic removed entirely. Storage Building is now a single-tier structure (150 slots). No upgrade state, no upgrade cost, no upgrade UI. To expand storage, players place additional Storage Areas or Storage Buildings. All upgrade references removed from `inventory-storage-system.md` (Formula 4, EC-M4, EC-L4, Tuning Knobs, UI section, AC13).

---

### ~~B6: Player fantasy split — architect vs. settler~~ ✅ RESOLVED 2026-05-13

**Files:** `player-character-system.md` ("NO visible sprite, acts remotely"), `game-concept.md`, `building-system.md` Player Fantasy
**Phase:** 3 — Design Theory (3g)

**Resolution:** Architect with a limited early phase. Manual labor (Pick Berries, Chop Tree, Mine Stone) is available only in the pre-NPC window (Day 1). The moment the first NPC is assigned to a building, all manual gathering locks out permanently. The player transitions into pure Architect Mode: building placement, storage management, system observation. No hybrid phase. This is a one-way, irreversible transition within a session.

Changes: `player-character-system.md` Rule 9 (Architect Mode) added; `game-concept.md` Core Mechanic 1 updated.

---

### ~~B7: No difficulty escalation after the first bottleneck is solved~~ ✅ RESOLVED 2026-05-13 — BY DESIGN

**Files:** `game-concept.md`, `hunger-system.md`, `tick-system.md`
**Phase:** 3 — Design Theory (3e)

**Resolution:** The Vertical Slice is intentionally a single linear path. Its purpose is to validate that systems connect correctly — it is a "does the loop work?" test, not a "is the game challenging?" test. Difficulty escalation arrives with MVP content: more complex production chains, population tier consumption scaling, and the 30×30 spatial constraint as new buildings compete for prime real estate. No VS changes required.

---

### ~~B8: Vertical Slice is a solved game — dominant strategy makes all choices irrelevant~~ ✅ RESOLVED 2026-05-13 — BY DESIGN

**Files:** All Vertical Slice GDDs
**Phase:** 3 — Design Theory (3c)

**Resolution:** The VS is intentionally a single validated path. Its purpose is to confirm that systems connect and the core loop (manual → automated) is satisfying — not to provide strategic variety. Meaningful decision-making arrives with MVP content. No changes to VS scope.

---

## Warnings

**~~W1: Building System Rule 7 text contradicts tuning knobs.~~** ✅ RESOLVED 2026-05-13
Rule 7 was already corrected during B4 resolution — output is never discarded, no timer. Also fixed a stale reference in EC-H1 step 4 (save/load stall timer language removed).

**~~W2: Formula section example calculation error.~~** ✅ RESOLVED 2026-05-13
`building-system.md` degeneracy example and formula example updated: distance 10 → modifier 0.70, output = 3 (was 0.80/4).

**~~W3: Resource naming inconsistency — German vs. English.~~** ✅ RESOLVED 2026-05-13
Canonical names: **Wood, Stone, Berry** (English). All "Holz"/"Stein" references removed from `inventory-storage-system.md` and `player-character-system.md` formula/UI sections. German prose in `game-concept.md` and `hunger-system.md` (Player Fantasy) intentionally left in German.

**~~W4: NPC System Formula 3 cross-reference naming is ambiguous.~~** ✅ RESOLVED 2026-05-13
`npc-system.md` Formula 3 updated to reference "Building System Formula 4 (Production Output, which uses Formula 3 — Distance Modifier internally)".

**~~W5: Tool durability cost is invisible at the point of consumption.~~** ✅ RESOLVED 2026-05-13
`building-system.md` UI-5 (Hover Tooltip) updated: buildings that consume tool durability now show `[Tool Name] — N durability remaining` in the hover tooltip. Durability ≤ 2 cycles worth displays in red.

**~~W6: HUD information density may exceed player attention budget.~~** ✅ RESOLVED 2026-05-13
`hud-system.md` OQ6 added: all system alerts must consolidate into a single **Notification Tray** before MVP. Required architectural constraint documented.

**W7: Population Tier consumption cliff risk.** ⏭ DEFERRED
Will be addressed when the Population Tier GDD is authored. Reminder: Tier 2 food cost must use a ramp (~1.5× Tier 1), not a step cliff (3×). Note this in the Population Tier GDD brief.

---

## Info (healthy patterns)

- **Signal ordering is well-reasoned.** `on_ticks_advanced()` before `on_day_transition()` for NPC spawn timing vs. hunger consumption is handled correctly in Building EC-M3.
- **Abstract NPC movement reduces attention demand.** NPCs without map sprites is a correct design choice for a systems-focused village builder.
- **Distance formulas are consistent.** Both penalty knobs (T1 output penalty, T2 time penalty) use the same Manhattan distance source and are tunable independently — good separation of concerns.
- **Edge case severity classification is thorough.** Building System's HIGH/MEDIUM/LOW organization with the cross-system interaction matrix is exemplary.
- **Energy provides a soft bottleneck.** The energy→food→work loop creates natural pacing within the single-path Vertical Slice structure.
- **Day 1 free period is intentional.** NPCs spawned during Day 1 don't trigger food consumption until the next day transition — giving the player one day to prepare. Correct per `hunger-system.md`.

---

## Cross-System Scenario Issues

| # | Severity | Scenario | Issue |
|---|----------|----------|-------|
| S1 | ~~**BLOCKER**~~ ✅ | 4: Storage Full | Resolved: STALLED output is never discarded. Building waits indefinitely; NPC state is tied to building, no independent WAITING timeout needed. |
| S2 | **BLOCKER** | 3: Energy Depletion | 0 Energy is a hard lockout. Design says "not locked out" but upfront energy check blocks all actions. Resolves when B3 is fixed. |
| S3 | **WARNING** | 4: Storage Full | Two code paths lead to STALLED (building deposit fail vs. NPC deposit fail). Neither GDD clearly assigns primary ownership of the STALLED state trigger. |
| S4 | **INFO** | 5: Day Transition | Lag spikes can extend construction by up to 100 ticks (excess ticks discarded at day boundary). Acceptable known limitation. |
| S5 | **INFO** | 1: Lumber Camp Setup | Day 1 NPC hunger-free period is intentional and handled correctly by signal ordering. |

---

## Recommended Resolution Order

| Priority | Issue | Before |
|----------|-------|--------|
| 1 | **B1** — Design Production System GDD or merge into Building System | Architecture |
| 2 | **B2** — Formalize NPC death or no-death with full consequence chain | Architecture |
| 3 | **B3** — Fix 0 energy lockout (allow free actions or correct design doc) | Architecture |
| 4 | **B4** — Sync NPC WAITING timeout with STALLED threshold | Architecture |
| 5 | **B5** — Assign upgrade mechanic ownership | Architecture |
| 6 | **B6** — Resolve architect vs. settler fantasy identity | MVP Design |
| 7 | **B7** — Define difficulty escalation beyond Vertical Slice | MVP Design |
| 8 | **B8** — Add branching choices to Vertical Slice | Playtesting |
| 9 | **W1–W7** | Before implementation of affected system |

**Do NOT run `/gate-check pre-production` until B1–B5 are resolved.** B6–B8 are design-critical and should be resolved before MVP to avoid rewriting foundational design decisions during production.
