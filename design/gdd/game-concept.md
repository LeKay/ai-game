# Game Concept: From Scratch

*Created: 2026-05-04*
*Status: Draft*

---

## Elevator Pitch

> Du startest mit nichts als deinen Händen in der Wildnis und baust Schritt für Schritt ein blühendes mittelalterliches Dorf auf — von manueller Holzfäller-Arbeit bis zu komplexen, automatisierten Produktionsnetzwerken mit spezialisierten NPCs und weitreichendem Handel.

---

## Core Identity

| Aspect | Detail |
| ---- | ---- |
| **Genre** | 2D Village Builder / Production Chain Management / Survival Automation |
| **Platform** | PC (Steam / Epic) |
| **Target Audience** | Achievement Hunters, Systems Optimizers, Management-Enthusiasten |
| **Player Count** | Single-player |
| **Session Length** | 1-3 Stunden (typisch), unbegrenzt möglich |
| **Monetization** | Premium (Einmalkauf) |
| **Estimated Scope** | **Hobby-Projekt, keine fixen Deadlines.** Vertical Slice (6-8 Wochen) → MVP (TBD) → Core Experience (Early Access) → Full Vision (1.0) |
| **Comparable Titles** | Factorio (Optimierung), Anno (Bevölkerungstiers + Produktionsketten), Rimworld (begrenzte Karte + Management), Card Survival: Tropical Island (Start from Zero) |

---

## Core Fantasy

**Du bist der visionäre Gründer eines mittelalterlichen Dorfs** — jemand, der mit den eigenen Händen das erste Holz hackt und Jahre später ein summende Produktionsimperium leitet, in dem Dutzende spezialisierter NPCs komplexe Handelsnetzwerke bedienen. Du erlebst die **befriedigende Transformation von manueller Arbeit zu strategischem Management**, wo jede Automatisierung verdient wurde und jeder Bottleneck, den du behebst, spürbare Ergebnisse bringt.

Die Macht liegt darin, **ineffiziente Prozesse zu erkennen und zu perfektionieren** — von "ich trage jedes Stück Holz selbst" zu "mein Dorf produziert 500 Bretter pro Tag ohne mein Zutun".

---

## Unique Hook

**Wie Factorio's Optimierung, AND ALSO du beginnst als einzelner Charakter, der buchstäblich jeden Schritt selbst gehen muss** — keine sofortige God-View, sondern echte Progression von "ich hacke selbst Holz" zu "ich manage 50 NPCs in 20 Werkstätten". Der Übergang von manueller Arbeit zu Automatisierung ist fließend statt abrupt.

**AND ALSO:** NPCs haben **Perks, die nur aktiv sind, wenn bestimmte Waren verfügbar sind** (Anno-Style Bevölkerungstiers) — du musst Luxusgüter produzieren, um die besten Handwerker zu aktivieren, was einen zweiten Optimierungs-Layer über die Produktionsketten legt.

---

## Player Experience Analysis (MDA Framework)

### Target Aesthetics (What the player FEELS)

| Aesthetic | Priority | How We Deliver It | Notes |
| ---- | ---- | ---- | ---- |
| **Submission** (relaxation, comfort zone) | **1 (PRIMARY)** | Pausierbare Zeit (meditatives Planen), kein Tod, exponentielles Wachstum ohne harte Bremsen, rhythmisches Sammeln | Aktuell umgesetzt |
| **Challenge** (obstacle course, mastery) | **2** | Optimierungspuzzles, Bottleneck-Hunting, Ressourcen-Management, Goal-driven Milestones | Aktuell umgesetzt. Später: Random events, NPC morale, optional Permadeath mode |
| **Discovery** (exploration, secrets) | **3** | Neue Produktionsketten freischalten, versteckte Perk-Synergien finden, Handelsnetzwerk-Möglichkeiten entdecken | Aktuell umgesetzt |
| **Fantasy** (make-believe, role-playing) | 4 | "Vom Holzfäller zum Dorfbaron" — spürbare Identitäts-Transformation | Aktuell umgesetzt |
| **Expression** (self-expression, creativity) | 5 | Dorf-Layout, Produktionsketten-Design (viele Lösungen für gleiche Probleme) | Aktuell umgesetzt |
| **Sensation** (sensory pleasure) | 6 | Minimalistisches 2D Art (Top-Down oder Isometric), sauberes UI, befriedigende Audio-Feedback bei Produktionsabschluss | Aktuell umgesetzt |
| **Narrative** (drama, story arc) | 7 | Keine Story — das Spiel erzählt sich durch Progression, nicht durch Text | Aktuell umgesetzt |
| **Fellowship** (social connection) | N/A | Singleplayer (evtl. Leaderboards später) | N/A |

### Key Dynamics (Emergent player behaviors)

**Gewünschte emergente Verhaltensweisen:**
- Spieler **theorycraften** Produktionsketten in Spreadsheets oder auf Papier, bevor sie bauen
- Spieler **experimentieren** mit NPC-Perk-Kombinationen, um optimale Setups zu finden
- Spieler **vergleichen** ihre Lösungen mit der Community (Screenshots, Effizienz-Scores)
- Spieler **iterieren** — sie reißen ineffiziente Layouts ab und bauen besser, nicht nur "mehr"
- Spieler **priorisieren** — bewusste Entscheidung "zuerst Nahrung stabilisieren, DANN Luxusgüter"

### Core Mechanics (Systems we build)

1. **Manual Labor → Architect Progression** — Pre-NPC: Spieler führt Aufgaben manuell aus (Holz hacken, Ressourcen transportieren). Sobald der erste NPC einem Gebäude zugewiesen wird, wechselt der Spieler permanent in den **Architect Mode**: alle manuellen Sammelaktionen werden gesperrt. Der Spieler ist ab dann nur noch Systemarchitekt — kein Hybrid, kein Rückfall. Der emotionale Höhepunkt ist der Moment, in dem der Spieler aufhört zu arbeiten, weil das System ohne ihn läuft.

2. **Dual Economy System:**
   - **Verbrauchsgüter** (Nahrung, Kleidung, Luxusgüter) — rate-basiert konsumiert von NPCs, bedienen Bevölkerungstiers
   - **Produktionswaren** (Rohstoffe, Werkzeuge, Zwischenprodukte) — Inputs für Crafting und Handel

3. **Bevölkerungstiers + Perk-System** — NPCs haben Tier-Anforderungen (Arbeiter brauchen nur Brot, Meister brauchen Luxusgüter). Perks (z.B. +50% Effizienz) sind nur aktiv, wenn bestimmte Waren verfügbar sind.

4. **Production Chain Management** — Sichtbare, debugbare Produktionsketten (Hover zeigt Status, Bottlenecks, Warenbewegung). Keine Black-Box-Systeme.

5. **Tick-Based Time System** — Zeit läuft nur wenn der Spieler Play drückt oder durch eigene Handlungen das Spiel weitertickt. Pause pausiert alles (Spieler + NPCs) bis Play gedrückt wird. Tag = 1000 Ticks. Nahrungsverbrauch wird täglich abgerechnet (nicht kontinuierlich).

6. **Player Energy System** — Der Spieler hat eine Energiebar (max 100 Energy), die sich mit jeder manuellen Aktion verringert. Nahrung (Beeren, Brot, etc.) füllt die Energie wieder auf. Hat der Spieler 0 Energy, funktionieren ALLE manuellen Aktionen nur noch mit 50% Effizienz (doppelte Tick-Kosten, halber Output). Energie ist ein strategisches Ressourcen-Management — nicht ein Survival-Timer, sondern eine Entscheidung: "Verbrauche ich jetzt Energie für schnelles Arbeiten, oder spare ich und esse erst später?"

6. **Hunger as Productivity Modifier** — Hunger ist KEIN Death-Timer. Bei Nahrungsmangel erhalten Spieler UND NPCs -50% Produktivitäts-Debuff (alle Aktionen kosten +50% Ticks, auch NPC-operated buildings). Ermöglicht meditative Planung ohne Survival-Stress.

8. **Tool-Based Production Chains** — Werkzeuge sind Produktionsketten-Inputs (nicht NPC-gebunden). Gebäude verbrauchen Werkzeug-Durability aus Lager. Realistische Progression: bare hands → simple tools → buildings → automation.

8. **Housing-Based Population** — NPCs kosten keine Ressourcen zur Rekrutierung. Wohnhäuser schaffen Lebensraum (1 Wohnhaus = 2 NPCs max). Neue NPCs erscheinen automatisch, wenn Wohnraum verfügbar.

9. **Rimworld-Style Map + Overmap** — Begrenzte Hauptkarte (30×30 Tiles, Layout-Planung wichtig) + Rimworld-style Übermap (NPCs reisen zwischen Tiles für Handel). Ressourcen benötigen Tiles — Anno-style Einzugsbereich um Gebäude (Beeren/Holz/Stein-Tiles müssen vorhanden sein, werden aber nicht erschöpft).

10. **Transport & Logistik (Anno-Prinzip, kein sichtbarer Spieler)** — Der Spieler ist NICHT als sichtbare Figur auf der Karte. Ressourcen erscheinen nach dem Abbau/Aufsuchen **auf dem Tile der Aktion** und müssen manuell in ein Lager verschoben werden. Jedes gebaute Gebäude benötigt gelieferte Ressourcen aus dem Lager — ohne Lager-Lieferung keine Produktion. Der Spieler definiert zu Beginn **einen Lager-Platz** (kostenlos, 20 Items Kapazität). Später können weitere Lager errichtet werden (+100 Kapazität pro Upgrade). Manuell verschobene Items verbrauchen Energy (0.5 Energy pro Item + 0.2 Energy pro Tile-Distanz) und Ticks (5 Ticks pro Transport). Später übernehmen NPCs den Transport automatisch. Das schafft einen zweiten Optimierung-Layer: "Wo platziere ich mein Lager für minimalen Transport-Aufwand?" und "Sammle ich gebündelt oder sofort?"

---

## Economic Foundation & Equilibrium Model

**Design-Prinzip:** Production chain games müssen mathematisch equilibrierbar sein. Diese Formeln sind die Grundlage aller Produktionsketten-GDDs.

### Tick-System Definition

| Parameter | Wert | Begründung |
|-----------|------|------------|
| **Ticks per Day** | 1000 | 1 Tag = 1000 Ticks (abstraktes Zeitmaß) |
| **Time Control** | Player-driven | Zeit läuft nur bei Play-Button oder manuellen Aktionen |
| **Day Transition** | Tick 1000 → Tick 0 | Verbrauchsgüter-Abrechnung am Tageswechsel |
| **Tick-to-Frame** | Real-time mit Speed-Modifiern | 1 real second = 10 Ticks (basis). Speed settings: 0.5x, 1x, 2x, 3x. Game loop akkumuliert Zeit pro Frame. Bei 3x = 30 Ticks/Sekunde |

### Verbrauchsgüter-Mechanik (Revised: No Death Timer)

**Hunger-System:**
```
Verbrauch: 1 Nahrungseinheit/Tag pro Entität (Spieler + NPCs)
Abrechnung: Bei Tageswechsel (Tick 1000 → Tick 0)
Mangel-Effekt: -50% Produktivität (alle Aktionen kosten +50% mehr Ticks)
Kein Tod: Spieler/NPCs sterben NICHT bei 0 Nahrung
```

**Warum kein Tod?** Ermöglicht "meditative Planung" (MDA: Submission aesthetic) ohne Survival-Stress. Hunger ist Optimierungs-Puzzle, nicht Überlebensdruck.

**Energy-System (Spieler):**
```
Start: 100 Energy (voll)
Max: 100 Energy | Min: 0 Energy (clamped — nie negativ)

Energie-Verbrauch pro Aktion (ohne Debuff):
  - Wiese durchsuchen:      10 Energy → Output: 1 Faser/Stein (50 Ticks)
  - Zweige sammeln:         8 Energy  → Output: 1 Holz (30 Ticks)
  - Beeren pflücken:        5 Energy  → Output: 3 Beeren (40 Ticks)
  - Werkzeug craften:       15 Energy → Output: 1 Werkzeug (100 Ticks)
  - Baum fällen:            12 Energy → Output: 5 Holz (80 Ticks)
  - Stein abbauen:          10 Energy → Output: 3 Stein (60 Ticks)
  - Wohnhaus bauen (manuell): 20 Energy → Bauzeit: 150 Ticks
  - Holzfällerhütte bauen:   25 Energy → Bauzeit: 200 Ticks

0 Energy Zustand:
  - Alle manuellen Aktionen: 2x Tick-Kosten (z.B. Beeren pflücken = 80 Ticks statt 40)
  - Alle manuellen Aktionen: 50% Output-Reduktion (z.B. Beeren pflücken = 1-2 Beeren statt 3)
  - UI-Hinweis: "Energy depleted — actions cost 2x time, yield 50% less"

Energy-Wiederauffüllung (durch Nahrung):
  - 1 Beere → +10 Energy (sofort)
  - 1 Brot → +25 Energy (sofort)
  - Maximal 100 Energy — Überschuss geht verloren
  - Nahrungsaufnahme kostet keine Aktionen/Ticks (automatisch bei Inventar-Verbrauch)
```

**Strategische Entscheidung:** Der Spieler muss wählen:
- "Arbeite schnell jetzt und verzichte später auf eine Pause?" (Energie verbrauchen, später Nahrung essen)
- "Iss jetzt und arbeite langsamer, aber plane für später?" (Energie sparen, frühzeitig nachlegen)
- "Iss nur wenn wirklich nötig, um Nahrung zu sparen?" (Riskanter Energy-Mangel, aber Nahrung für NPCs)

**Warum Energy statt Hunger?** Energy gibt dem Spieler eine proaktive Kontrolle über sein Tempo. Hunger ist reaktiv (Abrechnung bei Tageswechsel). Energy ist ein ständiges Mikromanagement: "Wie setze ich meine begrenzte Energie am besten ein?" Das schafft Taktik ohne Stress — der Spieler kann sich entscheiden, wann er langsam arbeiten will.

### Progression Phase 0: Bare Hands (Tag 1, ~200 Ticks)

**Verfügbare Aktionen:**

| Aktion | Tick-Kosten | Output | Werkzeug? |
|--------|-------------|--------|-----------|
| Wiese durchsuchen | 50 | 1 Faser ODER 1 Stein (50/50 Zufall) | ❌ |
| Zweige sammeln | 30 | 1 Holz | ❌ |
| Beeren pflücken | 40 | 3 Beeren | ❌ |
| Einfaches Werkzeug craften | 100 | 1 Werkzeug (150 Durability) | ❌ |
| Resource zum Lager tragen | Energy-Kosten: 2/Item + 1/Tile | Ressource im Lager | ❌ |

**Craft-Rezept: Einfaches Werkzeug**
```
Input:  2 Holz + 1 Faser + 1 Stein
Output: 1 Einfaches Werkzeug (Durability: 150)
Ticks:  100
```

### Progression Phase 1: Simple Tools (Tag 1-2, ~400 Ticks)

**Neue Aktionen mit Werkzeug:**

| Aktion | Tick-Kosten | Output | Werkzeug? | Durability-Kosten |
|--------|-------------|--------|-----------|------------------|
| Baum fällen | 80 | 5 Holz | ✅ Einfaches Werkzeug | -10 |
| Stein abbauen | 60 | 3 Stein | ✅ Einfaches Werkzeug | -5 |

### Progression Phase 2: Buildings (Tag 2-3, ~500 Ticks)

**Gebäude: Wohnhaus**

| Eigenschaft | Wert |
|-------------|------|
| Baukosten | 10 Holz + 3 Stein |
| Bauzeit (manuell) | 150 Ticks |
| Funktion | Schafft Wohnraum für 2 NPCs |
| NPC-Rekrutierung | Automatisch: 1 NPC sofort, 2. NPC nach 1 Tag |

**Gebäude: Holzfällerhütte**

| Eigenschaft | Wert |
|-------------|------|
| Baukosten | 15 Holz + 3 Stein |
| Bauzeit (manuell) | 200 Ticks |
| Produktionskette | **Input:** 1 Werkzeug (Durability) → **Output:** 5 Holz |
| Produktionszeit | 100 Ticks (wenn NPC zugewiesen + Werkzeug im Lager) |
| Werkzeug-Verbrauch | -5 Durability pro Produktion |
| NPC-Zuweisung | 1 NPC erforderlich |

**Wichtig:** Werkzeug ist im **Lager** (nicht NPC-Inventar). Gebäude "zieht" Werkzeug aus Lager, verbraucht Durability.

### Equilibrium-Beweis: Vertical Slice (4 Tage bis Automatisierung)

**Tag 1: Grundressourcen sammeln**
```
Aktionen:
  - Wiese durchsuchen × 2     = 100 Ticks → 1 Faser, 1 Stein      (-20 Energy)
  - Zweige sammeln × 2        = 60 Ticks  → 2 Holz                (-16 Energy)
  - Werkzeug craften          = 100 Ticks → 1 Werkzeug (150 Dur.) (-15 Energy)
  - Beeren pflücken × 2       = 80 Ticks  → 6 Beeren              (-10 Energy)

Gesamt: 340 Ticks (~34% des Tages)
Energy: 100 → 39 (61 Energy verbraucht)
Tageswechsel: -1 Beere (Spieler, Nahrungsverbrauch) → 5 Beeren Vorrat
          (Beere ISST nicht in Energy-Bilanz — Energie wird durch Aktion-Verbrauch geregelt,
           Nahrung dient primär der Energy-Auffüllung, nicht dem Hungern)
          → 5 Beeren im Vorrat, Spieler hat 39 Energy (kann essen für +10 → 49 Energy)
```

**Tag 2: Holz & Stein für Gebäude**
```
Aktionen:
  - Spieler isst 1 Beere am Morgen = +10 Energy  → 49 → 59 Energy
  - Baum fällen × 4           = 320 Ticks → 20 Holz (-48 Energy)
  - Stein abbauen × 2         = 120 Ticks → 6 Stein (-20 Energy)
  - Beeren pflücken × 1       = 40 Ticks  → 3 Beeren (-5 Energy)

Gesamt: 480 Ticks
Energy: 59 → -14 → ERST 0 Energy erreicht → -50% Debuff ab jetzt
  → Nur 3 Bäume fällig bei vollem Speed, 4. Baum mit Debuff (160 Ticks statt 80)
  → Strategie-Entscheidung: Beeren essen und mehr Energie für Bäume haben?
Tageswechsel: -1 Beere → 7 Beeren Vorrat
Werkzeug: 100 Durability übrig

💡 Design-Insight: Energy-Debuff zwingt zur strategischen Entscheidung —
   "Beere essen für +10 Energy (kostet 1 Beere, aber schneller)"
   oder "Debuff akzeptieren und Beere für Vorrat sparen"
```

**Tag 3: Wohnhaus + Holzfällerhütte bauen**
```
Aktionen:
  - Spieler isst 1 Beere am Morgen = +10 Energy → (verbleibend ~0+) → 10 Energy
  - Wohnhaus bauen            = 150 Ticks → -10 Holz, -3 Stein (-20 Energy)
    Energy: 10 → 0 → Debuff aktiv
    → Bauzeit verdoppelt sich nach dem 2. Steinabbau nicht (Wohnhaus = 20 Energy,
      aber Spieler hat nur 10 → Bau startet mit Debuff: 300 Ticks statt 150)
    EFFEKT: +1 NPC erscheint sofort
  - Holz nachsammeln (für Hütte) = 160 Ticks → 10 Holz (-12 Energy)
    → Start mit Debuff → 320 Ticks statt 160
  - Holzfällerhütte bauen     = 200 Ticks → -15 Holz, -3 Stein (-25 Energy)
    → Start mit Debuff → 400 Ticks statt 200

  → PROBLEM: Energy-Vorrat am Tag 3 reicht NICHT für effizientes Bauen!
  → Der Spieler MUSS strategisch Beeren sparen und essen

Ergebnis: Wohnhaus gebaut (aber 2x so lange wegen Energy-Debuff)
         Holzfällerhütte: muss am nächsten Tag fertig gebaut werden
Tageswechsel: -2 Beeren (Spieler + NPC) → 5 Beeren Vorrat
```

**Tag 4: Automatisierung startet (mit Energy-Management)**
```
  - Spieler isst 2 Beeren am Morgen → +20 Energy → 20 Energy
  - NPC zur Holzfällerhütte zuweisen (0 Ticks)
  - Holzfällerhütte fertig bauen = 200 Ticks → -15 Holz, -3 Stein (-25 Energy)
    → 20 Energy reicht nicht → 5 Energy nötig → Bau mit Debuff: 400 Ticks
    → ALTERNATIV: 3 Beeren essen (30 Energy) → Bau bei vollem Speed: 200 Ticks
    → Strategische Entscheidung: 1 Beere "kosten" für 200 Ticks Zeitersparnis
  - Zeit laufen lassen (Play-Button):
    Holzfällerhütte produziert automatisch:
      5 Produktionen × 100 Ticks = 500 Ticks → 25 Holz (-25 Durability)

  - Spieler sammelt parallel Beeren (mit verbleibendem Energy):
    Beeren pflücken × 2 = 80 Ticks → 6 Beeren (mit Debuff: 80 Ticks + 1-2 Beeren)

Tageswechsel: -2 Beeren → ~4 Beeren Vorrat (je nach Energy-Entscheidungen)
Werkzeug: 75 Durability übrig (hält noch ~3 Tage)

✅ EQUILIBRIUM ERREICHT (mit Energy-Lektion):
  - Holz-Produktion: 25 Holz/Tag automatisch
  - Energy-Strategie verstanden: Beeren = Energy + Nahrung, strategisch einsetzen
  - 1 NPC produktiv, Platz für 2. NPC (erscheint bald)
```

### Erkenntnisse aus dem Equilibrium-Modell

1. **Equilibrium in ~4 Tagen erreichbar** — schnell genug, um Spieler zu motivieren, langsam genug, um manuelles Spielen zu lehren
2. **Energy-Management schafft taktische Entscheidungen** — Der Spieler muss ständig wählen: "Arbeitet ich jetzt schnell (Energy verbrauchen) oder spare ich (Debuff in Kauf nehmen)?" Das ist kein Survival-Stress, sondern ein strategisches Puzzle.
3. **Nahrungsautomatisierung fehlt** — Beeren-Sammlung bleibt manuell. Nächstes Gebäude: Beerenstrauch-Garten (automatisiert Nahrung + Energy-Nachschub). Langfristig: Mehrere Nahrungsketten (Brot, Fleisch, etc.)
4. **Wohnhaus-System skaliert** — Im MVP wird nur der erste NPC gespawnt. Später: Rekrutierungsprozess für weitere NPCs
5. **Tick-System ermöglicht Planung** — Zeit läuft nur bei Play oder manuellen Aktionen. Spielgeschwindigkeit (Ticks pro Sekunde) ist variabel einstellbar.
6. **Energy-Debuff als Lehrinstrument** — Am Tag 3 merkt der Spieler: "Wenn ich schneller bauen will, MUSS ich Beeren essen." Das lehrt intuitiv den Zusammenhang zwischen Nahrung und Produktivität, ohne dass es als "Überlebensdruck" fühlt.

### Transport-System: Extrahiert ≠ Gelagert

**Kern-Regel:** Ressourcen, die der Spieler abbaut (Baum fällen, Beeren pflücken, Stein abbauen), erscheinen NICHT automatisch im gemeinsamen Lager. Sie landen im **Trage-Inventar** des Spielers (max 5 Items). Um sie verfügbar für Gebäude zu machen, muss der Spieler sie **manuell zum Lager transportieren**.

**Trage-Inventar:**
```
Kapazität: 5 Items
Inhalt: Sichtbar im UI (Slot-Anzeige mit Icons)
Entladen: Auto-Unload beim Betreten des Lager-Tiles (alle Items)
          ODER manuell entladen über UI-Button
Transport-Kosten: 2 Energy pro Item + 1 Energy pro Tile-Distanz zum Lager
Beispiel: 3 Items, 8 Tiles Distanz = 2×3 + 1×8 = 14 Energy
```

**Lager-Gebäude (zentraler Storage):**
```
Baukosten: 8 Holz + 2 Stein
Bauzeit: 120 Ticks (manuell)
Funktion: Zentraler Ressourcen-Storage (alle Ressourcen typen)
Kapazität: Start 50 Items, erweiterbar (+100 pro Upgrade, 10 Holz/Upgrade)
Transport-Annahme: Spieler betritt Tile → Items werden automatisch angelandet
                  (Transport-Kosten fallen trotzdem an — die Reise war die Arbeit)
NPC-Transport: NPCs können vom Lager zu Produktionsgebäuden transportieren
              (Entfernung × 1 Energy/NPC, aus Lager-Latenz bezahlt)
```

**Gebäude-Produktionslogik:**
```
Regel: Gebäude zieht Inputs AUS dem Lager, nicht direkt vom Spieler.
Flow: Spieler baut Ressource → Trage-Inventar → Transport zum Lager → Lager
     → Spieler weist NPC zu → NPC zieht aus Lager → Gebäude produziert

Das zwingt den Spieler zur Logistik-Planung:
- Lager-Positionierung (nahe Ressourcen? nahe Produktion?)
- Transport-Budget (Energy vs. Produktivität)
- NPC-Delegation (Transport automatisieren statt selbst machen)
```

### NPC Transport-System

```
NPC-Transport starten: NPC mit "Transport"-Aufgabe zuweisen
NPC wählt Items aus Lager (priorisiert: nächstes benötigtes Gebäude)
NPC läuft zum Ziel (pro Tile: +5 Ticks Transportzeit, +0 Energy-Kosten für Spieler)
NPC lädt am Ziel-Tile ab (automatisch, wenn Ziel ein Produktionsgebäude)
NPC läuft zurück (pro Tile: +5 Ticks)

Tragfähigkeit: 1 Item pro NPC (MVP), später: Upgrades für +2, +3
Transport-Debounce: NPC startet nicht wenn schon einer unterwegs ist (pro Ziel)

Beispiel: NPC transportiert 5 Holz vom Lager zur Holzfällerhütte (12 Tiles)
  Hinweg: 12 × 5 = 60 Ticks
  Abladen: 10 Ticks
  Rückweg: 12 × 5 = 60 Ticks
  Gesamt: 130 Ticks (vom Lager-Start an)
```

### Manuelles Transport-Energy-Balancing

```
Energie-Kosten pro Transport:
  2 Energy pro Item + 1 Energy pro Tile-Distanz

Strategische Implikation:
  - Kurze Transporte (3 Tiles): 2×1 + 1×3 = 5 Energy pro Item → machbar
  - Weite Transporte (15 Tiles): 2×1 + 1×15 = 17 Energy pro Item → teuer
  - Volles Inventar (5 Items, 15 Tiles): 5 × 17 = 85 Energy → fast alles

Design-Insight: Transport-Kosten belohnen **gutes Layout-Design**.
Ein Lager nahe den Ressourcen spart Energy → mehr Time für Produktion.
Ein Lager in der Mitte der Karte = Kompromiss (nahe Bauzone, weit von Ressourcen).
```

### Next Production Chain: Food Automation

**Gebäude: Beerenstrauch-Garten**

| Eigenschaft | Wert |
|-------------|------|
| Baukosten | 8 Holz + 2 Stein |
| Bauzeit | 120 Ticks |
| Produktionskette | **Input:** — (keine Werkzeuge) → **Output:** 5 Beeren |
| Produktionszeit | 500 Ticks (langsamer als manuell, aber automatisch) |
| NPC-Zuweisung | 1 NPC |

**Equilibrium:**
```
2 NPCs + Spieler = 3 Beeren/Tag Verbrauch
Beerenstrauch-Garten: 5 Beeren alle 500 Ticks = ~10 Beeren/Tag
→ 3.3x Überproduktion (Puffer für Expansion)
```

---

## Player Motivation Profile

### Primary Psychological Needs Served

| Need | How This Game Satisfies It | Strength |
| ---- | ---- | ---- |
| **Autonomy** (freedom, meaningful choice) | Spieler entscheiden WAS sie automatisieren, WANN sie expandieren, WIE sie Ketten designen — keine vorgegebenen Lösungen. Viele Wege zum Ziel. | **Core** |
| **Competence** (mastery, skill growth) | Progression ist **sichtbar** — von "ich hacke Holz" zu "mein Dorf läuft ohne mich". Bottleneck-Fixing gibt konstantes "Ich bin besser geworden"-Feedback. Goal-driven Milestones belohnen Meisterschaft. | **Core** |
| **Relatedness** (connection, belonging) | NPCs sind nicht nur Maschinen — du arbeitest MIT ihnen (hybrid phase), du kennst "deinen Meister-Schmied", du siehst wie dein Dorf lebt. Evtl. Community-Sharing von Layouts. | **Supporting** |

### Player Type Appeal (Bartle Taxonomy)

- [x] **Achievers** (goal completion, collection, progression) — **PRIMARY**: Goal-driven Milestones (X Einwohner, Y Gold, Z Produktionsketten), Unlock-basierte Progression, klare messbare Ziele
- [x] **Explorers** (discovery, understanding systems, finding secrets) — **SECONDARY**: Neue Produktionsketten freischalten, Perk-Synergien finden, Handelsnetzwerk-Möglichkeiten entdecken
- [ ] **Socializers** (relationships, cooperation, community) — **MINIMAL**: Singleplayer, aber Community-Sharing von Designs möglich
- [ ] **Killers/Competitors** (domination, PvP, leaderboards) — **MINIMAL**: Evtl. Leaderboards für "Fastest to X Goal" (später)

### Flow State Design

- **Onboarding curve**: Tutorial-Phase ist **manuelles Arbeiten** — du lernst jeden Prozess durch Ausführung. Erste 30 Minuten: Holz hacken, Nahrung sammeln, erstes Gebäude bauen. Keine Info-Dumps, "Learning by Doing".

- **Difficulty scaling**: Early Game = Überleben (Nahrung stabilisieren). Mid Game = Optimierung (Bottlenecks finden). Late Game = Komplexität (Tier-3-NPCs bedienen, Handelsnetzwerk ausbauen). Challenge wächst organisch.

- **Feedback clarity**: Hover-UI zeigt **exakt** was blockiert ist ("Mühle wartet auf Weizen", "Bäcker hat kein Mehl"). Produktions-Stats im UI (X Bretter/Tag). Klare Fortschrittsanzeige zu Goals.

- **Recovery from failure**: Tod = Respawn auf letzter Schlafstelle, Dorf läuft weiter (kein Permadeath). Ineffiziente Ketten = sichtbar, debugbar, nicht "Game Over". Failure ist lehrreich, nicht strafend.

---

## Core Loop

### Moment-to-Moment (30 seconds)

**Early Game (manuell):**
Spieler bewegt sich, klickt auf Ressource (Baum, Stein, Weizen), wartet auf Animation, Ressource im Trage-Inventar. **Ressource zum Lager tragen** (Transport-Kosten: Energy pro Item + Distanz), dann nächste Ressource. **Meditative Routine** — rhythmisch, beruhigend, Zeit zum Planen.

**Mid Game (hybrid):**
Spieler weist NPCs Transport- und Produktionsaufgaben zu ("Du bringst Holz zur Hütte, ich sammle Stein"), prüft Gebäude-Status (Hover: "Sägewerk produziert 5 Bretter/min, wartet auf Holz — NPC transportiert"), optimiert Lager-Platzierung und NPC-Routen.

**Late Game (management):**
Spieler prüft Dashboard, identifiziert Bottlenecks ("Meister-Schmied inaktiv — Luxusgüter fehlen"), baut neue Produktionskette, beobachtet wie System stabilisiert. **Submission + Challenge Mix** — Flow-State beim Debuggen.

**Intrinsische Befriedigung:** Audio-Feedback bei Produktionsabschluss, sichtbare Fortschritts-Balken, "Ding!"-Sound wenn Meilenstein erreicht.

### Short-Term (5-15 minutes)

**"One More X"-Psychologie:**
- **"One More Building"** — "Wenn ich noch ein Sägewerk baue, kann ich Bretter automatisieren..."
- **"One More Chain"** — "Wenn ich Weizen → Mehl → Brot verkette, habe ich Nahrung gelöst..."
- **"One More NPC"** — "Wenn ich einen Handwerker rekrutiere, kann ich Tier-2-Waren produzieren..."

**Spieler-Entscheidungen:**
- Was baue ich als nächstes? (Priorisierung unter Ressourcen-Knappheit)
- Wen stelle ich ein? (NPC-Perks vs. Verbrauchsgüter-Kosten)
- Welche Produktionskette optimiere ich? (Bottleneck-Hunting)

### Session-Level (30-120 minutes)

**Typische Session-Struktur:**

1. **Check-In** (5 min) — Dorf-Status prüfen: Läuft Nahrung aus? Sind NPCs inaktiv? Was ist ineffizient?
2. **Plan** (5 min) — "Heute automatisiere ich Nahrungsproduktion und rekrutiere einen Handwerker"
3. **Execute** (30-60 min) — Gebäude bauen, NPCs zuweisen, Ressourcen umleiten, Kette testen
4. **Optimize** (15-30 min) — Bottlenecks finden, Layouts anpassen, Effizienz steigern
5. **Expand** (10-20 min) — Nächste Produktionskette in Angriff nehmen oder Handelstile erschließen

**Natural Stopping Point:** Wenn eine Produktionskette "solved" ist und stabil läuft (grüne Checkmarks im UI, kein Bottleneck-Warning).

**Hook zum Weiterdenken:** "Morgen könnte ich Werkzeugproduktion automatisieren, dann habe ich Zugriff auf effizientere Ernte-Tools..." oder "Wenn ich Luxusgüter produziere, aktiviere ich meinen Meister-Schmied..."

### Long-Term Progression

**Wie wächst der Spieler?**

- **Power:** Von manueller Arbeit zu Management (weniger selbst tun, mehr planen). Spieler-Charakter bleibt relevant (kann immer noch manuell helfen), aber Fokus verschiebt sich.

- **Knowledge:** Neue Produktionsketten freischalten (Brot → Werkzeuge → Kleidung → Luxusgüter). Komplexere Ketten brauchen mehr Zwischenschritte und Tier-höhere NPCs.

- **Options:** Mehr Gebäudetypen (15-25), mehr NPC-Spezialisierungen (3 Tiers × X Berufe), komplexere Handelsnetzwerke (5-10 externe Tiles).

**Was ist das Langzeitziel?**

**Goal-driven Milestones** (Spieler wählt zu Beginn Schwierigkeitsgrad/Ziel):
- **Bevölkerungsziel:** Erreiche 50 Einwohner (davon 10 Handwerker, 3 Meister)
- **Wohlstandsziel:** Erwirtschafte 10.000 Gold durch Handel
  - **Gold Faucets (Einnahmen):**
    - Warenverkauf an reisende Händler (kommen alle X Tage)
    - Warenversand zu anderen Siedlungen via Übermap (Spieler schickt Karawane)
  - **Gold Sinks (Ausgaben):**
    - Import seltener Ressourcen (z.B. Edelsteine, exotische Gewürze)
    - Gebäude-Upgrades (verbesserte Versionen bestehender Gebäude)
    - NPC-Training (Tier-Aufstieg beschleunigen oder Spezial-Perks freischalten)
  - **Exchange Rates (Fixed Prices):**
    - **Basisressourcen**: Holz 2 Gold, Stein 3 Gold, Faser 1 Gold
    - **Verarbeitete Waren**: Bretter 10 Gold, Werkzeug 25 Gold
    - **Nahrung**: Beeren 5 Gold, Brot 15 Gold, Fleisch 20 Gold
    - **Kleidung**: Einfache Kleidung 50 Gold, Feine Kleidung 100 Gold
    - **Luxusgüter**: Wein 100 Gold, Schmuck 200 Gold, Kunstwerke 500 Gold
  - **Inflation Prevention**: Fixed prices, aber teurere Goods schalten später frei. Luxusgüter haben hohe Gewinnmargen, aber brauchen komplexe Ketten.
- **Produktionsziel:** Produziere 1.000 Einheiten Luxusgüter
- **Selbstversorgungs-Ziel:** Alle 3 Bevölkerungstiers vollständig bedient für 10 aufeinanderfolgende Tage — Tier gilt als "vollständig bedient" wenn alle NPCs erforderliche Waren erhalten haben + null NPCs haben Debuff + Produktion >= Verbrauch (Surplus existiert). Counter resettet wenn ein Tier fails.

**Bevölkerungstier Consumption/Production Scaling:**
- **Tier 1 (Arbeiter)**:
  - Consumption: 1 Nahrung/Tag
  - Produktion: Baseline (1x) — können einfache Gebäude betreiben (Holzfällerhütte, Beerenstrauch-Garten, Steinbruch)
  - Perks: Keine
  - Role: Grundressourcen-Produktion

- **Tier 2 (Handwerker)**:
  - Consumption: 2 Nahrung/Tag + 1 Kleidung alle 2 Tage (0.5/Tag)
  - Produktion: Baseline (1x) — KEINE Speed-Boni, aber **können komplexe Gebäude betreiben** (Schmiede, Weberei, Mühle) die Tier 1 nicht bedienen kann
  - Perks: **Aktivieren wenn Kleidung verfügbar** — z.B. "Effizienter Handwerker" (+20% Output wenn Kleidung-Surplus >10 Einheiten)
  - Required für Tier-Aufstieg: 10 Tage mit stabiler Nahrung + 5 Kleidung im Lager
  - Role: Verarbeitete Waren-Produktion

- **Tier 3 (Meister)**:
  - Consumption: 3 Nahrung/Tag + 1 Kleidung/Tag + 1 Luxusgut alle 5 Tage (0.2/Tag)
  - Produktion: Baseline (1x) — können **hochkomplexe Gebäude betreiben** (Juwelier, Alchemist, Meister-Schmiede) die nur sie bedienen können
  - Perks: **Aktivieren wenn Luxusgüter verfügbar** — z.B. "Meisterwerk" (+30% Quality/Output wenn Luxusgüter-Surplus >5)
  - Required für Tier-Aufstieg: 10 Tage mit stabiler Kleidung + 3 Luxusgüter im Lager
  - Role: Luxusgüter & High-End-Produktion

**Design-Prinzip:** Höhere Tiers ermöglichen **Zugang zu komplexeren Produktionsketten**, nicht nur höhere Geschwindigkeit. Ein Meister ist nicht "ein schnellerer Arbeiter", sondern "jemand der Dinge herstellen kann, die Arbeiter nicht können".

**"Gewonnen" = Ziel erreicht** → Post-Game Sandbox-Mode (weiter optimieren, höhere Ziele setzen) oder New Game+ mit härteren Constraints.

### Retention Hooks

- **Curiosity:** "Welche Produktionskette schalte ich als nächstes frei? Was brauchen Tier-3-NPCs wirklich?"
- **Investment:** "Mein Dorf läuft perfekt — ich will nicht aufhören, jetzt wo alles funktioniert"
- **Mastery:** "Ich weiß, ich kann diese Kette noch effizienter machen. Nächste Session optimiere ich das Layout."
- **Social (später):** Community-Sharing von Layouts, Speedrun-Challenges ("Fastest to 50 population")

---

## Game Pillars

### Pillar 1: "Earned Automation"

**Early Game:** Jede Automatisierung muss durch manuelle Arbeit verdient werden — du verstehst den Prozess, BEVOR du ihn delegierst. **Late Game:** Sobald du ein System gemeistert hast, kannst du ähnliche Produktionslinien direkt automatisiert aufbauen.

**Design test:** Wenn wir ein neues Gebäude hinzufügen — ist es im Early Game nur nach manuellem Prozess verfügbar, im Late Game direkt baubar wenn der Spieler das Grundprinzip bereits kennt? → **JA** = passt zum Pillar.

**Warum:** Macht Automatisierung emotional befriedigend ("Nie wieder!") statt belanglos, während Late-Game-Tedium vermieden wird.

---

### Pillar 2: "Information Transparency"

Jeder Schritt der Produktionskette ist **nachvollziehbar und debugbar** — durch UI, Feedback, Hover-Info — NICHT durch dauerhaft sichtbare NPC-Simulation. Systeme sind transparent, ohne Performance-Last.

**Design test:** Wenn wir ein neues System hinzufügen — kann der Spieler durch Hover/UI/Feedback sehen WO Ressourcen sind, WELCHER Prozess läuft, WARUM etwas blockiert ist? → **JA** = passt zum Pillar.

**Warum:** Achievement Hunters wollen Systeme **verstehen** und **debuggen**, nicht nur benutzen. NPCs permanent zu animieren ist Scope-Bloat ohne Design-Mehrwert — Rimworld zeigt, dass Abstraktion funktioniert.

---

### Pillar 3: "Optimization Over Expansion"

Tiefe vor Breite — es ist befriedigender, eine Produktionskette perfekt zu optimieren, als 10 ineffiziente zu haben. Die normale Karte ist begrenzt (30×30 Tiles), NPC upkeep costs sind Verbrauchsgüter (Nahrung, Kleidung, etc.).

**Design test:** Erstellt dieses Feature messbare Kosten für Expansion ohne Optimierung? (z.B. begrenzte Tiles erzwingen Layout-Planung, NPC-Verbrauch erfordert effiziente Ketten)

**Enforcement:** Begrenzte Karte, NPC-Verbrauchskosten steigen mit Bevölkerungstiers, Effizienz-Boni für gut geplante Layouts (z.B. kürzere Transportwege)

**Warum:** Factorio-Spieler lieben es, Bottlenecks zu finden und zu fixen — das ist der Core-Loop. "Bigger" ist nicht "Better", "Efficient" ist "Better".

---

### Anti-Pillars (What This Game Is NOT)

- **NOT "Instant Gratification"** — Wir werden KEINE "Skip Work"-Buttons hinzufügen, die Progression trivial machen. Automatisierung muss verdient werden. Kein Pay-to-Win, kein "Auto-Solve"-Feature.

- **NOT "Story-Driven"** — Wir werden KEINE komplexe Narrative mit Dialogen und Quests bauen. Das Spiel erzählt seine Geschichte durch Progression, nicht durch Text. NPCs haben Namen und Perks, aber keine Storylines.

- **NOT "Combat-Focused"** — Wir werden KEIN Kampfsystem als Kern-Feature entwickeln. Der Konflikt kommt aus Ressourcen-Management und Optimierungspuzzles, nicht aus Feinden. (Evtl. passive Bedrohungen wie Wetter/Krankheit später, aber nie Kampf-Mechanik).

- **NOT "Procedural Sprawl"** — Wir werden KEINE endlosen prozeduralen Welten ohne Grenzen bauen. Das Spiel hat eine **begrenzte Hauptkarte** (wie Rimworld) + **Übermap für Handel/Expansion** (definierte Tile-Menge, 5-10), aber klare Scope-Grenzen und definierte Ziele.

---

## Inspiration and References

| Reference | What We Take From It | What We Do Differently | Why It Matters |
| ---- | ---- | ---- | ---- |
| **Factorio** | Optimierungs-Focus, Bottleneck-Hunting, befriedigende Automatisierung, klare visuelle Feedback-Systeme | Mittelalterliches Setting, Start als einzelner Charakter (nicht instant God-View), Bevölkerungstiers statt nur Maschinen | Beweist, dass Optimierungs-Sandboxes ein engagiertes Publikum haben (~3.5M Kopien). Unsere "From Scratch"-Progression ist emotionaler Einstieg. |
| **Anno (Serie)** | Bevölkerungstiers mit wachsenden Bedürfnissen, Verbrauchsgüter-Wirtschaft, Produktionsketten-Visualisierung | 2D statt Isometric (Scope), Spieler arbeitet MIT NPCs (hybrid phase), keine Naval-Mechanik, kleinerer Scope | Zeigt, dass Tier-Systeme + Produktionsketten funktionieren. Unsere Perk-System-Integration (Waren bedingen Perks) ist neu. |
| **Rimworld** | Begrenzte Karte erzeugt interessante Constraints, Management-Interface-Design, NPC-Abstraktion (nicht permanent sichtbar) | Keine Kolonisten-Psychologie-Simulation, keine Combat-Focus, Goal-driven statt Sandbox-only | Beweist, dass begrenzte Karten besser für Optimierung sind als endlose. UI-Abstraktion (Rimworld zeigt NPCs nicht permanent) ist Scope-freundlich. |
| **Card Survival: Tropical Island** | "Start from Zero"-Progression, manuelles Crafting lehrt Systeme, befriedigender Übergang zu Effizienz | Multiplayer-fähig (später evtl.), Village-Building statt Solo-Survival, 2D Top-Down statt First-Person-Cards | Zeigt, dass "mit den Händen beginnen" emotional resonant ist. Spieler schätzen den Kontrast Early→Late Game. |

**Non-game inspirations:**
- **Mittelalterliche Handwerks-Dokumentationen** (Ton: authentisch, aber zugänglich — kein Fantasy-Kitsch)
- **"How It's Made"-Sendungen** (visuelles Design: klare Schritt-für-Schritt-Produktionsketten)
- **Lean Manufacturing / Kaizen** (philosophisch: kontinuierliche Verbesserung, Bottleneck-Elimination)

---

## Target Player Profile

| Attribute | Detail |
| ---- | ---- |
| **Age range** | 18-40 (Kern: 22-35) |
| **Gaming experience** | Hardcore / Mid-core — kennen Management-Games, schätzen Komplexität |
| **Time availability** | 1-3 Stunden pro Session, 3-5 Sessions pro Woche — "Deep Focus"-Spieler, keine Casual-Quick-Sessions |
| **Platform preference** | PC (Steam) — Maus+Tastatur, größere Bildschirme, Community-aktiv |
| **Current games they play** | Factorio, Rimworld, Anno (1800/1404), Oxygen Not Included, Satisfactory, Banished, Foundation |
| **What they're looking for** | **Factorio-Style Optimierung in frischem Setting** + **Anno-Style Wirtschaftstiefe** + **emotionale "From Zero"-Progression**. Sie haben Factorio "gelöst", suchen neue Optimierungs-Sandboxes. |
| **What would turn them away** | Story-Heavy-Games (zu viel Text), Action/Reflex-Games (zu stressig), Pay-to-Win, Mobile-Style "Wait or Pay"-Mechanik, zu einfache Systeme (langweilig) |

**Psychografisches Profil:**
- **Achievement Hunters** — tracken Stats, lieben Spreadsheets, wollen "100%" erreichen
- **Systems Thinkers** — analysieren, theorycraften, teilen Designs mit Community
- **Optimierungs-Enthusiasten** — "gut genug" ist nie gut genug, suchen immer nach +5% Effizienz
- **Geduldige Planer** — bereit, 30 Minuten zu planen bevor sie 10 Minuten bauen

---

## Technical Considerations

| Consideration | Assessment |
| ---- | ---- |
| **Recommended Engine** | **Godot 4.6** — 2D ist Godots Stärke, Node-System passt zu Gebäude/Produktionsketten-Architektur, GDScript anfängerfreundlich, Steam-Export einwandfrei. Kein Unity (Overhead für 2D), kein Unreal (Overkill). |
| **Target Performance** | **60fps** auf 8GB Laptops. **Memory ceiling: 500 MB** (Textures ~50MB, Audio ~20MB, Game state ~35KB, Engine ~80MB). Physics system: **Disabled** (kein Combat, kinematische Bewegung). |
| **Key Technical Challenges** | 1. **Produktionsketten-System** — flexible, data-driven Architektur, sonst wird jede Kette hardcoded (Albtraum). 2. **NPC Resource Movement** — NPCs bewegen Ressourcen abstrakt (teleportieren mit Delay), keine echte Pathfinding-Simulation. Entfernung = Zeit (pro Tile mehr Ticks). NPCs haben Tragkapazität (belt-capacity). Routes sollen visualisiert werden (wenn nötig: Navigation2D enablen, sonst disablen). Optimierung: Straßen auf Tiles reduzieren Transportzeit. 3. **Save/Load** — komplexe Spielzustände (viele Gebäude, NPCs, Ressourcen, Produktionsketten-States) sauber serialisieren. JSON für Saves. Loading screen oder async load (100 buildings = 70-110ms = 4-7 frames Hitch). |
| **Building System** | **1 tile pro Gebäude** (MVP scope). TileMapLayer-basiert. Architecture decision required: Scene tiles (4.6 feature) vs atlas tiles vs Node2D instances? |
| **Art Style** | **2D Top-Down Tiles** (Rimworld-ähnlich) oder **Isometric 2D** (Anno-ähnlich) — Top-Down ist Scope-freundlicher. **Pixel Art oder Simple Flat-Color Assets** — produzierbar als Solo-Dev. **Minimalistisch** — Information über Ästhetik (Pillar 2). |
| **Art Pipeline Complexity** | **LOW** — Tile-basierte Assets, wiederverwendbare Sprites, UI-fokussierte Darstellung. Keine Character-Animation (NPCs nicht permanent sichtbar), keine aufwändigen VFX. Gut für erstes Spiel + Monate-Timeline. |
| **Audio Needs** | **Moderate** — Ambient-Musik (mittelalterlich, nicht aufdringlich), UI-SFX (Klicks, Bestätigungen), Produktions-SFX ("Ding!" bei Abschluss, Hammer-Sounds bei Bau), kein Voice Acting. |
| **Networking** | **None** (MVP/Core Experience) — Singleplayer. Evtl. später: Leaderboards (async), Cloud-Save. Kein Multiplayer geplant (Scope-Explosion). |
| **Content Volume** | **MVP:** 5 Ressourcen, 5 Gebäude, 3 Ketten. **Core:** 15 Ressourcen, 12 Gebäude, 8 Ketten, 3 Bevölkerungstiers. **Full:** 25+ Ressourcen, 20+ Gebäude, 12+ Ketten, 10 Handelstiles. **Gameplay-Stunden (Core):** 12-20 Stunden bis Goal, +10-20 Stunden Post-Game Sandbox. |
| **Procedural Systems** | **None** (MVP/Core) — handdesignte Hauptkarte, fixe Übermap-Tiles. Evtl. später: Zufällige NPC-Perk-Generation, zufällige Händler-Angebote. Keine Prozedural-Generierte Welt (Anti-Pillar "Procedural Sprawl"). |

---

## Risks and Open Questions

### Design Risks

1. **Early Game Pacing** — Ist die manuelle Phase lang genug, um zu lehren, aber kurz genug, um nicht langweilig zu werden? **Mitigation:** Playtesting nach MVP, Tutorial-Pacing iterativ anpassen.

2. **Automation Satisfaction** — Fühlt sich der Übergang von manuell zu automatisiert **befriedigend** an, oder nur "klicke Button, fertig"? **Mitigation:** Audio/Visual-Feedback verstärken, "Before/After"-Statistiken zeigen ("Du hast 50 Bretter/Tag manuell geschafft, jetzt 200/Tag automatisch!").

3. **Tier-System Balance** — Sind Tier-2/3-NPCs zu teuer (frustrierend) oder zu billig (trivial)? **Mitigation:** Verbrauchsraten data-driven, einfach tweakbar. Playtesting mit verschiedenen Rates.

4. **Goal Balance** — Sind die Ziele erreichbar genug (Frustration vermeiden) aber herausfordernd genug (Triumph erzeugen)? **Mitigation:** Mehrere Schwierigkeitsgrade ("Casual", "Normal", "Expert"), Ziele skalieren.

### Technical Risks

1. **NPC Resource Movement** — NPCs müssen Ressourcen bewegen, aber nicht als sichtbare Sprites. **Mitigation:** NPCs bewegen Ressourcen abstrakt (teleportieren mit Delay basierend auf Entfernung). Entfernung pro Tile erhöht Transport-Ticks. NPCs haben belt-capacity (Tragmenge). Routes werden visualisiert (Pfeil/Linie), NPCs selbst nicht permanent sichtbar. Navigation2D nur wenn nötig.

2. **Produktionsketten-Architektur** — Hardcoded Ketten = Albtraum, jede neue Kette braucht Code. **Mitigation:** Data-driven System (JSON/YAML-Rezepte), generisches "Recipe"-System, das alle Ketten gleich behandelt. Prototyp in MVP-Phase.

3. **Save/Load Komplexität** — Viele bewegliche Teile (Gebäude-States, NPC-Assignments, Produktionsketten-Queues, Inventare). **Mitigation:** JSON für Saves (human-readable, nicht Resource class). Resource-Klassen nur für Data Definitions (Recipes, Building Stats). Async Load mit Loading Screen implementieren (100 buildings = 70-110ms = 4-7 frame hitch sonst). Früh implementieren (Week 2 von MVP), regelmäßig testen.

4. **Performance bei vielen Gebäuden** — 100+ Gebäude auf Karte, jedes tickt Produktions-Logic. **Mitigation:** Tick System ist intern (variable Ticks/Sekunde = Spielgeschwindigkeit). Objekt-Pooling, tickt nur aktive Gebäude (nicht leere). Physics disabled (kein Bedarf). Target: 60fps, 500MB memory ceiling.

### Market Risks

1. **Crowded Genre** — Viele Management-Games auf Steam. **Mitigation:** Hook ("From Scratch"-Progression + Perk-System) muss **klar kommuniziert** werden in Store-Page, Trailer zeigt Progression Early→Late. Nische ist klein, aber engagiert.

2. **Solo-Dev Wahrnehmung** — Spieler erwarten evtl. Factorio-Level-Polish von einem Solo-Dev (unrealistisch). **Mitigation:** Early Access, klare Kommunikation "Work in Progress", Community-Feedback einbinden.

3. **Mittelalterliches Setting = "generisch"?** — Viele mittelalterliche Builder. **Mitigation:** Visuelle Identität klar definieren (Art Bible), Fokus auf Systeme statt nur Ästhetik.

### Scope Risks

1. **Content Volume** — 25 Ressourcen × 20 Gebäude × 12 Ketten = viel Balancing-Arbeit. **Mitigation:** Scope Tiers strikt einhalten. MVP ist MINIMAL (5/5/3), nicht "ein bisschen von allem". Core Experience ist Feature-Complete, Full Vision ist "Nice to Have".

2. **Handelssystem-Komplexität** — Übermap, Händler-AI, Preissystem, Diplomatie? Kann explodieren. **Mitigation:** MVP hat KEIN Handelssystem. Core Experience hat simples System (fixe Preise, kein Angebot/Nachfrage). Full Vision hat Komplexität.

3. **Perk-System Balancing** — 50 verschiedene Perks × 3 Tiers × Aktivierungsbedingungen = Balancing-Hölle. **Mitigation:** MVP hat KEINE Perks. Core Experience hat ~10 simple Perks (+Speed, +Efficiency). Full Vision erweitert.

### Open Questions

1. **Wie fühlt sich Top-Down vs. Isometric an?** — **Antwort:** Prototyp beide in Week 1, entscheide basierend auf "was ist lesbarer + schneller produzierbar". Top-Down wahrscheinlich besser (Scope).

2. **Brauchen wir wirklich 3 Bevölkerungstiers im Core Experience?** — **Antwort:** Playtesting nach MVP. Evtl. reichen 2 Tiers (Arbeiter + Handwerker), Meister kommen in Full Vision.

3. **Wie abstrahieren wir NPC-Bewegung im UI?** — **Antwort:** Prototyp "Hover zeigt Pfeil von Quelle zu Ziel" vs. "Hover zeigt Text 'Bäcker holt Mehl aus Mühle'". A/B-Test mit Playtern.

4. **Ist Day/Night-Cycle wichtig oder Scope-Bloat?** — **Antwort:** MVP hat simple Time-System (abstraktes "Tage vergehen", kein visueller Cycle). Core Experience kann visuellen Cycle hinzufügen wenn Zeit übrig.

---

## Vertical Slice Definition (FIRST MILESTONE)

**Core hypothesis**: Spieler finden die **Progression von manueller Arbeit zu NPC-gestützter Automatisierung** emotional befriedigend und intrinsisch motivierend.

**Goal:** Validiere Core Loop in 6-8 Wochen. Ist "manual → automated" fun? Wenn nein, pivot. Wenn ja, weiter zu MVP.

### Required for Vertical Slice

1. **Tick-System Implementation:**
   - 1 Tag = 1000 Ticks
   - Play/Pause Button (Zeit läuft nur bei Play oder manuellen Aktionen)
   - Tageswechsel = Verbrauchsgüter-Abrechnung

2. **Player Character:**
   - Movement (WASD oder Click-to-Move)
   - Manuelle Aktionen mit Tick-Kosten:
     - Wiese durchsuchen (50 Ticks) → Faser/Stein
     - Zweige sammeln (30 Ticks) → Holz
     - Beeren pflücken (40 Ticks) → Beeren
     - Baum fällen (80 Ticks, braucht Werkzeug) → 5 Holz

3. **Tool System:**
   - Einfaches Werkzeug craftbar (100 Ticks): 2 Holz + 1 Faser + 1 Stein → 1 Werkzeug (150 Durability)
   - Werkzeuge im Lager (nicht NPC-gebunden)
   - Gebäude verbrauchen Werkzeug-Durability aus Lager

4. **3 Ressourcen:**
   - Holz (Rohstoff + wird zu Baukosten)
   - Beeren (Nahrung — Verbrauchsgut)
   - Stein (Rohstoff + wird zu Baukosten)

5. **3 Gebäude:**
   - **Lager** (8 Holz + 2 Stein, 120 Ticks Bauzeit) → **Zentraler Storage**, erst ab hier können Ressourcen gespeichert werden. MUSS vor allen anderen Gebäuden gebaut werden, da manuell extrahierte Ressourcen nur im Trage-Inventar (5 Slots) landen und zum Lager transportiert werden müssen. Lager ist die Voraussetzung für jegliche Produktion.
   - Wohnhaus (10 Holz + 3 Stein, 150 Ticks Bauzeit) → +2 NPCs Kapazität
   - Holzfällerhütte (15 Holz + 3 Stein, 200 Ticks) → Werkzeug → 5 Holz (100 Ticks/Produktion, muss Holz AUS Lager beziehen)

6. **NPC-System (minimal):**
   - NPCs erscheinen automatisch wenn Wohnhaus gebaut (1 sofort, 2. nach 1 Tag)
   - NPC-Zuweisung zu Gebäude (Klick)
   - NPCs arbeiten automatisch (auch bei Pause)
   - NPCs verbrauchen Nahrung (1 Beere/Tag)

7. **Player Energy System (NOT a survival mechanic):**
   - Spieler startet mit 100 Energy (voll)
   - Jede manuelle Aktion verbraucht Energy (Wiese 10, Baum fällen 12, etc.)
   - Nahrung (Beeren, Brot) füllt Energy sofort auf (+10/Beere, +25/Brot)
   - 0 Energy: Alle Aktionen kosten 2x Ticks, 50% Output-Reduktion
   - UI zeigt Energy-Bar + aktuellen Status (full/low/depleted)
   - KEIN Tod bei 0 Energy — Debuff bleibt bis Nahrung gegessen wird

8. **Hunger as Productivity Modifier (NOT Death Timer):**
   - Tägliche Abrechnung: -1 Beere/Entität
   - Bei Mangel: -50% Produktivität (alle Aktionen +50% Tick-Kosten)
   - KEIN Tod bei 0 Nahrung

8. **Minimal UI:**
   - Ressourcen-Anzeige (Holz, Beeren, Werkzeug-Durability)
   - **Energy-Bar** (visuell prominent, z.B. oben-links):
     - Farbcodiert: grün (70-100), gelb (30-69), orange (10-29), rot (0-9)
     - Current/Max Anzeige (z.B. "45/100")
     - "DEPLETED" Indikator bei 0 Energy mit gelbem Pulsieren
   - Gebäude-Platzierungs-Menü (2 Gebäude)
   - Hover-Info (Gebäude-Status: produziert X, wartet auf Y)
   - Tag-Anzeige (Tag 1, Tag 2, etc.)
   - **Nahrungs-Tipp bei low Energy**: "Low Energy! Eat 1 Berry for +10 Energy?" (optional, nicht aufdringlich)

9. **Victory Condition:**
   - Erreiche Tag 4 mit 25+ Holz produziert (automatisch durch NPC)
   - Beweist: Equilibrium funktioniert, Automatisierung fühlt sich gut an

10. **Einfache Karte:**
    - Single Map, prozedural generiert, 30×30 Tiles (PerlinNoise-basiert)
    - Bäume zum Fällen, Wiesen zum Durchsuchen

### Explicitly NOT in Vertical Slice

- ❌ Komplexe Produktionsketten (nur 1 Kette: Werkzeug → Holz)
- ❌ Mehrere Werkzeug-Typen (nur Einfaches Werkzeug)
- ❌ NPC-Transport (NPCs arbeiten nur in gebauten Gebäuden, kein Transport in VS)
- ❌ Save/Load (Vertical Slice = Session-only)
- ❌ Tutorial (direktes Experimentieren)
- ❌ Sound, Animation, Polish
- ❌ Multiple Gebäude-Typen über Lager/Wohnhaus/Holzfällerhütte hinaus

---

## MVP Definition (SECOND MILESTONE — after Vertical Slice validated)

**Core hypothesis validated** → Jetzt Scope erweitern auf shippable Prototype.

### Required for MVP (additional to Vertical Slice)

1. **+3 Ressourcen:** Weizen, Mehl, Brot (Nahrungsautomatisierung)

2. **+3 Gebäude:** Lager (zentraler Storage), Beerenstrauch-Garten (automatisiert Nahrung), Steinbruch (automatisiert Stein)

3. **+2 Produktionsketten:**
   - Weizen → Mehl → Brot (2-step chain)
   - Stein-Abbau (automatisiert)

4. **Save/Load System:**
   - JSON-basiert (human-readable, debuggable)
   - Speichert: Ressourcen, Gebäude, NPCs, Tag-Zähler

5. **Polished UI:**
   - Gebäude-Status-Dashboard (zeigt alle Gebäude auf einen Blick)
   - Bottleneck-Warnings (rot highlighten bei Input-Mangel)
   - Produktions-Stats (Bretter/Tag, Nahrung/Tag)

6. **Goal System:**
   - 3 Meilensteine: Tier 1 (10 Holz/Tag), Tier 2 (3 Gebäude automatisiert), Tier 3 (5 NPCs produktiv)
   - Victory Screen bei Erreichen aller Tiers

7. **Einfache Karte (größer):**
   - 50×50 Tiles, handdesignt
   - Mehr Ressourcen-Vorkommen

### Explicitly NOT in MVP (defer to Core Experience)

- ❌ Bevölkerungstiers (nur Tier 1 Arbeiter)
- ❌ Perk-System
- ❌ Handelssystem, Übermap
- ❌ Kleidung/Luxusgüter (nur Nahrung)
- ❌ Komplexe Werkzeuge (nur Einfaches Werkzeug)
- ❌ Tutorial (learn by doing)

---

### Scope Tiers

**Timeline Note:** Dies ist ein Hobby-Projekt mit flexibler Zeitplanung. Keine fixen Deadlines — Tiers definieren Scope, nicht Timeline.

| Tier | Ressourcen | Gebäude | Ketten | Features | Ziel |
| ---- | ---- | ---- | ---- | ---- | ---- |
| **Vertical Slice** | 3 (Holz, Beeren, Stein) | 3 (Lager, Wohnhaus, Holzfällerhütte) | 1 (Werkzeug → Holz) | Tick-System, manuelle Aktionen, 1 NPC, Hunger-Debuff, Equilibrium-Test | **Core Loop validieren:** Fühlt sich manual → automated gut an? |
| **MVP** | 6 (+ Weizen, Mehl, Brot) | 5 (+ Lager, Beerenstrauch-Garten, Steinbruch) | 3 (Holz → Bretter, Weizen → Brot, Stein-Abbau) | Nur Tier 1, nur Nahrung, kein Handel, Single Map, 3-5 Gebäude-Typen, 2-3 Werkzeug-Typen | **Shippable Prototype:** Beweis, dass System skaliert |
| **Core Experience** | 15 (+ Eisen, Werkzeuge, Wolle, Kleidung, Wein, etc.) | 12 (+ Schmiede, Weberei, Weinberg, Markt, etc.) | 8 (+ Werkzeug-Kette, Kleidungs-Kette, Wein-Kette) | **Bevölkerungstiers 1-3**, **Perk-System**, **Händler**, Übermap (3-5 Tiles), Lieferungen, polished UI, Tutorial | **Early Access Release:** Feature-complete, balanciert, polished |
| **Full Vision** | 25+ (alle Verbrauchsgüter + Luxus + viele Zwischenprodukte) | 20+ (spezialisierte Varianten, Upgrades) | 12+ (tiefe, mehrstufige Ketten) | NPC-Spezialisierungen, komplexes Handelsnetzwerk (Preise, Nachfrage), Achievements, Meta-Progression (New Game+), Steam-Integration (Cloud Save, Workshop-Support für Mods), Visual/Audio-Polish | **1.0 Release:** Alle Nice-to-Haves, maximale Tiefe |

**Scope-Hierarchie:**
- **Vertical Slice** — 6-8 Wochen, minimalster Core Loop (2 Ressourcen, 1 Kette, 1 NPC). Validiert Kern-Hypothese: "Ist manual → automated befriedigend?"
- **MVP** — Erweitert Slice auf 5 Ressourcen, 3 Ketten. Beweist, dass System skaliert. **Nicht** shippable (zu wenig Content für Verkauf).
- **Core Experience** — Shippable game. Feature-complete, balanciert, polished genug für Early Access/Steam.
- **Full Vision** — Dream game. Alle Features, maximale Tiefe, Community-Features (Mods, Achievements).

**Entscheidungsregel:** Shippe **Core Experience** als 1.0. Full Vision ist Post-Launch-Content (Updates, DLC). Vertical Slice ist Pre-MVP-Validation (6-8 Wochen Arbeit, entscheidet ob Konzept funktioniert).

---

## Visual Identity Anchor

*(Foundation for Art Bible — to be expanded in `/art-bible`)*

**Visual Direction: "Functional Clarity"**

**One-line visual rule:** *Every visual element serves readability and system transparency — beauty through clarity, not decoration.*

**Supporting principles:**

1. **Readable Over Realistic** — Exaggerated tile contrast (bright grass, dark forests), clear building silhouettes, high-contrast UI. Test: "Can I identify a building type from across the room?"

2. **Information Density** — Hover reveals layers (basic info always visible, detailed stats on hover, debug info on modifier key). Production states color-coded (green = running, yellow = waiting, red = blocked).

3. **Minimalist Medieval** — Authentic medieval shapes (timber frames, thatched roofs, cobblestone), but flat-colored or simple pixel art. No fantasy-kitsch (no glowing crystals, no dragons), but also not hyper-realistic.

**Color philosophy:** Earthy, muted palette for world (greens, browns, grays), high-saturation UI accents for actionable elements (blue for buildable, red for errors, green for success). Colorblind-friendly (no red/green-only indicators).

**Why this direction:** Aligns with Pillar 2 (Information Transparency) — the game is about understanding systems, so visuals must prioritize clarity over spectacle. Scope-friendly for solo dev (simple assets, reusable tiles).

---

## Architecture Decisions (Pre-GDD)

**Status:** Decisions made, ready for system GDD authoring.

### Time System ✅
1. **Tick-to-frame relationship:** Real-time with speed modifiers (1 real second = 10 Ticks basis, speeds: 0.5x/1x/2x/3x)
2. **Play/Pause semantics:** Pause freezes everything (Player + NPCs) until Play pressed
3. **Automated building behavior:** Buildings only produce when time runs (Pause = full stop)

### Economy System ✅
4. **Resource renewal model:** Anno-style resource tiles (Beeren/Holz/Stein tiles must exist in building radius, but are not depleted)
5. **Tool automation:** Deferred to post-MVP (manual crafting ~6 days)
6. **Tier 2-3 formulas:**
   - Tier 2: 2 Nahrung/Tag + 0.5 Kleidung/Tag, unlocks complex buildings (no speed bonus)
   - Tier 3: 3 Nahrung/Tag + 1 Kleidung/Tag + 0.2 Luxusgüter/Tag, unlocks high-end buildings
   - Principle: Higher tiers = access to complex chains, NOT speed multipliers
7. **Gold economy loop:**
   - Faucets: Sell goods to traveling merchants (interval-based) OR send caravan to other settlement
   - Sinks: Import rare resources, building upgrades, NPC training
   - Exchange rates: Fixed prices (Holz 2g, Werkzeug 25g, Luxusgüter 100-500g)
   - Inflation prevention: Fixed prices, expensive goods unlock later
8. **Continuous resource sinks:** Trading, building upgrades, complex production chains requiring inputs

### Spatial System ✅
9. **Building footprints:** 1 tile per building (MVP scope)
10. **Spatial optimization model:** Distance-based logistics (NPCs carry resources, distance = time per tile, belt-capacity limits, roads reduce transport time)
11. **Übermap structure:** Rimworld-style (NPCs travel between tiles on overworld instance for trade)

### NPC System ✅
12. **NPC visibility:** Routes visualized (arrows/lines), NPCs themselves not permanently visible
13. **NPC spawning gates:** 1 NPC spawns in MVP, later: recruitment process behind food surplus

### UI System ⏳
14. **Bottleneck visualization:** Deferred to `/ux-design` phase (dashboard + highlighting TBD)
15. **Production stats display:** Deferred to `/ux-design` phase (per-building vs global TBD)
16. **Dashboard structure:** Deferred to `/ux-design` phase (list vs grid vs tree TBD)

### Performance System ✅
17. **Target framerate:** 60fps
18. **Performance budgets:** 500MB memory ceiling, frame time TBD in architecture phase
19. **Physics:** Disabled (no use case for Jolt physics)

### Godot System ⏳
20. **Building representation:** Deferred to architecture phase (Scene tiles vs Atlas tiles vs Node2D instances TBD)
21. **Save/load format:** JSON (human-readable, not Resource class — Resources only for data definitions)

**Legend:**
- ✅ = Decided and documented
- ⏳ = Deferred to later phase (not blocking for GDD authoring)

---

## Acceptance Criteria

### Vertical Slice Victory Condition (Testable)
```
Victory Condition: Tag 4 Automatisierung
- Day 4 reached (tick >= 4000)
- Wood in storage >= 25
- Holzfällerhütte exists + 1 NPC assigned
Test Type: Integration (manual playtest)
Evidence: Screenshot showing Day 4, 25+ wood, NPC assigned
```

### MVP Tier Goals (Testable)
```
Tier 2 Goal: 3 Buildings Automated
- Building counts if: exists + NPC assigned
Test Type: Integration (manual playtest)
Evidence: Screenshot showing 3 buildings with NPCs

Tier 3 Goal: 5 NPCs Productive
- NPC counts if: assigned + no hunger debuff
Test Type: Logic (automated check: count NPCs where assigned == true AND hunger_debuff == false)
Evidence: Automated test pass
```

### Long-term Goals (Testable)
```
Bevölkerungsziel: 50 Einwohner
- Count total NPCs >= 50 (including 10 Handwerker, 3 Meister)
Test Type: Logic (automated count)

Wohlstandsziel: 10,000 Gold
- Gold counter >= 10000
Test Type: Logic (automated check)

Produktionsziel: 1,000 Luxusgüter
- Total Luxusgüter produced (lifetime counter) >= 1000
Test Type: Logic (automated check)

Selbstversorgungs-Ziel: 10 Consecutive Days Fully Supplied
- Tier "vollständig bedient" if: all NPCs received required goods at day transition + zero NPCs have debuff + production >= consumption (surplus exists)
- Victory: 10 consecutive days where ALL 3 tiers meet criteria
- Counter resets if any tier fails on any day
Test Type: Logic (automated state machine tracking consecutive days)
```

### System Tests (Required Evidence Before "Done")
| Feature | Test Type | Evidence Location | Gate |
|---------|-----------|-------------------|------|
| Tick System | Logic | `tests/unit/tick-system/` | BLOCKING |
| Hunger Debuff (affects NPCs) | Logic | `tests/unit/npc-system/` | BLOCKING |
| Tool Durability Consumption | Logic | `tests/unit/production/` | BLOCKING |
| Building Placement (1 tile) | Integration | `tests/integration/building-system/` | BLOCKING |
| NPC Resource Transport (distance-based) | Integration | `tests/integration/logistics/` | BLOCKING |
| Resource Tile Requirement (Anno-style) | Integration | `tests/integration/resource-system/` | BLOCKING |
| Save/Load (JSON) | Integration | `tests/integration/save-load/` | BLOCKING |
| Performance (60fps @ 100 buildings) | Performance | `production/qa/performance-[date].md` | ADVISORY |
| Memory (≤500MB) | Performance | `production/qa/performance-[date].md` | ADVISORY |

---

## Next Steps

- [x] Game concept created (this document)
- [ ] Run `/setup-engine` to configure Godot 4.6 and populate version-aware reference docs
- [ ] Run `/art-bible` to expand Visual Identity Anchor into full art specification (BEFORE writing GDDs — art decisions shape architecture)
- [ ] Use `/design-review design/gdd/game-concept.md` to validate concept completeness
- [ ] Decompose concept into systems with `/map-systems` — creates systems index with dependencies
- [ ] Author per-system GDDs with `/design-system [system-name]` for each system from map-systems
- [ ] Cross-system consistency check with `/review-all-gdds`
- [ ] Validate readiness with `/gate-check pre-production`
- [ ] Plan technical architecture with `/create-architecture`
- [ ] Record architectural decisions with `/architecture-decision` (one per major decision)
- [ ] Compile architecture into actionable rules with `/create-control-manifest`
- [ ] Validate architecture coverage with `/architecture-review`
- [ ] Prototype riskiest system with `/prototype core-automation-loop` (manual → NPC-assisted → automated)
- [ ] Document prototype playtest with `/playtest-report`
- [ ] If validated, plan first sprint with `/sprint-plan new`
