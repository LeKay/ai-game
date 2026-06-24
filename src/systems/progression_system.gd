extends Node
## ProgressionSystem — Autoload singleton.
## Single source of truth for the Progression Tree (tech tree) unlock state.
## Loads the node graph from data/progression_tree.json and tracks which nodes the
## player has unlocked. The UI is a pure renderer of this state — it never owns it.
##
## STEP 1 SCOPE (graph only): node graph + unlock state + radial layout + reveal
## queries + capability API. The capability API (is_building_unlocked etc.) is fully
## implemented but not yet called by any gameplay surface — content gating is wired in
## Step 2. Save/Load methods are ready but not yet hooked into WorldSaveManager.
##
## See design/quick-specs/progression-tree-2026-06-19.md.

const REGISTRY_PATH: String = "res://data/progression_tree.json"
const CURRENT_SCHEMA_VERSION: int = 1
const ROOT_NODE_ID: StringName = &"hearth"

## Perpendicular offset (px) between sibling nodes sharing the same branch+ring.
## Siblings are pushed sideways across the strand axis (not fanned angularly) so each
## category reads as a straight strand radiating from the center.
const SIBLING_OFFSET_PX: float = 185.0
const CORE_BRANCH: StringName = &"core"

## Emitted when a node transitions locked → unlocked. The UI re-populates on this.
signal node_unlocked(node_id: StringName)

## Emitted whenever the progression-point balance changes (unlock spend, task reward, load).
## Progression points are the "research currency" reserved by the tree design: they are
## earned by the Delivery Task System and spent here to unlock nodes. See
## design/quick-specs/delivery-task-system-2026-06-20.md.
signal points_changed(total: int)

## Emitted when the NPC level cap changes (a Leadership-branch node was unlocked). Lets NPC-facing
## UI (Day Overview, NPC detail panel) surface the "level up" affordance the moment the cap rises.
signal npc_level_cap_changed(cap: int)


# --- Config (loaded from JSON, see Tuning Knobs in the spec) ------------------

var node_cost_enabled: bool = false
## Progression points the player owns at game start (bootstraps the first unlock).
var starting_points: int = 1
var reveal_mode: String = "prereqs_met"
var branch_count: int = 4
var ring_radius: float = 190.0
var zoom_min: float = 0.5
var zoom_max: float = 2.0
var reveal_anim_duration: float = 0.4

var _branch_angles_deg: Dictionary = {}  # StringName -> float

# --- Graph state -------------------------------------------------------------

var _nodes: Dictionary = {}        # StringName -> ProgressionTreeNode (insertion order preserved)
var _unlocked: Dictionary = {}     # StringName -> true (set of unlocked node ids)

## Current progression-point balance. Spent in unlock() (when node_cost_enabled), earned via
## add_points() from completed delivery tasks. Initialised to starting_points by reset_to_initial().
var progression_points: int = 0
var _positions: Dictionary = {}    # StringName -> Vector2 (cached radial layout)

# --- Capability reverse-lookups (content -> owning node id) -------------------

var _building_node: Dictionary = {}         # int building_type -> StringName node_id
var _gather_node: Dictionary = {}           # int action_type -> StringName node_id
var _recipe_node: Dictionary = {}           # StringName recipe_id -> StringName node_id
var _building_recipe_node: Dictionary = {}  # "type:recipe" String -> StringName node_id
var _upgrade_node: Dictionary = {}          # StringName upgrade_id -> StringName node_id
var _search_nodes: Dictionary = {}          # StringName node_id -> true (gate the Search action)

## resource_id -> Array[StringName] of nodes that can produce it. Built lazily on first
## is_resource_unlocked() query (it needs the live registries + player action configs,
## which are not all available at autoload time). See _ensure_resource_map().
var _resource_nodes: Dictionary = {}
var _resource_map_built: bool = false

var _registry_version: int = 0


func _ready() -> void:
	load_from_file(REGISTRY_PATH)
	reset_to_initial()


# --- Loading -----------------------------------------------------------------

## Opens path, parses JSON, caches the node graph + config + reverse lookups.
## Returns false on file-open failure, parse error, or schema mismatch (fail-fast).
func load_from_file(path: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ProgressionSystem: Cannot open '%s'" % path)
		return false

	var json_text: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()
	var err: Error = json.parse(json_text)
	if err != OK:
		push_error("ProgressionSystem: JSON parse error at line %d: %s" % [
				json.get_error_line(), json.get_error_message()])
		return false

	var data: Variant = json.get_data()
	if not data is Dictionary:
		push_error("ProgressionSystem: Root JSON element must be an object")
		return false

	var new_version: int = int(data.get("version", 0))
	if new_version > CURRENT_SCHEMA_VERSION:
		push_error("ProgressionSystem: Data version %d exceeds game version %d" % [
				new_version, CURRENT_SCHEMA_VERSION])
		return false

	if not data.has("nodes"):
		push_error("ProgressionSystem: JSON is missing required 'nodes' key")
		return false

	_load_config(data.get("config", {}))

	if not _parse_nodes(data["nodes"]):
		return false

	_build_reverse_lookups()
	_compute_positions()
	_registry_version = new_version
	return true


func _load_config(cfg: Dictionary) -> void:
	node_cost_enabled = bool(cfg.get("node_cost_enabled", false))
	starting_points = int(cfg.get("starting_points", 1))
	reveal_mode = str(cfg.get("reveal_mode", "prereqs_met"))
	branch_count = int(cfg.get("branch_count", 4))
	ring_radius = float(cfg.get("ring_radius", 160.0))
	zoom_min = float(cfg.get("zoom_min", 0.5))
	zoom_max = float(cfg.get("zoom_max", 2.0))
	reveal_anim_duration = float(cfg.get("reveal_anim_duration", 0.4))
	_branch_angles_deg.clear()
	var angles: Variant = cfg.get("branch_angles_deg", {})
	if angles is Dictionary:
		for branch_key: Variant in angles:
			_branch_angles_deg[StringName(str(branch_key))] = float(angles[branch_key])


func _parse_nodes(entries: Variant) -> bool:
	if not entries is Array:
		push_error("ProgressionSystem: 'nodes' field must be an array")
		return false

	# Build into a local dict first; swap in only on full success (atomic load).
	var new_nodes: Dictionary = {}
	for i: int in entries.size():
		var entry: Variant = entries[i]
		if not entry is Dictionary:
			push_error("ProgressionSystem: Node at index %d is not an object" % i)
			return false
		var node: ProgressionTreeNode = _build_node(entry, i)
		if node == null:
			return false
		if new_nodes.has(node.id):
			push_error("ProgressionSystem: Duplicate node_id '%s' at index %d" % [node.id, i])
			return false
		new_nodes[node.id] = node

	# Validate prerequisite references now that every node id is known.
	for node_id: StringName in new_nodes:
		var node: ProgressionTreeNode = new_nodes[node_id]
		for prereq: StringName in node.prerequisites:
			if not new_nodes.has(prereq):
				push_error("ProgressionSystem: Node '%s' references unknown prerequisite '%s'" % [
						node_id, prereq])
				return false
		for hidden: StringName in node.hidden_prerequisites:
			if not new_nodes.has(hidden):
				push_error("ProgressionSystem: Node '%s' references unknown hidden_prerequisite '%s'" % [
						node_id, hidden])
				return false

	_nodes = new_nodes
	return true


func _build_node(entry: Dictionary, index: int) -> ProgressionTreeNode:
	var raw_id: Variant = entry.get("node_id")
	if raw_id == null or str(raw_id).is_empty():
		push_error("ProgressionSystem: Node at index %d is missing 'node_id'" % index)
		return null

	var node := ProgressionTreeNode.new()
	node.id = StringName(str(raw_id))
	node.display_name = str(entry.get("display_name", str(raw_id)))
	node.icon = str(entry.get("icon", ""))
	node.branch = StringName(str(entry.get("branch", "core")))
	node.ring = int(entry.get("ring", 0))
	node.cost = entry.get("cost", null)

	node.requires_buildings = int(entry.get("requires_buildings", 0))

	var raw_prereqs: Variant = entry.get("prerequisites", [])
	if raw_prereqs is Array:
		for p: Variant in raw_prereqs:
			node.prerequisites.append(StringName(str(p)))

	var raw_hidden: Variant = entry.get("hidden_prerequisites", [])
	if raw_hidden is Array:
		for h: Variant in raw_hidden:
			node.hidden_prerequisites.append(StringName(str(h)))

	var raw_unlocks: Variant = entry.get("unlocks", [])
	if raw_unlocks is Array:
		for u: Variant in raw_unlocks:
			if u is Dictionary and u.has("type") and u.has("id"):
				node.unlocks.append({"type": str(u["type"]), "id": str(u["id"])})

	return node


## Builds the content→node reverse maps from every node's unlocks[] array, resolving
## enum-name strings to their integer values via the owning registries. Done once at
## load so capability queries are O(1) and callers never hardcode node ids.
func _build_reverse_lookups() -> void:
	_building_node.clear()
	_gather_node.clear()
	_recipe_node.clear()
	_building_recipe_node.clear()
	_upgrade_node.clear()
	_search_nodes.clear()
	# The resource map depends on these lookups, so invalidate it on every rebuild.
	_resource_nodes.clear()
	_resource_map_built = false

	for node_id: StringName in _nodes:
		var node: ProgressionTreeNode = _nodes[node_id]
		for unlock: Dictionary in node.unlocks:
			match unlock["type"]:
				"building":
					var bt: int = _building_type_from_name(unlock["id"])
					if bt >= 0:
						_building_node[bt] = node_id
				"gather":
					var at: int = _action_type_from_name(unlock["id"])
					if at >= 0:
						_gather_node[at] = node_id
				"manual_recipe":
					_recipe_node[StringName(unlock["id"])] = node_id
				"building_recipe":
					# id format "BUILDING_TYPE_NAME:recipe_id"
					var parts: PackedStringArray = unlock["id"].split(":", false, 1)
					if parts.size() == 2:
						var bt2: int = _building_type_from_name(parts[0])
						if bt2 >= 0:
							_building_recipe_node["%d:%s" % [bt2, parts[1]]] = node_id
				"upgrade":
					_upgrade_node[StringName(unlock["id"])] = node_id
				"search":
					_search_nodes[node_id] = true


## Resolves a BuildingType enum name to its int value, or -1 if unknown.
func _building_type_from_name(name: String) -> int:
	if BuildingRegistry.BuildingType.has(name):
		return int(BuildingRegistry.BuildingType[name])
	push_warning("ProgressionSystem: unknown BuildingType '%s' in progression data" % name)
	return -1


## Resolves a PlayerCharacter.ManualActionType enum name to its int value, or -1.
func _action_type_from_name(name: String) -> int:
	if PlayerCharacter.ManualActionType.has(name):
		return int(PlayerCharacter.ManualActionType[name])
	push_warning("ProgressionSystem: unknown ManualActionType '%s' in progression data" % name)
	return -1


# --- Radial layout -----------------------------------------------------------

## Precomputes the deterministic radial position of every node.
##
## The visual ring is the length of the longest same-branch prerequisite chain (see
## _compute_visual_rings), so a drawn edge always spans exactly one ring and never passes
## through an intervening node. Within a ring, each node's perpendicular offset is centered
## on its same-branch parents' offsets and only pushed sideways far enough to clear its
## neighbors — so children sit under their parents and strand edges do not cross.
func _compute_positions() -> void:
	_positions.clear()
	var rings: Dictionary = _compute_visual_rings()
	var offsets: Dictionary = {}  # StringName -> float (perpendicular distance from strand axis)

	var max_ring: int = 0
	for node_id: StringName in _nodes:
		max_ring = maxi(max_ring, int(rings[node_id]))

	# Assign offsets ring by ring outward so every node's parents are already placed.
	for r: int in range(max_ring + 1):
		var by_branch: Dictionary = {}  # StringName branch -> Array[StringName]
		for node_id: StringName in _nodes:
			if int(rings[node_id]) != r:
				continue
			var b: StringName = _nodes[node_id].branch
			if not by_branch.has(b):
				by_branch[b] = [] as Array[StringName]
			by_branch[b].append(node_id)
		for b: StringName in by_branch:
			_assign_ring_offsets(by_branch[b], r, offsets)

	for node_id: StringName in _nodes:
		var node: ProgressionTreeNode = _nodes[node_id]
		var ring: int = int(rings[node_id])
		if ring <= 0:
			_positions[node_id] = Vector2.ZERO  # the Hearth sits at the center
			continue
		var dir: Vector2 = Vector2.from_angle(deg_to_rad(float(_branch_angles_deg.get(node.branch, 0.0))))
		_positions[node_id] = dir * (float(ring) * ring_radius) + dir.orthogonal() * float(offsets[node_id])


## Assigns the perpendicular offset of every node in one (branch, ring) group. Each node
## targets the mean offset of its same-branch parents (0 if it has none), nodes are ordered
## by that target, then separated to at least SIBLING_OFFSET_PX apart and re-centered on the
## group's target mean — keeping subtrees under their parents without overlap.
func _assign_ring_offsets(node_ids: Array, ring: int, offsets: Dictionary) -> void:
	if ring == 0:
		for id: StringName in node_ids:
			offsets[id] = 0.0
		return

	var desired: Dictionary = {}  # StringName -> float
	for id: StringName in node_ids:
		var node: ProgressionTreeNode = _nodes[id]
		var sum: float = 0.0
		var count: int = 0
		for prereq: StringName in node.prerequisites:
			var parent: ProgressionTreeNode = _nodes.get(prereq, null)
			if parent != null and parent.branch == node.branch and offsets.has(prereq):
				sum += float(offsets[prereq])
				count += 1
		desired[id] = (sum / float(count)) if count > 0 else 0.0

	var sorted_ids: Array = node_ids.duplicate()
	sorted_ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		if not is_equal_approx(float(desired[a]), float(desired[b])):
			return float(desired[a]) < float(desired[b])
		return node_ids.find(a) < node_ids.find(b))  # stable tiebreak

	# Spread out: keep each node at its target unless that would crowd the previous one.
	var has_prev: bool = false
	var prev: float = 0.0
	for id: StringName in sorted_ids:
		var o: float = float(desired[id])
		if has_prev:
			o = maxf(o, prev + SIBLING_OFFSET_PX)
		offsets[id] = o
		prev = o
		has_prev = true

	# Re-center the spread group on the mean of the targets so it stays under its parents.
	var assigned_sum: float = 0.0
	var desired_sum: float = 0.0
	for id: StringName in sorted_ids:
		assigned_sum += float(offsets[id])
		desired_sum += float(desired[id])
	var shift: float = (desired_sum - assigned_sum) / float(sorted_ids.size())
	for id: StringName in sorted_ids:
		offsets[id] = float(offsets[id]) + shift


## Computes each node's visual ring: 0 for the central Hearth, otherwise one past the
## deepest same-branch prerequisite. Nodes whose every prerequisite is cross-category
## (drawn as Hearth connectors, not strand links) sit at ring 1 next to the center.
func _compute_visual_rings() -> Dictionary:
	var rings: Dictionary = {}
	for node_id: StringName in _nodes:
		_visual_ring_of(node_id, rings, {})
	return rings


func _visual_ring_of(node_id: StringName, rings: Dictionary, visiting: Dictionary) -> int:
	if rings.has(node_id):
		return int(rings[node_id])
	var node: ProgressionTreeNode = _nodes[node_id]
	if node.branch == CORE_BRANCH and node.prerequisites.is_empty():
		rings[node_id] = 0
		return 0
	if visiting.has(node_id):
		return 1  # cycle guard — should never happen with validated data
	visiting[node_id] = true

	var deepest_same_branch: int = -1
	for prereq: StringName in node.prerequisites:
		var parent: ProgressionTreeNode = _nodes.get(prereq, null)
		if parent != null and parent.branch == node.branch:
			deepest_same_branch = maxi(deepest_same_branch, _visual_ring_of(prereq, rings, visiting))
	visiting.erase(node_id)

	var ring: int = (deepest_same_branch + 1) if deepest_same_branch >= 0 else 1
	rings[node_id] = ring
	return ring


## Returns the deterministic world position of a node (center-relative). Vector2.ZERO
## for unknown ids.
func get_node_position(node_id: StringName) -> Vector2:
	return _positions.get(node_id, Vector2.ZERO)


# --- Graph queries -----------------------------------------------------------

func has_progression_node(node_id: StringName) -> bool:
	return _nodes.has(node_id)


func get_progression_node(node_id: StringName) -> ProgressionTreeNode:
	return _nodes.get(node_id, null)


## All node ids in JSON insertion order.
func get_all_node_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for node_id: StringName in _nodes:
		result.append(node_id)
	return result


## All prerequisite→node edges, for the visual layer to draw. Each entry: {from, to}.
func get_edges() -> Array[Dictionary]:
	var edges: Array[Dictionary] = []
	for node_id: StringName in _nodes:
		var node: ProgressionTreeNode = _nodes[node_id]
		for prereq: StringName in node.prerequisites:
			edges.append({"from": prereq, "to": node_id})
	return edges


func is_unlocked(node_id: StringName) -> bool:
	return _unlocked.has(node_id)


## True when every prerequisite (visible AND hidden) is unlocked, any building-count gate is
## satisfied, and the node itself is not yet unlocked. Hidden prerequisites gate reveal/unlock
## exactly like visible ones but are not drawn — see ProgressionTreeNode.hidden_prerequisites.
func is_available(node_id: StringName) -> bool:
	var node: ProgressionTreeNode = _nodes.get(node_id, null)
	if node == null or is_unlocked(node_id):
		return false
	for prereq: StringName in node.prerequisites:
		if not is_unlocked(prereq):
			return false
	for hidden: StringName in node.hidden_prerequisites:
		if not is_unlocked(hidden):
			return false
	if node.requires_buildings > 0 and get_unlocked_building_count() < node.requires_buildings:
		return false
	return true


## Number of distinct buildings the player has unlocked (a building is unlocked once the node that
## grants it is unlocked). Drives the Leadership branch's `requires_buildings` gate. Note: the
## Hearth's COLLECTION_POINT counts, so the colony starts at 1 — tune the JSON thresholds with that
## in mind.
func get_unlocked_building_count() -> int:
	var count: int = 0
	for building_type: int in _building_node:
		if is_unlocked(_building_node[building_type]):
			count += 1
	return count


## Highest NPC level the player has unlocked via the Leadership branch. Base 1 (no node unlocked =
## NPCs cannot level past 1); each unlocked `npc_level_cap` node raises it. Clamped to MAX_LEVEL.
func get_npc_level_cap() -> int:
	var cap: int = 1
	for node_id: StringName in _nodes:
		if not is_unlocked(node_id):
			continue
		for unlock: Dictionary in _nodes[node_id].unlocks:
			if unlock["type"] == "npc_level_cap":
				cap = maxi(cap, int(unlock["id"]))
	return mini(cap, ExperienceFormulas.MAX_LEVEL)


## Whether a node should currently be shown, per reveal_mode:
##   prereqs_met — unlocked or available (the dynamic "tree grows" reveal)
##   all_visible — every node always shown (greyed when locked)
##   adjacent    — unlocked, available, or one prerequisite away
func is_visible(node_id: StringName) -> bool:
	if not _nodes.has(node_id):
		return false
	match reveal_mode:
		"all_visible":
			return true
		"adjacent":
			return is_unlocked(node_id) or is_available(node_id) or _is_one_ahead(node_id)
		_:
			return is_unlocked(node_id) or is_available(node_id)


## True when at least one prerequisite of node_id is available (i.e. the node is one
## unlock beyond the current frontier). Used by the "adjacent" reveal mode.
func _is_one_ahead(node_id: StringName) -> bool:
	var node: ProgressionTreeNode = _nodes.get(node_id, null)
	if node == null:
		return false
	for prereq: StringName in node.prerequisites:
		if is_available(prereq):
			return true
	return false


## Progression-point cost to unlock node_id. Reads the node's data-driven `cost`
## (null/absent = 1). Used by can_afford() and spent in unlock() when node_cost_enabled.
func get_node_cost(node_id: StringName) -> int:
	var node: ProgressionTreeNode = _nodes.get(node_id, null)
	if node == null or node.cost == null:
		return 1
	return maxi(0, int(node.cost))


## True when the player can pay node_id's unlock cost. Always true when costs are disabled.
func can_afford(node_id: StringName) -> bool:
	if DebugSettings.ignore_costs:
		return true
	if not node_cost_enabled:
		return true
	return progression_points >= get_node_cost(node_id)


## Adds (or, if negative, removes) progression points and notifies listeners. Clamped at 0.
## Called by the Delivery Task System when a task is completed.
func add_points(amount: int) -> void:
	if amount == 0:
		return
	progression_points = maxi(0, progression_points + amount)
	points_changed.emit(progression_points)


## Unlocks an available node permanently and emits node_unlocked. Returns false if the node
## is unknown, already unlocked, its prerequisites are not all met, or (when node_cost_enabled)
## the player cannot afford its progression-point cost. On success the cost is deducted.
func unlock(node_id: StringName) -> bool:
	if not is_available(node_id):
		return false
	if not can_afford(node_id):
		return false
	if node_cost_enabled and not DebugSettings.ignore_costs:
		progression_points = maxi(0, progression_points - get_node_cost(node_id))
		points_changed.emit(progression_points)
	_unlocked[node_id] = true
	node_unlocked.emit(node_id)
	if _grants_npc_level_cap(node_id):
		npc_level_cap_changed.emit(get_npc_level_cap())
	return true


## True if the node has at least one `npc_level_cap` unlock (i.e. unlocking it raises the cap).
func _grants_npc_level_cap(node_id: StringName) -> bool:
	var node: ProgressionTreeNode = _nodes.get(node_id, null)
	if node == null:
		return false
	for unlock: Dictionary in node.unlocks:
		if unlock["type"] == "npc_level_cap":
			return true
	return false


# --- Capability API (content → unlock state) ---------------------------------
# Implemented now; consumed by gameplay gating surfaces in Step 2.

## True if the node that unlocks this building type is unlocked. Unknown types (never
## gated by any node) default to unlocked so non-tree content is never blocked.
func is_building_unlocked(building_type: int) -> bool:
	if DebugSettings.unlock_all_progression:
		return true
	if not _building_node.has(building_type):
		return true
	return is_unlocked(_building_node[building_type])


## True if the manual hand-craft recipe is unlocked. Unknown recipes default to unlocked.
func is_recipe_unlocked(recipe_id: StringName) -> bool:
	if DebugSettings.unlock_all_progression:
		return true
	if not _recipe_node.has(recipe_id):
		return true
	return is_unlocked(_recipe_node[recipe_id])


## True if a specific recipe inside a building is unlocked. Unknown pairs default to unlocked.
func is_building_recipe_unlocked(building_type: int, recipe_id: StringName) -> bool:
	if DebugSettings.unlock_all_progression:
		return true
	var key: String = "%d:%s" % [building_type, recipe_id]
	if not _building_recipe_node.has(key):
		return true
	return is_unlocked(_building_recipe_node[key])


## True if the manual gather/forage action is unlocked. Unknown actions default to unlocked.
func is_gather_unlocked(action_type: int) -> bool:
	if DebugSettings.unlock_all_progression:
		return true
	if not _gather_node.has(action_type):
		return true
	return is_unlocked(_gather_node[action_type])


## True if the named building upgrade (e.g. &"crafting_bench") is unlocked. Unknown
## upgrades default to unlocked so non-gated upgrades are never blocked.
func is_upgrade_unlocked(upgrade_id: StringName) -> bool:
	if DebugSettings.unlock_all_progression:
		return true
	if not _upgrade_node.has(upgrade_id):
		return true
	return is_unlocked(_upgrade_node[upgrade_id])


## True if the world-tile Search action is unlocked. When no node gates Search it defaults
## to unlocked; otherwise any one unlocked gating node suffices.
func is_search_unlocked() -> bool:
	if DebugSettings.unlock_all_progression:
		return true
	if _search_nodes.is_empty():
		return true
	for node_id: StringName in _search_nodes:
		if is_unlocked(node_id):
			return true
	return false


## True if the resource can currently be produced by at least one unlocked node. A
## resource gated by no node (e.g. forage-only loot) defaults to unlocked. Used to hide
## not-yet-obtainable resources from menus such as the storage delivery-limits view.
func is_resource_unlocked(resource_id: StringName) -> bool:
	if DebugSettings.unlock_all_progression:
		return true
	_ensure_resource_map()
	if not _resource_nodes.has(resource_id):
		return true
	for node_id: StringName in _resource_nodes[resource_id]:
		if is_unlocked(node_id):
			return true
	return false


## Lazily builds resource_id -> [producing node ids] from every node's unlocks, resolving
## each unlock to the resource(s) it yields via the live registries + player action config.
## Built on first query because those sources are not all ready at autoload time.
func _ensure_resource_map() -> void:
	if _resource_map_built:
		return
	var player: PlayerCharacter = null
	if is_inside_tree():
		player = get_tree().get_first_node_in_group(&"player_character") as PlayerCharacter
	for node_id: StringName in _nodes:
		var node: ProgressionTreeNode = _nodes[node_id]
		for unlock: Dictionary in node.unlocks:
			for res: StringName in _resources_for_unlock(unlock, player):
				if not _resource_nodes.has(res):
					_resource_nodes[res] = [] as Array[StringName]
				if not _resource_nodes[res].has(node_id):
					_resource_nodes[res].append(node_id)
	# Only cache once the player (gather outputs) was available; otherwise rebuild later.
	if player != null:
		_resource_map_built = true


## Resolves a single unlock entry to the resource ids it makes obtainable. Tools/items are
## resources too (axe, spindle, cloth …), so manual/building recipes contribute their output.
func _resources_for_unlock(unlock: Dictionary, player: PlayerCharacter) -> Array[StringName]:
	var out: Array[StringName] = []
	match unlock["type"]:
		"gather":
			if player != null:
				var at: int = _action_type_from_name(unlock["id"])
				if at >= 0:
					var res: StringName = player.get_action_output_resource(at)
					if res != &"":
						out.append(res)
		"manual_recipe":
			var recipe_out: Dictionary = CraftingRegistry.RECIPE_OUTPUT.get(StringName(unlock["id"]), {})
			var rid: StringName = recipe_out.get(&"resource_id", &"")
			if rid != &"":
				out.append(rid)
		"building":
			var bt: int = _building_type_from_name(unlock["id"])
			if bt >= 0:
				for recipe: Dictionary in BuildingRegistry.RECIPES.get(bt, []):
					for res_key: StringName in recipe.get("output", {}):
						if not out.has(res_key):
							out.append(res_key)
		"building_recipe":
			var parts: PackedStringArray = unlock["id"].split(":", false, 1)
			if parts.size() == 2:
				var bt2: int = _building_type_from_name(parts[0])
				if bt2 >= 0:
					for recipe: Dictionary in BuildingRegistry.RECIPES.get(bt2, []):
						if str(recipe.get("id", "")) == parts[1]:
							for res_key: StringName in recipe.get("output", {}):
								if not out.has(res_key):
									out.append(res_key)
	return out


# --- Tooltip / descriptions --------------------------------------------------

## Human-readable, multi-line summary of everything a node unlocks, for its tooltip.
## Data-driven from the node's unlocks[] array; building/recipe/upgrade names come from the
## owning registries so the text stays in sync with the content.
func get_node_unlock_description(node_id: StringName) -> String:
	var node: ProgressionTreeNode = _nodes.get(node_id, null)
	if node == null:
		return ""
	var lines: Array[String] = [node.display_name]
	if node.unlocks.is_empty():
		lines.append("Unlocks: nothing")
	else:
		lines.append("Unlocks:")
		for unlock: Dictionary in node.unlocks:
			lines.append("• " + _unlock_label(unlock))
	return "\n".join(lines)


## One friendly line describing a single unlock entry.
func _unlock_label(unlock: Dictionary) -> String:
	var id: String = str(unlock["id"])
	match unlock["type"]:
		"building":
			var bt: int = _building_type_from_name(id)
			var bld_name: String = BuildingRegistry.get_type_display_name(bt) if bt >= 0 else _prettify(id)
			return "Build: %s" % bld_name
		"building_recipe":
			var parts: PackedStringArray = id.split(":", false, 1)
			if parts.size() == 2:
				var bt2: int = _building_type_from_name(parts[0])
				var bname: String = BuildingRegistry.get_type_display_name(bt2) if bt2 >= 0 else _prettify(parts[0])
				return "Recipe: %s (%s)" % [bname, _prettify(parts[1])]
			return "Recipe: %s" % _prettify(id)
		"manual_recipe":
			var disp: String = str(CraftingRegistry.RECIPE_DISPLAY_NAME.get(StringName(id), _prettify(id)))
			return "Craft: %s" % disp
		"gather":
			return _prettify(id)
		"upgrade":
			return "Upgrade: %s" % _prettify(id)
		"search":
			return "Search action (locate clay deposits)"
		"npc_level_cap":
			return "Raise NPC level cap to %s" % id
	return _prettify(id)


## Turns an UPPER_SNAKE / lower_snake id into a Title-cased phrase ("CLEAR_TREE" → "Clear Tree").
func _prettify(id: String) -> String:
	return id.capitalize()


# --- State management / Save-Load --------------------------------------------

## Resets to game-start state: nothing is unlocked (not even the root Hearth — unlocking it is the
## player's first action, which grants the "build a Collection Point" task) and the player holds
## starting_points progression points.
func reset_to_initial() -> void:
	_unlocked.clear()
	progression_points = starting_points
	points_changed.emit(progression_points)


## Unlocks every node at once, bypassing prerequisite checks. Intended for tests and
## dev cheats that need the whole tech tree open; emits node_unlocked for each newly
## unlocked node so gated UI surfaces refresh.
func unlock_all() -> void:
	for node_id: StringName in _nodes:
		if not _unlocked.has(node_id):
			_unlocked[node_id] = true
			node_unlocked.emit(node_id)


## Serializes the unlock state + progression-point balance for save files. The unlocked
## node ids are order-stable (graph order) for determinism.
func serialize() -> Dictionary:
	var ids: Array = []
	for node_id: StringName in _nodes:  # iterate in graph order for determinism
		if _unlocked.has(node_id):
			ids.append(str(node_id))
	return {"unlocked": ids, "points": progression_points}


## Restores unlock state + points from a serialized payload. Accepts the current Dictionary
## form ({unlocked:[ids], points:int}) and the legacy bare Array of node-id strings (points
## then default to starting_points). Unknown ids are skipped (a node may have been removed
## since the save). The Hearth is NOT auto-asserted: a fresh/empty save legitimately starts with
## nothing unlocked (the player must unlock the Hearth first). NOTE: this does NOT emit
## node_unlocked, so the Task System does not re-grant tasks on load — task status is restored
## separately by TaskSystem.deserialize().
func deserialize(data: Variant) -> void:
	var ids: Array = []
	if data is Dictionary:
		ids = data.get("unlocked", [])
		progression_points = int(data.get("points", starting_points))
	elif data is Array:
		ids = data
		progression_points = starting_points
	else:
		progression_points = starting_points
	_unlocked.clear()
	for raw: Variant in ids:
		var node_id := StringName(str(raw))
		if _nodes.has(node_id):
			_unlocked[node_id] = true
	points_changed.emit(progression_points)
