import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, DiagnosticsProperty, Listenable;
import 'package:vector_math/vector_math.dart' show Matrix4;

import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../hit_test.dart';
import '../layout3d.dart';

/// What a [Flow3dDelegate] is handed to place the children, the 3D analogue
/// of [FlowPaintingContext].
///
/// The name keeps Flutter's spelling, and it is worth saying what it means
/// here, because nothing paints. In Flutter, `paintChild` draws the child
/// through a transform, and the whole point of `Flow` is that redrawing is
/// cheaper than relaying out. Here [paintChild] writes the child's *node*
/// transform, which is the same bargain taken further: the child's geometry
/// moves, and no box is measured again, no text is re-shaped, no decoration
/// re-derives its uniforms. See [Layout3d.nodeOffset].
abstract interface class Flow3dPaintingContext {
  /// The size of the box the children are being arranged in.
  Size3d get size;

  /// How many children there are to place.
  int get childCount;

  /// The size child [index] chose, or null when there is no such child.
  Size3d? getChildSize(int index);

  /// Puts child [index] at [offset], optionally through [transform].
  ///
  /// A child not placed by a pass over the delegate is hidden, which — since
  /// hiding also puts a child out of reach of a ray — is how a flow drops a
  /// child it has no room for.
  ///
  /// [transform] is applied in the child's own frame, about its origin
  /// corner, and composes with [offset]: the geometry ends up at
  /// `T(offset) * transform`.
  void paintChild(int index, {Offset3d offset, Matrix4? transform});
}

/// Decides where a [Flow3d]'s children go, the 3D analogue of [FlowDelegate].
///
/// A flow is the box for arrangements that change constantly and never resize
/// anything: a menu whose items fan out from the button that opened it, a
/// carousel that curves away toward the back of the plane, a set of chips
/// that spring into place. [paintChildren] can run every frame — drive it
/// from an animation through [repaint] — and it costs one scene-node
/// transform per child, with the layout protocol untouched. That makes
/// `Flow3d` cheaper here than in Flutter, where the same trick still costs a
/// repaint of a layer.
///
/// The trade is the usual one for this category: what moves is the geometry,
/// not the box. So a flow's children are all as big as [getConstraintsForChild]
/// says and all *placed* at the flow's origin corner as far as the layout
/// protocol is concerned. See [Flow3d] for what that means for a ray.
abstract class Flow3dDelegate {
  /// Creates a delegate that re-places its children whenever [repaint]
  /// notifies.
  const Flow3dDelegate({this.repaint});

  /// A listenable that asks for the children to be placed again.
  ///
  /// An `Animation` usually. Every notification re-runs [paintChildren] and
  /// nothing else — no layout, no rebuild — which is the whole reason to use
  /// a flow rather than moving the children with real boxes.
  final Listenable? repaint;

  /// How big the flow itself is.
  ///
  /// The default fills every axis the parent bounded and collapses the ones
  /// it left open. A flow's size does not depend on its children: they are
  /// placed wherever the delegate puts them, including outside.
  Size3d getSize(Constraints3d constraints) => Size3d(
    constraints.hasBoundedWidth ? constraints.maxWidth : constraints.minWidth,
    constraints.hasBoundedHeight
        ? constraints.maxHeight
        : constraints.minHeight,
    constraints.hasBoundedDepth ? constraints.maxDepth : constraints.minDepth,
  );

  /// The constraints child [index] is laid out against.
  ///
  /// Loosened by default, so a child takes the size it wants inside the room
  /// the flow was given.
  Constraints3d getConstraintsForChild(int index, Constraints3d constraints) =>
      constraints.loosen();

  /// Places the children.
  void paintChildren(Flow3dPaintingContext context);

  /// Whether the children have to be laid out again with this delegate.
  ///
  /// Only about sizes: if nothing this delegate does changes what
  /// [getConstraintsForChild] or [getSize] returns, the answer is false and
  /// the flow re-places the children without measuring anything.
  bool shouldRelayout(covariant Flow3dDelegate oldDelegate) => false;

  /// Whether the children have to be placed again with this delegate.
  bool shouldRepaint(covariant Flow3dDelegate oldDelegate);
}

/// Arranges its children by moving their geometry rather than their boxes,
/// the 3D analogue of [Flow].
///
/// Every child is laid out once, against the constraints the delegate asks
/// for, and then placed by [Flow3dDelegate.paintChildren] writing node
/// transforms. Placing them again is not a layout: it is one matrix per child
/// and a request for a frame, so an animated arrangement runs without the
/// layout protocol hearing about it at all.
///
/// ```dart
/// Flow3d(delegate: FanOut(progress: controller), children: menuItems)
/// ```
///
/// ## Hit testing
///
/// This is the one box where a node transform is taken account of by a ray,
/// and it is worth being precise about why, because the rule everywhere else
/// is the opposite: [Layout3d.nodeOffset] and [Layout3d.nodeTransform] are
/// invisible to hit testing, so a button that lifts under the pointer is
/// still found where layout put it.
///
/// That rule assumes layout put it somewhere meaningful. In a flow it did
/// not: every child sits at the flow's origin corner, stacked on top of one
/// another, and the delegate's transform *is* the child's position. Honouring
/// the rule here would mean every ray hitting whichever child happens to be
/// last, wherever the viewer sees them. So a flow maps the ray through each
/// child's node transform, back to front, and finds the child the viewer is
/// actually aiming at. Flutter's `Flow` makes the same exception, for the
/// same reason.
///
/// A child the delegate did not place this pass is hidden, and a hidden child
/// is out of reach, so a dropped child cannot be hit either.
class Flow3d extends MultiChildLayout3d<ParentData3d>
    implements Flow3dPaintingContext {
  /// Creates a flow arranged by [delegate].
  Flow3d({required Flow3dDelegate delegate, super.children, super.name})
    : _delegate = delegate;

  Flow3dDelegate _delegate;

  /// The delegate deciding where the children go.
  ///
  /// Replacing it asks [Flow3dDelegate.shouldRelayout] and
  /// [Flow3dDelegate.shouldRepaint] what has to happen again; a delegate of a
  /// different type always means both.
  Flow3dDelegate get delegate => _delegate;

  set delegate(Flow3dDelegate value) {
    if (identical(_delegate, value)) return;
    final old = _delegate;
    if (attached) {
      old.repaint?.removeListener(_handleRepaint);
      value.repaint?.addListener(_handleRepaint);
    }
    _delegate = value;
    final differentType = value.runtimeType != old.runtimeType;
    if (differentType || value.shouldRelayout(old)) {
      markNeedsLayout();
    } else if (hasSize && value.shouldRepaint(old)) {
      _placeChildren();
      owner?.requestVisualUpdate();
    }
  }

  @override
  void attach(Layout3dOwner owner) {
    super.attach(owner);
    _delegate.repaint?.addListener(_handleRepaint);
  }

  @override
  void detach() {
    _delegate.repaint?.removeListener(_handleRepaint);
    super.detach();
  }

  @override
  void dispose() {
    _delegate.repaint?.removeListener(_handleRepaint);
    super.dispose();
  }

  void _handleRepaint() {
    if (!hasSize) return;
    _placeChildren();
    owner?.requestVisualUpdate();
  }

  // -------------------------------------------------- the delegate's context

  @override
  Size3d? getChildSize(int index) {
    if (index < 0 || index >= childCount) return null;
    final child = childAt(index);
    return child.hasSize ? child.size : null;
  }

  bool _placing = false;
  final Set<int> _placed = <int>{};

  @override
  void paintChild(
    int index, {
    Offset3d offset = Offset3d.zero,
    Matrix4? transform,
  }) {
    assert(
      _placing,
      'Flow3dPaintingContext.paintChild was called outside '
      'Flow3dDelegate.paintChildren. The context is only alive for the length '
      'of that call; keep the delegate, not the context.',
    );
    assert(
      index >= 0 && index < childCount,
      'A Flow3d delegate placed child $index, and the flow has $childCount '
      '${childCount == 1 ? 'child' : 'children'}.',
    );
    if (index < 0 || index >= childCount) return;
    final first = _placed.add(index);
    assert(
      first,
      'A Flow3d delegate placed child $index twice; the second placement '
      'would simply overwrite the first.',
    );
    final child = childAt(index);
    child
      ..nodeOffset = offset
      ..nodeTransform = transform;
    child.node.visible = true;
  }

  /// Runs the delegate over the children and hides whatever it left out.
  void _placeChildren() {
    _placing = true;
    _placed.clear();
    try {
      _delegate.paintChildren(this);
    } finally {
      _placing = false;
    }
    for (var index = 0; index < childCount; index++) {
      if (_placed.contains(index)) continue;
      childAt(index).node.visible = false;
    }
  }

  // ------------------------------------------------------------- the layout

  /// A flow's size comes from its delegate, not from its children, so an
  /// intrinsic query is answered without measuring any of them.
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
    for (var index = 0; index < childCount; index++) {
      final child = childAt(index);
      child.layout(
        _delegate.getConstraintsForChild(index, constraints),
        parentUsesSize: true,
      );
      // Every child sits at the origin corner as far as layout is concerned;
      // where it ends up is the node transform the delegate writes.
      child.place(Offset3d.zero);
    }
    _placeChildren();
  }

  @override
  bool hitTestChildren(HitTestResult3d result, {required Ray3d ray}) {
    for (var index = childCount - 1; index >= 0; index--) {
      final child = childAt(index);
      if (!child.node.visible) continue;
      // The node carries T(offset + nodeOffset) * nodeTransform, so undoing
      // it means the translation first and the matrix second.
      var childRay = ray.shifted(child.offset + child.nodeOffset);
      final transform = child.nodeTransform;
      if (transform != null) {
        final inverse = Matrix4.zero();
        if (inverse.copyInverse(transform) == 0.0) continue;
        childRay = childRay.transformed(inverse);
      }
      if (child.hitTest(result, ray: childRay)) return true;
    }
    return false;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Flow3dDelegate>('delegate', delegate));
  }
}
