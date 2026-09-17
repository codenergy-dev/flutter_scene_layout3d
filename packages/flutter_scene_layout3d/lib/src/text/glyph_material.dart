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

  /// How much of the label survives, from 0 to 1: the opacity in force on the
  /// box, from [Layout3d.inheritedOpacity].
  ///
  /// **Do not implement this by scaling the tint's alpha.** The compiled
  /// material discards a fragment whose coverage falls below `alpha_cutoff`,
  /// so a faded tint walks a glyph's whole silhouette under the cutoff at
  /// once: at 30% the type does not fade, it vanishes — and the wall around
  /// it, which is opaque and coloured by its own vertices, stays at full
  /// strength, so what is left is a hollow outline of the letter. That was
  /// photographed, and it is the defect the screen-door approach exists to
  /// avoid. See `assets/text_glyph3d.fmat`.
  ///
  /// [UnlitGlyphMaterial3d] is the one exception, and it is allowed to be:
  /// the fallback has no cutoff and no wall shader, so fading its alpha is
  /// the only thing it can do and is right for what it draws.
  void fade(double opacity);
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
  double _fade = 1.0;
  bool _hasAtlas = false;

  @override
  void bindAtlas(TextureSource? atlas) {
    _hasAtlas = atlas != null;
    if (atlas != null) material.baseColorTexture = atlas;
    material.baseColorFactor = _hasAtlas ? _faded : Vector4.zero();
  }

  @override
  void tint(Color color) {
    _tint = linearColor(color);
    if (_hasAtlas) material.baseColorFactor = _faded;
  }

  /// Folds the opacity into the tint's alpha, which is the one thing this
  /// material can do and is the right thing for it.
  ///
  /// The hazard [GlyphMaterial3d.fade] warns about does not apply here: this
  /// material blends rather than cutting off, so a faded label goes on
  /// looking like type all the way down, and it does not write depth either,
  /// so there is no slab to hide anything behind. What it does share with
  /// everything else in the fallback's story is the trade the fallback always
  /// made — it is correct wherever nothing else is drawn near the label's own
  /// plane, and at the mercy of the translucent sort where something is.
  @override
  void fade(double opacity) {
    final clamped = opacity.clamp(0.0, 1.0);
    if (_fade == clamped) return;
    _fade = clamped;
    if (_hasAtlas) material.baseColorFactor = _faded;
  }

  Vector4 get _faded => _fade >= 1.0
      ? _tint
      : Vector4(_tint.x, _tint.y, _tint.z, _tint.w * _fade);
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
  double _fade = 1.0;
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
      ..setColor('color', _tint)
      ..setFloat('fade', _fade);
  }

  @override
  void tint(Color color) {
    _tint = color;
    // Only applied once there is something to draw. A colour written while no
    // atlas is bound would put the label back to drawing the sampler's white
    // placeholder as solid rectangles. `bindAtlas` writes it then.
    if (_hasAtlas) material.parameters.setColor('color', color);
  }

  /// Writes the shader's `fade`, and leaves every colour alone.
  ///
  /// One float, and it is the whole cost of a frame of a fade over a label.
  /// The tint is untouched on purpose — see [GlyphMaterial3d.fade] for what
  /// scaling it would do to a glyph's silhouette.
  @override
  void fade(double opacity) {
    final clamped = opacity.clamp(0.0, 1.0);
    if (_fade == clamped) return;
    _fade = clamped;
    if (_hasAtlas) material.parameters.setFloat('fade', clamped);
  }
}

/// The `.fmat` the side of a letter is drawn with, named the way
/// `loadFmatMaterial` wants it: relative to the root of the package that ships
/// it.
const String kGlyphWallMaterialSource = 'assets/text_glyph_wall3d.fmat';

/// The material the wall around one label's glyphs is drawn with.
///
/// The third seam in a label, and the one nobody knew was there. A glyph is
/// not one mesh but three primitives — the front faces, the back faces, and
/// the **wall** that runs around each letter's silhouette joining them — and
/// the first two are drawn with [GlyphMaterial3d] while the wall never was.
/// It was an `UnlitMaterial` in [AlphaMode.opaque] with
/// `vertexColorWeight = 1.0`, because its colour is baked per segment into
/// the geometry's vertex colours: already shaded, already linear, nothing for
/// a uniform to say.
///
/// **Which is exactly why it needed a seam.** A colour in a vertex buffer
/// cannot be changed without rebuilding the mesh, and rebuilding geometry is
/// what the animation tiers forbid — so when a label fades, the faces fade
/// and the wall does not, and a 30% label comes out as a hollow outline of
/// itself. See [fade] and `plans/2026_09_16_a_box_that_fades.md`.
///
/// Like [GlyphMaterial3d] this is a factory called **once per label**,
/// because the fade is a per-label parameter. [installGlyphMaterial3d]
/// installs the compiled one alongside the glyph material; an application that
/// installs neither draws walls exactly as it always did, through
/// [UnlitGlyphWallMaterial3d].
abstract class GlyphWallMaterial3d {
  /// Makes the material every glyph wall in the tree is drawn with.
  ///
  /// [UnlitGlyphWallMaterial3d.new] until [installGlyphMaterial3d] replaces
  /// it.
  static GlyphWallMaterial3d Function() factory = UnlitGlyphWallMaterial3d.new;

  /// The engine material the wall geometry is drawn with.
  Material get material;

  /// How much of the label survives, from 0 to 1.
  ///
  /// **It has to be the same number the faces were given, and it has to be
  /// spent the same way.** The compiled materials both threshold a screen-door
  /// matrix against `gl_FragCoord`, so at any pixel the face and the wall
  /// meeting there keep or discard together and the letter dissolves as one
  /// solid. An implementation that faded the wall by some other rule — an
  /// alpha, a different matrix — would tear a fading letter along its own rim.
  void fade(double opacity);
}

/// The fallback: the `UnlitMaterial` the wall was always drawn with, which
/// fades by dropping out of the opaque pass.
///
/// Correct at full opacity, which is what it is for: an application that
/// installs no shaders draws exactly the walls it drew before. Under a fade
/// it does the only thing it can and blends — which takes the wall out of the
/// opaque pass and hands it to the translucent sort, the same trade every
/// other part of the uninstalled path makes.
class UnlitGlyphWallMaterial3d implements GlyphWallMaterial3d {
  /// Creates the fallback wall material.
  UnlitGlyphWallMaterial3d();

  @override
  final UnlitMaterial material = UnlitMaterial()
    ..alphaMode = AlphaMode.opaque
    // The colour comes entirely from the vertex colours
    // `AtlasText3dRenderer.buildGlyphWallGeometry` baked, which is why the
    // base factor is left white.
    ..vertexColorWeight = 1.0
    ..baseColorFactor = Vector4(1.0, 1.0, 1.0, 1.0);

  double _fade = 1.0;

  @override
  void fade(double opacity) {
    final clamped = opacity.clamp(0.0, 1.0);
    if (_fade == clamped) return;
    _fade = clamped;
    // Opaque again at the top, so a label that has finished fading in is
    // drawn by the depth buffer rather than by the sort, exactly as it was
    // before anything faded.
    material
      ..alphaMode = clamped >= 1.0 ? AlphaMode.opaque : AlphaMode.blend
      ..baseColorFactor = Vector4(1.0, 1.0, 1.0, clamped);
  }
}

/// The compiled one: `assets/text_glyph_wall3d.fmat`, which carries a `fade`
/// and discards against the same screen-door matrix the faces use.
///
/// Built by [installGlyphMaterial3d] rather than directly, because a
/// `PreprocessedMaterial` can only come from an asynchronous load.
class FmatGlyphWallMaterial3d implements GlyphWallMaterial3d {
  /// Wraps a freshly loaded instance of the wall shader.
  FmatGlyphWallMaterial3d(this.material);

  @override
  final PreprocessedMaterial material;

  double _fade = 1.0;

  @override
  void fade(double opacity) {
    final clamped = opacity.clamp(0.0, 1.0);
    if (_fade == clamped) return;
    _fade = clamped;
    material.parameters.setFloat('fade', clamped);
  }
}

/// Loads the glyph shaders and points the two factories at them.
///
/// Two shaders and two factories: [GlyphMaterial3d] for a glyph's faces and
/// [GlyphWallMaterial3d] for the wall around them. They are installed
/// together because they have to agree — a label whose faces fade and whose
/// wall does not is the defect this arrangement exists to avoid — and each is
/// skipped on its own when something other than the default is already there,
/// so an application with a material of its own keeps it.
///
/// Call it once, after `Scene.initializeStaticResources()` has resolved —
/// loading a `.fmat` reads the shader bundle that puts in place.
/// `initializeMaterial3d()` does both for a Material application. Pass
/// [bundle] to load from somewhere other than the root bundle.
///
/// The trick that makes a synchronous [GlyphMaterial3d.factory] out of an
/// asynchronous load is `loadFmatMaterial`'s own `factory` parameter: it hands
/// the caller the compiled fragment shader and the sidecar metadata, which is
/// exactly what building a second instance takes and is not reachable from a
/// `PreprocessedMaterial` afterwards. `flutter_scene_material3d`'s
/// `loadPanelMaterialFactory` is the same trick for panels, and for the same
/// reason: one material per box, because the parameters are per box.
Future<void> installGlyphMaterial3d({AssetBundle? bundle}) async {
  if (GlyphMaterial3d.factory == UnlitGlyphMaterial3d.new) {
    final make = await _loadPerLabel(kGlyphMaterialSource, bundle);
    GlyphMaterial3d.factory = () => FmatGlyphMaterial3d(make());
  }
  if (GlyphWallMaterial3d.factory == UnlitGlyphWallMaterial3d.new) {
    final make = await _loadPerLabel(kGlyphWallMaterialSource, bundle);
    GlyphWallMaterial3d.factory = () => FmatGlyphWallMaterial3d(make());
  }
}

/// Loads [source] and hands back a **synchronous** factory for more instances
/// of it.
///
/// One material per label is not an optimization, it is correctness: the
/// colour, the atlas and the fade are per-label parameters, and labels sharing
/// a material would collapse onto whichever drew last.
///
/// The trick that makes a synchronous factory out of an asynchronous load is
/// `loadFmatMaterial`'s own `factory` parameter: it hands the caller the
/// compiled fragment shader and the sidecar metadata, which is exactly what
/// building a second instance takes and is not reachable from a
/// `PreprocessedMaterial` afterwards. `flutter_scene_material3d`'s
/// `loadPanelMaterialFactory` is the same trick for panels.
Future<PreprocessedMaterial Function()> _loadPerLabel(
  String source,
  AssetBundle? bundle,
) async {
  PreprocessedMaterial Function()? build;
  final prototype = await loadFmatMaterial(
    source,
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
      'loadFmatMaterial did not use the factory it was given for $source, so '
      'flutter_scene_layout3d cannot build a material per label. Install the '
      'factory by hand.',
    );
  }
  // The registry already built one; handing it out first keeps the load from
  // costing an instance nobody uses.
  var first = true;
  return () {
    if (first) {
      first = false;
      return prototype;
    }
    return make();
  };
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
