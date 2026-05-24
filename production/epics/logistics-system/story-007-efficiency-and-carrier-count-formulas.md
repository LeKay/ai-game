# Story 007: Efficiency and Carrier Count Formulas

> **Epic**: Logistics System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-05-14

## Context

**GDD**: `design/gdd/logistics-system.md`
**Requirement**: `TR-logistics-010`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0011: Logistics System — Carrier FSM and Route Architecture
**ADR Decision Summary**: Formula 3 (route efficiency): `(route_throughput_per_day × cycle_ticks) / (TICKS_PER_DAY × production_output)`. Value = 1.0 means perfect match. < 1.0 means route is bottleneck. > 1.0 means excess capacity. Formula 4 (carriers needed): `ceil((base_output × TICKS_PER_DAY) / (route_throughput_per_day × cycle_ticks))`. Returns ∞ when throughput = 0.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Post-cutoff APIs used: None — pure math operations. Division-by-zero guard needed for Formula 4 when route_throughput_per_day = 0.

**Control Manifest Rules (Feature Layer)**:
- Required: Production carrier transport — output buffered for carrier pickup
- Required: Carrier travel time formula — `carrier_travel_ticks = floor(distance × ticks_per_tile)`

---

## Acceptance Criteria

*From GDD `design/gdd/logistics-system.md`, scoped to this story:*

- [ ] Formula 3 (route efficiency): `(route_throughput_per_day × cycle_ticks) / (TICKS_PER_DAY × production_output)` — value = 1.0 means perfect match, < 1.0 means route is bottleneck, > 1.0 means excess capacity
- [ ] Formula 4 (carriers needed): `ceil((base_output × TICKS_PER_DAY) / (route_throughput_per_day × cycle_ticks))` — returns 1 minimum
- [ ] Formula 4 handles division by zero: when `route_throughput_per_day = 0` (round-trip exceeds TICKS_PER_DAY), returns ∞ — displayed as "Infinite carriers needed" or "Route too long for any carrier"
- [ ] UI interpretation: efficiency ≥ 1.0 → green, 0.5 ≤ efficiency < 1.0 → yellow, efficiency < 0.5 → red
- [ ] All formula variables are documented and match the GDD Tuning Knobs section

---

## Implementation Notes

*Derived from ADR-0011 Implementation Guidelines:*

**Formula 2 (throughput) — prerequisite for Formulas 3 and 4**:
```
func calculate_throughput_per_day(carrier_round_trip_ticks: float, carrier_capacity: int) -> int:
    if carrier_round_trip_ticks > TICKS_PER_DAY:
        return 0
    return floor(TICKS_PER_DAY / carrier_round_trip_ticks) * carrier_capacity
```

**Formula 3 (efficiency)**:
```
func calculate_efficiency(route_throughput_per_day: int, cycle_ticks: int,
                          base_output: int) -> float:
    var denominator = TICKS_PER_DAY * base_output
    if denominator == 0:
        return 0.0
    return (route_throughput_per_day * cycle_ticks) / (denominator as float)
```

**Formula 4 (carriers needed)**:
```
func calculate_carriers_needed(base_output: int, cycle_ticks: int,
                               route_throughput_per_day: int) -> int:
    if route_throughput_per_day == 0:
        return -1  // sentinel for infinity (display as "infinite")
    var numerator = base_output * TICKS_PER_DAY
    var denominator = route_throughput_per_day * cycle_ticks
    if denominator == 0:
        return -1  // infinity
    return ceili(numerator / (denominator as float))
```

**Divide-by-zero guard**: Formula 4's denominator is `route_throughput_per_day × cycle_ticks`. When `route_throughput_per_day = 0` (carrier never completes a trip), the result is ∞. The sentinel value -1 is used to represent infinity — the UI interprets -1 as "Infinite carriers needed." Formula 3's denominator is `TICKS_PER_DAY × base_output` — TICKS_PER_DAY is a constant (1000) so it cannot be 0, but base_output could theoretically be 0 (edge case), so a guard is included.

**Test examples from GDD**:
- Formula 2 example: round_trip = 62, capacity = 1 → throughput = floor(1000/62) × 1 = 16 items/day
- Formula 3 example: throughput = 16, cycle_ticks = 100, TPD = 1000, base_output = 5 → efficiency = (16 × 100) / (1000 × 5) = 1600 / 5000 = 0.32
- Formula 4 example: base_output = 5, cycle_ticks = 100, throughput = 16 → carriers = ceil((5 × 1000) / (16 × 100)) = ceil(5000 / 1600) = ceil(3.125) = 4

**API placement**: These are static methods on the LogisticsSystem class (or on a dedicated `LogisticsFormulas` class_name). Since they are pure math with no state dependencies, they can be unit-tested in isolation.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 002]: Carrier FSM core loop (produces the route_throughput_per_day input via travel time)
- [Story 006]: Route visualization (the UI interpretation of efficiency values is visual, but the calculation is logic)

---

## QA Test Cases

*Written by qa-lead at story creation. The developer implements against these — do not invent new test cases during implementation.*

**Formula correctness:**

- **AC-1**: Formula 2 — throughput calculation
  - Given: carrier_round_trip_ticks = 62, carrier_capacity = 1, TICKS_PER_DAY = 1000
  - When: `calculate_throughput_per_day(62, 1)` is called
  - Then: Result = floor(1000 / 62) × 1 = 16
  - Edge cases: round_trip = 1001 (> TPD) → returns 0; round_trip = 1000 (exactly TPD) → returns 1 × capacity

- **AC-2**: Formula 3 — efficiency calculation
  - Given: route_throughput_per_day = 16, cycle_ticks = 100, TICKS_PER_DAY = 1000, base_output = 5
  - When: `calculate_efficiency(16, 100, 5)` is called
  - Then: Result = (16 × 100) / (1000 × 5) = 1600 / 5000 = 0.32
  - Edge cases: efficiency ≥ 1.0 → "route has excess capacity"; efficiency = 0.5 → "yellow boundary"; efficiency = 0.0 (zero throughput) → 0.0

- **AC-3**: Formula 4 — carriers needed
  - Given: base_output = 5, cycle_ticks = 100, route_throughput_per_day = 16
  - When: `calculate_carriers_needed(5, 100, 16)` is called
  - Then: Result = ceil(5000 / 1600) = ceil(3.125) = 4
  - Edge cases: throughput = 0 → returns -1 (infinity sentinel); base_output = 1, cycle_ticks = 1, throughput = 1000 → ceil(1000 / 1000) = 1

- **AC-4**: Formula 4 — division by zero guard
  - Given: route_throughput_per_day = 0 (carrier never completes a trip)
  - When: `calculate_carriers_needed(5, 100, 0)` is called
  - Then: Result = -1 (infinity sentinel), not a crash or NaN
  - Edge cases: cycle_ticks = 0 (should never happen with valid config) → also returns -1

**UI interpretation examples:**

- **AC-5**: Efficiency thresholds match GDD specification
  - Given: efficiency values of 1.5, 1.0, 0.7, 0.5, 0.3, 0.0
  - When: UI interprets each value
  - Then: 1.5 → green (≥ 1.0), 1.0 → green (≥ 1.0), 0.7 → yellow (0.5 ≤ e < 1.0), 0.5 → yellow (0.5 ≤ e < 1.0), 0.3 → red (e < 0.5), 0.0 → red (e < 0.5)
  - Edge cases: 1.0 is the exact boundary — should be green (≥ 1.0, not > 1.0); 0.5 is the exact boundary — should be yellow (≥ 0.5, not > 0.5)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/logistics/efficiency_formulas_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 002 (route_throughput_per_day is computed from Formula 2, which depends on travel time from the carrier FSM)
- Unlocks: Story 006 (efficiency values feed into route visualization colors)
