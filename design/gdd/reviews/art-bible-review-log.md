# Art Bible Review Log

## Review — 2026-05-14 — Verdict: NEEDS REVISION
**Reviewer:** Lean single-session review (no specialist agents)
**Scope signal:** M (multi-system visual direction, large document)

### Completeness: 12/13 relevant items
- Section index (Appendix) present but page numbers are line numbers, not meaningful page references

### Dependency Graph
All 12 GDD files reviewed against art bible — no broken references. Art bible implicitly covers all systems through its cross-cutting nature.

---

### Required Before Implementation (Blocking)

1. **File corruption: Sections 8 and 9 are duplicated** — approximately 30% of the file is duplicate text. Lines 689-768 contain an orphaned Appendix + exact copy of Section 9. Lines 770-882 contain another copy of Section 8. Two orphaned subsections (4. "Environmental Storytelling" and 5. "Tile Design Requirements" at lines 884-899) have no parent section. Fix: remove the duplicate block, integrate orphaned subsections into Section 6.

2. **Appendix page numbers are line numbers** — entries like "390-702" are git line references, not pages. Either replace with clickable markdown TOC links or remove the appendix.

3. **Color temperature values inverted for "cool" states** — Exploration says "Cool 3500K" but 3500K is warm halogen. True cool blue would be 6500K+. The warm state values (Production 5500-6000K, Victory 2800-3200K, Menu 6500K→3000K) are correct. Fix the 4 "cool" entries to use 6500K+ values.

4. **Production flow lines rendering approach undecided** — Section 2.4 describes them as "particle streams" which would consume the particle budget (3-5 systems total), but a player could have 10+ chains. Must specify: `GPUParticles2D` per chain (exceeds budget) or `CanvasItem`/`Line2D` (free, batchable). This affects both art and code architecture.

5. **TileMapLayer Layer 7 misclassified** — Layer 7 "UI overlay" should be a `CanvasLayer`, not a TileMapLayer. TileMapLayers are for camera-following world geometry. Indicators, tooltips, and placement preview are `CanvasItem`/`Control` territory.

### Recommended Revisions

6. **NPC LOD1 (8x8 dot) lacks non-color backup** — Section 5.3 says color is the fastest role ID method at 8x8, but colorblind players at that resolution have no icon space. Add dot-size variation or outline color coding as a secondary cue.

7. **Godot 4.6 lossless PNG import** — Verify Godot 4.6 still supports truly lossless PNG. If defaults changed, document the correct import override.

8. **No VFX Direction section** — VFX only appears in asset budgets. Add creative direction for particle effects (bloom, flow lines, construction smoke, victory celebration).

9. **Reference direction — missing investment ratios** — Each reference (Stardew, FS19, LOTR, Kingdomino, Manuscripts) could use a "steer X% from this, Y% from that" note to prevent scope creep.

### Nice-to-Have

10. Add lighting/shadow direction subsection (contact shadows in top-down 2D).
11. Add seasonal variation note (even if MVP has none).
12. Godot import preset name in Section 8.3 for easy copy-paste implementation.

### Scope Signal

Rough scope signal: **M** (producer should verify before sprint planning)
- 9 major sections covering art direction, asset pipeline, and Godot implementation
- References 12 GDDs
- ~900 lines of highly specific, implementable guidance
- Low technical risk — pixel art is scope-friendly for solo dev

---

*This review log tracks the revision history of the Art Bible. Future re-reviews should reference blocking items from prior reviews and note whether they were addressed.*

---

## Revision — 2026-05-14 — All 5 blockers resolved

### Blocker fixes applied:

| # | Blocker | Fix |
|---|---------|-----|
| 1 | Duplicate Sections 8+9 | Deleted 216 lines of duplicate content (899 → 703 lines). Orphaned subsections integrated into Section 6. |
| 2 | Broken Appendix | Deleted entire appendix — replaced with clean structure. |
| 3 | "Cool 3500K" | Exploration → "Cool 6500K". 3500K is warm halogen. |
| 4 | Flow lines rendering | Specified CanvasItem/CanvasLayer (batched, single draw call) instead of ambiguous "particle streams". |
| 5 | TileMapLayer Layer 7 | Removed UI overlay from TileMapLayer list. Added explicit CanvasLayer note. |

### Residual items (not re-reviewed):

| # | Type | Status |
|---|-------|--------|
| 6 | NPC LOD1 no color backup | **Recommended** — not re-reviewed |
| 7 | Godot 4.6 lossless PNG | **Recommended** — not re-reviewed |
| 8 | No VFX Direction section | **Recommended** — not re-reviewed |
| 9 | Reference investment ratios | **Recommended** — not re-reviewed |
| 10-12 | Nice-to-have items | **N/A** — not re-reviewed |

**Recommendation:** Apply recommended items at leisure. Document is implementation-ready once the 5 blockers are confirmed by an art director.
