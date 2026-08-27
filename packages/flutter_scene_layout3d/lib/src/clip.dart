import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' show Matrix4, Vector4;

import 'geometry/offset3d.dart';
import 'geometry/size3d.dart';
import 'layout3d.dart';

/// One half-space of a clip: everything on the negative side is clipped away.
///
/// A plane keeps the points where `dot(normal, p) + distance >= 0`, which is
/// the convention every clip-plane API uses (`gl_ClipDistance`, Godot's
/// `clip_plane`, Filament's scissor planes) and the one a fragment shader can
/// evaluate in a line. A region is an intersection of these, so it is always
/// convex — which is the whole reason clipping is expressible as planes at
/// all, and the reason a rounded corner is *not* a clip but a shape the
/// decoration shader carves out for itself.
///
/// The [normal] is in whatever frame the region is expressed in. Regions
/// travel down the tree in layout space, one box at a time, through
/// [Layout3d.clipRegion].
class ClipPlane3d {
  /// Creates a plane keeping `dot(normal, p) + distance >= 0`.
  ///
  /// [normal] is not normalized for you; [signedDistance] is only a true
  /// distance when it has unit length, and the axis-aligned constructors on
  /// [Clip3dRegion] always produce one that does.
  const ClipPlane3d(this.normal, this.distance);

  /// A plane whose kept side faces along [normal] from [point].
  factory ClipPlane3d.through(Offset3d point, Offset3d normal) =>
      ClipPlane3d(normal, -_dot(normal, point));

  /// The direction the kept side faces.
  final Offset3d normal;

  /// The plane's offset from the origin along [normal], negated.
  final double distance;

  /// How far [point] is on the kept side; negative means clipped away.
  double signedDistance(Offset3d point) => _dot(normal, point) + distance;

  /// This plane, translated by [delta].
  ///
  /// The normal is untouched and the offset slides, which is all a parent has
  /// to do when it hands its clip down: a child sitting at `offset` sees the
  /// same clip `shifted(-offset)`, because moving the frame forward is moving
  /// the plane back.
  ClipPlane3d shifted(Offset3d delta) =>
      ClipPlane3d(normal, distance - _dot(normal, delta));

  /// This plane, pulled back through [transform].
  ///
  /// [transform] maps the *new* frame into the frame this plane is expressed
  /// in, which is the direction a layout hands a clip down: the child's frame
  /// is mapped into the parent's by the parent's `localTransform`. A plane is
  /// a covector, so it pulls back by the transpose rather than pushing
  /// forward by the inverse — no matrix inversion, and it stays correct under
  /// a non-uniform scale, where the inverse-of-the-normal shortcut does not.
  ClipPlane3d transformed(Matrix4 transform) {
    final v = transform.transposed().transform(
      Vector4(normal.x, normal.y, normal.z, distance),
    );
    final length = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
    if (length == 0.0 || !length.isFinite) return this;
    return ClipPlane3d(
      Offset3d(v.x / length, v.y / length, v.z / length),
      v.w / length,
    );
  }

  static double _dot(Offset3d a, Offset3d b) =>
      a.x * b.x + a.y * b.y + a.z * b.z;

  @override
  bool operator ==(Object other) =>
      other is ClipPlane3d &&
      other.normal == normal &&
      other.distance == distance;

  @override
  int get hashCode => Object.hash(normal, distance);

  @override
  String toString() => 'ClipPlane3d($normal, $distance)';
}

/// The clip in force at a point in the layout tree: an intersection of
/// half-spaces, expressed in one box's own layout frame.
///
/// This is the contract the rest of the package clips against. It is a value,
/// it is computed on demand by walking up from a box ([Layout3d.clipRegion]),
/// and it says nothing about *how* the clip is enforced — which is
/// deliberate, because there are three tiers and a consumer picks the one it
/// can afford:
///
///  1. **Culling whole nodes.** [excludes] answers whether a box falls
///     entirely outside, and a `node.visible = false` follows. Costs nothing,
///     needs no engine support, and is what [ClipBox3d] does today. It is
///     also what the scrolling views already do by hand.
///  2. **Clip planes in the material.** [planes] is the uniform block: up to
///     [maxPlanes] `vec4`s, `xyz` the normal and `w` the distance, in the
///     frame the geometry is authored in. A fragment shader discards where
///     any plane reports negative. This is what clips *part* of a child — the
///     half of a list item sliding under a pinned header, the corner of a
///     menu — and it is the tier the engine does not yet provide.
///  3. **Doing nothing.** [isUnbounded] is the common case and is worth
///     testing for before anything else.
///
/// Everything here is exact arithmetic and is tested headless. The seam is
/// tier 2, which needs a material that reads the block; a decoration painter
/// is handed the region in its paint request and does with it what it can.
class Clip3dRegion {
  /// Creates a region from the half-spaces that bound it.
  const Clip3dRegion(this.planes);

  /// The whole of space: nothing is clipped.
  static const Clip3dRegion none = Clip3dRegion(<ClipPlane3d>[]);

  /// How many planes a consumer is required to honour.
  ///
  /// Six, which is exactly one axis-aligned box, because that is what every
  /// clip in a layout tree reduces to: [intersect] folds parallel planes
  /// together, so nesting a clipped list inside a clipped panel inside a
  /// clipped sheet still arrives as six. A region that exceeds this can only
  /// come from clipping through a rotation, and a consumer that cannot take
  /// them all should say so rather than drop planes silently.
  static const int maxPlanes = 6;

  /// The half-spaces, all of which a kept point must satisfy.
  final List<ClipPlane3d> planes;

  /// Whether nothing is clipped.
  bool get isUnbounded => planes.isEmpty;

  /// The four in-plane half-spaces of a box of [size] at the frame's origin.
  ///
  /// Depth is left alone, which is the right default for a window onto a
  /// plane: a raised card inside a scrolling list should still stand proud of
  /// it rather than be sliced off at the surface. Use [box] to clip the
  /// thickness as well.
  factory Clip3dRegion.rect(Size3d size) => Clip3dRegion(<ClipPlane3d>[
    const ClipPlane3d(Offset3d(1, 0, 0), 0.0),
    ClipPlane3d(const Offset3d(-1, 0, 0), size.width),
    const ClipPlane3d(Offset3d(0, 1, 0), 0.0),
    ClipPlane3d(const Offset3d(0, -1, 0), size.height),
  ]);

  /// All six half-spaces of a box of [size] at the frame's origin.
  factory Clip3dRegion.box(Size3d size) => Clip3dRegion(<ClipPlane3d>[
    ...Clip3dRegion.rect(size).planes,
    const ClipPlane3d(Offset3d(0, 0, 1), 0.0),
    ClipPlane3d(const Offset3d(0, 0, -1), size.depth),
  ]);

  /// Whether [point] survives every plane.
  bool contains(Offset3d point) {
    for (final plane in planes) {
      if (plane.signedDistance(point) < 0.0) return false;
    }
    return true;
  }

  /// Whether a box of [size] at [origin] is entirely inside the region, and
  /// so needs no clipping at all.
  bool containsBox(Offset3d origin, Size3d size) {
    for (final plane in planes) {
      if (_nearestCorner(plane, origin, size) < 0.0) return false;
    }
    return true;
  }

  /// Whether a box of [size] at [origin] falls entirely outside the region,
  /// and so can be hidden outright.
  ///
  /// Conservative in the safe direction: a box straddling two planes without
  /// violating either wholly is reported as *not* excluded, so nothing
  /// visible is ever hidden by mistake. The cost is that the odd box which is
  /// in fact outside a corner of the region is drawn anyway, which is a
  /// wasted draw call and never a wrong picture.
  bool excludes(Offset3d origin, Size3d size) {
    for (final plane in planes) {
      final farthest = _farthestCorner(plane, origin, size);
      if (farthest < 0.0) return true;
      // A box whose farthest corner lands exactly on a boundary meets the
      // clip in a face of zero volume, which is nothing to look at — so it is
      // out, and that is the ordinary case rather than an edge one: the first
      // row past the bottom of a two-unit window starts exactly at two. The
      // extent test is what keeps a *flat* box (a panel with no thickness,
      // clipped in depth against a plane with no thickness) from being
      // excluded by the same reasoning.
      if (farthest == 0.0 && _extentAlong(plane.normal, size) > 0.0) {
        return true;
      }
    }
    return false;
  }

  static double _extentAlong(Offset3d normal, Size3d size) =>
      normal.x.abs() * size.width +
      normal.y.abs() * size.height +
      normal.z.abs() * size.depth;

  /// This region, translated by [delta]; see [ClipPlane3d.shifted].
  Clip3dRegion shifted(Offset3d delta) {
    if (planes.isEmpty || delta == Offset3d.zero) return this;
    return Clip3dRegion(<ClipPlane3d>[
      for (final plane in planes) plane.shifted(delta),
    ]);
  }

  /// This region, pulled back through [transform]; see
  /// [ClipPlane3d.transformed].
  Clip3dRegion transformed(Matrix4 transform) {
    if (planes.isEmpty) return this;
    return Clip3dRegion(<ClipPlane3d>[
      for (final plane in planes) plane.transformed(transform),
    ]);
  }

  /// The region kept by both this and [other].
  ///
  /// Planes with the same normal are folded into the tighter of the two,
  /// which is what keeps nested axis-aligned clips at six planes however deep
  /// they are stacked. Order is preserved so the result is stable, which
  /// matters because a painter may key a cached uniform block on it.
  Clip3dRegion intersect(Clip3dRegion other) {
    if (other.planes.isEmpty) return this;
    if (planes.isEmpty) return other;
    final merged = <ClipPlane3d>[...planes];
    outer:
    for (final plane in other.planes) {
      for (var i = 0; i < merged.length; i++) {
        if (merged[i].normal == plane.normal) {
          // Same normal: the tighter plane is the one with the smaller
          // offset, since both keep the side the normal points at.
          if (plane.distance < merged[i].distance) merged[i] = plane;
          continue outer;
        }
      }
      merged.add(plane);
    }
    return Clip3dRegion(merged);
  }

  /// The plane block a material reads, `xyz` the normal and `w` the distance.
  ///
  /// Padded out to [maxPlanes] with a plane that keeps everything, so a
  /// shader can run a fixed-length loop with no branch. Throws when the
  /// region has more planes than that, rather than clipping less than it was
  /// asked to.
  List<double> toPlaneBlock() {
    if (planes.length > maxPlanes) {
      throw StateError(
        'A Clip3dRegion of ${planes.length} planes cannot be packed into a '
        'block of $maxPlanes. Intersecting axis-aligned clips folds to six; '
        'more than that means a clip was taken through a rotation.',
      );
    }
    final block = <double>[];
    for (final plane in planes) {
      block.addAll(<double>[
        plane.normal.x,
        plane.normal.y,
        plane.normal.z,
        plane.distance,
      ]);
    }
    while (block.length < maxPlanes * 4) {
      // A zero normal with a positive offset keeps every point, which is how
      // an unused slot disables itself.
      block.addAll(const <double>[0.0, 0.0, 0.0, 1.0]);
    }
    return block;
  }

  static double _nearestCorner(ClipPlane3d plane, Offset3d origin, Size3d s) {
    // The corner of the box that is least inside the half-space: take the low
    // end of each axis where the normal points positive, the high end where
    // it points negative.
    final x = origin.x + (plane.normal.x >= 0.0 ? 0.0 : s.width);
    final y = origin.y + (plane.normal.y >= 0.0 ? 0.0 : s.height);
    final z = origin.z + (plane.normal.z >= 0.0 ? 0.0 : s.depth);
    return plane.signedDistance(Offset3d(x, y, z));
  }

  static double _farthestCorner(ClipPlane3d plane, Offset3d origin, Size3d s) {
    final x = origin.x + (plane.normal.x >= 0.0 ? s.width : 0.0);
    final y = origin.y + (plane.normal.y >= 0.0 ? s.height : 0.0);
    final z = origin.z + (plane.normal.z >= 0.0 ? s.depth : 0.0);
    return plane.signedDistance(Offset3d(x, y, z));
  }

  @override
  String toString() =>
      isUnbounded ? 'Clip3dRegion.none' : 'Clip3dRegion(${planes.length})';
}

/// A box that clips its child to its own extent.
///
/// The 3D analogue of `ClipRect`, and the one place in this package that
/// publishes a [Clip3dRegion]. Layout is untouched: the child is laid out
/// against the same constraints and the box takes the child's size, exactly
/// as a `ProxyLayout3d` does. What changes is what the subtree below is
/// *allowed to be seen through*.
///
/// ```dart
/// ClipBox3d(
///   child: SizedBox3d(width: 2, height: 1, child: scrollingContent),
/// )
/// ```
///
/// Two things happen, and they are different tiers of the same contract:
///
///  * Every descendant's [Layout3d.clipRegion] now reports this box's extent,
///    so a decoration painter that can honour clip planes has the numbers.
///  * When [cullNodes] is set, descendants that fall entirely outside have
///    their scene node hidden, which also puts them out of reach of a ray —
///    the same rule the scrolling views already rely on. This is exact for
///    whole boxes and does nothing for a box that is half in, which is why it
///    is only the cheap tier.
///
/// Culling stops descending at a box that carries a transform of its own: the
/// clip is still published there (pulled back through the transform, which is
/// exact), but the visibility sweep does not try to reason about a rotated
/// subtree's extent.
class ClipBox3d extends ProxyLayout3d {
  /// Creates a box clipping [child] to its own extent.
  ClipBox3d({
    bool clipDepth = false,
    bool cullNodes = true,
    super.child,
    super.name,
  }) : _clipDepth = clipDepth,
       _cullNodes = cullNodes;

  bool _clipDepth;

  /// Whether the clip bounds the box's thickness as well as its face.
  ///
  /// False by default: a window onto a plane wants content that stands proud
  /// of it (a raised card, a shadow) to stay visible.
  bool get clipDepth => _clipDepth;

  set clipDepth(bool value) {
    if (_clipDepth == value) return;
    _clipDepth = value;
    markNeedsLayout();
  }

  bool _cullNodes;

  /// Whether descendants entirely outside the clip have their node hidden.
  bool get cullNodes => _cullNodes;

  set cullNodes(bool value) {
    if (_cullNodes == value) return;
    _cullNodes = value;
    if (!value) _restoreCulled();
    markNeedsLayout();
  }

  final Set<Layout3d> _culled = <Layout3d>{};

  /// The region this box imposes, in its own frame.
  Clip3dRegion get ownRegion => hasSize
      ? (_clipDepth ? Clip3dRegion.box(size) : Clip3dRegion.rect(size))
      : Clip3dRegion.none;

  @override
  Clip3dRegion clipRegionForChild(Layout3d child) => super
      .clipRegionForChild(child)
      .intersect(ownRegion.shifted(-child.offset));

  @override
  void performLayout() {
    super.performLayout();
    _restoreCulled();
    if (!_cullNodes) return;
    final child = this.child;
    if (child != null) _sweep(child, ownRegion);
  }

  /// Hides every box under [box] that falls entirely outside [region], with
  /// [region] expressed in [box]'s parent's frame.
  void _sweep(Layout3d box, Clip3dRegion region) {
    if (!box.hasSize) return;
    final here = region.shifted(-box.offset);
    if (here.excludes(Offset3d.zero, box.size)) {
      if (box.node.visible) {
        box.node.visible = false;
        _culled.add(box);
      }
      return;
    }
    // No early exit for a box that is wholly inside: a child may overflow its
    // parent's extent (a Column3d taller than the room it was given is the
    // ordinary case here), so a parent being inside says nothing about where
    // its children ended up.
    final local = box.localTransform;
    if (local != null) return;
    box.visitChildren((child) => _sweep(child, here));
  }

  void _restoreCulled() {
    for (final box in _culled) {
      box.node.visible = true;
    }
    _culled.clear();
  }

  @override
  void dispose() {
    _culled.clear();
    super.dispose();
  }
}
