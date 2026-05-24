# NPC System — Review Log

## Review — 2026-05-12 — Verdict: NEEDS REVISION
Scope signal: M
Specialists: (none — lean review)
Blocking items: 4 | Recommended: 4
Summary: Well-designed GDD with excellent player fantasy and thorough edge cases. Critical blocker: Perk System and Hunger System dependencies reference systems not in Vertical Slice scope, blocking NPC effectiveness mechanics (Rule 6, Formula 2, AC-9, AC-12). Contradiction between proportional perk effects (67%) and food-only debuff (50%). State transition table has minor gaps.
Prior verdict resolved: No — first review

## Revision — 2026-05-12 — Status: RESOLVED

### Fixes Applied
| Blocker | Fix |
|---------|-----|
| Perk/Hunger out of VS scope | Rule 6, Formula 2, AC-9, AC-12 marked deferred to post-VS. NPCs work at 100% effectiveness. |
| EC-H5 contradiction | Clarified: building demo → held output discarded. Aligned with Building System EC-H5. |
| State transition gaps | Added `TRAVEL_TO_STORAGE → IDLE (building demolished)` transition to state table. |
| Dependencies outdated | Perk/Population Tier/Hunger System entries marked deferred in dependencies table and data flow. |
| Tuning knob stale | `npc_effectiveness_floor` noted as deferred to post-VS. |

### Remaining Recommended (non-blocking)
| # | Item |
|---|------|
| 6 | Consider adding audio cues for NPC task cycle events (travel arrival, production start) |
| 7 | OQ-3 (perk evaluation timing) resolved by deferral — can close |
| 8 | Clarify BLOCKED storage interaction with NPC cycle (minimal impact at VS) |

## Review — 2026-05-12 — Verdict: NEEDS REVISION → FIXED
Scope signal: M
Specialists: (none — lean review)
Blocking items: 3 | Recommended: 4
Summary: Re-review of revised NPC System. Formula 3 discrepancy resolved (canonical source deferred to Building System), EC-3 STALLED state ownership clarified with explicit transition trigger, Tick System GDD updated to reference NPC System instead of Logistics. All 3 open questions closed with decisions. Design is approved for implementation.
Prior verdict resolved: Yes
