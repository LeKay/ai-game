# AI Asset Generation Prompts — Seeds

Prompts for PixelLab. These assets support the seeds mechanic: seeds drop as
byproducts when harvesting terrain tiles and can be planted on EMPTY tiles to
grow new resource terrain.

**Shared style rules (from sprite-prompts.md):**
- Perspective: slightly elevated angle ~60–70° above horizon ("classic top-down RPG")
- Light source upper-left; shadows fall lower-right
- Palette: earthy and muted — no saturated neon colors
- 2–3 shading levels per color (highlight, midtone, shadow)
- No outline around the entire object — only internal depth lines
- Object centered; fully visible; ≥ 4 px gap to every edge; transparent background

---

## World Badge Icons (Resource Overlay — transparent background, 64×64)

These appear floating above tiles as loot pickup badges when seeds drop from harvesting.

---

### 1. Tree Seed — `env_tile_resource_tree_seed.png`

A small winged maple-style seed (samara) lying flat, seed pod at center, two papery
wings extending left and right. Earthy brown tones. Seen from a top-down perspective.

**Prompt:**
```
A single maple samara seed (winged tree seed) seen from directly above at a slight
top-down RPG angle. The seed pod is a small rounded oval at the center with a pale
tan papery wing extending to each side, slightly curved. Light source from upper-left;
the seed pod casts a faint shadow downward-right. Colors are muted earthy browns and
warm tans. Object is perfectly centered, fully visible, at least 4 pixels from every
edge. Everything outside the seed shape is fully transparent.
```

**Target colors:** seed pod `#6B4A2A` · pod highlight `#8C6640` · wing midtone `#C8A87A`
· wing highlight `#E0C89A` · wing shadow `#A07A50`
**Background:** Transparent

---

### 2. Grass Seed — `env_tile_resource_grass_seed.png`

A small slender grain / grass seed head, like a tiny wheat stalk top, light yellow-green.

**Prompt:**
```
A single small grass seed head seen from a slight top-down RPG angle — a slender oval
grain with a tiny pointed tip at the top and a short stubby stem below. Pale
yellow-green coloring, like a ripening grass seed just before it dries. Light source
from upper-left. Muted palette, no bright greens. The seed is centered, fully visible,
at least 4 pixels from every edge. Everything outside the seed is fully transparent.
```

**Target colors:** seed body midtone `#B5C462` · seed highlight `#D4DE88` · seed shadow `#8A9A38`
· stem `#7A8A30`
**Background:** Transparent

---

### 3. Berry Seed — `env_tile_resource_berry_seed.png`

A tiny round pip / berry seed, like a small stone from inside a berry, dark purplish red.

**Prompt:**
```
A single small berry seed pip seen from a slight top-down RPG angle — a smooth oval
stone about the size of a cherry pit, slightly flattened. Deep muted burgundy-purple
color with a small highlight glint on the upper-left. Light source from upper-left.
The pip casts a small shadow to the lower-right. Centered, fully visible, at least 4
pixels from every edge. Everything outside the seed is fully transparent.
```

**Target colors:** pip midtone `#6B2040` · pip highlight `#9C3860` · pip shadow `#3D0F24`
· glint `#C86090`
**Background:** Transparent

---

## UI Icons (Inventory / HUD — transparent background, 64×64)

These appear in the inventory screen and tooltips.

---

### 4. Tree Seed UI Icon — `assets/ui/icons/resources/tree_seed.png`

Same maple samara as the world badge but rendered as a clean UI icon with slightly
more contrast for readability at small sizes.

**Prompt:**
```
A clean UI icon of a maple samara seed (winged tree seed) seen from slightly above.
The seed pod is a small rounded oval at center with two papery wings curving outward.
Muted earthy browns and warm tans. Light from upper-left. Slightly higher contrast
than the world tile version for readability at 32×32 display size. Object is centered,
fully visible, at least 4 px from every edge on transparent background.
```

**Target colors:** pod `#6B4A2A` · pod highlight `#9C6E48` · wing `#C8A87A` · wing highlight `#E0C89A`
**Background:** Transparent

---

### 5. Grass Seed UI Icon — `assets/ui/icons/resources/grass_seed.png`

Same slender grain seed as the world badge, slightly higher contrast.

**Prompt:**
```
A clean UI icon of a small grass seed (slender grain / seed head) seen from slightly
above. A narrow oval grain with a pointed tip and short stem. Pale yellow-green palette,
muted and earthy. Light from upper-left. Slightly higher contrast for readability.
Centered, fully visible, at least 4 px from every edge on transparent background.
```

**Target colors:** body `#B5C462` · highlight `#D4DE88` · shadow `#8A9A38` · stem `#7A8A30`
**Background:** Transparent

---

### 6. Berry Seed UI Icon — `assets/ui/icons/resources/berry_seed.png`

Same round pip as the world badge, slightly higher contrast.

**Prompt:**
```
A clean UI icon of a berry seed pip (small smooth oval stone) seen from slightly above.
Deep muted burgundy-purple with a glint highlight on the upper-left surface.
Light from upper-left. Slightly higher contrast for readability at small sizes.
Centered, fully visible, at least 4 px from every edge on transparent background.
```

**Target colors:** pip `#6B2040` · highlight `#9C3860` · shadow `#3D0F24` · glint `#C86090`
**Background:** Transparent

---

## Atlas Assembly Notes

- All tiles: 64×64 px, PNG with transparency
- Import settings: Filter = Nearest, Mipmaps = Disabled
- World badge PNGs → `assets/art/tiles/env_tile_resource_*_seed.png`
- UI icon PNGs → `assets/ui/icons/resources/*_seed.png`
- After placing PNGs, reimport in Godot editor (FileSystem dock → Reimport)

## Next Steps

1. Check PixelLab balance
2. Generate assets 1–6 via `/v2/create-image-pixen` (64×64, view: high top-down,
   outline: lineless, detail: highly detailed, no_background: true)
3. Save to target paths above
4. Verify visually against style references in sprite-prompts.md
5. Reimport in Godot editor
