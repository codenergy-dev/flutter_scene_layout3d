import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

/// Builds the engine's own shaders into this app's generated tree.
///
/// [buildEngineAssets] is what makes `Scene.initializeStaticResources()`
/// resolve; without it the engine prints "not ready to render" forever and
/// every probe sees an empty frame.
void main(List<String> args) {
  build(args, (input, output) async {
    await buildEngineAssets(buildInput: input, buildOutput: output);
  });
}
