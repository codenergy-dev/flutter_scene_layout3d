# layout3d_gallery

The example app. Three surfaces in one scene, all live at the same time and
all hit-testable:

- **Left**, a Material screen standing upright on a panel that turns. It is a
  `Scaffold3d` — an app bar, a body, a navigation bar and a floating action
  button — with filter chips over a scrolling list of cards on one tab and the
  selection controls on the other. Turning is the plane node's business, so
  the layout does not re-run to make it happen.

  (Left, because `flutter_scene` builds its view matrix as
  `right = up × forward`: a camera out on `+z` has a right vector of `-x`, so
  the surface at *positive* x is the one on your left. It costs a whole
  framing to discover, and it is in `docs/engine-rules.md` now.)
- **Middle**, the same catalogue lying flat on the ground. `LayoutBasis3d.xz`
  makes layout's "down" run away from the camera, and that is the whole
  difference: the widgets do not know. It is the case a 2D toolkit has no
  answer for, and the elevations on it are heights rather than shadows — tap a
  card and it rises off the table.
- **Right**, a scrolling list of real meshes, described declaratively. It is
  deliberately *not* Material: the same protocol arranges an application's own
  geometry, and having both in one frame is what says so.

Hovering names what is under the cursor — a Material component announces
itself through `Semantics3d`, so the readout says "Ada Lovelace" or "Compose"
rather than the name of a box — and pressing anything works: the switches
throw, the slider drags, the chips select, and the floating action button
raises a snack bar.

## Running it

This app commits no platform scaffolding, so generate the platform you want
before running it:

```sh
flutter create . --platforms=macos
flutter run -d macos --enable-flutter-gpu
```

`--enable-flutter-gpu` is required. `--enable-impeller` is not the flag, and
the native-assets experiment breaks the build.

One more flag, for the one defect this app is the only way to see:

```sh
flutter run -d macos --enable-flutter-gpu --dart-define=report_repacks=true
```

That turns on `debugReportGlyphAtlasRepacks`, which prints each glyph atlas
repack and the milliseconds its picture took to arrive — 700–850ms here, which
is not frames, it is a second of a person's attention. Between the two there
is a window in which a label that has to be baked again has no picture to draw
from, and **resizing the window is the worst case**. Not because the surfaces
resize: every one of them here is authored at a fixed size and a fixed unit
rate, so the 3D layout does not change at all. It is because a resize is a
storm of widget rebuilds, and this app's theme used to hand the tree a new
`textRendererFactory` closure on every one of them — which throws away and
rebuilds every label's renderer in the scene, and a renderer built this frame
has no mesh to keep and so cannot wait out a repack. The factory is
`_textRenderer`, a method, for that reason.

If letters come out wrong while a repack's window is open,
they are that; if they come out wrong with none open, they are something else,
and that is the more useful half of the answer. The background is *A mesh and
an atlas texture are a pair* in [docs/traps.md](../../docs/traps.md).

It is a `--dart-define` rather than a line to uncomment because no other lane
reaches this: `flutter drive` pumps frames slowly enough for the readback to
land between them, so the window never opens there, and a render probe that
asserted it would be asserting a race.

`flutter create` writes more than the platform directory — a `.metadata`, an
`analysis_options.yaml` the repository root already provides, a `.gitignore`,
and a `widget_test.dart` stub for a `MyApp` this app does not have. All of it
is listed in the repository's root `.gitignore`, so a `git add -A` after
generating a platform picks up source and nothing else.

## Two things without which nothing draws at all

The app owns both, and this is the shortest place to see them.

`hook/build.dart` calls `buildEngineAssets`, which is what makes
`Scene.initializeStaticResources()` resolve. Without it the engine prints
*"Flutter Scene is not ready to render. Skipping frame"* forever and the
window stays empty. It is an **application's** job — `flutter_scene_layout3d`
and `flutter_scene_material3d` deliberately do not do it for you, because a
library that called it would put a second copy of the engine's shaders in
every application that used it.

`main()` then calls `initializeMaterial3d()`, which awaits that and installs
the panel painter. `BoxDecoration3d.painterFactory` is null until something
sets it, so a themed component measures, lays out and shows *nothing*, with no
error anywhere. This app had neither of those until the gallery was given
something to draw, and it looked exactly like you would expect.

## What the code is arranged around

`lib/screens.dart` holds the two Material screens and nothing about the scene.
`lib/gallery.dart` mounts them: the surfaces, the camera, the pivot node the
upright screen turns on, and the input.

Input is one `SceneInput3d` around the `SceneView`, and that is the whole of
it: no listener, no `screenPointToRay`, no pointer group filled in from the
tick. Each surface states its own `zOrder` and announces itself when it
mounts. A pointer here is a ray, and what the host decides is which surface a
ray reaches first — z-order, then distance from the camera — so a press on the
screen in front does not also land on whatever is behind it. That question
cannot be answered by geometry alone once a panel is turned away from the
viewer, which is why the ordering is stated rather than derived. The upright
screen's snack bars are detached surfaces of their own and land a step in
front of it without the gallery saying anything.

The same host routes the wheel and a trackpad, so the mesh list scrolls under
either as well as under a drag. Keys need no wiring either: click a control and Tab,
the arrows, Enter and Space work on the Material screens. The gallery does not
pass `autofocus`, because a window that grabbed the keyboard before anyone
touched it would be a strange example to copy.

The gallery used to wire all of that by hand, and it is worth knowing what it
cost, because it is the argument for the widget: about ninety lines, three of
them with silent failure modes — a z-order in the wrong relative order routed
a press to the panel behind, a surface registered before it existed was
skipped forever, and a dialog never synced into the group could not be
pressed at all.

There is a headless test, `test/screens_test.dart`, that builds both screens
and checks the arrangement. It draws nothing — that needs a GPU — but it is
what stops a refactor of the catalogue silently breaking the one app a person
runs, and CI runs it. One of its cases is a regression rather than a check: it
presses a navigation destination through the camera, because every slot of
every `Scaffold3d` used to be unreachable by a press.

## Looking at it when you cannot see the window

`screencapture` on macOS returns the desktop picture and nothing else unless
the terminal has been granted Screen Recording, which is a thing you cannot
give yourself from inside a shell. The way round it, and the way every finding
in this app's history was actually made, is to photograph the frame from
*inside* the process.

That used to be a throwaway `integration_test` rebuilt from a recipe each time,
because adding `integration_test` here makes this a CocoaPods project and
`flutter create` does not finish wiring one. It is committed now, in
`examples/render_probe`, which already carries that wiring and depends on this
app to photograph it:

```sh
cd ../render_probe
flutter drive --driver=test_driver/photograph.dart \
  --target=integration_test/photograph_test.dart \
  -d macos --enable-flutter-gpu
```

Two PNGs land in `render_probe/build/photographs/`, a few seconds apart so the
turning panel is seen from two angles, and CI keeps them from every run. See
[its README](../render_probe/README.md#photographing-the-gallery).

## Testing a screen of your own

`test/screens_test.dart` is the worked example of
`package:flutter_scene_layout3d/testing.dart`: it pumps each screen, presses a
navigation destination through the camera with `tester.tap3d`, and asks every
label whether it is hidden inside the card it is written on with
`standsOnItsPanel3d`. Both of those are regressions for defects a person found
by looking at this window, and both fail when the defect is put back. The
layout package's README explains the library under *Testing a screen*.
