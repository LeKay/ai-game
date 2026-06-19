# AI Asset Generation Prompts — Specific Tools (Axe, Pickaxe, Spindle)

UI-Icons für die drei spezifischen Werkzeug-Ressourcen. Werden als Carrier-Icons
auf der Karte und in der Inventar-UI verwendet.

**Globale Orientierungen (aus sprite-prompts.md):**
- Perspektive: leicht erhöhter Winkel ~60–70° über dem Horizont (Oberseite + schmaler Frontstreifen)
- Lichtquelle oben-links, Schatten nach unten-rechts
- Palette erdig und gedämpft — keine Neonfarben
- 2–3 Schattierungsstufen pro Farbe
- Keine Gesamt-Outline — nur interne Tiefenlinien

**Komposition Resource-Overlay (gilt für alle drei Icons):**
- Objekt exakt zentriert, gleicher Abstand zu allen vier Kanten
- Vollständig sichtbar, ≥ 4 px Abstand zu jeder Kante
- Hintergrund vollständig transparent — kein Boden, kein Rahmen

---

### 1. Axt / Axe — `axe.png`

Eine Holzfäller-Axt mit kurzem Stiel und breitem Stahlblatt. Erkennbar als Werkzeug
zum Holzfällen.

**Prompt:**
```
A small wood-cutting axe seen from a slightly elevated top-down angle (~60-70 degrees
above horizon), classic top-down RPG perspective. The axe lies flat with the blade
facing upper-right and the handle extending lower-left. The axe head is a wide
steel blade with a sharp edge on the right side; the handle is a short wooden shaft
about two-thirds the width of the blade.

The steel blade uses three shades: a bright highlight on the upper-left edge (#C8C8D4),
a cool grey midtone (#8890A0), and a darker shadow on the lower-right (#505860).
The wooden handle uses warm brown tones: highlight (#C8A060), midtone (#906830),
shadow (#5C4018). A thin internal edge line separates blade from handle.

The axe is centered in the tile with at least 4 pixels of transparent margin on every
side. Everything outside the axe silhouette is fully transparent. No background, no
ground, no shadow cast on the floor.
```

**Zielfarben:** Blade highlight `#C8C8D4` · Blade mid `#8890A0` · Blade shadow `#505860` · Handle highlight `#C8A060` · Handle mid `#906830` · Handle shadow `#5C4018`
**Hintergrund:** Transparent

---

### 2. Spitzhacke / Pickaxe — `pickaxe.png`

Eine klassische Bergbau-Spitzhacke: schmaler Eisenkopf quer zum Stiel (T-Form /
Kreuzform), BEIDE Seiten enden in spitzen Zacken — kein breites Axenblatt.

**Prompt:**
```
A mining pickaxe icon in classic top-down RPG pixel art style, seen from a slightly
elevated angle (~60-70 degrees above horizon). The tool forms a clear cross shape:
a long wooden handle runs diagonally from lower-left to upper-right, and a narrow
elongated iron head crosses it perpendicularly. The iron head is a thin curved bar
with TWO sharp spike tips — one curved spike pointing upper-left and one pointing
lower-right. The head is narrow and symmetrical, NOT a wide flat axe blade. No flat
cutting edge, only pointed spike ends.

The iron head uses three shades: highlight (#B0A898), grey-brown midtone (#706860),
dark shadow (#3C3028). The wooden handle uses warm browns: highlight (#C8A060),
midtone (#906830), shadow (#5C4018). Internal edge lines at the head-handle junction.

Centered with at least 4 px transparent margin on every side. Fully transparent
background — no ground, no floor shadow, no background color.
```

**Zielfarben:** Head highlight `#B0A898` · Head mid `#706860` · Head shadow `#3C3028` · Handle highlight `#C8A060` · Handle mid `#906830` · Handle shadow `#5C4018`
**Hintergrund:** Transparent

---

### 3. Spindel / Spindle — `spindle.png`

Eine hölzerne Spindel mit aufgewickeltem Faden. Erkennbar als Textilwerkzeug.

**Prompt:**
```
A wooden drop spindle seen from a slightly elevated top-down angle (~60-70 degrees
above horizon), classic top-down RPG perspective. The spindle stands nearly upright,
slightly tilted. It consists of a slender wooden shaft with a round wooden whorl
(disc) near the bottom and a small hook at the top. A thin thread is wound in neat
coils around the upper shaft, tapering to a point where it meets the hook.

The wooden shaft and whorl use warm tones: highlight (#D4A870), midtone (#A07840),
shadow (#6B4E28). The wound thread uses soft off-white to cream tones:
highlight (#F0E8D0), midtone (#D8C8A0), shadow (#B09C70). The whorl disc has a
subtle circular highlight on its upper face.

The spindle is centered in the tile with at least 4 pixels of transparent margin on
every side. Everything outside the spindle silhouette is fully transparent. No
background, no ground, no shadow cast on the floor.
```

**Zielfarben:** Wood highlight `#D4A870` · Wood mid `#A07840` · Wood shadow `#6B4E28` · Thread highlight `#F0E8D0` · Thread mid `#D8C8A0` · Thread shadow `#B09C70`
**Hintergrund:** Transparent

---

## Atlas-Assembly & Nächste Schritte

1. PNGs via PixelLab (pixen, 64×64) generieren
2. In `assets/ui/icons/resources/` ablegen: `axe.png`, `pickaxe.png`, `spindle.png`
3. Godot Editor starten → FileSystem-Dock → Reimport (`.import`-Sidecars entstehen automatisch)
4. Import-Settings prüfen: Filter = Nearest, Mipmaps = Disabled
5. Visuell gegen Art Bible prüfen (Palette, Perspektive, Licht)
6. Bei Stil-Abweichung: erneut generieren mit präzisierterer `description`
