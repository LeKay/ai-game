# Balancing-Analyse: Game Loop "From Scratch"

*Erstellt: 2026-06-11 · Quelle: Simulation `tools/balance/economy_sim.py` (liest die realen
GDScript-Werte, nicht die GDD-Absicht). Lauf: `python tools/balance/economy_sim.py`.*

> **Umsetzungsstand 2026-06-11:** Die Balance-Werte + Formeln unten sind in den Code
> eingearbeitet (Tests bewusst noch nicht angepasst; kein Godot-Binary lokal → unverifiziert
> durch Lauf). Eingearbeitet: Nutrition-Feld (resources.json) + `efficiency_from_nutrition`-Kurve
> (2026-06-12 v3: Effizienz hängt an der GESAMT-Nutrition/Tag = Menge × Nahrungswert, Futter-Beitrag
> auf +0.75 gedeckelt → `0.25 + min(0.15×total, 0.75)`, max 100% aus Futter; 5 Nutrition = 100% →
> 5 Beeren == 1 Brot (nutrition 5) == 100%, kein Over-Feeding; NPC-Panel zeigt „Nutrition: x/y");
> Adjazenz-Formel `clamp(0.5+0.25·tiles, 0.5, 1.5)` + Adjazenz×Futter
> kombiniert; F3 verdrahtet (`_try_start_production_cycle`); Werkzeug-Haltbarkeit `charge_cost=1/30`
> (1 Werkzeug ≈ 30 Zyklen); Zeit-Rescale (Bau ×8–12, Zyklen ×2.5 = 250/375); Werkzeug-Craft 90 Ticks;
> `CARRIER_CAPACITY = 5`. **Transport (2026-06-11):** `TICKS_PER_TILE` 3 → 10 (synchron in
> Logistics/NPC/Building + UI-Panels lesen jetzt `LogisticsSystem.TICKS_PER_TILE`); F4 verdrahtet —
> Carrier-Reise skaliert mit Carrier-Futter (`_set_carrier_state`), Worker-Reise in `_compute_travel_path`.
> **Offen (User-Task):** geteilter Carrier-Pool (1 NPC, viele Routen).
> **Feel-Hinweis:** frisch zugewiesener Worker/Carrier hat NPC-Eff 0.5 bis zur
> ersten Tageswechsel-Fütterung → Gebäude starten halb so schnell, bis gefüttert (Auto-Futter-UX erwägen).

Diese Analyse modelliert **was der Code tatsächlich tut**, nicht was die GDDs beschreiben.
Mehrere Design-Mechaniken aus dem Game-Concept sind im Code **nicht** (oder anders) realisiert.
Das ist der Kern der Balancing-Probleme.

---

## TL;DR — die 4 wichtigsten Befunde

1. **Werkzeuge sind ein Pro-Zyklus-Verbrauch statt Kapital.** Im Code liefert 1 Werkzeug
   genau **1.0 Charge = 1 Produktionszyklus** (nicht 100, wie `max_charge` suggeriert). Ein
   Lumber Camp frisst also 1 Werkzeug alle 100 Ticks. Folge: der Werkzeug-Strang ist eine
   gnadenlose Steuer — die Standard-Dorf-Kette läuft mit **−13.3 Werkzeug/1000t ins Defizit**
   und bräuchte **~1.5 Tool-Workshops pro Lumber Camp** (jeder mit eigenem NPC). Das ist der
   Haupt-Balancing-Bug.

2. **Das gesamte Effizienz-/Hunger-System ist wirkungslos.** `calculate_effective_cycle_ticks`
   (F3) und `calculate_effective_travel_ticks` (F4) werden **nirgends in `src/` aufgerufen**
   (nur in Tests/ADRs/offenen Stories 003+004). Effizienz wird berechnet und im UI angezeigt,
   beeinflusst aber **keine** Produktionsdauer. Damit hat Füttern/Hunger **null** Gameplay-Effekt —
   die zentrale "meditative Optimierungs"-Schleife der MDA-Analyse existiert mechanisch nicht.

3. **NPCs/Carrier sind der echte Expansions-Flaschenhals — aus den falschen Gründen.** Die
   Architektur "1 Input-Carrier + 1 Output-Carrier pro Route" verlangt für ein winziges
   4-Gebäude-Dorf **13 NPCs** (4 Worker + 4 Output-Carrier + 5 Input-Carrier). Bei 2 NPC/Haus
   sind das ~7 Häuser nur für Logistik-Overhead. Expansion wird durch Carrier-Buchhaltung
   blockiert, nicht durch interessante Layout-Optimierung (verfehlt Pillar 3).

4. **Energie/Erschöpfung beißt nie.** `pick_berries` kostet 5 Energie und liefert 3 Beeren =
   30 Energie beim Essen → **netto +25 Energie pro Aktion**. Solange ein Beeren-Tile existiert,
   ist Energie selbstlösend. Die "strategische Energie-Entscheidung" aus dem GDD passiert nicht.

Sekundär: **Bootstrap bis zur ersten Automatisierung ~950 Ticks (~1.6 min reine Spielzeit)** —
sehr schnell. Vertretbar für niedrige Einstiegshürde, untergräbt aber Pillar 1 ("Earned
Automation"), wenn die manuelle Lernphase praktisch sofort vorbei ist.

---

## Die reale Ökonomie (aus dem Code extrahiert)

**Zeit:** 1440 Ticks/Tag (Code), nicht 1000 (GDD). 10 Ticks/s @ 1x.

**Manuelle Aktionen** (Spieler, Energie 0–100; bei 0 Energie 2× Ticks, 0.5× Output):

| Aktion | Ticks | Energie | Output | Werkzeug? |
|---|---|---|---|---|
| forage | 50 | 8 | 1 zufällig (25% je W/S/Beere/Faser) | nein |
| pick_berries | 40 | 5 | 3 Beeren | nein |
| harvest_fiber | 45 | 6 | 2 Faser | nein |
| chop_tree | 80 | 12 | 5 Holz | **ja** |
| mine_stone | 60 | 10 | 3 Stein | **ja** |

**Werkzeug-Rezept (realer UI-Pfad `CraftingRegistry.try_craft`):** 2 Holz + 1 Stein + 1 Faser
+ 15 Energie, **instant** (0 Ticks). *(Die manuelle Aktion `CRAFT_TOOL` mit 100 Ticks und ohne
Materialkosten ist totes Legacy — an kein UI angebunden.)*

**Gebäude (Produktion, je 1 NPC nötig):**

| Gebäude | Baukosten | Zyklus | Input/Zyklus | Output/Zyklus |
|---|---|---|---|---|
| Gathering Hut | 5W+2S | 100t | — | 3 Beeren + 2 Faser |
| Lumber Camp | 15W+3S | 100t | 1 Werkzeug | 5 Holz |
| Stone Mason | 10W+5S | 100t | 1 Werkzeug | 5 Stein |
| Tool Workshop | 10W+5S | 150t | 2W+1S+1F | 1 Werkzeug |

**Logistik:** 3 Ticks/Tile, Carrier-Kapazität **1 Item/Fahrt**, Output-Buffer 20.

---

## Befund-Details mit Zahlen

### B1 — Werkzeug-Charge nicht realisiert (kritisch)

`resources.json` gibt Werkzeug `max_charge: 100`, und `add_charge_to_input()` würde die volle
Charge übergeben — **wird aber nie aufgerufen**. Der reale Pfad (Logistik `_do_deposit` und
manuelles Laden in `map_root`) nutzt `receive_input_from_world(building, res, 1)` → addiert
`float(1)` = **1.0 Charge**. Der Zyklus zieht 1.0 ab. Also **1 Werkzeug = 1 Zyklus**.

Steady-State des Standard-Dorfs (1× jede Gebäudeart), `tool_charge=1`:

```
NET /1000t:  wood +36.7   stone +43.3   fiber +13.3   berry +30.0   tool -13.3  <-- DEFIZIT
```

Ein Tool Workshop macht 6.7 Werkzeuge/1000t; Lumber+Stone fressen 20/1000t. → Man braucht
3 Workshops (+3 NPC +3 Worker) nur um 1 Lumber + 1 Stone zu betanken. Die Kette frisst sich
selbst auf.

**Sensitivitäts-Sweep (Workshops nötig pro Lumber Camp):**

| tool_charge | Werkzeuge/1000t | Workshops/Lumber Camp | Netto-Holz/1000t |
|---|---|---|---|
| **1 (aktuell)** | 10.0 | **1.50** | 30.0 |
| 5 | 2.0 | 0.30 | 46.0 |
| 30 | 0.33 | 0.05 | 49.3 |
| 100 (Design) | 0.1 | 0.01 | 49.8 |

### B2 — Effizienz/Hunger wirkungslos (kritisch)

`grep calculate_effective_cycle_ticks src/` → **kein Treffer**. `BuildingRegistry`
nutzt `calculate_cycle_duration()` (gibt `base_cycle_ticks` unverändert zurück). Folge:

- Gefütterter vs. ungefütterter NPC: **identische** Produktionsgeschwindigkeit.
- Adjazenz-Effizienz (F6) wird berechnet und im UI gezeigt, aber **nicht** auf den Zyklus
  angewandt.
- `HungerSystem.apply_daily_consumption` verbraucht täglich Nahrung und setzt food_modifier —
  der Effekt versickert. **Beeren zu produzieren hat aktuell keinen mechanischen Nutzen.**

**Falle beim Verdrahten:** Würde man F3 **mit der aktuellen F6-Formel** (`tiles × 0.25`)
einfach anschalten, bräuchte ein Gebäude **4 angrenzende Ressourcen-Tiles** für volle Speed.
Bei 1–2 Nachbar-Tiles liefe alles auf 0.25–0.5 Effizienz → Produktion halbiert/geviertelt.
Die Simulation zeigt: naives Anschalten macht es **schlechter**. Die Adjazenz-Kurve muss
gleichzeitig gefixt werden (siehe Empfehlung E2).

### B3 — Carrier-Overhead sprengt das NPC-Budget (strukturell)

Pro Produktionsgebäude: 1 Worker + 1 Output-Carrier + 1 Input-Carrier je Input-Slot. Für das
4-Gebäude-Dorf: **4 + 4 + 5 = 13 NPCs**, aber nur 4 NPC bei 2 Häusern. → 9 NPC zu wenig,
~5 zusätzliche Häuser nur für Logistik. Carrier-Kapazität 1 verschärft das: bei 8 Tiles
Distanz schafft 1 Carrier nur **20.8 Items/1000t**, ein Lumber Camp wirft aber **50 Holz/1000t**
aus → Output-Buffer (20) läuft voll → Gebäude **stallt**. Distanz ist eine harte Wand statt
einer sanften Optimierung.

### B4 — Energie ist selbstlösend (Design-Schwäche)

Netto +25 Energie pro `pick_berries`. Erschöpfung (0 Energie → 2× Ticks) tritt im normalen
Spiel nie ein. Der "Energie sparen vs. schnell arbeiten"-Loop aus dem GDD ist mechanisch tot.

### B5 — Bootstrap sehr kurz

Hand → 1. Werkzeug → Gathering Hut + Haus + NPC ≈ **950 Ticks ≈ 1.6 min**. Schneller als die
GDD-Annahme (~4 Tage). Gut für Zugänglichkeit, schwach für "verdiente Automatisierung".

---

## Empfehlungen (priorisiert)

### E1 — Werkzeug zu Kapital machen *(kritisch, kleiner Aufwand)*
Charge realisieren: beim Liefern/Laden eines Werkzeugs dessen `current_charge` (Default via
`max_charge`) in den `input_buffer` schreiben statt `1.0`. Konkret `add_charge_to_input()`
im Logistik-`_do_deposit` und im `map_root`-Pfad nutzen. **Empfohlener Wert: charge 30–40**
(nicht die vollen 100 — sonst wird der Werkzeug-Strang trivial). Bei 30: ~0.05 Workshops pro
Lumber Camp, Netto-Holz 49.3/1000t, Werkzeug-Bilanz **positiv**. Macht den Tool Workshop zur
seltenen Investition statt zum Tretrad.

### E2 — Effizienz verdrahten *und* Adjazenz-Kurve fixen *(kritisch)*
Stories 003+004 (F3/F4) abschließen, **aber gleichzeitig** die F6-Formel ändern:
`eff = clamp(0.5 + 0.25 × tiles, 0.5, 1.5)`. Damit: 1 Nachbar = 0.75 (läuft), 2 = 1.0 (gut),
4 = 1.5 (Belohnung für enges Layout). Kein Gebäude stallt allein durch Map-Geometrie.
Erst danach hat Füttern Sinn (gefüttert 1.0 vs. ungefüttert 0.5 → halbe Speed) — und der
Hunger-Loop wird real.

### E3 — Carrier-Architektur entlasten *(strukturell, Design-Entscheidung nötig)*
Tuning allein löst die 13-NPC-Last nicht. Optionen (eine wählen):
- **Carrier-Kapazität 5** (statt 1): Distanz wird Optimierung statt Wand. Simulation: 1 Carrier
  schafft dann 104 Items/1000t > 50 Holz/1000t → kein Stall. *(Schnellster Hebel.)*
- **Geteilter Carrier-Pool** statt 1 NPC pro Route: ein Carrier bedient mehrere Gebäude.
- **Input-Carrier entfallen lassen, wenn Tool-Charge hoch** (E1): seltene Tool-Lieferung
  braucht keinen Dauer-NPC; gelegentliche Lieferung aus dem Worker-Pool reicht.

Empfehlung: **Kapazität 5 + E1** zuerst (kleinste Eingriffe, größte Wirkung), Pool-Architektur
als spätere ADR.

### E4 — Energie schärfen *(optional, niedrige Prio)*
Entweder Beeren-Energie senken (10 → 4) **oder** Aktionskosten erhöhen, sodass Beeren-Picking
energie-neutral statt stark positiv ist. Nur sinnvoll, wenn der Energie-Loop überhaupt
Designziel bleibt — sonst Energie ganz streichen und Tempo nur über Ticks steuern.

### E5 — Bootstrap leicht strecken *(optional)*
Wenn "Earned Automation" wichtig ist: erste Automatisierung an einen kleinen Meilenstein
koppeln (z. B. Gathering Hut zusätzlich 1 Werkzeug verlangen, oder Baukosten leicht anheben),
sodass der manuelle Teil ~2–3 min dauert statt ~1.6.

---

## Verifizierter Ziel-Zustand (PROPOSED-Config)

`python tools/balance/economy_sim.py --proposed` mit E1 (charge 30) + E2 (Effizienz an, Adjazenz
gefixt) + E3 (Kapazität 5):

```
NET /1000t:  wood +36.7   stone +43.3   fiber +13.3   berry +40.0   tool +6.0  (alle positiv)
Carrier @ 8 Tiles: 104 Items/1000t > 50 Holz/1000t  -> kein Stall
Gebäude-Effizienz 1.0 bei normaler Platzierung; Füttern/Layout heben/senken sie spürbar
```

Offen bleibt das NPC-Budget (13) — das ist die eine **Architektur-Entscheidung** (E3-Variante),
die das Spiel als Nächstes braucht, damit Expansion von Layout-Optimierung getrieben wird statt
von Carrier-Buchhaltung.

---

## Wie die Simulation gepflegt wird

`economy_sim.py` liest die Werte als Konstanten (Stand 2026-06-11) — sie ist **kein** Live-Hook
in den Code. Bei Balance-Änderungen die `Config`-Defaults (= CURRENT) nachziehen, oder die
`proposed_config()` als Experiment anpassen. Jede Zahl ist mit der Quelldatei kommentiert.
```
python tools/balance/economy_sim.py             # CURRENT vs PROPOSED nebeneinander
python tools/balance/economy_sim.py --current    # nur Live-Code
python tools/balance/economy_sim.py --proposed    # nur Tuning
```
