# Review Log: tick-system.md

## Review — 2026-05-09 (Revision Pass) — NEEDS REVISION (Superseded)
Scope signal: M
Specialists: (lean mode — no subagents)
Blocking items: 0 | Recommended: 2

### Prior verdict resolved: Re-review after NEEDS REVISION

All prior blocking items (B1, B2) and recommendations (R1, R2, R3) addressed in revision pass. New blocking item AC4 discovered during re-review — speed-dependent manual action cost contradicts revised Rule 4. Fixed: speed now has no effect on manual action cost (AC4 rewritten, States table corrected).

---

## Review — 2026-05-09 (First Review) — NEEDS REVISION (Superseded)

**Review mode:** lean (single-session analysis)
Scope signal: M (foundational infrastructure, 4 formulas, 8 downstream dependencies, 0 upstream)
Specialists: (lean mode — no subagents)
Blocking items: 2 | Recommended: 5

### Completeness: 10/8 sections present

All 8 required sections present plus bonus sections: States and Transitions, Visual/Audio, UI Requirements, Open Questions.

### Dependency Graph

| Declared Dependency | Status |
|---------------------|--------|
| Production System | NOT FOUND (file does not exist yet) |
| Manual Labor System | NOT FOUND (file does not exist yet) |
| Hunger System | NOT FOUND (file does not exist yet) |
| Day/Night Cycle System | NOT FOUND (file does not exist yet) |
| Logistics System | NOT FOUND (file does not exist yet) |
| HUD System | NOT FOUND (file does not exist yet) |
| Save/Load System | NOT FOUND (file does not exist yet) |
| Day Overview System | NOT FOUND (file does not exist yet) |
| Inventory/Storage System | NOT FOUND (not declared but IS a downstream consumer — see R2) |

All declared downstream dependencies are undesigned — expected for foundation system designed first.

**Missing dependency:** Inventory/Storage System subscribes to `on_ticks_advanced` for in-transit timer tracking (confirmed by Inventory GDD). Should be added to Dependencies table.

---

### Required Before Implementation

| # | Issue | Source | Severity |
|---|-------|--------|----------|
| **B1** | Formula 3 (`tick_count = tick_count mod 1000`) contradicts Rule 5 and Edge Cases which both say "reset tick_count to 0, overflow discarded" | structural | CRITICAL — implementation would differ between formula and rules. A programmer implementing Formula 3 would KEEP overflow ticks (50 remaining at t=1050), but the documented behavior DISCARDS them. |
| **B2** | `MANUAL_ACTION_FREE_SPEED` defined as a tuning knob (Rule 4, Tuning Knobs) but NO FORMULA exists for the decision. The GDD states "at 2x, manual actions are 0 tick cost" but does not define it as `cost = (speed_multiplier < MANUAL_ACTION_FREE_SPEED) ? base_cost : 0` | structural | HIGH — programmers need an explicit formula or decision rule for manual action tick cost. Currently it's stated as prose in Rule 4 but codified nowhere. |

### Recommended Revisions

| # | Issue | Source | Severity |
|---|-------|--------|----------|
| **R1** | Rule 1 pseudocode missing the `min(..., MAX_TICKS_PER_FRAME)` clamp that Formula 1 defines. Should include the clamp in the Rule 1 code to keep Rule and Formula consistent | structural | MEDIUM — causes inconsistency between prose rules and formal formulas |
| **R2** | Inventory/Storage System not listed in Dependencies table. It subscribes to `on_ticks_advanced` for in-transit timer tracking (confirmed by Inventory GDD) | cross-system | MEDIUM — missing downstream consumer |
| **R3** | Tuning Knob `MANUAL_ACTION_FREE_SPEED` has value 2.0 but `SPEED_OPTIONS` is `[0.5, 1.0, 2.0]` — the 2.0 speed is the ONLY one that reaches the threshold. If the knob changes to 1.5, the intended behavior is ambiguous (does 2x become free? does 1.0x stay non-free?). Clarify: is it `>= MANUAL_ACTION_FREE_SPEED` or `> MANUAL_ACTION_FREE_SPEED`? | tuning | MEDIUM — boundary condition ambiguity |
| **R4** | Edge Case "delta_seconds < 0.0" says treat as 0.0 but does not mention recovering from a "stuck" state. If the engine clock reverses by a large amount (debug scenario), the system silently stops and needs a speed change or manual action to unstick. Document recovery mechanism. | edge case | LOW |
| **R5** | No performance note about `on_ticks_advanced` event dispatch cost. With 10+ subscribers firing 60 times per second, event handlers must be lightweight. Recommend adding a note that subscribers should only do tick decrement in their handler, not complex logic. | implementation | LOW |

---

### Verdict: NEEDS REVISION

The B1 issue (Formula 3 vs Rule 5 contradiction on overflow handling) is the only blocking item that needs fixing before the GDD is ready for implementation. B2 (missing manual action cost formula) is important for programmer clarity but can be addressed during implementation as a minor addition. The remaining issues are recommendations that can be addressed in the revision pass or deferred.

---

## Review — 2026-05-09 (First Review) — NEEDS REVISION

**Review mode:** lean (single-session analysis)

Scope signal: M
Blocking items: 2 | Recommended: 5
