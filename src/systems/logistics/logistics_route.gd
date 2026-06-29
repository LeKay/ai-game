## LogisticsRoute — pure data class representing a carrier assignment between two buildings.
## ADR: ADR-0011 (Logistics System — Carrier FSM and Route Architecture)
## Story: logistics-system/story-001-route-model-and-slot-validation
class_name LogisticsRoute

## Which slot type this route fills on the source or destination building.
enum RouteType {
	INPUT  = 0,  ## Fills an input slot on the destination building.
	OUTPUT = 1,  ## Fills an output slot on the source building.
}

## Route lifecycle: whether the route is running, suspended, or archived.
enum LifecycleState {
	DRAFT       = 0,
	ACTIVE      = 1,
	PAUSED      = 2,
	DEACTIVATED = 3,
}

## Carrier position in the 8-state FSM (ADR-0011 Core Rules 5).
enum CarrierState {
	IDLE                  = 0,
	TRAVEL_TO_SOURCE      = 1,
	AT_SOURCE             = 2,
	WAITING_SOURCE        = 3,
	TRAVEL_TO_DESTINATION = 4,
	AT_DESTINATION        = 5,
	WAITING_DESTINATION   = 6,
	RETURN_HOME           = 7,
}

# ---- Fields ------------------------------------------------------------------

var id: StringName
var source_building_id: StringName
var destination_building_id: StringName
var npc_id: StringName
## RouteType enum value.
var route_type: int
var active: bool
## LifecycleState enum value.
var lifecycle_state: int
## CarrierState enum value.
var carrier_state: int
## Units of resource currently held by this carrier. 0 when not in transit.
var cargo: int
## Resource type currently carried. null when cargo == 0.
var cargo_resource = null
## Ticks remaining until carrier reaches its next waypoint.
var remaining_ticks: int
## The NPC's home tile — recorded when start_route() is called. Used for RETURN_HOME distance.
var npc_home_pos: Vector2i
## Start tile of the current TRAVEL_TO_SOURCE leg.
## Home on the first trip; destination building tile on subsequent trips (carrier goes direct).
var npc_start_pos: Vector2i
## Path cost for the current TRAVEL_TO_SOURCE leg — used by NpcOverlay for position lerp.
var cached_path_cost_current_leg: float = 0.0
## Effective duration (ticks) of the current travel leg, captured at leg start AFTER the F4
## efficiency scaling. Animations use this as the denominator so the icon's progress matches
## the real (efficiency-scaled) travel time. 0 when not currently travelling.
var current_leg_total_ticks: int = 0
## Nominal (efficiency-independent) duration of the in-progress source→destination delivery leg,
## captured at pickup BEFORE F4 scaling. Used by the Experience System to grant time-based
## delivery XP (ExperienceFormulas.xp_for_duration) when the carrier unloads. 0 when not delivering.
var delivery_leg_nominal_ticks: int = 0
## Human-readable reason set by _deactivate_route() when lifecycle_state → DEACTIVATED.
var deactivation_reason: String = ""
## Item this carrier is configured to pick up from a storage source. &"" for non-storage sources.
var source_item_id: StringName = &""

## Ticks the carrier has been stuck in WAITING_DESTINATION. Reset on entry, incremented
## per tick while waiting. When it crosses WAITING_DESTINATION_RESCUE_TICKS the carrier
## dumps cargo on the map and moves on (anti-lockup, 2026-06-28).
var waiting_dest_ticks: int = 0

# ---- Observed day stats (post-hoc, reset each day) --------------------------

## Items delivered on this route during the last complete day.
var stats_items_last_day: int = 0
## Ticks this route's carrier was actively working this route (State != IDLE) last day.
var stats_active_ticks_last_day: int = 0
## True after the first day_transition has been snapshotted — UI shows "—" until then.
var stats_data_available: bool = false

# ---- Path cache (ADR-0013 Story 011) -----------------------------------------

## Ordered tile path from source building → destination building.
## Populated by LogisticsSystem.create_route() via LogisticsPathfinder.
var cached_path: Array[Vector2i] = []
## Total A* cost of source → destination (Σ entered-tile costs, excluding start tile).
var cached_path_cost: float = 0.0
## True when cached_path / cached_path_cost are valid; false until route creation pathfinds.
var path_valid: bool = false
## A* cost from NPC home → source tile; set by start_route() when home position is known.
var cached_path_cost_home_to_source: float = 0.0
## A* cost from source tile → NPC home; set by start_route(); used for WAITING_SOURCE timeout.
var cached_path_cost_source_to_home: float = 0.0
## A* cost from destination tile → NPC home; set by start_route(); used for RETURN_HOME leg.
var cached_path_cost_dest_to_home: float = 0.0
## True when the three home-leg costs above have been computed by start_route().
var home_legs_valid: bool = false
## Path for the current travel leg — populated by LogisticsSystem at each leg start.
## Non-empty enables path-following in NpcOverlay; empty falls back to linear lerp.
var current_leg_path: Array[Vector2i] = []
## Home-to-source path — cached from start_route() so RETURN_HOME completion can reuse it.
var cached_leg_path_home_to_source: Array[Vector2i] = []

# ---- Factory -----------------------------------------------------------------

## Create a new route with default initial state (ACTIVE lifecycle, IDLE carrier).
## Called by LogisticsSystem.create_route() after slot validation passes.
static func create(
		source: StringName,
		destination: StringName,
		npc: StringName,
		p_route_type: int,
		p_source_item: StringName = &"") -> LogisticsRoute:
	var route := LogisticsRoute.new()
	# Unique per route, NOT per NPC: a shared carrier can own several routes, so the id must
	# include source+destination (a carrier can have at most one route per source→dest pair).
	# (Was "route_<npc>", which collided when one NPC had multiple routes — breaking the active-
	# route map and the per-id line/icon lookups in the overlays.)
	route.id = StringName("route_%s_%s_%s_%s" % [npc, source, destination, p_source_item])
	route.source_building_id = source
	route.destination_building_id = destination
	route.npc_id = npc
	route.route_type = p_route_type
	route.source_item_id = p_source_item
	route.active = true
	route.lifecycle_state = LifecycleState.ACTIVE
	route.carrier_state = CarrierState.IDLE
	route.cargo = 0
	route.cargo_resource = null
	route.remaining_ticks = 0
	route.npc_home_pos = Vector2i.ZERO
	route.npc_start_pos = Vector2i.ZERO
	route.cached_path_cost_current_leg = 0.0
	route.current_leg_total_ticks = 0
	route.delivery_leg_nominal_ticks = 0
	route.cached_path = []
	route.cached_path_cost = 0.0
	route.path_valid = false
	route.cached_path_cost_home_to_source = 0.0
	route.cached_path_cost_source_to_home = 0.0
	route.cached_path_cost_dest_to_home = 0.0
	route.home_legs_valid = false
	route.current_leg_path = []
	route.cached_leg_path_home_to_source = []
	route.stats_items_last_day = 0
	route.stats_active_ticks_last_day = 0
	route.stats_data_available = false
	return route
