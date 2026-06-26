# Story 004: Carrier Travel Integration

> **Epic**: Efficiency System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Manifest Version**: 2026-05-14

## Context

**Quick Spec**: `design/quick-specs/efficiency-system-2026-06-03.md`
**Requirement**: `TR-efficiency-004`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0012: Efficiency System — Entity Property and Formula Architecture
**ADR Decision Summary**: LogisticsSystem replaces the raw Manhattan travel tick formula with `EfficiencyFormulas.calculate_effective_travel_ticks(base_travel_ticks, carrier_npc.efficiency)`. A carrier with efficiency > 1.0 travels faster; a carrier with efficiency < 1.0 travels slower. This affects the carrier FSM's TRAVEL_TO_SOURCE and TRAVEL_TO_DESTINATION state durations. F4 must be applied at travel-start time (when ticks are computed), not recalculated per-tick.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: No post-cutoff APIs. Same `floori` / `maxi` pattern as F3.

**Control Manifest Rules (Feature Layer)**:
- Required: Travel ticks computed once at travel-start, stored as remaining_ticks counter
- Forbidden: Do not recompute travel ticks mid-transit when efficiency changes — compute at departure only

---

## Acceptance Criteria

*From Quick Spec `design/quick-specs/efficiency-system-2026-06-03.md`, scoped to this story:*

- [ ] LogisticsSystem uses `EfficiencyFormulas.calculate_effective_travel_ticks(base_travel_ticks, carrier.efficiency)` when a carrier begins TRAVEL_TO_SOURCE or TRAVEL_TO_DESTINATION
- [ ] Carrier with efficiency=1.0: travel_ticks = base (no change)
- [ ] Carrier with efficiency=1.2: travel_ticks = floor(62/1.2) = 51 (for base=62 example)
- [ ] Carrier with efficiency=0.5 (hungry): travel_ticks = floor(62/0.5) = 124 (for base=62 example)
- [ ] Carrier with efficiency=2.0: travel_ticks = floor(62/2.0) = 31 (minimum: 1 tick guaranteed)
- [ ] Effective travel ticks are computed once at departure, not recomputed if efficiency changes during transit
- [ ] efficiency=0.0 edge case: travel_ticks = INT_MAX (carrier cannot depart — LogisticsSystem treats as WAITING or does not start travel)

---

## Implementation Notes

*Derived from ADR-0012 Implementation Guidelines:*

**F4 in EfficiencyFormulas** (add to `efficiency_formulas.gd`):
```gdscript
static func calculate_effective_travel_ticks(base_ticks: int, npc_efficiency: float) -> int:
    if npc_efficiency <= 0.0:
        return 2147483647  # INT_MAX sentinel: carrier cannot travel
    return maxi(1, floori(float(base_ticks) / npc_efficiency))
```

**LogisticsSystem carrier travel change** — locate where carrier travel ticks are computed.
Current code (approximate, from ADR-0011):
```gdscript
# Formula 1 from logistics GDD:
var base_travel_ticks: int = floori(manhattan_distance * ticks_per_tile)
# BEFORE: travel_ticks = base_travel_ticks (no efficiency modifier)
carrier.remaining_travel_ticks = base_travel_ticks
```

Replace with:
```gdscript
# AFTER — route through efficiency:
var base_travel_ticks: int = floori(manhattan_distance * ticks_per_tile)
carrier.remaining_travel_ticks = EfficiencyFormulas.calculate_effective_travel_ticks(
    base_travel_ticks, carrier_npc.efficiency
)
```

**Compute-at-departure rule**: `remaining_travel_ticks` is set once when the carrier FSM transitions to TRAVEL_TO_SOURCE or TRAVEL_TO_DESTINATION. If the carrier's efficiency changes during travel (e.g., hunger triggers mid-route), the in-progress trip uses the already-computed ticks. The new efficiency takes effect on the next departure. This matches the NPC movement model (ADR-0009) which also computes travel ticks at travel-start.

**INT_MAX sentinel**: If a carrier has efficiency=0.0, LogisticsSystem should not start travel — treat as a failure to dispatch (carrier IDLE, route cannot start). This is an edge case requiring all three NPC modifiers to be 0.0 simultaneously; in practice it should never occur.

**Impact on route efficiency formulas (Story 007)**: The logistics Story 007 formula for `carrier_travel_ticks` is now `F4(base_travel_ticks, carrier.efficiency)` instead of `base_travel_ticks`. Update Story 007's implementation notes if needed.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 001]: NPC efficiency and hunger integration (carrier.efficiency must already be computed)
- [Story 003]: Production cycle integration (separate integration point)
- [Story 005]: Config values

---

## QA Test Cases

*Written by qa-lead at story creation. The developer implements against these — do not invent new test cases during implementation.*

**AC-1**: F4 — no efficiency change (base case)
  - Given: base_travel_ticks=62, carrier.efficiency=1.0
  - When: `calculate_effective_travel_ticks(62, 1.0)` is called
  - Then: Result = 62
  - Edge cases: base=1, eff=1.0 → 1; base=1000, eff=1.0 → 1000

**AC-2**: F4 — efficient carrier (faster travel)
  - Given: base_travel_ticks=62, carrier.efficiency=1.2
  - When: `calculate_effective_travel_ticks(62, 1.2)` is called
  - Then: Result = floor(62/1.2) = floor(51.67) = 51
  - Edge cases: base=62, eff=2.0 → floor(62/2.0) = 31

**AC-3**: F4 — hungry carrier (slower travel)
  - Given: base_travel_ticks=62, carrier.efficiency=0.5
  - When: `calculate_effective_travel_ticks(62, 0.5)` is called
  - Then: Result = floor(62/0.5) = 124
  - Edge cases: base=1, eff=0.5 → floor(1/0.5) = 2

**AC-4**: F4 — minimum 1 tick
  - Given: base_travel_ticks=1, carrier.efficiency=2.0
  - When: `calculate_effective_travel_ticks(1, 2.0)` is called
  - Then: Result = maxi(1, floor(0.5)) = maxi(1, 0) = 1
  - Edge cases: efficiency=100.0 (hypothetical) → still minimum 1

**AC-5**: F4 — zero efficiency sentinel
  - Given: carrier.efficiency=0.0
  - When: `calculate_effective_travel_ticks(62, 0.0)` is called
  - Then: Result = 2147483647, no division-by-zero error

**AC-6**: Integration — carrier with efficiency=1.2 reaches destination in fewer ticks
  - Given: Carrier NPC with efficiency=1.2; route with Manhattan distance producing base=60 ticks
  - When: Carrier begins travel (FSM transitions to TRAVEL_TO_SOURCE)
  - Then: remaining_travel_ticks = floor(60/1.2) = 50 (not 60)
  - Edge cases: carrier efficiency changes to 0.5 during transit → remaining_travel_ticks unchanged (mid-transit efficiency changes do not retroactively alter current trip)

**AC-7**: Integration — route throughput increases with carrier efficiency > 1.0
  - Given: Route with base round-trip 62 ticks, carrier efficiency=1.2
  - When: Route efficiency is computed (logistics Story 007 formula)
  - Then: effective round-trip = F4(62, 1.2) + F4(62, 1.2) = 51 + 51 = 102 (not 124)
  - This verifies the integration with the logistics formula chain

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/efficiency/carrier_travel_efficiency_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (carrier NPCData.efficiency must exist and be computed)
- Unlocks: Story 005 (config values)
