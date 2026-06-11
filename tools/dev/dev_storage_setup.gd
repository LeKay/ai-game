## [DEV ONLY] Befüllt den ersten platzierten Storage-Container mit 20 Einheiten
## jeder Ressource aus resources.json.
## Nicht in Production-Builds laden.
## Alle Systemzugriffe sind als [MOCK] markiert.

extends Node

const _SEED_AMOUNTS: Dictionary = {
	&"wood":  0,
	&"stone": 0,
	&"fiber": 0,
	&"berry": 30,
	&"bread": 0,
	&"plank": 0,
	&"tool":  0,
}


func _ready() -> void:
	# [MOCK] BuildingRegistry — wartet auf den ersten platzierten Storage
	BuildingRegistry.building_placed.connect(_on_building_placed)  # [MOCK]


func _on_building_placed(building_id: String, building_type: int, _tile: Vector2i) -> void:
	# Don't seed when a save is being loaded — the building (and its stored items)
	# come from the save file, not from a fresh start. Disconnect so no later
	# player-placed storage gets seeded either; a loaded world is already established.
	if WorldSaveManager.has_pending_load():
		BuildingRegistry.building_placed.disconnect(_on_building_placed)
		return
	if building_type != BuildingRegistry.BuildingType.STORAGE_BUILDING \
			and building_type != BuildingRegistry.BuildingType.COLLECTION_POINT:
		return

	# [MOCK] BuildingRegistry — get_building_instance
	var inst: BuildingRegistry.BuildingInstance = \
			BuildingRegistry.get_building_instance(building_id)  # [MOCK]
	if inst == null or inst.assigned_container_id == &"":
		return

	var container_id: StringName = inst.assigned_container_id
	for resource_id: StringName in _SEED_AMOUNTS:
		var amount: int = _SEED_AMOUNTS[resource_id]
		if amount <= 0:
			continue
		var result: InventoryContainer.DepositResult = \
				InventorySystem.try_deposit(container_id, resource_id, amount)
		if result != InventoryContainer.DepositResult.SUCCESS:
			push_warning("DevStorageSetup: Deposit fehlgeschlagen fuer '%s' (result=%d)" \
					% [resource_id, result])

	# Nach dem ersten Storage disconnecten — nicht bei jedem weiteren Gebäude erneut einzahlen
	BuildingRegistry.building_placed.disconnect(_on_building_placed)
