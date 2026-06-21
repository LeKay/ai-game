---
name: add-production-chain
model: claude-sonnet-4-6
description: "End-to-end-Implementierung einer neuen Produktionskette (z. B. wheat → flour → bread oder fiber → cloth): legt Rezepte und neue Ressourcen fest, bestimmt die nötigen Assets und schreibt deren AI-Prompts in eine neue Datei, definiert das Tick-Balancing, implementiert Code (building_registry / crafting_registry) und UI, verzahnt die Kette mit dem Progression-/Tech-Tree (Gating), aktualisiert die Design-Docs und verifiziert in Godot. Tabellengetrieben — der Skill kennt jede Stelle, die synchron gehalten werden muss."
argument-hint: "[kurze Beschreibung der Kette, z. B. 'wheat to flour to bread']"
user-invocable: true
allowed-tools: Read, Glob, Grep, Write, Edit, Bash, AskUserQuestion
---

# Add Production Chain

Dieser Skill implementiert eine **komplette neue Produktionskette** von der Idee bis
zum lauffähigen Gebäude im Spiel. Eine Produktionskette ist eine Folge von
Transformationen (Input → Gebäude/Hand → Output), oft mehrstufig
(`wheat → flour → bread`), die über mehrere Daten-, Code-, UI- und Doc-Dateien
verteilt implementiert wird.

**Kernproblem, das dieser Skill löst:** Eine Kette berührt **viele Sync-Tabellen**.
Vergisst man eine, schlägt sie still fehl (Gebäude erscheint nicht im Baumenü, rendert
mit Fallback-Symbol, Produktion startet nie). Der Skill führt durch jede Stelle.

**Dieser Skill schreibt die Dateien direkt selbst** (keine Subagent-Delegation) — die
Arbeit ist stark tabellengetrieben und passt in einen Kontext.

> **Kollaborationsprotokoll (CLAUDE.md):** Vor jedem Write/Edit den Diff bzw. Entwurf
> zeigen und fragen „Darf ich das nach [Pfad] schreiben?". Mehrdateien-Änderungen
> brauchen explizite Freigabe des gesamten Changesets. Keine Commits ohne Anweisung.

---

## Referenz: Die Touch-Liste (alle Sync-Stellen)

Bevor du startest, präge dir diese Karte ein. **Jede neue Produktionskette berührt eine
Teilmenge davon.** Prüfe am Ende jede Zeile explizit.

| # | Datei | Was | Pflicht? |
|---|-------|-----|----------|
| 1 | `data/resources.json` | Neue Ressourcen (Roh-/Zwischen-/Endprodukt) | wenn neue Items |
| 2 | `src/gameplay/building_registry.gd` → `BuildingType` enum | Neuer Gebäudetyp | bei Gebäude-Rezept |
| 3 | `building_registry.gd` → `BUILD_COST` | Platzierungskosten | bei Gebäude |
| 4 | `building_registry.gd` → `BUILD_TIME` | Bau-Ticks | bei Gebäude |
| 5 | `building_registry.gd` → `BUILD_ENERGY` | Energie f. manuellen Bau | bei Gebäude |
| 6 | `building_registry.gd` → `BUILDING_TEXTURES` | Tile-Texturpfad | bei Gebäude |
| 7 | `building_registry.gd` → `ADJACENCY_REQUIREMENTS` | Terrain-Bindung | nur falls terrain-gated |
| 8 | `building_registry.gd` → `TERRAIN_HARVEST_OUTPUT` | Gathering-Output | nur Gathering-Typ |
| 9 | `building_registry.gd` → `RECIPES` | Array von Rezept-Dicts (Hauptrezept + optionale Alternativen) | bei Gebäude-Produktion |
| 10 | `building_registry.gd` → `_building_type_name()` | Anzeigename (match) | bei Gebäude |
| 11 | `src/gameplay/crafting_registry.gd` (6 Tabellen) | Manuelles Spieler-Rezept | nur falls Hand-Craft |
| 12 | `src/ui/screens/inventory_screen.gd` → `_building_list()` | **Baumenü-Eintrag** | bei Gebäude (sonst nicht baubar!) |
| 13 | `src/ui/components/building_grid.gd` → `_building_icon()` | Emoji im Baumenü | bei Gebäude (sonst 🏛️) |
| 14 | `src/ui/components/transportation_panel.gd` (Emoji-match) | Emoji in Logistik-UI | bei Gebäude |
| 15 | `assets/art/ai-prompts/` (**neue Datei**) | AI-Prompts der neuen Assets | bei neuen Assets |
| 16 | `design/gdd/recipe-database.md` + `building-system.md` | Design-Doku | immer |
| 17 | `data/resources.json` → `icon_path` für **alle** neuen Ressourcen | UI-Icon-Pfad vorhanden? `assets/ui/icons/resources/<id>.png` | immer bei neuen Items |
| 18 | `assets/ui/icons/resources/<id>.png` + `.import` | Raster-Icon für Transport-Animation + UI | wenn Icon-PNG vorhanden |
| 19 | `src/systems/world_grid.gd` → `TileType` enum | Neuer Boden-/Terrain-Typ | nur bei neuem Terrain-Typ (z. B. Weizenfeld, Lehmgrube) |
| 20 | `src/scenes/map_root/terrain_renderer.gd` → `_TERRAIN_PNG_VARIANTS` + `_TERRAIN_FALLBACK_COLORS` | **Alle** Tile-Varianten + Fallback-Farbe für neuen Terrain-Typ | nur bei neuem Terrain-Typ |
| 21 | `data/progression_tree.json` → `nodes[]` | Tech-Tree-Knoten, der das neue Gebäude/Rezept/Gathering **gated** | wenn die Kette ins Tech-Tree soll (Default: **ja**) |
| 22 | `data/progression_tree.json` → `config.branch_angles_deg` (+ `branch_count`) | Winkel für einen **neuen** Branch | nur bei neuem Branch |

> **⚠️ PROGRESSION-GATE IST DEFAULT-OFFEN, NICHT GESPERRT.** Inhalte, die in
> `data/progression_tree.json` **nicht** gemappt sind, gelten als **freigeschaltet**
> (`ProgressionSystem.is_*_unlocked` → `true` bei unbekanntem Content). Eine neu
> hinzugefügte Kette ist also **sofort verfügbar und NICHT gated**, solange du sie nicht
> in den Tree einträgst. Das ist Absicht (nichts blockiert still), heißt aber: du musst
> **bewusst entscheiden**, ob/wie die Kette ins Tech-Tree gehört — siehe Phase 7. Für
> gameplay-relevante Ketten lautet die Antwort fast immer „ja".

> **`INPUT_RESOURCES` existiert nicht mehr** — Inputs sind seit dem Multi-Rezept-System
> direkt in jedem Rezept-Dict unter `"inputs"` eingebettet (→ `RECIPES[type][i]["inputs"]`).
> Niemals einen `INPUT_RESOURCES`-Eintrag anlegen.

> **Transport-Animation (`route_lines.gd`):** Der Carrier-Icon auf der Karte nutzt
> `ResourceRegistry.get_icon_texture()` — Priorität: `world_icon_path` → `icon_path` → Fallback-Kreis.
> Verarbeitungsressourcen (kein Terrain-Spawn) brauchen **zwingend** ein `icon_path`-PNG unter
> `assets/ui/icons/resources/<id>.png`, damit der Carrier das richtige Icon zeigt statt eines
> grauen Kreises. Das PNG muss zusammen mit einer `.import`-Datei committet werden.
> Touch-Punkte #17 und #18 erfassen diesen Schritt.

> **`building_detail_panel.gd` braucht KEINE Änderung** — es liest `RECIPES`,
> `get_active_recipe()` und `buffered_output` dynamisch und zeigt automatisch den
> Rezept-Selector, sobald ein Gebäude mehr als ein Rezept hat. Nicht anfassen.

> **`LogisticsSystem` invalidiert Routen automatisch** — bei einem Rezeptwechsel durch
> den Spieler werden Input-Routen für Ressourcen, die das neue Rezept nicht mehr braucht,
> selbsttätig gelöscht. Kein manueller Eingriff nötig.

> **Bekannte Inkonsistenz als Mahnung:** `building_grid.gd:_building_icon()` hat aktuell
> kein Icon für `STONE_MASON` → der Steinmetz rendert im Baumenü mit Fallback 🏛️.
> Genau dieser Fehlertyp (Tabelle #13 vergessen) soll mit diesem Skill nicht mehr passieren.

---

## Phase 1: Kette und Rezepte feststellen

Lies das Argument. Fehlt es, frage: „Welche Produktionskette sollen wir bauen?
Beschreibe Input → Zwischenprodukte → Endprodukt."

**Lies zuerst den Ist-Zustand**, um an Bestehendes anzuknüpfen, statt zu duplizieren:
- `data/resources.json` — welche Ressourcen existieren bereits?
- `src/gameplay/building_registry.gd` — `RECIPES`, `BuildingType`, `ADJACENCY_REQUIREMENTS`
- `design/gdd/recipe-database.md` — Rezept-Schema und Designziele

Lege dann für **jede Stufe** der Kette unmissverständlich fest und kläre per
`AskUserQuestion`, wo eine echte Designentscheidung offen ist:

1. **Manuell oder Gebäude?** — `crafting_registry.gd` (Spieler craftet von Hand, blockiert
   Spieler-Aktion für `tick_cost`) **oder** `RECIPES` (Gebäude + zugewiesener NPC,
   Schleifenbetrieb). Faustregel: Frühe/einfache Rezepte manuell, Skalierung über Gebäude.
2. **NPC-Pflicht?** (`npc_required`) — fast immer `true` für Produktionsgebäude.
3. **Terrain-Bindung?** (`ADJACENCY_REQUIREMENTS`) — braucht das Gebäude angrenzendes
   Terrain (wie Lumber Camp → TREE, Stone Mason → STONE)? Falls ja, läuft die Effizienz
   über F6 (Adjazenz × Worker), nicht über die Worker-Standardformel.
4. **Logistik?** — Inputs/Outputs werden von Carrier-NPCs zwischen Gebäuden bewegt
   (LogisticsSystem). Ohne Carrier blockiert das Gebäude mit „No carrier assigned (inputs)",
   sofern Inputs nicht manuell geladen werden. Bei mehrstufigen Ketten klären, ob der
   Spieler Routen legen muss.
5. **Tool-Verbrauch?** — Produktionsgebäude verbrauchen typ. 1 Werkzeug/Zyklus
   (`{"resource_id": &"tool", "quantity": 1}` in `inputs`).
6. **Fallback-Rezept?** — Soll das Gebäude ein alternatives, schwächeres Rezept ohne
   spezielle Inputs haben (z. B. „Ohne Werkzeug")? Regeln:
   - Sinnvoll, wenn das Hauptrezept knappe Vorleistungen braucht (Tools, Zwischenprodukte)
     und der Spieler ohne diese komplett blockiert wäre.
   - **Nicht** sinnvoll für Gathering-Huts (keine Inputs ohnehin) oder einfache Verarbeitungen
     mit immer verfügbaren Basis-Inputs.
   - Das Fallback-Rezept läuft als zweites Element in `RECIPES[type]` (Index 1+).
   - Typisches Verhältnis: Fallback produziert ~40 % des Outputs in ~3× der Zykluszeit
     (→ ~8× schlechtere Ressourcen-/Zeit-Rate).
7. **Progression-Gating?** — Soll die Kette hinter dem Tech-Tree liegen (Default: **ja**
   für jede gameplay-relevante Kette)? Falls ja, ist die **Einbettung eine echte
   Designentscheidung, die du in Phase 7 explizit mit dem Nutzer klärst** (an welchen
   vorhandenen Knoten/Branch hängt die Kette, welche Stufen bekommen eigene Knoten, welche
   Voraussetzungen). Hier in Phase 1 nur grob vormerken (gated: ja/nein, grober Branch);
   die genauen `prerequisites` werden in Phase 7 per `AskUserQuestion` festgelegt.

**Output dieser Phase — ein Ketten-Spec** (im Chat zeigen, bestätigen lassen):

```
Kette: wheat → flour → bread
Stufe 1: Wheat Field (Gebäude, Gathering, Terrain GRASS) → wheat
Stufe 2: Mill (Gebäude, NPC, Input wheat ×2 + tool ×1) → flour
         Fallback: „Ohne Werkzeug" (Input wheat ×2) → flour ×1, 750 Ticks (vs. 3/250 Ticks)
Stufe 3: Bakery (Gebäude, NPC, Input flour ×2 + tool ×1) → bread
         Kein Fallback (Mehl ist immer ausreichend verfügbar, Tool ist nicht knapp genug)
Neue Ressourcen: wheat, flour   (bread existiert bereits)
Neue Gebäude: Wheat Field, Mill, Bakery
Progression: gated, food-Branch (genaue Prereqs in Phase 7 mit Nutzer klären)
```

---

## Phase 2: Neue Ressourcen definieren (`data/resources.json`)

Für **jede** neue Ressource der Kette einen Eintrag ergänzen. Schema (siehe
`ResourceRegistry._validate_resource` für Pflichtfelder):

```json
{
  "id": "flour",
  "display_name": "Flour",
  "category": "production_good",          // "consumable" | "production_good"
  "subcategory": "intermediate",          // raw_material | intermediate | tool | food
  "stack_limit": 99,
  "weight": 1.0,
  "base_value": 5,                        // treibt Effizienz-/Wert-Formeln
  "max_charge": 100.0,
  "movement_cost": 4.0,
  "icon_path": "assets/ui/icons/resources/flour.png",
  "glyph": "🌾",                          // UI-Fallback-Emoji (Pflicht für saubere UI)
  "description": "Ground wheat, ready for baking.",
  "tags": []
  // optional bei Terrain-Ressourcen: "world_icon_path", "fallback_color": [r,g,b]
  // optional bei Nahrung: "nutrition": <float>   (0 = ungenießbar)
}
```

Regeln:
- `id` ist eindeutig und unveränderlich (lowercase, snake_case).
- `glyph` immer setzen — sonst zeigt die UI 📦. Endprodukt-Nahrung braucht `nutrition`.
- Nur Roh-Ressourcen, die als Terrain auf der Karte abbaubar sind, brauchen
  `world_icon_path` + `fallback_color`.

`version` und `last_updated` oben in der Datei bei Bedarf aktualisieren.

---

## Phase 3: Assets feststellen und AI-Prompts anlegen

### 3a. Asset-Liste bestimmen

Pro neuem Element der Kette ein Asset:
- **Pro neuem Gebäude:** ein Tile `bld_tile_<name>.png` (transparenter Hintergrund,
  leicht isometrisch ~60–70°).
- **Pro neuer Ressource:** ein UI-Icon `assets/ui/icons/resources/<id>.png`; falls als
  Terrain abbaubar zusätzlich ein World-Tile `env_tile_resource_<id>.png`.

### 3b. AI-Prompts in eine NEUE Datei schreiben (Referenz + Fallback)

Lege eine **neue** Markdown-Datei an:
`assets/art/ai-prompts/<ketten-slug>-prompts.md`
(z. B. `bread-chain-prompts.md`). **Nicht** an `sprite-prompts.md` anhängen — pro Kette
eine eigene Datei.

Lies vorher `assets/art/ai-prompts/sprite-prompts.md` als Stil-Referenz und übernimm
**diese verbindlichen Orientierungen** in den Kopf der neuen Datei (sie sind die DNA
aller Prompts dieses Projekts):

**Globale Perspektive (Tiles von oben / Objekte leicht isometrisch):**
- Terrain-Tiles: strikt von direkt oben (Kamera senkrecht nach unten), nur Oberseite
  sichtbar, Tiefe nur durch Schattierung.
- Gebäude / Ressourcen-Overlays / NPCs: leicht erhöhter Winkel ~60–70° über dem Horizont
  („classic top-down RPG perspective") — Oberseite plus schmaler Frontstreifen sichtbar.

**Konsistenz-Regeln (für alle):**
- Lichtquelle oben-links, Schatten fallen nach unten-rechts.
- Palette erdig und gedämpft — keine gesättigten Neonfarben.
- 2–3 Schattierungsstufen pro Farbe (Highlight, Midtone, Shadow).
- Keine Outline um das gesamte Objekt — nur interne Tiefenlinien.

**Komposition Resource-Overlay & Gebäude (transparenter Hintergrund):**
- Objekt exakt zentriert, gleicher Abstand zu allen vier Kanten.
- Vollständig sichtbar, kein Teil abgeschnitten, ≥ 2–4 px Abstand zu jeder Kante.
- Hintergrund vollständig transparent — kein Boden, kein Rahmen, kein Fülldetail.
- Gebäude: Footprint ~18–20 px breit, ~14–16 px hoch; Satteldach (Highlight links,
  Schatten rechts), schmaler Frontwand-Streifen mit Tür (~3×4 px); ein
  charakteristisches Betriebs-Requisit seitlich/davor zur Unterscheidbarkeit
  (Holzstapel = Lumber, Amboss = Toolmaker, Stoffballen = Tailor …).

**Format jedes Prompt-Eintrags** (exakt wie in `sprite-prompts.md`):

```markdown
### <Nr>. <Deutscher Name> / <English Name> — `bld_tile_<name>.png`

<1-Satz-Beschreibung: was es ist + erkennbares Betriebs-Requisit>

**Prompt:**
` ` `
<englischer Bildprompt, ~1 Absatz, in der Projekt-Diktion: Perspektive nennen,
Dach/Wände/Requisit beschreiben, Licht oben-links, "Everything outside ... is
fully transparent.">
` ` `

**Zielfarben:** Dach-Highlight `#…` · Dach-Mitte `#…` · Dach-Schatten `#…` · Wand `#…` · Tür `#…` · <Requisit> `#…`
**Hintergrund:** Transparent
```

Am Dateiende den **Atlas-Assembly-Hinweis** und die **Nächste-Schritte-Liste**
übernehmen (Pixellab → PNG export → in `assets/art/tiles/` bzw.
`assets/art/resources/` ablegen → Import-Settings Filter=Nearest, Mipmaps=Disabled →
im Editor gegen Art Bible prüfen).

> Die Prompts-Datei ist primär **Referenz und Audit-Trail**. Die Generierung selbst
> übernimmt Phase 3c via direktem API-Call. Bis die PNGs existieren, greift der Code-Fallback
> (`BUILDING_TEXTURES.get(..., storage)` bzw. `glyph`/`fallback_color`).

---

### 3c. Assets via PixelLab API generieren (direkt)

> **⛔ PFLICHTSCHRITT — DARF NICHT ÜBERSPRUNGEN WERDEN.**
> Phase 3c ist kein optionaler Schritt. Die PNGs MÜSSEN in derselben Session generiert
> werden, in der Phase 3b die Prompts anlegt. Ohne PNGs rendert das Gebäude im Spiel
> mit dem Storage-Fallback-Tile und der Carrier zeigt einen grauen Kreis statt eines Icons.
> Nach dem Schreiben der Prompts (3b) direkt in 3c weitermachen — kein Commit, kein
> Abschluss-Summary ohne generierte Assets.

**Dieser Schritt generiert die PNGs direkt** — kein manueller Pixellab-Aufruf durch den
Nutzer nötig. Wir nutzen `POST /v2/create-image-pixen` direkt via Python `urllib` —
**kein MCP**, kein Polling, synchron, ein Bild pro Call.

#### API-Key-Handling — PFLICHT

> **NIEMALS** den API-Key als Literal in einem Bash-Befehl oder Script hardcoden —
> der Sandbox-Classifier blockt den Call bei "credential leakage" (Key sichtbar im
> Shell-Argument). Stattdessen:
>
> 1. Key liegt in `~/.pixellab_key` (plain text, eine Zeile). Er ist im Memory unter
>    `reference_pixellab_api.md` gespeichert.
> 2. Scripts lesen den Key immer per `Path.home() / ".pixellab_key"` oder
>    `os.environ.get("PIXELLAB_API_KEY")`.
> 3. Bash-Calls rufen nur `python3 <script>` auf — kein Key im Command.
>
> Wenn `~/.pixellab_key` fehlt: erst per `python3 -c "from pathlib import Path;
> Path.home().joinpath('.pixellab_key').write_text('<key>')"` schreiben
> (Key kommt aus Memory), dann Script aufrufen.

**Empfohlenes Vorgehen:** Für jede Kette ein dediziertes Generator-Script anlegen
(`assets/art/ai-prompts/generate_<slug>_assets.py`), das den Key aus der Datei liest.
So ist das Script commitbar (kein Geheimnis drin) und direkt per Bash aufrufbar.

#### Vorbereitung: Kontostand prüfen und Freigabe einholen

```python
# balance_check.py — Key kommt aus ~/.pixellab_key
import urllib.request, json
from pathlib import Path

key = Path.home().joinpath('.pixellab_key').read_text().strip()
req = urllib.request.Request(
    'https://api.pixellab.ai/v2/balance',
    headers={'Authorization': f'Bearer {key}'},
)
with urllib.request.urlopen(req) as resp:
    print(json.load(resp))
```

Zeige dem Nutzer den Kontostand und liste die Assets auf, die du generieren willst
(Name, Typ, Zieldatei). Frage explizit: „Darf ich diese N Assets generieren?" —
Generierungen verbrauchen Credits und sind nicht umkehrbar.

#### Pflichtregeln für jeden API-Call — NIEMALS abweichen

> **Größe:** IMMER `"width": 64, "height": 64` — alle Projekt-Tiles sind 64×64 px.
> 32×32 erzeugt ein zu kleines Tile, das im Godot-Renderer falsch skaliert erscheint.
>
> **Zielfarben:** Die Hex-Farbwerte aus dem Prompt in 3b MÜSSEN in die `description`
> eingebettet werden. Format am Ende der Description:
> `Color palette: roof highlight #C8B068, roof midtone #A07840, shadow #6B4E28, …`
> Ohne Farben weicht das Ergebnis von der Art-Bible-Palette ab und muss neu generiert werden.
>
> **Feste Parameter:**
> - `view`: `"high top-down"` (Art-Bible: ~60–70° für alle Gebäude- und Ressource-Tiles)
> - `outline`: `"lineless"` (Art-Bible: keine Gesamt-Outline)
> - `detail`: `"highly detailed"`
> - `no_background`: `true`

#### API-Call-Vorlage (für alle Asset-Typen)

```python
# generate_<slug>_assets.py — commitbar, kein Key im Code
import urllib.request, json, base64, os
from pathlib import Path

def _load_key():
    key = os.environ.get('PIXELLAB_API_KEY', '')
    if not key:
        key = (Path.home() / '.pixellab_key').read_text().strip()
    return key

KEY = _load_key()
HEADERS = {'Authorization': f'Bearer {KEY}', 'Content-Type': 'application/json'}

payload = {
    'description': (
        '<englischer Bildprompt aus Phase 3b, vollständig>'
        ' Color palette: <Zielfarben aus 3b als kommaseparierte Liste mit Hex-Codes>.'
    ),
    'image_size': {'width': 64, 'height': 64},   # IMMER 64×64 — nicht ändern
    'view': 'high top-down',
    'detail': 'highly detailed',
    'outline': 'lineless',
    'no_background': True,
}

data = json.dumps(payload).encode('utf-8')
req = urllib.request.Request(
    'https://api.pixellab.ai/v2/create-image-pixen',
    data=data, headers=HEADERS, method='POST',
)
with urllib.request.urlopen(req) as resp:
    d = json.load(resp)

img = d['image']['base64']
if ',' in img:
    img = img.split(',', 1)[1]
png = base64.b64decode(img)
with open('assets/art/tiles/bld_tile_<name>.png', 'wb') as f:
    f.write(png)
print(f'Saved ({len(png)} bytes)')
```

**Zielpfade nach Asset-Typ:**

| Asset | Zielpfad |
|-------|----------|
| Gebäude-Tile | `assets/art/tiles/bld_tile_<name>.png` |
| World-Ressource-Overlay | `assets/art/tiles/env_tile_resource_<id>.png` |
| UI-Icon (Carrier-Animation) | `assets/ui/icons/resources/<id>.png` |

> **`.import`-Sidecar:** Godot erzeugt die `.import`-Datei automatisch beim nächsten
> Editor-Scan. Nicht manuell anlegen. Nach dem Kopieren den Editor einmal neu starten
> oder „Reimport" im FileSystem-Dock triggern.

#### Nach der Generierung: Konsistenzprüfung

- Vergleiche die generierten PNGs visuell gegen die Stil-Orientierungen aus 3b
  (Perspektive, Palette, Licht). Bei starker Abweichung: erneut generieren mit
  präzisierterer `description`.
- Prüfe, ob Gebäude-Tiles zur Referenz in `sprite-prompts.md` passen (Palette, Größe).
- Fehlende PNGs nie stillschweigend überspringen — Code-Fallback ist temporär,
  nicht dauerhaft akzeptabel.

---

### 3d. Boden-/Terrain-Tiles via create-tiles-pro (NICHT pixen)

Manche Ketten führen einen neuen **Boden-/Terrain-Typ** ein, der das Tile **randlos von
Kante zu Kante** füllt und kachelbar sein muss (z. B. **Weizenfeld**, **Lehmgrube**) — kein
zentriertes Objekt auf transparentem Hintergrund. Dafür ist `create-image-pixen` (3c)
**ungeeignet** (es liefert ein zentriertes Objekt auf transparentem Hintergrund). Bevorzugter
Endpoint für Boden-Tiles ist **`create-tiles-pro`** (erprobt 2026-06-18; liefert mehrere
64×64-Varianten eines Tiles).

> Es gibt auch `/create-tileset` (Zwei-Ebenen-Wang-Generator, `tile_size` nur 16/32 px,
> Retrieval über `/tilesets/{tileset_id}`). Für einfache flache Varianten-Böden **nicht** nötig —
> `create-tiles-pro` kann direkt 64 px und ist der Standardweg.

**Endpoint:** `POST https://api.pixellab.ai/v2/create-tiles-pro` — **asynchron**: liefert eine
`background_job_id`. Quelle: OpenAPI `https://api.pixellab.ai/v2/openapi.json`.

**Request-Felder (laut OpenAPI):**

| Feld | Pflicht | Wert für unsere flachen Boden-Tiles |
|------|---------|--------------------------------------|
| `description` | **ja** | Terrain-Prompt + Farbpalette als Text (kein eigenes `color_palette`-Feld) |
| `tile_type` | opt | `"square_topdown"` (Enum: `hex`, `hex_pointy`, `isometric`, `octagon`, `square_topdown`) |
| `tile_size` | opt | `64` (Range 16–256 — anders als `/create-tileset`, das nur 16/32 kann) |
| `tile_view_angle` | opt | `90.0` (0–90°, überschreibt `tile_view`) → senkrecht von oben |
| `tile_depth_ratio` | opt | `0.0` (Dicke/Thickness aus) |
| `seed` | opt | fester Wert (z. B. `42`) für Reproduzierbarkeit |
| `tile_view` | opt | Enum `top-down` \| `high top-down` \| `low top-down` \| `side` (nur falls kein `tile_view_angle`) |

> Es gibt **kein** `outline`/`detail`/`color_palette`-Feld — Stil/Palette in die `description`
> schreiben. Die ursprünglichen Web-UI-Werte (square / 64 px / view angle 90° / thickness 0 %)
> bilden sich exakt auf `tile_type "square_topdown"` + `tile_size 64` + `tile_view_angle 90` +
> `tile_depth_ratio 0.0` ab.

**Retrieval (WICHTIG — der knifflige Teil):**
- **NICHT** `GET /tiles-pro/{id}` mit der Job-ID (→ 404 „Tile not found"); eine `/tiles-pro`-Liste
  existiert nicht.
- Pollen über den **generischen Job-Endpoint** `GET /v2/background-jobs/{background_job_id}`.
  Bei `status == "completed"` liegen die Tiles unter **`last_response.images[]`** (für
  `square_topdown` 16 Stück), jedes mit `width`, `height` und `base64`.

> **⚠️ GOTCHA — `images[].base64` ist KEIN PNG, sondern rohes RGBA8** (`width*height*4` Bytes,
> z. B. 64×64 → 16384 Bytes). Speichert man diese Bytes direkt als `.png`, scheitert der
> Godot-Import („Error importing …"). **Vor dem Speichern in PNG enkodieren**, z. B. mit Pillow:
> `Image.frombytes("RGBA",(w,h),raw).save(path)`. (Zum Vergleich: `create-image-pixen` in 3c
> liefert eine echte `data:image/png;base64,…`-URI — die wird nur base64-dekodiert.)

**Workflow:**
1. `POST /create-tiles-pro` je Boden-Typ → `background_job_id` merken.
2. `GET /background-jobs/{job_id}` pollen bis `status == "completed"`.
3. Jedes `last_response.images[i].base64` base64-dekodieren → **rohes RGBA → PNG enkodieren**
   (Pillow) → als `assets/art/tiles/env_tile_<type>_NN.png` speichern (NN = `01`, `02`, …).
4. Neuen Wert in `src/systems/world_grid.gd` → `TileType` ergänzen (Touch-Liste #19).
5. **Alle** Varianten-Pfade in `src/scenes/map_root/terrain_renderer.gd` →
   `_TERRAIN_PNG_VARIANTS[<TileType-Index>]` eintragen; Fallback-Farbe an gleicher
   Index-Position in `_TERRAIN_FALLBACK_COLORS` ergänzen (Touch-Liste #20). Der Renderer
   baut daraus den Atlas und wählt pro Tile via `(x*7 + y*13) % count` eine Variante.
6. `.import`-Sidecars entstehen beim nächsten Editor-Scan automatisch.

> **Abgrenzung pixen ↔ tiles-pro:** Zentrierte Einzel-Assets (Resource-Overlays
> `env_tile_resource_*`, UI-Icons, Gebäude `bld_tile_*`, NPC-Icons, Marker) bleiben beim
> **pixen**-Endpoint (3c, echtes PNG). Nur randlose, kachelbare **Boden-/Terrain-Tiles** nutzen
> **create-tiles-pro** (rohes RGBA → PNG enkodieren). Ein neuer Terrain-Typ braucht meist BEIDES:
> das Boden-Tile (tiles-pro, Varianten) **und** das Resource-Overlay des darauf abbaubaren Guts
> (pixen, einzeln) — so wie GRASS-Boden + `fiber`-Overlay oder TREE-Boden + `wood`-Overlay.

> **Doku-Hinweis:** Felder/Enums und Job-Flow vor dem Skripten gegen
> `https://api.pixellab.ai/v2/openapi.json` gegenprüfen. Auth wie bei pixen:
> `Authorization: Bearer <key>`. Vorab `GET /v2/balance` zeigen + Freigabe einholen
> (Generierungen kosten Credits, nicht umkehrbar).

---

## Phase 4: Balancing (Ticks) festlegen

**Anker-Wissen dieses Projekts (Stand Balancing 2026-06-11) — fest in jede Rechnung:**
- **1 Tick ≈ 1 Minute, 1440 Ticks = 1 Spieltag.** Der Tag ist eine echte Planungseinheit.
- Basis-Produzenten: `base_cycle_ticks ≈ 250` → **~5–6 Zyklen/Tag**.
- Komplexere Verarbeitung (z. B. Tool Workshop): `base_cycle_ticks ≈ 375` → ~4 Zyklen/Tag.
- **Effektive Zyklusdauer = `base_cycle_ticks / building_efficiency`** (F3, live pro Tick).
  Effizienz 1.0 → base; 0.5 → 2× base; 0.25 → 4× base. Hunger/schlechte Platzierung
  verlangsamen real.
- Bau-Zeiten (`BUILD_TIME`) in Stunden-bis-Tagen: Hütte ≈ 640 (~0.4 Tag),
  Haus/Camp/Mason ≈ 1200–1600 (~0.8–1.1 Tage), Workshop ≈ 3000 (~2 Tage).
- Manuelle Rezepte (`crafting_registry.RECIPE_TICKS`): advancen die Weltuhr via
  `advance_ticks_manual`; Tool ≈ 90 Ticks (~1.5 h Arbeit).
- 1 Werkzeug wird pro Zyklus für werkzeugnutzende Gebäude verbraucht.

**Für jede Stufe festlegen:** `base_cycle_ticks`, `output`-Menge, `output_capacity`
(typ. 20, Workshop 10), `input_capacity` (typ. 5–10), Bau-Kosten/-Zeit/-Energie.

### Balancing von Fallback-Rezepten

Falls Phase 1 ein Fallback-Rezept ergeben hat, nach diesen Leitlinien skalieren:

| Kennzahl | Hauptrezept | Fallback-Ziel | Begründung |
|----------|-------------|---------------|------------|
| Output pro Zyklus | z. B. 5 | ~40 % → 2 | deutlich weniger — Tool-Kosten fehlen |
| `base_cycle_ticks` | z. B. 250 | ~3× → 750 | Handarbeit dauert länger |
| Effektive Rate (Output/Tick) | 5/250 = 0.020 | 2/750 = 0.0027 | ~7–8× schlechter — Spieler wird motiviert, Tools zu beschaffen |
| `input_capacity` | 5 | 0 (keine Inputs) | kein Buffer nötig |
| `npc_required` | true | true | NPC arbeitet trotzdem |

**Faustregel:** Das Fallback soll die Siedlung am Laufen halten, aber nicht konkurrenzfähig sein.
Ein Spieler mit Tool-Supply soll klar belohnt werden (7–8× höhere Effizienz-Rate).

**Sanity-Check der Kette:** Stelle sicher, dass der Durchsatz der Stufen ungefähr
zusammenpasst (Stufe-1-Output/Tag ≥ Stufe-2-Input-Bedarf/Tag), sonst entsteht sofort ein
Engpass. Wenn `tools/balance/` existiert, dort die Kette gegenrechnen; siehe auch
`design/quick-specs/efficiency-system-*.md`. Werte als Quick-Spec-Tabelle zeigen und
bestätigen lassen, bevor sie in den Code gehen.

---

## Phase 5: Implementierung im Code

Arbeite die Touch-Liste #1–#11 ab. **Zeige den geplanten Diff je Datei und hole Freigabe**,
bevor du editierst.

### `building_registry.gd` (pro neuem Gebäude)

Reihenfolge wie im Enum/den Tabellen einhalten, **alle** Tabellen ergänzen — eine
vergessene Tabelle = stiller Bug. Zentrale Änderung gegenüber altem System:
**`RECIPES` ist ein Array pro Typ**, Index 0 = Standardrezept, Index 1+ = Alternativen.
`INPUT_RESOURCES` und die frühere `PRODUCTION_TABLE` existieren nicht mehr.

```gdscript
# 1. Enum
enum BuildingType {
    …
    MILL,   ## mahlt Wheat zu Flour; Fallback ohne Werkzeug verfügbar
}

# 2.–5. je ein Eintrag
const BUILD_COST    = { … BuildingType.MILL: {&"wood": 10, &"stone": 5}, }
const BUILD_TIME    = { … BuildingType.MILL: 1600, }
const BUILD_ENERGY  = { … BuildingType.MILL: 30, }
const BUILDING_TEXTURES = { … BuildingType.MILL: "res://assets/art/tiles/bld_tile_mill.png", }

# 6. (nur falls terrain-gated) ADJACENCY_REQUIREMENTS
# 7. (nur Gathering) TERRAIN_HARVEST_OUTPUT

# 8. RECIPES — Array pro Typ; Index 0 = Hauptrezept, Index 1 = Fallback (optional)
const RECIPES: Dictionary = {
    …
    BuildingType.MILL: [
        # Hauptrezept (Index 0): mit Werkzeug, effizienter Output
        {
            "id": &"with_tool",
            "label": "Mit Werkzeug",
            "inputs": [
                {"resource_id": &"wheat", "quantity": 2},
                {"resource_id": &"tool",  "quantity": 1},
            ],
            "output": {&"flour": 3},
            "output_capacity": 20,
            "input_capacity": 10,
            "base_cycle_ticks": 250,
            "npc_required": true,
        },
        # Fallback (Index 1): ohne Werkzeug, deutlich langsamer und schwächer
        {
            "id": &"bare_hands",
            "label": "Ohne Werkzeug (langsam)",
            "inputs": [
                {"resource_id": &"wheat", "quantity": 2},
            ],
            "output": {&"flour": 1},
            "output_capacity": 20,
            "input_capacity": 10,
            "base_cycle_ticks": 750,
            "npc_required": true,
        },
    ],
    # Gebäude ohne Fallback: einfaches Array mit einem Element
    BuildingType.BAKERY: [
        {
            "id": &"bake",
            "label": "Backen",
            "inputs": [
                {"resource_id": &"flour", "quantity": 2},
                {"resource_id": &"tool",  "quantity": 1},
            ],
            "output": {&"bread": 4},
            "output_capacity": 20,
            "input_capacity": 10,
            "base_cycle_ticks": 300,
            "npc_required": true,
        },
    ],
}

# 9. Anzeigename
func _building_type_name(building_type: int) -> String:
    match building_type:
        …
        BuildingType.MILL:   return "Mill"
        BuildingType.BAKERY: return "Bakery"
```

**Was passiert beim Rezeptwechsel (automatisch durch das System):**
- `BuildingRegistry.set_active_recipe(building_id, index)` bricht den laufenden Zyklus sofort ab.
- Buffer-Items, die das neue Rezept nicht mehr braucht, werden als World-Drop gespawnt.
- `LogisticsSystem` löscht automatisch alle Carrier-Routen, die nun obsolete Ressourcen liefern.
- Das `BuildingDetailPanel` zeigt sofort den Rezept-Selector (OptionButton) — bei Gebäuden
  mit nur einem Rezept bleibt er unsichtbar.

**Keine `INPUT_RESOURCES`-Zeile anlegen** — Inputs sind im Rezept eingebettet.

### `crafting_registry.gd` — nur falls die Stufe ein **manuelles** Spieler-Rezept ist

Alle 6 Tabellen synchron ergänzen: `RECIPE_COST`, `RECIPE_ENERGY_COST`, `RECIPE_TICKS`,
`RECIPE_OUTPUT`, `RECIPE_DISPLAY_NAME`, **und** `RECIPE_ORDER` (sonst erscheint es nicht
in der CraftingGrid).

**Engine-Hinweis:** Godot 4.6, GDScript, statische Typisierung beibehalten. **Niemals
`Engine.get_singleton()` für GDScript-Autoloads** — Autoload-Namen direkt verwenden
(`BuildingRegistry`, `InventorySystem`, …). Vor Nutzung jeder Engine-API
`docs/engine-reference/godot/` prüfen (Knowledge-Cutoff liegt vor 4.6).

---

## Phase 6: Implementierung in der UI

Drei Pflicht-Touchpoints (sonst ist das Gebäude nicht oder falsch sichtbar):

1. **`src/ui/screens/inventory_screen.gd` → `_building_list()`**: neuen Eintrag in
   `building_entries` ergänzen:
   ```gdscript
   {&"building_type": BuildingRegistry.BuildingType.MILL, &"display_name": "Mill"},
   ```
   **Ohne diesen Eintrag erscheint das Gebäude nicht im Baumenü — häufigster Fehler.**
   Kosten/Energie/Affordability werden hier automatisch aus `BUILD_COST` abgeleitet.

2. **`src/ui/components/building_grid.gd` → `_building_icon()`**: Emoji ergänzen, sonst
   Fallback 🏛️:
   ```gdscript
   BuildingRegistry.BuildingType.MILL: return "⚙️"
   ```

3. **`src/ui/components/transportation_panel.gd`** (Emoji-`match`): Emoji ergänzen, damit
   das Gebäude in der Logistik-/Routen-UI ein eigenes Symbol hat.

**`building_detail_panel.gd` nicht anfassen** — der Rezept-Selector erscheint
automatisch bei Gebäuden mit mehr als einem Rezept; Inputs/Outputs/Rates werden
dynamisch aus dem aktiven Rezept gelesen.

---

## Phase 7: Progression-Tree-Verzahnung (Gating)

Der `ProgressionSystem`-Autoload (`data/progression_tree.json`) gated **Gebäude, manuelle
Rezepte, Gebäude-Rezepte und Gathering-Aktionen**. Eine neue Kette muss bewusst eingebettet
werden — sonst ist sie ungated sofort verfügbar (siehe ⚠️-Hinweis bei der Touch-Liste).

### 7a. Einbettung mit dem Nutzer klären — PFLICHT, vor jedem JSON-Schreiben

**Bevor** du auch nur einen Knoten entwirfst, stelle fest, *wie* die neuen Inhalte im
Tech-Tree hängen — das ist eine Designentscheidung, keine Ableitung. Lies zuerst den
Ist-Zustand (`data/progression_tree.json` — vorhandene `node_id`s, Branches, Strähnen),
und kläre dann **per `AskUserQuestion`**:

1. **Gaten oder offen lassen?** Soll die Kette hinter dem Tree liegen (Default: ja) oder
   bewusst ungated (sofort verfügbar) bleiben? Bei „offen" → Phase 7 überspringen, im
   Spec/Zusammenfassung als bewusste Entscheidung vermerken.
2. **An welchen vorhandenen Knoten/Branch?** Welcher existierende `node_id` ist die
   Voraussetzung der ersten neuen Stufe (z. B. `agriculture` für eine Nahrungskette,
   `forestry` für eine Holzkette)? Eigener neuer Branch nur, wenn die Kette ein eigenes
   Themenfeld eröffnet.
3. **Knoten-Granularität:** Bekommt **jede Stufe** einen eigenen Knoten (übliche
   lineare Strähne `stufe1 → stufe2 → stufe3`), oder werden Stufen zu einem Knoten
   gebündelt?
4. **Werkzeug-Rezepte:** Falls ein Gebäude `with_tool`/`bare_hands` hat — soll das
   `with_tool`-Rezept einen **separaten, tool-gegateten Knoten** bekommen (Prereq = der
   Tool-Knoten wie `axe`/`pickaxe`)? (Projekt-Standardmuster, fast immer ja.)
5. **Cross-Branch-Voraussetzungen:** Braucht eine Stufe ein Tool/Zwischenprodukt aus einem
   anderen Branch als Prereq (z. B. „Mühle braucht zusätzlich `axe`")?

Zeige dem Nutzer den vorgeschlagenen **Knoten-Plan** (Knoten, je `prerequisites`, je
`unlocks`) als kurze Tabelle und hole Freigabe, **bevor** du `data/progression_tree.json`
editierst. Erst dann 7b/7c.

### 7b. Pro freischaltbarem Element einen `unlocks`-Eintrag

Jeder Tree-Knoten ist ein Objekt in `nodes[]` mit einem `unlocks: []`-Array. Pro Inhaltstyp
ein Eintrag — die `id`-Strings werden beim Laden gegen die echten Enums/Registries
aufgelöst (`_build_reverse_lookups`):

| Inhalt | `unlocks`-Eintrag | `id`-Format (MUSS exakt matchen) |
|--------|-------------------|----------------------------------|
| Gebäude | `{ "type": "building", "id": "MILL" }` | `BuildingType`-Enum-Name (`building_registry.gd`) |
| Manuelles Rezept | `{ "type": "manual_recipe", "id": "axe" }` | recipe-`id` aus `crafting_registry` (`RECIPE_*`-Keys) |
| Gebäude-Rezept | `{ "type": "building_recipe", "id": "MILL:with_tool" }` | `BuildingType`-Name `:` recipe-`id` aus `RECIPES[type][i]["id"]` |
| Gathering-Aktion | `{ "type": "gather", "id": "HARVEST_WHEAT" }` | `PlayerCharacter.ManualActionType`-Enum-Name |

> **Tippfehler werden NICHT laut.** Eine unbekannte `id` → `push_warning` beim Laden, und
> der Inhalt bleibt **ungemappt = offen** (still nicht gated). Darum: Enum-Namen 1:1 aus dem
> Code kopieren, nicht erfinden; recipe-`id`s sind die echten Keys aus
> `RECIPES`/`crafting_registry` (z. B. `bare_hands`, `with_tool`, `gather_berry`) — keine
> Phantasienamen.

### 7c. Knoten-Schema und Platzierungs-Regeln

```json
{
  "node_id": "milling",                // eindeutig, snake_case
  "display_name": "Milling",
  "icon": "🌀",                         // Emoji (es gibt keine Icon-Assets für abstrakte Knoten)
  "branch": "food",                    // MUSS einen Eintrag in config.branch_angles_deg haben
  "ring": 5,                           // NUR Autoren-Hinweis — Layout-Ring wird auto-berechnet
  "prerequisites": ["agriculture"],    // existierende node_ids; treibt Reveal + Unlock-Reihenfolge
  "unlocks": [ { "type": "building", "id": "MILL" } ],
  "cost": null
}
```

- **`prerequisites` = der Lehrpfad** und müssen auf **existierende** `node_id`s zeigen,
  sonst schlägt das Laden fehl (fail-fast).
- **`ring` ist nur ein Hinweis** — der echte Layout-Ring ist die Länge der längsten
  same-branch-Prereq-Kette (`_compute_visual_rings`). Layout nicht über `ring` erzwingen.
- **Werkzeug-Rezept-Muster:** Gebäude-Knoten schaltet Gebäude + `bare_hands`-Rezept früh
  frei; ein separater, tool-gegateter Knoten (Prereq = Tool-Knoten) schaltet `with_tool`
  frei. Vorbild: `forestry` (→ LUMBER_CAMP + `LUMBER_CAMP:bare_hands`) + `tooled_logging`
  (Prereq `forestry`+`axe` → `LUMBER_CAMP:with_tool`).
- **Neuer Branch?** In `config.branch_angles_deg` einen Winkel ergänzen (vorhanden:
  core 0°, food 270°, materials 180°, crafting 90°, textiles 0°) und `config.branch_count`
  prüfen.

### 7d. Was NICHT angefasst werden muss

- **Kein Code-Change zum Gaten.** Die Gates (`BuildingRegistry.initiate_build`,
  `CraftingRegistry.try_craft`, `player_character.try_start_action`,
  `building_detail_panel`, `inventory_screen`) lesen die Capability-API live; die
  Reverse-Lookups werden beim Laden gebaut. JSON ergänzen reicht.
- **Kein Save/Load-Change.** `WorldSaveManager` serialisiert `ProgressionSystem` bereits
  (als `node_id`-Liste) — neue Knoten landen automatisch im Save.

### 7e. Tests anpassen (falls neuer Content gated wird)

Wird ein **Gathering** oder **Gebäude** neu gated, schlagen Integrationstests fehl, die es
ungated erwarten — der globale `ProgressionSystem`-Autoload startet hearth-only. Muster
(vgl. bestehende Suites in `tests/integration/building_system/*` und
`tests/integration/player_character/*`):

```gdscript
func before_test() -> void:
    ProgressionSystem.unlock_all()         # ganzen Baum öffnen — Test prüft Mechanik, nicht Gating

func after_test() -> void:
    ProgressionSystem.reset_to_initial()   # offenen Baum nicht in andere Suites lecken lassen
```

Betroffen sind nur Suites, die das neu gegatete Gebäude bauen oder die neue
Gathering-Aktion starten. Manuelle Rezepte (`try_craft`) werden derzeit von keinem Test
berührt.

Jede JSON-/Test-Änderung als Diff zeigen und freigeben lassen.

---

## Phase 8: Design-Docs aktualisieren

- **`design/gdd/recipe-database.md`**: neue Rezepte in die Implementation-Note / Beispiele
  aufnehmen (es ist die Single Source of Truth für Rezepte). Bei Gebäuden mit Fallback
  alle Rezepte dokumentieren (Hauptrezept + Alternativen je mit Balancing-Begründung).
- **`design/gdd/building-system.md`**: neue Gebäudetypen + ihre `RECIPES`-Einträge
  dokumentieren. Fallback-Rezepte explizit als Design-Absicht vermerken.
- Aktualisiere ggf. `design/gdd/systems-index.md` und `data/resources.json`-bezogene Docs.
- **Progression:** Wurden in Phase 7 Tree-Knoten ergänzt (oder die Kette bewusst ungated
  gelassen), vermerke das in der Progression-Spec (`design/quick-specs/progression-tree-*.md`
  bzw. der späteren GDD) — neue `node_id`s, ihre Prereqs und welche Inhalte sie freischalten.
- **Neues, eigenständiges Mechanik-Verhalten?** Dann via `/architecture-decision` einen ADR
  in `docs/architecture/` erwägen. Reine Daten-/Tabellen-Erweiterung einer bestehenden
  Mechanik braucht keinen neuen ADR.

Jede Doc-Änderung als Diff zeigen und freigeben lassen.

---

## Phase 9: Verifikation in Godot

Es gibt **kein garantiert lokales Godot-Binary** — Verifikation ist ein expliziter Schritt,
nicht „läuft schon".

1. **Statische Prüfung:** Alle berührten Tabellen gegen die Touch-Liste durchgehen — pro
   neuem Gebäude müssen #2–#6, #9, #10, #12, #13, #14 einen Eintrag haben (plus #7/#8 je
   nach Typ). Pro neuer Ressource ohne `world_icon_path` muss #17+#18 erfüllt sein (UI-Icon
   für Carrier-Animation). Ist die Kette gated, muss #21 (Tree-Knoten) vorhanden sein und
   jede `unlocks`-`id` exakt einem Enum-/recipe-Namen entsprechen. Fehlt einer, nachtragen.
2. **Rezept-Selector prüfen (bei Fallback-Gebäuden):** Im Godot-Editor Gebäude platzieren
   und das BuildingDetailPanel öffnen — der OptionButton muss sichtbar sein und alle
   Rezept-Labels korrekt anzeigen. Wechsel zwischen Rezepten testen:
   - Aktiver Zyklus bricht sofort ab.
   - Buffer-Items die das neue Rezept nicht braucht erscheinen als World-Drop.
   - Carrier-Routen für obsolete Inputs verschwinden aus dem TransportPanel.
3. **Im Editor (MCP `godot` Tools oder Nutzer):** Hauptrezept testen: Gebäude platzieren →
   NPC zuweisen → Inputs laden → einen Zyklus laufen lassen → Output im Detail-Panel prüfen.
   Dann auf Fallback wechseln und dasselbe verifizieren.
4. **Screenshot** des Baumenüs + Detail-Panels gegen die Erwartung (richtiges Emoji,
   richtiger Rezept-Selector, korrekte Inputs/Outputs, Tick-Fortschritt). Visuelle
   Korrektheit wird per Screenshot belegt, nicht headless.
5. **Gating prüfen (falls gated):** 🌳-Button öffnen → der/die neue(n) Knoten erscheinen
   an der erwarteten Stelle der Strähne mit korrekten Prereq-Kanten. Vor dem Unlock darf
   das neue Gebäude **nicht** im Baumenü und die neue Gathering-Aktion nicht im
   Tile-Panel erscheinen; nach dem Unlock schon. Save/Load-Round-Trip: Knoten freischalten
   → speichern → laden → Unlock-Status bleibt erhalten.
6. Falls eine Test-Suite gewünscht wird (in diesem Skill bewusst nicht erzwungen): die
   Integrationstests in `tests/integration/building_system/production_cycles_test.gd`
   spiegeln das Muster — dort ansetzen (inkl. `unlock_all()`/`reset_to_initial()` aus 7e).

---

## Abschluss-Zusammenfassung

Am Ende ausgeben:

```
## Produktionskette implementiert: <Name>

Neue Ressourcen:      <ids> (data/resources.json)
Neue Gebäude:         <namen> (building_registry.gd)
Rezepte je Gebäude:   <Gebäude>: <Hauptrezept-id> [+ <Fallback-id> falls vorhanden]
Manuelle Rezepte:     <ids oder "keine"> (crafting_registry.gd)
Balancing:            <base_cycle_ticks je Rezept>, ~<n> Zyklen/Tag
AI-Prompts:           assets/art/ai-prompts/<slug>-prompts.md (<n> Assets dokumentiert)
Assets generiert:     <n> PNGs via PixelLab API (pixen, 64×64) — bld_tile_*.png + ui/icons/resources/*.png  ← PFLICHT, nicht weglassen
UI:                   Baumenü + Icon + Logistik-Emoji ✓
Progression-Tree:     <node_ids + Prereqs> in data/progression_tree.json [oder "ungated (bewusst offen)"]
Design-Docs:          recipe-database.md, building-system.md [, progression-tree-spec] ✓

Touch-Liste-Check: <jede berührte Zeile #x ✓ — inkl. #21/#22 falls gated>
Offen:             Godot-Verifikation (Screenshot + Gating/Save-Load) · ggf. erneute Generierung bei Stil-Abweichung
```

## Kollaborationsprotokoll

- **Vor jedem Schreibvorgang fragen** — Entwurf/Diff zeigen, dann „Darf ich nach [Pfad]
  schreiben?". Das gesamte Mehrdateien-Changeset braucht Freigabe.
- **Nichts hardcoden** — alle Gameplay-Werte in Daten/Tabellen, nie inline (Gameplay-Code-Rule).
- **Reihenfolge respektieren** — erst Kette+Ressourcen klären (Phase 1–2), dann Assets/Balancing,
  dann Code, dann UI, dann Progression-Gating, dann Docs, dann Verifikation. Code vor geklärter
  Kette = Drift; Progression-Knoten erst, wenn die Enum-/recipe-Namen im Code feststehen
  (die `unlocks`-`id`s müssen exakt matchen).
- **Sync-Tabellen sind ein Vertrag** — wird eine Tabelle ergänzt, müssen alle korrespondierenden
  ergänzt werden. Die Touch-Liste am Ende Zeile für Zeile abhaken.
- **Kein `INPUT_RESOURCES`-Eintrag** — Inputs gehören ins Rezept-Dict, nicht in eine separate Tabelle.
- **Engine-Risiko** — Godot 4.6 liegt hinter dem LLM-Cutoff; APIs vor Nutzung in
  `docs/engine-reference/godot/` verifizieren. Keine `Engine.get_singleton()` für Autoloads.

---

## Empfohlene nächste Schritte

- In Godot platzieren und per Screenshot verifizieren (Phase 8) — `.import`-Sidecars entstehen automatisch beim Editor-Start
- Bei visueller Abweichung: erneute Generierung in Phase 3c mit präzisierterer `description`
- Balancing nach erstem Playtest mit `/quick-design` oder `/balance-check` nachjustieren
