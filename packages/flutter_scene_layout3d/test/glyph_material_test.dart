// The seam a label's material comes through.
//
// Almost everything about `GlyphMaterial3d` needs a GPU — building an engine
// material, binding an atlas, drawing a letter — and lives in
// `examples/render_probe` (`type_on_a_turning_panel`). What is checkable here
// is the part an application actually touches: which factory is in force, and
// that installing the compiled material does not overwrite a factory someone
// chose deliberately.

import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in that never builds an engine material, so the parts of the seam
/// that are arithmetic can be checked without a shader bundle.
class _NeverBuilt implements GlyphMaterial3d {
  @override
  Never get material => throw UnimplementedError();

  @override
  void bindAtlas(Object? atlas) {}

  @override
  void tint(Object color) {}
}

void main() {
  test(
    'a label draws with the unlit fallback until something installs one',
    () {
      expect(GlyphMaterial3d.factory, same(UnlitGlyphMaterial3d.new));
    },
  );

  test(
    'installing the compiled material leaves a chosen factory alone',
    () async {
      final original = GlyphMaterial3d.factory;
      addTearDown(() => GlyphMaterial3d.factory = original);

      GlyphMaterial3d.factory = _NeverBuilt.new;
      // Returns before it loads anything, which is what makes this callable
      // without a GPU — and is the behaviour an application with a glyph
      // material of its own depends on.
      await installGlyphMaterial3d();
      expect(GlyphMaterial3d.factory, same(_NeverBuilt.new));
    },
  );
}
