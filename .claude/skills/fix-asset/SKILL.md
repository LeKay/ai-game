---
name: fix-asset
model: claude-sonnet-4-6
description: "Regeneriert ein bestehendes KI-generiertes Asset (PixelLab), das visuell falsch
  aussieht. Diagnostiziert die Ursache im Prompt, schreibt einen verbesserten Prompt, läuft den
  PixelLab-API-Call direkt, und iteriert bis das Ergebnis stimmt. Aufruf:
  /fix-asset <asset-id> '<Fehlerbeschreibung>' — z. B. /fix-asset pickaxe 'sieht aus wie eine Axt'"
argument-hint: "<asset-id> '<was ist falsch>'"
user-invocable: true
allowed-tools: Read, Glob, Grep, Write, Edit, Bash, AskUserQuestion
---

# Fix Asset

Dieser Skill repariert ein visuell falsches KI-Asset. Er diagnostiziert, welcher
Teil des Prompts das Problem verursacht hat, verbessert ihn gezielt, generiert neu
und iteriert bis das Ergebnis stimmt.

> **Kollaborationsprotokoll:** Prompt-Änderungen und Schreibvorgänge vor dem
> Ausführen zeigen. Generierungen verbrauchen Credits — vor jedem API-Call
> bestätigen lassen.

---

## Phase 0: Problem verstehen

Lies das Argument. Fehlt die Fehlerbeschreibung, frage:
> "Was stimmt am Asset nicht? Beschreibe konkret, was du siehst vs. was du
> erwartest."

Typische Fehlerklassen (direkt aus der Fehlerbeschreibung ableiten):

| Fehlerbeschreibung | Ursache im Prompt | Gegenmaßnahme |
|--------------------|-------------------|---------------|
| „sieht wie [anderes Objekt] aus" | Beschreibung zu generisch, KI greift auf Trainings-Stereotype zurück | Explizit sagen was es NICHT ist; Referenzspiele nennen (Stardew Valley, Minecraft) |
| „Kopf/Blatt sitzt in der Mitte des Stiels" | Position nicht explizit: Kopf soll am ENDE des Stiels sitzen | „attached at the UPPER END of the handle, not in the middle" |
| „sieht aus wie ein Kreuz / Plus" | Beide Spitzen/Enden zeigen in entgegengesetzte Richtungen beschrieben | Beide Elemente müssen in dieselbe Richtung zeigen; Kreuz-Analogie explizit verbieten |
| „falsche Form am Stiel-Ende" | Unerwünschtes Element nicht verboten | „The bottom end of the handle is a plain rounded grip — no blade, no extra element" |
| „Stil passt nicht (zu realistisch/zu cartoonig)" | Perspektiv- oder Stil-Anker fehlen | `view: high top-down`, `outline: lineless`, Referenz-Spiele; Palette explizit mit Hex |
| „Proportionen falsch / zu groß / zu klein" | Keine Kompositions-Anweisung | „centered, occupies 70–80% of the 64×64 tile, 4px margin on all sides" |

---

## Phase 1: Bestehenden Prompt finden

Suche die Prompt-Datei für das Asset:

```
Glob pattern="assets/art/ai-prompts/**/*.md"
```

Lies die relevante Sektion. Identifiziere den Abschnitt, der das Problem verursacht —
markiere ihn explizit für den Nutzer:

> „Das Problem liegt in Zeile X: _'[zitierter Text]'_ — das hat die KI
> als [Fehlinterpretation] gelesen."

---

## Phase 2: Verbesserten Prompt entwerfen

Schreibe einen neuen Prompt. **Pflichtregeln:**

- Beginne mit Objekt + Stil + Perspektive: `"Pixel art icon of a [object], top-down RPG
  inventory style, 64x64, seen from ~60-70 degrees above horizon."`
- Beschreibe die **Silhouette** explizit — was sieht man, wie ist es ausgerichtet
- Für jede Fehlklasse aus Phase 0: füge eine explizite Verneinung ein
  (`NOT a wide flat blade`, `does NOT form a plus sign`, `no extra element at the bottom`)
- Verwende Analogien für schwierige Formen: „curved like a crescent", „banana-shaped"
- Referenziere bekannte Spiele zum Stil-Anker: „similar to classic RPG icons like in
  Stardew Valley or Minecraft"
- Schreibe Kopf-Handle-Verbindung explizit: „head attached at the UPPER END of the handle"
- Füge Farbpalette am Ende ein:
  `"Color palette: [label] #HEX, [label] #HEX, …"`

Zeige den vollständigen neuen Prompt und **frage:** „Darf ich diesen Prompt in
`assets/art/ai-prompts/[datei].md` schreiben und das Icon generieren?"

---

## Phase 3: Kontostand prüfen

```python
import urllib.request, json, os
from pathlib import Path

# API-Key NIEMALS hardcoden — aus Env oder ~/.pixellab_key lesen
key = os.environ.get('PIXELLAB_API_KEY') or (Path.home() / '.pixellab_key').read_text().strip()

req = urllib.request.Request(
    'https://api.pixellab.ai/v2/balance',
    headers={'Authorization': f'Bearer {key}'},
)
with urllib.request.urlopen(req) as resp:
    print(json.load(resp))
```

Zeige: verbleibende Generierungen. Fahre erst fort wenn bestätigt.

---

## Phase 4: Prompt-Datei aktualisieren

Ersetze die alte Prompt-Sektion in `assets/art/ai-prompts/[datei].md` mit dem
neuen Prompt (Edit-Tool). Kommentar am Anfang der Sektion:
`<!-- v[N] — [datum]: [grund der Änderung] -->`

---

## Phase 5: Generierung via PixelLab API

**Pflichtparameter — niemals abweichen:**
- `image_size`: `{"width": 64, "height": 64}` — immer 64×64
- `view`: `"high top-down"` — Art-Bible-Standard
- `outline`: `"lineless"` — keine Gesamt-Outline
- `detail`: `"highly detailed"`
- `no_background`: `true`

```python
import urllib.request, json, base64, os
from pathlib import Path

# API-Key NIEMALS hardcoden — aus Env oder ~/.pixellab_key lesen
key = os.environ.get('PIXELLAB_API_KEY') or (Path.home() / '.pixellab_key').read_text().strip()

payload = {
    'description': '<vollständiger verbesserter Prompt inkl. Farbpalette>',
    'image_size': {'width': 64, 'height': 64},
    'view': 'high top-down',
    'detail': 'highly detailed',
    'outline': 'lineless',
    'no_background': True,
}

data = json.dumps(payload).encode('utf-8')
req = urllib.request.Request(
    'https://api.pixellab.ai/v2/create-image-pixen',
    data=data,
    headers={
        'Authorization': f'Bearer {key}',
        'Content-Type': 'application/json',
    },
    method='POST',
)
with urllib.request.urlopen(req) as resp:
    d = json.load(resp)

png = base64.b64decode(d['image']['base64'])
out_path = 'assets/ui/icons/resources/<id>.png'   # Pfad anpassen
with open(out_path, 'wb') as f:
    f.write(png)
print(f'Saved {len(png)} bytes to {out_path}')
```

**Zielpfade nach Asset-Typ:**

| Asset-Typ | Zielpfad |
|-----------|----------|
| UI-Icon (Ressource, Carrier) | `assets/ui/icons/resources/<id>.png` |
| Gebäude-Tile | `assets/art/tiles/bld_tile_<name>.png` |
| World-Ressource-Overlay | `assets/art/tiles/env_tile_resource_<id>.png` |

> `.import`-Sidecar entsteht automatisch beim nächsten Godot-Editor-Start.
> Nicht manuell anlegen. „Reimport" im FileSystem-Dock triggern.

---

## Phase 6: Iteration

Frage den Nutzer: „Wie sieht das neue Icon aus? Stimmt es jetzt?"

**Falls nein** — gehe zurück zu Phase 2. Wende dabei folgende Eskalationsregel an:

| Iteration | Strategie |
|-----------|-----------|
| 1. Versuch | Fehlklasse aus Phase 0 adressieren, explizite Verneinung hinzufügen |
| 2. Versuch | Silhouette anders beschreiben (andere Analogie, andere Ausrichtung), Referenzspiele hinzufügen |
| 3. Versuch | Vollständig neuer Ansatz: andere Ausrichtung (z. B. statt diagonal → aufrecht), simplere Beschreibung |
| 4. Versuch | `image_guidance` Parameter: Frage ob Nutzer ein Referenz-PNG bereitstellen kann; nutze es als Basis |

Bei Iteration ≥ 3: zeige alle bisherigen Prompts und frage explizit, welche
Elemente aus dem letzten Ergebnis gut waren — behalte diese, ändere nur das
Problematische.

---

## Phase 7: Abschluss

Sobald das Ergebnis akzeptiert:

1. Bestätigen: aktualisierter Prompt liegt in `assets/art/ai-prompts/[datei].md` ✓
2. PNG liegt unter dem korrekten Zielpfad ✓
3. Godot-Hinweis: Editor neu starten → FileSystem-Dock → Reimport, dann
   Import-Settings prüfen: Filter = Nearest, Mipmaps = Disabled

```
## Ergebnis
Asset:        <id>.png
Iterationen:  N
Problem war:  [Diagnose aus Phase 0]
Fix war:      [was im Prompt geändert wurde]
Prompt-Datei: assets/art/ai-prompts/<datei>.md (aktualisiert)
```
