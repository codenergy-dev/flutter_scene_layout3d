import '../geometry/offset3d.dart';
import '../hit_test.dart';
import '../layout3d.dart';

/// Makes its subtree invisible to hit testing, the 3D analogue of
/// [IgnorePointer].
///
/// Layout and rendering are untouched: the child is laid out, placed, and
/// drawn exactly as before, it simply cannot be hit. Use it for scenery, for
/// a model that decorates a panel without being part of it, and for anything
/// standing between the camera and the content that should be pointed at.
class IgnorePointer3d extends ProxyLayout3d {
  /// Creates a box that hides [child] from hit tests while [ignoring].
  IgnorePointer3d({this.ignoring = true, super.child, super.name});

  /// Whether the subtree is out of reach. Costs nothing to flip: hit testing
  /// reads it as it walks, with no relayout behind it.
  bool ignoring;

  @override
  bool hitTest(HitTestResult3d result, {required Ray3d ray}) =>
      ignoring ? false : super.hitTest(result, ray: ray);
}

/// Takes the hit its subtree would have taken, the 3D analogue of
/// [AbsorbPointer].
///
/// Where [IgnorePointer3d] lets the ray carry on to whatever is behind,
/// this one stops it: the box answers the hit itself and its children are
/// never asked. That is the difference between "not there" and "in the way",
/// and it is how a panel is put out of action without letting a click reach
/// the scene behind it.
class AbsorbPointer3d extends ProxyLayout3d {
  /// Creates a box that answers hits for [child] while [absorbing].
  AbsorbPointer3d({this.absorbing = true, super.child, super.name});

  /// Whether this box swallows hits meant for its subtree.
  bool absorbing;

  @override
  bool hitTestSelf(Offset3d position) => absorbing;

  @override
  bool hitTestChildren(HitTestResult3d result, {required Ray3d ray}) =>
      absorbing ? false : super.hitTestChildren(result, ray: ray);
}
