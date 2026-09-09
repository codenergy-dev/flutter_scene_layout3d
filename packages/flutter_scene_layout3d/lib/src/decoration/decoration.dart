import 'dart:math' as math;
import 'dart:ui' show Color, lerpDouble;

import 'package:flutter_scene/scene.dart' show Node;

import '../clip.dart';
import '../geometry/basis3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../metrics.dart';

/// A press ripple: a circle of state layer expanding from where the finger
/// landed.
///
/// The half of Material's state layer that one colour and one opacity cannot
/// express. A [StateLayer3d] washes the whole box; this washes a disc of it,
/// and a component grows [radius] over a few frames to make the wash arrive
/// from the point that was touched rather than everywhere at once.
///
/// It costs the same as the wash does — two more shader parameters on the
/// panel material, no second mesh and no second box — because the panel
/// shader already knows where in the box each fragment is. That is the whole
/// reason this is a value with three numbers in it rather than an ink feature
/// that paints itself.
///
/// **The colour is [StateLayer3d.color], not a colour of its own.** Material 3
/// describes the press state layer as *arriving* with a ripple, so the ripple
/// is the press wash with an origin rather than a second thing drawn over it.
/// Carrying a colour here would let the two drift apart with nothing to say
/// which was right.
///
/// **[origin] and [radius] are in world units**, unlike every figure on
/// [BoxDecoration3d], and the reason is where they come from: a press reports
/// its position through [PointerEvent3d.localPosition], which is in units and
/// stays exact for a surface seen at any angle, and the radius has to be
/// compared against a box's extent, which is in units too. Converting through
/// the metrics and back would be a round trip that could only lose precision.
/// `InkWell3d.minimumSize` in `flutter_scene_material3d` takes world units for
/// the same reason.
class Ripple3d {
  /// Creates a ripple centred on [origin] at [radius].
  const Ripple3d({
    required this.origin,
    required this.radius,
    this.opacity = 0.0,
  }) : assert(radius >= 0.0),
       assert(opacity >= 0.0 && opacity <= 1.0);

  /// Where the press landed, in the decorated box's **own frame**: the origin
  /// corner is `(0, 0, 0)`, which is the frame a hit test's local position and
  /// the clip planes are both already in.
  ///
  /// Only the two in-plane components are drawn — a ripple is a circle on the
  /// face, not a sphere in the slab — so the depth of the point the ray
  /// entered at is carried and ignored.
  final Offset3d origin;

  /// How far the ripple has expanded, in world units.
  final double radius;

  /// How much of [StateLayer3d.color] to blend inside the circle, from zero
  /// to one.
  final double opacity;

  /// Whether this ripple draws anything.
  bool get isNone => opacity == 0.0 || radius == 0.0;

  /// The radius at which a ripple centred on [origin] covers every corner of
  /// a box of [size].
  ///
  /// What a component grows a press ripple *to*: Material's ripple ends
  /// having covered the control, and a press near a corner therefore has
  /// further to travel than one in the middle. Measured on the face only, for
  /// the same reason [origin]'s depth is ignored.
  static double radiusCovering(Size3d size, Offset3d origin) {
    final dx = math.max(origin.x.abs(), (size.width - origin.x).abs());
    final dy = math.max(origin.y.abs(), (size.height - origin.y).abs());
    return math.sqrt(dx * dx + dy * dy);
  }

  /// A copy with the given fields replaced.
  Ripple3d copyWith({Offset3d? origin, double? radius, double? opacity}) =>
      Ripple3d(
        origin: origin ?? this.origin,
        radius: radius ?? this.radius,
        opacity: opacity ?? this.opacity,
      );

  /// Linearly interpolates between two ripples, either of which may be null.
  ///
  /// A missing end is treated as the other one at zero opacity and zero
  /// radius, so a ripple appearing or disappearing grows and shrinks from its
  /// own centre instead of sliding in from `(0, 0)`.
  static Ripple3d? lerp(Ripple3d? a, Ripple3d? b, double t) {
    if (a == null && b == null) return null;
    final from = a ?? Ripple3d(origin: b!.origin, radius: 0.0);
    final to = b ?? Ripple3d(origin: a!.origin, radius: 0.0);
    return Ripple3d(
      origin: Offset3d.lerp(from.origin, to.origin, t),
      radius: lerpDouble(
        from.radius,
        to.radius,
        t,
      )!.clamp(0.0, double.infinity),
      opacity: lerpDouble(from.opacity, to.opacity, t)!.clamp(0.0, 1.0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Ripple3d &&
      other.origin == origin &&
      other.radius == radius &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(origin, radius, opacity);

  @override
  String toString() => 'Ripple3d($origin, r: $radius, at: $opacity)';
}

/// The overlay a control paints over itself to say what is happening to it.
///
/// Material's state layers, unchanged: hover, focus, press and drag are the
/// same colour at four different opacities, blended over whatever the control
/// already looks like. Here they are a *uniform* — one colour and one number
/// handed to the decoration's material — and that is the whole point.
/// A second mesh would mean geometry per state; a second box would mean
/// layout per state. A uniform means a pressed button costs a parameter write
/// and a frame, and [DecoratedBox3d.stateLayer] enforces that by not marking
/// anything dirty for layout when it is set.
///
/// [ripple] is the one thing a single colour and a single opacity cannot say:
/// *where* the press landed. It rides on the same object, on the same tier,
/// and is drawn in the same [color] — see [Ripple3d].
class StateLayer3d {
  /// Creates a state layer.
  const StateLayer3d({
    this.color = const Color(0xFFFFFFFF),
    this.opacity = 0.0,
    this.ripple,
  }) : assert(opacity >= 0.0 && opacity <= 1.0);

  /// No overlay, and the default.
  static const StateLayer3d none = StateLayer3d(opacity: 0.0);

  /// The overlay colour, before [opacity] is applied.
  ///
  /// Material calls this the "on" colour of the surface underneath: the
  /// colour text would be drawn in, used at a low opacity as a wash.
  final Color color;

  /// How much of [color] to blend in, from zero to one.
  final double opacity;

  /// The press ripple in force, or null for none.
  ///
  /// Drawn **over** the uniform wash, in the same [color]: a hovered control
  /// that is pressed keeps its 8% everywhere and takes the press's 10% inside
  /// the expanding circle. A component that wants the press to be *only* the
  /// ripple resolves the uniform half without the pressed state, which is what
  /// `flutter_scene_material3d`'s ink controller does.
  ///
  /// Setting this is on the same tier as [opacity] — one uniform, one
  /// repaint — which is what makes an animated ripple legal at all. See
  /// [DecoratedBox3d.stateLayer].
  final Ripple3d? ripple;

  /// Whether this layer changes anything.
  bool get isNone => opacity == 0.0 && (ripple?.isNone ?? true);

  /// [color] with [opacity] folded into its alpha, which is the single value
  /// a shader wants.
  Color get resolvedColor => color.withValues(alpha: color.a * opacity);

  /// A copy with the given fields replaced.
  ///
  /// [ripple] cannot be cleared this way; construct a new layer for that, the
  /// way `copyWith` on a nullable field always has to be used.
  StateLayer3d copyWith({Color? color, double? opacity, Ripple3d? ripple}) =>
      StateLayer3d(
        color: color ?? this.color,
        opacity: opacity ?? this.opacity,
        ripple: ripple ?? this.ripple,
      );

  /// Linearly interpolates between two state layers.
  ///
  /// The colour is taken from [b] once there is any of it to see, because
  /// interpolating a colour that is about to be invisible is wasted work and
  /// produces a muddy midpoint on a cross-fade between two different states.
  static StateLayer3d lerp(StateLayer3d a, StateLayer3d b, double t) =>
      StateLayer3d(
        color: t < 0.5 ? a.color : b.color,
        opacity: lerpDouble(a.opacity, b.opacity, t)!.clamp(0.0, 1.0),
        ripple: Ripple3d.lerp(a.ripple, b.ripple, t),
      );

  @override
  bool operator ==(Object other) =>
      other is StateLayer3d &&
      other.color == color &&
      other.opacity == opacity &&
      other.ripple == ripple;

  @override
  int get hashCode => Object.hash(color, opacity, ripple);

  @override
  String toString() {
    if (isNone) return 'StateLayer3d.none';
    final ripple = this.ripple;
    return ripple == null
        ? 'StateLayer3d($color at $opacity)'
        : 'StateLayer3d($color at $opacity, $ripple)';
  }
}

/// The part of a decoration that stands off its parent.
///
/// Implemented by [BoxDecoration3d], and named separately so [DecoratedBox3d]
/// can lift any decoration that has a height without knowing what else is on
/// it. A decoration of your own that wants the same lift implements this and
/// reports a figure in logical pixels. The lift is a real displacement toward
/// the viewer and not a shadow; see [BoxDecoration3d.elevation] for why there
/// is no shadow to go with it.
abstract class Decoration3dElevation {
  /// How far the decoration stands off its parent, in logical pixels.
  double get elevation;
}

/// What a box looks like: a description, not the geometry that realizes it.
///
/// The 3D analogue of `Decoration`, and the same split. A decoration is an
/// immutable value that can be compared, interpolated and cached; a
/// [Decoration3dPainter] is the mutable thing that owns a mesh and a material
/// and keeps them in step with a box's size. `BoxDecoration3d` is the
/// concrete one, and it is the one every panel in a component library ends up
/// using.
///
/// The interface is open for the case a shader cannot express — a decoration
/// that has to generate a mesh, because it is a shape rather than a rounded
/// slab. Such a decoration is written exactly like this one, generates its
/// geometry inside its painter, and is subject to the same rule: it is handed
/// a size after every layout, so it had better compare against what it built
/// last time.
abstract class Decoration3d {
  /// Allows subclasses to be const.
  const Decoration3d();

  /// Whether moving from [old] to this one needs the painter's geometry
  /// rebuilt, as opposed to its parameters rewritten.
  ///
  /// The distinction is the plan this package's decorations are built on. A
  /// colour, a corner radius, a border width and an elevation are *uniforms*:
  /// they change what the shader draws over the same mesh, so the answer is
  /// false and a frame of animation costs nothing but a parameter write. Only
  /// a change to the shape of the thing being drawn — a different decoration
  /// class, a different mesh generator — needs a rebuild.
  bool shouldRebuild(covariant Decoration3d old);

  /// What two decorations must agree on to share a painter.
  ///
  /// A hundred cards with the same shape are a hundred boxes, one painter and
  /// one mesh. Keep this coarse: it names the *resources*, not the parameter
  /// values, so two decorations differing only in colour should return the
  /// same key and let the difference land in the uniforms.
  Object get cacheKey;

  /// Creates the painter that realizes this decoration, or null when nothing
  /// is available to draw it.
  ///
  /// Null is the normal answer in a headless test and on a surface built
  /// before `Scene.initializeStaticResources()` has resolved. A
  /// [DecoratedBox3d] with no painter lays out, sizes and hit-tests exactly
  /// as it otherwise would and draws nothing, which is the same bargain
  /// `Text3d` strikes with `Text3dRenderer`.
  Decoration3dPainter? createPainter();
}

/// Everything a painter needs to put one box's decoration in the scene.
///
/// Handed to [Decoration3dPainter.paint] after every layout of the box, and
/// valid only for the duration of that call: keep the numbers, not the
/// object.
class Decoration3dPaintRequest {
  /// Describes one paint.
  const Decoration3dPaintRequest({
    required this.node,
    required this.decoration,
    required this.size,
    required this.elevation,
    required this.stateLayer,
    required this.clip,
    required this.basis,
    required this.metrics,
  });

  /// The box's scene node, which the geometry hangs under.
  ///
  /// Its transform belongs to the layout and is rewritten on every placement;
  /// add children to it, do not move it.
  ///
  /// **A painter may be shared between boxes**, because the cache hands the
  /// same painter to every decoration with the same [Decoration3d.cacheKey].
  /// This node is therefore the identity a painter keys its per-box state on:
  /// one geometry for the painter, one material and one child node per node
  /// it is asked to paint. [Decoration3dPainter.release] says when one of
  /// them is finished with.
  final Node node;

  /// The decoration to realize, which is the one the painter was created for
  /// or another with the same cache key.
  final Decoration3d decoration;

  /// The box's extent in world units, in layout axes.
  final Size3d size;

  /// How far toward the viewer the box's geometry has been lifted, in world
  /// units.
  ///
  /// Already applied to [node] by the box — the geometry is where it says it
  /// is. It is reported because Material's elevation has a second half that
  /// is not a position: the surface tint that a raised panel takes on, which
  /// is a uniform on the same shader.
  final double elevation;

  /// The overlay in force, from [DecoratedBox3d.stateLayer].
  final StateLayer3d stateLayer;

  /// The clip the box sits inside, in the box's own layout frame.
  ///
  /// [Clip3dRegion.none] unless a [ClipBox3d] is above it. A painter whose
  /// material can honour clip planes packs it with
  /// [Clip3dRegion.toPlaneBlock]; one that cannot may ignore it, because the
  /// clip box has already hidden whatever falls entirely outside.
  final Clip3dRegion clip;

  /// The mapping from layout space to the surface's scene space.
  ///
  /// Geometry authored in scene axes — the engine's own primitives, a loaded
  /// model — has to undo this the way `NodeBox3d` does. Geometry generated in
  /// layout axes does not.
  final LayoutBasis3d basis;

  /// The unit contract, for a painter that needs to turn a spec figure into
  /// units itself or wants [Layout3dMetrics.logicalPixelsPerUnit] as a
  /// rasterization resolution.
  final Layout3dMetrics metrics;
}

/// Owns the mesh and material behind a [Decoration3d], and keeps them in step
/// with a box's size.
///
/// The seam. Measurement, elevation, state and clipping are arithmetic and
/// are tested headless; producing geometry needs a GPU context, which
/// `flutter test` does not have and a surface built before
/// `Scene.initializeStaticResources()` resolves does not either. Keeping the
/// box free of both is what lets the layout half be finished while the
/// drawing half is a choice — the same seam `Text3dRenderer` is.
///
/// Two rules a painter has to keep, and they are the whole reason the
/// interface looks like this:
///
///  * **A size change must not rebuild geometry.** [paint] is called after
///    every layout of every box using this painter, which on an animating
///    screen is every frame. Scale a shared mesh and rewrite parameters;
///    generating vertices here is what the shader path exists to avoid.
///  * **A painter may be shared.** Key everything per-box on
///    [Decoration3dPaintRequest.node], and drop it in [release].
abstract class Decoration3dPainter {
  /// Allows subclasses to be const.
  const Decoration3dPainter();

  /// Realizes [request], replacing whatever the last call for the same node
  /// put there.
  void paint(Decoration3dPaintRequest request);

  /// Says that [node] is no longer decorated by this painter.
  ///
  /// Called when the box changes decoration, is disposed, or drops out of the
  /// cache. Release the per-node material and geometry node here; the shared
  /// mesh survives until [dispose].
  void release(Node node);

  /// Releases the shared resources this painter built.
  ///
  /// Called by the cache when the last box using this painter has let go.
  void dispose();
}

/// The per-surface store that lets equal decorations share one painter.
///
/// A screen of Material components is a hundred boxes and a handful of
/// distinct shapes. Keying on [Decoration3d.cacheKey] collapses the hundred
/// onto the handful: one painter, one mesh, one material class, and a
/// parameter set per box. Reference counted, so the last box to let go of a
/// shape is what disposes it.
///
/// Lives on [Layout3dOwner], which is per-surface, for the same reason the
/// basis and the metrics do: it is tree-wide state that both the imperative
/// and the declarative layer have to reach without a `BuildContext`.
class Decoration3dPainterCache {
  final Map<Object, _CacheEntry> _entries = <Object, _CacheEntry>{};

  /// How many distinct painters are alive.
  int get length => _entries.length;

  /// The painter for [decoration], creating it if this is the first box to
  /// ask for that shape.
  ///
  /// Returns null when the decoration has no painter to give — a headless
  /// test, an engine that is not ready — and remembers nothing in that case,
  /// so the next box to ask tries again.
  Decoration3dPainter? acquire(Decoration3d decoration) {
    final key = decoration.cacheKey;
    final existing = _entries[key];
    if (existing != null) {
      existing.users++;
      return existing.painter;
    }
    final painter = decoration.createPainter();
    if (painter == null) return null;
    _entries[key] = _CacheEntry(painter);
    return painter;
  }

  /// Gives up one use of the painter for [decoration], on behalf of [node].
  ///
  /// The painter is told to drop what it built for that node, and is disposed
  /// once nothing is using it.
  void release(Decoration3d decoration, Node node) {
    final key = decoration.cacheKey;
    final entry = _entries[key];
    if (entry == null) return;
    entry.painter.release(node);
    entry.users--;
    if (entry.users > 0) return;
    _entries.remove(key);
    entry.painter.dispose();
  }

  /// Disposes every painter and empties the cache.
  void clear() {
    for (final entry in _entries.values) {
      entry.painter.dispose();
    }
    _entries.clear();
  }
}

class _CacheEntry {
  _CacheEntry(this.painter);

  final Decoration3dPainter painter;
  int users = 1;
}
