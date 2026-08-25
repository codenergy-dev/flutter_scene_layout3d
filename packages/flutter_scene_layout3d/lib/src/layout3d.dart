import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show VoidCallback, mustCallSuper, protected;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:vector_math/vector_math.dart' show Matrix4;

import 'geometry/basis3d.dart';
import 'geometry/constraints3d.dart';
import 'geometry/offset3d.dart';
import 'geometry/size3d.dart';
import 'hit_test.dart';

/// Builds the layout for one item of a lazily built view.
///
/// The one signature shared by every builder in the package:
/// `ListView3d.builder`, `GridView3d.builder`, `SliverList3d.builder` and
/// `SliverGrid3d.builder` all hand out an index and take a box back.
typedef Layout3dItemBuilder = Layout3d Function(int index);

/// Data a parent layout stores on its child, the 3D analogue of [ParentData].
///
/// Every child carries at least its [offset], the position its parent gave
/// it. Layouts that need more per-child state subclass this: `Flex3d` adds
/// the flex factor, `Stack3d` adds the positioning fields.
class ParentData3d {
  /// The child's origin corner, in the parent's layout space.
  ///
  /// Written by the parent through [Layout3d.place], never by the child.
  Offset3d offset = Offset3d.zero;

  /// An extra offset applied to the child's scene node and to nothing else.
  ///
  /// Measured in layout axes, like [offset], but the layout protocol never
  /// sees it: the child's box still sits at [offset], intrinsics ignore it,
  /// and a hit test walks straight past it. It moves the *geometry*, not the
  /// box.
  ///
  /// That distinction is what [Stack3d.depthStep] is built on. Coplanar
  /// children fight for the depth buffer and have to be separated in the
  /// scene, but separating them in the layout would push them out of their
  /// parent's box, break a [Positioned3d] pin, and take the topmost child out
  /// of reach of a ray. Nudging the node alone leaves every one of those
  /// intact.
  ///
  /// Written by the parent before [Layout3d.place], which is what applies it.
  Offset3d sceneOffset = Offset3d.zero;

  /// Called when the child is removed from its parent.
  @mustCallSuper
  void detach() {}

  @override
  String toString() => sceneOffset == Offset3d.zero
      ? 'offset=$offset'
      : 'offset=$offset, sceneOffset=$sceneOffset';
}

/// Drives layout for a tree of [Layout3d] objects, the 3D analogue of
/// [PipelineOwner].
///
/// The owner collects the layouts that went dirty, and [flushLayout] relayouts
/// them shallowest first. Everything downstream of layout, the scene node
/// transforms, is written as layout happens, so there is no separate paint
/// phase to flush.
class Layout3dOwner {
  /// Creates an owner, optionally reporting when a relayout is pending.
  Layout3dOwner({this.onNeedVisualUpdate});

  /// Called when a layout goes dirty, so a host can schedule [flushLayout].
  ///
  /// The widget layer wires this to the Flutter pipeline; imperative users
  /// can leave it null and call [flushLayout] themselves.
  VoidCallback? onNeedVisualUpdate;

  /// The mapping from layout space to the surface node's scene space, owned
  /// by the root and read by leaves when they place engine content.
  LayoutBasis3d basis = LayoutBasis3d.xy;

  final List<Layout3d> _nodesNeedingLayout = <Layout3d>[];

  bool _doingLayout = false;

  /// Whether [flushLayout] is running.
  bool get debugDoingLayout => _doingLayout;

  /// Whether any layout in this tree is waiting to be laid out.
  bool get hasPendingLayout => _nodesNeedingLayout.isNotEmpty;

  /// Requests that the host schedule a [flushLayout].
  void requestVisualUpdate() => onNeedVisualUpdate?.call();

  /// Lays out every dirty layout, shallowest first, until none are left.
  ///
  /// Relayouts started while flushing (a layout that dirtied a subtree deeper
  /// than itself) are picked up by the same call.
  void flushLayout() {
    if (_doingLayout) return;
    _doingLayout = true;
    try {
      while (_nodesNeedingLayout.isNotEmpty) {
        final dirty = List<Layout3d>.of(_nodesNeedingLayout)
          ..sort((a, b) => a.treeDepth - b.treeDepth);
        _nodesNeedingLayout.clear();
        for (final layout in dirty) {
          if (layout._needsLayout && identical(layout._owner, this)) {
            layout._layoutWithoutResize();
          }
        }
      }
    } finally {
      _doingLayout = false;
    }
  }
}

/// A box in a 3D layout tree: Flutter's layout protocol, one axis richer.
///
/// The contract is the one every Flutter developer already knows. A parent
/// hands down [Constraints3d]; the child picks a [Size3d] that satisfies them
/// and reports it up; the parent then decides where the child sits and calls
/// [place]. A child never reads its own position during [performLayout], and a
/// parent never reads anything of the child's but its [size] (and only if it
/// passed `parentUsesSize: true`).
///
/// What is new in 3D is the output. Each layout owns a scene [Node], and a
/// child's node is a child of its parent's node, so [place] writing an offset
/// *is* the placement: the transforms compose down the graph the same way the
/// layout composes. Moving, rotating, or scaling the surface's node carries
/// the whole tree with it.
///
/// Subclass [SingleChildLayout3d] or [MultiChildLayout3d] rather than this
/// class directly unless the box is a leaf.
abstract class Layout3d {
  /// Creates a layout, optionally naming its scene [Node].
  Layout3d({String? name}) : _node = Node() {
    _node.name = name ?? '$runtimeType';
  }

  final Node _node;

  /// The scene node this layout positions.
  ///
  /// Owned by the layout: its `localTransform` is rewritten on every
  /// placement, so do not set the transform yourself. Reading it (to attach
  /// components, or to hang extra content under it) is fine.
  Node get node => _node;

  Layout3d? _parent;

  /// The layout that owns and positions this one, or null at the root.
  Layout3d? get parent => _parent;

  Layout3dOwner? _owner;

  /// The owner driving layout for this tree, or null while detached.
  Layout3dOwner? get owner => _owner;

  /// Whether this layout is attached to an owner.
  bool get attached => _owner != null;

  /// The mapping from layout space to scene space in force for this tree.
  ///
  /// Falls back to [LayoutBasis3d.xy] while detached.
  LayoutBasis3d get basis => _owner?.basis ?? LayoutBasis3d.xy;

  int _depth = 0;

  /// Distance from the root, used to relayout parents before children.
  ///
  /// Named `treeDepth` rather than Flutter's `depth`, which in this package
  /// is an extent along `z`.
  int get treeDepth => _depth;

  /// The state this layout's parent keeps about it, including its [offset].
  ///
  /// Installed by the parent in [setupParentData]; null while unparented.
  ParentData3d? parentData;

  Size3d? _size;

  /// The extent this layout chose in its most recent [performLayout].
  ///
  /// Reading this from anywhere but the layout itself or its parent (and only
  /// when the parent passed `parentUsesSize: true`) breaks the protocol.
  Size3d get size {
    assert(
      _size != null,
      '$runtimeType has not been laid out yet, so it has no size.',
    );
    return _size ?? Size3d.zero;
  }

  /// Records the size chosen during [performLayout].
  @protected
  set size(Size3d value) {
    assert(value.isNonNegative, '$runtimeType chose a negative size: $value.');
    _size = value;
  }

  /// Whether this layout has been laid out at least once.
  bool get hasSize => _size != null;

  Constraints3d? _constraints;

  /// The constraints most recently handed down by the parent.
  Constraints3d get constraints {
    assert(
      _constraints != null,
      '$runtimeType has not been laid out yet, so it has no constraints.',
    );
    return _constraints ?? const Constraints3d();
  }

  /// Whether the size depends only on the constraints.
  ///
  /// When true, [performResize] sets the size and [performLayout] only
  /// positions children, which lets the tree skip resizing work the same way
  /// Flutter's `sizedByParent` does.
  bool get sizedByParent => false;

  bool _needsLayout = true;

  /// Whether this layout is waiting to be laid out.
  bool get needsLayout => _needsLayout;

  Layout3d? _relayoutBoundary;

  /// Whether the child's own tree layer can pull the transform under the
  /// parent's offset. Overridden by layouts that add a transform of their
  /// own, such as `Transform3d` and `Container3d`.
  @protected
  Matrix4? get localTransform => null;

  // ---------------------------------------------------------------- tree

  /// Installs the [ParentData3d] subclass this layout keeps on its children.
  ///
  /// Called for each child as it is adopted.
  @protected
  void setupParentData(Layout3d child) {
    child.parentData ??= ParentData3d();
  }

  /// Takes ownership of [child]: parents it here, hangs its node under this
  /// one, and joins it to this tree's owner.
  @protected
  @mustCallSuper
  void adoptChild(Layout3d child) {
    assert(
      child._parent == null,
      'Cannot adopt $child, it already has a parent (${child._parent}).',
    );
    child.parentData = null;
    setupParentData(child);
    child._parent = this;
    child._redepth(_depth + 1);
    _node.add(child._node);
    if (_owner != null) child.attach(_owner!);
    markNeedsLayout();
  }

  /// Releases [child]: unparents it and unhooks its node.
  @protected
  @mustCallSuper
  void dropChild(Layout3d child) {
    assert(identical(child._parent, this));
    _node.remove(child._node);
    child.parentData?.detach();
    child.parentData = null;
    child._parent = null;
    child._relayoutBoundary = null;
    if (child._owner != null) child.detach();
    markNeedsLayout();
  }

  void _redepth(int depth) {
    if (_depth == depth) return;
    _depth = depth;
    visitChildren((child) => child._redepth(depth + 1));
  }

  /// Calls [visitor] for each child, in layout order.
  void visitChildren(void Function(Layout3d child) visitor) {}

  /// Joins this subtree to [owner].
  @mustCallSuper
  void attach(Layout3dOwner owner) {
    _owner = owner;
    if (_needsLayout && _relayoutBoundary != null) {
      _needsLayout = false;
      markNeedsLayout();
    }
    visitChildren((child) => child.attach(owner));
  }

  /// Detaches this subtree from its owner.
  @mustCallSuper
  void detach() {
    _owner = null;
    visitChildren((child) => child.detach());
  }

  bool _debugDisposed = false;

  /// Whether [dispose] has been called on this layout, in debug builds.
  ///
  /// Always false in release, where the flag is not kept.
  bool get debugDisposed {
    var disposed = false;
    assert(() {
      disposed = _debugDisposed;
      return true;
    }());
    return disposed;
  }

  /// Releases this subtree's scene resources.
  ///
  /// A layout only ever disposes what it created. Engine content handed to a
  /// leaf (a model loaded by the application, say) is detached, never
  /// disposed.
  ///
  /// A disposed layout is finished: it is not laid out again and not put back
  /// in a tree. It is not unparented here, because whoever disposes it is the
  /// one that removed it, and the lazy views do exactly that. What this does
  /// catch is using one afterwards, which otherwise fails much later and
  /// somewhere else.
  @mustCallSuper
  void dispose() {
    assert(
      !_debugDisposed,
      '$runtimeType was disposed twice. A layout is disposed by whoever '
      'removed it from the tree, and only once.',
    );
    visitChildren((child) => child.dispose());
    _node.removeAll();
    assert(() {
      _debugDisposed = true;
      return true;
    }());
  }

  // -------------------------------------------------------------- layout

  /// Forces the next [layout] call to run [performLayout], even when the
  /// constraints have not changed.
  ///
  /// For protocols layered on top of the box one, where the constraints that
  /// actually changed are not [Constraints3d]: a sliver relaid out at a new
  /// scroll offset has the same box constraints as before, and would
  /// otherwise be skipped. Unlike [markNeedsLayout] this tells nobody, since
  /// the caller is the parent that is about to lay this layout out.
  @protected
  void invalidateLayout() {
    _needsLayout = true;
  }

  /// Marks this layout as needing to be laid out again.
  ///
  /// Stops at the nearest relayout boundary: a tightly constrained ancestor
  /// (or one that does not use its child's size) absorbs the dirt, so a deep
  /// change does not relayout the whole plane.
  void markNeedsLayout() {
    assert(
      !_debugDisposed,
      '$runtimeType was marked as needing layout after it was disposed.',
    );
    // Anything cached here was asked for by the parent, which means the
    // parent's own layout was decided from an answer that is now stale. The
    // dirt therefore has to go up, however tightly this box is constrained:
    // a relayout boundary bounds the *sizes* that flow up, not the questions
    // that were asked before them. Flutter's `RenderBox` does exactly this.
    if (_clearIntrinsicsCache() && _parent != null) {
      markParentNeedsLayout();
      return;
    }
    if (_needsLayout) return;
    final boundary = _relayoutBoundary;
    if (boundary == null) {
      _needsLayout = true;
      if (_parent != null) markParentNeedsLayout();
      return;
    }
    if (!identical(boundary, this)) {
      markParentNeedsLayout();
      return;
    }
    _needsLayout = true;
    final owner = _owner;
    if (owner != null) {
      owner._nodesNeedingLayout.add(this);
      owner.requestVisualUpdate();
    }
  }

  /// Marks this layout dirty and pushes the dirt up to the parent, for
  /// changes that alter the size this layout reports.
  @protected
  void markParentNeedsLayout() {
    _needsLayout = true;
    _clearIntrinsicsCache();
    final parent = _parent;
    if (parent == null) {
      final owner = _owner;
      if (owner != null) {
        owner._nodesNeedingLayout.add(this);
        owner.requestVisualUpdate();
      }
      return;
    }
    parent.markNeedsLayout();
  }

  /// Computes this layout's size and lays out its children.
  ///
  /// The entry point a parent calls. Pass `parentUsesSize: true` when the
  /// parent's own size or child positions depend on the size this call
  /// produces; that is what decides where relayout boundaries land.
  void layout(Constraints3d constraints, {bool parentUsesSize = false}) {
    assert(!_debugDisposed, '$runtimeType was laid out after it was disposed.');
    assert(
      constraints.isNormalized,
      '$runtimeType was given non-normalized constraints: $constraints.',
    );
    final isBoundary =
        !parentUsesSize ||
        sizedByParent ||
        constraints.isTight ||
        _parent == null;
    final relayoutBoundary = isBoundary ? this : _parent!._relayoutBoundary!;
    if (!_needsLayout && constraints == _constraints) {
      if (!identical(relayoutBoundary, _relayoutBoundary)) {
        _relayoutBoundary = relayoutBoundary;
        visitChildren(_propagateRelayoutBoundaryToChild);
      }
      return;
    }
    _constraints = constraints;
    if (_relayoutBoundary != null &&
        !identical(relayoutBoundary, _relayoutBoundary)) {
      visitChildren(_cleanChildRelayoutBoundary);
    }
    _relayoutBoundary = relayoutBoundary;
    if (sizedByParent) {
      performResize();
    }
    performLayout();
    _needsLayout = false;
  }

  void _layoutWithoutResize() {
    assert(_relayoutBoundary != null && identical(_relayoutBoundary, this));
    // A layout that has never been given constraints has nothing to redo;
    // its first layout comes from its parent.
    if (_constraints == null) return;
    performLayout();
    _needsLayout = false;
  }

  static void _propagateRelayoutBoundaryToChild(Layout3d child) {
    if (identical(child._relayoutBoundary, child)) return;
    final parentBoundary = child._parent!._relayoutBoundary;
    if (identical(parentBoundary, child._relayoutBoundary)) return;
    child._relayoutBoundary = parentBoundary;
    child.visitChildren(_propagateRelayoutBoundaryToChild);
  }

  static void _cleanChildRelayoutBoundary(Layout3d child) {
    if (!identical(child._relayoutBoundary, child)) {
      child._relayoutBoundary = null;
      child.visitChildren(_cleanChildRelayoutBoundary);
    }
  }

  /// Sets [size] from the constraints alone, for layouts that are
  /// [sizedByParent].
  @protected
  void performResize() {
    assert(
      !sizedByParent,
      '$runtimeType is sizedByParent but does not implement performResize.',
    );
  }

  /// Sizes this layout and positions its children.
  ///
  /// Lay each child out with the constraints it should honour, read its
  /// [size] only if you asked for it, set this layout's [size], and call
  /// [place] on each child.
  @protected
  void performLayout();

  // ---------------------------------------------------------- intrinsics

  final Map<(Axis3d, bool, Size3d), double> _cachedIntrinsics =
      <(Axis3d, bool, Size3d), double>{};

  final Map<Axis3d, double?> _cachedBaselines = <Axis3d, double?>{};

  /// Empties the intrinsic and baseline caches, reporting whether anything
  /// was in them.
  bool _clearIntrinsicsCache() {
    if (_cachedIntrinsics.isEmpty && _cachedBaselines.isEmpty) return false;
    _cachedIntrinsics.clear();
    _cachedBaselines.clear();
    return true;
  }

  /// The smallest extent along [axis] in which this box can present its
  /// content without giving up anything it would otherwise fit, the 3D
  /// analogue of [RenderBox.getMinIntrinsicWidth] and its siblings.
  ///
  /// The pair of questions is Flutter's, one axis at a time: the minimum is
  /// the extent below which the box would have to sacrifice something (a
  /// column would start compressing its children), and
  /// [getMaxIntrinsicExtent] is the extent beyond which more room buys
  /// nothing.
  ///
  /// [limits] carries what the box would be offered on the *other two* axes;
  /// its own component along [axis] is ignored, since that is the question
  /// being asked. The default asks with nothing else constrained.
  ///
  /// This is a speculation, not a layout: nothing is sized, nothing is
  /// placed. It is also expensive, because answering walks the entire
  /// subtree, which is why the answer is cached until the next
  /// [markNeedsLayout] and why so few boxes ask. Do not call it from
  /// [performLayout] unless the box exists to (see [IntrinsicExtent3d]);
  /// laying a child out and reading its [size] is the cheap way to find out
  /// how big it is.
  double getMinIntrinsicExtent(
    Axis3d axis, [
    Size3d limits = Size3d.infinite,
  ]) => _intrinsicExtent(axis, limits, min: true);

  /// The extent along [axis] beyond which giving this box more room does not
  /// change what it does with it, the 3D analogue of
  /// [RenderBox.getMaxIntrinsicWidth].
  ///
  /// See [getMinIntrinsicExtent] for what [limits] means and what this costs.
  double getMaxIntrinsicExtent(
    Axis3d axis, [
    Size3d limits = Size3d.infinite,
  ]) => _intrinsicExtent(axis, limits, min: false);

  double _intrinsicExtent(Axis3d axis, Size3d limits, {required bool min}) {
    // The component along the queried axis is not part of the question, so
    // it is zeroed before it reaches the cache key: two callers who differ
    // only there are asking the same thing.
    final others = limits.withAxis(axis, 0.0);
    assert(
      others.isNonNegative,
      'Intrinsic limits must be non-negative, but $limits was given for '
      '$axis on $runtimeType.',
    );
    final key = (axis, min, others);
    final cached = _cachedIntrinsics[key];
    if (cached != null) return cached;
    final result = min
        ? computeMinIntrinsicExtent(axis, others)
        : computeMaxIntrinsicExtent(axis, others);
    assert(
      result.isFinite && result >= 0.0,
      '$runtimeType reported $result as its intrinsic extent along $axis, '
      'which is not a finite non-negative extent.',
    );
    _cachedIntrinsics[key] = result;
    return result;
  }

  /// Computes [getMinIntrinsicExtent]. Override this; call the getter.
  ///
  /// Zero by default, as in Flutter: a box that has not been taught to
  /// measure itself claims to need nothing.
  @protected
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) => 0.0;

  /// Computes [getMaxIntrinsicExtent]. Override this; call the getter.
  @protected
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) => 0.0;

  // ----------------------------------------------------------- baselines

  /// How far along [axis] this box's baseline sits, measured from its origin
  /// corner, the 3D analogue of [RenderBox.getDistanceToBaseline].
  ///
  /// A baseline is a line content declares so that neighbours can line up on
  /// it rather than on their edges. Flutter has one, running across a box at
  /// the foot of its text; a box here can declare one on any axis, because
  /// there are three ways for a row of content to be side by side.
  ///
  /// Null means this box has no baseline of its own, which is the default.
  /// With [onlyReal] false, the answer for such a box is its far edge along
  /// [axis] — the same substitution Flutter makes, and what lets a
  /// baseline-aligned line mix content that has a baseline with content that
  /// does not.
  double? getDistanceToBaseline(Axis3d axis, {bool onlyReal = false}) {
    final double? distance;
    if (_cachedBaselines.containsKey(axis)) {
      distance = _cachedBaselines[axis];
    } else {
      distance = computeDistanceToActualBaseline(axis);
      _cachedBaselines[axis] = distance;
    }
    if (distance == null && !onlyReal) return size.alongAxis(axis);
    return distance;
  }

  /// Computes [getDistanceToBaseline]. Override this; call the getter.
  ///
  /// Return null for a box with no baseline of its own. A box that wraps
  /// another usually returns the child's, moved by wherever it placed the
  /// child; [Layout3dChildIntrinsicsMixin] does that.
  @protected
  double? computeDistanceToActualBaseline(Axis3d axis) => null;

  // ------------------------------------------------------------ placement

  /// The offset this layout's parent gave it.
  Offset3d get offset => parentData?.offset ?? Offset3d.zero;

  /// Positions this layout's origin corner at [offset] in the parent's layout
  /// space, and writes the corresponding scene transform.
  ///
  /// Called by the parent during [performLayout]. Because layout offsets are
  /// expressed in layout space all the way down and the surface applies the
  /// [LayoutBasis3d] once at the root, this is a plain translation.
  void place(Offset3d offset) {
    final data = parentData ??= ParentData3d();
    data.offset = offset;
    applyNodeTransform();
  }

  /// The offset the parent applies to this layout's scene node on top of
  /// [offset], which layout and hit testing never see.
  ///
  /// See [ParentData3d.sceneOffset].
  Offset3d get sceneOffset => parentData?.sceneOffset ?? Offset3d.zero;

  /// Rewrites this layout's node transform from its offset and
  /// [localTransform].
  ///
  /// Call after changing anything [localTransform] depends on.
  @protected
  void applyNodeTransform() {
    final position = offset + sceneOffset;
    final transform = Matrix4.translationValues(
      position.x,
      position.y,
      position.z,
    );
    final local = localTransform;
    if (local != null) {
      transform.multiply(local);
    }
    _node.localTransform = transform;
  }

  // ------------------------------------------------------------ hit testing

  /// The layout-space transform between this box's own frame and the frame
  /// its children are placed in.
  ///
  /// Defaults to [localTransform], which is what a `Transform3d` puts between
  /// itself and its child. The box's own [size] is measured in the frame
  /// *before* this transform, exactly as Flutter measures a
  /// `RenderTransform`'s size in the untransformed frame, so a child rotated
  /// out of its parent's box is not reachable.
  @protected
  Matrix4? get hitTestTransform => localTransform;

  /// The transform taking this box's own frame to world space.
  ///
  /// The box's node carries `T(offset + sceneOffset) * localTransform`, so the
  /// node's world transform describes the frame this box's *children* sit in;
  /// undoing [hitTestTransform] backs up one step to the frame this box
  /// measures itself in, the one [HitTestEntry3d.localPosition] is expressed
  /// in, and undoing [sceneOffset] discards the nudge the parent applied to
  /// the geometry alone.
  ///
  /// Only meaningful once the surface has been mounted in a scene and laid
  /// out. Inverting it takes a world-space ray into this box's frame, which
  /// is how a drag keeps tracking a box after the pointer has left it.
  Matrix4 get worldTransform {
    var world = Matrix4.copy(_node.globalTransform);
    final local = hitTestTransform;
    if (local != null) {
      final inverse = Matrix4.zero();
      if (inverse.copyInverse(local) == 0.0) return world;
      world = world.multiplied(inverse);
    }
    final nudge = sceneOffset;
    if (nudge == Offset3d.zero) return world;
    // Translations commute, so undoing the nudge on the right of
    // `T(offset + sceneOffset)` leaves `T(offset)`: the layout frame.
    return world.multiplied(
      Matrix4.translationValues(-nudge.x, -nudge.y, -nudge.z),
    );
  }

  /// Whether [ray] reaches this box or anything below it, recording what it
  /// found in [result].
  ///
  /// The 3D analogue of [RenderBox.hitTest], and the same contract: children
  /// are asked first, front to back, so the box on top wins; the entry for
  /// this layout is added after them, which leaves [result] ordered deepest
  /// first. [ray] arrives in this box's own frame, where the origin corner is
  /// `(0, 0, 0)`.
  ///
  /// A ray that misses this box's extent never reaches its children, and the
  /// stretch of the ray inside the box is all a child can be found in. That
  /// is what Flutter's `size.contains(position)` gate does in two dimensions.
  /// A box carrying a [hitTestTransform] is the exception on both counts; see
  /// there.
  bool hitTest(HitTestResult3d result, {required Ray3d ray}) {
    if (!hasSize) return false;
    final transform = hitTestTransform;
    if (transform != null) {
      // A transforming box does not answer for itself, and does not gate its
      // children on its own extent. Flutter's `RenderTransform` makes the
      // same choice, for the same reason: its size is measured in the frame
      // before the transform, so testing the two against each other compares
      // quantities that do not live in the same space. The box maps the ray
      // down and stays out of the result.
      final inverse = Matrix4.zero();
      if (inverse.copyInverse(transform) == 0.0) return false;
      return hitTestChildren(result, ray: ray.transformed(inverse));
    }
    final range = ray.intersectBox(size);
    if (range == null) return false;
    final entry = ray.at(range.near);
    // An unbounded box entered by a line has no entry point to speak of;
    // rather than hand NaN coordinates down the tree, call it a miss.
    if (!entry.isFinite) return false;
    final inside = ray.clampedTo(range.near, range.far);
    if (hitTestChildren(result, ray: inside) || hitTestSelf(entry)) {
      result.add(HitTestEntry3d(this, entry));
      return true;
    }
    return false;
  }

  /// Whether this box answers a hit at [position] on its own account.
  ///
  /// False by default, as in Flutter: a box that arranges other boxes is not
  /// itself a target, so a ray through the gap between two items in a
  /// `Column3d` passes through. Leaves that stand for something the user can
  /// point at ([NodeBox3d]) and boxes that consume a gesture over their whole
  /// extent (the scrolling views) return true.
  @protected
  bool hitTestSelf(Offset3d position) => false;

  /// Whether any child is reached by [ray], which arrives in the frame this
  /// box places its children in.
  ///
  /// Test children front to back and stop at the first hit.
  @protected
  bool hitTestChildren(HitTestResult3d result, {required Ray3d ray}) => false;

  /// Hit-tests [child], moving [ray] into the child's own frame.
  ///
  /// Skips children whose node is hidden, so what a `ListView3d` culls out of
  /// its window is out of reach as well: nothing invisible is pointable.
  @protected
  bool hitTestChild(
    HitTestResult3d result,
    Layout3d child, {
    required Ray3d ray,
  }) {
    if (!child.node.visible) return false;
    return child.hitTest(result, ray: ray.shifted(child.offset));
  }

  @override
  String toString() {
    final sizeText = _size == null ? 'not laid out' : '$_size';
    return '$runtimeType($sizeText)';
  }
}

/// A layout with at most one child, the 3D analogue of
/// [RenderObjectWithChildMixin].
abstract class SingleChildLayout3d extends Layout3d
    with Layout3dWithChildMixin {
  /// Creates a layout wrapping [child].
  SingleChildLayout3d({Layout3d? child, super.name}) {
    this.child = child;
  }
}

/// Holds one child, the 3D analogue of [RenderObjectWithChildMixin].
///
/// Separate from [SingleChildLayout3d] because the box protocol is not the
/// only one that wraps a single child: a `SliverToBoxAdapter3d` holds one too,
/// and it answers to the sliver protocol instead.
mixin Layout3dWithChildMixin on Layout3d {
  Layout3d? _child;

  /// The wrapped layout, or null.
  Layout3d? get child => _child;

  set child(Layout3d? value) {
    if (identical(_child, value)) return;
    final old = _child;
    if (old != null) {
      dropChild(old);
    }
    _child = value;
    if (value != null) {
      adoptChild(value);
    }
    markNeedsLayout();
  }

  @override
  bool hitTestChildren(HitTestResult3d result, {required Ray3d ray}) {
    final child = _child;
    return child != null && hitTestChild(result, child, ray: ray);
  }

  @override
  void visitChildren(void Function(Layout3d child) visitor) {
    final child = _child;
    if (child != null) visitor(child);
  }
}

/// Answers measurement questions with the child's answers, the 3D analogue
/// of what [RenderProxyBox] and [RenderShiftedBox] do.
///
/// For every wrapper that neither adds room of its own nor changes what its
/// child would ask for: its intrinsic extents are the child's, and its
/// baseline is the child's, moved by wherever it placed the child. A wrapper
/// that *does* add room ([Padding3d]) or impose limits ([ConstrainedBox3d])
/// mixes this in and overrides the intrinsic half.
mixin Layout3dChildIntrinsicsMixin on Layout3dWithChildMixin {
  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) =>
      child?.getMinIntrinsicExtent(axis, limits) ?? 0.0;

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) =>
      child?.getMaxIntrinsicExtent(axis, limits) ?? 0.0;

  @override
  double? computeDistanceToActualBaseline(Axis3d axis) {
    final child = this.child;
    if (child == null) return null;
    final distance = child.getDistanceToBaseline(axis, onlyReal: true);
    if (distance == null) return null;
    return distance + child.offset.alongAxis(axis);
  }
}

/// A layout that sizes itself to its child and passes its constraints
/// straight through, the 3D analogue of [RenderProxyBox].
///
/// The base for wrappers that change nothing about layout on their own.
abstract class ProxyLayout3d extends SingleChildLayout3d
    with Layout3dChildIntrinsicsMixin {
  /// Creates a pass-through layout around [child].
  ProxyLayout3d({super.child, super.name});

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    size = child.size;
    child.place(Offset3d.zero);
  }
}

/// A layout with an ordered list of children, the 3D analogue of
/// [ContainerRenderObjectMixin].
///
/// [ParentDataType] is the per-child state this layout keeps; read it with
/// [parentDataOf].
abstract class MultiChildLayout3d<ParentDataType extends ParentData3d>
    extends Layout3d
    with Layout3dWithChildrenMixin<ParentDataType> {
  /// Creates a layout holding [children], in order.
  MultiChildLayout3d({List<Layout3d>? children, super.name}) {
    if (children != null) {
      addAll(children);
    }
  }
}

/// Holds an ordered list of children, the 3D analogue of
/// [ContainerRenderObjectMixin].
///
/// Separate from [MultiChildLayout3d] for the same reason
/// [Layout3dWithChildMixin] is separate: the sliver protocol needs the same
/// child list without being a box.
mixin Layout3dWithChildrenMixin<ParentDataType extends ParentData3d>
    on Layout3d {
  final List<Layout3d> _children = <Layout3d>[];

  /// The children, in layout order.
  List<Layout3d> get children => List<Layout3d>.unmodifiable(_children);

  /// The children this layout actually holds, for its own [performLayout].
  ///
  /// The same list [children] answers with, everywhere except a layout that
  /// forwards its public child list somewhere else: a `BoxScrollView3d`
  /// answers [children] with the items inside its one sliver, because that is
  /// what a caller means by the children of a list, while the child it holds
  /// and lays out is the sliver. Layout code reads this; callers read
  /// [children].
  ///
  /// Live, not a copy: do not edit it while walking it.
  @protected
  List<Layout3d> get heldChildren => _children;

  /// How many children this layout has.
  int get childCount => _children.length;

  /// The child at [index], in layout order.
  Layout3d childAt(int index) => _children[index];

  /// The per-child state this layout keeps on [child].
  @protected
  ParentDataType parentDataOf(Layout3d child) {
    assert(identical(child.parent, this), '$child is not a child of $this.');
    return child.parentData! as ParentDataType;
  }

  /// Appends [child].
  void add(Layout3d child) => insert(child, index: _children.length);

  /// Appends every child in [children], in order.
  void addAll(Iterable<Layout3d> children) {
    for (final child in children) {
      add(child);
    }
  }

  /// Inserts [child] at [index], appending when [index] is omitted.
  void insert(Layout3d child, {int? index}) {
    final at = index ?? _children.length;
    assert(at >= 0 && at <= _children.length);
    adoptChild(child);
    _children.insert(at, child);
    markNeedsLayout();
  }

  /// Removes [child].
  void remove(Layout3d child) {
    if (!_children.remove(child)) return;
    dropChild(child);
    markNeedsLayout();
  }

  /// Removes every child.
  void removeAll() {
    final removed = List<Layout3d>.of(_children);
    _children.clear();
    for (final child in removed) {
      dropChild(child);
    }
    markNeedsLayout();
  }

  /// Replaces the child list with [children], adopting what is new, dropping
  /// what is gone, and reordering the rest.
  ///
  /// The entry point the widget layer uses to mirror a reconciled element
  /// list onto the layout tree; an unchanged list is a no-op.
  void syncChildren(List<Layout3d> children) {
    if (_listIdentical(_children, children)) return;
    final incoming = Set<Layout3d>.identity()..addAll(children);
    for (final child in List<Layout3d>.of(_children)) {
      if (!incoming.contains(child)) {
        _children.remove(child);
        dropChild(child);
      }
    }
    final existing = Set<Layout3d>.identity()..addAll(_children);
    _children
      ..clear()
      ..addAll(children);
    for (final child in children) {
      if (!existing.contains(child)) {
        adoptChild(child);
      }
    }
    markNeedsLayout();
  }

  static bool _listIdentical(List<Layout3d> a, List<Layout3d> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  /// The baseline of the first child that has one, moved by where that child
  /// was placed, the 3D analogue of
  /// `defaultComputeDistanceToFirstActualBaseline`.
  ///
  /// The right answer for children stacked along [axis]: the line the first
  /// one sits on is the line the whole run sits on.
  @protected
  double? defaultComputeDistanceToFirstActualBaseline(Axis3d axis) {
    for (final child in _children) {
      final distance = child.getDistanceToBaseline(axis, onlyReal: true);
      if (distance != null) return distance + child.offset.alongAxis(axis);
    }
    return null;
  }

  /// The lowest of the children's baselines along [axis], the 3D analogue of
  /// `defaultComputeDistanceToHighestActualBaseline`.
  ///
  /// "Highest" as Flutter means it, which is the smallest distance from the
  /// origin corner: the right answer for children lying side by side across
  /// [axis], where the whole group hangs from the topmost line among them.
  @protected
  double? defaultComputeDistanceToHighestActualBaseline(Axis3d axis) {
    double? result;
    for (final child in _children) {
      final distance = child.getDistanceToBaseline(axis, onlyReal: true);
      if (distance == null) continue;
      final candidate = distance + child.offset.alongAxis(axis);
      result = result == null ? candidate : math.min(result, candidate);
    }
    return result;
  }

  /// Tests children back to front, so the one drawn last is found first,
  /// which is what makes a later `Stack3d` child sit on top of an earlier one.
  @override
  bool hitTestChildren(HitTestResult3d result, {required Ray3d ray}) {
    for (var i = _children.length - 1; i >= 0; i--) {
      if (hitTestChild(result, _children[i], ray: ray)) return true;
    }
    return false;
  }

  @override
  void visitChildren(void Function(Layout3d child) visitor) {
    for (final child in List<Layout3d>.of(_children)) {
      visitor(child);
    }
  }
}
