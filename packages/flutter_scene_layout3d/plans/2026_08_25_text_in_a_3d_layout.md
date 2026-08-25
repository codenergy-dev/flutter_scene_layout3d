---
status: pending
created_at: 2026-08-25T20:31:04Z
updated_at: 2026-08-25T20:31:04Z
commit: d7bb9db224f8080ddddde70d019ab5481b45d05e
---

# Text in a 3D layout

There is no `Text3d`, and `flutter_scene` has no text geometry. A Material
catalogue is mostly text: a button is a label, a `ListTile` is three of them,
an app bar is a title. This is the first thing that has to exist.

Part of [the readiness overview](2026_08_25_material3d_readiness_overview.md).
Depends on the unit contract from
[camera-bound surfaces](2026_08_25_camera_bound_surfaces.md); the backing
panel behind a label comes from
[size-driven geometry](2026_08_25_size_driven_geometry.md).

## Two problems, and they separate cleanly

**Measurement and line breaking.** Given a string, a style and a maximum
width, how many lines, how wide, how tall, where is the baseline, and where
does each run of glyphs sit. This is what the box protocol needs, and it is
pure arithmetic once the font has been consulted.

**Rasterization and geometry.** How those glyphs become something the scene
draws.

They separate because the first is testable headless and the second is not,
and because the second has three plausible answers while the first has one.
Build the first alone, behind an interface, and the renderer becomes a choice
rather than a commitment.

## What exists to build on

- [NodeBox3d](../lib/src/boxes/node_box.dart) is the wrong direction: it
  measures content that already exists and scales it into the room available.
  Text is sized *by* the room available. A text box is a new leaf, not a
  `NodeBox3d` with a clever content node.
- `Layout3d.computeMin/MaxIntrinsicExtent` and
  `computeDistanceToActualBaseline` are already in the protocol and currently
  have nothing real to answer with. Text is what makes both meaningful — the
  README says outright that nothing in a scene reports a baseline, which is
  why `Baseline3d` has to state one by hand.
- `flutter_scene` has
  [widget_component.dart](../../flutter_scene/lib/src/components/widget_component.dart):
  a live Flutter subtree rasterized onto a quad, with input forwarding. Real
  text on a surface, today, at the cost of a capture and a texture per box.
- `flutter_scene` has `texture_atlas.dart`, `GeometryBuilder`
  (`lib/src/geometry/mesh_geometry.dart:996`) and `ShaderMaterial`, which is
  what a glyph-atlas renderer is assembled from.
- `dart:ui` is the ground-truth font engine: `ParagraphBuilder`, `Paragraph`,
  `TextPainter`, `package:characters` for graphemes.

## The measurement layer, and what pretext has to say about it

[pretext](https://github.com/chenglou/pretext) is a JS/TS text measurement and
layout library whose whole design is one idea, and the idea transfers.

**What it does.** `prepare()` runs once per string: normalize whitespace,
segment the text (`Intl.Segmenter`), apply line-breaking rules, and measure
each segment with the browser's canvas `measureText` — the browser's own font
engine as ground truth, but consulted once. It returns an opaque cached
handle. `layout(prepared, maxWidth, lineHeight)` is then **pure arithmetic**
over the cached segment widths: no DOM, no reflow. Their measured claim is
0.09 ms against 43.50 ms for the DOM-interleaved equivalent, roughly 480×.
A richer handle (`prepareWithSegments`) exposes per-line streaming
(`layoutNextLineRange`, `walkLineRanges`) where each line may be given a
*different* width, and positions are expressed as segment/grapheme cursors
rather than string offsets. Break rules covered: `white-space: normal` and
`pre-wrap`, `word-break: normal` and `keep-all`, `overflow-wrap: break-word`
with a grapheme-boundary fallback for containers narrower than one word, soft
hyphens as optional break points, `tab-size: 8`. Knuth–Plass (TeX's optimal
line breaking) is available on top of the same prepared data.

**Why the idea matters more here than it does in a browser.** In this package
a text box is re-laid-out far more often than a DOM node is: whenever a
scroll offset changes the room an item gets, whenever the surface resizes,
on every frame of an animation, and — twice — whenever an `IntrinsicWidth3d`
above it asks the question, because answering an intrinsic walks the whole
subtree and then the subtree is laid out again for real. If every one of those
calls `ui.Paragraph.layout`, text dominates the frame budget and the
package's own intrinsics become unusable over labels. A prepare/layout split
makes all of that arithmetic. `IntrinsicWidth3d` over a column of labels
becomes O(segments) with no shaping at all, which is the difference between a
usable `Column3d(crossAxisAlignment: stretch)` of cards and an unusable one.

**What carries over.**

- The two-phase split, with the platform font engine as ground truth
  consulted once: `prepare()` measures each segment with a single-segment
  `ui.Paragraph` laid out at infinite width, reading `maxIntrinsicWidth`.
- A measurement cache keyed by (segment text, resolved style). Most UI text
  repeats: labels, numbers, the same words down a list.
- Segment/grapheme cursors rather than string offsets, which is what makes
  hit-testing into text and (later) selection tractable.
- The streaming per-line API with a per-line width. In a browser that is for
  shaped containers; here it is for text on a curved panel or flowing around
  a model, which is not exotic in 3D.
- Greedy first; Knuth–Plass as a separable strategy over the same prepared
  data, if it is ever wanted.

**What does not.** The DOM-avoidance motivation, `measureText` specifics, the
CSS property surface, and their `system-ui`-on-macOS accuracy caveat. Our
equivalent risks are different and are named below.

**The accuracy trade, stated up front.** Summing per-segment widths is not the
same as shaping the whole line: kerning and ligatures across a segment
boundary, and the joining behaviour of Arabic and Indic scripts, are not
modelled. pretext accepts this because segments are word-like and break
candidates, and it says so — its segment widths are "for line breaking, not
exact glyph-position data". The same trade is acceptable here for the same
reason, but it must be an explicit, swappable policy:

```
abstract class TextMeasurement3d {
  PreparedText3d prepare(String text, TextStyle style);
  TextLayout3d layout(PreparedText3d prepared, double maxWidth, ...);
}
```

with `SegmentedTextMeasurement3d` (fast, the default) and
`ParagraphTextMeasurement3d` (exact, delegating to `ui.Paragraph` per layout)
behind it. Complex scripts pick the exact one; a benchmark and a fidelity
test compare the two.

## The rendering layer

Three candidates, and the plan takes a position.

**(a) Widget texture.** A `WidgetComponent` per text box. Correct immediately —
every script, emoji, font feature Flutter supports — but a texture and a
capture per box, flat on a quad, and a re-capture policy to reason about.
Keep it as the escape hatch (`RichText3d`), not the default.

**(b) Glyph atlas and quads.** One atlas texture per font/size bucket, one
mesh per text run built with `GeometryBuilder`, glyphs as textured quads.
Scales to hundreds of labels, and with a signed-distance field stays sharp as
the panel moves toward the camera. The obstacle is that `dart:ui` exposes no
glyph rasters: a glyph has to be painted individually into a `PictureRecorder`
and read back into the atlas, keyed by (font, glyph, size bucket). This is
the default renderer for the catalogue.

**(c) Extruded outlines — real 3D letterforms.** `dart:ui` gives no access to
glyph outlines, so this needs a font parser. Out of scope; noted because
`swept_geometry.dart` in the engine is the extrusion facility it would use
if outlines ever arrive.

## Design decisions to make and record

- **Reuse Flutter's `TextStyle`, `TextAlign`, `TextDirection`** rather than
  inventing `TextStyle3d`. Component authors already know them, and the
  measurement layer needs them to build a `ui.Paragraph` anyway. Font size
  stays in logical pixels and is converted by the metrics contract.
- **A `Text3d` has zero depth by default.** Glyphs are flat; thickness behind
  a label is the decoration's job. A `depth` property may follow with (c).
- **Baseline.** `computeDistanceToActualBaseline(Axis3d.vertical)` returns
  the first line's alphabetic baseline; the other two axes return null. This
  is the first real baseline in the package.
- **Intrinsics.** `computeMaxIntrinsicExtent(horizontal)` is the single-line
  width; `computeMinIntrinsicExtent(horizontal)` is the widest unbreakable
  segment. Both from the prepared handle, without laying out.
- **Where the density comes from.** A text box needs *world units per logical
  pixel* to size type and *pixels per world unit* to choose a rasterization
  scale. Both come from the metrics contract in
  [camera-bound surfaces](2026_08_25_camera_bound_surfaces.md). Until that
  lands, take an explicit `unitsPerLogicalPixel` on the box with a documented
  default so this plan is not blocked.

## The work

- [ ] **Phase 1 — prepare.** Segmentation (graphemes via `package:characters`,
      line-break opportunities), whitespace normalization, per-segment
      measurement through `ui.Paragraph`, the cache and its eviction. Pure
      Dart, no GPU, fully testable.
- [ ] **Phase 2 — layout.** Greedy line breaking over prepared segments;
      `break-word` grapheme fallback; soft hyphens; alignment; `maxLines` and
      ellipsis. Output is lines, each with a range, a width and a baseline.
- [ ] **Phase 3 — the box.** `Text3d extends Layout3d`: sizes from the layout,
      answers intrinsics and the baseline, holds no geometry yet (a null
      renderer). Everything above is headless-testable at this point.
- [ ] **Phase 4 — the atlas renderer.** Glyph rasterization, atlas packing,
      run meshes, the material. SDF as a follow-up within the phase.
- [ ] **Phase 5 — `RichText3d`** over `WidgetComponent`, for what the atlas
      cannot do.
- [ ] **Phase 6, optional** — `ParagraphTextMeasurement3d` for complex
      scripts, per-line variable width, Knuth–Plass, bidi levels.

## Tests

- Measured width and height against `TextPainter` ground truth for Latin text
  at several widths, within a stated tolerance; the tolerance *is* the
  accuracy claim.
- Break rules: normal, `keep-all`, `break-word`, soft hyphen, a word wider
  than the container, an empty string, whitespace-only.
- Intrinsics answer without a layout pass, and a `Column3d` with
  `CrossAxisAlignment3d.stretch` under `IntrinsicWidth3d` sizes to the widest
  label.
- The baseline is real: two `Text3d`s of different sizes in a
  `CrossAxisAlignment3d.baseline` row share a line.
- A benchmark that asserts the hot path performs no `Paragraph.layout` — the
  point of the whole design, so it should fail loudly if a change reintroduces
  one.
- Cache: a style change invalidates, an identical string reuses.

## Out of scope

Editable text, IME, selection, cursor rendering, rich-text spans in `Text3d`
(they belong to `RichText3d`), vertical writing modes.
