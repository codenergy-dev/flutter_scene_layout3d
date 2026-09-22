---
status: completed
created_at: 2026-09-15T19:50:41Z
updated_at: 2026-09-21T16:25:00Z
commit: af086f9de841081071e99089ea8b0d91e220ccf9
---

# A row that reads right to left

The fourth plan off
[what a real application still needs](2026_09_11_what_a_real_application_still_needs.md),
and the first of the four that map says the first real port will demand. No
port has yet said which of the four it wants first, so this one is taken first
because it is the one another item waits on:
[a catalogue that speaks more than one language](2026_09_11_what_a_real_application_still_needs.md#a-catalogue-that-speaks-more-than-one-language)
cannot do its arrangement half without it.

## What is actually missing

**Reading direction reaches the text and stops there.** `Text3d` and
`RichText3d` take a `TextDirection`, and their widget forms read the ambient
`Directionality`. Nothing else in the layout package knows a direction exists:

- `Flex3d` has no `textDirection` and no `verticalDirection`, so a `Row3d`
  arranges left to right around text running right to left, and there is no
  reversed `Column3d`.
- `Wrap3d` has neither either.
- There is no `EdgeInsetsDirectional3d`, so a padding cannot say *start*, and
  no `AlignmentDirectional3d`, so an alignment cannot say it either. Every box
  that takes one — `Padding3d`, `Align3d`, `Container3d`, `Stack3d`,
  `FittedBox3d`, the overflow boxes, `Transform3d`, `NodeBox3d`,
  `SliverPadding3d` — takes the physical kind only.
- `Positioned3d` has no `directional` form.
- `Table3d` puts its first column on the left whatever the language.

The consequence in Arabic or Hebrew is not a missing feature but **a divergence
from Flutter's own contract**, which is the strongest kind of gap for a package
whose promise is that the protocol is the one people already know.

## What Flutter does, checked against the SDK this repository resolves

Flutter 3.47.1, read in the framework source.

- **`RenderFlex` flips by visiting children in visual order.** `_flipMainAxis`
  is `textDirection == rtl` for a horizontal flex and `verticalDirection == up`
  for a vertical one; `_flipCrossAxis` is the other one. When the main axis
  flips, the children are walked last to first from the top-left, and
  `MainAxisAlignment.start` puts the free space *before* them. So an
  overflowing right-to-left row keeps its **last** child at the left edge and
  pushes the first child out past the right — not a mirror image of the
  left-to-right overflow. `CrossAxisAlignment.start` flipped is `freeSpace`;
  baseline alignment ignores the cross flip.
- **A null `textDirection` asserts** in `RenderFlex` whenever the order or a
  `start`/`end` needs it, and `AlignmentDirectional.resolve(null)` asserts.
  The `Flex` widget fills it from `Directionality.maybeOf(context)`.
- **`RenderWrap` flips the same way, run by run.** Within a run it walks
  children in visual order with the flipped distribution; across runs it walks
  the runs in reverse when the cross axis flips and swaps `start` and `end` of
  the cross alignment.
- **`EdgeInsetsGeometry` and `AlignmentGeometry`** are the base types every
  render box takes; `EdgeInsets`/`EdgeInsetsDirectional` and
  `Alignment`/`AlignmentDirectional` are the concrete kinds, a private mixed
  kind carries the sum of the two, and `resolve(TextDirection?)` turns any of
  them into the physical one at layout time.
- **`Positioned.directional`** is a factory that resolves `start`/`end` into
  `left`/`right` against a direction it is handed.
- **`RenderTable` takes a `textDirection`** and, in right to left, puts the
  first column at the right.

## The decisions

### Direction belongs to the layout, not to the view

The design question the map asked: what does `start` mean on a plane the viewer
can walk behind? **The same thing it means from the front.** A row in Arabic
has its first child on the right of the plane's front face, and a person who
walks round to the back sees that child on their left — exactly as they would
see the first word of a sign printed on glass. Nothing re-lays out when the
camera moves, and nothing could: which side a viewer is on is a property of
the frame, while layout is computed once for everyone looking at it.

This is the position
[the wheel plan](2026_09_15_a_wheel_a_trackpad_and_a_key_that_reach_a_box.md)
took first for scrolling, and it is taken here for the same reason. It is also
the only answer consistent with the text: a glyph run is laid out on the plane,
and a row whose arrangement followed the viewer while its words did not would
disagree with itself.

### Flutter's types, with a `3d` suffix, and Flutter's rules

`EdgeInsetsGeometry3d` and `AlignmentGeometry3d` become the types the boxes
take. `EdgeInsets3d` and `Alignment3d` extend them unchanged, so every existing
constructor call still compiles. `EdgeInsetsDirectional3d` and
`AlignmentDirectional3d` are new; a private mixed kind holds the sum, and
`resolve(TextDirection?)` is where a direction becomes a side.

**Depth has no direction.** Front is where the viewer is, whatever language the
text is in, so `EdgeInsetsDirectional3d` has `front` and `back` and
`AlignmentDirectional3d` has a `z`, both physical — the same asymmetry
[the depth axis](../../../docs/traps.md) already has everywhere else.

### A missing direction is left to right, not an assertion

**The one deliberate divergence.** Flutter asserts when a direction is needed
and null; here, null resolves as left to right on the imperative layer. Every
layout in this package has been written with no direction since the first
commit, and an assertion would stand in front of every multi-child row the
suites and the catalogue build, to say something nobody was wrong about. It is also what this package already does
for text: `Text3d` falls back to left to right when there is no
`Directionality`, because a scene is not always under a `WidgetsApp`.

The widget layer is where Flutter's ambient behaviour lives, and it is kept:
`SceneRow3d`, `ScenePadding3d` and every other widget form read
`Directionality.maybeOf(context)` when no direction is stated. **So an
application under a right-to-left `Directionality` mirrors without writing a
line** — which is the point, and which reaches the catalogue too; see below.

### `Flex3d` and `Wrap3d` are ported, flip for flip

`textDirection` flips whichever axis of the line is horizontal — the main axis
of a `Row3d`, the first cross axis of a `Column3d` or a `Depth3d` — and
`verticalDirection` whichever is vertical. The depth axis never flips. The
placement is Flutter's visual-order walk, overflow behaviour included, rather
than a mirror of the left-to-right result, so an overflowing row does what a
Flutter row does. Baseline alignment ignores the cross flip, as in Flutter.

### A box resolves at layout, and takes its direction as a property

Each box that takes a geometry gains a `textDirection` and resolves in
`performLayout` — or in `localTransform` for the two that pivot. A box with a
single geometry skips the relayout when only the direction changes and the
geometry is physical; `Container3d`, with four of them, and the lines, whose
order is the direction, always relayout.

### What stays physical

- **A surface's `origin`, an overlay entry's `alignment` and
  `Layout3d.anchorOffsetTo`.** These place a plane in a room, an entry on a
  screen and a menu against a node; they are about the frame, not the reading
  order of a line. The catalogue's `Follower3dWidget` resolves a directional
  corner into them, which is where a menu learns which side is the start.
- **A horizontal scroll view.** Flutter starts a horizontal `ListView` at the
  right in right to left, by reversing its axis direction. No view here has
  `reverse` at all, so that is an absence of its own rather than a direction
  to thread, and it is recorded on the map rather than taken here.
- **`BorderRadius3d`.** There is no `BorderRadiusDirectional3d`; a panel's
  corners are painted by the shader against physical corners, and nothing in
  the catalogue rounds one side only except the side sheet, whose edge is
  physical anyway.

### The catalogue, so that mirroring is not half done

The moment `SceneRow3d` reads the ambient direction, every row in the Material
catalogue mirrors under a right-to-left `Directionality`. Its asymmetric
paddings would not, and a list tile with its 16dp and 24dp on the wrong sides
is worse than one that does not mirror at all. So this plan also takes the
catalogue's physical sides that Flutter writes as directional, and the slider,
which [the wheel plan](2026_09_15_a_wheel_a_trackpad_and_a_key_that_reach_a_box.md#a-slider-on-the-arrow-keys)
explicitly left to this one: a track that runs from the right, and arrows that
follow it. Strings are not this plan's; they are the language plan's.

## The API

```dart
abstract class EdgeInsetsGeometry3d {        // EdgeInsets3d, EdgeInsetsDirectional3d, a private mixed kind
  EdgeInsets3d resolve(TextDirection? direction);
  EdgeInsetsGeometry3d add(EdgeInsetsGeometry3d other);
  static EdgeInsetsGeometry3d? lerp(a, b, t);
  // horizontal, vertical, depth, alongAxis, collapsedSize, isNonNegative…
}
class EdgeInsetsDirectional3d extends EdgeInsetsGeometry3d { start, top, end, bottom, front, back }

abstract class AlignmentGeometry3d {         // Alignment3d, AlignmentDirectional3d
  Alignment3d resolve(TextDirection? direction);
  AlignmentGeometry3d add(AlignmentGeometry3d other);
  static AlignmentGeometry3d? lerp(a, b, t);
}
class AlignmentDirectional3d extends AlignmentGeometry3d { start, y, z; topStart … }

Flex3d / Row3d / Column3d / Depth3d(textDirection:, verticalDirection:)
Wrap3d(textDirection:, verticalDirection:)
Table3d(textDirection:)
Padding3d, Align3d, Container3d, Stack3d, FittedBox3d, Transform3d, NodeBox3d,
  the overflow boxes, SliverPadding3d: geometry + textDirection
Positioned3d.directional(textDirection:, start:, end:, …)
EdgeInsetsGeometry3dTween, AlignmentGeometry3dTween
Layout3dMetrics.dpInsets<T extends EdgeInsetsGeometry3d>(T)

// Widgets read Directionality when textDirection is not stated.
SceneRow3d(textDirection:, verticalDirection:) … SceneWrap3d, SceneStack3d,
  SceneIndexedStack3d, SceneTable3d(textDirection:)
ScenePositionedDirectional3d(start:, end:, …)   // Flutter's PositionedDirectional

// The catalogue.
ListTile3d.defaultContentPadding: EdgeInsetsDirectional3d
Material3d.padding: EdgeInsetsGeometry3d, Material3d.alignment: AlignmentGeometry3d
Follower3dWidget(self:, target:): AlignmentGeometry3d, start corners by default
showMenu3d(menuCorner:, anchorCorner:): AlignmentGeometry3d
SliderGesture3d(textDirection:)
```

## The boundary

- **Not a horizontal scroll view that starts at the right** — see above.
- **Not strings.** The language plan owns every word the catalogue invents.
- **Not arrow-key focus traversal.** `DirectionalFocusIntent` is geometric in
  Flutter and here, and is unaffected by reading direction in both.

## The work

- [x] Geometry: the two base types, the directional and mixed kinds, `resolve`,
      `add`, `lerp`, and the geometry tweens.
- [x] `Flex3d` and its three lines, `Wrap3d`, `Table3d`.
- [x] The boxes that take a geometry, and `Positioned3d.directional`.
- [x] The widget forms, reading `Directionality`; the implicit animations over
      geometry tweens.
- [x] Tests: 48 in `test/reading_direction_test.dart` here — the geometry,
      each line and box in both directions, and the ambient direction reaching
      and following a widget — and 11 in the Material package's
      `right_to_left_test.dart`. The suites are 1131 and 545.
- [x] The catalogue: the list tile, the divider, the app bar and its centred
      toolbar, the slider, the switch, and the corner a menu hangs from.
- [x] Both package READMEs, `docs/traps.md` (a new *Reading direction*
      section), both changelogs, `docs/README.md`, `AGENTS.md`'s table and
      counts, and the map.

## Verification

`flutter test` in both packages and the gallery, `dart analyze` clean,
`dart format .`. The oracle is Flutter: each flip is tested against the
position Flutter's own render object gives the same children, worked by hand
from the SDK source above.

**Done**, on 2026-09-15, headless-verified only. The gallery has no
right-to-left screen and was not run for this plan; the render probes draw
nothing this plan changes the arithmetic of in left to right, and they were
not run either. A person looking at a right-to-left screen is still the
missing check — the first real port in Arabic or Hebrew is the natural one.

## What the reasoning got wrong

**The map called it a layout-package item, and the largest risk was in the
catalogue.** The mechanism is small and Flutter had already designed it. What
it did the moment it worked was move every row in the Material catalogue to
the right under a right-to-left `Directionality` — while the list tile's 16dp
and 24dp stayed where they were, the app bar's centred toolbar still put its
leading widget at `x = 0`, the slider's thumb still slid by
`travel * (value - 0.5)`, the switch was still on at the right and a menu
still hung from its button's left corner. A half-mirrored catalogue is worse
than one that does not mirror at all, so the catalogue pass was not a
follow-up but a condition of shipping the layout half. Anything positioned by
arithmetic rather than by a box is invisible to a direction, and that is now a
trap.

**"`Flex3d` has no direction, and there are no directional insets" was a third
of the list.** `Wrap3d` and `Table3d` had no direction either, twelve boxes
took only physical geometry, and `Positioned3d` had no directional form. The
map read the two classes a row is made of and stopped.

**The map counted `readingDirection3d` among the things that already handled
direction properly.** It handles the direction a component *announces* in —
the `textDirection` a catalogue component takes is for its semantics label,
and has nothing to do with its layout. That is also Flutter's split, and it is
now written down in the Material README and in the traps, because the name
suggests otherwise.

**The design question the map called "a good one" had already been answered.**
What `start` means behind a plane was decided by the wheel plan for scrolling,
for the same reason, and the only new work was saying it again for layout.

**One latent defect, in the catalogue's anchoring.** `Follower3d.self` and
`target` were `final`, and `Follower3dWidget`'s host did not update them on a
rebuild, so a follower rebuilt with different corners would silently have kept
the first ones. Nothing rebuilt one with different corners until a corner could
depend on the ambient direction.

**And one thing the map filed as a direction was an absence.** A horizontal
`ListView` in Flutter starts at the right in right to left, by reversing its
axis. No view here has `reverse` at all, so there was no direction to thread;
it is recorded on the map beside the carousel that will want it.

*Since found:* the floating action button was missed. `Scaffold3d` put it at
the right whatever the reading direction, where Flutter's `endFloat` is the
trailing corner; the rows, paddings and corners above were all covered, and
the button is a delegate's arithmetic rather than any of them. Phase 2 of
[the components a screen still needs](../../flutter_scene_material3d/plans/2026_09_21_the_components_a_screen_still_needs.md)
mirrored it while giving it a side for the trailing inset.
