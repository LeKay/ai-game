# AI Asset Prompts — Barrel Chain (Cooperage)

Generated: 2026-06-24

## Global Style (inherited from sprite-prompts.md)

- **Perspective:** slightly elevated ~60–70° above the horizon ("classic top-down RPG") — top face plus narrow front strip visible.
- **Light:** upper-left source, shadows fall to the lower-right.
- **Palette:** earthy, muted — no saturated neons. 2–3 shading tones per colour (highlight, midtone, shadow).
- **Outline:** none around the full object — only internal depth lines.
- **Background:** fully transparent — no ground, no frame, no fill.
- **Composition:** object centred, all four sides equal margin, nothing clipped, ≥2–4 px gap to every edge.
- **Building footprint:** ~18–20 px wide, ~14–16 px tall. Saddle roof (highlight left, shadow right), narrow front-wall strip with door (~3×4 px), one characteristic trade prop.

---

## 1. Cooperage / Fassbinderei — `bld_tile_cooperage.png`

A small workshop where a cooper shapes barrel staves into barrels. Characteristic prop: two or three wooden barrels stacked to the side of the entrance.

**Prompt:**
```
Pixel art building tile for a top-down RPG game. A cooperage workshop seen from a slightly elevated angle (~60-70 degrees above horizon), showing the top face and a narrow front strip. The building has a dark-brown saddle roof with highlight on the left slope and shadow on the right. A narrow front wall below the roof has a small wooden door (~3x4 px). To the right of the entrance, two or three small wooden barrels are stacked — each barrel is roughly 4 px wide, rendered with curved stave highlights and iron-hoop bands. One barrel lies on its side at ground level. The walls are warm tan-brown planks with subtle vertical plank lines. Light source upper-left, earthy muted palette, 2-3 shading tones per colour, no outline around the full object, only internal depth lines. Everything outside the building silhouette is fully transparent. Color palette: roof highlight #8B5A2B, roof midtone #6B3F1E, roof shadow #4A2B10, wall plank #C8A06A, door #5C3A1E, barrel stave #A07840, barrel hoop #4A4A4A.
```

**Target colours:** Roof highlight `#8B5A2B` · Roof mid `#6B3F1E` · Roof shadow `#4A2B10` · Wall `#C8A06A` · Door `#5C3A1E` · Barrel stave `#A07840` · Barrel hoop `#4A4A4A`
**Background:** Transparent

---

## 2. Barrel (UI Icon) — `assets/ui/icons/resources/barrel.png`

A single wooden barrel, centred on transparent background. Used in carrier animation and resource HUD.

**Prompt:**
```
Pixel art resource icon for a top-down RPG game. A single wooden barrel seen from a slightly elevated angle (~60-70 degrees), showing the top face and a narrow front strip. The barrel is rendered with curved vertical stave planks highlighted on the upper-left and shadowed on the lower-right. Two iron hoop bands wrap around the barrel — one near the top and one near the bottom — rendered as thin dark-grey arcs. The barrel top is a slightly lighter wood circle with subtle grain lines. The barrel is exactly centred in the 64x64 tile with equal margins on all sides, fully visible, no part clipped, at least 4 px gap to every edge. Light source upper-left, earthy muted palette, no outline around the full object, only internal depth lines. Everything outside the barrel silhouette is fully transparent. Color palette: stave highlight #C8A06A, stave midtone #A07840, stave shadow #6B4E28, hoop #4A4A4A, hoop highlight #6E6E6E, barrel top #B89050.
```

**Target colours:** Stave highlight `#C8A06A` · Stave mid `#A07840` · Stave shadow `#6B4E28` · Hoop `#4A4A4A` · Hoop highlight `#6E6E6E` · Top `#B89050`
**Background:** Transparent

---

## Atlas / Next Steps

1. Generate PNGs via PixelLab `create-image-pixen` (64×64, `high top-down`, `lineless`, `no_background: true`).
2. Place building tile → `assets/art/buildings/bld_tile_cooperage.png`
3. Place UI icon → `assets/ui/icons/resources/barrel.png`
4. `.import` sidecars are created automatically on the next Godot editor scan.
5. Verify visually against art bible (palette, perspective, barrel prop visible).
