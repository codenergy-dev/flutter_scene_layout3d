import 'dart:ui' show Color;

import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart'
    show BuildContext, StatelessWidget, TextDirection, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show Alignment3d, BorderRadius3d, Constraints3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dMetricsScope,
        SceneAlign3d,
        SceneConstrainedBox3d,
        SceneSemantics3d,
        WidgetPageRoute3d;

import '../theme/theme.dart';
import 'material.dart';
import 'overlay_style.dart';
import 'overlay_support.dart';
import 'reading_direction.dart';

/// Which edge a [BottomSheet3d] is anchored to.
///
/// Material has a bottom sheet and a side sheet, and they are the same
/// surface on different edges: full-bleed against one face of the screen,
/// rounded on the two corners away from it. One class rather than two, which
/// is the same call `Divider3d` and `VerticalDivider3d` did *not* make — a
/// divider's indent runs along its own axis and the two need different
/// vocabulary, while a sheet's only difference is where it is pinned.
enum Sheet3dEdge {
  /// Across the bottom: Material's bottom sheet.
  bottom,

  /// Across the top.
  top,

  /// Down the left side: Material's side sheet, in a left-to-right layout.
  left,

  /// Down the right side.
  right;

  /// Where a sheet on this edge sits in the overlay.
  ///
  /// The depth component is **front**, not centre. `Alignment3d.bottomCenter`
  /// centres in depth as well, which would put the sheet inside the lift that
  /// carries it in front of the screen — the trap `docs/traps.md` records for
  /// a padded box's six faces, in its alignment form.
  Alignment3d get alignment => switch (this) {
    Sheet3dEdge.bottom => const Alignment3d(0, 1, -1),
    Sheet3dEdge.top => const Alignment3d(0, -1, -1),
    Sheet3dEdge.left => const Alignment3d(-1, 0, -1),
    Sheet3dEdge.right => const Alignment3d(1, 0, -1),
  };

  /// The shape a sheet on this edge takes, out of [radius].
  ///
  /// Rounded on the two corners away from the edge and square on the two
  /// against it, which is what makes a sheet read as attached to the screen
  /// rather than floating on it.
  BorderRadius3d shapeFor(double radius) => switch (this) {
    Sheet3dEdge.bottom => BorderRadius3d.vertical(top: radius),
    Sheet3dEdge.top => BorderRadius3d.vertical(bottom: radius),
    Sheet3dEdge.left => BorderRadius3d.horizontal(right: radius),
    Sheet3dEdge.right => BorderRadius3d.horizontal(left: radius),
  };

  /// Whether the sheet runs across the screen rather than down it.
  bool get isHorizontal =>
      this == Sheet3dEdge.bottom || this == Sheet3dEdge.top;
}

/// A Material sheet: a surface pinned to one edge of the screen.
///
/// ```dart
/// final picked = await showModalBottomSheet3d<String>(
///   context: context,
///   builder: (context) => BottomSheet3d(
///     semanticLabel: 'Share with',
///     child: SceneColumn3d(
///       mainAxisSize: MainAxisSize3d.min,
///       children: contacts,
///     ),
///   ),
/// );
/// ```
///
/// ## Modal is the caller's choice, and both forms are real
///
/// Material has two sheets that look the same and behave differently. A
/// **modal** sheet is a route over a scrim: it takes the input, it is
/// dismissed by a tap outside, and it returns a value —
/// [showModalBottomSheet3d]. A **persistent** sheet is part of the screen:
/// nothing is dimmed, the app underneath keeps working, and it goes away when
/// the application says so — [showBottomSheet3d]. Neither is a special case of
/// the other and this package ships both, because a catalogue that shipped
/// only the modal one would be missing the half that is actually structural.
///
/// ## A sheet is structure, so it is a structural slab
///
/// `Thickness3d.structural`, 8dp, the same as an app bar and a navigation bar
/// — and deliberately not `raised`, which is a card. A sheet is a piece of the
/// screen that has slid into view, not an object resting on it, and the depth
/// scale is where that distinction is stated. It sits at
/// `Scaffold3d.overlayLift` like every other overlay, so it clears the bars
/// it slides over.
class BottomSheet3d extends StatelessWidget {
  /// Creates a sheet.
  const BottomSheet3d({
    super.key,
    this.edge = Sheet3dEdge.bottom,
    this.style,
    this.semanticLabel,
    this.textDirection,
    this.child,
  });

  /// Which edge the sheet is pinned to.
  final Sheet3dEdge edge;

  /// The tokens to draw with, or null for the theme's.
  final BottomSheetStyle3d? style;

  /// What a screen reader announces the sheet as.
  ///
  /// **State it.** A `Semantics3d` gathers nothing from the labels inside.
  final String? semanticLabel;

  /// The direction [semanticLabel] reads in.
  final TextDirection? textDirection;

  /// What the sheet holds.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final resolved = style ?? BottomSheetStyle3d.of(theme);
    // The style carries one radius for the whole shape; which corners it
    // reaches is the edge's business.
    final shape = edge.shapeFor(resolved.shape.topLeft);

    return SceneSemantics3d(
      properties: SemanticsProperties(
        scopesRoute: true,
        namesRoute: semanticLabel != null,
        label: semanticLabel,
        textDirection: readingDirection3d(context, textDirection),
      ),
      child: SceneConstrainedBox3d(
        constraints: edge.isHorizontal
            ? Constraints3d(maxWidth: metrics.dp(resolved.maxWidth))
            : Constraints3d(maxHeight: metrics.dp(resolved.maxWidth)),
        child: Material3d(
          color: resolved.container,
          contentColor: resolved.contentColor,
          shape: shape,
          elevation: resolved.elevation,
          thickness: resolved.thickness,
          surfaceTint: const Color(0x00000000),
          textStyle: theme.textStyle(
            resolved.textStyle,
            color: resolved.contentColor,
          ),
          alignment: null,
          child: SceneAlign3d(
            alignment: Alignment3d.frontCenter,
            // The sheet shrink-wraps across the edge it is pinned to and
            // spans the other axis: a bottom sheet is as tall as its content
            // and as wide as the screen allows.
            widthFactor: edge.isHorizontal ? null : 1.0,
            heightFactor: edge.isHorizontal ? 1.0 : null,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Slides a sheet in over a scrim and returns what it is popped with.
///
/// The modal form: input goes to the sheet, a tap outside pops it with null,
/// and focus is trapped inside it. Everything [showDialog3d] does, aligned to
/// an edge rather than centred.
Future<T?> showModalBottomSheet3d<T>({
  required BuildContext context,
  required Widget Function(BuildContext context) builder,
  Sheet3dEdge edge = Sheet3dEdge.bottom,
  bool barrierDismissible = true,
  BottomSheetStyle3d? style,
  bool restoreFocus = true,
  String? debugLabel,
}) {
  final theme = Theme3d.of(context);
  final metrics = Layout3dMetricsScope.of(context);
  final resolved = style ?? BottomSheetStyle3d.of(theme);
  final navigator = navigatorOf3d(context);

  late final WidgetPageRoute3d<T> route;
  route = WidgetPageRoute3d<T>(
    layer: overlayLayer3d(theme, metrics),
    modal: false,
    trapFocus: true,
    restoreFocus: restoreFocus,
    alignment: edge.alignment,
    debugLabel: debugLabel ?? 'BottomSheet3d',
    builder: (context, self) => modalFrame3d(
      alignment: edge.alignment,
      scrimColor: resolved.scrimColor,
      scrimThickness: metrics.dp(resolved.scrimThickness),
      depthStep: metrics.dp(theme.thickness.depthStep),
      dismissible: barrierDismissible,
      onDismiss: route.pop,
      child: builder(context),
    ),
  );
  return navigator.push(route);
}

/// Slides a sheet in **without** a scrim, and returns what it is popped with.
///
/// The persistent form: nothing is dimmed, nothing is blocked, and the screen
/// under the sheet keeps working. It is still a route, so the application
/// closes it with `Navigator3d.pop` — or a control inside it does, which is
/// what the returned future is for.
///
/// It does **not** shorten the screen the way Flutter's
/// `Scaffold.showBottomSheet` does. A `Scaffold3d` positions its slots and an
/// overlay is not one of them, by design: an overlay belongs to the surface so
/// that it can outlive the screen that opened it. A sheet that has to make
/// room for itself is a scaffold slot, and that is a different component.
Future<T?> showBottomSheet3d<T>({
  required BuildContext context,
  required Widget Function(BuildContext context) builder,
  Sheet3dEdge edge = Sheet3dEdge.bottom,
  BottomSheetStyle3d? style,
  String? debugLabel,
}) {
  final theme = Theme3d.of(context);
  final metrics = Layout3dMetricsScope.of(context);
  final navigator = navigatorOf3d(context);

  final route = WidgetPageRoute3d<T>(
    layer: overlayLayer3d(theme, metrics),
    modal: false,
    trapFocus: false,
    alignment: edge.alignment,
    debugLabel: debugLabel ?? 'BottomSheet3d.persistent',
    builder: (context, self) =>
        SceneAlign3d(alignment: edge.alignment, child: builder(context)),
  );
  return navigator.push(route);
}
