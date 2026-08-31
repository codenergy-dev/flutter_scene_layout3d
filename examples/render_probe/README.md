# render_probe

Render tests for `flutter_scene_layout3d`. The package's own suite is all
arithmetic — it proves the protocol arranges correctly and proves nothing about
whether a frame comes out. This is the other half.

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
pairs for that reason. A scene that legitimately covers less of the frame than
the default floor — five letters of type, rather than a wall of cubes — states
its own `minCoverage` instead.

Two rules that are not obvious:

- **Use `BoxFit3d.contain`, not the default `BoxFit3d.none`.** With `none` the
  content keeps its own size inside whatever slot layout gave it, so a box's
  screen bounds enclose empty space and a probe aimed at the box's edge finds
  nothing. `contain` makes box extent and geometry extent the same thing, which
  is the premise the harness rests on.
- **Primitives only, generated in code.** A scene that loads an asset is a
  scene that can fail for a reason that has nothing to do with layout.
