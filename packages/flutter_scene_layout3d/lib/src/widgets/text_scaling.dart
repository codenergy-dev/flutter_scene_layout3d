import 'package:flutter/painting.dart' show TextScaler;
import 'package:flutter/widgets.dart'
    show Builder, BuildContext, InheritedWidget, Key, Widget;

import 'surface.dart';

/// Says how far the labels below it grow with the reader's font setting.
///
/// Flutter's `MediaQuery.withClampedTextScaling`, and the reason it is not
/// spelled that way here. Flutter keeps the reader's setting on `MediaQuery`
/// and a component rewrites it for a subtree. Here the setting is
/// [Layout3dMetrics.textScaler], one value per surface that the layout reads
/// inside `performLayout`, and restating it for a subtree would be a second
/// home for the same number. So this carries the *answer for a subtree*
/// instead — the surface's scaler, clamped or replaced — and `SceneText3d`
/// and `SceneRichText3d` hand it to their box as `textScaler`.
///
/// ```dart
/// // A navigation bar's labels keep the bar's hierarchy: they grow with the
/// // reader's setting, and stop at 1.3, which is Flutter's own figure.
/// SceneTextScaling3d.clamped(
///   maxScaleFactor: 1.3,
///   child: SceneText3d(label),
/// )
/// ```
///
/// **It reaches labels built by the widget layer only.** A `Text3d` made
/// imperatively has no `BuildContext` and follows the surface unless it is
/// given a `textScaler` of its own. And a label given one explicitly keeps
/// it: an explicit scaler wins over the ambient one, as Flutter's
/// `Text.textScaler` wins over `MediaQuery`.
class SceneTextScaling3d extends InheritedWidget {
  /// Gives every label below [scaler] in place of the surface's.
  const SceneTextScaling3d({
    super.key,
    required this.scaler,
    required super.child,
  });

  /// Clamps what the labels below grow by to between [minScaleFactor] and
  /// [maxScaleFactor], starting from whatever is in force here.
  ///
  /// Starting from what is in force is what makes two of these nest: a
  /// clamp inside a clamp narrows it rather than replacing it.
  static Widget clamped({
    Key? key,
    double minScaleFactor = 0.0,
    double maxScaleFactor = double.infinity,
    required Widget child,
  }) {
    assert(maxScaleFactor >= minScaleFactor);
    return Builder(
      key: key,
      builder: (context) => SceneTextScaling3d(
        scaler: SceneTextScaling3d.of(
          context,
        ).clamp(minScaleFactor: minScaleFactor, maxScaleFactor: maxScaleFactor),
        child: child,
      ),
    );
  }

  /// What the labels below this scope grow by.
  final TextScaler scaler;

  /// The scaler a scope above [context] states, or null when none does and
  /// a label should follow its surface.
  ///
  /// Null rather than the surface's scaler on purpose: a box given null
  /// keeps following [Layout3dMetrics.textScaler] if the surface's setting
  /// changes, where a box given a copy of it would not.
  static TextScaler? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SceneTextScaling3d>()?.scaler;

  /// What a label built at [context] grows by: a scope's scaler, or the
  /// surface's own.
  static TextScaler of(BuildContext context) =>
      maybeOf(context) ?? Layout3dMetricsScope.of(context).textScaler;

  @override
  bool updateShouldNotify(SceneTextScaling3d oldWidget) =>
      oldWidget.scaler != scaler;
}
