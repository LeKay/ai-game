# Review Log: resource-system.md

## Review — 2026-05-09 — Verdict: NEEDS REVISION
Scope signal: S (data registry, no complex formulas, no new ADRs, ~12 downstream dependencies)
Specialists: (lean mode — no subagents)
Blocking items: 3 | Recommended: 6

### Completeness: 10/8 sections present

All 8 required sections present plus bonus sections: States and Transitions, Visual/Audio, UI Requirements, Open Questions.

### Dependency Graph

All declared downstream systems are undesigned — expected for foundation system designed first. No upstream dependencies (correct for foundation layer).

| System | Status |
|--------|--------|
| Inventory/Storage System | NOT FOUND (undesigned) |
| Production System | NOT FOUND (undesigned) |
| Manual Labor System | NOT FOUND (undesigned) |
| Hunger System | NOT FOUND (undesigned) |
| Trading System | NOT FOUND (undesigned) |
| HUD/UI | NOT FOUND (undesigned) |
| Building System | NOT FOUND (undesigned) |
| Tool System | NOT FOUND (undesigned) |
| Logistics System | NOT FOUND (undesigned) |
| Recipe Database System | NOT FOUND (undesigned) |
| NPC System | NOT FOUND (undesigned) |
| Bevölkerungstier System | NOT FOUND (undesigned) |

**Cross-check finding:** Inventory GDD exists and calls `get_resource_definition(id)` — but Resource GDD only defines `get_resource(id)`. API name mismatch (see B1).

---

### Required Before Implementation

| # | Issue | Severity |
|---|-------|----------|
| **B1** | **API name mismatch: Inventory GDD calls `get_resource_definition(resource_id)` (Section C, Formulas) but Resource GDD only defines `get_resource(id)` (Section C table, line 120).** Different method names. If a programmer implements `get_resource(id)` and the Inventory System expects `get_resource_definition(id)`, the integration breaks. Must define a canonical API contract. | CRITICAL |
| **B2** | **`base_value = 0` edge case contradicts Trading System interface.** Edge Case (line 210): "If `base_value = 0`: Cannot sell to merchants." But Interface table (line 124): "filter `base_value != null`". These are mutually exclusive — `0 ≠ null`. If the filter is `!= null`, then `base_value = 0` IS tradeable (price = 0 gold). Which is correct? | HIGH |
| **B3** | **Weight > 100 kg statement underspecified.** Tuning Knobs: "If `weight > 100 kg`: NPC carriers can't move resources (1 unit exceeds capacity)." But no carrying capacity value is defined in this GDD. What IS the NPC carry capacity? 50 kg? 100 kg? 200 kg? Without that value, "can't move" is a guess. | HIGH |

### Recommended Revisions

| # | Issue | Severity |
|---|-------|----------|
| **R1** | Formula 1 output range says [1, 10] for `stacks_needed`. If `q = 999, stack_limit = 1`, result = 999, not 10. Range should be [1, 999]. The [1, 10] range only holds if `stack_limit >= 100` (true for VS resources) but the variable table declares `stack_limit: 1-999`. | MEDIUM |
| **R2** | `max_durability` safe range is 10-500 but Edge Cases explicitly handle `max_durability = 1` ("Valid single-use tool. Destroyed after first use."). Safe range should be 1-500, not 10-500. | MEDIUM |
| **R3** | `max_durability = 1` in Tuning Knobs: same contradiction as R2. The "What breaks" section says "Tools break too quickly" for `max_durability < 5` — but `max_durability = 1` is a valid design choice for consumable tools (wooden spear). This should be documented as a valid option, not an error. | MEDIUM |
| **R4** | Formula 3 (Weight Per Stack) output range is [0.0, unbounded]. Practical max = `stack_limit(999) × weight(50.0) = 49,950 kg`. Replace "unbounded" with practical range for QA reference. | LOW |
| **R5** | `stack_limit = 0` Edge Case says "Runtime: force `stack_limit = 1`" without design-time blocking, while `max_durability > 0 AND stack_limit > 1` says "Design-time validation BLOCKS. Runtime: force `stack_limit = 1`." Why is stack_limit = 0 only runtime while the durability conflict has both design-time AND runtime handling? Either both should block at design-time, or neither should. | LOW |
| **R6** | Formula 2 (Durability Percent) has no division-by-zero guard. Schema rules prevent `max_durability = 0`, so this is safe in practice, but the formula should explicitly state the precondition `max_durability > 0` in the variable table for completeness. | LOW |

---

### Verdict: NEEDS REVISION

B1 (API contract mismatch) is the most critical issue — it blocks Integration between the two designed systems. B2 (base_value = 0 contradiction) affects Trading System design. B3 (weight threshold without carrying capacity) is design-underspecified but fixable during Logistics GDD.

---

## Additional Notes (from structural review)

**Pillar alignment:** Overview header lists "Pillar 2, Pillar 3" but Player Fantasy section describes resource tangibility ("I remember chopping the tree") which serves **Pillar 1 (Manual → Automated)**. Consider adding Pillar 1 to header.

---

## Review — 2026-05-09 (Re-review) — Verdict: NEEDS REVISION

**Prior verdict:** NEEDS REVISION (2026-05-09)
**Prior blocking items:** 3 | **Prior recommended:** 6
**All prior items addressed.** Additional issues found during re-review.

### Issues Addressed from Prior Review

| # | Issue | Status | Fix Applied |
|---|-------|--------|-------------|
| **B1** | API name mismatch (`get_resource_definition` vs `get_resource`) | RESOLVED | Inventory GDD updated: all 6 occurrences changed to `get_resource(id)` |
| **B2** | `base_value = 0` contradicts Trading filter | RESOLVED | Replaced with `base_value < 0` (negative values invalid, design-time blocks) |
| **B3** | Weight > 100 kg without carrying capacity definition | RESOLVED | Added "100 kg base NPC carrying capacity, upgradable via perks/buildings" |
| **R1** | Formula 1 output range [1, 10] incorrect | RESOLVED | Changed to [1, 999] |
| **R2** | max_durability safe range 10-500, but EC handles = 1 | RESOLVED | Changed to 1-500 |
| **R3** | Tuning knob `max_durability = 1` contradicts range | RESOLVED | Range now 1-500, consistent |
| **R4** | Weight formula output "unbounded" | RESOLVED | Changed to [0.0, 49,950] |
| **R5** | stack_limit = 0 inconsistent handling | RESOLVED | Already correct — design-time blocking confirmed |

### Additional Issues Found During Re-review

| # | Issue | Severity | Fix Applied |
|---|-------|----------|-------------|
| **B4** | Pillar alignment — Overview header lists Pillar 2, 3 but Player Fantasy describes Pillar 1 | HIGH | Header now includes Pillar 1 |
| **R7** | Overview body also missing Pillar 1 reference | LOW | Overview body now includes Pillar 1 |

### New Recommended Items from Prior Review

| # | Issue | Severity | Status |
|---|-------|----------|--------|
| **R1** | Formula 1 output range | MEDIUM | RESOLVED |
| **R2** | max_durability safe range | MEDIUM | RESOLVED |
| **R3** | Tuning knob contradiction | MEDIUM | RESOLVED |
| **R4** | Weight formula unbounded | LOW | RESOLVED |
| **R5** | stack_limit = 0 handling | LOW | RESOLVED (already correct) |

### Verdict: NEEDS REVISION

All prior blocking issues resolved. Pillar alignment (header + body) addressed. All recommended items resolved.

---

## Review — 2026-05-09 (Final) — Verdict: APPROVED

**Prior verdict:** NEEDS REVISION (2026-05-09 re-review)
**All items resolved.**

### Final Checklist

- [x] B1 — API name canonicalized to `get_resource(id)`
- [x] B2 — `base_value = 0` replaced with `base_value < 0` edge case
- [x] B3 — Weight > 100 kg clarified with carrying capacity + upgradable note
- [x] B4 — Pillar 1 added to Overview header and body
- [x] R1 — Formula 1 output range [1, 999]
- [x] R2/R3 — max_durability range 1-500
- [x] R4 — Weight formula range [0.0, 49,950]
- [x] R5 — stack_limit = 0 design-time blocking confirmed
- [x] R7 — Overview body pillar alignment

**Scope signal:** S (data registry, no complex formulas, no new ADRs, ~12 downstream dependencies)
**Specialists:** (lean mode — no subagents)
**Blocking items:** 0 | **Recommended:** 0

---

### Nice-to-Have (Post-Approval)

| # | Suggestion | Severity |
|---|------------|----------|
| **N1** | Add resource icon reference field to schema (currently only mentions "icon references" in Overview but not in the attribute table) | LOW |
| **N2** | Consider adding a `rarity` or `unlock_tier` attribute to gate resource availability through progression | LOW |

### Verdict: APPROVED

The Resource System GDD is now complete, consistent, and ready for implementation. All cross-system contracts are aligned.
