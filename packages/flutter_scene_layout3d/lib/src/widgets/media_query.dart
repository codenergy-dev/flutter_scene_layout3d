import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, DiagnosticsProperty;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        InheritedWidget,
        Key,
        Orientation,
        StatelessWidget,
        Widget;

import '../geometry/edge_insets3d.dart';
import '../geometry/size3d.dart';
import 'layouts.dart';
import 'surface.dart';

/// What the enclosing surface knows about itself: how big it is, and what
/// part of it the platform has already spent.
///
/// The 3D counterpart of `MediaQueryData`, and a deliberately short one. Every
/// figure here is in **logical pixels**, because that is the frame a screen is
/// specified in — a phone breakpoint is 600dp, not six world units — and
/// because the platform speaks it. Convert with the unit contract before a
/// figure reaches a box:
///
/// ```dart
/// final media = MediaQuery3d.of(context);
/// final metrics = Layout3dMetricsScope.of(context);
/// if (media.size.width >= 600) {
///   return SceneRow3d(children: [rail, SceneExpanded3d(child: body)]);
/// }
/// return SceneColumn3d(children: [SceneExpanded3d(child: body), bar]);
/// ```
///
/// **The reader's font setting is not here.** It is
/// [Layout3dMetrics.textScaler], because the *layout* measures with it — a
/// `Text3d` reads it inside `performLayout`, where there is no
/// `BuildContext` — and one number with two homes is one number that will
/// eventually disagree with itself. This is the first place a reader coming
/// from Flutter looks; it is one line away, on `Layout3dMetricsScope.of`.
///
/// **There is no `devicePixelRatio` either**, and that absence is a statement.
/// A ratio of logical pixels to real ones is a promise only a camera-bound
/// surface can keep: a panel the viewer can walk toward covers a different
/// number of real pixels every frame. What a rasterizer actually wants is
/// [Layout3dMetrics.logicalPixelsPerUnit], which promises exactly what it
/// says.
class MediaQuery3dData {
  /// Creates a description of a surface.
  const MediaQuery3dData({
    required this.size,
    this.padding = EdgeInsets3d.zero,
  });

  /// The surface's own extent, in logical pixels.
  ///
  /// For a surface bound to the camera with
  /// [Layout3dCameraBinding.screenFilling] this is the view's logical size:
  /// that panel *is* the screen, and the binding's own arithmetic makes the
  /// two equal.
  ///
  /// For every other surface it is what the surface was given — a
  /// `SceneLayout3d`'s `size` or `constraints`, divided by the unit rate. An
  /// axis the surface was given no bound on reports **infinity**, which is
  /// honest rather than unhelpful: a plane that shrink-wraps its content has
  /// no screen size until the content decides, and `SceneLayoutBuilder3d` is
  /// what answers a question about the room a box actually got.
  final Size3d size;

  /// What the platform has already spent of [size], in logical pixels.
  ///
  /// The safe area: the notch, the status bar, the home indicator. **Zero for
  /// every surface that does not stand in for the view**, which is every
  /// surface but a [Layout3dCameraBinding.screenFilling] one — a plane
  /// hanging on a wall in a room does not have a notch, and the question does
  /// not apply to it rather than having the answer zero by accident.
  ///
  /// `front` and `back` are always zero. No platform reports a depth inset;
  /// the type is the package's own so that it converts and composes like
  /// every other inset.
  ///
  /// Consume it with [SceneSafeArea3d] rather than by hand, so that whatever
  /// is below stops being told about an inset that has already been spent.
  final EdgeInsets3d padding;

  /// Whether the surface is wider than it is tall.
  Orientation get orientation =>
      size.width > size.height ? Orientation.landscape : Orientation.portrait;

  /// A copy with the given fields replaced.
  MediaQuery3dData copyWith({Size3d? size, EdgeInsets3d? padding}) =>
      MediaQuery3dData(
        size: size ?? this.size,
        padding: padding ?? this.padding,
      );

  /// A copy with the named sides of [padding] set to zero.
  ///
  /// What a widget that has *consumed* an inset hands down, so that a second
  /// one below it does not pad for the same notch twice. [SceneSafeArea3d]
  /// does this for you.
  MediaQuery3dData removePadding({
    bool removeLeft = false,
    bool removeTop = false,
    bool removeRight = false,
    bool removeBottom = false,
  }) {
    if (!(removeLeft || removeTop || removeRight || removeBottom)) return this;
    return copyWith(
      padding: EdgeInsets3d.only(
        left: removeLeft ? 0.0 : padding.left,
        top: removeTop ? 0.0 : padding.top,
        right: removeRight ? 0.0 : padding.right,
        bottom: removeBottom ? 0.0 : padding.bottom,
        front: padding.front,
        back: padding.back,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MediaQuery3dData &&
      other.size == size &&
      other.padding == padding;

  @override
  int get hashCode => Object.hash(size, padding);

  @override
  String toString() => 'MediaQuery3dData($size, padding: $padding)';
}

/// Publishes a [MediaQuery3dData] to the widgets below it.
///
/// `SceneLayout3d` puts one at the root of every surface, so a screen built on
/// this package can ask how big it is without being told. Insert one yourself
/// to say something the package cannot derive — a panel set into a physical
/// frame, a test that wants a phone-sized screen — or to take an inset away
/// from a subtree that has already been padded for it.
///
/// ```dart
/// MediaQuery3d(
///   // A panel in a bezel: the top forty logical pixels are behind trim.
///   data: MediaQuery3d.of(context).copyWith(
///     padding: const EdgeInsets3d.only(top: 40),
///   ),
///   child: screen,
/// )
/// ```
///
/// Unlike [Layout3dMetricsScope], which reports what a single surface
/// measures with and therefore has no public constructor, this one is meant to
/// be inserted: an inset is *consumed*, and consuming it means telling the
/// subtree below that it is gone.
class MediaQuery3d extends InheritedWidget {
  /// Publishes [data] to [child] and everything below it.
  const MediaQuery3d({super.key, required this.data, required super.child});

  /// What the surface below this point knows about itself.
  final MediaQuery3dData data;

  /// The data in force above [context], or null when there is no surface.
  ///
  /// The caller becomes a dependent: it rebuilds when the data changes.
  static MediaQuery3dData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MediaQuery3d>()?.data;

  /// The data in force above [context].
  ///
  /// The caller becomes a dependent: it rebuilds when the data changes.
  /// Asserts when there is no surface above, because the alternative —
  /// answering a made-up size — is a screen that branches on a number nothing
  /// produced.
  static MediaQuery3dData of(BuildContext context) {
    final data = maybeOf(context);
    assert(
      data != null,
      'MediaQuery3d.of() found no surface above this context. A screen\'s own '
      'measurements are published by SceneLayout3d, so a widget that reads '
      'them has to be built inside one; use maybeOf() if being outside is a '
      'legitimate state.',
    );
    return data!;
  }

  /// Wraps [child] in a [MediaQuery3d] with the named sides of the padding
  /// removed, the way `MediaQuery.removePadding` does.
  static Widget removePadding({
    Key? key,
    required BuildContext context,
    bool removeLeft = false,
    bool removeTop = false,
    bool removeRight = false,
    bool removeBottom = false,
    required Widget child,
  }) => MediaQuery3d(
    key: key,
    data: MediaQuery3d.of(context).removePadding(
      removeLeft: removeLeft,
      removeTop: removeTop,
      removeRight: removeRight,
      removeBottom: removeBottom,
    ),
    child: child,
  );

  @override
  bool updateShouldNotify(MediaQuery3d oldWidget) => oldWidget.data != data;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<MediaQuery3dData>('data', data));
  }
}

/// Insets its child by the part of the surface the platform has spent.
///
/// Flutter's `SafeArea`, on a plane: it reads [MediaQuery3d]'s padding,
/// converts it through the surface's unit contract, pads with it, and
/// republishes the data with what it consumed removed, so a `SceneSafeArea3d`
/// inside another one pads nothing.
///
/// ```dart
/// SceneSafeArea3d(
///   child: SceneColumn3d(children: [appBar, body]),
/// )
/// ```
///
/// **On most surfaces it is a no-op, by design.** Only a panel bound to the
/// camera with [Layout3dCameraBinding.screenFilling] stands in for the view
/// and inherits its notch; a panel on a wall has none, so this pads it by
/// [minimum] and nothing more. Writing it anyway is right: the same screen
/// ported onto a camera-bound surface needs it, and it costs one box that
/// insets by zero.
class SceneSafeArea3d extends StatelessWidget {
  /// Creates a box that avoids the surface's spent edges.
  const SceneSafeArea3d({
    super.key,
    this.left = true,
    this.top = true,
    this.right = true,
    this.bottom = true,
    this.minimum = EdgeInsets3d.zero,
    required this.child,
  });

  /// Whether to avoid the inset on the left edge.
  final bool left;

  /// Whether to avoid the inset on the top edge.
  final bool top;

  /// Whether to avoid the inset on the right edge.
  final bool right;

  /// Whether to avoid the inset on the bottom edge.
  final bool bottom;

  /// The least padding to apply, in **logical pixels**.
  ///
  /// Used where it is larger than the platform's own inset, side by side, the
  /// way Flutter's `SafeArea.minimum` is. In dp because everything a `build`
  /// method states is in dp; the conversion to world units happens here.
  final EdgeInsets3d minimum;

  /// The layout to inset.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery3d.of(context).padding;
    final metrics = Layout3dMetricsScope.of(context);
    final insets = EdgeInsets3d.only(
      left: _resolve(left, padding.left, minimum.left),
      top: _resolve(top, padding.top, minimum.top),
      right: _resolve(right, padding.right, minimum.right),
      bottom: _resolve(bottom, padding.bottom, minimum.bottom),
    );
    return MediaQuery3d.removePadding(
      context: context,
      removeLeft: left,
      removeTop: top,
      removeRight: right,
      removeBottom: bottom,
      child: ScenePadding3d(padding: metrics.dpInsets(insets), child: child),
    );
  }

  static double _resolve(bool avoid, double inset, double minimum) =>
      avoid && inset > minimum ? inset : minimum;
}
