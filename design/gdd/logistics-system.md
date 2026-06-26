# Logistics System

> **Status**: Implemented — synced against `src/systems/logistics/` (2026-06-13)
> **Author**: [user + agents]
> **Last Updated**: 2026-06-13
> **Implements Pillar**: Pillar 1 (Earned Automation), Pillar 2 (Information Transparency), Pillar 3 (Optimization Over Expansion)
> **Sync note**: Reverse-synced to the implementation. Two structural changes since the
> 2026-05-19 design: (1) **shared carriers** — one NPC can serve several routes,
> switching after each delivery; (2) **tile-weighted A\* pathfinding** (ADR-0013)
> replaced raw Manhattan distance. Waiting timeouts were removed. Time values use the
> pacing anchor 1 tick ≈ 1 minute, 1440 ticks/day.

## Overview

The Logistics System is the village's supply chain — it connects buildings via NPC
carriers that physically move resources across the map. Production buildings use
carriers to deliver inputs (tools, intermediate goods) and collect outputs; storage
buildings act as sources and sinks. A building without the carriers it needs enters
BLOCKED (inputs cannot arrive); a building whose output is never collected idles with
a full output buffer.

Transport time is **path-based**: routes are pathfound with a tile-weighted A\*
(roads cost 0.5, open ground 1.0, resource tiles more; ADR-0013), and the path cost is
multiplied by `TICKS_PER_TILE` (5.0) to get the base travel time at 100% carrier
efficiency. The base time is then divided by the carrier's food-efficiency (Formula F4,
ADR-0012) — a starving carrier crawls at 20 ticks/tile, a bread-fed one moves at
5 ticks/tile. Placement, road building, and carrier feeding are all levers on the same
spatial optimization puzzle.

**Shared-carrier model (2026-06-12):** A single NPC can be the carrier for several
routes but serves **one at a time**. After each delivery it switches round-robin to its
next route that actually has work; if none has work, it waits in place and re-checks
every tick. This collapsed the old "1 NPC per route" architecture that demanded ~13
NPCs for a 4-building village (balance finding B3).

The route types:
- **OUTPUT route** (production → storage): collects finished goods from a building's output buffer.
- **INPUT route** (storage → production, or production → production): delivers a chosen resource into a building's input buffer (e.g. tools to the Lumber Camp).

Carriers are visualized as icons moving along their route lines (NpcOverlay +
RouteLines); a carrier's journey is a mechanic with a readable visual trace, not a
spectacle.

*Reference: Factorio's conveyor logic abstracted into human-scale NPC carriers; Anno's
supply chains where buildings starve without delivery.*

## Player Fantasy

**"The Village Works Because of You."**

Every carrier trip, every completed delivery, every optimized route is evidence that
the player's decisions created something that runs without them.

**The first carrier** proves delegation works. The player assigns an NPC to a
Lumber Camp → Storage route and watches the icon crawl along the route line — 10 tiles,
50 ticks each way at full efficiency. When the wood lands in storage, the loop closes:
"I built things and they work."

**The shared carrier** proves systemic thinking. One NPC serves the lumber camp's
output route AND the tool delivery route. The player watches it deliver wood, then pivot
directly to the workshop to fetch a tool — no wasted walk home. Three buildings, three
routes, one worker: the player built a *system*, and the system economizes on its own.

**The optimized route** proves spatial mastery. A road cuts the path cost in half;
feeding the carrier bread doubles its speed again. The same route that took 100 ticks
now takes 25. Both improvements are visible on the map — the route line shortens along
the road, the icon visibly speeds up.

**What it serves:** Pillar 1 (Earned Automation), Pillar 2 (Information Transparency —
routes, carrier positions and cargo are visible; every delay is debuggable), Pillar 3
(Optimization Over Expansion — distance, roads, and feeding are all throughput levers).

## Detailed Rules

**1. Route Model**

A route is an explicit connection between two buildings served by an NPC carrier
(`LogisticsRoute`, pure data):

| Field | Meaning |
|-------|---------|
| `id` | `route_<npc>_<source>_<destination>` — unique per (carrier, pair); one carrier may own several routes |
| `source_building_id` / `destination_building_id` | pickup / delivery buildings |
| `npc_id` | the carrier NPC (may appear on multiple routes — shared carrier) |
| `route_type` | INPUT (fills destination input slot) or OUTPUT (drains source output slot) |
| `source_item_id` | for storage sources: which resource to pick up (required); for production sources: optional filter |
| `active` / `lifecycle_state` | DRAFT / ACTIVE / PAUSED / DEACTIVATED |
| `carrier_state` | 8-state carrier FSM position (see Rule 5) |
| `cached_path`, `cached_path_cost`, `path_valid` | A\* path source → destination (ADR-0013) |
| `current_leg_path`, `current_leg_total_ticks` | current travel leg for overlay animation (F4-scaled duration) |

**2. Route Creation and Slot Validation**

Routes are created via the Transportation panel. Validation gates, in order:

1. Source ≠ destination.
2. **OUTPUT route:** source building must have a free output slot (`MAX_OUTPUT_SLOTS = 1`).
3. **INPUT route:** destination must have a free input slot. Max input slots = number of
   distinct input resources in its `PRODUCTION_TABLE` entry (Tool Workshop: 3, Lumber
   Camp: 1); storage/unknown buildings: 1. Inactive/paused routes still occupy their
   slot until deleted.
4. **Path gate (ADR-0013):** a viable A\* path source → destination must exist;
   otherwise creation fails with "No viable path…". The found path is cached on the
   route.

Carrier candidates are idle non-worker NPCs **plus NPCs already serving as carriers**
(`get_carrier_candidates`) — assigning an existing carrier to another route is the
shared-carrier feature, not an error.

**3. Shared-Carrier Scheduling**

The system maintains `carrier_active_route: npc_id → route_id` — the ONE route each
carrier is currently executing. All its other routes are dormant.

- **Decision point** (`_carrier_pick_next`): whenever the carrier has no cargo in hand
  (after a delivery, after arriving at an empty source, or when its active route went
  away), it picks the next of its routes **round-robin starting after the current
  route** ("switch after each delivery") that **has work**.
- **Has work** = source has cargo available AND destination has space.
- **Wait in place:** if no route has work, the carrier idles at its current tile (no
  trek home) and the scheduler re-checks every tick (`_service_carriers`).
- **Travel to source starts from the carrier's current tile** — after a delivery the
  carrier moves directly from the destination to the next route's source.
- A **busy** carrier (travelling or holding cargo) is never preempted: a newly started
  route simply joins its round-robin.

**4. Route Execution (per-trip loop of the active route)**

```
(decision point) → TRAVEL_TO_SOURCE → AT_SOURCE → pickup min(available, CARRIER_CAPACITY)
→ TRAVEL_TO_DESTINATION → AT_DESTINATION → deposit → (decision point: next route / wait in place)
```

- Pickup and deposit are instant (same tick as arrival); there are no loading ticks.
- Pickup amount = `min(available, CARRIER_CAPACITY)` with `CARRIER_CAPACITY = 2`.
- Storage sources consume `source_item_id` via InventorySystem; production sources
  drain `buffered_output` (filtered by `source_item_id` when set).
- Storage destinations deposit via `InventorySystem.try_deposit`; production
  destinations receive into `input_buffer` via `receive_input_from_world` (a delivered
  tool adds 1.0 charge — see Building System T9). Delivery is blocked while the
  destination slot is full (`is_input_full`).

**5. Carrier State Machine (8 states, `LogisticsRoute.CarrierState`)**

| State | Description | Exits |
|-------|-------------|-------|
| IDLE | No work on any of the carrier's routes — waiting **in place**; also the parked state of dormant routes | → TRAVEL_TO_SOURCE (work appears, re-checked each tick) |
| TRAVEL_TO_SOURCE | Moving to the active route's source (from current tile) | → AT_SOURCE |
| AT_SOURCE | At source, attempting pickup | → TRAVEL_TO_DESTINATION (cargo loaded) · → decision point (source empty — try other routes) |
| WAITING_SOURCE | **Legacy** — no longer entered; old saves route through the decision point | → decision point |
| TRAVEL_TO_DESTINATION | Moving along the cached route path with cargo | → AT_DESTINATION |
| AT_DESTINATION | At destination, attempting deposit | → decision point (deposited) · → WAITING_DESTINATION (destination full) |
| WAITING_DESTINATION | Holding cargo, destination full — **waits indefinitely** (switching would destroy the held cargo); deposits the moment space frees | → decision point |
| RETURN_HOME | Travelling home — only used when a route is deactivated/paused mid-loop | → TRAVEL_TO_SOURCE (route still active) · → IDLE + release (inactive) |

There are **no waiting timeouts** — they were removed because they made carriers
discard held cargo and walk pointless home-and-back legs. `carrier_waiting_timeout`
survives only as a serialized field for save-file compatibility.

On every state transition the Logistics System mirrors the carrier state into the NPC
System (`set_carrier_state`, ADR-0011 mapping). Travel-leg entry applies F4: the base
leg ticks are divided by the carrier's current efficiency, and the effective duration
is recorded in `current_leg_total_ticks` for the overlay animation.

**6. Building Status Integration**

| Condition | Effect |
|-----------|--------|
| Carrier at source/destination working | destination building set OPERATING |
| INPUT route deactivated, no other active INPUT routes | destination building set BLOCKED ("no input carrier") |
| OUTPUT route deactivated | source's output carrier slot cleared; building idles naturally when its buffer fills |
| Carrier in transit (IDLE/TRAVEL/RETURN) | building status untouched |

**7. Pathfinding and Invalidation (ADR-0013)**

- Paths are computed by `LogisticsPathfinder.find_path` over WorldGrid tile costs
  (roads 0.5 via PathSystem, terrain via resource `movement_cost`, buildings
  impassable except roads).
- Terrain changes crossing a cached path invalidate that route; terrain-type changes
  and road placement/removal invalidate **all** routes (costs may have improved).
  Recalculation is deferred to end of frame.
- If recalculation finds no path for an active route, the route is **DEACTIVATED**
  with reason "Path blocked by terrain change." — the player must fix the map and
  reactivate.

**8. Fairness and Persistence**

- Routes are processed with a rotating start offset per tick batch so no route gets
  permanent priority.
- All route state (including FSM position, cargo, leg progress and cached paths) is
  serialized. On load, each carrier's active route is reconstructed as its first
  non-IDLE route; the rest stay dormant.

### Route Lifecycle States

| State | Description | Transitions |
|-------|-------------|-------------|
| ACTIVE | Route participates in its carrier's round-robin | → PAUSED (player), → DEACTIVATED (path blocked / NPC removed), → deleted |
| PAUSED | Slot stays occupied; route leaves the round-robin. If it was the carrier's active route, the carrier freezes in place until rescheduled onto its other routes (next tick) | → ACTIVE (resume), → deleted |
| DEACTIVATED | Broken (no path, NPC removed); record preserved with a human-readable `deactivation_reason` for reassignment | → ACTIVE (player fixes + reactivates), → deleted |

**Deletion:** frees the building slot. The carrier is released home **only if it has no
other routes left**; otherwise it keeps serving its remaining routes.

## Formulas

### Formula 1: Leg Travel Time (with F4)

`leg_ticks = max(1, floor( floor(path_cost × TICKS_PER_TILE) / carrier_efficiency ))`

**Variables:**
| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `path_cost` | float | 0–∞ | A\* cost of the leg (Σ entered-tile costs; roads 0.5/tile, open ground 1.0/tile). Falls back to Manhattan distance when no grid is available. |
| `TICKS_PER_TILE` | float | 1.0–10.0 | **5.0** — base ticks per cost unit at 100% efficiency. Identical constant in LogisticsSystem, NPCSystem, BuildingRegistry. |
| `carrier_efficiency` | float | 0.25–1.0 | The carrier NPC's food-driven efficiency (Hunger System Formula 1); 1.0 fallback when unavailable. |

**Anchors:** 10-tile open path, fed carrier (1.0) → 50 ticks. Same path, unfed (0.5) →
100 ticks. Same path fully on roads (cost 5.0), fed → 25 ticks.

**Example:** Source at (3,7), destination at (8,2), no roads → path cost 10.
Base = `floor(10 × 5.0)` = 50. Unfed carrier: `floor(50 / 0.5)` = 100 ticks for the leg.

### Formula 2: Route Loop Time and Throughput

For a carrier serving a single route (steady state, no waiting):

`loop_ticks = leg(dest → source) + leg(source → dest)`
`throughput_per_day = floor(1440 / loop_ticks) × CARRIER_CAPACITY`

**Variables:** legs from Formula 1; `CARRIER_CAPACITY = 2` items/trip;
1440 ticks/day (Tick System).

**Example:** 10-tile route, fed carrier: loop = 50 + 50 = 100 ticks →
`floor(1440/100) × 2 = 28 items/day`. A Lumber Camp at full efficiency produces
`floor(1440/250) × 5 = 25 wood/day` → one fed carrier keeps pace. The same carrier
unfed (loop 200) delivers 14/day → bottleneck. Feeding the carrier IS logistics tuning.

**Shared carriers:** a carrier on n routes divides its trips between them on demand;
per-route throughput is bounded by the single-route figure and decreases with
contention. There is no closed-form formula — the scheduler is demand-driven.

### Formula 3: Route Efficiency Score (STUB)

`get_route_efficiency` currently returns a lifecycle approximation: 0.0 (inactive),
0.5 (waiting states), 1.0 (otherwise). UI interpretation: green ≥ 1.0, yellow 0.5–1.0,
red < 0.5. The full throughput-vs-production formula is future work (logistics
story 007 / TR-logistics-010).

## Edge Cases

**EC-L1: Carrier arrives at source, buffer is empty.** The carrier is empty-handed →
decision point: it serves its next route with work, or idles **in place** if none has
work, re-checking every tick. It never walks home and never times out. (Replaced the
old WAITING_SOURCE + 300-tick timeout.)

**EC-L2: Carrier arrives at destination, destination is full.** The carrier holds its
cargo in WAITING_DESTINATION **indefinitely** — switching routes now would destroy the
held cargo. The moment space frees (signal-driven, same tick), it deposits and moves to
the decision point. Cargo is never discarded.

**EC-L3: Route between identical source and destination.** Blocked at creation:
"Source and destination cannot be the same building."

**EC-L4: Source or destination demolished while en route.** The route is DEACTIVATED
with a reason; the carrier finishes via RETURN_HOME → released if it has no other
routes. The route record is preserved for reassignment.

**EC-L5: Carrier NPC removed (house demolished).** All its routes are DEACTIVATED;
record preserved; the player can assign a new NPC per route.

**EC-L6: Route deleted mid-trip.** Slot freed immediately. The carrier is released home
only if this was its last route; otherwise the scheduler reassigns it to its remaining
routes at the next service tick.

**EC-L7: No path exists at creation.** Route creation fails (path gate) — the player
sees "No viable path between X and Y. Check for blocking buildings."

**EC-L8: Terrain change blocks an active route's path.** Route is DEACTIVATED with
"Path blocked by terrain change."; the carrier returns home (or serves other routes).
Roads placed/removed anywhere invalidate all cached paths (they may now be shorter) and
trigger deferred recalculation.

**EC-L9: One carrier, several routes, only some have work.** The scheduler skips
workless routes in the round-robin; a route whose source never produces simply never
gets a visit (its building shows BLOCKED/idle states, which is the player's diagnostic
signal).

**EC-L10: Save during a travel leg.** FSM state, remaining ticks, leg path, cargo and
the carrier's active route are serialized and restored exactly; dormant routes stay
dormant after load.

## Dependencies

### Hard Dependencies

| System | Direction | Interface | Rationale |
|--------|-----------|-----------|-----------|
| NPC System | Bidirectional | `set_carrier_state()`, `get_npc_position()`, `get_npc_instance()` (efficiency for F4), `release_npc()`, `get_carrier_candidates()` | NPCs ARE carriers; NPC efficiency scales travel. |
| Building System | Reads/Writes | `get_building_tile()`, `has_output_buffer()`, `get_output_buffer_*()`, `remove_from_output()`, `receive_input_from_world()`, `is_input_full()`, `assign_output_carrier()`, `add/remove_input_carrier()`, `set_status()` | Slot bookkeeping, pickup/deposit, status integration. |
| Grid/Map + PathSystem | Reads | `LogisticsPathfinder.find_path()`, `terrain_changed`, `terrain_tile_changed`, `path_placed/removed` | Tile-weighted A\* and path invalidation (ADR-0013). |
| Tick System | Subscribes | `ticks_advanced(delta)` | All carrier timing is tick-based; 1440 ticks/day. |
| Inventory System | Reads/Writes | `get_resource_quantity()`, `try_consume()`, `try_deposit()`, `get_total_quantity()`, `get_capacity()` | Storage-side pickup/deposit and capacity checks. |
| Efficiency System | Uses | `EfficiencyFormulas.calculate_effective_travel_ticks()` (F4) | Carrier speed scales with feeding. |
| Experience System | Writes | `NPCSystem.add_pending_xp(npc_id, ExperienceFormulas.xp_for_duration(delivery_leg_nominal_ticks))` on each completed delivery | Carriers earn cosmetic, time-based XP scaled to the delivery's nominal travel time. See `design/gdd/experience-system.md`. |

### Soft Dependencies

| System | Direction | Interface | Rationale |
|--------|-----------|-----------|-----------|
| Transportation Panel (UI) | Written by | `create_route()`, `start_route()`, `delete_route()`, `pause/resume_route()`, `get_active_routes()` | Route management UI. |
| NpcOverlay / RouteLines (UI) | Reads | `get_active_route_for_npc()`, route `current_leg_path` / `current_leg_total_ticks` | Carrier icon follows its ONE active route; line per route. |
| Hunger System | Indirect | via NPC efficiency | Feeding carriers is a logistics decision. |
| Save/Load System | Bidirectional | `serialize()` / `deserialize()` | Full route + scheduler state persists. |

## Tuning Knobs

| Knob | Default | Safe Range | Effect | What breaks at extremes |
|------|---------|------------|--------|------------------------|
| `TICKS_PER_TILE` | 5.0 | 1.0–10.0 | Base ticks per path-cost unit at 100% efficiency. | 1.0 = distance negligible, placement stops mattering. 10.0 = logistics dominates everything. Must stay in sync across the three systems that define it. |
| `CARRIER_CAPACITY` | 2 | 1–5 | Items per trip. Raised from 1 (2026-06-12) so one carrier keeps pace with one producer at typical distances. Intended to become a per-carrier upgradeable stat. | 1 = carrier is the binding bottleneck everywhere. 5+ = one carrier serves the whole village, distance loses meaning. |
| `MAX_OUTPUT_SLOTS` | 1 | 1–2 | Output routes per building. | >1 needs UI for splitting output streams. |
| Input slots | per recipe | — | Derived: distinct inputs in `PRODUCTION_TABLE` (not directly tunable). | — |
| Road cost factor | 0.5 | 0.25–0.9 | PathSystem tile cost; halves travel on roads. | Too low: roads trivialize distance. Too high: roads pointless. |

Removed knobs: `loading_ticks`/`unloading_ticks` (pickup/deposit are instant),
`carrier_waiting_timeout` (timeouts removed; field kept in saves only),
`max_carriers_per_slot` (always 1; scaling now comes from capacity + shared carriers).

## Visual/Audio Requirements

**Route lines (RouteLines):** one line per route along its cached A\* path. The
carrier's currently-active route renders highlighted; dormant routes render dimmed.
DEACTIVATED routes render gray with the deactivation reason in the panel.

**Carrier icons (NpcOverlay):** carrier NPCs render as icons that follow
`current_leg_path`, animated over `current_leg_total_ticks` so the on-screen speed
matches the F4-scaled travel time (a starving carrier visibly crawls). Cargo is shown
as a small resource icon on the carrier.

**Audio:** deferred (no logistics audio implemented; keep arrival/status sounds in
mind for the audio pass).

**Colorblind accessibility:** route status uses line style in addition to color
(active = solid, dormant = dim, broken = gray/dashed).

## Acceptance Criteria

| ID | Acceptance Criterion | Verification |
|----|---------------------|--------------|
| AC-1 | Creating an OUTPUT route on a building with a free output slot succeeds; a second OUTPUT route on the same building is rejected ("no free output slots") | Automated |
| AC-2 | Creating an INPUT route to a Tool Workshop succeeds up to 3 times (3 distinct inputs); the 4th is rejected | Automated |
| AC-3 | Route creation between buildings with no viable path fails with the path error and no route is created | Automated |
| AC-4 | A fed carrier (eff 1.0) on a 10-cost path takes 50 ticks per leg; the same leg at eff 0.5 takes 100 ticks (F4) | Automated |
| AC-5 | At AT_SOURCE the carrier picks up `min(available, 2)` items and they leave the source buffer in the same tick | Automated |
| AC-6 | At AT_DESTINATION with space, cargo is deposited the same tick (storage via InventorySystem; production via input buffer, tools as +charge) | Automated |
| AC-7 | After a delivery, a carrier with two routes that both have work serves them alternately (switch after each delivery, round-robin) | Automated |
| AC-8 | A carrier whose routes all lack work idles in place (no walk home) and starts travelling within 1 tick batch of work appearing | Automated |
| AC-9 | A carrier in WAITING_DESTINATION holds its cargo indefinitely and deposits within 1 tick of space freeing; cargo is never discarded | Automated |
| AC-10 | Deleting a carrier's last route releases the NPC home; deleting one of several routes keeps the carrier serving the rest | Automated |
| AC-11 | An INPUT route deactivation with no other active INPUT routes sets the destination building BLOCKED | Automated |
| AC-12 | Placing or removing a road invalidates cached paths and routes re-path (shorter where the road helps) | Automated/Integration |
| AC-13 | A terrain change that severs an active route's only path DEACTIVATEs it with reason "Path blocked by terrain change." | Automated |
| AC-14 | Save/load mid-leg restores FSM state, remaining ticks, cargo, leg path, and the carrier's active route exactly | Automated |
| AC-15 | Route lines render along the cached path; the carrier icon follows the leg path and completes it in `current_leg_total_ticks` | Manual/Visual |

## Open Questions

1. **Per-route throughput metrics (Formula 3):** the efficiency score is still a
   lifecycle stub. Implement real measured items/day per route for the panel?
2. **Carrier capacity as upgrade:** `CARRIER_CAPACITY` is a global constant; the
   balancing intent is a per-carrier upgradeable stat (equipment?).
3. **Priority between a shared carrier's routes:** currently strict round-robin among
   routes with work. Should the player be able to mark a route "high priority"?
4. **Auto-feed for carriers:** a freshly assigned carrier runs at 0.5 efficiency until
   the first day transition feeding — consider auto-assign food UX (balance findings,
   feel note).
