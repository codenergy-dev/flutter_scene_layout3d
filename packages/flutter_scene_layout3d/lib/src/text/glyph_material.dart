import 'dart:math' as math;

import 'package:flutter/painting.dart' show Color;
import 'package:flutter/services.dart' show AssetBundle;
import 'package:flutter_scene/scene.dart'
    show
        AlphaMode,
        Material,
        PreprocessedMaterial,
        TextureSource,
        UnlitMaterial,
        loadFmatMaterial;
import 'package:vector_math/vector_math.dart' show Vector4;

/// The `.fmat` a line of type is drawn with, named the way `loadFmatMaterial`
/// wants it: relative to the root of the package that ships it.
const String kGlyphMaterialSource = 'assets/text_glyph3d.fmat';

/// The material one label's glyph mesh is drawn with.
///
/// A seam rather than a material, for the same reason [BoxDecoration3d] has a
/// painter factory: the material that draws type *correctly* is a compiled
/// `.fmat`, loading one is asynchronous and needs a GPU, and a label builds
/// its mesh synchronously in the middle of a layout pass. So the asynchronous
/// half happens once, at startup, through [installGlyphMaterial3d], and every
/// label afterwards asks [factory] for one.
///
/// **What the compiled one does that the fallback cannot.** It writes depth.
/// `flutter_scene` orders translucent draws back to front by the distance to
/// the centre of each object's bounds, and that comparison mixes a label's
/// distance from the centre of the panel it sits on with the angle the panel
/// is turned at — so a panel can sort *after* the label written on it and
/// paint over it. A glyph mesh that writes depth is not at the mercy of that:
/// whichever is drawn first, the depth buffer settles which is in front. The
/// engine's `UnlitMaterial` cannot be made to do it — `translucentDepthWrite`
/// is not settable and `AlphaMode.mask` is unimplemented for unlit — which is
/// why this package ships a shader for it.
///
/// An application that never installs one still draws type, the way it always
/// did, with [UnlitGlyphMaterial3d]. `initializeMaterial3d()` installs the
/// compiled one, and so does any application that says so itself:
///
/// ```dart
/// await Scene.initializeStaticResources();
/// await installGlyphMaterial3d();
/// ```
abstract class GlyphMaterial3d {
  /// Makes the material every [AtlasText3dRenderer] and [RichText3d] draws
  /// with.
  ///
  /// [UnlitGlyphMaterial3d.new] until [installGlyphMaterial3d] replaces it.
  /// Assign a factory of your own for a material with different rules — a
  /// distance field, a shader that fades type with distance — and note that
  /// it is called **once per label**, because the colour and the atlas are
  /// per-label parameters and the last mesh drawn would otherwise win them.
  static GlyphMaterial3d Function() factory = UnlitGlyphMaterial3d.new;

  /// The engine material the glyph mesh is drawn with.
  Material get material;

  /// Points the material at the atlas the glyphs were packed into, or at
  /// nothing.
  ///
  /// The second half is not a nicety: a material with no texture samples a
  /// **1x1 white placeholder**, so a glyph mesh attached before the atlas has
  /// uploaded anything draws its quads as solid rectangles in the label's own
  /// colour. Every implementation must draw *nothing* until it has an atlas.
  void bindAtlas(TextureSource? atlas);

  /// The colour the white glyphs are tinted with.
  ///
  /// In sRGB, as a `TextStyle` gives it. What the implementation does with it
  /// is its own business: both of the ones here decode it to linear, because
  /// that is the space a material's colour is multiplied in and a label handed
  /// a mid grey comes out visibly too light without it.
  void tint(Color color);
}

/// The fallback: `UnlitMaterial`, which blends and does not write depth.
///
/// What every label drew with before there was a shader for it, and what one
/// still draws with in an application that installs nothing. It is correct
/// wherever nothing else is drawn near the label's own plane — type floating
/// in a scene, a label on a surface with no panel behind it — and it is the
/// thing that loses letters when a panel it is written on turns. See
/// [GlyphMaterial3d].
class UnlitGlyphMaterial3d implements GlyphMaterial3d {
  /// Creates the fallback material.
  UnlitGlyphMaterial3d();

  @override
  final UnlitMaterial material = UnlitMaterial()
    ..alphaMode = AlphaMode.blend
    ..vertexColorWeight = 0.0;

  Vector4 _tint = Vector4(1.0, 1.0, 1.0, 1.0);
  bool _hasAtlas = false;

  @override
  void bindAtlas(TextureSource? atlas) {
    _hasAtlas = atlas != null;
    if (atlas != null) material.baseColorTexture = atlas;
    material.baseColorFactor = _hasAtlas ? _tint : Vector4.zero();
  }

  @override
  void tint(Color color) {
    _tint = linearColor(color);
    if (_hasAtlas) material.baseColorFactor = _tint;
  }
}

/// The compiled one: `assets/text_glyph3d.fmat`, which blends *and* writes
/// depth.
///
/// Built by [installGlyphMaterial3d] rather than directly, because a
/// `PreprocessedMaterial` can only come from an asynchronous load.
class FmatGlyphMaterial3d implements GlyphMaterial3d {
  /// Wraps a freshly loaded instance of the glyph shader.
  FmatGlyphMaterial3d(this.material);

  @override
  final PreprocessedMaterial material;

  Color _tint = const Color(0xFFFFFFFF);
  bool _hasAtlas = false;

  @override
  void bindAtlas(TextureSource? atlas) {
    final texture = atlas?.sampledTexture;
    _hasAtlas = texture != null;
    if (texture == null) {
      // No atlas yet: draw nothing rather than the sampler's white
      // placeholder. A zero alpha is below any cutoff, so the shader
      // discards, which also keeps these fragments out of the depth buffer.
      material.parameters.setColor('color', const Color(0x00000000));
      return;
    }
    material.parameters
      ..setTexture('atlas', texture, sampler: atlas!.sampledSampler)
      ..setColor('color', _tint);
  }

  @override
  void tint(Color color) {
    _tint = color;
    // Only applied once there is something to draw. A colour written while no
    // atlas is bound would put the label back to drawing the sampler's white
    // placeholder as solid rectangles. `bindAtlas` writes it then.
    if (_hasAtlas) material.parameters.setColor('color', color);
  }
}

/// Loads the glyph shader and points [GlyphMaterial3d.factory] at it.
///
/// Call it once, after `Scene.initializeStaticResources()` has resolved —
/// loading a `.fmat` reads the shader bundle that puts in place.
/// `initializeMaterial3d()` does both for a Material application.
///
/// Returns without doing anything when a factory other than the default is
/// already installed, so an application with a glyph material of its own keeps
/// it. Pass [bundle] to load from somewhere other than the root bundle.
///
/// The trick that makes a synchronous [GlyphMaterial3d.factory] out of an
/// asynchronous load is `loadFmatMaterial`'s own `factory` parameter: it hands
/// the caller the compiled fragment shader and the sidecar metadata, which is
/// exactly what building a second instance takes and is not reachable from a
/// `PreprocessedMaterial` afterwards. `flutter_scene_material3d`'s
/// `loadPanelMaterialFactory` is the same trick for panels, and for the same
/// reason: one material per box, because the parameters are per box.
Future<void> installGlyphMaterial3d({AssetBundle? bundle}) async {
  if (GlyphMaterial3d.factory != UnlitGlyphMaterial3d.new) return;
  PreprocessedMaterial Function()? build;
  final prototype = await loadFmatMaterial(
    kGlyphMaterialSource,
    bundle: bundle,
    factory: ({required fragmentShader, required metadata, vertexShaders}) {
      build = () => PreprocessedMaterial(
        fragmentShader: fragmentShader,
        metadata: metadata,
        vertexShaders: vertexShaders,
      );
      return build!();
    },
  );
  final make = build;
  if (make == null) {
    // Defensive, and the same guard the panel loader carries: the registry has
    // always called the factory it was given, and a version that stopped would
    // otherwise fail as every label in the application sharing one colour.
    throw StateError(
      'loadFmatMaterial did not use the factory it was given, so '
      'flutter_scene_layout3d cannot build a material per label. Install '
      'GlyphMaterial3d.factory by hand.',
    );
  }
  var first = true;
  GlyphMaterial3d makeGlyphMaterial() {
    if (first) {
      first = false;
      return FmatGlyphMaterial3d(prototype);
    }
    return FmatGlyphMaterial3d(make());
  }

  GlyphMaterial3d.factory = makeGlyphMaterial;
}

/// [color] as the linear RGBA a material's colour factor multiplies in.
///
/// A `Color` is sRGB and `UnlitMaterial.baseColorFactor` is linear, so a
/// label handed a mid grey and drawn without this comes out visibly too
/// light. The engine's own `setColor` does the same decode for a shader
/// parameter tagged `source_color`, which is how the compiled glyph material
/// gets there instead.
Vector4 linearColor(Color color) => Vector4(
  _srgbToLinear(color.r),
  _srgbToLinear(color.g),
  _srgbToLinear(color.b),
  color.a,
);

double _srgbToLinear(double component) => component <= 0.04045
    ? component / 12.92
    : math.pow((component + 0.055) / 1.055, 2.4).toDouble();
