# Review Log: game-concept.md

## Review — 2026-05-04 — Verdict: NEEDS REVISION

**Scope signal:** L (Large)
**Specialists:** economy-designer, game-designer, systems-designer, ux-designer, level-designer, performance-analyst, godot-specialist, qa-lead
**Blocking items:** 10 | **Recommended:** 16 | **Nice-to-Have:** 6
**Prior verdict resolved:** First review

### Summary

This is an **exceptionally well-documented game concept** with strong vision, clear pillars, and impressive economic modeling for a first draft. The Player Fantasy ("befriedigende Transformation von manueller Arbeit zu strategischem Management") is compelling, and the economic equilibrium model (4-day automation proof) demonstrates rigorous design thinking.

**However**, **10 blocking issues** must be resolved before system GDD authoring can begin:

1. **Play/Pause contradiction** — Lines 82 and 537 directly contradict each other (time system ambiguity)
2. **Hybrid Phase is flavor text** — "Working side-by-side with NPCs" has no mechanical support
3. **Tool durability economy unsustainable** — Manual crafting every 3-4 days = 10% daily busywork forever
4. **Wohnhaus spam trap** — No prevention for building housing before food production (starvation spiral)
5. **Tier 2-3 economic model undefined** — No consumption rates, production multipliers, or luxury good thresholds
6. **Gold economy undefined** — Wohlstandsziel mentions 10,000 gold but no faucets/sinks exist
7. **Bottleneck visualization underspecified** — Pillar 2 promises transparency but 80% of UI is undefined
8. **Goals not testable** — 4 victory conditions have ambiguous criteria (QA cannot verify)
9. **Tick system architecture undefined** — Frame-locked vs batch-simulated has 100x performance difference
10. **Resource renewal model unclear** — Are trees finite, renewable, or building-spawned?

**Key tensions identified:**

- **Tick system undermines management fantasy**: Player-controlled time removes juggling tension that defines management games. If time can pause indefinitely, there's no challenge—just puzzle-solving in frozen time.
- **Manual phase too short**: 4-day automation arc (~20-30 minutes) insufficient to establish contrast. Automation only feels earned after meaningful manual tedium.
- **MDA aesthetic mismatch**: Design delivers Submission (meditative, no death) not Challenge (obstacle course). Aesthetics priority should be reordered to match.
- **Pillar 3 lacks enforcement**: "Optimization Over Expansion" is aspirational but not mechanically rewarded. Expansion always dominates without constraints (limited space, upkeep costs, efficiency bonuses).

---

## Detailed Findings by Specialist

### Economy Designer — Critical Economic Flaws

**1. Tool Durability Economy Unsustainable [BLOCKING]**
- Werkzeug (150 durability) lasts ~6 days at demonstrated consumption rate
- Every 6 days: 200 ticks gathering Faser/Stein + 100 ticks crafting = **300 ticks/6 days = 50 ticks/day overhead**
- At 10 buildings consuming tools: **15% of every day** spent on mandatory tool upkeep
- **No automation path** in Vertical Slice or MVP
- **Fix**: Add Werkstatt building to MVP, OR increase durability 3x, OR allow bare-hands gathering to scale
- Solution: Es wird nach der MVP stage eine automatisierung der werkzeuge eingebaut die das problem löst

**2. Wohnhaus Spam Trap [BLOCKING]**
- Player can build 3 Wohnhäuser (30 Holz + 9 Stein) → 6 NPCs
- 6 NPCs consume 6 Beeren/Day
- Manual berry picking: 3 Beeren per 40 Ticks → 80 Ticks/Day minimum to break even
- **Result**: Player locked into 8% daily berry-picking with 6 idle NPCs (trap state)
- **No warning UI** or prevention mechanism
- **Fix**: Gate NPC spawning behind food surplus, OR add "Idle NPC consuming food" warning, OR increase Wohnhaus costs
- Solution: Im MVP wird nur der erste NPC gespawnt, in späteren versionen soll es einen Rekrutierungsprozess geben

**3. Tier 2-3 Economic Model Undefined [BLOCKING]**
- Bevölkerungstiers mentioned but **zero formulas**:
  - Consumption rates per tier? (2 food/day? 5 food/day?)
  - Production multipliers? (2x output? 1.5x?)
  - Luxury good "verfügbar" threshold? (>0 units? >10 units? consumed daily?)
- **Circular dependency risk**: Need Kleidung to unlock perk → perk makes Kleidung production efficient → bootstrapping problem
- **Fix**: Define Tier 2-3 consumption/production formulas with bootstrapping mitigation (perks = bonus not baseline)
- Solution: Mit höherer Bevölkerungsstufe erhöht sich auch die Nahrungs consumption. Define Tier 2-3 consumption/production formulas with bootstrapping mitigation (perks = bonus not baseline)

**4. Gold Economy Undefined [BLOCKING]**
- Wohlstandsziel: 10,000 Gold (line 339)
- **No gold faucets**: How do players earn gold? Sell goods to traders?
- **No gold sinks**: What is gold spent on? Import rare resources? NPC wages?
- **No exchange rates**: 1 Holz = X Gold?
- **Fix**: Specify full gold economy loop (earn sources, spend sinks, exchange rates, inflation prevention)
- Solution: Specify full gold economy loop (earn sources, spend sinks, exchange rates, inflation prevention)

**5. Verbrauchsgüter Scaling Underspecified**
- Beerenstrauch-Garten produces 10 Beeren/Day, feeds 9 entities with 10% margin
- At 50 NPCs: 51 Beeren/Day → **6 Gärten required**
- **Missing**: Scaling table (X NPCs → Y Gärten), ideal production ratios, surplus safety margins
- **Fix**: Add scaling table to Tuning Knobs section
- Solution: Es wird mehr Warenketten als nur Beeren geben (Brot/Fleisch,etc)

**6. No Continuous Resource Sinks [RECOMMENDED]**
- Wood/stone consumed once (building construction), then accumulate infinitely
- No building maintenance, repair costs, or endgame resource dumps
- **Result**: 10,000 wood stockpiled by Day 20 with nothing to spend it on
- **Fix**: Add maintenance costs, building upgrades, NPC training costs, or prestige monuments
- Solution: Fixed via Trading, upgrades, komplizierte Warenketten

### Game Designer — Player Fantasy Delivery Issues

**7. Play/Pause Contradiction [BLOCKING]**
- Line 82: "Zeit läuft NICHT automatisch. Spieler kontrolliert Zeit via Play/Pause"
- Line 537: "NPCs arbeiten automatisch (auch bei Pause)"
- **These cannot both be true**
- **Impact**: Undermines management fantasy. Management games create tension through juggling simultaneous demands. If time pauses, there's no management—just frozen puzzle-solving.
- **Fix**: Choose one:
  - Option A: Remove player pause. Time advances at variable speed (0.5x, 1x, 2x, 3x) but never stops.
  - Option B: Clarify "pause" only freezes player actions, not NPC production (rename to avoid confusion).
  - Option C: Accept this is turn-based puzzle, not management sim. Rewrite Player Fantasy to match.
- Solution: Option C. Pause pausiert alles bis der Spieler play drückt oder durch eigene Handlungen das Spiel weitertickt

**8. Hybrid Phase is Flavor Text [BLOCKING]**
- Unique Hook (line 39): "Hybrid-Phase (du arbeitest Seite an Seite mit deinen ersten NPCs) macht den Übergang fließend"
- **Zero mechanical support**. Equilibrium proof (Day 4) shows: Player gathers berries, NPC chops wood = **parallel not collaborative**
- No "assist" actions, no training bonuses, no shared tasks
- **Fix**: Either design hybrid mechanics (player assists buildings +50% output, NPCs assist player, shared tasks) OR remove "side-by-side" language
- Solution: remove "side-by-side" language

**9. Manual Phase Too Short [RECOMMENDED]**
- 4-day equilibrium (~1800 ticks) = **20-30 real minutes** of manual labor
- **Insufficient contrast** for "befriedigende Transformation"
- Compare: Card Survival (2-3 hours manual), Factorio (30-60 min but multiple relief moments)
- **Fix**: Extend to 6-10 days (~45-90 min) OR add intermediate relief moments (Day 2: better tools, Day 5: first NPC, Day 8: automation)
- Solution: No change. Das wird in späteren Versionen hinfällig

**10. MDA Aesthetic Priority Mismatch [RECOMMENDED]**
- **Stated**: (1) Challenge, (2) Discovery
- **Delivered**: (1) Submission (meditative, no death, pause-at-will), (2) Challenge (optimization puzzles), (3) Discovery
- No death timer, no time pressure, exponential growth with no brakes
- **Fix**: Reorder aesthetics to match design, OR add Challenge mechanics (random events, NPC morale, permadeath mode option)
- Solution: Aktuell keine Änderungen aber (random events, NPC morale, permadeath mode option) werden in späteren Versionen hinzugefügt

**11. Pillar 3 Lacks Enforcement [BLOCKING]**
- Pillar 3: "Optimization Over Expansion" (line 378)
- **No mechanical incentive** for optimization over expansion
- More buildings = more production. No cost to inefficiency.
- Factorio: Belt throughput limited, pollution attracts biters. Anno: Influence points capped, island space finite.
- **This game**: No stated constraints.
- **Fix**: Add constraints (limited map tiles with specified size, NPC upkeep costs, efficiency bonuses for 80%+ utilization, building maintenance, pollution/noise penalties)
- Solution: Die Normale Karte ist begrenzt (30x30 Tiles). NPC upkeep costs sind die verbauchsgüter (Nahrung, Kleidung, etc).

**12. Pillars Falsifiability [RECOMMENDED]**
- Pillar 1 & 2: ✅ Falsifiable (can design violations)
- Pillar 3: ⚠️ Test is subjective ("belohnt dieses Feature Optimierung **mehr als** Expansion?")
- **Fix**: Make Pillar 3 test concrete: "Does this feature create a measurable cost for expansion without optimization?" (e.g., limited space forces layout planning)
- Solution: Make Pillar 3 test concrete: "Does this feature create a measurable cost for expansion without optimization?" (e.g., limited space forces layout planning)

### Systems Designer — Formula Boundary Failures

**13. Hunger Debuff Scope Ambiguity [BLOCKING]**
- Line 112: "alle Aktionen kosten +50% mehr Ticks"
- **Does this apply to NPC-operated buildings?**
- **If YES**: Tag 4 equilibrium is FALSE. Holzfällerhütte production: 100 Ticks → 150 Ticks with hunger. 5 productions × 150 = 750 Ticks (only 3 fit in 1000 Ticks) → 15 Holz not 25 Holz.
- **If NO**: Equilibrium holds, but must be documented.
- **Fix**: Specify "Hunger debuff applies ONLY to manual player actions. NPC-operated buildings unaffected."
- Solution: Auch die NPCs sind betroffen

**14. Tool Lifespan Claim Contradicts Math [RECOMMENDED]**
- Claim (line 230): "alle ~3 Tage ein neues Werkzeug craften"
- Math: 150 durability ÷ 65 consumed in 4 days = 2.31 cycles × 4 = **9.23 days lifespan**
- At continuous production (10 cycles/day): 150 ÷ 50 = **3 days** ✓
- **Discrepancy**: Equilibrium proof shows 5 cycles/day (half capacity), not 10 cycles/day
- **Fix**: Change claim to "alle ~6 Tage" OR document that full-capacity operation (10 cycles/day) is intended endgame state
- Solution: Change claim to "alle ~6 Tage"

**15. Beerenstrauch-Garten Formula [VALIDATED]**
- 5 Beeren / 500 Ticks = 10 Beeren/Day ✅ Correct
- 10 Beeren ÷ 3 consumption = 3.33x overproduction ✅ Correct
- **No degenerate outputs found**

**16. 50 NPC Scaling [VALIDATED]**
- 50 NPCs + 1 Player = 51 Beeren/Day
- Required: 6 Gärten (10 Beeren each)
- 6 NPCs as farmers = 12% workforce overhead
- **Sustainable** ✅

**17. Division by Zero Edge Cases [RECOMMENDED]**
- Werkzeug lifespan: 150 ÷ 0 consumption = **undefined**. If building never uses tools, formula breaks.
- **Mitigation**: Document constraint "All tool-based buildings must have Durability_Cost > 0"
- Production_Time > 1000 Ticks = **fractional productions/day**. Does game round down (0/day) or accumulate across days?
- **Mitigation**: Document "Production time ≤ 1000 Ticks, OR specify multi-day accumulation behavior"

**18. Wood ROI is 37.5x [RECOMMENDED]**
- Input: 2 Holz → Output: 75 Holz (via 15 tool uses × 5 wood/use)
- **Runaway exponential growth**
- **Fix**: Reduce tool output (30 wood not 75), OR increase crafting costs (5 wood not 2), OR add scaling wood sinks

### UX Designer — Information Transparency Gap

**19. Bottleneck Visualization Underspecified [BLOCKING]**
- Pillar 2 promises "debugbare Produktionsketten" (line 369)
- **80% of UI decisions unmade**:
  - How does player identify bottleneck in 10-building chain without hovering each? (No global view specified)
  - Dashboard: List view? Map overlay? Dedicated panel? (Minimal UI section doesn't specify)
  - Bottleneck highlighting: Automatic red borders? Manual investigation? (Not specified)
  - Production stats: Per-building? Global? Both? Where displayed? (Mentioned in MVP line 591, not defined)
- **Programmer cannot implement** without guessing 80% of interactions
- **Fix**: Run `/ux-design hud`, `/ux-design building-inspector`, `/ux-design dashboard`, `/ux-design production-chain-view` BEFORE implementation

**20. Hover-Dependency at Scale [RECOMMENDED]**
- Hover mentioned 7 times, but:
  - Requires mouse (limits controller/touch)
  - Requires buildings on-screen (doesn't work off-screen or large maps)
  - At 50 buildings, pan-and-hover = tedious
- **Fix**: Dashboard/summary view showing all chains at-a-glance

**21. NPC Assignment Visualization [RECOMMENDED]**
- "NPCs nicht permanent sichtbar" (line 374) but how does player know NPC is assigned?
- Icon overlay? Name label? "1/1 workers assigned"?
- Unassigned building state? Grayed? "?" icon?
- **Fix**: Define visual language for assignment states

**22. Play/Pause UI Semantics [BLOCKING — duplicate of #7]**
- Contradiction creates UX confusion. What does "Pause" button do if NPCs still work?

### Level Designer — Spatial Constraints Undefined

**23. Resource Renewal Model Unclear [BLOCKING]**
- "Ressourcen sind endlich" (line 89) but:
  - Beerenstrauch-Garten produces 5 Beeren infinitely (renewable via building)
  - Holzfällerhütte produces 5 Holz — **from where?**
- **If finite trees**: Player chops all 50 trees → no more wood → **unwinnable**
- **If building-spawned**: Why claim "Ressourcen sind endlich"? What's the constraint?
- **Fix**: Specify renewal model for each resource type (finite / renewable-regrow / building-spawned-infinite)
- Solution: Resourcen nehmen ein Tile ein. Ähnlich wie bei Anno werden dann in einem Umkreis um das Gebäude die Ressourcen benötigt damit sie verarbeitet werden (gilt nur für abbaubare Ressourcen Beeren/Holz/Stein). Diese Tiles werden nicht erschöpft. Sie müssen nur vorhanden sein. Bei Gebäuden wie Holzfällern kann der Spieler die Position des Resource tiles beeinflussen. Bei Ressourcen wie Stein nicht.

**24. Tile Budget Doesn't Exist [BLOCKING — partial]**
- **No building footprints specified**. 3×3 tiles? 5×5? Variable?
- 30×30 Vertical Slice = 900 tiles. If buildings = 5×5 + 2-tile clearance (81 tiles total), 2 buildings = 162 tiles (18% of map). Tight but workable.
- **If buildings = 7×7** + clearance: 2 buildings = 245 tiles (27% of map). Problematic.
- **Fix**: Define building footprints in architecture phase
- Solution: Für den Anfang sind alle Gebäude 1 Tile groß

**25. Spatial Optimization Factors Undefined [RECOMMENDED]**
- "Layout-Planung wichtig" (line 89) — **what makes a layout good?**
- Proximity (NPC travel time)? Logistics (warehouse placement)? Zoning (chain clustering)? Expansion planning?
- **No spatial rules = "Layout-Planung" is meaningless**
- **Fix**: Choose spatial model:
  - Option A: Abstract logistics (low micro, NPCs teleport with delay)
  - Option B: Proximity-based (medium depth, closer buildings = faster)
  - Option C: Full logistics simulation (Factorio-depth, carrying capacity/stamina/congestion)
- Solution: Die Entfernung von Gebäuden spielt eine Rolle. NPCs die als Träger für Resourcen eingesetzt werden (holz vom holzfäller zum Sägewerk tragen) brauchen pro tile entfernung mehr zeit. Der Träger kann nur eine bestimmte Menge tragen und hat eine gewisse Geschwindigkeit (belt-capacity). Diese kann durch Perks oder das bauen von straßen auf einer Tile optimiert werden.

**26. Übermap Structure Undefined [RECOMMENDED]**
- "Übermap (3-5 Tiles)" (line 620) but:
  - Adjacent tiles (Anno-style world grid) or instanced separately (menu-based)?
  - NPCs travel between tiles? Or abstract trades?
  - Tiles have different biomes/resources?
- **Massive scope difference**: Adjacent = inter-tile pathfinding/caravans. Instanced = menu system.
- **Fix**: Specify Übermap spatial model (recommend: Instanced for MVP scope control)
- Solution: Die Übermap ist wie bei Rimworld definiert. Verlassen NPCs die Karte befinden sie sich in der Überwelt instanz und reisen dort von Tile zu Tile.

### Performance Analyst — Architecture Ambiguities

**27. Tick System Architecture Undefined [BLOCKING]**
- **Frame-locked vs batch-simulated has 100x performance difference**
- Frame-locked (1 tick = 1 frame at 60fps): 100 buildings × 60 ticks/sec = 6000 function calls/sec
- Batch-simulated (player presses "Next Day" → simulate 1000 ticks instantly): 100 buildings × 1000 ticks = 100,000 checks in <1 second (freeze/hitch)
- **GDD does not specify which model**
- **Fix**: Define tick-to-frame relationship BEFORE architecture phase
- Solution: Ticks sind eine interne Berechnungsgrundlage. Wie viele Ticks pro Sekunde angezeigt werden muss variable einstellbar sein (Spielgeschwindigkeit)

**28. Target Framerate Unconfigured [BLOCKING — partial]**
- Line 39 in technical-preferences.md: "[TO BE CONFIGURED]"
- 30fps vs 60fps changes acceptable budgets by 2x
- At 60fps (16.67ms budget): 2.25ms building ticks = 13.5% (tight but acceptable)
- At 30fps (33.3ms budget): 2.25ms = 6.7% (comfortable)
- **Fix**: Set target to 60fps in technical-preferences.md
- Solution: Set target to 60fps in technical-preferences.md

**29. Physics System Likely Unused [RECOMMENDED]**
- Godot 4.6 default: Jolt physics enabled
- Top-down tile game: No projectiles (no combat), kinematic movement (not physics-based), tile collision (not physics bodies)
- **Waste**: ~0.2ms/frame + 5MB RAM
- **Fix**: Disable physics in Project Settings unless specific use case identified
- Solution: Disable physics in Project Settings unless specific use case identified

**30. Pathfinding Contradiction [BLOCKING — duplicate of #7/#19]**
- Line 464: "NPCs bewegen Ressourcen abstrakt (teleportieren mit Delay)"
- Line 440: "Godot Navigation2D Setup nötig"
- **If teleporting**: No Navigation2D needed
- **If pathfinding**: Why claim abstract?
- **Fix**: Clarify NPC movement model, remove Navigation2D if abstracted
- Solution: Die Route der NPCs soll angezeigt werden, auch wenn die NPCs nicht dargestellt werden. Wenn man es dafür braucht enablen sonst disablen

**31. Memory Budget Undefined [RECOMMENDED]**
- No ceiling set → could bloat to 1GB+ without tracking
- Estimated: 150 MB (textures 50 MB + audio 20 MB + game state 35 KB + engine 80 MB)
- **Fix**: Set ceiling to 500 MB (allows 8GB laptops), track texture memory separately
- Solution: Set ceiling to 500 MB (allows 8GB laptops), track texture memory separately

**32. Save/Load Will Hitch [RECOMMENDED]**
- 100 buildings = 70-110ms load time (4-7 frames at 60fps)
- **Visible hitch** unless async or loading screen
- **Fix**: Implement loading screen or async load
- Solution: Implement loading screen or async load

### Godot Specialist — API Mismatches

**33. TileMapLayer Architecture Underspecified [BLOCKING — partial]**
- "Grid-locked TileMapLayer architecture" mentioned but:
  - Buildings = scene tiles (new in Godot 4.6), atlas tiles (sprite-only), or separate Node2D instances?
  - Multi-tile buildings (2×3) possible?
  - Separate TileMapLayer per visual layer (terrain, buildings, decorations)?
- **Scene tiles** (4.6 feature) = cleanest for buildings with logic (production state, NPC assignment)
- **Fix**: Decide building representation strategy in architecture phase
- Solution: Decide building representation strategy in architecture phase

**34. Save/Load via "Resource-System" Incorrect [RECOMMENDED]**
- Line 468: "Godot's Resource-System + JSON-Serialisierung"
- `Resource` class is for **data definitions** (RecipeResource), **not save state**
- **Correct**: Use `JSON.stringify()` for saves, `ConfigFile` for INI-style, or `ResourceSaver` for `.tres` (but harder to debug than JSON)
- **Fix**: Clarify "Use JSON for save/load. Use Resource subclasses for data definitions only (recipes, building stats)"
- Solution: Clarify "Use JSON for save/load. Use Resource subclasses for data definitions only (recipes, building stats)"

**35. Navigation2D Over-Engineering [RECOMMENDED — duplicate of #30]**
- If NPCs abstracted (line 464), Navigation2D not needed
- **Fix**: Remove Navigation2D from tech requirements unless NPCs are visible sprites that walk

**36. Godot 4.6 Post-Cutoff Risks [ADVISORY]**
- LLM training covers Godot ~4.3 (May 2025). 4.4/4.5/4.6 introduced breaking changes:
  - FileAccess return types changed (4.4)
  - Shader texture types changed (4.4)
  - TileMapLayer scene tiles added (4.6)
- **Mitigation**: Cross-reference `/docs/engine-reference/godot/VERSION.md` before suggesting API calls
- Solution: Cross-reference `/docs/engine-reference/godot/VERSION.md` before suggesting API calls

### QA Lead — Goals Not Testable

**37. Vertical Slice Victory Condition [BLOCKING]**
- Line 552: "Erreiche Tag 4 mit 25+ Holz produziert (automatisch durch NPC)"
- **"automatisch durch NPC"** ambiguous:
  - Must NPC produce ALL 25 wood? Or just some?
  - Can player manually produce ANY wood on Day 4?
  - "produziert" = production rate or cumulative production or current inventory?
- **QA cannot verify** without designer interpretation
- **Solution rewrite**:
  ```
  Victory Condition:
  - Day 4 reached (tick >= 4000)
  - Wood in storage >= 25
  - Holzfällerhütte exists + 1 NPC assigned
  ```

**38. MVP Tier 2 Goal [BLOCKING]**
- Line 594: "Tier 2 (3 Gebäude automatisiert)"
- **"automatisiert"** undefined:
  - Building exists? Exists + NPC assigned? Assigned + produced >=1 item? Currently producing (not blocked)?
- **Solution rewrite**:
  ```
  Tier 2 Goal: 3 Buildings Automated
  - Building counts if: exists + NPC assigned
  ```

**39. MVP Tier 3 Goal [BLOCKING]**
- Line 594: "Tier 3 (5 NPCs produktiv)"
- **"produktiv"** undefined:
  - Assigned to building? Assigned + building produced >=1? Currently producing? Not suffering hunger debuff?
- **Solution rewrite**:
  ```
  Tier 3 Goal: 5 NPCs Productive
  - NPC counts if: assigned + no hunger debuff
  ```

**40. Selbstversorgungs-Ziel [BLOCKING]**
- Lines 342-343: "Alle 3 Bevölkerungstiers vollständig bedient für 10 Tage"
- **"vollständig bedient"** most ambiguous goal in document:
  - No hunger debuff? All perks active? Surplus production > consumption? All NPCs consumed required goods in last day?
- **Solution rewrite**:
  ```
  Selbstversorgungs-Ziel: 10 Consecutive Days Fully Supplied
  - Tier "vollständig bedient" if: all NPCs received required goods at day transition + zero NPCs have debuff + production >= consumption (surplus exists)
  - Victory: 10 consecutive days where ALL 3 tiers meet criteria
  - Counter resets if any tier fails on any day
  ```

**41. Missing Test Evidence Section [RECOMMENDED]**
- GDD defines victory conditions but not:
  - How tested? (Automated unit test? Manual playtest?)
  - What story type? (Logic? Integration?)
  - What evidence required before "implemented"?
- **Fix**: Add Acceptance Criteria section (currently 0/8 completeness) with test requirements per goal
- Solution:  Add Acceptance Criteria section (currently 0/8 completeness) with test requirements per goal

---

## Architectural Decisions Required Before GDD Authoring

Before writing any system GDDs (`/map-systems` → `/design-system`), the following **architectural questions** must be answered:

### Time System
1. Tick-to-frame relationship: Frame-locked (1 tick/frame), batch-simulated (1000 ticks on "Next Day"), or accelerated real-time (1 tick = 0.1s)?
2. Play/Pause semantics: Does "Pause" freeze time (NPCs stop) or freeze player input only (NPCs continue)?
3. Automated building behavior during pause: Do buildings queue production, or does production only advance when time runs?


### Economy System
4. Resource renewal model: Trees/stones finite, renewable (regrow after X days), or building-spawned (infinite)?
5. Tool automation: MVP scope or deferred to Core Experience?
6. Tier 2-3 formulas: Consumption rates, production multipliers, luxury good thresholds, perk activation conditions?
7. Gold economy loop: Earn sources (trade?), spend sinks (imports? wages?), exchange rates, inflation prevention?
8. Continuous resource sinks: Building maintenance? Repair costs? NPC training? Prestige monuments?

### Spatial System
9. Building footprints: 3×3 tiles? 5×5? Variable by building type?
10. Spatial optimization model: Abstract logistics (teleport with delay), proximity-based efficiency (closer = faster), or full simulation (carrying capacity/stamina)?
11. Übermap structure: Adjacent tiles (Anno-style) or instanced separately (menu-based)?

### NPC System
12. NPC visibility: Visible sprites that walk (requires Navigation2D) or abstracted (UI icons only)?
13. NPC spawning gates: Automatic when housing built, or gated behind food surplus?

### UI System
14. Bottleneck visualization: Automatic highlighting, dashboard view, or manual hover?
15. Production stats display: Per-building, global aggregate, or both? Where shown (HUD, dashboard, tooltip)?
16. Dashboard structure: List view, grid view, or tree view? Sorting/filtering options?

### Performance System
17. Target framerate: 60fps? 30fps? Uncapped?
18. Performance budgets: Frame time, draw calls, memory ceiling?
19. Physics: Disabled (no use case) or enabled (specify use case)?

### Godot System
20. Building representation: TileMapLayer scene tiles, atlas tiles, or separate Node2D instances?
21. Save/load format: JSON (human-readable) or binary (smaller)?

---

## Next Steps

**Immediate (BLOCKING):**
1. Answer 21 architectural questions above
2. Update `technical-preferences.md` with decisions
3. Resolve 10 blocking items (Play/Pause, Hybrid Phase, Tool economy, Wohnhaus trap, Tier formulas, Gold economy, Bottleneck UI, Testable goals, Tick architecture, Resource renewal)

**Before system GDD authoring:**
4. Run `/setup-engine` to configure Godot 4.6 settings
5. Create UX specs: `/ux-design hud`, `/ux-design building-inspector`, `/ux-design dashboard`
6. Define Tick System GDD with Godot 4.6 implementation patterns
7. Re-review with `/design-review --depth lean` (faster, no agent spawning)

**After revisions approved:**
8. Run `/map-systems` to decompose concept into systems
9. Author per-system GDDs with `/design-system [system-name]`
10. Run `/review-all-gdds` for cross-system consistency
11. Run `/create-architecture` for technical architecture document

---

## Positive Findings (What Works Well)

- **Economic equilibrium model** (lines 93-253) demonstrates rigorous math-driven design
- **Beerenstrauch-Garten formula** mathematically sound (10 Beeren/Day = correct)
- **50 NPC scaling** validated as sustainable (12% farming overhead acceptable)
- **Pillar 1 & 2** are falsifiable and well-defined
- **MDA framework analysis** shows strong design thinking (even if priority order needs adjustment)
- **Vertical Slice definition** (lines 500-567) is concrete and minimal (good scope discipline)
- **Scope tiers** clearly differentiated with explicit "NOT in X" sections
- **Risk section** (lines 450-496) demonstrates awareness of common pitfalls
- **Visual Identity Anchor** (lines 633-652) provides clear art direction philosophy
- **Bevölkerungsziel** (50 Einwohner goal) is perfectly testable as written
- **Documentation quality** far exceeds typical first-draft game concepts

---

## Creative Director Synthesis

*(This review coordinated 8 specialist perspectives. Key synthesis:)*

The **Player Fantasy** is compelling: "befriedigende Transformation von manueller Arbeit zu strategischem Management." However, the **Tick System design** fundamentally undermines this fantasy. Management games create tension through **simultaneous demands**—Anno's ships sail while you plan districts, Factorio's belts run while you build elsewhere, Rimworld's colonists work while you zone storage. If the player can pause indefinitely, there is no juggling, no management challenge—only turn-based puzzle-solving.

The **economic equilibrium model** is mathematically rigorous and demonstrates exceptional design thinking. But it has a **fatal flaw**: tool production is never automated in the first two scope tiers. This creates a **10-15% daily busywork tax** that persists forever, violating the "Earned Automation" pillar. The player automates wood, automates food, but still manually gathers fiber/stone and crafts tools every few days—an inconsistency that will frustrate players.

The **Hybrid Phase** is the game's unique selling point ("working side-by-side with NPCs"), but it's **flavor text without mechanics**. The equilibrium proof shows the player gathering berries while the NPC chops wood—that's parallel task execution, not cooperation. If this hook is critical to the game's identity, it must be mechanically realized (assist actions, training bonuses, shared tasks). If not, remove the claim to avoid overpromising.

**Pillar 3** ("Optimization Over Expansion") is aspirational but not enforced. The design rewards expansion (more buildings = more production) with no constraints. Limited map size is mentioned but never quantified. Without concrete enforcement (space scarcity, upkeep costs, efficiency bonuses), players will always expand rather than optimize.

Despite these issues, this is a **strong concept** with clear vision and impressive rigor. The blocking items are resolvable design decisions, not fundamental flaws. Once the architectural questions are answered and the blocking items addressed, this concept has excellent potential for a compelling production chain game.

**Verdict**: Revise blocking items, then re-review. The vision is sound—execution needs tightening.
