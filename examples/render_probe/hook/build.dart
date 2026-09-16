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
/// `assets/opacity_poc/` is not either, and is a different case again: those
/// four are **generated copies** of the package's two shaders, each patched in
/// one place, and they exist to let the opacity experiment compare ways of
/// fading a subtree without editing anything the package ships. They are this
/// app's own assets, so they are compiled here. See
/// `tool/make_opacity_variants.dart`, which writes them, and
/// `lib/opacity_poc.dart`, which installs them.
void main(List<String> args) {
  build(args, (input, output) async {
    await buildEngineAssets(buildInput: input, buildOutput: output);
    await buildMaterials(
      buildInput: input,
      buildOutput: output,
      materials: [
        'assets/opacity_poc/panel_dither.fmat',
        'assets/opacity_poc/panel_bayer.fmat',
        'assets/opacity_poc/panel_nodepth.fmat',
        'assets/opacity_poc/glyph_dither.fmat',
        'assets/opacity_poc/glyph_bayer.fmat',
        'assets/opacity_poc/glyph_nodepth.fmat',
      ],
    );
  });
}
