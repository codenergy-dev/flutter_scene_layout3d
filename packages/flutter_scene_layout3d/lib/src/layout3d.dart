import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show
        DiagnosticLevel,
        DiagnosticPropertiesBuilder,
        DiagnosticableTreeMixin,
        DiagnosticsNode,
        DiagnosticsProperty,
        FlagProperty,
        StringProperty,
        VoidCallback,
        describeIdentity,
        mustCallSuper,
        protected;
import 'package:flutter/widgets.dart' show FocusManager, FocusScopeNode;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:vector_math/vector_math.dart' show Matrix4;

import 'clip.dart';
import 'debug/wireframe.dart';
import 'decoration/decoration.dart';
import 'geometry/basis3d.dart';
import 'geometry/constraints3d.dart';
import 'geometry/offset3d.dart';
import 'geometry/size3d.dart';
import 'hit_test.dart';
import 'metrics.dart';
import 'slot.dart';

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

  /// The unit contract in force for this tree: how many world units a logical
  /// pixel is worth, and the dials a component library reads beside it.
  ///
  /// It rides here, next to [basis], rather than in an `InheritedWidget`,
  /// because the imperative layer has no `BuildContext` and the basis already
  /// set the precedent. Everything in the tree reaches it through
  /// [Layout3d.metrics]; the root writes it, through
  /// [Layout3dSurface.metrics] or a [Layout3dCameraBinding].
  ///
  /// This is the only copy that decides anything. The widget layer reads a
  /// *published* one — `SceneLayout3d` mirrors this value into a
  /// `Layout3dMetricsScope` so a `build` method can convert its own figures
  /// — and that scope follows this value rather than the other way round.
  Layout3dMetrics metrics = Layout3dMetrics.standard;

  /// The painters the decorated boxes in this tree share, keyed by
  /// [Decoration3d.cacheKey].
  ///
  /// Per-surface, and here for the same reason [basis] and [metrics] are: it
  /// is tree-wide state both layers have to reach without a `BuildContext`.
  /// A screen of Material components is a hundred boxes and a handful of
  /// shapes, and this is what collapses the one onto the other.
  final Decoration3dPainterCache painters = Decoration3dPainterCache();

  FocusScopeNode? _focusScope;

  /// The focus scope every [Focus3d] in this tree hangs under.
  ///
  /// Per-surface, and here for the same reason [basis] and [metrics] are: it
  /// is tree-wide state both layers have to reach without a `BuildContext`.
  ///
  /// Made on first use and parented under the application's root scope at
  /// that moment, which is when the surface starts taking part in the
  /// application's focus at all — a scene nobody has clicked on should not be
  /// holding the keyboard. The scope skips Flutter's own traversal: a policy
  /// that reasons about `Rect`s has nothing to say about a box on a plane,
  /// and [Focus3dTraversal] is what moves focus inside a surface.
  ///
  /// Needs Flutter's binding, since [FocusManager] does.
  FocusScopeNode get focusScope {
    final existing = _focusScope;
    if (existing != null) return existing;
    final scope = FocusScopeNode(
      debugLabel: 'Layout3dOwner',
      skipTraversal: true,
    );
    // The attachment is what a later `dispose` unparents through; nothing
    // reparents through it, so the null context it is made with is never
    // dereferenced.
    scope.attach(null);
    FocusManager.instance.rootScope.setFirstFocus(scope);
    return _focusScope = scope;
  }

  /// Whether anything on this surface has ever asked for focus.
  bool get hasFocusScope => _focusScope != null;

  final Map<Layout3dSlot<Object>, Object> _slots =
      <Layout3dSlot<Object>, Object>{};

  /// What [key] holds on this surface, or null when nothing has written it.
  ///
  /// The open, typed half of the owner. [basis], [metrics], [painters] and
  /// [focusScope] are here because they are tree-wide state both layers need
  /// and the imperative one has no `BuildContext` to read an inherited widget
  /// with; a component library's theme is exactly that shape, and its
  /// vocabulary has no business in this package. So the library declares a
  /// [Layout3dSlot] and puts the value here:
  ///
  /// ```dart
  /// const themeSlot = Layout3dSlot<Theme3dData>('theme');
  /// owner.setSlot(themeSlot, Theme3dData.light());
  /// final Theme3dData? theme = owner.slot(themeSlot);
  /// ```
  ///
  /// A box below reads it as [Layout3d.slot], which falls back to null while
  /// detached, the way [Layout3d.metrics] falls back to the standard value.
  T? slot<T extends Object>(Layout3dSlot<T> key) => _slots[key] as T?;

  /// Writes [value] under [key], returning whether it changed anything.
  ///
  /// Null removes the entry. This is the plain write: it does *not* relayout,
  /// because the owner does not know which boxes read the slot and cannot
  /// reach the root to dirty it. Use [Layout3dSurface.setSlot] for a value
  /// boxes measure against — a theme's paddings and type sizes — which is
  /// most of them.
  bool setSlot<T extends Object>(Layout3dSlot<T> key, T? value) {
    if (value == null) return _slots.remove(key) != null;
    if (identical(_slots[key], value) || _slots[key] == value) return false;
    _slots[key] = value;
    return true;
  }

  /// Every slot currently holding a value, for a diagnostic dump.
  Iterable<Layout3dSlot<Object>> get slotKeys => _slots.keys;

  Layout3dWireframe? _debugWireframe;

  /// Whether a debug wireframe is currently drawing this tree.
  ///
  /// See [debugPaintLayout3dSize]. Always false unless something set that
  /// flag and flushed.
  bool get debugHasWireframe => _debugWireframe != null;

  /// The wireframe drawing this tree's debug overlay, made on first use.
  ///
  /// Per-surface for the same reason [painters] is: one set of shared line
  /// geometries serves every box on the plane, and they have to be reachable
  /// without a `BuildContext`. Returns null while [factory] cannot build one,
  /// which is what a headless test and a not-yet-ready engine both look like.
  Layout3dWireframe? debugAcquireWireframe(
    Layout3dWireframe? Function() factory,
  ) => _debugWireframe ??= factory();

  /// Drops the debug wireframe and everything it built.
  void debugReleaseWireframe() {
    _debugWireframe?.dispose();
    _debugWireframe = null;
  }

  /// Releases what the owner made, which is the focus scope and nothing else.
  ///
  /// Called by [Layout3dSurface.dispose]. The layouts are not the owner's to
  /// dispose: it collects them, it does not hold them.
  void dispose() {
    _focusScope?.dispose();
    _focusScope = null;
    debugReleaseWireframe();
    _nodesNeedingLayout.clear();
    // Dropped, not disposed. The owner collects tree-wide state, it does not
    // own it: a slot value that holds resources is disposed by whoever put it
    // there, the same rule this class already follows for the layouts.
    _slots.clear();
  }

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
abstract class Layout3d with DiagnosticableTreeMixin {
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

  /// The unit contract in force for this tree.
  ///
  /// How a box written against a component spec turns a dp figure into world
  /// units: `metrics.dp(48)` is a Material touch target on whatever scale the
  /// surface is drawn at. The root owns the value and every box below it
  /// inherits the same one, so a component never has to be told.
  ///
  /// Falls back to [Layout3dMetrics.standard] while detached, which is the
  /// authored default (one unit to a hundred logical pixels) rather than
  /// anything derived. A box whose size depends on this must be laid out
  /// again when it changes, which is why writing it at the root relayouts.
  Layout3dMetrics get metrics => _owner?.metrics ?? Layout3dMetrics.standard;

  /// What [key] holds on this box's surface, or null.
  ///
  /// The way a box reads tree-wide state a component library put there — a
  /// theme, a density, a palette — without a `BuildContext` and without being
  /// handed it as a constructor argument. Null while detached, and null when
  /// nothing has written the slot, so a box that needs a value states its own
  /// fallback:
  ///
  /// ```dart
  /// final theme = slot(themeSlot) ?? Theme3dData.light();
  /// ```
  ///
  /// Read it inside [performLayout] like [metrics]. A slot written through
  /// [Layout3dSurface.setSlot] relayouts the subtree, which is what makes
  /// that safe.
  T? slot<T extends Object>(Layout3dSlot<T> key) => _owner?.slot(key);

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

  /// Marks this layout and everything below it as needing to be laid out.
  ///
  /// The blunt instrument, and it exists because [markNeedsLayout] is not
  /// enough for a change to something the whole tree measures *against*: the
  /// [basis] a leaf maps its content bounds through, or the [metrics] a
  /// component turns a dp figure into world units with. Neither reaches a
  /// child as a constraint, and [layout] skips a clean child whose
  /// constraints did not change — which is the optimization that makes
  /// relayout cheap, and exactly the one that has to be defeated here.
  ///
  /// Called by the root when it is handed a new tree-wide value. Nothing on
  /// the hot path does this.
  void markSubtreeNeedsLayout() {
    markNeedsLayout();
    visitChildren((child) => child.markSubtreeNeedsLayout());
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

  Offset3d _nodeOffset = Offset3d.zero;

  /// An extra offset this box applies to its **own** scene node, which layout,
  /// intrinsics and hit testing never see.
  ///
  /// The node-only animation path, and the one category of animation a 2D
  /// framework cannot have. A slide, a hover lift, a pressed depression, a
  /// billboard turn: they change where the geometry *is* without changing how
  /// big any box is, so there is nothing for the layout protocol to redo.
  /// Writing this therefore rewrites one node transform and asks the host for
  /// a frame — it does not call [markNeedsLayout], and nothing downstream of
  /// it measures text, rebuilds a mesh, or reads [metrics].
  ///
  /// It is the sibling of [ParentData3d.sceneOffset] and composes with it.
  /// The difference is ownership: `sceneOffset` is the *parent's* nudge,
  /// rewritten whenever the parent places this box (that is how
  /// [Stack3d.depthStep] separates coplanar children), while this one is the
  /// box's own and survives every relayout. An animation must use this one,
  /// or a stack would erase it on the next pass.
  ///
  /// Measured in layout axes, like [offset]. [worldTransform] undoes it, so a
  /// drag keeps tracking the box where layout put it rather than where the
  /// animation has carried it.
  Offset3d get nodeOffset => _nodeOffset;

  set nodeOffset(Offset3d value) {
    if (_nodeOffset == value) return;
    _nodeOffset = value;
    applyNodeTransform();
    _owner?.requestVisualUpdate();
  }

  Matrix4? _nodeTransform;

  /// A transform this box applies to its own scene node and to nothing else,
  /// pivoting on the box's origin corner.
  ///
  /// [nodeOffset] for the rotations and scales a translation cannot express:
  /// a card that tips under the pointer, a chip that pops, a label that turns
  /// to face the camera. The same rule holds — no relayout, no change to any
  /// size, and [worldTransform] undoes it — and the same warning: this is the
  /// box's own transform, not [localTransform], which *is* a change of frame
  /// and which layout, clipping and hit testing all take account of.
  ///
  /// The node ends up carrying
  /// `T(offset + sceneOffset + nodeOffset) * nodeTransform * localTransform`.
  Matrix4? get nodeTransform => _nodeTransform;

  set nodeTransform(Matrix4? value) {
    if (_nodeTransform == value) return;
    _nodeTransform = value == null ? null : Matrix4.copy(value);
    applyNodeTransform();
    _owner?.requestVisualUpdate();
  }

  /// Rewrites this layout's node transform from its offset and
  /// [localTransform].
  ///
  /// Call after changing anything [localTransform] depends on.
  @protected
  void applyNodeTransform() {
    final position = offset + sceneOffset + _nodeOffset;
    final transform = Matrix4.translationValues(
      position.x,
      position.y,
      position.z,
    );
    final node = _nodeTransform;
    if (node != null) {
      transform.multiply(node);
    }
    final local = localTransform;
    if (local != null) {
      transform.multiply(local);
    }
    _node.localTransform = transform;
  }

  // --------------------------------------------------------------- clipping

  /// The clip in force for this box, in its own layout frame.
  ///
  /// [Clip3dRegion.none] unless some ancestor is a [ClipBox3d]. Computed by
  /// walking up rather than pushed down, because the walk is O(depth) and
  /// happens only when something asks — a decoration painter, a culling
  /// sweep — while pushing would cost every box on every layout whether or
  /// not anything in the tree clips at all.
  ///
  /// Only meaningful once this box and its ancestors have been laid out: a
  /// clip is an extent, and an extent is what layout produces.
  Clip3dRegion get clipRegion =>
      _parent?.clipRegionForChild(this) ?? Clip3dRegion.none;

  /// The clip this box imposes on [child], in the child's own frame.
  ///
  /// The default takes what this box inherits, pulls it back through
  /// [localTransform] (so a rotated subtree is still clipped, exactly) and
  /// slides it by the child's offset. [ClipBox3d] overrides this to intersect
  /// its own extent in.
  @protected
  Clip3dRegion clipRegionForChild(Layout3d child) {
    final region = clipRegion;
    if (region.isUnbounded) return region;
    final local = localTransform;
    final inFrame = local == null ? region : region.transformed(local);
    return inFrame.shifted(-child.offset);
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
  /// The box's node carries
  /// `T(offset + sceneOffset + nodeOffset) * nodeTransform * localTransform`,
  /// so the node's world transform describes the frame this box's *children*
  /// sit in; undoing [hitTestTransform] backs up one step to the frame this
  /// box measures itself in, the one [HitTestEntry3d.localPosition] is
  /// expressed in, and undoing [nodeTransform], [sceneOffset] and
  /// [nodeOffset] discards the nudges applied to the geometry alone.
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
    final animated = _nodeTransform;
    if (animated != null) {
      final inverse = Matrix4.zero();
      if (inverse.copyInverse(animated) == 0.0) return world;
      world = world.multiplied(inverse);
    }
    final nudge = sceneOffset + _nodeOffset;
    if (nudge == Offset3d.zero) return world;
    // Translations commute, so undoing the nudge on the right of
    // `T(offset + sceneOffset + nodeOffset)` leaves `T(offset)`: the layout
    // frame, which is where the box's extent and its children's offsets are.
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

  // ------------------------------------------------------------ diagnostics

  /// Describes this box for [toStringDeep], [toStringShallow] and the error
  /// messages that quote a box.
  ///
  /// The 3D counterpart of `RenderObject.debugFillProperties`, and it exists
  /// for the same reason: a layout here produces no pixels, so when a test
  /// says a box is `Size3d(0.000, 0.000, 0.000)` there is nothing to look at
  /// and no way to tell a box that was never laid out from one that was
  /// squeezed to nothing by its parent. The properties below are the ones
  /// that answer that question — what came down, what went up, where the
  /// parent put it, and whether the answer is current.
  ///
  /// Subclasses add what they were configured with (a padding, an alignment,
  /// a flex factor) and call `super`. Everything here is debug-only:
  /// [DiagnosticPropertiesBuilder] work is stripped in release.
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    final name = _node.name;
    properties.add(
      StringProperty(
        'name',
        name,
        quoted: true,
        // The node is named after its runtime type unless the caller named
        // it, and repeating the type in every line of a tree dump is noise.
        defaultValue: '$runtimeType',
      ),
    );
    properties.add(
      DiagnosticsProperty<Constraints3d>(
        'constraints',
        _constraints,
        missingIfNull: true,
      ),
    );
    properties.add(
      DiagnosticsProperty<Size3d>(
        'size',
        _size,
        // A box with no size has not been laid out, and saying so is more
        // useful than printing `null`.
        ifNull: 'MISSING',
      ),
    );
    properties.add(
      DiagnosticsProperty<Offset3d>(
        'offset',
        offset,
        defaultValue: Offset3d.zero,
      ),
    );
    properties.add(
      DiagnosticsProperty<Offset3d>(
        'sceneOffset',
        sceneOffset,
        defaultValue: Offset3d.zero,
        description: sceneOffset == Offset3d.zero
            ? null
            : 'sceneOffset: $sceneOffset (geometry only)',
      ),
    );
    properties.add(
      DiagnosticsProperty<Offset3d>(
        'nodeOffset',
        _nodeOffset,
        defaultValue: Offset3d.zero,
      ),
    );
    properties.add(
      DiagnosticsProperty<Matrix4>(
        'nodeTransform',
        _nodeTransform,
        defaultValue: null,
      ),
    );
    properties.add(
      FlagProperty(
        'sizedByParent',
        value: sizedByParent,
        ifTrue: 'sizedByParent',
        level: DiagnosticLevel.fine,
      ),
    );
    properties.add(
      StringProperty(
        'relayoutBoundary',
        _debugRelayoutBoundaryDescription,
        level: DiagnosticLevel.fine,
      ),
    );
    properties.add(
      FlagProperty('needsLayout', value: _needsLayout, ifTrue: 'NEEDS-LAYOUT'),
    );
    properties.add(
      FlagProperty('attached', value: attached, ifFalse: 'DETACHED'),
    );
    properties.add(
      FlagProperty('debugDisposed', value: debugDisposed, ifTrue: 'DISPOSED'),
    );
  }

  /// How far up the tree this box's relayout boundary sits, in Flutter's
  /// `up{n}` spelling, or null when there is none yet.
  ///
  /// The single most useful number when a change is not showing up: dirt
  /// stops at the boundary, so a box whose boundary is `up3` is relaid out
  /// by a box three levels above it, and marking *it* dirty does nothing the
  /// parent has not already been told.
  String? get _debugRelayoutBoundaryDescription {
    final boundary = _relayoutBoundary;
    if (boundary == null) return null;
    var steps = 0;
    Layout3d? node = this;
    while (node != null && !identical(node, boundary)) {
      steps += 1;
      node = node._parent;
    }
    if (node == null) return 'elsewhere';
    return steps == 0 ? 'this' : 'up$steps';
  }

  /// The children of this box, as diagnostics nodes.
  ///
  /// Taken from [visitChildren], so a box that arranges its children in an
  /// order of its own dumps them in that order too. A single child is named
  /// `child`; a list is numbered from one, as Flutter numbers a
  /// `RenderFlex`'s.
  @override
  List<DiagnosticsNode> debugDescribeChildren() {
    final children = <Layout3d>[];
    visitChildren(children.add);
    if (children.isEmpty) return const <DiagnosticsNode>[];
    if (children.length == 1) {
      return <DiagnosticsNode>[
        children.single.toDiagnosticsNode(name: 'child'),
      ];
    }
    return <DiagnosticsNode>[
      for (var i = 0; i < children.length; i += 1)
        children[i].toDiagnosticsNode(name: 'child ${i + 1}'),
    ];
  }

  @override
  String toStringShort() {
    final buffer = StringBuffer(describeIdentity(this));
    if (_debugDisposed) buffer.write(' DISPOSED');
    return buffer.toString();
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
