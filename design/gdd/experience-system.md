# Experience System

> **Status**: Draft — complete (2026-06-17); time-based XP revision (2026-06-18)
> **Author**: User + Claude (Opus 4.8)
> **Last Updated**: 2026-06-18
> **Implements Pillar**: Pillar 1 (Earned Automation), Pillar 2 (Information Transparency)
> **Design note**: NPCs accrue XP from completed work and logistics deliveries and level up
> (max level 10). XP is **time-based**: a completed activity earns XP in proportion to the ticks
> it nominally takes, so a building with a short production cycle no longer out-levels a slow one
> for the same working time. **Update 2026-06-18: level-ups are no longer cosmetic** — each level
> raises the NPC's efficiency **cap** by +5% (via `EfficiencyFormulas.nutrition_bonus_cap`); the
> higher ceiling must be filled by feeding more nutrition. Note this was implemented through the
> nutrition cap, not the originally-reserved `experience_modifier` F1 hook (which stays at 1.0).
> Each level-up also grants a perk choice (Perk System).

## Overview

The Experience System gives every NPC a sense of growth over its working life. As an NPC does
completed work — a building's assigned worker finishing a production cycle, or a carrier finishing
a logistics delivery — it earns experience points (XP) **in proportion to the time that activity
nominally takes**, so progress tracks working time rather than the raw count of completed actions.
Accumulated XP raises the NPC's level
along a rising curve that starts cheap and grows steadily, capping at level 10. Each NPC tracks
its lifetime XP and a derived level; both persist across save/load. **As of 2026-06-18, levelling
matters mechanically**: each level raises the NPC's efficiency *cap* by +5% (via
`EfficiencyFormulas.nutrition_bonus_cap`), so a higher-level NPC can reach a higher max efficiency
— but only if fed enough nutrition to fill the raised ceiling. Travel speed and output remain
unaffected by level. (The originally-reserved `experience_modifier` F1 hook stays fixed at 1.0; the
level effect was routed through the nutrition cap instead.) Progress is surfaced everywhere the player already looks at
NPCs: a level badge and XP bar on the NPC grid tile, a level row and detailed XP bar in the NPC
detail panel, and a "Level Up!" float over the NPC icon on the map.

## Player Fantasy

Your crew grows with you. The NPC you recruited on day one — the one who first picked up the axe
while you watched — is not the same worker months later. They have hauled hundreds of logs,
walked thousands of tiles, and the game remembers it. A small number ticks up beside their name,
and you feel it: this one is a veteran.

This is the fantasy of investment paying off over time. You already feel the Foreman's competence
through delegation; experience adds *attachment*. The named worker you renamed "Old Pieter" is now
Level 7, and you notice him. When a "Level Up!" floats over a worker mid-shift, it is a quiet
acknowledgement — your village is not static, it is accruing history. You did not micromanage that
growth; it emerged from keeping your crew employed and fed.

Crucially, at this stage the level is a *badge of service*, not a power lever — and the game is
honest about that (Pillar 2: no hidden effects). It is a foundation the player can already see and
care about, before it ever changes a number. When the system later grants veterans real bonuses,
the player will already have an emotional stake in who their experienced workers are.

## Detailed Rules

### Core Rules

**Rule 1: Per-NPC XP and Level**
Each NPC carries two new properties: `xp` (cumulative lifetime experience, an integer that only
ever increases) and `level` (an integer 1–10, the cached value derived from `xp`). A newly
recruited NPC starts at `xp = 0`, `level = 1`. The level is always a pure function of total XP
(Formula 2) — `xp` is the source of truth, `level` is a cached derivation that is recomputed
whenever XP is granted and re-derived on load.

**Rule 2: XP-Granting Events**
XP is awarded per *completed activity*, never per tick (keeps it deterministic and tick-rate
independent). The amount, however, **scales with the activity's nominal duration** so that XP
accrues per unit of working time, not per raw count of actions (Formula 1). Exactly two events
grant XP at this scope:

- **Production cycle completed** — when a building with an assigned worker finishes a production
  cycle and places output in its buffer (the Building System's `production_output_ready` event).
  The building's assigned worker earns `xp_for_duration(base_cycle_ticks)` — XP proportional to
  the recipe's nominal cycle length. (This is the canonical "the crew did a unit of work" moment in
  the current build, where production is building-driven and output is collected by carriers — the
  worker does not itself walk output to storage.)
- **Carrier delivery completed** — when a carrier NPC completes a logistics delivery (unloads
  cargo at the destination). Grants `xp_for_duration(delivery_leg_nominal_ticks)` — XP proportional
  to the nominal source→destination travel time of that delivery.

**Nominal, not effective, duration.** The duration used is the *efficiency-independent* base value
(the recipe's `base_cycle_ticks`; the delivery leg's pre-efficiency travel ticks). Hunger and
efficiency change how *many* activities finish per day, not the XP earned per activity — so a
hungry worker simply completes fewer cycles per day and levels more slowly, rather than earning a
per-cycle bonus for being slow.

Travel to the source, recruitment, waiting, and idle time grant no XP. A recruited-but-unassigned
NPC, and a building that produces without an assigned worker (e.g. unstaffed gathering), gain no XP
— experience is strictly a reward for an NPC doing completed productive work.

**Rule 3: Granting and Level-Up Resolution**
When an event grants `amount` XP to an NPC: `xp += amount`; the new level is derived via Formula 2.
If the derived level is higher than the stored `level`, a level-up has occurred — the stored
`level` is updated and a level-up notification fires. A single grant may cross at most one
threshold in practice, but the derivation is robust to crossing several at once (it always lands
on the correct level for the new total). XP is never lost or "spent"; it accumulates for the NPC's
whole life.

**Rule 4: Level Cap**
The maximum level is `MAX_LEVEL` (10). Once an NPC reaches level 10, it continues to accumulate
`xp` (the number keeps rising) but the level does not increase further and no further level-up
notifications fire. The UI shows a "MAX" state instead of a progress bar for level-10 NPCs.

**Rule 5: Level Raises the Efficiency Cap (2026-06-18)**
Each NPC level raises the efficiency **ceiling** by `+0.05` (`LEVEL_EFFICIENCY_PER_LEVEL`), added
to `EfficiencyFormulas.nutrition_bonus_cap`. Level 1 fed-max is 0.50; level 10 fed-max is 0.95.
The bonus is a *cap*, not a flat boost: the extra ceiling is only realized by feeding more nutrition
(5%/nutrition) — levelling alone does not change current efficiency. Implementation note: this uses
the nutrition cap channel, **not** the reserved `experience_modifier` F1 hook (still fixed at 1.0;
kept for a possible future multiplicative use). Travel speed, output, and carry capacity are still
unaffected by level. Each level-up also grants one perk choice (Perk System).

**Rule 6: Persistence**
`xp` is serialized and restored with each NPC. `level` is **not** trusted from the save file — it
is re-derived from `xp` on load (Formula 2), so a change to the level curve in a patch
retroactively yields the correct level for existing saves. Removing an NPC (house demolition,
player removal) discards its XP with it; XP is not transferable between NPCs.

### Notifications

The system emits two signals consumed by the UI (display-only, per UI-code rules):

- `npc_xp_gained(npc_id, total_xp, xp_into_level, xp_span)` — fired on every grant, drives the
  live XP-bar update.
- `npc_leveled_up(npc_id, new_level)` — fired only when the level actually increases, drives the
  "Level Up!" map float and badge refresh.

### Future Direction (non-binding)

A later balancing pass is expected to convert `experience_modifier` from the fixed `1.0` into a
level-driven curve feeding Efficiency Formula F1 (e.g. a small per-level efficiency or speed
bonus). When that happens, the storage model, signals, and UI defined here do not need to change —
only the modifier computation and this GDD's Rule 5. This section documents intent; it is not an
acceptance criterion at this scope.

## Formulas

### Formula 1: Time-Based XP Grant

XP is granted in proportion to the activity's nominal duration in ticks, rounded to the nearest
integer:

`xp_gain = round(XP_PER_REFERENCE_CYCLE × duration_ticks / REFERENCE_CYCLE_TICKS × role_multiplier)`

where `duration_ticks` is the activity's **nominal** (efficiency-independent) length:
`base_cycle_ticks` for a production cycle, or the source→destination travel ticks for a delivery.
`role_multiplier` biases XP by role: `PRODUCTION_XP_MULTIPLIER` for a building worker's production
cycle, `CARRIER_XP_MULTIPLIER` for a carrier's delivery. A non-positive duration grants 0. Work and
delivery share the same per-tick base currency, scaled by their role multiplier — so an hour of
hauling and an hour of working no longer earn identical XP; carriers level faster, workers slower.

| Variable | Type | Default | Range | Description |
|----------|------|---------|-------|-------------|
| `XP_PER_REFERENCE_CYCLE` | int | 10 | 1–100 | XP earned for one *reference-length* activity at `role_multiplier = 1.0`. |
| `REFERENCE_CYCLE_TICKS` | int | 250 | 1–∞ | The nominal duration those XP correspond to (the base producer's cycle length). |
| `PRODUCTION_XP_MULTIPLIER` | float | 0.75 | 0.1–2.0 | Role multiplier for a production worker's per-cycle XP. |
| `CARRIER_XP_MULTIPLIER` | float | 1.25 | 0.1–2.0 | Role multiplier for a carrier's per-delivery XP. |
| `duration_ticks` | int | — | 0–∞ | The activity's nominal length (input, not a knob). |

With the defaults the base per-tick rate is `10 / 250 = 0.04 XP/tick`, then scaled by role. A
250-tick base-producer cycle earns `round(10 × 0.75) = 8` XP for its worker; a 750-tick cycle earns
`round(30 × 0.75) = 23`. A 50-tile delivery (~250 ticks) earns its carrier `round(10 × 1.25) = 13`
XP. Because slow activities earn proportionally more per completion, every building levels its
worker at the **same rate per day of continuous work** within a role — see the pacing example below.
`XP_PER_REFERENCE_CYCLE` is the primary global pacing knob; `REFERENCE_CYCLE_TICKS` sets what "10 XP
worth of work" means; the two role multipliers tilt pacing between workers and carriers.

---

### Formula 2: Level Curve and Derivation

**XP required to advance from a given level to the next** (rounded to a clean step):

`xp_to_advance(level) = round(BASE_XP × level ^ LEVEL_EXPONENT / XP_ROUNDING) × XP_ROUNDING`

**Cumulative XP required to reach a level** (the threshold at which the NPC *is* that level):

`cumulative_xp(L) = Σ xp_to_advance(k)` for `k = 1 … L-1`, with `cumulative_xp(1) = 0`

**Level from total XP** (the derivation in Rule 1/6):

`level_for_total_xp(total) = ` the largest `L` in `[1, MAX_LEVEL]` such that `cumulative_xp(L) ≤ total`

| Variable | Type | Default | Range | Description |
|----------|------|---------|-------|-------------|
| `BASE_XP` | int | 100 | 50–500 | XP for the first level-up (1→2). Scales the whole curve. |
| `LEVEL_EXPONENT` | float | 1.5 | 1.0–2.5 | Curve steepness. 1.0 = linear, higher = later levels cost disproportionately more. |
| `XP_ROUNDING` | int | 10 | 1–100 | Thresholds are rounded to this step for clean display. |
| `MAX_LEVEL` | int | 10 | 2–50 | Hard cap; XP keeps rising past it but level does not. |

**Resulting curve (defaults):**

| Level → next | `xp_to_advance` | Cumulative to reach level |
|--------------|-----------------|----------------------------|
| 1 → 2 | 100 | L1: 0 |
| 2 → 3 | 280 | L2: 100 |
| 3 → 4 | 520 | L3: 380 |
| 4 → 5 | 800 | L4: 900 |
| 5 → 6 | 1120 | L5: 1700 |
| 6 → 7 | 1470 | L6: 2820 |
| 7 → 8 | 1850 | L7: 4290 |
| 8 → 9 | 2260 | L8: 6140 |
| 9 → 10 | 2700 | L9: 8400 |
| (10 = MAX) | — | **L10: 11100** |

Total lifetime XP to reach max level: **11,100**.

---

### Formula 3: Progress Within a Level (UI)

Drives the XP progress bar and the "120 / 280 XP" label:

`xp_into_level = total_xp − cumulative_xp(level)`
`xp_span       = xp_to_advance(level)`  *(for `level < MAX_LEVEL`)*
`progress      = xp_into_level / xp_span`  *(0.0–1.0)*

At `level == MAX_LEVEL`, `xp_span = 0`: the UI shows a filled bar / "MAX" instead of a ratio
(division by zero is guarded).

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `total_xp` | int | 0–∞ | NPC's lifetime XP. |
| `xp_into_level` | int | 0 … `xp_span` | XP accrued since reaching the current level. |
| `xp_span` | int | 0, 100–2700 | XP needed to clear the current level (0 at MAX). |
| `progress` | float | 0.0–1.0 | Fraction for the bar fill. |

---

### Example Calculations

**Level derivation:** An NPC has `total_xp = 500`. `cumulative_xp(3) = 380 ≤ 500` and
`cumulative_xp(4) = 900 > 500`, so `level = 3`. Bar: `xp_into_level = 500 − 380 = 120`,
`xp_span = xp_to_advance(3) = 520` → `progress = 120/520 ≈ 0.23`. UI: "120 / 520 XP".

**A single grant crossing a threshold:** NPC at `total_xp = 95`, `level = 1`. A completed 250-tick
production cycle grants `round(10 × 0.75) = 8` → `total_xp = 103`. `cumulative_xp(2) = 100 ≤ 103`, so
derived level = 2 > stored 1 → level-up to 2, `npc_leveled_up` fires. New bar: `xp_into_level = 3`,
`xp_span = 280`.

**Pacing:** A day is `TICKS_PER_DAY = 1440` ticks. The base rate is `0.04 XP/tick`, scaled per role.
A worker producing continuously earns up to `1440 × 0.04 × 0.75 ≈ 43.2 XP/day` **regardless of cycle
length** — a 250-tick building does ~5.76 cycles/day × 8 XP, a 750-tick building does ~1.92
cycles/day × 23 XP, both ≈ 43 XP/day. A carrier hauling continuously earns up to
`1440 × 0.04 × 1.25 ≈ 72 XP/day`, so carriers level roughly `1.25 / 0.75 ≈ 1.7×` faster than workers
for the same time on the job. At the worker rate that gives ~level 2 in ~3 days, level 10
(11,100 XP) in ~260 days of full employment; carriers reach the same milestones proportionally
sooner. (Under the old flat-per-cycle rule the 750-tick building leveled ~3× slower than the
250-tick one — the bug an earlier revision fixed; role multipliers were added on top 2026-06-19.)
Raising `XP_PER_REFERENCE_CYCLE` or lowering `BASE_XP` compresses the curve for everyone; the role
multipliers tilt workers vs. carriers without changing the global pace.

## Edge Cases

**EC-1: NPC at Max Level Keeps Working**
A level-10 NPC completes further cycles/deliveries. `xp` continues to rise (it is never frozen),
but `level_for_total_xp` is capped at 10, so `level` stays 10 and no `npc_leveled_up` fires. The UI
shows a "MAX" state (full bar, no ratio) for that NPC. `npc_xp_gained` still fires; the detail
panel may show lifetime XP but no "to next" target.

**EC-2: Production Stalled (Output Buffer Full / No Input)**
When a building cannot complete a cycle — output buffer full, missing input, or no assigned worker
— it emits no `production_output_ready`, so **no XP is granted**. XP is tied to actual cycle
completion, not to a building merely being staffed. Once production resumes and a cycle completes,
the worker earns XP normally.

**EC-3: Building Without an Assigned Worker**
A building that produces without an assigned worker (e.g. an unstaffed gathering building, if the
recipe permits) still emits `production_output_ready`, but the XP lookup finds no assigned NPC and
grants nothing. XP requires an NPC to credit it to.

**EC-4: NPC Pulled Off Mid-Cycle**
If a building is demolished or the NPC is released/reassigned while a cycle is in progress (NPC
System Rule 8), no `production_output_ready` fires for that interrupted cycle → **no XP**.
Experience only rewards finished cycles; no partial credit.

**EC-5: NPC Removed From the Game**
When an NPC is permanently removed (house demolition + player-confirmed removal), its `xp` and
`level` are discarded with it. XP is not refunded, banked, or transferred to any other NPC.

**EC-6: Level Curve Changed in a Patch**
Because `level` is always re-derived from `xp` on load (Rule 6), changing `BASE_XP`,
`LEVEL_EXPONENT`, or `MAX_LEVEL` in an update retroactively yields the correct level for every
existing NPC. No migration step is needed. A curve change can move an NPC's level up or down
relative to its old display; this is expected and silent (no level-up float fires on load).

**EC-7: Multiple Thresholds Crossed in One Grant**
If a single grant (e.g. a very long cycle, or after a tuning change to a large `XP_PER_REFERENCE_CYCLE`) pushes `total_xp` past
several thresholds at once, the derivation lands on the correct final level. One
`npc_leveled_up(npc_id, new_level)` fires carrying the **final** level — not one signal per
intermediate level. The "Level Up!" float reflects the final level reached.

**EC-8: Threshold Boundary Is Inclusive**
Reaching exactly `cumulative_xp(L)` counts as level `L` (the comparison is `≤`). E.g.
`total_xp = 100` is level 2, not level 1.

**EC-9: Missing or Corrupt Save Data**
If an NPC's `xp` is absent or unreadable in a save, it defaults to `0` (level 1). The NPC is never
left in an invalid level state; `level` is recomputed regardless of any stored value.

**EC-10: Shared Carrier on Multiple Routes**
A carrier assigned to several routes (shared-carrier model) earns `xp_for_carrier(delivery_leg_nominal_ticks)`
per completed delivery, sized to that delivery's own nominal travel time, regardless of which route
it was serving. Each delivery counts once; switching routes between deliveries does not grant or lose XP.

## Dependencies

| System | Relationship | Data Flow |
|--------|-------------|-----------|
| **NPC System** | Both | Owns the `NPCInstance` where `xp`/`level` live and hosts the experience signals (`npc_xp_gained`, `npc_leveled_up`). Exposes the `grant_xp()` entry point and serializes/restores `xp`. The Experience System is a logic module *inside* the NPC System's domain, not a separate Autoload. |
| **Building System** | Inbound | Work XP is driven by the Building System's `production_output_ready(building_id, output, cycle_ticks)` signal: each completed production cycle credits `xp_for_production(cycle_ticks)` (nominal `base_cycle_ticks`, scaled by `PRODUCTION_XP_MULTIPLIER`) to the building's `assigned_npc_id` (NPC System subscribes). |
| **Logistics System** | Inbound | On a completed carrier delivery (cargo unloaded at destination), calls the NPC System's XP grant for `route.npc_id` with `xp_for_carrier(route.delivery_leg_nominal_ticks)` (the delivery's nominal source→destination travel time, captured at pickup before efficiency scaling, scaled by `CARRIER_XP_MULTIPLIER`). |
| **Efficiency System** | Outbound | NPC `level` raises `EfficiencyFormulas.nutrition_bonus_cap` by `+0.05`/level (read by HungerSystem when computing the food modifier). The reserved `experience_modifier` F1 hook stays fixed at `1.0` — the level effect went through the nutrition cap instead (Rule 5). |
| **Save / World Save Manager** | Both | `xp` is persisted through the NPC System's `serialize`/`deserialize`; `level` is re-derived on load (Rule 6, EC-6). |
| **Tick System** | None | The Experience System is **event-driven**, not tick-driven — it holds no tick subscription. XP accrues only on completed-activity events. |
| **UI (NpcGrid, NpcDetailPanel, NpcOverlay, InventoryScreen)** | Outbound | Consume `npc_xp_gained`/`npc_leveled_up` and read `xp`/`level` for display only (no state writes), per UI-code rules. |

**Bidirectional back-references to add when implementing:** the dependency rule requires the
paired docs to mention this system. During implementation I will add a short Experience-System
entry to the Dependencies tables of `npc-system.md`, `logistics-system.md`, and
`efficiency-system.md` (the latter noting the `experience_modifier` input, fixed at 1.0).

## Tuning Knobs

| Knob | Default | Range | Effect | Notes |
|------|---------|-------|--------|-------|
| `XP_PER_REFERENCE_CYCLE` | 10 | 1–100 | XP earned for one reference-length activity at multiplier 1.0. Primary global pacing lever — scales XP/day for every NPC linearly. | Higher = faster levelling for all roles. Base currency shared by workers and carriers, then tilted per role by the two multipliers below. |
| `REFERENCE_CYCLE_TICKS` | 250 | 1–∞ | The nominal tick duration that `XP_PER_REFERENCE_CYCLE` corresponds to (the base producer's cycle). | Sets the XP/tick rate (`XP_PER_REFERENCE_CYCLE / REFERENCE_CYCLE_TICKS`). Lowering it raises XP for every activity proportionally. |
| `PRODUCTION_XP_MULTIPLIER` | 0.75 | 0.1–2.0 | Role multiplier on a production worker's per-cycle XP. <1.0 makes building workers level slower than the base rate. | Tilts pacing toward carriers. Set to 1.0 to make workers and carriers share one rate again. |
| `CARRIER_XP_MULTIPLIER` | 1.25 | 0.1–2.0 | Role multiplier on a carrier's per-delivery XP. >1.0 makes carriers level faster than the base rate. | Counterpart to `PRODUCTION_XP_MULTIPLIER`. Raise to reward hauling more; lower toward 1.0 to neutralise. |
| `BASE_XP` | 100 | 50–500 | XP cost of the first level-up; scales the entire curve. | Lowering compresses the whole curve; the cheapest global pacing change. |
| `LEVEL_EXPONENT` | 1.5 | 1.0–2.5 | Curve steepness. 1.0 = linear, higher = late levels cost disproportionately more. | 1.5 gives "early levels quick, late levels earned". >2.0 makes max level very grindy. |
| `XP_ROUNDING` | 10 | 1–100 | Rounds each level threshold to a clean step for display. | Cosmetic only; does not change pacing meaningfully. Set to 1 for exact curve values. |
| `MAX_LEVEL` | 10 | 2–50 | Hard level cap. XP keeps accruing past it but level stops. | Raising it extends progression; the UI badge and bar must remain legible at the chosen cap. |
| `experience_modifier` | 1.0 | 1.0 (locked) | The multiplicative efficiency hook for levels (Formula F1). | **Still locked at 1.0** — the live level effect (2026-06-18) instead raises the efficiency *cap* via `LEVEL_EFFICIENCY_PER_LEVEL` (+5%/level) in the nutrition curve. This F1 hook is reserved for a possible future multiplicative use. |

All knobs except `experience_modifier` live as constants in `ExperienceFormulas`; per the
gameplay-code rule they are defined in one place and consumed everywhere, never duplicated.

## Acceptance Criteria

| ID | Acceptance Criterion | Verification |
|----|---------------------|--------------|
| AC-1 | A completed production cycle grants `xp_for_production(base_cycle_ticks)` to the building's assigned worker (= `round(XP_PER_REFERENCE_CYCLE × PRODUCTION_XP_MULTIPLIER)` for a 250-tick cycle, scaling with longer cycles) | Automated: assign worker, fire `production_output_ready(building, output, cycle_ticks)` → assert worker `xp` increased by `xp_for_production(cycle_ticks)` |
| AC-1b | Two buildings with different cycle lengths, run for the same number of ticks, grant their workers (near-)equal XP | Automated: run an N-tick and a 3N-tick recipe over the same total ticks → assert the two workers' XP totals match within rounding |
| AC-2 | A completed carrier delivery grants `xp_for_carrier(delivery_leg_nominal_ticks)` to the carrier (nominal, efficiency-independent; `round(XP_PER_REFERENCE_CYCLE × CARRIER_XP_MULTIPLIER × ...)`) | Automated: run a logistics delivery to completion → assert carrier `xp` increased by `xp_for_carrier(delivery_leg_nominal_ticks)` |
| AC-3 | `level_for_total_xp` matches Formula 2 at every threshold and boundary (inclusive `≤`) | Automated: table test of total XP → expected level across all 10 levels, incl. exact-threshold values (e.g. 100 → 2) |
| AC-4 | Crossing a threshold raises `level` and fires `npc_leveled_up` once with the new level | Automated: grant XP across a boundary → assert `level` updated and one `npc_leveled_up(new_level)` emitted |
| AC-5 | A grant crossing several thresholds at once lands on the correct final level with one signal | Automated: grant a large amount → assert final level correct and exactly one `npc_leveled_up` carrying the final level |
| AC-6 | Level is capped at `MAX_LEVEL`; XP keeps rising past it with no further level-up | Automated: push `xp` past `cumulative_xp(MAX_LEVEL)` → assert `level == MAX_LEVEL`, further grants raise `xp` but emit no `npc_leveled_up` |
| AC-7 | A failed/interrupted deposit grants no XP; no double-grant on WAITING retry | Automated: full storage → NPC WAITING → assert no XP; free space → successful deposit grants exactly once |
| AC-8 | `xp` survives save/load and `level` is correctly re-derived on load | Automated: set `xp`, serialize, deserialize → assert `xp` restored and `level` equals `level_for_total_xp(xp)` |
| AC-9 | The NPC grid tile shows the level badge and an XP progress bar reflecting Formula 3 | Manual: screenshot the NPCs tab → badge shows current level, bar fill matches `progress` |
| AC-10 | The NPC detail panel shows the level and a "xp_into_level / xp_span XP" readout, updating live | Manual: open detail panel, trigger a deposit → level row and XP bar/label update; MAX level shows "MAX" |
| AC-11 | A "Level Up!" float appears over the NPC icon on the map when it levels up | Manual: drive an NPC across a level threshold → observe the float over its map icon |
| AC-12 | Level raises the NPC efficiency cap by +5%/level | Automated: `nutrition_bonus_cap(level)` increases by 0.05 per level; a fully-fed lvl-10 NPC reaches 0.95 vs lvl-1 0.50 |
