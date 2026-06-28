# Perk-Gut-Gruppen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Level-Up-Perk-Karten ziehen das gebundene Consumable (Good) abhängig vom Level aus einer definierten Ressourcen-Gruppe. Erstes Level-Up (Level 2) → Gruppe 1 = nur `clothing`.

**Architecture:** Neues Datenfeld `perk_group` (int) pro Ressource in `data/resources.json`. `ResourceRegistry` exponiert einen Group-Filter. `PerkRegistry` hält ein Level→Group-Mapping und ersetzt sein bisheriges Goods-Sampling. Distinct-Goods-Constraint zwischen Karten entfällt — gleiche Goods sind erlaubt.

**Tech Stack:** GDScript / Godot 4.6, gdUnit4 für Tests, JSON-Daten unter `data/`.

**Design Spec:** `docs/superpowers/specs/2026-06-28-perk-good-groups-design.md`

---

## File Structure

**Create:**
- `tests/fixtures/perk_group_fixture.json` — fixture mit perk-eligible Resources in unterschiedlichen `perk_group`-Werten
- `tests/unit/resource/perk_group_test.gd` — Unit-Tests für `get_perk_eligible_ids_for_group`
- `tests/unit/perks/perk_registry_level_groups_test.gd` — Tests für level-basiertes Goods-Sampling in `PerkRegistry`
- `tests/unit/perks/.gdignore` (falls dirs gdignore brauchen — siehe Convention-Check Task 0)

**Modify:**
- `data/resources.json:155-170` — `perk_group: 1` an `clothing` ergänzen
- `src/systems/resource_registry.gd:40-43` — neues Feld in `_ResourceDefinition`
- `src/systems/resource_registry.gd:206-214` — neuer Accessor `get_perk_eligible_ids_for_group`
- `src/systems/resource_registry.gd:357-358` — Parsing für `perk_group`
- `src/systems/perks/perk_registry.gd` — `LEVEL_PERK_GROUPS` const, `_goods_pool_for_level()` helper, Refactor von `generate_choices()` und `_calling_cards()`

---

## Task 0: Convention-Check (Orientation, no commits)

**Files:** *(read-only)*

- [ ] **Step 1: Verify the test directory layout for new perks tests**

Run:
```bash
ls /Users/lukas.kersting/IdeaProjects/ai-game/tests/unit/
```

Expected: kein `perks/`-Verzeichnis vorhanden. Du legst es in Task 5 implizit über die erste Testdatei an.

- [ ] **Step 2: Verify Godot binary path**

Run:
```bash
ls /Applications/Godot.app/Contents/MacOS/godot
```

Expected: existiert. Falls nicht — User fragen, an welchem Pfad das Binary liegt; alle nachfolgenden Test-Kommandos anpassen.

- [ ] **Step 3: Re-read the spec**

Read `docs/superpowers/specs/2026-06-28-perk-good-groups-design.md` komplett, insbesondere Abschnitt "Akzeptanzkriterien".

---

## Task 1: ResourceRegistry — perk_group field + accessor (TDD)

**Files:**
- Create: `tests/fixtures/perk_group_fixture.json`
- Create: `tests/unit/resource/perk_group_test.gd`
- Modify: `src/systems/resource_registry.gd`

- [ ] **Step 1: Write the fixture**

Create `tests/fixtures/perk_group_fixture.json` mit folgendem Inhalt:

```json
{
  "version": 1,
  "resources": [
    {
      "id": "alpha",
      "display_name": "Alpha",
      "category": "production_good",
      "stack_limit": 99,
      "weight": 1.0,
      "base_value": 1,
      "max_charge": 100.0,
      "perk_eligible": true,
      "perk_group": 1
    },
    {
      "id": "beta",
      "display_name": "Beta",
      "category": "production_good",
      "stack_limit": 99,
      "weight": 1.0,
      "base_value": 1,
      "max_charge": 100.0,
      "perk_eligible": true,
      "perk_group": 1
    },
    {
      "id": "gamma",
      "display_name": "Gamma",
      "category": "production_good",
      "stack_limit": 99,
      "weight": 1.0,
      "base_value": 1,
      "max_charge": 100.0,
      "perk_eligible": true,
      "perk_group": 2
    },
    {
      "id": "delta",
      "display_name": "Delta",
      "category": "production_good",
      "stack_limit": 99,
      "weight": 1.0,
      "base_value": 1,
      "max_charge": 100.0,
      "perk_eligible": true
    },
    {
      "id": "epsilon",
      "display_name": "Epsilon",
      "category": "production_good",
      "stack_limit": 99,
      "weight": 1.0,
      "base_value": 1,
      "max_charge": 100.0,
      "perk_eligible": false,
      "perk_group": 1
    },
    {
      "id": "zeta",
      "display_name": "Zeta",
      "category": "production_good",
      "stack_limit": 99,
      "weight": 1.0,
      "base_value": 1,
      "max_charge": 100.0,
      "perk_eligible": true,
      "perk_group": 1,
      "deprecated": true
    }
  ]
}
```

Begründung der Einträge:
- `alpha`, `beta`: perk-eligible, Gruppe 1 → erwartet bei `get_perk_eligible_ids_for_group(1)`.
- `gamma`: Gruppe 2 → erwartet bei `(2)`.
- `delta`: perk-eligible, kein `perk_group`-Feld → Gruppe 0 (Default).
- `epsilon`: in Gruppe 1, aber `perk_eligible: false` → muss gefiltert werden.
- `zeta`: in Gruppe 1, perk-eligible, aber `deprecated: true` → muss gefiltert werden.

- [ ] **Step 2: Write the failing test**

Create `tests/unit/resource/perk_group_test.gd`:

```gdscript
## Tests for ResourceRegistry.get_perk_eligible_ids_for_group (perk-group filter).
## Spec: docs/superpowers/specs/2026-06-28-perk-good-groups-design.md

extends GdUnitTestSuite

const ResourceRegistry := preload("res://src/systems/resource_registry.gd")

const _FIXTURE := "res://tests/fixtures/perk_group_fixture.json"


func _make_registry() -> ResourceRegistry:
	var reg := ResourceRegistry.new()
	auto_free(reg)
	reg.load_from_file(_FIXTURE)
	return reg


func test_group_1_returns_only_perk_eligible_non_deprecated_members() -> void:
	var reg := _make_registry()
	var ids: Array[StringName] = reg.get_perk_eligible_ids_for_group(1)
	assert_array(ids).contains_exactly_in_any_order([&"alpha", &"beta"])


func test_group_2_returns_single_member() -> void:
	var reg := _make_registry()
	var ids: Array[StringName] = reg.get_perk_eligible_ids_for_group(2)
	assert_array(ids).contains_exactly_in_any_order([&"gamma"])


func test_group_0_returns_resources_without_group_assignment() -> void:
	var reg := _make_registry()
	var ids: Array[StringName] = reg.get_perk_eligible_ids_for_group(0)
	assert_array(ids).contains_exactly_in_any_order([&"delta"])


func test_unused_group_returns_empty() -> void:
	var reg := _make_registry()
	var ids: Array[StringName] = reg.get_perk_eligible_ids_for_group(99)
	assert_array(ids).is_empty()
```

- [ ] **Step 3: Run test to verify it fails**

Run:
```bash
bash addons/gdUnit4/runtest.sh --godot_binary /Applications/Godot.app/Contents/MacOS/godot -a res://tests/unit/resource/perk_group_test.gd
```

Expected: 4 Tests failing. Konkret eine Fehlermeldung à la "Invalid call. Nonexistent function 'get_perk_eligible_ids_for_group'" — Funktion existiert noch nicht.

- [ ] **Step 4: Add `perk_group` field to `_ResourceDefinition`**

Modify `src/systems/resource_registry.gd:41` — nach Zeile 41 (`var perk_eligible: bool = false`) einfügen:

```gdscript
	## Perk-Gut-Gruppe (Perk System). 0 = nicht zugeordnet.
	## Nur relevant wenn perk_eligible == true. Mapping Level→Gruppe in perk_registry.gd.
	var perk_group: int = 0
```

- [ ] **Step 5: Parse `perk_group` from JSON**

Modify `src/systems/resource_registry.gd:357-358` — direkt nach den existierenden `raw_perk_eligible` Zeilen einfügen:

```gdscript
	var raw_perk_group: Variant = entry.get("perk_group")
	def.perk_group = int(raw_perk_group) if raw_perk_group is float or raw_perk_group is int else 0
```

- [ ] **Step 6: Implement the accessor**

Modify `src/systems/resource_registry.gd` — direkt nach der existierenden `get_perk_eligible_ids()` Funktion (Ende bei Zeile 214) einfügen:

```gdscript
## Returns perk-eligible (non-deprecated) resource IDs whose perk_group matches `group`.
## Used by PerkRegistry to draw the bound good from a level-restricted pool.
func get_perk_eligible_ids_for_group(group: int) -> Array[StringName]:
	var result: Array[StringName] = []
	for id: StringName in _definitions:
		var def: _ResourceDefinition = _definitions[id]
		if def.perk_eligible and not def.deprecated and def.perk_group == group:
			result.append(id)
	result.sort()
	return result
```

- [ ] **Step 7: Run tests to verify they pass**

Run:
```bash
bash addons/gdUnit4/runtest.sh --godot_binary /Applications/Godot.app/Contents/MacOS/godot -a res://tests/unit/resource/perk_group_test.gd
```

Expected: 4 tests PASS.

- [ ] **Step 8: Verify existing resource-registry tests still pass**

Run:
```bash
bash addons/gdUnit4/runtest.sh --godot_binary /Applications/Godot.app/Contents/MacOS/godot -a res://tests/unit/resource/
```

Expected: alle Tests PASS (Regression-Check).

- [ ] **Step 9: Commit**

```bash
git add tests/fixtures/perk_group_fixture.json tests/unit/resource/perk_group_test.gd src/systems/resource_registry.gd
git commit -m "feat(resources): add perk_group field + group accessor"
```

---

## Task 2: Tag `clothing` with `perk_group: 1`

**Files:**
- Modify: `data/resources.json:155-170`

- [ ] **Step 1: Add the field**

Modify `data/resources.json` — am Clothing-Eintrag (beginnt Zeile 155). Direkt nach `"perk_eligible": true,` (Zeile 158) einfügen:

```json
	  "perk_group": 1,
```

Ergebnis (Auszug):
```json
{
  "id": "clothing",
  "display_name": "Clothing",
  "perk_eligible": true,
  "perk_group": 1,
  "category": "production_good",
  ...
}
```

- [ ] **Step 2: Sanity-check JSON syntax**

Run:
```bash
python3 -c "import json; json.load(open('/Users/lukas.kersting/IdeaProjects/ai-game/data/resources.json'))" && echo OK
```

Expected: `OK`.

- [ ] **Step 3: Run full resource test suite (regression)**

Run:
```bash
bash addons/gdUnit4/runtest.sh --godot_binary /Applications/Godot.app/Contents/MacOS/godot -a res://tests/unit/resource/
```

Expected: alle Tests PASS.

- [ ] **Step 4: Commit**

```bash
git add data/resources.json
git commit -m "data(resources): tag clothing as perk_group 1"
```

---

## Task 3: PerkRegistry — Level→Group mapping + pool helper

**Files:**
- Modify: `src/systems/perks/perk_registry.gd`

(Kein neuer Test in diesem Task — Task 5 testet das Verhalten ganzheitlich über `generate_choices`. Hier wird nur die interne Helper-Funktion + die Konstante hinzugefügt; das vereinfacht Task 4.)

- [ ] **Step 1: Add `LEVEL_PERK_GROUPS` constant**

Modify `src/systems/perks/perk_registry.gd` — direkt nach den Pool-Konstanten (nach Zeile 26, vor `# ---- Perk catalog`) einfügen:

```gdscript
# ---- Level → perk-group mapping -----------------------------------------------

## At a given NPC level (post-level-up), perk cards' bound goods are drawn ONLY
## from resources whose perk_group matches this value. Levels not listed fall
## back to the full perk-eligible pool (legacy behaviour). See
## docs/superpowers/specs/2026-06-28-perk-good-groups-design.md.
const LEVEL_PERK_GROUPS: Dictionary = {
	2: 1,
}
```

- [ ] **Step 2: Add the goods-pool helper**

Modify `src/systems/perks/perk_registry.gd` — direkt vor `static func generate_choices(` (Zeile 148) einfügen:

```gdscript
## Returns the perk-eligible goods pool a level-up at `level` should draw from.
## Falls back to the full perk-eligible pool when no group is configured for this
## level OR when the configured group is empty (safety: never soft-lock).
static func _goods_pool_for_level(level: int) -> Array[StringName]:
	var group: int = int(LEVEL_PERK_GROUPS.get(level, 0))
	if group <= 0:
		return ResourceRegistry.get_perk_eligible_ids()
	var pool: Array[StringName] = ResourceRegistry.get_perk_eligible_ids_for_group(group)
	if pool.is_empty():
		return ResourceRegistry.get_perk_eligible_ids()
	return pool
```

- [ ] **Step 3: Smoke-check the file parses**

Run:
```bash
/Applications/Godot.app/Contents/MacOS/godot --headless --check-only --path /Users/lukas.kersting/IdeaProjects/ai-game src/systems/perks/perk_registry.gd 2>&1 | tail -5
```

Expected: keine Parse-Errors. (Falls `--check-only` nicht verfügbar ist: nur Task 4/5 ausführen — die Tests decken Compile-Fehler ab.)

- [ ] **Step 4: Commit**

```bash
git add src/systems/perks/perk_registry.gd
git commit -m "feat(perks): add LEVEL_PERK_GROUPS mapping + goods-pool helper"
```

---

## Task 4: Refactor `generate_choices` to use level-based pool with replacement

**Files:**
- Modify: `src/systems/perks/perk_registry.gd:148-208` (Funktion `generate_choices`)

- [ ] **Step 1: Replace the goods-pool selection and remove distinct-good constraint**

Modify `src/systems/perks/perk_registry.gd` — die existierende `generate_choices` Funktion (Zeilen 148-208) komplett ersetzen durch:

```gdscript
## Builds up to `count` distinct perk cards for a level-up choice, respecting the profession gate.
## `npc` is an NPCSystem.NPCInstance (typed Object to avoid load-order coupling). Each card is a
## Dictionary: {perk_id, name, desc, effect, magnitude, good, building_type}.
## `good` is a perk-eligible resource id; `building_type` is an int (or -1 if not building-bound).
## Returns fewer than `count` cards only if the candidate pool is too small. The goods pool is
## level-restricted via LEVEL_PERK_GROUPS — when restricted, the same good may appear on multiple
## cards (cards differ in perk and/or building).
static func generate_choices(npc: Object, count: int = 3) -> Array:
	var has_profession: bool = npc != null and int(npc.profession) != -1

	# First perk choice (normally the level-2 level-up): force the profession decision. Offer ONLY
	# Calling cards — up to `count`, each bound to a DIFFERENT already-unlocked production building.
	# Falls through to the normal mix only if no production building is unlocked yet, so the choice
	# is never empty.
	if npc != null and not has_profession and (npc.perks as Array).is_empty():
		var calling_cards: Array = _calling_cards(npc, count)
		if not calling_cards.is_empty():
			return calling_cards

	# 1) Candidate perk definitions, filtered by the profession gate.
	var candidates: Array[Dictionary] = []
	for p: Dictionary in PERKS:
		if p["is_profession"]:
			if has_profession:
				continue  # already specialised — one profession per NPC, permanent
		elif p["building_bound"]:
			if not has_profession:
				continue  # building-bound effect perks are locked until a profession is chosen
			if p["pool"] == POOL_INPUT_PROCESSING and not input_processing_types().has(int(npc.profession)):
				continue  # Thrifty only when the profession is an input-processing type
		candidates.append(p)
	candidates.shuffle()

	# 2) Goods pool restricted by NPC level (LEVEL_PERK_GROUPS). May be small — duplicate goods
	#    across cards are allowed (cards still differ in perk).
	var level: int = int(npc.level) if npc != null else 0
	var goods: Array[StringName] = _goods_pool_for_level(level)

	# 3) Build up to `count` distinct cards.
	var cards: Array = []
	for p: Dictionary in candidates:
		if cards.size() >= count:
			break
		var good: StringName = &""
		if p["good_bound"]:
			if goods.is_empty():
				continue  # no eligible goods at all — cannot bind this perk
			good = goods[randi() % goods.size()]
		var building_type: int = -1
		if p["building_bound"]:
			if p["is_profession"]:
				var pool: Array[int] = unlocked_production_types()
				if pool.is_empty():
					continue  # no unlocked profession to offer — skip this Calling card
				building_type = pool[randi() % pool.size()]
			else:
				building_type = int(npc.profession)  # applies to the NPC's profession type
		cards.append({
			&"perk_id": p["id"],
			&"name": p["name"],
			&"desc": p["desc"],
			&"effect": p["effect"],
			&"magnitude": p["magnitude"],
			&"good": good,
			&"building_type": building_type,
		})
	return cards
```

Wichtige Änderungen ggü. heute:
- `goods` kommt aus `_goods_pool_for_level(npc.level)` statt `ResourceRegistry.get_perk_eligible_ids()` + shuffle.
- `good_idx`-Variable + Distinkt-Check entfernt.
- Jede Karte zieht `good = goods[randi() % goods.size()]` (mit Replacement).
- `_calling_cards(count)` → `_calling_cards(npc, count)` (siehe Task 5).

- [ ] **Step 2: Commit (interim — compile-Check folgt im nächsten Task gemeinsam mit _calling_cards)**

Noch nicht committen — der Aufruf `_calling_cards(npc, count)` matcht erst nach Task 5. Weiter zu Task 5.

---

## Task 5: Refactor `_calling_cards` to use level-based pool

**Files:**
- Modify: `src/systems/perks/perk_registry.gd:214-242` (Funktion `_calling_cards`)

- [ ] **Step 1: Replace `_calling_cards` to take npc and use the level helper**

Modify `src/systems/perks/perk_registry.gd` — die existierende `_calling_cards` Funktion (Zeilen 214-242) komplett ersetzen durch:

```gdscript
## Builds up to `count` Calling (profession) cards, each bound to a DISTINCT already-unlocked
## production building. The bound good is drawn from the NPC's level-restricted pool
## (LEVEL_PERK_GROUPS) — duplicates across cards are allowed. Empty if no production building is
## unlocked yet. Used for the first level-up's forced profession choice.
static func _calling_cards(npc: Object, count: int) -> Array:
	var def: Dictionary = get_def(&"berufung")
	if def.is_empty():
		return []
	var pros: Array[int] = unlocked_production_types()
	pros.shuffle()
	var level: int = int(npc.level) if npc != null else 0
	var goods: Array[StringName] = _goods_pool_for_level(level)
	var cards: Array = []
	for t: int in pros:
		if cards.size() >= count:
			break
		var good: StringName = &""
		if def["good_bound"]:
			if goods.is_empty():
				break  # no eligible goods at all
			good = goods[randi() % goods.size()]
		cards.append({
			&"perk_id": def["id"],
			&"name": def["name"],
			&"desc": def["desc"],
			&"effect": def["effect"],
			&"magnitude": def["magnitude"],
			&"good": good,
			&"building_type": t,
		})
	return cards
```

Wichtige Änderungen ggü. heute:
- Neuer Parameter `npc: Object`.
- Goods-Pool aus `_goods_pool_for_level(npc.level)` statt `ResourceRegistry.get_perk_eligible_ids()` + shuffle.
- `good_idx`/`break on out of goods (distinct)` entfernt; stattdessen mit Replacement.

- [ ] **Step 2: Verify no other callers of `_calling_cards`**

Run:
```bash
grep -rn "_calling_cards" /Users/lukas.kersting/IdeaProjects/ai-game/src /Users/lukas.kersting/IdeaProjects/ai-game/tests
```

Expected: nur die Definition in `perk_registry.gd` und der Aufruf in `generate_choices` (jetzt mit `npc, count`). Sonst nichts — `_calling_cards` ist privat.

- [ ] **Step 3: Run existing tests as smoke-check**

Run:
```bash
bash addons/gdUnit4/runtest.sh --godot_binary /Applications/Godot.app/Contents/MacOS/godot -a res://tests/unit/resource/
```

Expected: alle Tests PASS (Compile-Check via Autoload-Loading).

- [ ] **Step 4: Commit Task 4 + 5 zusammen**

```bash
git add src/systems/perks/perk_registry.gd
git commit -m "feat(perks): draw bound goods from level-restricted pool with replacement"
```

---

## Task 6: Behavior test for level-based card generation

**Files:**
- Create: `tests/unit/perks/perk_registry_level_groups_test.gd`

- [ ] **Step 1: Write the test**

Create `tests/unit/perks/perk_registry_level_groups_test.gd`:

```gdscript
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


# ---- AC-5: Level 3+ uses the full perk-eligible pool ------------------------

func test_level_3_uses_full_pool() -> void:
	# NPC mit Profession + bereits 1 Perk → kein Calling-Pfad mehr;
	# generate_choices nimmt LEVEL_PERK_GROUPS.get(3, 0) == 0 → voller Pool.
	var first_perk := {&"perk_id": &"berufung", &"good": &"clothing", &"building_type": 0}
	var npc := _stub(3, BuildingRegistry.BuildingType.LUMBER_CAMP, [first_perk])

	var seen_non_clothing := false
	for _i in 100:
		var cards: Array = PerkRegistry.generate_choices(npc, 3)
		for card: Dictionary in cards:
			var good: StringName = card[&"good"]
			if good != &"" and good != &"clothing":
				seen_non_clothing = true
				break
		if seen_non_clothing:
			break
	# Mit dem vollen Pool (Plank, Cloth, Clothing, Axe, Spindle, Pottery, Salt) und
	# 100 Iterationen × bis zu 3 good-bound Karten ist es extrem unwahrscheinlich,
	# dass nur clothing gezogen wird — würde auf eine fehlerhafte Pool-Auswahl deuten.
	assert_bool(seen_non_clothing).is_true()
```

- [ ] **Step 2: Run the test**

Run:
```bash
bash addons/gdUnit4/runtest.sh --godot_binary /Applications/Godot.app/Contents/MacOS/godot -a res://tests/unit/perks/perk_registry_level_groups_test.gd
```

Expected: 3 Tests PASS.

Falls Tests FAIL:
- `test_level_2_calling_cards_all_bind_clothing` FAIL mit non-clothing good → Task 2 (clothing.perk_group) wurde nicht gespeichert ODER `_goods_pool_for_level` greift nicht.
- `test_level_3_uses_full_pool` FAIL → entweder LEVEL_PERK_GROUPS hat `3:` Eintrag (sollte nicht), oder Pool-Helper liefert für Level 3 unerwartet die Group-1-Liste.

- [ ] **Step 3: Run the full test suite (regression)**

Run:
```bash
bash addons/gdUnit4/runtest.sh --godot_binary /Applications/Godot.app/Contents/MacOS/godot -a res://tests/
```

Expected: alle Tests PASS. (Achte besonders auf experience-/npc_system-Suites, falls vorhanden.)

- [ ] **Step 4: Commit**

```bash
git add tests/unit/perks/perk_registry_level_groups_test.gd
git commit -m "test(perks): cover level-based goods pool restriction"
```

---

## Task 7: Manual smoke check in Godot

**Files:** *(none — verification only)*

- [ ] **Step 1: Start the game**

Run game (z. B. via Godot Editor → Play). Spiele bis ein NPC Level 2 erreicht (oder lade einen Save kurz davor).

- [ ] **Step 2: Trigger level-up**

Klicke den ⬆️-Button für den NPC, der pending perk choices hat (oder warte auf das Day-Overview-Panel).

- [ ] **Step 3: Verify the cards**

Expected:
- 3 (oder weniger, falls < 3 production buildings unlocked sind) Calling/Profession-Karten.
- Jede Karte zeigt unten die Zeile "Requires: Clothing/day" mit dem Clothing-Icon.
- Karten unterscheiden sich im gezeigten Building (Lumber Camp / Gathering Hut / …).

Falls die Karten unterschiedliche Goods anzeigen → Bug; den Test in Task 6 nochmal lokal laufen lassen und Logs prüfen.

- [ ] **Step 4: Optional — Level 3+ smoke**

Falls möglich (Save mit NPC kurz vor Level 3): nach Wahl der Profession und erneutem Level-Up sollten die Karten wieder verschiedene Goods (nicht nur Clothing) zeigen.

- [ ] **Step 5: No commit — verification only**

(Falls Screenshots gewünscht sind: optional in `production/qa/evidence/` ablegen.)

---

## Done Criteria (Spec Mapping)

- AC-1: `Clothing.perk_group = 1` ✓ Task 2
- AC-2: `get_perk_eligible_ids_for_group(1) == [clothing]` ✓ Task 1 (fixture-based) + Task 6 (live data smoke via Calling-Test)
- AC-3: `get_perk_eligible_ids_for_group(0)` liefert ungetaggte perk-eligible Ressourcen ✓ Task 1
- AC-4: Erstes Level-Up → alle Karten an `clothing` gebunden ✓ Task 6 + Task 7
- AC-5: Level 3 → Goods aus vollem Pool ✓ Task 6
- AC-6: 3 Karten bei 1-Element-Gruppe möglich (mit Replacement) ✓ Task 6
