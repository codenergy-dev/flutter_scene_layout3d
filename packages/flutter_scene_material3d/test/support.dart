// Shared helpers for the material3d tests.

import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';

/// A surface holding [child], already laid out.
Layout3dSurface laidOut(
  Layout3d child, {
  Constraints3d constraints = const Constraints3d(),
  Layout3dMetrics metrics = Layout3dMetrics.standard,
}) {
  final surface = Layout3dSurface(
    constraints: constraints,
    metrics: metrics,
    child: child,
  );
  surface.flush();
  return surface;
}

/// A box that sizes itself from the theme, the way a real component will.
///
/// It reads a token (a thickness, in logical pixels) and converts it with the
/// metrics, which is the one-way arrow the token layer exists to enforce:
/// the theme decides the dp figure, the metrics turns dp into world units.
class ThemedBox extends Layout3d {
  ThemedBox({super.name});

  /// How many times this box has been laid out.
  int layoutCount = 0;

  /// The theme seen on the last layout.
  Theme3dData? sawTheme;

  /// Whether a theme was actually published on the last layout.
  bool sawPublishedTheme = false;

  @override
  void performLayout() {
    layoutCount++;
    sawTheme = theme3d;
    sawPublishedTheme = hasTheme3d;
    final thickness = metrics.dp(theme3d.thickness.raised);
    final height = metrics.dp(40.0);
    size = constraints.constrain(Size3d(height, height, thickness));
  }
}
