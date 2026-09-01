import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

/// Compiles this package's own panel shader, for whatever app depends on it.
///
/// `assets/box_decoration3d.fmat` is the signed-distance-field shader behind
/// every `BoxDecoration3d`, and until this hook existed the only thing that
/// ran `impellerc` over it was `examples/render_probe`'s own hook, through a
/// symlink — so an application that added this package got panels that drew
/// nothing and no error saying why.
///
/// A package's `hook/build.dart` runs when the package is a dependency, not
/// only when it is the root, and `buildMaterials` resolves its paths against
/// *this* package's root. The outputs land in this package's own
/// `flutter_scene_generated/` directory, which its pubspec lists under
/// `flutter: assets:`, so they reach the app bundle keyed
/// `packages/flutter_scene_layout3d/...` and `loadFmatMaterial` resolves them
/// by source path. It is the same arrangement `flutter_scene` uses for the
/// engine's own shaders.
///
/// **`buildEngineAssets` is deliberately not called here.** That is what makes
/// `Scene.initializeStaticResources()` resolve, it belongs to the application
/// (or to `flutter_scene`'s own hook), and calling it from a second package
/// would put two copies of the engine's shaders in one bundle.
void main(List<String> args) {
  build(args, (input, output) async {
    await buildMaterials(
      buildInput: input,
      buildOutput: output,
      materials: ['assets/box_decoration3d.fmat'],
    );
  });
}
