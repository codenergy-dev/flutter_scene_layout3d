---
status: completed
created_at: 2026-09-09T21:50:00Z
updated_at: 2026-09-09T23:05:00Z
commit: 8a7da597f7778ffe2869f09f204ed3ef6ab54c79
---

# Where a press landed

`StateLayer3d` is one colour and one opacity across a whole box. That is
Material's state layer exactly, and for hover, focus and drag it is the whole
story. It cannot say *where* a press landed, which is what a ripple is.

The Material catalogue's plan spotted, two months before it needed it, that
this is two shader parameters rather than a redesign — because the panel
shader's whole trick is that the slab's vertex colours are its own
object-space coordinates, so **a fragment already knows where in the box it
is**. A ripple is a distance from a point and a `smoothstep` on it. Everything
else about the ripple — the timings, the curve, the press that starts it —
belongs to `flutter_scene_material3d`. This plan is the layout package's half:
the parameters, the value that carries them, and the one piece of arithmetic
that gets a point from the box that recognized the press to the box that draws
the wash.

## What the catalogue needed and could not get from here

Three things, and the third is the one that was not obvious.

1. **A place to put the origin and the radius.** `BoxDecoration3dUniforms`
   writes eight parameters and `assets/box_decoration3d.fmat` declares them;
   neither had any notion of a ripple, and the guard test in
   `test/decoration_material_test.dart` exists precisely so that adding one on
   the Dart side without adding it to the shipped `.fmat` fails loudly instead
   of drawing a default.

2. **A value to carry it on the repaint-only tier.** `DecoratedBox3d.stateLayer`
   is a setter that writes a uniform and marks nothing dirty for layout. A
   ripple is an animation, so it has to ride on that setter or it is not a
   ripple, it is a stutter.

3. **A change of frame.** The press lands on an `InkWell3d`'s gesture boxes;
   the state layer belongs to the `Material3d`'s decorated box, which is a
   different box with a different origin. `Layout3d.anchorOffsetTo` — phase 6's
   answer to "nothing anchors anything" — does exactly this arithmetic, but
   only between two *alignment points*. A finger is not an alignment.

## The design

### `Ripple3d`, on `StateLayer3d`

A ripple is three numbers: where, how far, how strong. It hangs on
`StateLayer3d` rather than beside it, because the two are one thing in
Material 3 — the spec describes the press state layer as *arriving* with a
ripple — and because that keeps the whole wash on one setter and one
comparison.

The consequence worth stating out loud: **the ripple has no colour of its
own.** It is drawn in `StateLayer3d.color`, so it cannot drift from the wash
it is a part of, and the shader spends two `vec2`s instead of a fifth `vec4`.

`Ripple3d.radiusCovering(size, origin)` is the radius at which a ripple covers
every corner of a box from wherever it started, which is where Material's
ripple ends. It lives here rather than in the catalogue because it is geometry
over a `Size3d` and an `Offset3d`, and because the render probe needs it too.

### The units, which are not this package's usual ones

**`origin` and `radius` are in world units**, and everything else on a
`BoxDecoration3d` is in logical pixels. That is a deliberate exception, and the
reason is where the numbers come from: a press reports its position through
`PointerEvent3d.localPosition`, which is in world units and stays exact for a
surface seen at any angle, and the radius is compared against a box's extent,
which is in units too. Converting to dp and back would be a round trip that
can only lose precision, to produce a number no specification is written in.
`InkWell3d.minimumSize` already takes world units for the same reason.

### Two `vec2`s, and one `smoothstep`

```
{ type: vec2, name: ripple_origin, default: [0, 0] },
{ type: vec2, name: ripple,        default: [0, 0] },
```

`ripple_origin` is in the box's own frame with the origin at its corner —
**the same frame the clip planes are in**, so there is one convention in the
shader rather than two. The fragment moves it to the centre frame the signed
distance field works in by subtracting the half extent, which is the clip's own
change of frame in reverse.

`ripple` is `(radius, alpha)`. The edge is feathered by one pixel of the radial
distance's own `fwidth`, exactly as the panel's outline is, so the circle is as
sharp as the display is at any size.

### `Layout3d.localPointFrom`

The change of frame, generalized off an alignment:

```dart
final origin = panel.localPointFrom(event.entry.layout, event.localPosition);
```

It is a new method on the **existing** `Layout3dAnchoring` extension, over the
**existing** `worldTransform` round trip, and `anchorOffsetTo` is now written
in terms of it. So there is one piece of arithmetic in this package for "where
is that point, over here", with two ways in, rather than a third mechanism
that could disagree with the other two.

## The work

- [x] `Ripple3d` in `decoration.dart`, with `radiusCovering` and a `lerp` that
      grows a missing end out of its own centre rather than sliding it in from
      the origin corner.
- [x] `StateLayer3d.ripple`, folded into `==`, `hashCode`, `isNone`, `lerp`,
      `copyWith` and `toString`.
- [x] `ripple_origin` and `ripple` in `assets/box_decoration3d.fmat`, with the
      `smoothstep` and the note about which frame the origin arrives in.
- [x] `BoxDecoration3dUniforms.rippleOrigin`, `.rippleRadius`, `.rippleOpacity`,
      written by `applyTo` and resolved by `resolve` — with the state layer's
      own alpha folded into the ripple's exactly as it is into the wash's.
- [x] `Layout3d.localPointFrom`, and `anchorOffsetTo` rewritten over it.
- [x] Exports, dartdoc, `docs/traps.md`, and the package README's decoration
      section.
- [x] Tests: the covering radius from the middle, from a corner and from
      outside the box; the depth of the pressed point being ignored; the lerp;
      a ripple alone not counting as `StateLayer3d.none`; the uniforms copying
      world units across untouched under a metrics whose rate is not one; the
      shader declaring both parameters and no ripple colour; and
      `localPointFrom` agreeing with `anchorOffsetTo` on the point they share.

**944 tests** in this package, up from 932. `dart analyze` clean.

## What the original reasoning got wrong

**"Two shader parameters" was right, and the uniform block was the part that
needed checking.** `.fmat` takes a `vec2` and `MaterialParameters.setVec2`
writes one; the std140 offsets come from the compiled shader's own reflection,
so nothing here computes padding. That was the one thing that could have
forced the design to a `vec4` and it did not.

**The ripple wanted the *state layer's* colour, and that was not the first
plan.** The obvious shape is a fourth colour parameter, and it is wrong twice
over: it is a uniform that can disagree with the wash beside it, and it is a
whole `vec4` for a value that is already in the block. What made it clearly
right is that `MaterialParameters.setColor` does **not** premultiply, so
`state_layer.rgb` survives its own alpha going to zero — which is exactly the
state a press-with-no-other-state produces, and it means the ripple can borrow
a colour from a wash that is drawing nothing.

**A point is not an alignment, and `anchorOffsetTo` could not be reused as it
stood.** The brief for this work said to use what exists rather than invent a
third way, and the honest reading of that turned out to be neither "call
`anchorOffsetTo`" nor "write a second matrix round trip in the catalogue": it
was to extract the round trip that was already inside `anchorOffsetTo` and give
it a name. `anchorOffsetTo` lost four lines in the process.

**`Offset3d` carries a depth the ripple throws away, and that is the right
trade.** A hit test's local position is three-dimensional; a ripple is a circle
on a face. Taking an `Offset3d` and documenting that `z` is ignored means a
caller passes `event.localPosition` straight through with no destructuring, and
`radiusCovering` measures on the face for the same reason. A two-component type
would have been more honest about the maths and worse at the call site, which
is every call site.

## What this plan deliberately left out

- **More than one ripple per box.** One box carries one pair of uniforms, so it
  carries one ripple; a second press replaces the first. Material draws
  overlapping splashes. Doing that here means an array of ripples in the
  uniform block and a loop in the fragment shader, which is a real cost on
  every panel in a tree for a case a reader sees when they drum their fingers
  on a button.
- **A ripple that is not a circle.** M3's bounded ripple on a rounded container
  is clipped to the container's shape; here it is clipped to the panel's own
  signed distance field for free, because the fragment is discarded outside it
  before the ripple is ever evaluated. An *unbounded* ripple — the one that
  escapes a small icon button's box — is not expressible and is not attempted:
  it is ink outside the box, and there is no box outside the box.
- **Interpolating a ripple's origin.** `Ripple3d.lerp` moves it, because a
  `lerp` that refused to would be a surprise, but nothing in the catalogue
  animates a decoration across a press. The interesting animation is the run,
  and the run lives in `flutter_scene_material3d`.
