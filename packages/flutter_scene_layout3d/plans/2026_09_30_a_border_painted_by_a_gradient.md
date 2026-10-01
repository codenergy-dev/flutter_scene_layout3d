---
status: completed
created_at: 2026-09-30T20:14:57Z
updated_at: 2026-09-30T21:30:00Z
commit: 2f227ef2bcf78044b184e1c1380052cc1060d26c
---

# A border painted by a gradient

Phase 0 of phase 3 of
[the components a screen still needs](../../flutter_scene_material3d/plans/2026_09_21_the_components_a_screen_still_needs.md),
in the package it belongs to — the rule the catalogue's own phase 0 set, that
a change to the layout protocol the catalogue needs gets its plan here rather
than a line item in a Material plan.

## What the catalogue needed

Phase 3 builds `CircularProgressIndicator3d`, and Flutter's is one call:
`canvas.drawArc` with a stroked paint. **Nothing in this package can draw an
arc.** The panel shader draws a rounded box, and everything it can put on that
box is either the whole of it or an outer band of it:

- A `ShapeScale3d.full` radius on a square box is a circle, and a `Border3d`
  on a transparent circle is a **ring** — the band where the distance field is
  shallower than the border's width. That is the stroke, all the way round.
- A `SweepGradient` fill with a hard stop is a **wedge** — the angular cut —
  and a fragment the gradient leaves transparent is discarded, so the rest of
  the circle is genuinely not there.

A ring is the radial half of an arc and a wedge is the angular half, and the
shader has no way to intersect them. The fill is always the inner disc and
the border always the outer band; a transparent border erases the rim of a
wedge rather than the middle of it. Clip planes are an intersection of
half-spaces from the layout's own clips, axis-aligned in practice and convex
by construction, so they cannot cut an arc longer than half a turn either.

## The design

**A border's band can be painted by a gradient**, exactly as a decoration's
fill already can:

```dart
BoxDecoration3d(
  color: const Color(0x00000000),              // nothing in the middle
  borderRadius: const BorderRadius3d.circular(9999),
  border: Border3d(
    width: 4,
    gradient: SweepGradient(
      colors: [primary, primary, clear, clear],
      stops: const [0.0, 0.3, 0.3, 1.0],       // 30% of a turn, from 3 o'clock
    ),
  ),
)
```

`Border3d.gradient` replaces `Border3d.color` in the band, which is the
sentence `BoxDecoration3d.gradient` already says about `color`. The arc is the
band where the ramp is opaque, and everywhere else is discarded for the
reason a transparent fill is: the shader throws away a fragment with no alpha
rather than writing depth for it.

Three decisions, each with a reason:

- **One ramp per panel.** The shader has one set of gradient uniforms — eight
  stops and eight colours, which is most of its parameter block — and a
  second set for the border would double it for a feature one component uses.
  So the gradient uniforms paint the fill *or* the band, and the unused fourth
  component of the shader's `gradient` vector says which. A decoration with
  both a fill gradient and a border gradient asserts, rather than quietly
  dropping one.
- **No rotation.** A `SweepGradient`'s angles are Skia's: `t` is measured from
  an angle in `[0, 2π)`, so a sweep that starts at twelve o'clock (`-π/2`)
  draws its first quarter clamped, and Flutter's answer is a
  `GradientRotation`, which the shader has no arithmetic for and still
  reports rather than approximates. An arc that has to start somewhere other
  than three o'clock is **turned on the node tier** instead: a circle's
  distance field does not care which way it faces, and a `nodeTransform`
  costs one matrix and no layout. That is also how an indeterminate spinner
  turns, so the one mechanism serves both.
- **A hard stop is not anti-aliased.** The outline and the ring's two edges
  are feathered by one pixel of the distance field's own rate of change; the
  ends of an arc are a step in `t` and are not. At a 4dp stroke that is a few
  stair steps at each end, the same as a hard-stop gradient on a fill has
  always had. Feathering `t` would need the shader to know which kind of
  gradient wants it, and a sweep's rate of change goes to infinity at its
  centre.

`Border3d.isNone` learns that a border with a gradient draws something even
when its colour is transparent, and `Border3d.lerp` interpolates the gradient
with `Gradient.lerp`, as `BoxDecoration3d.lerp` does for the fill.

## The work

- [x] `Border3d.gradient`, with `isNone`, `lerp`, equality and `toString`.
- [x] One ramp per panel, asserted — where the decoration is **resolved**,
      not where it is constructed; see below.
- [x] `BoxDecoration3dUniforms` resolves the border's gradient when it has
      one, with `gradientPaintsBorder`, and `applyTo` writes it into the
      `gradient` vector's fourth component.
- [x] The shader paints the band from the ramp when that component is set.
- [x] Tests, in `test/picture_test.dart` beside the fill's: the uniforms for
      a border gradient, the flag, a border with no width sending no ramp
      anywhere, the assert, `lerp`, `isNone` and equality.
- [x] Two render probes, `arc_on_a_ring` and `arc_turned`: ink in the
      quadrant the arc covers and none elsewhere on the ring or in its
      middle, and the same ring turned a quarter back on the node tier with
      the ink moved to twelve o'clock. Both pass on macOS.
- [x] The changelog, `Border3d`'s and `BoxDecoration3d`'s dartdoc, the
      package README beside the fill gradient, and `docs/README.md`.

## What the reasoning got wrong

Little, and one thing it did not know to ask.

- **The assert could not go in the constructor.** `BoxDecoration3d` is
  `const`, and a `const` constructor's assert cannot read a field of its
  border — the same wall `docs/traps.md` records for `List.length`. The check
  is in `BoxDecoration3dUniforms.resolve`, which every painted panel passes
  through, so it is exactly as loud and a frame later.
- **The turn's direction needed a picture.** The plan reasoned that a
  positive `rotateZ` in layout axes turns clockwise on the face, because y
  runs down, and that a sweep's angle runs the same way. Both are true, and
  nothing headless could say so: `arc_turned` is the scene that does, by
  finding the ink where the reasoning said it would be rather than mirrored
  into the quadrant beside it.
- **It did not ask what else draws a partial ring.** A 2024 circular
  indicator's track has a gap either side of the arc, and a tab indicator in
  phase 5 has an inset. Both are a second hard stop in the same ramp — the
  track is `[arc, arc, clear, track, track, clear]` — and the eight stops the
  shader has room for are enough for either. Nothing here needed changing
  for them; it is written down so that the next plan does not re-derive it.
