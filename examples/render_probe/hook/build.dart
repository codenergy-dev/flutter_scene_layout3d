import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

/// Builds the engine's shaders for this app.
///
/// [buildEngineAssets] is what makes `Scene.initializeStaticResources()`
/// resolve; without it the engine prints "not ready to render" forever and
/// every probe sees an empty frame. It is an application's job, and it stays
/// here.
///
/// The panel shader is not. `flutter_scene_layout3d` compiles
/// `assets/box_decoration3d.fmat` from its own `hook/build.dart` now, so this
/// app inherits it the way it inherits any other dependency's build output,
/// and the symlink this hook used to reach through is gone.
/// Neither is the glyph shader or the one a glyph's wall is drawn with, for
/// the same reason. **This app compiles no shaders of its own**, which is
/// worth saying because it briefly did: the opacity experiment shipped six
/// generated variants of the package's shaders here, and they went when the
/// approach they were comparing was chosen and shipped. See
/// `README.md`'s *What the opacity experiment settled*.
void main(List<String> args) {
  build(args, (input, output) async {
    await buildEngineAssets(buildInput: input, buildOutput: output);
  });
}
