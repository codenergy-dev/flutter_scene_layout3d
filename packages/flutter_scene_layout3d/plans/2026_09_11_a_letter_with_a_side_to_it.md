---
status: completed
created_at: 2026-09-11T18:18:23Z
updated_at: 2026-09-11T19:05:00Z
commit: d5c6b5972a17890350a624dd41027a830d6ce9a0
---

# A letter with a side to it

Every glyph in this repository is one textured quad. That is what makes a
screen of type cheap — one atlas, one draw per label — and it is also why the
gallery's text and icons read as decals stuck onto the panels rather than as
things *in* the scene. Turn a panel and the letters turn with it, perfectly
flat, with no edge to catch the eye. A card next to them is 4dp thick; its
title is zero.

This gives a glyph a third dimension: a front face, a back face, and a **wall**
around its silhouette, so a letter seen at an angle shows a side.

## Why not the two obvious things

**Extruding the font's outline** is the textbook answer and is not available:
`dart:ui` exposes no glyph outlines, and there is no font parser here. The
`Text3dRenderer` docstring has been offering "extruded outlines where a font
parser is available" as a hypothetical since the text layer was written; it is
still hypothetical.

**Stacking slices** — drawing the same alpha-cut quad at a dozen depths — needs
the spacing to be under a screen pixel or the side comes out as a comb, which
means the slice count has to rise with how close the viewer is and how thick
the type is. It is a picture of thickness that stops working exactly when
someone leans in to look at it.

## What is actually available: the raster

The atlas already rasterizes every glyph, and `GlyphAtlas3d.rasterize` already
reads the pixels back to the CPU — `GlyphAtlasImage3d.pixels`, straight-alpha
RGBA — because that is how a texture gets uploaded. The silhouette is *in that
buffer*. Tracing it is arithmetic over a bitmap, which means it runs headless
and can be pinned down by tests the way the rest of the text layer is.

So: trace the ink's boundary out of the atlas image, once per distinct glyph,
and build the wall from it.

## The pieces

### 1. `lib/src/text/glyph_outline.dart` — new

`GlyphOutline3d`: a glyph's closed contours, in **logical pixels from the
top-left of its padded cell** — the same origin `TextGlyphQuad3d.left` and
`.top` are measured to, so an outline drops onto a placed quad with an add.

`traceGlyphOutline(...)`: mask → contours, in three steps, all testable.

- **Threshold** at `kGlyphOutlineThreshold`, which is `text_glyph3d.fmat`'s own
  `alpha_cutoff` (0.35). The wall has to meet the face where the face's
  fragments stop being discarded, or the two silhouettes disagree and the
  letter grows a fringe.
- **Boundary edges.** For each ink texel, each of its four sides whose
  neighbour is not ink becomes a directed unit edge, wound so that the
  **outward normal is always `(-dy, dx)`** — with `y` downward, that is away
  from the ink for all four sides, and it stays away from the ink inside a
  hole, which is what makes an `o` come out right with no special case.
- **Linking.** Every grid point has as many boundary edges leaving it as
  arriving, so the edge set decomposes into closed loops; walk them, consuming
  edges. At a diagonal junction — two ink texels touching at a corner — take
  the candidate maximizing `cross(in, out)`, which keeps the ink 8-connected
  and stops a thin diagonal stroke from splitting into two loops.
- **Simplification.** Douglas–Peucker per loop, tolerance stated in logical
  pixels and converted to texels, so a staircase becomes a polygon of a few
  dozen segments instead of a few hundred, and the segment count does not grow
  when someone raises `AtlasText3dRenderer.resolution`.

  **0.30, and the plan's 0.15 was wrong.** At 0.15 a single-texel step is
  inside the tolerance only marginally, so a hard-turned 64dp label came out
  with a visible sawtooth along the near-horizontal tops of `s`, `u` and `r` —
  photographed, not reasoned about. Doubling it clears a one-texel step
  outright and is still under a third of a logical pixel, which nothing at UI
  sizes can show. The floor of 0.6 texels stays: a tolerance under half a texel
  cannot remove a step at all, which is the entire job.

### 2. `GlyphAtlas3d` — outlines alongside the texture

Trace during `_flush`, from the image it already accepted, for every non-blank
slot without an outline yet. Keyed by grapheme and therefore **immune to a
repack**: a cell's size does not change when it moves. Two additions:
`outlineFor(grapheme)` and `outlineRevision`, which moves when outlines land so
a renderer can tell "the texture changed" from "the silhouettes changed".

Outlines arrive with the pixels — that is, a frame or two after the first
layout, the same contract the atlas already documents for the texture itself. A
label draws flat until then and rebuilds when they land, through the listener
it already has.

### 3. `buildGlyphWallSegments` in `text_geometry.dart`

Places each glyph's contours at its quad's position. Output is a flat list of
segments in logical pixels — eight numbers per wall, no GPU, no mesh, matching
what `buildTextGlyphQuads` is for.

### 4. `AtlasText3dRenderer` — three surfaces instead of one

- `depth` (logical pixels) and `depthFactor` (a fraction of the font size,
  0.10, used when `depth` is null). Relative by default because a 24dp icon and
  a 57dp display headline want different walls and neither wants the body
  text's.
- The extrusion grows **toward the viewer**: the back face stays on the plane
  the flat quad used to occupy, so `depthOffset` and every `contentLift`
  figure a component already computed still clear the surface underneath.
- One `Mesh.primitives` with two primitives: the two glyph faces on the
  existing `GlyphMaterial3d`, and the walls on an opaque `UnlitMaterial` with
  the shading baked into vertex colours. Opaque, so the walls write depth in
  the opaque pass rather than joining the translucent sort the faces have to
  survive.
- Baked shading rather than a light: type here is deliberately unlit so it does
  not dim as a panel turns away, and a wall lit by the scene would reintroduce
  exactly that. A fixed key direction in layout space gives a letter a
  consistent light-from-the-upper-left edge that turns with it.

## What this does not do

`RichText3d` stays flat. It draws a whole paragraph Flutter rasterized in full
colour onto one quad; there is no per-glyph mask to trace and no atlas holding
one. Say so in its dartdoc.

## What it costs

Measured on a GPU rather than estimated: **about 18 wall segments a glyph** at
UI sizes (14–16dp) and 28 for a 24dp icon, so "Continue" is 8 glyphs and 143
wall quads, and a 35-character line is 638. Twenty-odd times the geometry a
flat label was, and still a couple of thousand vertices for a whole line.

The tolerance is what holds it there, and it is why the tolerance is stated in
logical pixels: in texels it would have been fixed against the *raster*, so
raising `AtlasText3dRenderer.resolution` from 2 to 3 to sharpen the faces would
have multiplied the wall geometry of every label in the scene by more than two.

## What was found on the way

**A tolerance wide enough eats the letter.** Douglas–Peucker deletes a corner
it can reach across, and a loop of two points is not a loop, so a badly chosen
tolerance leaves a glyph with no wall — silently, because the type still draws,
flat. There is a test that states it outright rather than a guard that hides
it: the failure is visible, the tolerance is a constant, and the default is two
orders of magnitude away from the cliff.

**The back face needs its own winding.** The compiled glyph material culls
nothing, so a second quad at the extruded depth would have drawn either way —
but `UnlitGlyphMaterial3d`, the fallback an application that installs no shader
gets, blends, and `flutter_scene` culls back faces for anything that is not
opaque. A back face wound like the front one is invisible in exactly the
application with the least to fall back on.

## Tests

- `test/glyph_outline_test.dart`: a solid block traces to one rectangle with
  the right logical-pixel corners; a ring traces to two contours; an empty mask
  to none; the outward normal of every segment points away from the ink, in a
  hole as well as outside; two texels touching diagonally give one loop;
  simplification collapses a staircase and keeps the corners.
- `test/text_atlas_test.dart`: the atlas has an outline for a glyph after a
  flush and not before, and `outlineRevision` moves once.
- Wall geometry: segment count, the z range, the winding around the stated
  normal, and that a zero depth builds no wall at all.

Plus the render probe, because none of the above can say whether the wall is
*drawn*. `glyph_extrusion` and `glyph_extrusion_flat` are the same letter on
the same turned surface with and without a thickness, and the test asserts the
thick one covers more of the frame and that the extra ink is on one side. A
wall wound inside out is culled and the pair comes out equal, which is the
failure mode with no other symptom.

## Documentation

`docs/traps.md` gets the one that will cost someone real time: **a glyph's wall
is traced from the atlas raster, so it arrives with the texture and not with
the layout** — a label is flat on the frame it is first laid out on, and the
thing that fixes it is the atlas listener, not a relayout. With the two
corollaries: the trace threshold is the shader's `alpha_cutoff` and has to be,
and the extrusion grows toward the viewer so that every `contentLift` already
computed against the old plane still holds.

Both READMEs, `Icon3d`'s dartdoc (an icon is text, so an icon is a slab now)
and `RichText3d`'s (it is the one thing here that stays flat, and it is worth
saying beside a `Text3d` that does not).
