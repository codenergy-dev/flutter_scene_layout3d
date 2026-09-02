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

The last four scenes belong to `flutter_scene_material3d` rather than to the
layout protocol, and they are here because there is nowhere else they could
be: what they check needs a GPU.

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

`installPanelPainter` here is `initializeMaterial3d()` — the call a Material
application makes — which is the only verification lane it has, since loading
a compiled `.fmat` needs a GPU context that `flutter test` does not have. It
also gives every decorated box a material of its own, which is what lets
`material_elevation` show three different colours at once instead of three
copies of whichever panel painted last.
