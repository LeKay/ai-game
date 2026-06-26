# AI Asset Prompts — Bread Production Chain

Chain: wheat → flour → bread  
Buildings: Farm, Mill, Bakery  
New resource icon: flour

---

## Global Style Reference

**Perspective (buildings + resource overlays):** Elevated view ~60–70° above the horizon
("classic top-down RPG perspective") — top surface plus a narrow front-wall strip visible.

**Perspective (UI icons):** Same elevated angle, full object visible, transparent background.

**Consistency rules for all:**
- Light source upper-left, shadows fall lower-right.
- Palette: earthy and muted — no saturated neon colors.
- 2–3 shading levels per color (Highlight, Midtone, Shadow).
- No outer outline — only internal depth lines.

**Building composition (transparent background):**
- Object centered, equal margin to all four edges, ≥ 2–4 px from each edge.
- Fully visible — nothing clipped.
- Background fully transparent — no ground, no frame, no fill.
- Footprint ~18–20 px wide, ~14–16 px high.
- Saddle roof: highlight left, shadow right; narrow front-wall strip with door (~3×4 px).
- One characteristic operating prop to distinguish from other buildings.

---

## Building Tiles

### 1. Bauernhof / Farm — `bld_tile_farm.png`

Compact farm building with an open-sided grain store attached; several wheat sheaves bundled
and leaning against the side wall as the characteristic prop.

**Prompt:**
```
A tiny pixel-art farm building seen from a classic top-down RPG angle (camera roughly
60–70° above the horizon). The main structure has a saddle roof about 20 pixels wide and
16 pixels tall overall. Roof left half uses a warm straw-yellow highlight, right half a
golden-amber midtone, with a dark-brown ridge line and a narrow shadow on the rightmost
edge. Walls below are pale warm wood planks in a muted sandy-tan tone; the front-facing
strip is 3–4 pixels tall with a small dark rectangle for a doorway. Attached to the right
side is a smaller lean-to canopy in the same straw-yellow, open underneath. Three wheat
sheaves — bundles of golden stalks tied with a dark band — lean against the building's
right side: each sheaf is about 5 px tall, slightly angled inward. Light falls from the
upper-left; shadows on roof right half and building right wall. Everything outside the
building and props is fully transparent. No background, no ground plane.
Color palette: roof highlight #D9B85C, roof midtone #B8912F, roof shadow #7A5E1A,
wall #C4A87A, door #5A3E28, sheaf stalk #E2C76A, sheaf band #6B4A1E.
```

**Target colors:** Roof highlight `#D9B85C` · Roof midtone `#B8912F` · Roof shadow `#7A5E1A` · Wall `#C4A87A` · Door `#5A3E28` · Sheaf `#E2C76A`
**Background:** Transparent

---

### 2. Mühle / Mill — `bld_tile_mill.png`

Stone-walled grinding mill with a large wooden mill-wheel (horizontal) visible on one side
as the characteristic prop; suggests a simple water- or animal-driven mill.

**Prompt:**
```
A tiny pixel-art mill building seen from a classic top-down RPG angle (camera roughly
60–70° above the horizon). The main structure has a saddle roof about 20 pixels wide and
16 pixels tall overall. Roof left half uses a cool-gray slate highlight, right half a
medium blue-gray midtone, with a dark ridge line and a narrow shadow on the rightmost
edge. Walls below are rough stone blocks in a muted warm-gray tone; mortar lines are
single dark-pixel gaps between blocks. The front-facing strip is 3–4 pixels tall with a
small dark rectangle for a doorway. Attached to the right side and slightly in front of
the building is a large wooden mill wheel lying almost flat (viewed from slightly above):
a circle of about 8 px diameter, dark weathered-wood spokes radiating from a center hub,
a pale wooden rim ring around the outside. Light falls from the upper-left; shadows on
roof right and stone wall right. Everything outside the building and wheel is fully
transparent. No background, no ground plane.
Color palette: roof highlight #A8A8A0, roof midtone #787872, roof shadow #484842,
wall #9B8E7A, mortar #6A5F52, door #3E3028, wheel wood #8B6830, wheel rim #C4A060.
```

**Target colors:** Roof highlight `#A8A8A0` · Roof midtone `#787872` · Wall `#9B8E7A` · Door `#3E3028` · Mill wheel `#8B6830`
**Background:** Transparent

---

### 3. Bäckerei / Bakery — `bld_tile_bakery.png`

Warm-toned bakery building with a short round chimney emitting a tiny curl of smoke, and
a wooden bread paddle leaning against the front wall as the characteristic prop.

**Prompt:**
```
A tiny pixel-art bakery building seen from a classic top-down RPG angle (camera roughly
60–70° above the horizon). The main structure has a saddle roof about 20 pixels wide and
16 pixels tall overall. Roof left half uses a warm terracotta-red highlight, right half a
deep rust midtone, with a dark clay-brown ridge and a narrow shadow on the rightmost edge.
Walls below are pale sandstone-yellow bricks; the front-facing strip is 3–4 pixels tall
with a small dark rectangle for a doorway. A short cylindrical chimney (3 px wide, 4 px
tall) sits on the roof slightly left of center, capped with a darker ring; one tiny
2-pixel wide S-curve of lighter gray represents rising smoke above it. Leaning against
the front-right corner is a long-handled bread paddle: a thin dark-wood handle (~8 px)
with a small flat rectangular paddle head (~5×3 px) at the top. Light falls from the
upper-left; shadows on roof right half and building right wall. Everything outside the
building, chimney, and paddle is fully transparent. No background, no ground plane.
Color palette: roof highlight #C05840, roof midtone #8C3820, roof shadow #5A2010,
wall #D4B882, door #5A3E28, chimney #7A5040, smoke #C8C0B0, paddle handle #6B4A28,
paddle head #9B7248.
```

**Target colors:** Roof highlight `#C05840` · Roof midtone `#8C3820` · Wall `#D4B882` · Door `#5A3E28` · Chimney `#7A5040` · Paddle `#6B4A28`
**Background:** Transparent

---

## Resource UI Icon

### 4. Mehl / Flour — `assets/ui/icons/resources/flour.png`

Small linen sack of flour, slightly open at the top revealing white powder inside.

**Prompt:**
```
A tiny pixel-art icon of a small flour sack seen from a classic top-down RPG angle
(camera roughly 60–70° above the horizon). The sack is about 20 px wide and 22 px tall,
centered in a 64×64 canvas with equal transparent margins on all sides. The sack body is
a rounded rectangle in muted linen-cream, slightly wider at the bottom; the cloth texture
has two or three subtle horizontal crease lines in a slightly darker tone. The sack is
gathered and tied near the top with a thin dark cord, then the open neck flares slightly
outward revealing a small oval of pure white flour powder inside. Light falls from the
upper-left; the sack left face is the lightest tone, right face is a midtone, and the
lower-right underside shows a shadow tone. Everything outside the sack is fully
transparent. No background, no ground.
Color palette: sack highlight #F0E8D0, sack midtone #D4C4A0, sack shadow #A89878,
cord #5A4030, flour inside #F8F8F4.
```

**Target colors:** Sack highlight `#F0E8D0` · Sack midtone `#D4C4A0` · Sack shadow `#A89878` · Cord `#5A4030` · Flour `#F8F8F4`
**Background:** Transparent

---

## Atlas Assembly

After generation:
- Building tiles → `assets/art/tiles/bld_tile_farm.png`, `bld_tile_mill.png`, `bld_tile_bakery.png`
- Flour icon → `assets/ui/icons/resources/flour.png`

Import settings in Godot: Filter = Nearest, Mipmaps = Disabled.
`.import` sidecars are generated automatically on next editor scan — do not create manually.

## Next Steps

1. Generate via PixelLab `POST /v2/create-image-pixen` (64×64, `view: "high top-down"`, `outline: "lineless"`, `detail: "highly detailed"`, `no_background: true`).
2. Check balance and request user approval before generation (credits are non-refundable).
3. Verify each result against the style rules above — re-generate if perspective or palette deviates significantly.
4. Place files at the paths above, then restart Godot editor to trigger import.
5. Verify Farm appears in build menu with 🌾 icon, Mill with ⚙️, Bakery with 🥖.
