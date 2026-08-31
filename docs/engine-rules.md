# Using flutter_scene correctly

`flutter_scene` is the engine this package draws through, and it diverges from
three.js, Godot and Unity in specific ways. Most first-attempt failures come
from reaching for another engine's spelling. Everything below is either a build
failure or a silently wrong result.

This repository is a **consumer** of the engine, not a fork of it. Work here
never edits it; if something is genuinely missing, the answer is to work around
it on this side or open an issue upstream — and to write down which.

## Do not reach for these

- **Not `package:vector_math/vector_math_64.dart`.** Use
  `package:vector_math/vector_math.dart`. The `_64` `Vector3` is a different,
  incompatible type, and the error you get points nowhere near the import.
- **Not `--enable-impeller`, not `--enable-experiment=native-assets`.** The run
  flag is `--enable-flutter-gpu` alone. The native-assets experiment breaks the
  build on Dart 3.10+.
- **Not the master channel.** Flutter 3.47 stable or newer. Master resolves
  worse, not better.
- **Not `node.position.set(...)`.** `Node` has `position`, `rotation` (a
  `Quaternion`) and `scale`, but they are whole-value get/set — the getters
  return *copies*, so mutating one changes nothing:

  ```dart
  node.position = Vector3(0, 1, 0);              // yes
  node.mutateLocalTransform((m) => ...);         // for a raw matrix edit
  ```

- **Not `Node.fromAsset(...)` or `loadModel(...)`.** Load a preprocessed model
  with `loadScene('assets/x.glb')`, which returns a `Future<Node>`, or a
  runtime glTF with `Node.fromGlbAsset` / `Node.fromGlbBytes`.
- **Not a hand-rolled `CustomPainter` and `Ticker`.** A scene is displayed with
  the `SceneView` widget.

## Nothing renders until the engine says so

Rendering is gated on `Scene.initializeStaticResources()`. Until it resolves,
the engine prints *"Flutter Scene is not ready to render. Skipping frame"* and
you see an empty view.

Build geometry and materials only after it resolves — their constructors touch
the shader bundle. In a test that captures a frame, the order that works is:
pump one ordinary Flutter frame first (some backends race GPU context setup
otherwise), then await the engine, then build the scene, then settle for
several frames rather than one.

## The engine has more than you expect

Before hand-rolling any of these, know they exist: directional, point, spot and
area lights, shadows, ambient occlusion, screen-space reflections, depth of
field, fog, auto exposure, colour grading, bloom, anti-aliasing, tone mapping,
instancing and LOD, plus ten built-in primitive geometries and a
`GeometryBuilder` for custom meshes.

Custom `ShaderMaterial` output is **linear HDR premultiplied by alpha**; the
engine applies exposure, tone mapping and the display transform afterward.

## Compiling a `.fmat`

A custom material is compiled by a **build hook**, which is why a package
cannot compile one from inside a dependency — the app that uses it must.
`examples/render_probe/hook/build.dart` is the worked example: it calls
`buildEngineAssets` (which is what makes `initializeStaticResources` resolve)
and then `buildMaterials` over the shader this package ships.

## Going deeper

The engine ships agent skills covering correct usage, a verification loop,
lighting presets, procedural content and performance. Install them into a
checkout with:

```sh
dart run flutter_scene:skills
```
