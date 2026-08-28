---
status: in progress
reason: phases 1-3 and 6 are done; phases 4 (the atlas renderer) and 5
  (RichText3d) are not, because a glyph atlas needs a GPU context that
  `flutter test` does not have. `2026_08_28_render_coverage.md` builds that
  lane and is the thing to do first. See "What was left out, and why".
created_at: 2026-08-25T20:31:04Z
updated_at: 2026-08-26T22:51:13Z
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

- [x] **Phase 1 — prepare.** Segmentation, whitespace normalization,
      per-segment measurement through `ui.Paragraph`, the cache and its
      eviction. `lib/src/text/break_rules.dart` (the policy),
      `lib/src/text/line_break.dart` (normalize and segment, no font),
      `lib/src/text/prepared_text.dart` (the handle),
      `lib/src/text/text_measurement.dart` (the measuring and the LRU cache).
      Graphemes come from `package:characters`, which is a new dependency of
      this package.
- [x] **Phase 2 — layout.** Greedy line breaking over prepared segments;
      `break-word` grapheme fallback; soft hyphens; alignment (including
      justify); `maxLines` and ellipsis. `lib/src/text/text_layout.dart` is
      the output — lines, each with a range, a width, a baseline and its
      runs.
- [x] **Phase 3 — the box.** `Text3d extends Layout3d` in
      `lib/src/text/text3d.dart`, with `SceneText3d` beside it in
      `lib/src/widgets/layouts.dart`. Sizes from the layout, answers
      intrinsics and the baseline, holds no geometry.
- [ ] **Phase 4 — the atlas renderer.** **Not done.** The seam is:
      `Text3dRenderer` and `Text3dRenderRequest` in
      `lib/src/text/text_renderer.dart`, called after every layout of the box
      and disposed with it. See *What was left out, and why* below.
- [ ] **Phase 5 — `RichText3d`** over `WidgetComponent`. **Not done**, same
      reason.
- [x] **Phase 6, partly** — `ParagraphTextMeasurement3d` is in, because the
      plan's own design section makes the *swappable policy* part of phase 1
      rather than an optional extra: without a second implementation the
      interface is a claim rather than a seam, and the fidelity test has
      nothing to compare against. Per-line variable width, Knuth–Plass and
      bidi levels are not in; the prepared handle is the shape they would be
      built on and nothing has asked for them.

## Tests

`test/text_test.dart` (53) and `test/text_box_test.dart` (27).

- [x] Measured width and height against `TextPainter` ground truth, for eight
      strings at every whole width from 10 to 210 logical pixels. **The
      tolerance is zero** — they agree exactly, which is a stronger claim than
      the plan asked for and is what the break-word correction below bought.
- [x] Break rules: preserved and collapsed whitespace, `keep-all`,
      `break-word` and its `overflow` opposite, soft hyphen (taken and not
      taken), zero-width space, tabs, a word wider than the container, an
      empty string, whitespace-only, a trailing newline, CJK, a grapheme
      cluster that must not be split, closing punctuation that may not start a
      line.
- [x] Intrinsics answer without a layout pass — asserted through the
      paragraph counter, not by inspection — and a `Column3d` with
      `CrossAxisAlignment3d.stretch` under `IntrinsicWidth3d` sizes to the
      widest label.
- [x] The baseline is real: two `Text3d`s of different sizes in a
      `CrossAxisAlignment3d.baseline` row share a line, and a wrapping label
      reports its *first* line's baseline.
- [x] The benchmark: `debugTextParagraphCount` does not move across 200
      layouts at 200 different widths with alignment and a line limit. It is
      exported, so a later plan's hot path can make the same assertion.
- [x] Cache: an identical string reuses, a style change invalidates, the LRU
      evicts rather than growing.
- [x] Extra: the unit contract (a denser surface, a text scale, a change
      reaching a deep label), `maxLines` and ellipsis through the box,
      `softWrap: false`, relayout at the same width doing nothing, a ray
      finding the label, the renderer seam being called and disposed, and the
      declarative widget picking up `DefaultTextStyle` and `Directionality`.

## What the original reasoning got wrong

**Flutter breaks a word that does not fit; the plan treated that as an
opt-in.** `overflow-wrap: break-word` was written up as one rule among
several, with CSS's default (let it overflow) implied as ours. It is the other
way round: Skia breaks an over-wide word at a grapheme boundary, so a
`Text3d` whose default matched CSS would report a different height from the
equivalent `Text` at every narrow width. `OverflowWrap3d.breakWord` is the
default and `OverflowWrap3d.overflow` is the opt-out.

**And it does not break the word in isolation.** The obvious implementation —
put the over-wide word on a line of its own and split it there — is one line
out from Flutter at several widths. What Skia actually does is pack the word's
graphemes into whatever room is left *on the current line*, and then carry on
into the following word by graphemes as well, so `'hello world'` at 42px is
`hell` / `o wo` / `rld`, not `hell` / `o` / `worl` / `d`. Matching that is
what took the ground-truth comparison from "close" to exact. It is written up
on `_breakLines`.

**Whitespace collapsing is not the default.** The plan named CSS's
`white-space: normal` and `pre-wrap` as the two modes to cover, which reads as
though collapsing were the ordinary case. Flutter preserves whitespace, and
this package mirrors Flutter, so `TextWhitespace3d.preserve` is the default and
`collapse` is the opt-in. A hard `\n` is a line break under both, which is
Flutter's rule rather than CSS's.

**The break rules belong to `prepare`, not to `layout`.** The plan's sketch
was `prepare(text, style)` and `layout(prepared, maxWidth, lineHeight)`. The
rules decide the *segmentation* — where a line may end at all — so they have
to be in the first phase or the second one is not arithmetic. And `lineHeight`
is not a layout parameter either: it comes from `TextStyle.height` through the
paragraph style, which `prepare` has already consulted. What `layout` does
need, and the plan did not have, is a **`minWidth`**: a block shrink-wraps to
its longest line, so without one there is nothing for `textAlign` to align
inside of. It is the same pair `TextPainter.layout` takes, for the same
reason.

**Grapheme widths cannot be measured in `prepare`.** Measuring every grapheme
of every string up front would cost a `ui.Paragraph` per character for a
policy most text never exercises. They are measured on first use and kept on
the handle, so the first layout narrow enough to break a given word pays once
and every layout after it is arithmetic again. The benchmark test warms that
up before it starts counting, and there is a separate test asserting the
one-time cost is one-time.

**The escape hatch for a missing unit contract was not needed.** The plan
allowed for an explicit `unitsPerLogicalPixel` on the box "until [camera-bound
surfaces] lands". It landed first, so `Text3d` reads `Layout3d.metrics` like
any other box and has no unit property of its own. `logicalPixelScale` is the
one number it exposes, and it is derived rather than settable.

**Tabs are a fixed advance, not a tab stop.** A real tab stop depends on where
the tab sits on the line, and a line's position is not known until after it
has been broken and aligned — which would put an intra-segment cursor into the
arithmetic half for a feature a 3D label has no use for. A tab is `tabSize`
space widths, and says so.

**The line box comes from a probe, not from the content.** `prepare` measures
a single space at the style to get the line height and baseline, the way
`TextPainter.preferredLineHeight` does, and then widens the box if a segment's
own paragraph came out taller (which is how a fallback font for an emoji gets
counted). The alternative — deriving the box from the content — makes an empty
label a different height from a full one.

## What was left out, and why

**Phases 4 and 5, the two halves of drawing.** Everything above is headless
and is tested; a renderer is neither. A glyph atlas needs per-glyph rasters,
which `dart:ui` does not expose: each glyph has to be painted into a
`PictureRecorder`, read back through `Picture.toImage` and `Image.toByteData`
(both asynchronous), packed into an atlas and uploaded with
`Texture2D.fromPixels`, which requires a GPU context that `flutter test` does
not have. The widget-capture path has the same problem plus a dependency on
`SceneView` hosting the subtree. Landing several hundred lines of GPU code
that neither this suite nor a reviewer could execute would have been worse
than landing the seam, and the plan's own framing — *"build the first alone,
behind an interface, and the renderer becomes a choice rather than a
commitment"* — is the argument for stopping here. `Text3dRenderer` takes
everything a renderer needs, including both directions of the unit conversion
and the rasterization resolution, and `Text3d` calls it after every layout and
disposes it with the box.

**Knuth–Plass, per-line variable width, bidi levels.** The prepared handle is
the right shape for all three (they are strategies over the same segment
widths), and none of them has a caller. `ParagraphTextMeasurement3d` covers
the bidi case today by handing it back to the platform.

## What the later plans need from this

- `Text3d(data, style: ..., textAlign:, textDirection:, softWrap:, overflow:,
  maxLines:, depth:, rules:, measurement:, renderer:)` is the box, and
  `SceneText3d` the widget. Every property has a setter that invalidates the
  right amount: text, style, rules and the measurement re-prepare; alignment,
  direction, wrapping, overflow and `maxLines` only re-lay-out.
- **Everything in the measurement layer is in logical pixels.** `Text3d`
  multiplies by `logicalPixelScale`, which is
  `metrics.unitsPerLogicalPixel * metrics.textScaleFactor`. A prepared handle
  therefore survives a change of metrics, which matters because a metrics
  change relayouts the whole tree.
- `Text3d.textLayout` is the last layout (null before the first), and
  `Text3d.prepared` the measured handle. Between them they carry every line,
  its runs, its width and its baseline, which is what
  [size-driven geometry](2026_08_25_size_driven_geometry.md) needs to put a
  panel behind a label and what a renderer needs to draw one.
- `debugTextParagraphCount` is the instrument for "this path does no
  shaping". [Animation](2026_08_25_animation_and_scroll_physics.md) dirties
  layout every frame and should assert against it.
- Text is the first thing in the package with a **real baseline**
  (`Axis3d.vertical` only). `Baseline3d` is still what states one for content
  that has none.
- A `Text3d` answers hit tests on its own account, like a `NodeBox3d`. A label
  inside a `Button3d` wants an `IgnorePointer3d` around it so the button
  answers rather than the text — that is
  [pointer dispatch](2026_08_25_pointer_dispatch_and_focus.md)'s business.
- The renderer seam is open. Whoever implements it owns the level-of-detail
  question [camera-bound surfaces](2026_08_25_camera_bound_surfaces.md) left
  open: `logicalPixelsPerUnit` is a promise about screen pixels only for a
  camera-bound surface.

## Out of scope

Editable text, IME, selection, cursor rendering, rich-text spans in `Text3d`
(they belong to `RichText3d`), vertical writing modes.
