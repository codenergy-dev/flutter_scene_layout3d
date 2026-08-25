import '../geometry/offset3d.dart';
import 'scroll_controller.dart';

/// What every scrolling view in this package has in common: an axis and a
/// position.
///
/// The handle input code reaches for. A hit test returns the layouts a ray
/// passed through, and asking that path for the nearest [Scrollable3d] is how
/// a drag finds the view it should move, whether that is a [Viewport3d] or a
/// [ListView3d]:
///
/// ```dart
/// final scrollable = surface.hitTestRay(ray).firstOf<Scrollable3d>();
/// ```
abstract interface class Scrollable3d {
  /// The axis the content moves along, in the view's own layout space.
  Axis3d get scrollAxis;

  /// The position, and the metrics the view measured for it.
  Scroll3dController get controller;
}

/// What a scrolling view answers when it is asked how much room it wants.
///
/// Nothing honest, which is the point. A viewport's content is as long as it
/// is, and the view exists precisely so that it need not grow to match, so
/// there is no extent it would like. Flutter throws here; this asserts, and
/// answers zero in release so that a layout degrades rather than dies.
///
/// A scrolling view that has to sit inside an [IntrinsicHeight3d] should be
/// given a size instead, with a [SizedBox3d].
double noIntrinsicExtent(Object view, Axis3d axis) {
  assert(
    false,
    '$view was asked for its intrinsic extent along $axis. A scrolling view '
    'has none: its content is whatever length it is, and the view does not '
    'grow to match it. Give it a size instead.',
  );
  return 0.0;
}
