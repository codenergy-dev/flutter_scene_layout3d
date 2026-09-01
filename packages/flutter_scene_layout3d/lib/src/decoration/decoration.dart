import 'dart:ui' show Color, lerpDouble;

import 'package:flutter_scene/scene.dart' show Node;

import '../clip.dart';
import '../geometry/basis3d.dart';
import '../geometry/size3d.dart';
import '../metrics.dart';

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
class StateLayer3d {
  /// Creates a state layer.
  const StateLayer3d({this.color = const Color(0xFFFFFFFF), this.opacity = 0.0})
    : assert(opacity >= 0.0 && opacity <= 1.0);

  /// No overlay, and the default.
  static const StateLayer3d none = StateLayer3d(opacity: 0.0);

  /// The overlay colour, before [opacity] is applied.
  ///
  /// Material calls this the "on" colour of the surface underneath: the
  /// colour text would be drawn in, used at a low opacity as a wash.
  final Color color;

  /// How much of [color] to blend in, from zero to one.
  final double opacity;

  /// Whether this layer changes anything.
  bool get isNone => opacity == 0.0;

  /// [color] with [opacity] folded into its alpha, which is the single value
  /// a shader wants.
  Color get resolvedColor => color.withValues(alpha: color.a * opacity);

  /// A copy with the given fields replaced.
  StateLayer3d copyWith({Color? color, double? opacity}) => StateLayer3d(
    color: color ?? this.color,
    opacity: opacity ?? this.opacity,
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
      );

  @override
  bool operator ==(Object other) =>
      other is StateLayer3d && other.color == color && other.opacity == opacity;

  @override
  int get hashCode => Object.hash(color, opacity);

  @override
  String toString() =>
      isNone ? 'StateLayer3d.none' : 'StateLayer3d($color at $opacity)';
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
