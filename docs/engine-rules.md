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

A custom material is compiled by a **build hook**, and a package's own
`hook/build.dart` *does* run when that package is a dependency rather than the
root — which was worth establishing by experiment, because the engine's own
source still carries a TODO saying a third-party package generating assets for
its consumers "has no supported path yet". It works, and the runtime half was
built for it: `GeneratedAssetSource.isPackageOwned` exists to resolve a
`packages/<name>/flutter_scene_generated/` manifest.

The arrangement has three parts, and all three are needed:

- `hook/build.dart` calls `buildMaterials` with paths relative to **its own**
  package root.
- The package's `pubspec.yaml` lists `flutter_scene_generated/` under
  `flutter: assets:`, or the build fails naming the missing entry.
- The directory exists in the checkout with the engine's `.gitignore` inside
  it, so a fresh clone has the entry the pubspec promises.

`packages/flutter_scene_layout3d/hook/build.dart` is the worked example: it
compiles the panel shader this package ships, for every app that depends on
it. `flutter_scene` does the same for the engine's own shaders.

**`buildEngineAssets` is a separate question.** It is what makes
`Scene.initializeStaticResources()` resolve, and it belongs to the application
— `flutter_scene`'s own hook already builds those shaders into its own package
directory, so an app calls it only to have its own copy in its own bundle,
which a locked-down pub cache forces. A second *library* must never call it: a
package that did would put two copies of the engine's shaders in every app
that used it. `examples/render_probe/hook/build.dart` calls that and nothing
else; `packages/flutter_scene_layout3d/hook/build.dart` calls
`buildMaterials` and nothing else.

**A generated tree is not cleaned by removing the call that filled it.**
`flutter_scene_generated/` is persistent by design — it survives `flutter
clean` — and stale outputs are pruned only by the builder that wrote them, on
a run. Take a `buildMaterials` call out of an app's hook and its old bundle
stays behind, so the next load finds the same source path in two packages and
throws *"Multiple generated .fmat materials"*. Delete the contents of the
app's `flutter_scene_generated/` once, keeping the `.gitignore`.

## Going deeper

The engine ships agent skills covering correct usage, a verification loop,
lighting presets, procedural content and performance. Install them into a
checkout with:

```sh
dart run flutter_scene:skills
```
