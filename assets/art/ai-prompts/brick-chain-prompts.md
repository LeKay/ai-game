# Brick Chain — AI Prompt Reference

**Chain:** Clay + Fiber → Brick Kiln → Brick

---

## Global Style Orientations (Art Bible)

**Perspective:**
- Terrain tiles: strict top-down (camera perpendicular), only top face visible.
- Buildings / resource overlays: slightly elevated ~60–70° ("classic top-down RPG perspective") — top face plus narrow front strip visible.

**Consistency rules (all assets):**
- Light source upper-left, shadows fall lower-right.
- Palette earthy and muted — no saturated neon colors.
- 2–3 shading levels per color (highlight, midtone, shadow).
- No outline around the whole object — only internal depth lines.

**Composition (transparent background):**
- Object exactly centered, equal margin to all four edges.
- Fully visible, nothing cut off, ≥ 2–4 px clearance to every edge.
- Background fully transparent — no ground, no frame, no fill detail.
- Building footprint ~18–20 px wide, ~14–16 px tall; characteristic operational prop for distinctiveness.

---

## Assets

### 1. Brick Kiln / Brick Kiln — `bld_tile_brick_kiln.png`

A squat kiln building for firing clay bricks; recognized by its stone chimney with orange glow and a stack of unfired clay bricks leaning against the side.

**Prompt:**
```
A small brick kiln building seen from a slightly elevated angle (classic top-down RPG
perspective, roughly 60-70 degrees above horizon). The kiln has a squat stone chimney
with orange glow at the top, dark reddish-brown fired brick walls, a low arched
furnace opening on the front face, and a short stack of unfired clay bricks leaning
against the left side as the characteristic operational prop. Light source upper-left,
shadows fall lower-right. Earthy muted palette. Roof/top surface shows warm brick
texture. Object is fully centered with at least 3 px clearance on all sides.
Background is fully transparent — no ground, no border, no fill.
Color palette: chimney highlight #D4704A, chimney midtone #A84E30, chimney shadow #6E2E14,
wall brick #B85C3A, wall mortar #8C6B56, furnace opening #2A1A0E, clay stack #C49A72.
```

**Target colors:** Chimney highlight `#D4704A` · Chimney midtone `#A84E30` · Chimney shadow `#6E2E14` · Wall brick `#B85C3A` · Wall mortar `#8C6B56` · Furnace `#2A1A0E` · Clay stack `#C49A72`
**Background:** Transparent

---

### 2. Brick (UI Icon) / Brick — `assets/ui/icons/resources/brick.png`

A single fired clay brick; used as the carrier transport icon and in the resource HUD.

**Prompt:**
```
A single fired clay brick seen from a slightly elevated angle (classic top-down RPG
perspective). The brick is rectangular with visible rough texture, showing the top face
and a narrow front edge. Warm reddish-brown color with subtle mortar-line grooves.
Light source upper-left, shadow lower-right. Earthy muted palette, 2-3 shading tones.
Object fully centered with at least 3 px clearance on all sides.
Background fully transparent.
Color palette: top face highlight #D4704A, top face midtone #A84E30, shadow edge #6E2E14,
mortar groove #7A5C48.
```

**Target colors:** Top highlight `#D4704A` · Top midtone `#A84E30` · Shadow `#6E2E14` · Mortar `#7A5C48`
**Background:** Transparent

---

## Atlas Assembly Note

Both assets are standalone 64×64 PNGs — no atlas needed for this chain.

## Next Steps

1. Generated PNGs → `assets/art/tiles/bld_tile_brick_kiln.png` and `assets/ui/icons/resources/brick.png`
2. In Godot editor: FileSystem dock → right-click → Reimport to generate `.import` sidecars
3. Import settings: Filter = Nearest, Mipmaps = Disabled
4. Check against Art Bible: perspective, palette, light direction
5. If style deviates: re-run `generate_brick_assets.py` with a refined description
