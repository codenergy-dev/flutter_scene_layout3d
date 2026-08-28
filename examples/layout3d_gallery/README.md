# layout3d_gallery

Three layout surfaces in one scene, all live at the same time:

- **Left**, an upright panel driven imperatively, turning on its axis — a
  laid-out tree follows the plane node it hangs from, and the layout does not
  re-run to make that happen.
- **Middle**, the same protocol on the ground plane, where the basis makes
  layout's "down" run away from the camera.
- **Right**, a scrolling list described declaratively with the widget layer.

All three are hit-testable: the pointer becomes a camera ray and walks down the
layout tree, so hovering names what is under the cursor and dragging the list
scrolls it — even while the panel beside it is turning.

This app commits no platform scaffolding, so generate the platform you want
before running it:

```sh
flutter create . --platforms=macos
flutter run -d macos --enable-flutter-gpu
```

`--enable-flutter-gpu` is required. `--enable-impeller` is not the flag, and
the native-assets experiment breaks the build.
