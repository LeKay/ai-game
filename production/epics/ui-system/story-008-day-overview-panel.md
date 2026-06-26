# Story 008: Day Overview Panel

> **Epic**: UI System
> **Status**: Complete
> **Layer**: Presentation
> **Type**: UI
> **Manifest Version**: 2026-05-14

## Context

**GDD**: `design/gdd/tick-system.md` (Day Transition — Section 5)
**Requirement**: `TR-ui-007`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0003: Input Context System
**ADR Decision Summary**: UI-Screens pushen `Context.UI_ACTIVE` beim Öffnen und poppen
beim Schließen — Welt-Input wird währenddessen gesperrt. `grab_focus()` nach `show()`
setzt Keyboard-Focus auf den Bestätigungs-Button.

**Engine**: Godot 4.6 | **Risk**: MEDIUM
**Engine Notes**: Dual-Focus (4.6): `grab_focus()` setzt nur Keyboard-Focus, nicht
Mouse-Hover — beide Pfade müssen getestet werden. `ItemList` oder `VBoxContainer`
mit dynamisch erzeugten Labels für die Ressourcen-Listen verwenden.

**Control Manifest Rules (Presentation Layer)**:
- Required: `InputContext.push_context(Context.UI_ACTIVE)` beim Panel-Open; `pop_context()` beim Dismiss
- Required: Y-sort und Layer-Ordnung via `CanvasLayer.layer` — Panel über Spielwelt
- Forbidden: Kein direkter Welt-Input-Zugriff während Panel sichtbar ist

---

## Acceptance Criteria

*Abgeleitet aus tick-system.md Section 5 und DayLedger-API (Story 007):*

- [ ] **AC-1**: Bei `TickSystem.day_transition` erscheint das Panel mit Tageszahl (`TickSystem.get_current_day()`) und NPC-Anzahl (`NPCSystem.get_npc_count()`)
- [ ] **AC-2**: Abschnitt "Tageskonsum" zeigt alle Items aus `DayLedger.get_last_hunger_consumed()` als Liste (Name + Menge); bei leerem Dictionary: Hinweistext "Keine Nahrung verbraucht"
- [ ] **AC-3**: Abschnitt "Tagesbilanz" zeigt alle Einträge aus `DayLedger.get_last_day_deltas()` — positive Werte grün mit "+N", negative Werte rot mit "−N"; bei leerem Dictionary: Hinweistext "Keine Änderungen"
- [ ] **AC-4**: Beim Erscheinen wird `InputContext.push_context(UI_ACTIVE)` aufgerufen; "Nächster Tag"-Button erhält Keyboard-Focus via `grab_focus()`
- [ ] **AC-5**: Klick oder Enter auf "Nächster Tag" → Panel blendet aus, `InputContext.pop_context()`, `TickSystem.set_pause(false)`
- [ ] **AC-6**: Kein Doppel-Panel — wenn Panel bereits sichtbar ist, wird ein weiteres `day_transition`-Signal ignoriert

---

## Implementation Notes

*Abgeleitet aus ADR-0003 Input Context + tick-system.md Section 5:*

Panel ist ein `CanvasLayer` (layer = 10) als Kind der Hauptszene. Szenenbaum:

```
DayOverviewPanel (CanvasLayer, layer=10)
  └─ PanelContainer
       └─ VBoxContainer
            ├─ HBoxContainer
            │    ├─ Label _day_label        ← "Tag N"
            │    └─ Label _npc_label        ← "N Bewohner"
            ├─ HSeparator
            ├─ Label "Tageskonsum"
            ├─ VBoxContainer _hunger_list   ← dynamisch befüllt
            ├─ HSeparator
            ├─ Label "Tagesbilanz"
            ├─ VBoxContainer _delta_list    ← dynamisch befüllt
            └─ Button _next_day_btn         ← "Nächster Tag"
```

```gdscript
func _ready() -> void:
    hide()
    TickSystem.day_transition.connect(_on_day_transition)
    _next_day_btn.pressed.connect(_on_next_day_pressed)

func _on_day_transition(_days: int) -> void:
    if visible:
        return  # AC-6
    _populate()
    show()
    InputContext.push_context(InputContext.Context.UI_ACTIVE)
    _next_day_btn.grab_focus()

func _populate() -> void:
    _day_label.text = "Tag %d" % TickSystem.get_current_day()
    _npc_label.text = "%d Bewohner" % NPCSystem.get_npc_count()
    _fill_resource_list(_hunger_list, DayLedger.get_last_hunger_consumed(), false)
    _fill_resource_list(_delta_list, DayLedger.get_last_day_deltas(), true)

func _fill_resource_list(container: VBoxContainer, data: Dictionary, show_sign: bool) -> void:
    for child in container.get_children():
        child.queue_free()
    if data.is_empty():
        var lbl := Label.new()
        lbl.text = "Keine Änderungen" if show_sign else "Keine Nahrung verbraucht"
        container.add_child(lbl)
        return
    for resource_id: StringName in data:
        var qty: int = data[resource_id]
        var lbl := Label.new()
        var name_str: String = ResourceRegistry.get_definition(resource_id).display_name
        lbl.text = ("+%d %s" % [qty, name_str]) if qty >= 0 else ("-%d %s" % [abs(qty), name_str])
        if show_sign:
            lbl.modulate = Color.GREEN if qty >= 0 else Color.RED
        container.add_child(lbl)

func _on_next_day_pressed() -> void:
    hide()
    InputContext.pop_context()
    TickSystem.set_pause(false)
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 007: DayLedger (muss DONE sein bevor diese Story beginnt)
- Animationen / Fade-In (defer auf Polish-Phase)
- Lokalisierung (hardcodierte Strings für Vertical Slice)
- Produktions-Statistiken pro Gebäude (kein GDD-Requirement für VS)

---

## QA Test Cases

*UI-Story — manuelle Verifikation.*

- **AC-1**: Tageszahl und NPC-Count korrekt
  - Setup: Spiel auf Tag 3 mit 2 NPCs, Zeitraffer bis Tag-Wechsel
  - Verify: Panel erscheint mit "Tag 4" und "2 Bewohner"
  - Pass: Beide Werte stimmen exakt mit Spielstand überein

- **AC-2**: Tageskonsum-Liste korrekt
  - Setup: HungerSystem hat 3 Beeren + 1 Brot konsumiert im letzten Tag
  - Verify: Liste zeigt "Beere ×3" und "Brot ×1" (oder entsprechende display_name-Werte)
  - Pass: Keine leere Liste, keine Duplikate; bei 0 NPCs erscheint Hinweistext

- **AC-3**: Tagesbilanz grün/rot mit Vorzeichen
  - Setup: 10 Holz produziert (deposit), 2 Beeren verbraucht (withdraw) im letzten Tag
  - Verify: "+10 Holz" in grün, "−2 Beere" in rot
  - Pass: Farben und Vorzeichen korrekt; bei keinen Änderungen erscheint Hinweistext

- **AC-4**: Button erhält Focus
  - Setup: Panel öffnet sich (Keyboard-Nutzer)
  - Verify: "Nächster Tag"-Button ist sofort mit Enter bedienbar ohne Tab-Druck
  - Pass: `_next_day_btn.has_focus() == true` unmittelbar nach Panel-Open

- **AC-5**: Button schließt Panel und startet Tag
  - Setup: Panel offen — einmal mit Mausklick testen, einmal mit Enter
  - Verify: Panel verschwindet, Ticks laufen wieder
  - Pass: `TickSystem.is_paused() == false` und Panel `visible == false`

- **AC-6**: Kein Doppel-Panel
  - Setup: Panel bereits sichtbar
  - Verify: Manuell `day_transition.emit(1)` auslösen
  - Pass: Kein zweites Panel-Layer erscheint; genau ein Panel sichtbar

---

## Test Evidence

**Story Type**: UI
**Required evidence**: `production/qa/evidence/day-overview-panel-evidence.md`
  (Screenshot des Panels + Walkthrough-Notizen für alle 6 ACs)
**Status**: [ ] Nicht erstellt

---

## Dependencies

- Depends on: Story 007 (DayLedger) muss DONE sein
- Unlocks: Vollständiger Tag-Zyklus-Flow spielbar (Tag-Wechsel → Summary → Weiter)

---

## Completion Notes
**Completed**: 2026-06-03
**Criteria**: 6/6 passing (all confirmed — AC-1 through AC-6)
**Deviations**: None
**Test Evidence**: UI — evidence placeholder at `production/qa/evidence/day-overview-panel-evidence.md`; all ACs manually confirmed in-game
**Code Review**: Skipped (Lean mode)
