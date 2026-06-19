# Quick Design Spec: Efficiency System

> **SUPERSEDED (2026-06-13)** by `design/gdd/efficiency-system.md` (full GDD, synced
> to the implementation) and ADR-0012 Amendment 2026-06-13. Key deviations from this
> spec as built: NPC base efficiency 0.5 (not 1.0), nutrition curve instead of binary
> hunger modifier, building cap 1.0 (not 2.0), added adjacency curve F6, constants not
> yet externalized to JSON config. Kept for design history.

**Type**: New Small System
**Scope**: Ein numerischer Effizienz-Wert (0.0–2.0, Basis 1.0) auf Gebäuden und NPCs.
Gebäude: Effizienz beschleunigt Produktionszyklen. Worker-NPCs: tragen ihre Effizienz-Delta
zum zugewiesenen Gebäude bei. Transport-NPCs: Effizienz beschleunigt Reisezeit.
Quellen: Ausrüstung, Upgrades, Hunger-Modifikator, Zufriedenheits-Modifikator.
**Date**: 2026-06-03
**Estimated Implementation**: 2–3 Tage (Patches an Building, NPC, Logistics, Hunger System)

---

## Overview

Das Effizienz-System ist die vereinheitlichte Schicht für "wie gut läuft ein
Gebäude oder NPC gerade?" statt isolierter Debuffs. Jeder NPC trägt eine
`efficiency: float` — Basis 1.0, modifiziert durch Hunger, Zufriedenheit und
Ausrüstung. Worker-NPCs übertragen ihre Effizienz-Delta an ihr zugewiesenes
Gebäude; das Gebäude beschleunigt oder verlangsamt seinen Produktionszyklus
entsprechend. Carrier-NPCs beschleunigen oder verlangsamen ihre Reisezeit.
Bei Effizienz 2.0 produziert ein Gebäude doppelt so schnell; bei 0.5
halbiert sich die Geschwindigkeit — dasselbe Ergebnis wie der bisherige
Hunger-Debuff, aber jetzt durch ein einheitliches System ausgedrückt.

---

## Core Rules

**Rule 1 — Effizienz als Geschwindigkeitsmultiplikator**
Effizienz teilt Tick-Dauer — höhere Effizienz = kürzere Zyklen.
`effective_ticks = floor(base_ticks / efficiency)` (Minimum: 1 Tick)

**Rule 2 — NPC-Effizienz (Quellen, multiplikativ)**
```
npc.efficiency = clamp(
    1.0 * hunger_modifier * satisfaction_modifier * equipment_modifier,
    0.0, 2.0
)
```
- `hunger_modifier`: 1.0 (fed) / 0.5 (hungry) — ersetzt den bisherigen Hunger-Debuff
- `satisfaction_modifier`: 1.0 Standard, Bereich 0.8–1.2 (nach Zufriedenheitssystem)
- `equipment_modifier`: 1.0 Standard, Bereich 0.5–2.0 (nach Equipment-System)

**Rule 3 — Building-Effizienz (Worker-Beiträge + Upgrades)**
```
building.efficiency = clamp(
    1.0 + sum(worker.efficiency - 1.0 for worker in assigned_workers)
        + upgrade_bonus,
    0.0, 2.0
)
```
- Kein Worker → Effizienz bleibt 1.0
- Worker mit Effizienz 0.5 (hungrig) → −0.5 Delta → Gebäude bei 0.5
- Worker mit Effizienz 1.2 (zufrieden) → +0.2 Delta → Gebäude bei 1.2
- `upgrade_bonus`: 0.0 zum VS-Scope, +0.25 pro Upgrade-Stufe (future)

**Rule 4 — Produktionszyklus (Building)**
```
effective_cycle_ticks = max(1, floor(base_cycle_ticks / building.efficiency))
```
Beim VS-Scope gilt: Hunger → npc.efficiency = 0.5 → building.efficiency = 0.5
→ cycle_ticks × 2 — gleich wie bisherige Hunger-System-Implementierung.

**Rule 5 — Reisezeit (Carrier/Transport NPC)**
```
effective_travel_ticks = max(1, floor(base_travel_ticks / carrier.efficiency))
```
Carrier mit Effizienz 2.0: halbe Reisezeit, doppelter Durchsatz.

**Rule 6 — Lesbarkeit für UI**
`efficiency >= 1.0` → grün (normal oder besser)
`0.5 <= efficiency < 1.0` → gelb (beeinträchtigt)
`efficiency < 0.5` → rot (stark beeinträchtigt)
Bereits etabliert in logistics-system.md — hier auf alle Effizienz-Werte ausgedehnt.

---

## Formulas

**F1 — NPC-Effizienz:**
```
npc.efficiency = clamp(1.0 × hunger_mod × satisfaction_mod × equipment_mod, 0.0, 2.0)
```
Beispiel: Hungry (0.5) × Zufrieden (1.1) × Kein Equipment (1.0) = 0.55

**F2 — Building-Effizienz:**
```
building.efficiency = clamp(1.0 + Σ(worker.efficiency − 1.0) + upgrade_bonus, 0.0, 2.0)
```
Beispiel: 1 Worker mit 0.55 eff → 1.0 + (0.55 − 1.0) = 0.55

**F3 — Effektive Zyklusdauer:**
```
effective_cycle_ticks = max(1, floor(base_cycle_ticks / building.efficiency))
```
Beispiel: base=100, eff=0.55 → floor(100/0.55) = floor(181.8) = 181 Ticks

**F4 — Effektive Reisezeit:**
```
effective_travel_ticks = max(1, floor(base_travel_ticks / carrier.efficiency))
```
Beispiel: base=62, eff=1.2 → floor(62/1.2) = floor(51.6) = 51 Ticks

---

## Tuning Knobs

Alle Werte leben in `assets/data/efficiency-config.json` — kein Hardcode.

| Knob | Default | Range | Category | Rationale |
|------|---------|-------|----------|-----------|
| `base_efficiency` | 1.0 | 0.1–2.0 | feel | Neutraler Ausgangswert |
| `efficiency_min` | 0.0 | 0.0–0.5 | gate | Bodenlimit; 0.0 = Gebäude produziert nie fertig |
| `efficiency_max` | 2.0 | 1.5–3.0 | curve | Oberlimit gegen Overpowered-Equipment |
| `hunger_modifier_fed` | 1.0 | 0.8–1.0 | feel | Kein Bonus für ausreichend Essen |
| `hunger_modifier_hungry` | 0.5 | 0.1–0.8 | feel | Übernimmt bisherigen Hunger-Debuff |
| `satisfaction_modifier_min` | 0.8 | 0.5–1.0 | curve | Penalty bei tiefer Zufriedenheit |
| `satisfaction_modifier_max` | 1.2 | 1.0–1.5 | curve | Bonus bei hoher Zufriedenheit |
| `upgrade_bonus_per_tier` | 0.25 | 0.1–0.5 | curve | +0.25 pro Upgrade-Stufe (future) |

---

## Affected Systems

| System | Impact | Action Required |
|--------|--------|-----------------|
| Building System | `cycle_ticks` wird durch `building.efficiency` geteilt | Formel 3 einbauen in Produktionszyklus |
| NPC System | `efficiency: float` Property auf NPC-Klasse; Rule 6 Placeholder füllen | Property hinzufügen, Hunger-Patch-Hook |
| Hunger System | `hunger_modifier` Callback an NPC statt direktem 2×-Debuff | Debuff-Implementierung auf Effizienz-API umstellen |
| Logistics System | Carrier-Reisezeit via Formel 4; ersetzt Story-007-Effizienz-Input | `carrier.efficiency` in travel_ticks Berechnung |
| Route Visualization | Bereits grün/gelb/rot — nur Schwellenwerte ggf. anpassen | Evtl. building.efficiency auch anzeigen |

---

## Acceptance Criteria

- [ ] NPC besitzt `efficiency: float` Property (default 1.0)
- [ ] NPC-Effizienz berechnet sich aus hunger_modifier × satisfaction_modifier × equipment_modifier, geclampt [0.0, 2.0]
- [ ] Hungriger NPC hat efficiency = 0.5 (ersetzt bisherigen 2×-Tick-Debuff im Hunger System)
- [ ] Gebäude berechnet `building.efficiency` als 1.0 + Σ Worker-Delta + upgrade_bonus
- [ ] Gebäude ohne Worker behält efficiency = 1.0
- [ ] Produktionszyklus: `effective_cycle_ticks = max(1, floor(base_cycle_ticks / building.efficiency))`
- [ ] Carrier-Reisezeit: `effective_travel_ticks = max(1, floor(base_travel_ticks / carrier.efficiency))`
- [ ] Alle Werte aus `assets/data/efficiency-config.json`, kein Hardcode
- [ ] UI: efficiency ≥ 1.0 grün, 0.5–1.0 gelb, < 0.5 rot
- [ ] Kein Regression: bisherige Hunger-Debuff-Logik wird durch Effizienz-System ersetzt, nicht dupliziert
- [ ] Unit-Test: F1–F4 jeweils mit Randwerten (hunger=0.5, equipment=2.0, building mit 0 / 1 / 2 Workern)

---

## Systems Index

Dieses System gehört in `design/gdd/systems-index.md`:
- **Layer**: 4 (Core Gameplay — hängt von NPC System + Building System ab)
- **Priority**: Core Experience
- **Vorgeschlagene Zeile:**
  `| 30 | Efficiency System | Gameplay | Core Experience | Not Started | — | NPC System, Building System, Hunger System, Logistics System |`

---

## GDD Updates Required?

**Ja — drei Stellen:**
1. `design/gdd/npc-system.md` — Rule 6: Placeholder füllen
2. `design/gdd/hunger-system.md` — Rule 3: Debuff-Implementierungsdetail auf Effizienz-API umstellen
3. `design/gdd/systems-index.md` — Effizienz-System als System #30 eintragen
