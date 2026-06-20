# Leather Chain — Asset Prompts

Chain: hide → Tannery → leather → Tailor → clothing
New assets: 1 building tile (Tannery) + 2 UI icons (knife, leather)

---

## Global style orientation (from sprite-prompts.md)

**Perspective:** Buildings/overlays at ~60–70° elevated angle (classic top-down RPG).
**Light:** Top-left source, shadows fall bottom-right.
**Palette:** Earthy and muted — no neon saturation. 2–3 shading levels per colour.
**Outline:** None around the whole object — only internal depth lines.
**Composition:** Object centred, ≥ 2–4 px from every edge, background fully transparent.
**Building footprint:** ~18–20 px wide, ~14–16 px tall; saddle roof + narrow front wall strip.

---

### 1. Tannery / Tannery — `bld_tile_tannery.png`

A small stone-and-timber workshop with a large wooden vat or barrel out front used for
soaking hides — the tannery's signature prop that makes it instantly recognisable.

**Prompt:**
```
Pixel art building tile, top-down RPG perspective at ~65° elevation angle. A small
stone-and-timber workshop for processing animal hides. Saddle roof in dark brown shingles
(highlight top-left, shadow bottom-right). Narrow stone walls with a short doorway on the
front strip. In front of the building: a large wooden barrel or vat (the tannery's
distinctive prop), slatted timber staves with a dark liquid inside, lit from the top-left.
Object centred on a 64×64 canvas. Everything outside the building and barrel is fully
transparent — no ground, no border, no fill.
```

**Target colours:** Roof highlight `#8B6245` · Roof midtone `#6B4A2F` · Roof shadow `#3E2A18` · Stone wall `#9A8C80` · Vat staves `#7A5C3A` · Vat liquid `#3D2B1A` · Door `#4A3020`
**Background:** Transparent

---

### 2. Knife / Knife — `knife.png` (UI icon, `assets/ui/icons/resources/`)

A small handled blade with a bone or wooden grip — the tannery tool.

**Prompt:**
```
Pixel art UI icon at ~65° elevated angle. A simple crafted knife: short single-edged blade
of grey-silver steel, wooden or bone handle wrapped with a leather strip. Blade edge glints
top-left, shadow falls to the bottom-right. Object centred on a 64×64 canvas with ≥ 3 px
clearance on all sides. Background fully transparent.
```

**Target colours:** Blade highlight `#D4D0C8` · Blade midtone `#A0A098` · Blade shadow `#686860` · Handle `#8C6840` · Handle wrap `#6B4530`
**Background:** Transparent

---

### 3. Leather / Leather — `leather.png` (UI icon, `assets/ui/icons/resources/`)

A folded or rolled piece of tanned leather — earthy brown, slightly glossy.

**Prompt:**
```
Pixel art UI icon at ~65° elevated angle. A folded piece of tanned leather: smooth earthy
brown surface with subtle sheen highlight top-left, darker shadow on the fold crease
bottom-right. Slightly textured to suggest cured animal hide. Object centred on a 64×64
canvas with ≥ 3 px clearance on all sides. Background fully transparent.
```

**Target colours:** Leather highlight `#B07A50` · Leather midtone `#8C5E38` · Leather shadow `#5C3A20` · Fold crease `#4A2E18`
**Background:** Transparent

---

## Atlas assembly note

Export each asset at 64×64 px (1× — no downscaling).
Place in:
- `assets/art/tiles/bld_tile_tannery.png`
- `assets/ui/icons/resources/knife.png`
- `assets/ui/icons/resources/leather.png`

After copying, open the Godot editor so `.import` sidecars are created automatically
(Filter = Nearest, Mipmaps = Disabled). Check against art bible in the editor viewport.

## Next steps
- [ ] Generate PNGs via PixelLab API (Phase 3c)
- [ ] Drop into correct folders, let editor create .import sidecars
- [ ] Verify Tannery tile in build menu (emoji 🪣 shows until PNG loads)
- [ ] Verify knife + leather icons in carrier animation and inventory
