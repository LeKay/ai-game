# Systems Index: From Scratch

> **Status**: Draft
> **Created**: 2026-05-05
> **Last Updated**: 2026-06-13 (code↔doc sync: implementation statuses, 1440 ticks/day, Efficiency GDD)
> **Source Concept**: design/gdd/game-concept.md

---

## Overview

"From Scratch" is a 2D village builder combining Factorio-style optimization with Anno-style population tiers and a unique "manual → automated" progression. The game requires 29 interconnected systems spanning tick-based time management, NPC management with tier-based consumption, and a distance-based logistics network. The core loop (identify bottleneck → build/optimize → watch system stabilize) demands transparent, debuggable production chains (Pillar 2), earned automation through manual labor (Pillar 1), and spatial optimization over expansion (Pillar 3). This index organizes all systems by dependency order and priority tier to ensure foundation systems are designed before the features that depend on them.

---

## Systems Enumeration

| # | System Name | Category | Priority | Status | Design Doc | Depends On |
|---|-------------|----------|----------|--------|------------|------------|
| 1 | Tick System | Core | Vertical Slice | Implemented | design/gdd/tick-system.md | None |
| 2 | Resource System | Core | Vertical Slice | Implemented | design/gdd/resource-system.md | None |
| 3 | Input System | Core | Vertical Slice | Implemented | design/gdd/input-system.md | None |
| 4 | Recipe Database System | Economy | MVP | Partially Implemented (CraftingRegistry + PRODUCTION_TABLE; JSON registry pending) | design/gdd/recipe-database.md | None |
| 5 | Grid/Map System | Core | Vertical Slice | Implemented | design/gdd/grid-map-system.md | Resource System |
| 6 | Player Character System (inferred) | Core | Vertical Slice | Implemented | design/gdd/player-character-system.md | Input System, Tick System |
| 7 | Camera System (inferred) | Core | Vertical Slice | Implemented | design/gdd/camera-system.md | Input System, Grid/Map System |
| 8 | Inventory/Storage System | Economy | Vertical Slice | Implemented | design/gdd/inventory-storage-system.md | Resource System |
| 9 | Settings System (inferred) | Meta | Full Vision | Not Started | — | Input System |
| 10 | Building System | Gameplay | Vertical Slice | Implemented | design/gdd/building-system.md | Grid/Map System, Resource System, Inventory/Storage System, Recipe Database System |
| 11 | NPC System | Gameplay | Vertical Slice | Implemented | design/gdd/npc-system.md | Building System, Inventory/Storage System |
| 12 | Hunger System | Gameplay | Vertical Slice | Implemented (per-NPC nutrition model) | design/gdd/hunger-system.md | NPC System, Player Character System, Inventory/Storage System |
| 13 | Bevölkerungstier System | Progression | Core Experience | Not Started | — | NPC System, Hunger System, Inventory/Storage System |
| 14 | Logistics System | Gameplay | Core Experience | Implemented (shared-carrier model) | design/gdd/logistics-system.md | NPC System, Building System, Grid/Map System, Tick System |
| 30 | Efficiency System | Gameplay | Core Experience | Implemented | design/gdd/efficiency-system.md | NPC System, Building System, Hunger System, Logistics System |
| 31 | Experience System | Progression | Core Experience | Implemented (cosmetic — no gameplay modifier yet) | design/gdd/experience-system.md | NPC System, Logistics System |
| 15 | Perk System | Progression | Core Experience | Not Started | — | Bevölkerungstier System, Inventory/Storage System |
| 16 | Goal System | Progression | MVP | Not Started | — | NPC System, Gold Economy, Hunger System |
| 17 | Gold Economy | Economy | Core Experience | Not Started | — | Inventory/Storage System, Trading System |
| 18 | Trading System | Economy | Core Experience | Not Started | — | Inventory/Storage System, Tick System, Übermap System |
| 19 | Übermap System | Gameplay | Core Experience | Not Started | — | Grid/Map System, NPC System, Tick System |
| 20 | Save/Load System | Persistence | MVP | In Progress (stories 001–003 done; save_world_save_manager.gd) | — | ALL gameplay systems |
| 21 | Audio System (inferred) | Audio | Core Experience | Not Started | — | Building System, Input System |
| 22 | VFX/Feedback System (inferred) | UI | Core Experience | Not Started | — | Building System |
| 23 | HUD System | UI | Vertical Slice | Implemented | design/gdd/hud-system.md | Inventory/Storage System, Tick System |
| 24 | Dashboard UI (inferred) | UI | MVP | Not Started | — | Building System |
| 25 | Goal Tracking UI (inferred) | UI | MVP | Not Started | — | Goal System |
| 26 | Trading UI (inferred) | UI | Core Experience | Not Started | — | Trading System, Gold Economy |
| 27 | Settings/Pause Menu UI (inferred) | UI | MVP | Not Started | — | Settings System, Tick System, Save/Load System |
| 28 | Tutorial System (inferred) | Meta | Core Experience | Not Started | — | ALL core gameplay systems |
| 29 | Day Overview System | UI | MVP | Implemented (day_ledger.gd + DayOverviewPanel) | — | Tick System, Resource System |

---

## Categories

| Category | Description | Systems in This Project |
|----------|-------------|-------------------------|
| **Core** | Foundation systems everything depends on | Tick System, Input System, Player Character System, Camera System, Grid/Map System |
| **Gameplay** | The systems that make the game fun | Building System, NPC System, Hunger System, Logistics System, Trading System, Übermap System |
| **Progression** | How the player grows over time | Bevölkerungstier System, Perk System, Goal System |
| **Economy** | Resource creation and consumption | Resource System, Inventory/Storage System, Recipe Database System, Gold Economy |
| **Persistence** | Save state and continuity | Save/Load System, Settings System |
| **UI** | Player-facing information displays | HUD System, Dashboard UI, Day Overview System, Goal Tracking UI, Trading UI, Settings/Pause Menu UI, VFX/Feedback System |
| **Audio** | Sound and music systems | Audio System |
| **Meta** | Systems outside the core game loop | Tutorial System |

---

## Priority Tiers

| Tier | Definition | Target Milestone | Design Urgency | System Count |
|------|------------|------------------|----------------|--------------|
| **Vertical Slice** | Validate core loop ("manual → automated" feels good). Tag 4 Equilibrium. | 6-8 weeks | Design FIRST | 11 systems |
| **MVP** | Shippable prototype. 5 resources, 5 buildings, Save/Load, Goals. | After Vertical Slice | Design SECOND | 18 systems |
| **Core Experience** | Feature-complete for Early Access. Tiers 1-3, Perks, Trading, Übermap, Tutorial. | Early Access Release | Design THIRD | 28 systems |
| **Full Vision** | Polished 1.0. All nice-to-haves, meta-progression, Steam integration. | 1.0 Release | Design as needed | 29 systems |

---

## Dependency Map

Systems sorted by dependency order — design and build from top to bottom. Systems at the top are foundations; systems at the bottom are wrappers.

### Layer 1: Foundation (Zero Dependencies)

1. **Tick System** — Time is the basis for all gameplay (1440 ticks/day, variable speed)
2. **Resource System** — Resource database (pure data, no logic dependencies)
3. **Input System** — Hardware → Software bridge (mouse, keyboard, WASD)
4. **Recipe Database System** — Data definitions for production chains (pure data)

### Layer 2: Core Infrastructure (Depend on Foundation Only)

5. **Grid/Map System** — depends on: *Tick System* (for animation), *Resource System* (tiles show resources)
6. **Player Character System** — depends on: *Input System*, *Tick System* (actions cost ticks)
7. **Camera System** — depends on: *Input System* (pan/zoom), *Grid/Map System* (what to show)
8. **Inventory/Storage System** — depends on: *Resource System* (what is stored)
9. **Settings System** — depends on: *Input System* (keybindings)

### Layer 3: Gameplay Foundation (Depend on Core Infrastructure)

10. **Building System** — depends on: *Grid/Map System* (placement), *Resource System* (build costs), *Inventory/Storage System* (resource consumption)
11. **NPC System** — depends on: *Building System* (housing spawns NPCs), *Inventory/Storage System* (NPCs consume goods)

### Layer 4: Core Gameplay (Depend on Gameplay Foundation)

12. **Hunger System** — depends on: *NPC System* + *Player Character System* (who is hungry), *Inventory/Storage System* (deduct food)
13. **Logistics System** — depends on: *NPC System* (carriers), *Building System* (source/dest), *Grid/Map System* (distance), *Tick System* (transport time)
14. **Bevölkerungstier System** — depends on: *NPC System* (tiers are NPC states), *Hunger System* (consumption rates), *Inventory/Storage System* (goods requirements)

### Layer 5: Feature Gameplay (Depend on Core Gameplay)

15. **Perk System** — depends on: *Bevölkerungstier System* (tiers have perks), *Inventory/Storage System* (goods activate perks)
16. **Goal System** — depends on: *NPC System* (population goal), *Gold Economy* (wealth goal), *Hunger System* (self-sufficiency goal)
17. **Gold Economy** — depends on: *Inventory/Storage System* (store gold), *Trading System* (earn/spend gold)
18. **Trading System** — depends on: *Inventory/Storage System* (trade goods), *Tick System* (merchant intervals), *Übermap System* (caravans)
19. **Übermap System** — depends on: *Grid/Map System* (leave main map), *NPC System* (NPCs travel), *Tick System* (travel time)

### Layer 6: Persistence & Feedback (Depend on All Gameplay)

20. **Save/Load System** — depends on: **ALL Gameplay Systems** (must serialize every state)
21. **Audio System** — depends on: *Building System*, *Input System* (trigger SFX)
22. **VFX/Feedback System** — depends on: *Building System* (animations)

### Layer 7: UI Presentation (Depend on Gameplay Systems)

23. **HUD System** — depends on: *Inventory/Storage System* (show resources), *Tick System* (play/pause button)
24. **Dashboard UI** — depends on: *Building System* (status)
25. **Day Overview System** — depends on: *Tick System* (`on_day_transition` signal), *Resource System* (show daily consumption)
26. **Goal Tracking UI** — depends on: *Goal System* (show progress)
27. **Trading UI** — depends on: *Trading System* (merchant interaction), *Gold Economy* (show prices)
28. **Settings/Pause Menu UI** — depends on: *Settings System*, *Tick System* (speed control), *Save/Load System*

### Layer 8: Polish (Depend on Everything)

29. **Tutorial System** — depends on: **ALL Core Gameplay Systems** (must teach all mechanics)

---

## Recommended Design Order

Combining dependency sort and priority tier. Design these systems in this order. Each system's GDD should be completed and reviewed before starting the next, though independent systems at the same layer can be designed in parallel.

| Order | System | Priority | Layer | Agent(s) | Est. Effort |
|-------|--------|----------|-------|----------|-------------|
| 1 | Tick System | Vertical Slice | Foundation | game-designer, systems-designer | M |
| 2 | Resource System | Vertical Slice | Foundation | game-designer, economy-designer | S |
| 3 | Input System | Vertical Slice | Foundation | ux-designer, gameplay-programmer | S |
| 4 | Grid/Map System | Vertical Slice | Core Infra | game-designer, godot-specialist | M |
| 5 | Inventory/Storage System | Vertical Slice | Core Infra | game-designer, economy-designer | M |
| 6 | Player Character System | Vertical Slice | Core Infra | game-designer, gameplay-programmer | M |
| 7 | Camera System | Vertical Slice | Core Infra | ux-designer, gameplay-programmer | S |
| 8 | Building System | Vertical Slice | Gameplay Foundation | game-designer, systems-designer | L |
| 9 | NPC System | Vertical Slice | Gameplay Foundation | game-designer, ai-programmer | L |
| 10 | Hunger System | Vertical Slice | Core Gameplay | game-designer, systems-designer | M |
| 11 | HUD System | Vertical Slice | UI | ux-designer, ui-programmer | M |
| 12 | Recipe Database System | MVP | Foundation | economy-designer, systems-designer | M |
| 13 | Goal System | MVP | Feature | game-designer, systems-designer | M |
| 14 | Dashboard UI | MVP | UI | ux-designer, ui-programmer | L |
| 15 | Goal Tracking UI | MVP | UI | ux-designer, ui-programmer | S |
| 16 | Settings/Pause Menu UI | MVP | UI | ux-designer, ui-programmer | M |
| 17 | Save/Load System | MVP | Persistence | technical-director, gameplay-programmer | L |
| 18 | Day Overview System | MVP | UI | ux-designer, ui-programmer | S |
| 19 | Bevölkerungstier System | Core Experience | Core Gameplay | game-designer, economy-designer, systems-designer | L |
| 20 | Logistics System | Core Experience | Core Gameplay | game-designer, systems-designer, ai-programmer | L |
| 21 | Perk System | Core Experience | Feature | game-designer, systems-designer | M |
| 22 | Gold Economy | Core Experience | Feature | economy-designer, systems-designer | M |
| 23 | Trading System | Core Experience | Feature | game-designer, economy-designer | L |
| 24 | Übermap System | Core Experience | Feature | game-designer, level-designer | L |
| 25 | Trading UI | Core Experience | UI | ux-designer, ui-programmer | M |
| 26 | Audio System | Core Experience | Audio | audio-director, sound-designer | M |
| 27 | VFX/Feedback System | Core Experience | UI | technical-artist, ui-programmer | M |
| 28 | Tutorial System | Core Experience | Meta | ux-designer, game-designer, gameplay-programmer | L |
| 29 | Settings System | Full Vision | Meta | gameplay-programmer | S |

**Effort estimates:** S = 1 session, M = 2-3 sessions, L = 4+ sessions. A "session" is one focused design conversation producing a complete GDD.

**Note:** Save/Load System (#17) is designed last in the MVP tier because it depends on the final state of all gameplay systems.

---

## Circular Dependencies

**None found.** ✅ All systems have a clean dependency hierarchy.

---

## High-Risk Systems

Systems that are technically unproven, design-uncertain, or scope-dangerous. These should be prototyped early regardless of priority tier.

| System | Risk Type | Risk Description | Mitigation |
|--------|-----------|-----------------|------------|
| **Tick System** | Technical + Scope | 15+ systems depend on it. If tick-to-frame architecture is wrong, everything breaks. Real-time vs batch-simulated has 100x performance difference. | Prototype in Week 1 of Vertical Slice. Validate 100+ buildings can tick at 60fps before committing to architecture. |
| **Inventory/Storage System** | Technical | 20+ systems depend on it. Centralized vs distributed storage, data structure choices (HashMap vs Array), serialization format — wrong choice = refactor 20 systems later. | Design GDD with architecture options, run `/architecture-decision` to lock in approach before production. |
| **Logistics System** | Design | Distance-based transport with belt-capacity = new mechanic (not in reference games). Unclear if fun or tedious. Pathfinding performance at 50+ NPCs. | Prototype after Vertical Slice. Playtest "is optimizing NPC routes satisfying or just micromanagement?" before committing to Core Experience. |
| **Bevölkerungstier System** | Design | Tier consumption rates must be balanced — too high = frustrating, too low = trivial. Bootstrapping problem (need Tier 2 to make Kleidung efficiently, but Kleidung required for Tier 2). | Spreadsheet model first (Excel/Google Sheets), validate equilibrium math before GDD. Playtest Tier 1→2 transition extensively. |
| **Übermap System** | Scope | Rimworld-style overworld travel = pathfinding on two maps, caravan state management, travel time simulation. Scope creep risk (players want combat on overworld, resource nodes, etc.). | Define MVP Übermap scope strictly: NPC travels tile-to-tile for trade ONLY. No combat, no exploration, no random events in MVP. Defer features to Full Vision. |
| **Save/Load System** | Technical | Must serialize 28 systems' state. JSON size at 100+ buildings, 50+ NPCs? Load time hitches? Corrupted save recovery? | Design last (after all systems finalized). Use async load + loading screen. Implement auto-save + backup system. Playtest save/load extensively before MVP release. |

---

## Progress Tracker

| Metric | Count |
|--------|-------|
| **Total systems identified** | 29 |
| **Design docs complete** | 13 |
| **Design docs reviewed** | 10 |
| **Design docs approved** | 11 |
| **Vertical Slice systems designed** | 10 / 11 |
| **MVP systems designed** | 10 / 18 |
| **Core Experience systems designed** | 11 / 28 |
| **Full Vision systems designed** | 10 / 29 |

---

## Next Steps

- [x] Systems index created and approved
- [x] Tick System GDD designed (Sections A-E complete)
- [x] Resource System GDD designed (All sections complete)
- [x] Input System GDD designed and reviewed (All sections complete)
- [x] Grid/Map System GDD designed and approved
- [x] Inventory/Storage System GDD designed (All sections complete)
- [x] Hunger System GDD designed and approved
- [x] HUD System GDD designed and approved
- [ ] Vertical Slice complete — all 11 systems designed ✅ (pending gate check)
- [ ] Prototype Tick System in Week 1 (validate 100+ buildings @ 60fps)
- [ ] Run `/gate-check pre-production` to transition to MVP phase
- [ ] Design MVP systems (next: Recipe Database System)
- [ ] Run `/design-review` on each completed GDD
- [ ] Run `/review-all-gdds` when MVP systems complete
