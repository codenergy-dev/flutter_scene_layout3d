import 'dart:ui' show Size;

import 'package:flutter/painting.dart' show TextScaler;
import 'package:flutter/widgets.dart' show MediaQueryData;

/// The platform view a surface can be derived from: how big it is, and how
/// the reader has asked for type to be scaled.
///
/// A scene is not a window, so nothing in it has these numbers naturally —
/// which is the whole reason [Layout3dCameraBinding] exists. This is what a
/// binding reads, handed to it once per frame by whoever drives it:
/// `SceneLayout3d` composes one from the enclosing `MediaQuery` and the view's
/// own box, and an imperative host passes one of its own.
///
/// ```dart
/// binding.update(
///   surface,
///   camera: camera,
///   view: Layout3dView.fromMediaQuery(MediaQuery.of(context)),
/// );
/// ```
///
/// **It carries what a binding derives from and nothing else.** The view's
/// safe area is not here, because no binding computes anything from it: an
/// inset is consumed by a `build` method, and `MediaQuery3d` is where the
/// widget layer publishes it. The day something derived from a keyboard inset
/// or a display's refresh rate, it would gain a field.
class Layout3dView {
  /// Creates a description of a platform view.
  const Layout3dView({
    this.size = Size.zero,
    this.textScaler = TextScaler.noScaling,
  });

  /// The same, read off a [MediaQueryData].
  factory Layout3dView.fromMediaQuery(MediaQueryData data) =>
      Layout3dView(size: data.size, textScaler: data.textScaler);

  /// The view's logical size, in logical pixels.
  ///
  /// What a [Layout3dCameraBinding.screenFilling] surface's unit contract is
  /// derived against: the plane covers the view, so its world height spans
  /// exactly this many logical pixels.
  ///
  /// Zero is allowed and is what a caller driving one of the bindings that
  /// does not derive from it — the ones whose `needsView` is false — passes
  /// when it has nothing to say. Those read the scale and nothing else.
  final Size size;

  /// The reader's own font setting.
  ///
  /// Written into the surface's [Layout3dMetrics] by any binding that derives
  /// the metrics, unless that binding states one of its own.
  final TextScaler textScaler;

  /// A copy with the given fields replaced.
  Layout3dView copyWith({Size? size, TextScaler? textScaler}) => Layout3dView(
    size: size ?? this.size,
    textScaler: textScaler ?? this.textScaler,
  );

  @override
  bool operator ==(Object other) =>
      other is Layout3dView &&
      other.size == size &&
      other.textScaler == textScaler;

  @override
  int get hashCode => Object.hash(size, textScaler);

  @override
  String toString() => 'Layout3dView($size, textScaler: $textScaler)';
}
