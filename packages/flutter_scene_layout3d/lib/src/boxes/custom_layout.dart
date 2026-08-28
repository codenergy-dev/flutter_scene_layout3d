import 'package:flutter/foundation.dart' show protected;

import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';

/// Tags a child of a [CustomMultiChildLayout3d] so a delegate can name it,
/// the 3D analogue of [LayoutId].
///
/// Flutter's `LayoutId` is a `ParentDataWidget`, which writes an id into the
/// child's parent data. There is no parent-data widget here, and none is
/// wanted: a [Layout3d] is cheap — a scene node and a size — so the id is
/// carried by a box that wraps the child, exactly as [Positioned3d] carries a
/// [Stack3d]'s pins. The box passes constraints and size straight through, so
/// it changes nothing about the layout it takes part in.
class LayoutId3d extends ProxyLayout3d {
  /// Tags [child] with [id].
  LayoutId3d({required Object id, super.child, super.name}) : _id = id;

  Object _id;

  /// The name the delegate knows this child by.
  ///
  /// Compared with `==`, so a `String`, an enum value or any value type will
  /// do; an enum is the usual choice, because a typo in a string is a child
  /// the delegate silently never lays out.
  Object get id => _id;

  set id(Object value) {
    if (_id == value) return;
    _id = value;
    // The parent's delegate looks children up by id, so the arrangement it
    // produced was for the old one.
    markParentNeedsLayout();
  }
}

/// Decides how a [CustomMultiChildLayout3d] arranges children it knows by
/// name, the 3D analogue of [MultiChildLayoutDelegate].
///
/// The escape hatch from the algebra of rows, columns and stacks: when the
/// arrangement is a *relationship* between named parts rather than a run of
/// them, write it as a delegate. Flutter's `Scaffold` is literally a
/// `CustomMultiChildLayout` — the body is laid out with the room the app bar
/// and the bottom bar left over, and the floating action button is placed
/// relative to both — and a `Scaffold3d` wants the same shape.
///
/// Three rules, the same three Flutter has:
///
///  * lay a child out exactly once, with [layoutChild], before positioning
///    it;
///  * position every child you laid out, with [positionChild]; a child that
///    is never positioned sits at the origin corner;
///  * do not look at anything but the constraints, the sizes children report
///    and the delegate's own fields. In particular, do not look at where a
///    child was placed by a previous pass — layout has to be a pure function
///    of what comes in, or it will not converge.
///
/// [performLayout] is called with the size [getSize] chose, and the id of
/// every child is whatever the [LayoutId3d] around it carries.
///
/// ```dart
/// enum _Panel { bar, body }
///
/// class PanelDelegate extends MultiChildLayout3dDelegate {
///   @override
///   void performLayout(Size3d size) {
///     final bar = layoutChild(
///       _Panel.bar,
///       Constraints3d.tightFor(width: size.width, height: 0.6),
///     );
///     positionChild(_Panel.bar, Offset3d.zero);
///     layoutChild(
///       _Panel.body,
///       Constraints3d.tight(
///         Size3d(size.width, size.height - bar.height, size.depth),
///       ),
///     );
///     positionChild(_Panel.body, Offset3d(0, bar.height, 0));
///   }
///
///   @override
///   bool shouldRelayout(PanelDelegate oldDelegate) => false;
/// }
/// ```
abstract class MultiChildLayout3dDelegate {
  /// Creates a delegate.
  MultiChildLayout3dDelegate();

  /// Whether a child called [childId] was given to the layout.
  ///
  /// A delegate that arranges optional parts asks this first; laying out a
  /// child that is not there is an error, because a delegate that does not
  /// know what it has cannot be producing a considered arrangement.
  bool hasChild(Object childId) => _state!.children.containsKey(childId);

  /// Lays the child called [childId] out against [constraints] and returns
  /// the size it chose.
  ///
  /// Call once per child per pass.
  Size3d layoutChild(Object childId, Constraints3d constraints) {
    final state = _state!;
    final child = state.children[childId];
    assert(
      child != null,
      'The delegate of a CustomMultiChildLayout3d tried to lay out a child '
      'called $childId, and no child has that id. Wrap the child in a '
      'LayoutId3d(id: $childId, ...), or ask hasChild($childId) first.',
    );
    assert(
      state.pending.remove(childId),
      'The delegate of a CustomMultiChildLayout3d laid out the child called '
      '$childId more than once. A second layout with different constraints '
      'would throw the first answer away, and one with the same constraints '
      'is work already done.',
    );
    child!.layout(constraints, parentUsesSize: true);
    return child.size;
  }

  /// Puts the child called [childId] at [offset], measured from this box's
  /// origin corner.
  void positionChild(Object childId, Offset3d offset) {
    final state = _state!;
    final child = state.children[childId];
    assert(
      child != null,
      'The delegate of a CustomMultiChildLayout3d tried to position a child '
      'called $childId, and no child has that id.',
    );
    assert(
      !state.pending.contains(childId),
      'The delegate of a CustomMultiChildLayout3d positioned the child called '
      '$childId before laying it out. Where a child goes usually depends on '
      'how big it is, so lay it out first.',
    );
    child!.place(offset);
  }

  /// How big the box itself is, before any child is laid out.
  ///
  /// The default fills every axis the parent bounded and collapses the ones
  /// it left open, which is the only answer available before the children
  /// have spoken: an unbounded axis is the normal case on a surface, and
  /// `constraints.biggest` there would be an infinite extent in the scene.
  /// Override it to shrink-wrap, or to state a size outright.
  Size3d getSize(Constraints3d constraints) => Size3d(
    constraints.hasBoundedWidth ? constraints.maxWidth : constraints.minWidth,
    constraints.hasBoundedHeight
        ? constraints.maxHeight
        : constraints.minHeight,
    constraints.hasBoundedDepth ? constraints.maxDepth : constraints.minDepth,
  );

  /// Arranges the children inside a box of [size].
  void performLayout(Size3d size);

  /// Whether a layout using [oldDelegate] has to be redone with this one.
  ///
  /// Called when a new delegate of the same type replaces an old one, which
  /// in the declarative layer happens on every rebuild. Compare the fields
  /// the arrangement depends on and return false when nothing that matters
  /// changed; the layout is then skipped entirely.
  bool shouldRelayout(covariant MultiChildLayout3dDelegate oldDelegate);

  _DelegateState? _state;

  /// Runs [performLayout] with the child map in place.
  void _run(Size3d size, Map<Object, Layout3d> children) {
    _state = _DelegateState(children);
    try {
      performLayout(size);
      assert(
        _state!.pending.isEmpty,
        'The delegate of a CustomMultiChildLayout3d did not lay out '
        '${_state!.pending.join(', ')}. Every child handed to it has to be '
        'laid out, or it has no size and the first read of one trips an '
        'assertion somewhere else entirely.',
      );
    } finally {
      _state = null;
    }
  }

  @override
  String toString() => '$runtimeType';
}

class _DelegateState {
  _DelegateState(this.children) : pending = children.keys.toSet();

  final Map<Object, Layout3d> children;

  /// The ids not yet laid out this pass, for the assertions above.
  final Set<Object> pending;
}

/// Arranges children a delegate knows by name, the 3D analogue of
/// [CustomMultiChildLayout].
///
/// Each child is wrapped in a [LayoutId3d]; the work is in the
/// [MultiChildLayout3dDelegate], which is where the documentation of this
/// pair lives.
///
/// The children are laid out in whatever order the delegate asks for them,
/// not in child order, which is the point: the body can be told how much room
/// the bar left only after the bar has been measured. What child order still
/// decides is hit testing, which runs back to front as everywhere else, so a
/// child later in the list wins a ray both boxes are in.
class CustomMultiChildLayout3d extends MultiChildLayout3d<ParentData3d> {
  /// Creates a box arranged by [delegate].
  CustomMultiChildLayout3d({
    required MultiChildLayout3dDelegate delegate,
    super.children,
    super.name,
  }) : _delegate = delegate;

  MultiChildLayout3dDelegate _delegate;

  /// The delegate deciding the arrangement.
  ///
  /// Replacing it with a delegate of a different type always relayouts;
  /// replacing it with one of the same type asks
  /// [MultiChildLayout3dDelegate.shouldRelayout] first.
  MultiChildLayout3dDelegate get delegate => _delegate;

  set delegate(MultiChildLayout3dDelegate value) {
    if (identical(_delegate, value)) return;
    final old = _delegate;
    _delegate = value;
    if (value.runtimeType != old.runtimeType || value.shouldRelayout(old)) {
      markNeedsLayout();
    }
  }

  /// The children by the id their [LayoutId3d] carries.
  @protected
  Map<Object, Layout3d> childrenById() {
    final result = <Object, Layout3d>{};
    for (final child in heldChildren) {
      assert(
        child is LayoutId3d,
        'Every child of a CustomMultiChildLayout3d needs an id its delegate '
        'can name it by, and a ${child.runtimeType} has none. Wrap it in a '
        'LayoutId3d.',
      );
      if (child is! LayoutId3d) continue;
      assert(
        !result.containsKey(child.id),
        'Two children of a CustomMultiChildLayout3d share the id '
        '${child.id}. The delegate can only reach one of them.',
      );
      result[child.id] = child;
    }
    return result;
  }

  /// The size the delegate chooses, which is what an intrinsic query answers
  /// with here.
  ///
  /// A delegate states its own size from the constraints, so this box has an
  /// exact answer without laying anything out — the same shortcut Flutter's
  /// `RenderCustomMultiChildLayoutBox` takes.
  double _intrinsic(Axis3d axis, Size3d limits) {
    var constraints = const Constraints3d();
    for (final other in Axis3d.values) {
      if (other == axis) continue;
      final limit = limits.alongAxis(other);
      if (!limit.isFinite) continue;
      constraints = constraints.withAxis(other, min: limit, max: limit);
    }
    return _delegate.getSize(constraints).alongAxis(axis);
  }

  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) =>
      _intrinsic(axis, limits);

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) =>
      _intrinsic(axis, limits);

  @override
  void performLayout() {
    size = constraints.constrain(_delegate.getSize(constraints));
    _delegate._run(size, childrenById());
  }
}
