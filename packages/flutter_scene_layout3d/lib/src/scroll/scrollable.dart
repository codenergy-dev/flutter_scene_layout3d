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
