import 'dart:ui' show Size;

import 'package:flutter_scene/scene.dart' show Camera;
import 'package:vector_math/vector_math.dart' show Matrix4;

import 'geometry/constraints3d.dart';
import 'geometry/size3d.dart';
import 'metrics.dart';
import 'surface.dart';

/// Ties a [Layout3dSurface] to a camera, and with it the unit contract.
///
/// A surface is unbounded on all three axes until something bounds it, and
/// nothing in a scene naturally does: a scene is not a window. Flutter never
/// has this problem, because the screen bounds everything, and that is
/// exactly what a binding restores. Put the plane at a fixed distance in
/// front of the camera, oriented to it, and the view frustum at that distance
/// has an exact world width and height — so the surface has constraints, a
/// list on it has something to fill, and content reflows when the view
/// resizes, all for the same reasons they do in Flutter.
///
/// Once the surface covers the view, the unit contract stops being a choice.
/// The plane's world height spans exactly `viewSize.height` logical pixels,
/// so
///
/// ```
/// unitsPerLogicalPixel = worldHeight / viewSize.height
/// ```
///
/// and a 48dp Material touch target laid out as `metrics.dp(48)` units lands
/// as 48dp on the screen. That derivation is the reason this exists, and the
/// reason [Layout3dMetrics] is not simply a number somebody picks.
///
/// Three modes, which are the three honest ways a panel gets a scale:
///
///  * [Layout3dCameraBinding.screenFilling] — the panel *is* the screen. Sets
///    the plane's transform, the surface's constraints, and the metrics.
///  * [Layout3dCameraBinding.billboard] — the application owns where the
///    panel is, the camera owns which way it faces. Writes the plane's
///    transform and nothing else, so it never touches layout.
///  * [Layout3dCameraBinding.fixedDensity] — a panel on a wall is not a
///    screen, and its author says what it is drawn at. Writes the metrics and
///    nothing else.
///
/// Drive one per frame. Imperatively that is a call of your own:
///
/// ```dart
/// final binding = Layout3dCameraBinding.screenFilling(distance: 2);
///
/// void onFrame(Size viewSize) {
///   binding.update(surface, camera: camera, viewSize: viewSize);
///   surface.flush();
/// }
/// ```
///
/// Declaratively, hand it to `SceneLayout3d` along with the camera and it
/// runs itself.
///
/// A binding is an immutable description, not a live object, so the same
/// instance can be a `const` in a widget's build method and be applied to
/// whichever surface that widget owns. The hierarchy is closed: the three
/// modes are the ones this package derives honestly, and a fourth (a curved
/// surface, a per-eye viewport) would be a different contract, not another
/// case of this one.
abstract class Layout3dCameraBinding {
  const Layout3dCameraBinding._({
    this.textScaleFactor = 1.0,
    this.density = VisualDensity3d.standard,
  });

  /// A surface that covers the camera's view exactly, at [distance] in front
  /// of it.
  ///
  /// The constraints come from the view frustum at [distance] and are tight
  /// on width and height — a screen is a screen — and tight on [depth], which
  /// no frustum can supply and which therefore stays an explicit property.
  /// Leaving [depth] at zero gives a genuinely flat panel; give it a real
  /// thickness if content is to stand in it (see the depth trap in the
  /// README).
  ///
  /// The metrics fall out of the same arithmetic: the derived world height
  /// covers the view's logical height, so `unitsPerLogicalPixel` is their
  /// ratio. [textScaleFactor] and [density] are passed through, since neither
  /// is derivable from a camera.
  ///
  /// [extentEpsilon] is the dead band around the extents already in force: a
  /// newly derived extent within it of the standing one is taken to be the
  /// same extent and is not assigned. Without it the last bits of the view
  /// matrix jitter as the camera moves, every frame looks like a size change,
  /// and the whole tree relayouts for nothing.
  const factory Layout3dCameraBinding.screenFilling({
    double distance,
    double depth,
    double extentEpsilon,
    double textScaleFactor,
    VisualDensity3d density,
  }) = _ScreenFillingBinding;

  /// A surface that keeps its own position and turns to face the camera.
  ///
  /// Writes the plane's transform and nothing else: no constraints, no
  /// metrics, no layout. That is the point of it — a billboarded panel is
  /// cheap enough to update every frame for as many surfaces as the scene
  /// holds, because a node transform is not a layout.
  ///
  /// The facing is screen-aligned (the plane is made parallel to the view
  /// plane) rather than aimed at the eye point. Aiming at the eye makes a
  /// panel off to the side of the view lean, which foreshortens text and puts
  /// its two ends at different distances; keeping it parallel to the view
  /// plane keeps every panel in the scene rendering at the same scale as
  /// every other, which is what a HUD wants.
  ///
  /// Pair it with [Layout3dCameraBinding.fixedDensity], or an authored
  /// [Layout3dSurface.metrics], to give the panel a scale.
  const factory Layout3dCameraBinding.billboard() = _BillboardBinding;

  /// An authored scale: [unitsPerLogicalPixel] world units to the logical
  /// pixel, stated rather than derived.
  ///
  /// Writes the metrics and nothing else — no transform, no constraints — so
  /// it needs no camera and `update` may be called with none. For a panel
  /// hanging on a wall, lying on a table, or otherwise not standing in for a
  /// screen, this is the honest answer: there is no frustum to derive the
  /// number from, and inventing one from the current viewing distance would
  /// change the layout every time the viewer walked toward it.
  const factory Layout3dCameraBinding.fixedDensity(
    double unitsPerLogicalPixel, {
    double textScaleFactor,
    VisualDensity3d density,
  }) = _FixedDensityBinding;

  /// The default dead band around a derived extent, in world units.
  ///
  /// A ten-thousandth of a unit, which at the default metrics is a hundredth
  /// of a logical pixel: far below anything visible, and far above the
  /// floating-point noise a rotating view matrix puts in the last bits.
  ///
  /// A dead band rather than a rounding quantum, because rounding only moves
  /// the problem: an extent that happens to land near a quantum boundary
  /// flips across it on exactly the jitter the rounding was meant to absorb.
  /// Measuring against the extent already in force has no boundaries in it,
  /// the surface keeps covering the view exactly, and a slow genuine drift
  /// still lands, one epsilon at a time.
  static const double defaultExtentEpsilon = 1e-4;

  /// The accessibility text scale written into the surface's metrics.
  final double textScaleFactor;

  /// The visual density written into the surface's metrics.
  final VisualDensity3d density;

  /// Whether [update] needs a camera to do anything.
  ///
  /// False for [Layout3dCameraBinding.fixedDensity], which is authored rather
  /// than derived. The declarative layer checks this before insisting on a
  /// camera.
  bool get needsCamera => true;

  /// Whether [update] needs the view's logical size to do anything.
  ///
  /// True only for [Layout3dCameraBinding.screenFilling], which is the only
  /// mode whose result depends on the aspect ratio and on how many logical
  /// pixels the view is tall. A billboard takes only a facing from the
  /// camera, and an authored density takes nothing at all.
  bool get needsViewSize => false;

  /// Whether this binding writes the surface's [Layout3dSurface.configuration].
  ///
  /// True only for [Layout3dCameraBinding.screenFilling]. A surface bound
  /// that way must not also be given a size of its own, because the two would
  /// fight every frame.
  bool get derivesConstraints => false;

  /// Whether this binding writes the surface's [Layout3dSurface.metrics].
  bool get derivesMetrics => true;

  /// Applies this binding to [surface].
  ///
  /// Call it once per frame, before flushing. [camera] is required by every
  /// mode but [Layout3dCameraBinding.fixedDensity], and [viewSize] by
  /// [Layout3dCameraBinding.screenFilling] alone; [needsCamera] and
  /// [needsViewSize] say which. A degenerate view (zero area) or a singular
  /// view matrix is a no-op rather than an error, because both happen
  /// transiently while a view is being sized.
  ///
  /// Cheap when nothing moved. The plane's transform is compared before it is
  /// written, and [Layout3dSurface.configuration] and
  /// [Layout3dSurface.metrics] both early-out on an equal value, so a still
  /// camera dirties nothing at all and a turning one dirties only a node
  /// transform.
  void update(Layout3dSurface surface, {Camera? camera, Size? viewSize});
}

/// [value], unless it is within [epsilon] of the [standing] one, in which case
/// the standing one — so an extent that did not really change is not
/// reassigned.
///
/// An infinite [standing] value is the unbound state a surface starts in, and
/// never matches.
double _settle(double value, double standing, double epsilon) =>
    standing.isFinite && (value - standing).abs() < epsilon ? standing : value;

/// The plane-to-world transform that puts a surface square to [camera]'s
/// view, [distance] in front of the eye.
///
/// The columns are read out of the inverted view matrix, which is the one
/// place the camera's orthonormal frame is guaranteed to be consistent
/// whatever kind of [Camera] this is (a look-at camera, a node-driven one, a
/// caller's own subclass).
///
/// The signs are the counterpart of the ones in [LayoutBasis3d]. The engine
/// builds its view basis with `right = up x forward`, and the default basis
/// maps layout space through a full negation, so the plane's local `+x` has
/// to be the camera's *left* and its local `+z` the direction *back toward*
/// the eye for a `Row3d` to run left to right on screen and for layout depth
/// to run away from the viewer.
///
/// Returns null when the view matrix is singular.
Matrix4? _planeTransform(Camera camera, double distance) {
  final inverseView = Matrix4.zero();
  if (inverseView.copyInverse(camera.getViewMatrix()) == 0.0) return null;
  final right = inverseView.getColumn(0).xyz;
  final up = inverseView.getColumn(1).xyz;
  final forward = inverseView.getColumn(2).xyz;
  final eye = inverseView.getColumn(3).xyz;
  final origin = eye + forward * distance;
  return Matrix4(
    -right.x,
    -right.y,
    -right.z,
    0.0, //
    up.x,
    up.y,
    up.z,
    0.0, //
    -forward.x,
    -forward.y,
    -forward.z,
    0.0, //
    origin.x,
    origin.y,
    origin.z,
    1.0, //
  );
}

/// Writes [transform] onto [plane] unless it is already there.
///
/// Assigning a node transform invalidates the cached world transforms of the
/// whole subtree below it, so a binding that runs every frame on a camera
/// that did not move should not assign.
void _setPlaneTransform(Layout3dSurface surface, Matrix4? transform) {
  if (transform == null) return;
  if (surface.plane.localTransform == transform) return;
  surface.plane.localTransform = transform;
}

class _ScreenFillingBinding extends Layout3dCameraBinding {
  const _ScreenFillingBinding({
    this.distance = 1.0,
    this.depth = 0.0,
    this.extentEpsilon = Layout3dCameraBinding.defaultExtentEpsilon,
    super.textScaleFactor,
    super.density,
  }) : assert(
         distance > 0.0,
         'A screen-filling plane sits in front of the camera, so distance '
         'must be positive.',
       ),
       assert(depth >= 0.0),
       assert(extentEpsilon >= 0.0),
       super._();

  /// How far in front of the eye the plane sits, in world units.
  ///
  /// For a perspective camera the derived extents scale with it: twice as far
  /// is twice as wide and twice as tall, and the panel looks identical. It
  /// still matters, because it decides what the panel is in front of and
  /// behind, and because the unit contract scales with it too — a distant
  /// screen-filling plane is a coarse one, measured in world units.
  ///
  /// For an orthographic projection the extents do not depend on it at all,
  /// which is the reason a HUD wants one.
  final double distance;

  /// The plane's thickness, the one extent no frustum can supply.
  final double depth;

  /// The quantum the derived extents are rounded to.
  ///
  /// See [Layout3dCameraBinding.defaultExtentEpsilon].
  final double extentEpsilon;

  @override
  bool get derivesConstraints => true;

  @override
  bool get needsViewSize => true;

  @override
  void update(Layout3dSurface surface, {Camera? camera, Size? viewSize}) {
    assert(
      camera != null && viewSize != null,
      'Layout3dCameraBinding.screenFilling derives the surface from the view, '
      'so it needs both a camera and a view size.',
    );
    if (camera == null || viewSize == null) return;
    if (viewSize.isEmpty || !viewSize.isFinite) return;

    // The half-extents of the frustum at [distance], read out of the
    // projection matrix rather than out of a PerspectiveProjection's fov.
    // A point at view-space depth z lands at NDC x = (m00 * x + ...) / w with
    // w = m32 * z + m33, so the visible half-width there is w / m00 and the
    // half-height w / m11. For a perspective projection (m32 = 1, m33 = 0)
    // that is the familiar `z * tan(fov / 2)` pair; for an orthographic one
    // (m32 = 0, m33 = 1) it collapses to a constant, independent of distance,
    // with no branch needed here and none needed when the engine grows an
    // orthographic projection.
    final projection = camera.projection.getProjectionMatrix(
      viewSize.width / viewSize.height,
    );
    final scaleX = projection.entry(0, 0);
    final scaleY = projection.entry(1, 1);
    if (scaleX == 0.0 || scaleY == 0.0) return;
    final w = projection.entry(3, 2) * distance + projection.entry(3, 3);
    final width = (2.0 * w / scaleX).abs();
    final height = (2.0 * w / scaleY).abs();
    if (!width.isFinite || !height.isFinite) return;

    final standing = surface.configuration;
    final settledWidth = _settle(width, standing.maxWidth, extentEpsilon);
    final settledHeight = _settle(height, standing.maxHeight, extentEpsilon);

    surface.configuration = Constraints3d.tight(
      Size3d(settledWidth, settledHeight, depth),
    );
    // Derived from the settled height, not the raw one, so the metrics are as
    // stable as the constraints are: a metrics change relayouts too.
    surface.metrics = Layout3dMetrics(
      unitsPerLogicalPixel: settledHeight / viewSize.height,
      textScaleFactor: textScaleFactor,
      density: density,
    );
    _setPlaneTransform(surface, _planeTransform(camera, distance));
  }
}

class _BillboardBinding extends Layout3dCameraBinding {
  const _BillboardBinding() : super._();

  @override
  bool get derivesMetrics => false;

  @override
  void update(Layout3dSurface surface, {Camera? camera, Size? viewSize}) {
    assert(
      camera != null,
      'Layout3dCameraBinding.billboard takes its facing from the camera, so '
      'it needs one.',
    );
    if (camera == null) return;
    // Distance zero: the facing comes from the camera, the position stays
    // where the application put it, so the transform is rebuilt around the
    // plane's own translation.
    final facing = _planeTransform(camera, 0.0);
    if (facing == null) return;
    facing.setTranslation(surface.plane.localTransform.getTranslation());
    _setPlaneTransform(surface, facing);
  }
}

class _FixedDensityBinding extends Layout3dCameraBinding {
  const _FixedDensityBinding(
    this.unitsPerLogicalPixel, {
    super.textScaleFactor,
    super.density,
  }) : assert(unitsPerLogicalPixel > 0.0),
       super._();

  /// The authored scale: world units to the logical pixel.
  final double unitsPerLogicalPixel;

  @override
  bool get needsCamera => false;

  @override
  void update(Layout3dSurface surface, {Camera? camera, Size? viewSize}) {
    surface.metrics = Layout3dMetrics(
      unitsPerLogicalPixel: unitsPerLogicalPixel,
      textScaleFactor: textScaleFactor,
      density: density,
    );
  }
}
