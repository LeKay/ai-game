# Furniture Chain — AI Asset Prompts

> Style reference: see `sprite-prompts.md` for project-wide art bible.

## Global Style Rules (all assets in this file)

**Perspective:**
- Buildings/objects: slightly elevated angle ~60–70° above horizon ("classic top-down RPG") — top face + narrow front strip visible.

**Consistency:**
- Light source top-left, shadows fall bottom-right.
- Earthy, muted palette — no saturated neon colors.
- 2–3 shading levels per color (highlight, midtone, shadow).
- No outline around the whole object — only internal depth lines.

**Composition (transparent background):**
- Object exactly centered, equal distance to all four edges.
- Fully visible, no part cut off, ≥ 2–4 px margin to every edge.
- Background fully transparent — no ground, no frame, no fill detail.
- Building footprint ~18–20 px wide, ~14–16 px high; saddle roof (highlight left, shadow right), narrow front-wall strip with door (~3×4 px); one characteristic operational prop beside/in front for recognizability.

---

### 1. Carpenter's Workshop / Tischlerei — `bld_tile_carpenter.png`

A small workshop with a wooden workbench visible in the front, wood shavings on the floor, and a stack of finished planks leaning against the side wall.

**Prompt:**
```
A tiny carpenter's workshop rendered as a 64×64 pixel-art tile from a slightly elevated top-down RPG perspective (~60–70° above horizon). Saddle roof with light source from top-left: roof highlight left, midtone center, shadow right. Narrow front-wall strip with a small door (~3×4 px). Beside the building: a wooden workbench with tools on top and a neat stack of light-colored planks leaning against the right wall — the characteristic prop that makes this building instantly recognizable as a carpentry workshop. Wood-shaving curls scattered at the base. Earthy muted palette; 2–3 shading levels per color; no outlines around the whole object, only internal depth lines. Everything outside the building silhouette is fully transparent.
```

**Target colors:** Roof highlight `#C8A060` · Roof midtone `#A07840` · Roof shadow `#6B4E28` · Walls `#D4B880` · Door `#7A4A20` · Planks `#E8C880` · Workbench `#9B6A3A`
**Background:** Transparent

---

### 2. Furniture (UI icon) — `assets/ui/icons/resources/furniture.png`

A simple wooden chair seen from a slightly elevated angle — the carrier animation icon for furniture in transit.

**Prompt:**
```
A small wooden chair rendered as a 64×64 pixel-art icon from a slightly elevated top-down RPG perspective (~60–70° above horizon). The chair has four legs, a flat seat, and a straight back rest. Light source from top-left. Earthy brown palette; 2–3 shading levels; no outline around the whole object, only internal depth lines. Object exactly centered in the 64×64 canvas with equal margins to all edges. Background fully transparent.
```

**Target colors:** Wood highlight `#D4A060` · Wood midtone `#A07040` · Wood shadow `#6B4820` · Seat `#B88040`
**Background:** Transparent

---

## Atlas Assembly Note

Both assets are standalone PNGs (no atlas needed for this chain).

## Next Steps

1. Generate via PixelLab API (`generate_furniture_assets.py`) — `POST /v2/create-image-pixen`, 64×64, `view: "high top-down"`, `outline: "lineless"`, `no_background: true`.
2. Save outputs:
   - `assets/art/tiles/bld_tile_carpenter.png`
   - `assets/ui/icons/resources/furniture.png`
3. Restart Godot editor or trigger "Reimport" in FileSystem dock — `.import` sidecars are created automatically.
4. Verify against art bible: perspective, palette, light direction, centered composition.
5. If visual deviation is strong: re-generate with more precise color/composition description.
