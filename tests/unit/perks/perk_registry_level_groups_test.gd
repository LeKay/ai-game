## Tests that PerkRegistry.generate_choices draws bound goods from the
## level-restricted pool defined by LEVEL_PERK_GROUPS.
## Spec: docs/superpowers/specs/2026-06-28-perk-good-groups-design.md
##
## Uses the live ResourceRegistry autoload (data/resources.json) — `clothing`
## must be tagged perk_group: 1 (Task 2).

extends GdUnitTestSuite

const PerkRegistry := preload("res://src/systems/perks/perk_registry.gd")


## Minimal duck-typed stand-in for NPCSystem.NPCInstance — PerkRegistry only
## reads .profession, .perks, .level on the npc argument.
class _NPCStub:
	var level: int = 1
	var profession: int = -1
	var perks: Array = []


func _stub(level: int, profession: int, perks: Array) -> _NPCStub:
	var n := _NPCStub.new()
	n.level = level
	n.profession = profession
	n.perks = perks
	return n


# ---- AC-4: Level 2 calling cards all bind clothing ---------------------------

func test_level_2_calling_cards_all_bind_clothing() -> void:
	# Frischer NPC: keine Profession, keine Perks, level=2 → Calling-Pfad.
	var npc := _stub(2, -1, [])
	# Mehrfach laufen, weil _calling_cards Zufall enthält (building shuffle).
	for _i in 50:
		var cards: Array = PerkRegistry.generate_choices(npc, 3)
		assert_array(cards).is_not_empty()
		for card: Dictionary in cards:
			assert_that(card[&"good"]).is_equal(&"clothing")


# ---- AC-6: Duplicates allowed when pool has 1 member -------------------------

func test_level_2_can_produce_three_cards_with_same_good() -> void:
	var npc := _stub(2, -1, [])
	var produced_three_cards := false
	for _i in 50:
		var cards: Array = PerkRegistry.generate_choices(npc, 3)
		if cards.size() == 3:
			produced_three_cards = true
			break
	assert_bool(produced_three_cards).is_true()


# ---- Level 3 → group 2 (pottery, leather, furniture) -----------------------

func test_level_3_draws_only_from_group_2() -> void:
	# NPC mit Profession + bereits 1 Perk → kein Calling-Pfad mehr;
	# generate_choices nimmt LEVEL_PERK_GROUPS.get(3, 0) == 2 → nur Gruppe-2-Goods.
	var first_perk := {&"perk_id": &"berufung", &"good": &"clothing", &"building_type": 0}
	var npc := _stub(3, BuildingRegistry.BuildingType.LUMBER_CAMP, [first_perk])
	var allowed: Array[StringName] = [&"pottery", &"leather", &"furniture"]

	for _i in 50:
		var cards: Array = PerkRegistry.generate_choices(npc, 3)
		assert_array(cards).is_not_empty()
		for card: Dictionary in cards:
			var good: StringName = card[&"good"]
			if good == &"":
				continue  # non-good-bound perk
			assert_array(allowed).contains([good])


func test_level_3_eventually_draws_each_group_2_member() -> void:
	# Sanity: Pool ist tatsächlich {pottery, leather, furniture}, nicht nur ein Element.
	var first_perk := {&"perk_id": &"berufung", &"good": &"clothing", &"building_type": 0}
	var npc := _stub(3, BuildingRegistry.BuildingType.LUMBER_CAMP, [first_perk])
	var seen: Dictionary = {&"pottery": false, &"leather": false, &"furniture": false}
	for _i in 200:
		var cards: Array = PerkRegistry.generate_choices(npc, 3)
		for card: Dictionary in cards:
			var good: StringName = card[&"good"]
			if seen.has(good):
				seen[good] = true
		if seen[&"pottery"] and seen[&"leather"] and seen[&"furniture"]:
			break
	for id: StringName in seen:
		assert_bool(seen[id]).is_true()
