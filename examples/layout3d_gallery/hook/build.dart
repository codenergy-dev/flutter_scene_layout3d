import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

/// Builds the engine's shaders for this app.
///
/// [buildEngineAssets] is what makes `Scene.initializeStaticResources()`
/// resolve, and `initializeMaterial3d()` awaits that before it loads the
/// panel shader. Without this hook the engine prints "Flutter Scene is not
/// ready to render. Skipping frame" forever and the window stays empty — this
/// app had no hook at all until the gallery was given something to draw, and
/// that is exactly what it looked like.
///
/// The panel shader itself is *not* built here. `flutter_scene_layout3d`
/// compiles `assets/box_decoration3d.fmat` from its own `hook/build.dart`, so
/// an application inherits it the way it inherits any other build output of a
/// dependency.
void main(List<String> args) {
  build(args, (input, output) async {
    await buildEngineAssets(buildInput: input, buildOutput: output);
  });
}
