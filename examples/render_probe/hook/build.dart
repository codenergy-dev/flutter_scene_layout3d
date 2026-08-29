import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

/// Builds the engine's shaders, and the layout package's panel shader.
///
/// [buildEngineAssets] is what makes `Scene.initializeStaticResources()`
/// resolve; without it the engine prints "not ready to render" forever and
/// every probe sees an empty frame.
///
/// [buildMaterials] is the first thing in either repository to run `impellerc`
/// over `box_decoration3d.fmat`. The package ships that shader and a unit test
/// checks that every parameter the Dart side writes is declared in it, which
/// catches a silent mismatch — but nothing until now has asked the compiler
/// whether it is even valid GLSL. `assets/box_decoration3d.fmat` is a symlink
/// to the package's own copy, so this compiles the shipped file rather than a
/// stale duplicate of it.
void main(List<String> args) {
  build(args, (input, output) async {
    await buildEngineAssets(buildInput: input, buildOutput: output);
    await buildMaterials(
      buildInput: input,
      buildOutput: output,
      materials: ['assets/box_decoration3d.fmat'],
    );
  });
}
