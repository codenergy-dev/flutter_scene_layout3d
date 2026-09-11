# render_probe

Render tests for `flutter_scene_layout3d` and `flutter_scene_material3d`. Both
packages' own suites are all arithmetic — they prove the protocol arranges
correctly and prove nothing about whether a frame comes out. This is the other
half.

```sh
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/render_test.dart \
  -d macos --enable-flutter-gpu
```

Unlike the gallery, this app commits its macOS scaffolding, so it runs straight
from a checkout. `flutter run -d macos --enable-flutter-gpu` opens a browser for
the same scenes by hand, which is much the fastest way to understand a failure.

## What makes these different from a smoke test

A smoke test asks a frame one question: did something sane draw? That floor is
here too — corners clear, coverage in range, geometry not black.

But a layout package can ask something sharper, because **it knows where every
box ended up**. `Layout3d.screenCenter` projects a laid-out box to a pixel, so
an assertion reads:

```dart
expect(frame.coverageAt(capture.centerOf('left'), radius: 10), greaterThan(0.8));
```

Nothing there is a hard-coded coordinate. The layout tree is the oracle: the
test asks layout where the cube should be and checks the frame agrees. That
catches the one class of bug no unit test can see — the arithmetic is right and
the picture is still wrong — and it does it without a golden image, so it does
not break when a driver changes.

`FrameProbe` never reads a single pixel's value. Anti-aliasing and perspective
mean a projected centre is approximate, so every question is a fraction over a
small disc or a mean over a region.

## Writing a scene

Add it to `kProbeScenes` in `lib/probe_scenes.dart`, naming the boxes the test
will ask about:

```dart
ProbeScene('row_of_cubes', () {
  final left = NodeBox3d(fit: BoxFit3d.contain, content: cube(), name: 'left');
  return ProbeSceneContent(
    surfaces: [Layout3dSurface(child: Row3d(children: [left, ...]))],
    probes: {'left': left},
  );
}),
```

A scene that is a **control** says so with `minCoverage: 0`, and the floor
test flips its question: it must draw nothing at all. That is what makes its
partner's coverage mean something — "there are pixels where the label is" is
not evidence on its own, and "there are pixels here and none in the identical
scene without a renderer" is. The text and decoration scenes are both built as
pairs for that reason, and `plain_panel` is the control for three of them at
once: elevation, the border and the state layer are each "this capture differs
from the identical one without the feature". A scene that legitimately covers
less of the frame than the default floor — five letters of type, rather than a
wall of cubes — states its own `minCoverage` instead.

One more rule for a pair that compares *colours*: assert a direction, not a
distance. "The rim is a different colour from the middle" is just as true when
the two are swapped, which is how the panel shader shipped with its border
drawn inside out. Ask which colour is where, by something lighting and tone
mapping cannot reorder — a channel order, a luminance.

Two rules that are not obvious:

- **Use `BoxFit3d.contain`, not the default `BoxFit3d.none`.** With `none` the
  content keeps its own size inside whatever slot layout gave it, so a box's
  screen bounds enclose empty space and a probe aimed at the box's edge finds
  nothing. `contain` makes box extent and geometry extent the same thing, which
  is the premise the harness rests on.
- **Primitives only, generated in code.** A scene that loads an asset is a
  scene that can fail for a reason that has nothing to do with layout.

### A scene that needs a light

Everything here draws under the engine's default environment on purpose: a
probe that depends on a lighting rig is a probe that fails when the rig
changes. The exception is a scene asking what something *casts*, and
`ProbeScene.configureScene` is the hook for it — it is handed the `Scene`
before any surface is added:

```dart
configureScene: (scene) {
  scene.directionalLight = DirectionalLight(
    direction: Vector3(0.0, -1.0, 0.22),
    castsShadow: true,
  );
},
```

`castsShadow` is false by default, which is the first thing to check when a
shadow scene reads as "nothing casts anything". `panel_shadow` is the one
scene that uses this, and what it demonstrates is a defect rather than a
feature: a `BoxDecoration3d` panel casts no shadow at all, because the panel
shader blends its own anti-aliased outline and `flutter_scene` keeps
non-opaque materials out of the shadow pass. It draws an opaque cube beside
the panel as the control — without it, "the ground is not darkened" would be
satisfied by a scene with no shadows in it.

### A scene that is mid-interaction

Two of them are: `drag_feedback_depth` and `drag_feedback_detached` hold a
`Draggable3d` in flight while the frame is captured, because what a drag looks
like is the one part of it no arithmetic can check. A scene does that by
building its surface, flushing it, and driving a real `Layout3dPointer` — see
`_dragAcross` — all inside `build()`, so what the harness receives is a static
scene that happens to have a live drag in it.

The step that is easy to leave out is the flush *in the middle*. An overlay
entry has no size on the frame it is inserted, so `Draggable3d` cannot yet work
out where the feedback has to sit to cover the card it came from; the press and
the first move insert it, a flush gives it a size, and only the second move
writes the node offset a probe is there to look at.

A probe aimed at feedback can use `centerOf` and get the carried position, and
the reason is worth knowing before you assume otherwise. `worldTransform`
undoes a box's **own** `nodeOffset` — that channel exists to move geometry
without moving the box layout arranged — but an *ancestor's* stays in
`globalTransform` and therefore in the projection. `Draggable3d` writes the
offset onto the `IgnorePointer3d` it wraps the feedback subtree in, which is
above anything a caller can name, so `centerOf('feedback')` follows the drag.

Reconstructing the drawn point by hand from `box.nodeOffset` is the trap: on a
probed feedback box that is always zero, so the "drawn" point comes out equal
to the laid-out one and an assertion built on the difference compares a number
with itself. An earlier version of the detached scene did exactly that and
failed with a distance of 0.0.

## The catalogue scenes

A growing share of the scenes belong to `flutter_scene_material3d` rather than
to the layout protocol, and they are here because there is nowhere else they
could be: what they check needs a GPU.

`material_elevation` and `material_hover` build their panels through
`Material3d.decorationFor`, which is the single place a token becomes a
`BoxDecoration3d` — a probe that resolved the tokens itself would be checking
its own arithmetic. Both use the **light** theme, and not for looks: this
harness decides what is geometry by distance from its clear colour of
`#101820`, and Material 3's dark surface is `#141218`, inside that tolerance.
A dark panel reads as background and the scene looks like it never drew. So
the direction asserted is *higher elevation is darker* — a purple primary
tinting a near-white surface — and a hover darkens rather than lightens. Same
claim, opposite sign.

`icon_glyph` and its control settled the question the whole `Icon3d` design
hung on: does the label atlas rasterize an icon-font glyph? It does, so an
icon is one quad and a screen of icons and labels is one texture.

`card_in_clipped_list` and `divider_rule` belong to the catalogue's surfaces
and rows, and the first of them is the reason this lane exists. It draws a
raised card scrolled half out of a clipping window, and asks the frame three
things at once: the card drew, the half outside the window is gone, and what
is there instead is the backing rather than nothing. **It failed on its first
run**, with the card reading the same colour above and below the window's
edge — which is how it was discovered that the clip contract's *plane* tier
had never fired anywhere, in any scene, since it was written. Nothing but a
frame could have said so: `Layout3d.clipRegion` reports the right planes to
anything that asks after layout, and the block the shader actually gets was
the unbounded one every box is born with.

`divider_rule` is the smallest thing this catalogue draws. A 1dp rule is 0.01
world units at the default rate, so the scene turns the *surface's*
`unitsPerLogicalPixel` up to 0.06 rather than fattening a published token —
the same answer `button_outlined` gives, applied to a component that is
nothing but a line. The direction asserted is a luminance: `outlineVariant` is
a mid grey and the card under it is near white, so the rule is darker than
what it divides, and a scene where the two were swapped fails.

`checkbox_mark`, `switch_thumb` and `slider_drag` are the selection controls,
and each one asks something the arithmetic cannot. The first draws two
identical `primary` boxes, one with a rendered checkmark and one whose glyph
has no renderer, and asks which is lighter in the middle — `icon_glyph`'s
pairing at 18dp instead of 220dp, because the size was the part in doubt. It
turns up something worth knowing before you write another glyph scene: raising
the surface's `unitsPerLogicalPixel` to make a small component probeable
magnifies the drawn quad and leaves the **rasterization alone**, because the
atlas scale is `AtlasText3dRenderer.resolution` and the two metrics factors in
front of it cancel. So that dial is a magnifying glass over the real raster
rather than a bigger checkbox.

The other two are about the node tier, and both inherit the rule
`menu_at_its_button` established: `worldTransform` undoes `nodeOffset`, so
`screenCenter` on a moved thumb reports where *layout* put it. The oracle has
to be a box that did not move — a switch's track, a slider's body — and every
reading in both scenes is taken as a fraction along one of those.
`switch_thumb` draws an on switch and an off one and asserts the thumb ends up
at opposite ends, by two directions with **opposite signs**: on, the thumb is
`onPrimary` on a `primary` track and reads lighter; off, it is `outline` on a
near-white track and reads darker. `slider_drag` is mid-interaction, like the
drag scenes: it drives a real `Layout3dPointer` through the component's own
`SliderGesture3d` three quarters of the way across, then asks whether the
active track stops where the thumb is.

`switch_thumb` is also where the *"a difference is not a direction"* rule below
earned a corollary. Its first version asserted that the thumb was lighter than
the track by more than 0.2 — which reads like a direction and is a magnitude
nobody can justify — and it failed by a thousandth on a frame that was
perfectly correct. The assertion that survived is a **channel order**: a
`primary` track reads with blue above red, a near-white thumb reads neutral, so
"the thumb carries less of the track's purple than the track does" compares two
quantities of the same kind and has no threshold in it.

The four `ripple_*` scenes are the press ripple, and they are the first family
here that is *one* scene sampled at several moments. They build the same panel,
put the same `InkRipple3dRun` on it — the same object the ink controller drives
from a `Ticker` — and ask it what the ripple looks like at 0, 75, 110 and 260
milliseconds. The test then samples a grid of twenty-four points on the panel
in each capture and counts how many are darker than *that same point* in the
capture with no press on it, which is what makes "lit" a comparison rather than
a threshold. What is asserted is the order of three such counts: 15, then 21,
then all 24.

The scene is where the work went, not the assertion. The first version put its
three moments at 90, 160 and 260ms and the second one already covered the whole
grid, because `Curves.ease` is 95% of the way home two thirds of the way
through — so the "order" it asserted was between two numbers that were both the
maximum. The moments and the grid have to be chosen *together*, so that the
counts separate and every reading sits several pixels clear of the circle's
rim. That is the same lesson `switch_thumb` taught from the other side: the
assertion carries no magnitude, and the *scene* is what has to make the question
a fair one.

`transparent_slab` and `two_surfaces_of_type` are the two newest, and both are
scenes whose *arrangement* is the work rather than whose assertion is. Each
closes a defect that a person found by running the gallery, and in each case
the obvious scene passes whether the bug is there or not.

`transparent_slab` asks whether a `Material3d` with no colour in it erases what
it is standing on. The panel shader writes depth, so a fragment with no alpha
used to occlude everything drawn after it — but a blended draw only erases what
comes *after* it, and the translucent pass sorts back to front by the
world-space centre of each draw's bounds. A transparent slab standing plainly
in front of a panel is therefore drawn second and hides nothing. What
reproduces the defect is the arrangement the component actually makes, measured
off a photographed navigation bar: a destination's surface is a **child** of
the bar's, `Material3d` hands its child a tight depth, and the two come out
co-centred, so their sort keys tie. The assertion is coverage, which carries
neither a colour nor a magnitude — a hole is clear pixels and nothing else in
the scene looks like one.

`two_surfaces_of_type` is the first scene here to draw **two** lots of type,
which is what every other text scene could not do and what a gallery found in
its first frame. Two surfaces with two-letter labels share one atlas; the first
starts a rasterization and the second reserves its letters while that is in
flight. Its atlas is built with `initialSize` equal to `maxSize`, and that is
load-bearing: an atlas that can grow *repacks*, a repack is the one thing that
used to be noticed, and the bug is invisible in any scene where one happens.
The assertion asks for ink in each half of each label's own screen bounds — a
disc at the centre of a two-letter label lands in the gap between the letters,
which was the first version and it failed on a correct frame.

`slab_occludes_its_inside` and `type_on_a_turning_panel` are the newest pair,
and they belong together: they are the two halves of what it takes to draw a
letter on a panel, and each one fails on its own arrangement rather than on a
sharp reading.

`slab_occludes_its_inside` puts one label on a slab's front face and one a
third of the way into it, and asks for ink at the first and none at the second.
The claim is a *difference* on purpose — no exposure, tone-mapping or lighting
change can satisfy "here and not there" by accident — and it is the only thing
in this repository that would have noticed that the panel's slab was wound
inside out. Both labels drew before that was fixed, because the slab's
back-face culling kept the face pointing *away* from the camera and the panel
wrote the depth of its own rear.

`type_on_a_turning_panel` is the first scene here to **turn a surface**. Three
labels on a card-thin slab — one at each edge, one in the middle — on a plane
yawed a quarter of a radian. The middle one is the control: it sits at the
panel's own sort depth whatever the plane does. Both edges are asked, because
which edge swings away from the camera depends on the sign of the turn and on
whether the surface's basis is a mirror, and naming only the near one would
pass while the defect stood. The slab's thickness is load-bearing in the other
direction from `two_surfaces_of_type`'s atlas size: what keeps a label in front
of the panel it is written on is *half the panel's thickness*, so a thick slab
hides the defect and a 4dp card is where it lives.

`installPanelPainter` here is `initializeMaterial3d()` — the call a Material
application makes — which is the only verification lane it has, since loading
a compiled `.fmat` needs a GPU context that `flutter test` does not have. It
also gives every decorated box a material of its own, which is what lets
`material_elevation` show three different colours at once instead of three
copies of whichever panel painted last, and it installs the glyph material,
without which `type_on_a_turning_panel` fails by design.
