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

Input is a `Layout3dPointerGroup` rather than three separate pointers. A
pointer here is a ray, and a group is what decides which surface a ray reaches
first — z-order, then distance from the camera — so a press on the screen in
front does not also land on whatever is behind it. That question cannot be
answered by geometry alone once a panel is turned away from the viewer, which
is why the ordering is stated rather than derived.

There is a headless test, `test/screens_test.dart`, that builds both screens
and checks the arrangement. It draws nothing — that needs a GPU — but it is
what stops a refactor of the catalogue silently breaking the one app a person
runs. One of its cases is a regression rather than a check: it presses a
navigation destination with a ray, because every slot of every `Scaffold3d`
used to be unreachable by one.

## Looking at it when you cannot see the window

`screencapture` on macOS returns the desktop picture and nothing else unless
the terminal has been granted Screen Recording, which is a thing you cannot
give yourself from inside a shell. The way round it, and the way every finding
in this app's history was actually made, is to photograph the frame from
*inside*: a throwaway `integration_test` that pumps `Layout3dGallery` inside a
`RepaintBoundary`, settles for a hundred frames with real delays between them,
and writes `boundary.toImage()` to disk.

It is deliberately not committed, because adding `integration_test` makes this
a CocoaPods project and `flutter create` does not finish wiring one — which
would break the two commands at the top of this file. The recipe, with the
three things that cost time (an opaque backdrop *inside* the boundary, the app
sandbox making `/tmp` unwritable, and the `Pods-Runner` xcconfig include the
generated project is missing), is written down in
[a label that survives a repack](../../packages/flutter_scene_layout3d/plans/2026_09_10_a_label_that_survives_a_repack.md).
