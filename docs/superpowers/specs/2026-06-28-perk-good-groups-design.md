# Perk-Gut-Gruppen für Level-Up-Karten

**Status:** Approved
**Datum:** 2026-06-28
**Betroffene Systeme:** PerkRegistry, ResourceRegistry, `data/resources.json`

## Ziel

Beim Level-Up gebundene Consumables (Goods) für Perks sollen je nach Level aus einer definierten Gruppe von Ressourcen gezogen werden — nicht mehr aus dem Gesamtpool aller perk-eligible Goods. Beispiel: erstes Level-Up (Level 2) zieht ausschließlich aus Gruppe 1, die initial nur `clothing` enthält.

## Designentscheidungen (aus Brainstorming)

1. **Mapping Level → Gruppe** ist eine vom Spielautor explizit gepflegte Tabelle (kein Schema wie „Level N = Gruppe N").
2. **Gruppen-Zuordnung pro Ressource** lebt als neues Feld `perk_group` in `data/resources.json`.
3. **Pool zu klein für `count` Karten:** dasselbe Good darf auf mehreren Karten erscheinen (Spieler wählt zwischen verschiedenen Perks am selben Good).
4. **Calling/Profession-Karten (Level 2)** folgen derselben Gruppen-Restriktion.
5. **Initiales Mapping:** nur `{2: 1}` definiert; Gruppe 1 = `{clothing}`. Ab Level 3 fällt die Logik auf den heutigen Gesamtpool zurück.

## Datenmodell

### `data/resources.json`

Neues optionales Feld pro Ressourcen-Eintrag:

```json
"perk_group": <int>     // default 0 = "nicht in einer spezifischen Gruppe"
```

**Seed-Werte:**
| Resource ID | perk_group |
|---|---|
| `clothing` | 1 |
| alle anderen perk-eligible | 0 (oder Feld weglassen) |

### ResourceRegistry

`ResourceDefinition` erhält Feld:

```gdscript
var perk_group: int = 0
```

`_parse_definition()` liest:

```gdscript
var raw_perk_group: Variant = entry.get("perk_group")
def.perk_group = int(raw_perk_group) if raw_perk_group is float or raw_perk_group is int else 0
```

Neue Accessor-Methode:

```gdscript
## Returns perk-eligible (non-deprecated) resource IDs whose perk_group == group.
func get_perk_eligible_ids_for_group(group: int) -> Array[StringName]
```

## Code-Änderungen

### `perk_registry.gd`

Neuer const Dict an obersten Konstanten:

```gdscript
## Level → perk-group: at this NPC level, perk cards' bound goods are drawn
## ONLY from resources whose perk_group matches this value. Levels not listed
## fall back to the full perk-eligible pool (legacy behaviour).
const LEVEL_PERK_GROUPS: Dictionary = {
    2: 1,
}
```

Helper:

```gdscript
## Returns the goods pool a level-up at `level` should draw from. Falls back to
## the full perk-eligible pool when no group is configured for this level OR
## when the configured group is empty.
static func _goods_pool_for_level(level: int) -> Array[StringName]:
    var group: int = int(LEVEL_PERK_GROUPS.get(level, 0))
    if group <= 0:
        return ResourceRegistry.get_perk_eligible_ids()
    var pool: Array[StringName] = ResourceRegistry.get_perk_eligible_ids_for_group(group)
    if pool.is_empty():
        return ResourceRegistry.get_perk_eligible_ids()  # safety: never soft-lock
    return pool
```

`generate_choices(npc, count)`:

- Statt `goods := ResourceRegistry.get_perk_eligible_ids(); goods.shuffle()` → `goods := _goods_pool_for_level(int(npc.level))`.
- Entferne `good_idx` und die Distinkt-Garantie: pro Karte wird ein zufälliges Good aus `goods` gewählt (`goods[randi() % goods.size()]`). Karten dürfen dasselbe Good tragen.

`_calling_cards(count)`:

- Goods-Pool analog über `_goods_pool_for_level(2)` (Calling läuft immer beim ersten Level-Up = Level 2).
- Auch hier: `good_idx`/Break-on-out-of-goods entfernen, Goods werden mit Replacement gezogen.

## Edge Cases

- **Goods-Pool ist leer (sollte nicht passieren):** Helper fällt auf vollen perk-eligible Pool zurück. Verhindert leeren Karten-Stack.
- **Resource mit `perk_eligible: false` und `perk_group: 1`:** wird ignoriert. Accessor filtert beides (`perk_eligible AND perk_group == group AND not deprecated`).
- **Save-Kompatibilität:** Perk-Instanzen speichern bereits konkrete Good-StringNames. Keine Save-Migration nötig.
- **Mapping ohne Eintrag (Level 3+):** Verhalten heute = Verhalten nachher (voller Pool, mit Replacement statt distinct). Verhaltensänderung: vor dem Refactor zog `generate_choices` distinct Goods pro Karte; danach mit Replacement. Akzeptiert.

## Tuning Knobs

- `LEVEL_PERK_GROUPS` (perk_registry.gd): Mapping Level → Gruppe.
- `perk_group` (data/resources.json, pro Ressource): Mitgliedschaft.

## Akzeptanzkriterien

1. `Clothing` hat `perk_group: 1` in `data/resources.json`.
2. `ResourceRegistry.get_perk_eligible_ids_for_group(1)` liefert `[clothing]`.
3. `ResourceRegistry.get_perk_eligible_ids_for_group(0)` liefert genau die perk-eligible Ressourcen mit `perk_group == 0` (also alle, bei denen das Feld fehlt oder explizit 0 ist).
4. Beim ersten Level-Up (Level 2) eines NPCs ohne Profession sind **alle** angebotenen Karten an `clothing` gebunden (Calling-Pfad).
5. Beim Level-Up auf Level 3 sind die Karten an Goods aus dem vollen perk-eligible Pool gebunden (gleiche Verteilung wie heute, abzüglich Distinkt-Garantie).
6. Drei Karten bei Level 2 sind erlaubt, auch wenn die Gruppe nur 1 Good enthält (jede Karte trägt `clothing`).

## Tests

`tests/unit/perks/resource_registry_perk_group_test.gd`:

- `test_clothing_in_group_1`: `get_perk_eligible_ids_for_group(1)` enthält `&"clothing"`.
- `test_group_with_no_members_returns_empty`: `get_perk_eligible_ids_for_group(99)` ist leer.
- `test_deprecated_excluded`: deprecated Resource mit `perk_group: 1` taucht nicht auf.

`tests/unit/perks/perk_registry_level_groups_test.gd`:

- `test_level_2_calling_cards_all_clothing`: Frischer NPC (level=2, keine Perks, keine Profession), mind. 1 unlocked Production-Building → alle generierten Calling-Karten haben `good == &"clothing"`.
- `test_level_3_uses_full_pool`: NPC mit Profession und 1 vorhandenem Perk, level=3 → Goods stammen aus `get_perk_eligible_ids()` (nicht nur clothing).
- `test_duplicate_goods_allowed_when_pool_small`: Level 2, drei Karten möglich (alle clothing).

## Out of Scope

- UI-Anpassungen am `PerkChoicePanel` (rendert Good automatisch korrekt).
- Erweitertes Mapping über Level 2 hinaus (kommt iterativ).
- Verschiebung des Mappings in eine JSON-Datei (kann später als Refactor, wenn der Map größer wird).
