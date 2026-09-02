import 'package:flutter/services.dart' show AssetBundle;
import 'package:flutter_scene/scene.dart'
    show PreprocessedMaterial, Scene, loadFmatMaterial;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show BoxDecoration3d, BoxDecoration3dPainter;

/// The `.fmat` every Material surface is drawn with, named the way
/// `loadFmatMaterial` wants it: relative to the root of the package that
/// ships it.
///
/// It lives in `flutter_scene_layout3d`, which compiles it from its own build
/// hook for whatever application depends on it, so this path resolves through
/// *that* package's generated manifest and an application's own hook needs
/// nothing in it about panels.
const String kPanelMaterialSource = 'assets/box_decoration3d.fmat';

/// Makes new instances of the panel material, synchronously, once
/// [loadPanelMaterialFactory] has run.
typedef PanelMaterialFactory = PreprocessedMaterial Function();

/// Everything a Material application does once, before anything draws.
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await initializeMaterial3d();
///   runApp(const MyApp());
/// }
/// ```
///
/// Two things happen, in an order that cannot be swapped:
///
/// 1. `Scene.initializeStaticResources()` is awaited. Until it resolves the
///    engine prints *"Flutter Scene is not ready to render. Skipping frame"*
///    and every geometry and material constructor is touching a shader bundle
///    that is not there yet. It is idempotent — the engine caches the future
///    — so calling it here costs nothing if the application already did.
/// 2. The panel painter is installed, which is what turns a themed component
///    from a correctly laid-out nothing into a picture. See
///    [installPanelPainter3d] for what that actually is.
///
/// **The default text renderer is deliberately not here**, and the reason is
/// the reason `DefaultTextRenderer3d` carries a factory rather than a
/// renderer. A `Text3dRenderer` is *owned by one label* — the label disposes
/// it — so there is no such thing as a global one to install; it reaches
/// labels through the widget tree, one instance each. The second half of
/// setup is therefore a widget rather than a call, and it is one line at the
/// point the theme goes in:
///
/// ```dart
/// SceneTheme3d(
///   data: Theme3dData.light,
///   textRendererFactory: AtlasText3dRenderer.new,   // the other half
///   child: screen,
/// )
/// ```
///
/// Pass [bundle] to load the shader from somewhere other than the root
/// bundle. Awaiting this twice is free: the second call sees the painter
/// already installed and returns.
Future<void> initializeMaterial3d({AssetBundle? bundle}) async {
  await Scene.initializeStaticResources();
  await installPanelPainter3d(bundle: bundle);
}

/// Loads the panel shader and points `BoxDecoration3d.painterFactory` at it.
///
/// Split out of [initializeMaterial3d] for an application that has already
/// awaited `Scene.initializeStaticResources()` itself and would rather say so.
/// **It must not be called before that resolves**: loading a `.fmat` reads the
/// shader bundle the engine's initialization puts in place.
///
/// Returns without doing anything when a painter is already installed, so an
/// application that installs its own painter — a different shader, a mesh of
/// its own — keeps it.
///
/// ## Why this is not the one-liner the layout package's README shows
///
/// That README installs one material and hands it to every box:
///
/// ```dart
/// final material = await loadFmatMaterial(kPanelMaterialSource);
/// BoxDecoration3d.painterFactory =
///     (_) => BoxDecoration3dPainter(createMaterial: () => material);
/// ```
///
/// which is correct exactly as long as the panels on a surface look alike,
/// because `BoxDecoration3dPainter` writes each box's parameters into the
/// material it was handed and **the last box painted wins the block**. A
/// Material catalogue is the case that breaks: a screen is a surface, a card
/// on it and a filled button on that, in three different colours at three
/// different elevations, and sharing one material collapses all three into
/// whichever painted last.
///
/// So every decorated box gets a material of its own, which needs a
/// *synchronous* factory — `BoxDecoration3dPainter.createMaterial` is called
/// during a layout pass — while `loadFmatMaterial` is asynchronous. The seam
/// that closes the gap is its `factory` parameter: it hands the caller the
/// compiled fragment shader, the sidecar metadata and the vertex variants, so
/// one asynchronous load can capture what it takes to build any number of
/// further instances synchronously. [loadPanelMaterialFactory] is that, and
/// it is the whole trick.
Future<void> installPanelPainter3d({AssetBundle? bundle}) async {
  if (BoxDecoration3d.painterFactory != null) return;
  final factory = await loadPanelMaterialFactory(bundle: bundle);
  BoxDecoration3d.painterFactory = (_) =>
      BoxDecoration3dPainter(createMaterial: factory);
}

/// Loads the panel shader and returns a synchronous factory for it.
///
/// Public because a caller building its own `Decoration3dPainter` — a
/// nine-slice, a mesh with the same object-space vertex colours — needs the
/// same material and the same per-box rule, and because it is the honest
/// place to look when panels stop drawing.
///
/// The instance the load itself produces is the first one the factory hands
/// out, so nothing is wasted.
///
/// ## The radiance-cube variant, and why it is threaded through by hand
///
/// `box_decoration3d.fmat` declares `shading_model: lit`, so the registry
/// resolves a second fragment shader for it — the variant used when the bound
/// environment carries a cubemap prefiltered radiance — and attaches it to
/// the instance it built. A material without that variant does not crash; it
/// falls back to the ordinary shader, which the engine's own comment says can
/// sample whatever texture the unit still held. So every instance this
/// factory makes is given the prototype's variant through the constructor,
/// which is the only way in: the setter that attaches it is `@internal`, and
/// this package is a consumer of the engine rather than a fork of it.
Future<PanelMaterialFactory> loadPanelMaterialFactory({
  AssetBundle? bundle,
}) async {
  PreprocessedMaterial Function(PreprocessedMaterial? like)? build;
  final prototype = await loadFmatMaterial(
    kPanelMaterialSource,
    bundle: bundle,
    factory: ({required fragmentShader, required metadata, vertexShaders}) {
      // The closure captures the three typed values the registry resolved,
      // which is exactly what a further instance needs and what nothing on
      // PreprocessedMaterial exposes afterwards. `like` carries the one thing
      // the registry attaches after construction.
      build = (like) => PreprocessedMaterial(
        fragmentShader: fragmentShader,
        metadata: metadata,
        vertexShaders: vertexShaders,
        radianceCubeFragmentShader: like?.radianceCubeFragmentShader,
      );
      return build!(null);
    },
  );
  final make = build;
  if (make == null) {
    // Defensive: the registry has always called the factory it was given,
    // and a version that stopped would otherwise fail as panels that are all
    // one colour rather than as an error.
    throw StateError(
      'loadFmatMaterial did not use the factory it was given, so '
      'flutter_scene_material3d cannot build a material per panel. Install '
      'BoxDecoration3d.painterFactory by hand.',
    );
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
