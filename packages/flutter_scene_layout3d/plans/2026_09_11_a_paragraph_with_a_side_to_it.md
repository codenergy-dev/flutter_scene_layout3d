---
status: completed
created_at: 2026-09-11T20:18:22Z
updated_at: 2026-09-11T21:05:00Z
commit: 54e28974c6ff3f65e9c44fcf57310c251f27e5f4
---

# A paragraph with a side to it

[A letter with a side to it](2026_09_11_a_letter_with_a_side_to_it.md) gave
every glyph a wall and left one thing flat: `RichText3d`, which draws a whole
paragraph Flutter rasterized onto a single quad and therefore has no per-glyph
mask to trace. That plan said so outright and moved on. This closes it, and the
route is not the one that looked obvious.

## Two things that do not work, and why

**The atlas trick does not transfer.** A `RichText3d`'s capture arrives as a
`gpu.Texture` through `WidgetComponent.bindOnly`'s `bind` callback. There is no
CPU-side buffer anywhere, and at the default `WidgetUpdatePolicy.everyFrame`
that texture is re-delivered every frame. Reading it back to trace it would be
a GPU-to-CPU stall per frame.

**Extruding the box does not work either, and this was photographed rather
than reasoned about.** The obvious cheap answer — the box already takes a
`depth`, so make the quad a slab with four sides and a back face — produces two
different wrong pictures, both for the same reason. A captured paragraph is
*mostly transparent*: with a back face you see straight through the letters to
the mirrored copy behind them and the type doubles; without one, the only side
that ever faces the viewer is the bottom, and it reads as a stray rule under
the paragraph.

The reason is structural and worth keeping: **extrusion reads as thickness only
when the thing being extruded is the ink.** Extruding the bounding rectangle of
transparent content draws the outline of an empty box in the air. That is why
there is no cheap version of this.

## What does work

Re-rasterize the paragraph **on the CPU**, from the `TextPainter` the box
already holds and has already laid out. `painter.paint` into a
`ui.PictureRecorder`, `toImage`, `toByteData` — the same three steps
`GlyphAtlas3d.rasterize` takes, for the same reason, and with no GPU and no
capture involved. That yields an alpha mask of the paragraph, and an alpha mask
has the *ink* as its silhouette.

`traceGlyphOutline` then handles it **unchanged**: it already takes an
arbitrary rectangle of an arbitrary buffer, and a paragraph is just a larger
rectangle with more contours in it.

### The part that had to be prototyped

A `Text3d`'s wall takes the label's one colour. A rich span has no such thing.
The prototype settled it: because the mask is on the CPU, each segment's colour
can be **sampled out of the bitmap**, a texel or two inside the ink along the
inward normal. A span reading "Signed in as **Ada** — admin" came out with a
blue-grey wall on the first run, orange on `Ada` and green on `admin`, with no
per-span bookkeeping at all — the geometry asks the picture what colour it is
standing on.

That is what makes this worth doing rather than a compromise, and it is also
what makes the fallback honest: where the sample lands on nothing, the segment
takes the root span's colour.

## Measured, before deciding

| Content | Bitmap | Contours | Segments | Time |
| --- | --- | --- | --- | --- |
| One line, 40dp | 900x282 texels | 31 | 809 | 41–78ms |
| A paragraph, 15dp | 900x702 texels | 597 | 7960 | 81ms |

The time is dominated by `toImage`/`toByteData` rather than by the trace — a
bitmap two and a half times larger cost about the same — and it is
asynchronous, so it costs no frame. It is the same contract the atlas already
has: the wall arrives a few frames after the content it belongs to.

**And the benefit runs the opposite way to the cost.** At 15dp on a panel at
reading distance the wall is barely visible, and that is the case that costs
eight thousand segments; at display sizes it is the whole point and costs
hundreds. The honest statement is that this earns its keep on large rich type —
a heading with mixed styles, and Arabic or Devanagari at any size, which cannot
use `Text3d` at all and are otherwise condemned to be flat for ever.

It is on by default anyway, because a `RichText3d` sitting flat beside a
`Text3d` on one panel reads as a mistake, and `glyphDepth: 0` is one word.

## The pieces

### 1. `GlyphWallSegment3d` gains a colour

Optional, null meaning "whatever the caller's own tint is", which is every
existing caller. `AtlasText3dRenderer.buildGlyphWallGeometry` reads
`segment.color ?? color`. One type, two customers, and — the reason it is
shared rather than copied — **one derivation of the winding**. Getting that
backwards is the bug with no symptom, and writing it twice is how it would
happen.

### 2. `rasterizeParagraph` and `buildParagraphWallSegments`

Both top-level in `rich_text3d.dart`, both headless. The first is `dart:ui` and
async but touches no GPU; the second is arithmetic over a bitmap and a traced
outline, and is where the colour sampling lives.

### 3. `RichText3d.glyphDepth` / `glyphDepthFactor`

Named for the glyphs, because `depth` is already taken by the box's own extent
and means something different. `glyphDepthFactor` is 0.10 of the **root span's**
font size, exactly as `AtlasText3dRenderer.depthFactor` is — one depth per box
rather than one per span, because a wall that changed thickness at a style
boundary would come apart at the seam.

The extrusion grows **toward the viewer**, and the face moves with it: the
captured quad goes to `z = -thickness` and the wall runs from there back to
`z = 0`, which is the plane the flat quad occupied. Identical to a glyph's
wall, which matters because the two sit next to each other, and it keeps every
`contentLift` computed against that plane valid.

### 4. A cap, reported rather than absorbed

A paragraph large enough to trace into tens of thousands of segments gets no
wall and an error in debug, the way `GlyphAtlas3d._grow` refuses to grow past
`maxSize`. Silently building a thirty-thousand-vertex mesh for an edge a reader
cannot see is the failure this is guarding, and the cure is `glyphDepth: 0` on
the box that asked for it.

### 5. The dartdoc `depth` never had

`RichText3d(depth: 3)` reports `Size3d(0.700, 0.140, 3.000)` and draws a flat
quad. The box tells its parent it is three units thick and puts nothing there.
That is defensible — it is a reservation, like a `SizedBox3d`'s — and it is not
what the current wording implies. Say it.

## Tests

- `rasterizeParagraph` gives a bitmap the size the painter and the resolution
  imply, with ink in it and clear margins.
- `buildParagraphWallSegments` samples a two-colour span into two colours, and
  falls back where the sample lands on nothing.
- A segment's own colour wins over the builder's; a segment without one takes
  the builder's, which is every glyph in the atlas path.
- The wall is empty at `glyphDepth: 0`, and the box then draws exactly the
  single flat quad it always did.
- The cap refuses, and says so.
- A render probe pair, the same shape as `glyph_extrusion`: one paragraph
  turned, with and without a wall, asserting the walled one covers more frame.

## What the implementation added to the plan

**A `_wallKey`, and it is the difference between viable and not.** The trace
is kicked off from `performLayout`, which runs on every scroll and every frame
of an animation that moves the paragraph. Hashing the span, the laid-out width
and height, the resolution and the alignment means a paragraph that lays out
again *at the same width* traces nothing — so the cost is per distinct picture
of the paragraph rather than per layout, which is the only reason this can be
on by default.

**A token, not a flag, for the async gap.** `toImage` is awaited twice over,
and anything that moves in the meantime — a new span, a relayout at another
width, disposal — makes the raster a picture of a paragraph that no longer
exists. An incrementing token checked on both sides of the await is what drops
it, and `_releaseSurface` bumps it too so a disposed box cannot be handed a
wall.

**The face moves, and that is deliberate.** `buildTextQuadGeometry` gained a
`z`, and the capture is drawn at `-thickness` with the wall running back to
zero — identical to a glyph's, which is what makes a `RichText3d` and a
`Text3d` on one panel read as the same material rather than as two different
depths of the same idea.

## Documentation

`docs/traps.md`'s glyph-wall entry currently ends by saying `RichText3d` has no
wall. It has one now, on a different clock and with two exclusions worth
stating: a `WidgetSpan`'s content is not painted by a `TextPainter`, so an
inline widget gets no wall; and the trace runs on layout rather than on the
capture, so a wall does **not** follow anything animating inside the subtree
under `WidgetUpdatePolicy.everyFrame`.
