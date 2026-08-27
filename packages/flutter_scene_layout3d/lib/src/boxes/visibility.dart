import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';

/// A box that can hide its child without taking it out of the layout.
///
/// The 3D analogue of `Visibility`, and simpler than Flutter's for one
/// reason: there is no display list to skip. A scene node either draws or it
/// does not, so hiding is a flag on the node, and the flag is the same one
/// the scrolling views already set on the children they cull. Hit testing
/// honours it — `Layout3d.hitTestChild` refuses a hidden child — so an
/// invisible box is unpointable as well as unseen, which is what a caller
/// almost always means.
///
/// The child is still laid out and still reports its size, so the space stays
/// reserved and nothing above moves. Use [Offstage3d] to take the space back.
///
/// ```dart
/// Visibility3d(visible: index == selected, child: checkmark)
/// ```
class Visibility3d extends ProxyLayout3d {
  /// Creates a box showing or hiding [child].
  Visibility3d({bool visible = true, super.child, super.name})
    : _visible = visible {
    node.visible = visible;
  }

  bool _visible;

  /// Whether the child is drawn and reachable by a ray.
  ///
  /// Setting it does not relayout: nothing about an extent changed, and a
  /// list that toggles a row's checkmark on selection should not pay for a
  /// layout pass to do it.
  bool get visible => _visible;

  set visible(bool value) {
    if (_visible == value) return;
    _visible = value;
    node.visible = value;
    owner?.requestVisualUpdate();
  }

  @override
  void performLayout() {
    super.performLayout();
    // The scrolling views cull by writing this flag too, and the last writer
    // during a layout pass should be the box that owns the decision.
    node.visible = _visible;
  }
}

/// A box that hides its child and gives back the space it took.
///
/// The 3D analogue of `Offstage`. It reports the smallest size its
/// constraints allow, hides its node, and answers every intrinsic query with
/// zero, so a `Row3d` full of offstage children is an empty row rather than a
/// row of gaps.
///
/// The child is still laid out, against the same constraints, which is what
/// Flutter's `RenderOffstage` does and for the same reason: a subtree that
/// has never been laid out cannot be measured, and a caller flipping
/// [offstage] back on wants the thing to appear, not to appear a frame later.
///
/// ```dart
/// Offstage3d(offstage: !expanded, child: details)
/// ```
class Offstage3d extends SingleChildLayout3d with Layout3dChildIntrinsicsMixin {
  /// Creates a box that can take its child out of the layout.
  Offstage3d({bool offstage = true, super.child, super.name})
    : _offstage = offstage {
    node.visible = !offstage;
  }

  bool _offstage;

  /// Whether the child is hidden and its space given back.
  ///
  /// Setting it relayouts, unlike [Visibility3d.visible], because the size
  /// this box reports depends on it.
  bool get offstage => _offstage;

  set offstage(bool value) {
    if (_offstage == value) return;
    _offstage = value;
    node.visible = !value;
    markParentNeedsLayout();
  }

  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) =>
      _offstage ? 0.0 : super.computeMinIntrinsicExtent(axis, limits);

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) =>
      _offstage ? 0.0 : super.computeMaxIntrinsicExtent(axis, limits);

  /// An offstage box has no baseline to offer, whatever its child would say.
  ///
  /// A `Row3d` aligning on a baseline must not be pulled around by a child
  /// nobody can see.
  @override
  double? computeDistanceToActualBaseline(Axis3d axis) =>
      _offstage ? null : super.computeDistanceToActualBaseline(axis);

  @override
  void performLayout() {
    final child = this.child;
    if (_offstage) {
      child?.layout(constraints);
      size = constraints.smallest;
      child?.place(Offset3d.zero);
      node.visible = false;
      return;
    }
    if (child == null) {
      size = constraints.smallest;
    } else {
      child.layout(constraints, parentUsesSize: true);
      size = child.size;
      child.place(Offset3d.zero);
    }
    node.visible = true;
  }
}
