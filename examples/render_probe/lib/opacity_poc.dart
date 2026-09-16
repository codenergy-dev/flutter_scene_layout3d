// An experiment, not a probe suite.
//
// `plans/2026_09_11_what_a_real_application_still_needs.md` carries an item,
// *a box that fades*, whose entry says there is no `Opacity3d` and that it may
// not be buildable — because `flutter_scene`'s `Node` has no opacity. This
// compares the ways of fading a subtree that do not need one, so that the plan
// written afterwards picks its approach from photographs rather than from
// reasoning.
//
// **The gate is not what the map says it is.** Both shaders this package
// ships already multiply alpha: `box_decoration3d.fmat` takes a `vec4 color`
// and `text_glyph3d.fmat` computes `sampled.a * color.a`. Folding an opacity
// into them is uniform arithmetic and needs nothing from the engine. What
// actually stands in the way is **depth**: both declare `depth_write: true`,
// deliberately and with photographed evidence behind it (see
// `plans/2026_09_10_a_transparent_slab_that_does_not_erase.md`), and a partly
// transparent slab that writes depth hides what is behind it instead of
// showing it through. A fading subtree is that case, everywhere, at once.
//
// So the approaches here are answers to *depth*, not answers to alpha:
//
// | approach | alpha | depth |
// | --- | --- | --- |
// | [FadeApproach.naive] | folded into the colour | written, as shipped |
// | [FadeApproach.dither] | untouched | written, by the fragments that survive |
// | [FadeApproach.bayer] | untouched | written, by the fragments that survive |
// | [FadeApproach.noDepth] | folded into the colour | not written |
//
// The last two differ only in *which* fragments survive, which is a question
// about how the fade looks rather than about whether it is correct.
//
// [FadeApproach.dither] is the engine's own idiom rather than an invention:
// `flutter_scene` cross-fades levels of detail with a screen-door discard in
// `shaders/lod_fade.glsl`, and `Material.lodFade` drives it. That field is
// `@internal` and its dartdoc says only the built-in lit and unlit materials
// honour it, so a `.fmat` cannot be faded through it — but a `.fmat` can
// declare a `fade` uniform of its own and inline the same four lines, which is
// what `tool/make_opacity_variants.dart` does.

import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart'
    show
        Camera,
        Node,
        PreprocessedMaterial,
        RenderTexture,
        RenderTextureView,
        RenderView,
        Scene,
        SceneView,
        TextureSource,
        loadFmatMaterial;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart'
    show kPanelMaterialSource;
import 'package:vector_math/vector_math.dart' show Quaternion, Vector3;

import 'probe_scene.dart';

/// How a subtree is faded.
enum FadeApproach {
  /// The opacity is folded into every drawn colour's alpha, and the shaders
  /// are the ones the package ships — depth write and all.
  ///
  /// The cheapest thing that could work, and the one an implementer reaches
  /// for first. It is here to be photographed failing.
  naive('naive'),

  /// The opacity becomes screen-door coverage: a stable per-pixel hash decides
  /// which fragments survive, and the survivors draw and write depth exactly
  /// as an unfaded panel does.
  ///
  /// Ordering is therefore unchanged by fading, which is the claim to check.
  /// The cost to look for is grain.
  dither('dither'),

  /// Screen-door coverage again, thresholded against an ordered 4x4 Bayer
  /// matrix rather than against the engine's hash.
  ///
  /// Identical to [dither] in every way that matters to depth, and different
  /// only in what the fade *looks like* — which is the one thing left to
  /// choose between once ordering is settled.
  bayer('bayer'),

  /// The opacity is folded into the alpha, as [naive], and the shaders do not
  /// write depth.
  ///
  /// The one-line change the package's own shader argues against at length.
  /// Photographed here under a fade rather than under a fully transparent
  /// slab, because the map's open question is about the milder case.
  noDepth('nodepth'),

  /// Flutter's own `Opacity`, over the subtree rendered into a texture of its
  /// own — the closest thing to a `saveLayer` this stack can build.
  ///
  /// Nothing is faded in the scene at all. The faded subtree's nodes are
  /// stamped onto a render layer of their own; a second `RenderView` with that
  /// layer mask and a `RenderTexture` target draws them alone, the screen view
  /// draws everything else, and the two are composed by the widget tree with
  /// an `Opacity` in between.
  ///
  /// This is the only approach here that gets **group opacity** exactly right:
  /// the subtree is composited once and then made transparent, so a label over
  /// a panel does not blend twice. What it costs is a whole render pass per
  /// faded subtree per frame, and the thing to look for in the picture is what
  /// it does to **depth**: a composited texture is drawn over the screen view
  /// entire, so anything that should stand *in front of* the faded subtree is
  /// buried by it. `pin` is in the scene to catch exactly that.
  layer('layer');

  const FadeApproach(this.id);

  /// Used in a capture's file name.
  final String id;
}

// ── The materials ───────────────────────────────────────────────────────────

const String _panelDither = 'assets/opacity_poc/panel_dither.fmat';
const String _panelBayer = 'assets/opacity_poc/panel_bayer.fmat';
const String _panelNoDepth = 'assets/opacity_poc/panel_nodepth.fmat';
const String _glyphDither = 'assets/opacity_poc/glyph_dither.fmat';
const String _glyphBayer = 'assets/opacity_poc/glyph_bayer.fmat';
const String _glyphNoDepth = 'assets/opacity_poc/glyph_nodepth.fmat';

/// Loads a `.fmat` and returns a **synchronous** factory for further copies.
///
/// `loadFmatMaterial`'s own `factory` parameter is the trick, and it is
/// `flutter_scene_material3d`'s `loadPanelMaterialFactory` generalized to any
/// source path: the closure captures the three typed values the registry
/// resolved, which is what building another instance takes and is not
/// reachable from a `PreprocessedMaterial` afterwards.
///
/// One material per box is not an optimization here, it is correctness: a
/// painter writes each box's parameters into the material it was handed, so
/// boxes sharing one material collapse onto whichever painted last.
Future<PreprocessedMaterial Function()> _factoryFor(String source) async {
  PreprocessedMaterial Function(PreprocessedMaterial? like)? build;
  final prototype = await loadFmatMaterial(
    source,
    factory: ({required fragmentShader, required metadata, vertexShaders}) {
      build = (like) => PreprocessedMaterial(
        fragmentShader: fragmentShader,
        metadata: metadata,
        vertexShaders: vertexShaders,
        // `lit` materials resolve a second fragment shader for a prefiltered
        // radiance cube, attached to the instance the registry built. The
        // setter is internal, so it is threaded through the constructor.
        radianceCubeFragmentShader: like?.radianceCubeFragmentShader,
      );
      return build!(null);
    },
  );
  final make = build;
  if (make == null) {
    throw StateError('loadFmatMaterial did not use its factory for $source');
  }
  var first = true;
  return () {
    if (first) {
      first = false;
      return prototype;
    }
    return make(prototype);
  };
}

/// The loaders, resolved once each and reused across captures.
///
/// A capture rebuilds its scene, so it rebuilds its materials; reloading the
/// shader each time would be several seconds per capture and would prove
/// nothing.
final Map<String, Future<PreprocessedMaterial Function()>> _factories =
    <String, Future<PreprocessedMaterial Function()>>{};

Future<PreprocessedMaterial Function()> _factory(String source) =>
    _factories[source] ??= _factoryFor(source);

/// The glyph material the experiment draws type with.
///
/// Modelled on `FmatGlyphMaterial3d`, which is not reusable here because it
/// has no way to carry either of the two things an approach needs: a scale on
/// the tint's alpha, or a `fade` uniform.
class _PocGlyphMaterial implements GlyphMaterial3d {
  _PocGlyphMaterial({
    required this.material,
    required this.tintScale,
    required this.ditherFade,
  });

  @override
  final PreprocessedMaterial material;

  /// Multiplied into the tint's alpha — how [FadeApproach.naive] and
  /// [FadeApproach.noDepth] fade a label.
  final double tintScale;

  /// Written to the shader's `fade` uniform, or null for a shader without one.
  final double? ditherFade;

  Color _tint = const Color(0xFFFFFFFF);
  bool _hasAtlas = false;

  @override
  void bindAtlas(TextureSource? atlas) {
    final texture = atlas?.sampledTexture;
    _hasAtlas = texture != null;
    if (texture == null) {
      // No atlas yet: draw nothing rather than the sampler's white
      // placeholder, which a glyph mesh would otherwise show as solid
      // rectangles. Zero alpha is below any cutoff, so the shader discards
      // and these fragments stay out of the depth buffer too.
      material.parameters.setColor('color', const Color(0x00000000));
      return;
    }
    material.parameters
      ..setTexture('atlas', texture, sampler: atlas!.sampledSampler)
      ..setColor('color', _faded(_tint));
    final fade = ditherFade;
    if (fade != null) material.parameters.setFloat('fade', fade);
  }

  @override
  void tint(Color color) {
    _tint = color;
    if (_hasAtlas) material.parameters.setColor('color', _faded(color));
  }

  Color _faded(Color color) =>
      tintScale >= 1.0 ? color : color.withValues(alpha: color.a * tintScale);
}

/// A panel that is **inside the faded subtree**.
///
/// It exists because a fade has to reach some boxes and not others, and the
/// painter seam has no other way to say which: `BoxDecoration3d.cacheKey` is
/// the type, so every panel in the tree shares one painter and one
/// `createMaterial` factory. A subclass gets a cache key of its own, therefore
/// a painter of its own, therefore a factory that can write a `fade` uniform
/// the backdrops never see.
///
/// The first version of this experiment had no such thing and set the fade on
/// every material the factory made, which dithered the backdrops away too —
/// so at low opacity the frame emptied and the comparison measured nothing.
///
/// It is also, not by accident, the shape the real thing would take: something
/// has to mark a subtree as faded, and a decoration that knows its own opacity
/// is one of the two candidates (the other being an inherited value on
/// `Layout3d`, the way `clipRegion` is inherited).
class FadedBoxDecoration3d extends BoxDecoration3d {
  /// Creates a faded panel.
  const FadedBoxDecoration3d({super.color});

  /// Builds the painter faded panels are drawn by.
  static Decoration3dPainter? Function(BoxDecoration3d decoration)?
  painterFactory;

  @override
  Object get cacheKey => FadedBoxDecoration3d;

  @override
  Decoration3dPainter? createPainter() => painterFactory?.call(this);
}

/// Installs the panel painter and the glyph material [approach] draws with,
/// faded to [fade].
///
/// Both seams are global statics — `BoxDecoration3d.painterFactory` and
/// `GlyphMaterial3d.factory` — so this **overwrites** rather than installing,
/// which is what lets one process photograph every approach in turn.
/// `initializeMaterial3d` cannot be used for that reason: it returns early
/// when a factory is already in place.
Future<void> installApproach(FadeApproach approach, double fade) async {
  // Idempotent, and cached by the engine, so awaiting it per capture is free.
  // Nothing below may run before it resolves: loading a `.fmat` reads the
  // shader bundle it puts in place.
  await Scene.initializeStaticResources();

  final (String panelSource, String glyphSource) = switch (approach) {
    FadeApproach.naive => (kPanelMaterialSource, kGlyphMaterialSource),
    FadeApproach.dither => (_panelDither, _glyphDither),
    FadeApproach.bayer => (_panelBayer, _glyphBayer),
    FadeApproach.noDepth => (_panelNoDepth, _glyphNoDepth),
    // Nothing is faded in the scene: the fade happens in the widget tree.
    FadeApproach.layer => (kPanelMaterialSource, kGlyphMaterialSource),
  };

  final panels = await _factory(panelSource);
  final glyphs = await _factory(glyphSource);

  // Dithering leaves every colour alone and fades by coverage; the other two
  // leave coverage alone and fade every colour. That one line is the whole
  // difference between the approaches on the alpha side.
  final screenDoor =
      approach == FadeApproach.dither || approach == FadeApproach.bayer;
  final ditherFade = screenDoor ? fade : null;
  // The layer approach fades nothing it draws — `Opacity` does that to the
  // finished image — so its tint is left alone too.
  final tintScale = screenDoor || approach == FadeApproach.layer ? 1.0 : fade;

  // The backdrops: this approach's shader, and no fade. They are outside the
  // faded subtree and must be drawn exactly as they always are.
  BoxDecoration3d.painterFactory = (_) =>
      BoxDecoration3dPainter(createMaterial: panels);

  // The faded subtree. Only dithering has anything to write here; the other
  // two carry their fade in the colour, which the scene has already folded in.
  FadedBoxDecoration3d.painterFactory = (_) => BoxDecoration3dPainter(
    createMaterial: () {
      final material = panels();
      // Written once, at creation, and it survives every repaint:
      // `BoxDecoration3dUniforms.applyTo` writes exactly the parameters the
      // package's shader declares, and `fade` is not one of them.
      if (ditherFade != null) material.parameters.setFloat('fade', ditherFade);
      return material;
    },
  );

  GlyphMaterial3d.factory = () => _PocGlyphMaterial(
    material: glyphs(),
    tintScale: tintScale,
    ditherFade: ditherFade,
  );
}

// ── The scene ───────────────────────────────────────────────────────────────

/// What the faded subtree must let through: a warm, red-dominant panel.
///
/// The pair of colours is a **channel order** rather than a pair of
/// luminances, which is the rule `README.md` states for any probe comparing
/// colours: no exposure, tone mapping or lighting change can put more red than
/// blue into a blue panel by accident.
const Color kBackdrop = Color(0xFFC85A16);

/// The faded panel: blue-dominant, the same fill the other scenes here use.
const Color kFaded = Color(0xFF1B3A6B);

/// The label on the faded panel.
const Color kInk = Color(0xFFF5F5F5);

/// A small opaque panel standing **in front of** the faded card, and outside
/// the faded subtree.
///
/// It exists for one approach: rendering the faded subtree into a texture and
/// compositing it flattens that subtree onto everything else, so whatever was
/// supposed to be in front of it is buried. Nothing else in this scene can
/// show that, because everything else the fade touches is genuinely the
/// frontmost thing there.
///
/// Green-dominant, so "is the pin there" is a channel order against a warm
/// backdrop and a cold card rather than a brightness anyone has to justify.
const Color kPin = Color(0xFF6FBF3A);

/// Builds the comparison scene.
///
/// **Two arrangements, because the defect only lives in one of them.** A
/// blended draw erases only what is drawn *after* it, and the translucent pass
/// sorts back to front by the world-space centre of each draw's bounds — so a
/// faded panel standing plainly in front of what it covers is drawn second and
/// behaves perfectly. That scene passes whatever the approach, which is the
/// trap `2026_09_10_a_transparent_slab_that_does_not_erase.md` fell into and
/// recorded.
///
/// So the left half is that benign arrangement — a faded card in front of a
/// backdrop, with a label on it — and it is there to answer the *alpha*
/// questions: does the label fade with its panel, what does the fade look
/// like, what does it cost. The right half is the arrangement the catalogue
/// actually makes, measured off a photographed navigation bar: a thin panel
/// **co-centred** with the thick one behind it, so their sort keys tie and the
/// faded one is drawn first. That is where erasure lives.
///
/// [turned] yaws the surface, which is the one thing that separates a shader
/// that writes depth from one that merely happens to be drawn in the right
/// order: turning the plane by `theta` moves a label `d` units off-centre by
/// `d * sin(theta)` in the sort, and the only thing keeping a label in front of
/// its own panel is half the panel's thickness.
ProbeSceneContent buildFadeScene({
  required double fade,
  required bool foldIntoAlpha,
  required bool turned,
}) {
  // A backdrop, outside the faded subtree.
  DecoratedBox3d backdrop(String name) => DecoratedBox3d(
    decoration: const BoxDecoration3d(color: kBackdrop),
    name: name,
  );

  // A panel inside it. The decoration's type is what carries "this is being
  // faded" to the painter seam — see [FadedBoxDecoration3d].
  DecoratedBox3d panel(Color color, String name) => DecoratedBox3d(
    decoration: FadedBoxDecoration3d(color: color),
    name: name,
  );

  // [FadeApproach.naive] and [FadeApproach.noDepth] fade by alpha, and this is
  // where they do it: the opacity multiplied into the drawn colour, which is
  // what an `Opacity3d` folding into `BoxDecoration3dUniforms` would arrive
  // at. Dithering leaves every colour alone and fades by coverage instead, so
  // it passes 1.0 here and carries the fade in its own uniform.
  //
  // A real implementation would have to fold it into the border, the surface
  // tint and the state layer as well. This scene has none of the three, which
  // is why the colour alone is honest here and would not be in the package.
  final faded = foldIntoAlpha
      ? kFaded.withValues(alpha: kFaded.a * fade)
      : kFaded;

  // The backdrops are never faded: they are what the faded subtree has to let
  // through, and an approach is judged by how much of them arrives.
  final backLeft = backdrop('backLeft');
  final backRight = backdrop('backRight');
  final fadeLeft = panel(faded, 'fadeLeft');
  final fadeRight = panel(faded, 'fadeRight');
  final pin = DecoratedBox3d(
    decoration: const BoxDecoration3d(color: kPin),
    name: 'pin',
  );
  final label = Text3d(
    'Ag',
    style: TextStyle(
      fontSize: 64,
      // The label fades the same way the panel it sits on does, which for the
      // alpha approaches means through the tint's alpha — see
      // `_PocGlyphMaterial.tintScale`. Set here as well so a reader of the
      // scene can see that a label is part of the faded subtree.
      color: foldIntoAlpha ? kInk.withValues(alpha: kInk.a * fade) : kInk,
    ),
    renderer: AtlasText3dRenderer(),
    name: 'label',
  );

  final surface = Layout3dSurface(
    constraints: Constraints3d.tight(const Size3d(4.0, 2.0, 1.2)),
    child: Stack3d(
      children: <Layout3d>[
        // ── Left: the benign ordering ──────────────────────────────────
        //
        // The card stands a third of a unit proud of the backdrop, so the
        // backdrop's bounds centre is further from the camera (0.55 against
        // 0.19), the backdrop is drawn first, and the card blends over
        // something that has already drawn. Every approach should get this
        // one right, which is what makes it the half that answers the
        // questions about *alpha* rather than about depth.
        Positioned3d(
          left: 0.10,
          top: 0.15,
          front: 0.50,
          width: 1.70,
          height: 1.70,
          depth: 0.10,
          child: backLeft,
        ),
        Positioned3d(
          left: 0.30,
          top: 0.35,
          front: 0.15,
          width: 1.30,
          height: 1.30,
          depth: 0.08,
          child: fadeLeft,
        ),
        // Near the top of the card, and small, so that a reading taken low on
        // the card is of the panel alone. The first version of this scene put
        // a 96-point label across the middle and every "panel" reading in the
        // table was really a reading of the label.
        Positioned3d(left: 0.45, top: 0.45, front: 0.13, child: label),
        // A tenth of a unit in front of the card's face, overlapping its lower
        // corner, and **not** part of the faded subtree. Under every approach
        // that leaves the depth buffer in charge this is drawn over the card
        // whatever the card's opacity; under the layer approach the card's
        // texture is composited over the whole screen view and this goes with
        // it. Placed clear of both panel readings on purpose.
        Positioned3d(
          left: 1.25,
          top: 1.25,
          front: 0.05,
          width: 0.50,
          height: 0.50,
          depth: 0.04,
          child: pin,
        ),

        // ── Right: the ordering that erases ────────────────────────────
        //
        // The faded panel's **bounds centre is further from the camera** than
        // the backdrop's (0.56 against 0.55) while its **front face is
        // nearer** (0.45 against 0.50). So the translucent pass draws it
        // first, it writes its depth, and the backdrop drawn afterwards fails
        // the depth test across the whole overlap — leaving the faded panel
        // blending over the scene's backdrop instead of over the panel it is
        // supposed to be in front of.
        //
        // That is the arrangement a navigation bar produced and
        // `2026_09_10_a_transparent_slab_that_does_not_erase.md` photographed,
        // with one change: there the two were exactly **co-centred**, and a
        // tie in this sort is not an ordering at all — Dart's `List.sort` is
        // not stable, so which one draws first is unspecified. A hundredth of
        // a unit of separation makes the pathological order the one that
        // happens every run, which an experiment comparing three approaches
        // needs and a bug report does not.
        Positioned3d(
          left: 2.20,
          top: 0.15,
          front: 0.50,
          width: 1.70,
          height: 1.70,
          depth: 0.10,
          child: backRight,
        ),
        Positioned3d(
          left: 2.45,
          top: 0.40,
          front: 0.45,
          width: 1.20,
          height: 1.20,
          depth: 0.22,
          child: fadeRight,
        ),
      ],
    ),
  );

  if (turned) {
    surface.plane.rotation = Quaternion.axisAngle(Vector3(0, 1, 0), 0.25);
  }

  return ProbeSceneContent(
    surfaces: <Layout3dSurface>[surface],
    probes: <String, Layout3d>{
      'backLeft': backLeft,
      'backRight': backRight,
      'fadeLeft': fadeLeft,
      'fadeRight': fadeRight,
      'label': label,
      'pin': pin,
    },
  );
}

/// One capture: an approach, an opacity, and whether the surface is turned.
ProbeScene fadeScene(
  FadeApproach approach,
  double fade, {
  bool turned = false,
}) {
  final suffix = turned ? '_turned' : '';
  return ProbeScene(
    'fade_${approach.id}_${(fade * 100).round()}$suffix',
    () => buildFadeScene(
      fade: fade,
      foldIntoAlpha:
          approach != FadeApproach.dither && approach != FadeApproach.bayer,
      turned: turned,
    ),
    viewSize: const Size(720, 420),
    preload: () => installApproach(approach, fade),
  );
}

// ── The layer approach ──────────────────────────────────────────────────────

/// The render layer the faded subtree is moved onto.
///
/// Bit 1. Bit 0 is [kRenderLayerDefault], which every node is born with and
/// which everything outside the faded subtree keeps.
const int kFadedLayer = 1 << 1;

/// Puts [box] and everything drawn under it onto [layers].
///
/// A walk rather than a flag, because **`Node.layers` is not inherited** — the
/// engine's own dartdoc says so, and says to set it on each mesh-bearing node.
/// A box's geometry hangs under its node as children the painter and the text
/// renderer added, so the subtree has to be walked to the leaves.
///
/// That is worth noticing rather than working around: it is the first real
/// cost of this approach, and it is per frame in any tree where boxes come and
/// go while a fade is running, because a node created after the stamp is born
/// on the default layer and appears at full opacity.
void stampLayer(Layout3d box, int layers) {
  void walk(Node node) {
    node.layers = layers;
    for (final child in node.children) {
      walk(child);
    }
  }

  walk(box.node);
}

/// Draws the fade scene with the faded subtree composited through a texture.
///
/// The structure is the whole experiment, so it is worth reading as a shape:
/// one `Scene`, two `RenderView`s over it. The screen view is given every
/// layer **except** the faded one, so it draws the backdrops and the pin and
/// leaves a hole where the card is. The second view is given only the faded
/// layer and a [RenderTexture] to draw into, so it draws the card and the
/// label alone, against nothing. Flutter then stacks the two with an
/// [Opacity] in between, which is `saveLayer` by another name.
class LayerFadeView extends StatefulWidget {
  /// Creates the view.
  const LayerFadeView({
    required this.fade,
    required this.turned,
    required this.viewSize,
    super.key,
  });

  /// How opaque the faded subtree is.
  final double fade;

  /// Whether the surface is yawed.
  final bool turned;

  /// The size the scene is drawn at.
  final Size viewSize;

  @override
  State<LayerFadeView> createState() => LayerFadeViewState();
}

/// The state, which owns the scene so a rebuild does not build geometry twice.
class LayerFadeViewState extends State<LayerFadeView> {
  /// The scene both views render.
  final Scene scene = Scene();

  /// The camera both views share, so the two images line up exactly.
  late final Camera camera;

  /// The laid-out surfaces, for a probe to ask where a box ended up.
  late final ProbeSceneContent content;

  /// Where the faded subtree is drawn.
  late final RenderTexture texture;

  @override
  void initState() {
    super.initState();
    camera = ProbeScene.defaultCamera();
    // Nothing in the scene is faded: no colour is touched and no uniform is
    // written. The opacity lives entirely in the widget tree below.
    content = buildFadeScene(
      fade: 1.0,
      foldIntoAlpha: false,
      turned: widget.turned,
    );
    for (final surface in content.surfaces) {
      scene.add(surface.plane);
      surface.flush();
    }

    // The faded subtree, named box by box. A real implementation would take
    // this from the layout tree under an `Opacity3d`; here the three boxes are
    // spelled out, which is the same set.
    for (final name in const <String>['fadeLeft', 'fadeRight', 'label']) {
      stampLayer(content.probes[name]!, kFadedLayer);
    }

    final ratio =
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    texture = RenderTexture(
      width: (widget.viewSize.width * ratio).round(),
      height: (widget.viewSize.height * ratio).round(),
    );
    // A view with a target renders whenever the scene does, and before the
    // screen views, so the texture a frame composites is that frame's.
    scene.views.add(
      RenderView(camera: camera, target: texture, layerMask: kFadedLayer),
    );
  }

  @override
  Widget build(BuildContext context) => Center(
    child: RepaintBoundary(
      key: probeBoundaryKey,
      child: SizedBox(
        width: widget.viewSize.width,
        height: widget.viewSize.height,
        child: ColoredBox(
          color: kProbeClear,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              SceneView(
                scene,
                viewsBuilder: (_) => <RenderView>[
                  RenderView(camera: camera, layerMask: ~kFadedLayer),
                ],
              ),
              Opacity(
                opacity: widget.fade,
                child: RenderTextureView(texture, fit: BoxFit.fill),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
