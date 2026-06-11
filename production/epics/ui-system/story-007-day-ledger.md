# Story 007: DayLedger — Tägliche Ressourcen-Delta-Erfassung

> **Epic**: UI System
> **Status**: Complete
> **Layer**: Presentation
> **Type**: Logic
> **Manifest Version**: 2026-05-14

## Context

**GDD**: `design/gdd/tick-system.md` (Day Transition — Section 5)
**Requirement**: `TR-ui-006`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0001 + ADR-0003 (Autoload-Muster, Signal-Subscription)
**ADR Decision Summary**: DayLedger ist ein Autoload-Singleton das InventorySystem-Signale
abonniert und täglich akkumulierte Deltas (Zugewinne und Verluste pro Ressource) hält.
Beim `day_transition` werden die gesammelten Deltas eingefroren und für Abfrage
bereitgestellt, danach wird der Puffer zurückgesetzt.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Nur Signal-Subscriptions und Dictionary-Operationen — keine post-cutoff APIs.

**Control Manifest Rules (Foundation Layer)**:
- Required: Autoload-Singleton-Muster (`extends Node`); Null-Check auf InventorySystem in `_enter_tree()`
- Forbidden: Kein direktes Lesen von TileMapLayer oder Szene-Nodes
- Guardrail: Keine per-Frame-Logik — DayLedger ist rein reaktiv (Signals)

---

## Acceptance Criteria

*Abgeleitet aus tick-system.md Section 5 und dem Day Overview Panel Requirement:*

- [ ] **AC-1**: `DayLedger` ist als Autoload registriert und per `Engine.get_singleton("DayLedger")` erreichbar ab Spielstart
- [ ] **AC-2**: Jede Inventory-Änderung (deposit/withdraw via InventorySystem-Signale) wird als Delta akkumuliert — positive Werte = Zuwachs, negative = Verlust
- [ ] **AC-3**: Beim `day_transition`-Signal friert DayLedger die gesammelten Deltas ein; `get_last_day_deltas() -> Dictionary` gibt sie zurück und der Puffer wird auf leer zurückgesetzt
- [ ] **AC-4**: `get_last_day_deltas()` gibt ein leeres Dictionary zurück wenn noch kein Tag abgeschlossen wurde
- [ ] **AC-5**: Hunger-Konsum (via `HungerSystem.food_consumed_daily`-Signal) wird separat als `get_last_hunger_consumed() -> Dictionary` gehalten — nicht mit allgemeinen Deltas gemischt

---

## Implementation Notes

*Abgeleitet aus ADR-0001/ADR-0003 Autoload-Muster:*

```gdscript
extends Node

var _current_deltas: Dictionary = {}
var _last_day_deltas: Dictionary = {}
var _last_hunger_consumed: Dictionary = {}

func _enter_tree() -> void:
    var inv = Engine.get_singleton("InventorySystem")
    if inv:
        inv.item_deposited.connect(_on_deposited)
        inv.item_withdrawn.connect(_on_withdrawn)
    TickSystem.day_transition.connect(_on_day_transition)
    HungerSystem.food_consumed_daily.connect(_on_hunger_consumed)

func _on_deposited(resource_id: StringName, qty: int) -> void:
    _current_deltas[resource_id] = _current_deltas.get(resource_id, 0) + qty

func _on_withdrawn(resource_id: StringName, qty: int) -> void:
    _current_deltas[resource_id] = _current_deltas.get(resource_id, 0) - qty

func _on_day_transition(_days: int) -> void:
    _last_day_deltas = _current_deltas.duplicate()
    _current_deltas.clear()

func _on_hunger_consumed(items: Dictionary) -> void:
    _last_hunger_consumed = items.duplicate()

func get_last_day_deltas() -> Dictionary:
    return _last_day_deltas

func get_last_hunger_consumed() -> Dictionary:
    return _last_hunger_consumed
```

**Voraussetzung — zu prüfen vor Implementierung**:
- `InventorySystem` muss Signale `item_deposited(resource_id: StringName, qty: int)` und `item_withdrawn(resource_id: StringName, qty: int)` emittieren. Falls nicht vorhanden, als Teil dieser Story hinzufügen.
- `HungerSystem` muss `food_consumed_daily(items: Dictionary)` emittieren. Falls nicht vorhanden, als Teil dieser Story hinzufügen.
- `DayLedger` in `project.godot` als Autoload nach `HungerSystem` registrieren (Ladereihenfolge ADR-0006).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 008: UI-Panel das DayLedger abfragt und anzeigt
- Persistenz der Deltas über Save/Load (kein GDD-Requirement)
- Aggregation über mehrere Tage

---

## QA Test Cases

*Written by qa-lead at story creation. The developer implements against these — do not invent new test cases during implementation.*

- **AC-1**: DayLedger erreichbar
  - Given: Spiel gestartet, Autoload registriert
  - When: `Engine.get_singleton("DayLedger")` aufgerufen
  - Then: Rückgabe ist nicht null
  - Edge cases: Aufruf vor `_ready()` anderer Nodes — muss trotzdem erreichbar sein

- **AC-2**: Deposit akkumuliert positiv
  - Given: DayLedger frisch initialisiert (neuer Tag, leerer Puffer)
  - When: `item_deposited("wood", 5)` emittiert, danach `item_deposited("wood", 3)`
  - Then: `_current_deltas["wood"] == 8`
  - Edge cases: Zwei verschiedene Ressourcen bleiben unabhängig; qty = 0 bleibt neutral

- **AC-2b**: Withdraw akkumuliert negativ
  - Given: `_current_deltas["berry"] == 0`
  - When: `item_withdrawn("berry", 2)` emittiert
  - Then: `_current_deltas["berry"] == -2`
  - Edge cases: Withdraw vor Deposit — negative Werte erlaubt

- **AC-3**: Day-Transition friert ein und resettet
  - Given: `_current_deltas = {wood: 8, berry: -2}`
  - When: `day_transition` Signal feuert
  - Then: `get_last_day_deltas() == {wood: 8, berry: -2}`; `_current_deltas == {}`
  - Edge cases: Zweites `day_transition` ohne weitere Änderungen → `get_last_day_deltas()` gibt leeres Dictionary zurück (Tag war leer)

- **AC-4**: Leeres Dictionary vor erstem Tag
  - Given: Spiel frisch gestartet, kein Tag abgeschlossen
  - When: `get_last_day_deltas()` aufgerufen
  - Then: `{}` zurückgegeben — kein Crash, kein null

- **AC-5**: Hunger-Konsum separat
  - Given: HungerSystem emittiert `food_consumed_daily({&"berry": 3})`
  - When: `get_last_hunger_consumed()` aufgerufen
  - Then: `{&"berry": 3}` — unabhängig von `get_last_day_deltas()`
  - Edge cases: Kein Hunger-Signal gefeuert → `get_last_hunger_consumed()` gibt `{}` zurück

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/ui/day_ledger_test.gd` — muss existieren und bestehen
**Status**: [ ] Nicht erstellt

---

## Dependencies

- Depends on: InventorySystem (item_deposited/item_withdrawn Signale müssen existieren), HungerSystem (food_consumed_daily Signal muss existieren), TickSystem.day_transition
- Unlocks: Story 008 (Day Overview Panel)

## Completion Notes
**Completed**: 2026-06-03
**Criteria**: 5/5 passing (all ACs auto-verified)
**Deviations**: None
**Test Evidence**: Logic — `tests/unit/ui/day_ledger_test.gd` (11 test functions, all ACs covered)
**Code Review**: Skipped — Lean mode
