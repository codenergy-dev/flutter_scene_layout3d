import 'dart:ui' show Color;

import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart'
    show BuildContext, StatelessWidget, TextDirection, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show Alignment3d, Constraints3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dMetricsScope,
        SceneAlign3d,
        SceneConstrainedBox3d,
        ScenePadding3d,
        SceneSemantics3d,
        WidgetPageRoute3d;

import '../theme/theme.dart';
import 'material.dart';
import 'overlay_style.dart';
import 'overlay_support.dart';

/// A Material dialog: a surface in front of everything, over a scrim.
///
/// ```dart
/// final confirmed = await showDialog3d<bool>(
///   context: context,
///   builder: (context) => Dialog3d(
///     semanticLabel: 'Delete this file?',
///     child: SceneColumn3d(
///       mainAxisSize: MainAxisSize3d.min,
///       crossAxisAlignment: CrossAxisAlignment3d.start,
///       children: <Widget>[
///         const SceneText3d('Delete this file?'),
///         TextButton3d(
///           label: 'Delete',
///           semanticLabel: 'Delete',
///           onPressed: () => Navigator3d.of(...)?.pop(true),
///         ),
///       ],
///     ),
///   ),
/// );
/// ```
///
/// This is the surface alone, which is what Flutter's own `Dialog` is. There
/// is no `AlertDialog3d` — see *What phase 6 left out* in the catalogue's
/// plan: an alert dialog is a column of a title, some text and a row of
/// buttons, and nothing about that arrangement is three-dimensional.
///
/// ## The depth, which is the part with no Flutter equivalent
///
/// A dialog has to be in front of the whole screen, not merely in front of
/// the body. A `Scaffold3d` has already spent four depth steps on its own
/// slots, and the frontmost of them — the floating action button — is a slab
/// in its own right. So the lift a dialog is inserted at is
/// `Scaffold3d.overlayLift(theme.thickness.depthStep)`, which is one step in
/// front of the last slot the scaffold declares. The two agree by
/// construction: add a slot to `Scaffold3dSlot` and the overlay moves with
/// it.
///
/// `Overlay3d.defaultLift` is **not** that number. It is eight logical
/// pixels, which the layout package describes as a depth-buffer separation
/// rather than a distance, and a Material screen is far deeper than that.
///
/// ## The scrim is geometry
///
/// Material's scrim is black at 32% over the content. Here it is a slab in
/// front of the screen and behind the dialog, `thickness.thin` deep, and
/// every depth rule applies to it: a zero-depth scrim would be coplanar with
/// whatever it covers, and the dialog needs a real step in front of the scrim
/// rather than an implicit one. [showDialog3d] builds that frame itself
/// instead of using `Overlay3dEntry.modal`, whose barrier and content share a
/// plane.
///
/// The 32% alpha is real: `box_decoration3d.fmat` declares `blending: alpha`,
/// so a translucent colour blends. What is still missing from the stack is
/// *subtree* opacity — there is no way to fade an arbitrary child — which is
/// what `ModalBarrier3d`'s documentation means when it says a translucent
/// scrim is not expressible.
class Dialog3d extends StatelessWidget {
  /// Creates a dialog surface.
  const Dialog3d({
    super.key,
    this.style,
    this.semanticLabel,
    this.textDirection,
    this.child,
  });

  /// The tokens to draw with, or null for the theme's.
  final DialogStyle3d? style;

  /// What a screen reader announces the dialog as.
  ///
  /// **State it.** A `Semantics3d` gathers nothing from the labels inside the
  /// dialog, so one without this announces a route with no name.
  final String? semanticLabel;

  /// The direction [semanticLabel] reads in.
  final TextDirection? textDirection;

  /// What the dialog holds.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final resolved = style ?? DialogStyle3d.of(theme);

    return SceneSemantics3d(
      properties: SemanticsProperties(
        scopesRoute: true,
        namesRoute: semanticLabel != null,
        label: semanticLabel,
        textDirection: textDirection,
      ),
      child: ScenePadding3d(
        padding: metrics.dpInsets(resolved.insetPadding),
        child: SceneConstrainedBox3d(
          constraints: Constraints3d(
            minWidth: metrics.dp(resolved.minWidth),
            maxWidth: metrics.dp(resolved.maxWidth),
          ),
          child: Material3d(
            color: resolved.container,
            contentColor: resolved.contentColor,
            shape: resolved.shape,
            elevation: resolved.elevation,
            thickness: resolved.thickness,
            // The container token already encodes the elevation, exactly as a
            // card's and a button's do, so tinting it again double-counts.
            surfaceTint: const Color(0x00000000),
            padding: resolved.padding,
            textStyle: theme.textStyle(
              resolved.textStyle,
              color: resolved.contentColor,
            ),
            // Null, with an align inside: an aligning container fills every
            // bounded axis, and a dialog inside a full-screen frame would
            // come out the size of the screen. This is the shape `Button3d`
            // found in phase 3 and it is the same trap.
            alignment: null,
            child: SceneAlign3d(
              alignment: Alignment3d.frontCenter,
              widthFactor: 1.0,
              heightFactor: 1.0,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Puts a dialog in front of everything and returns what it is popped with.
///
/// The 3D analogue of Flutter's `showDialog`, over `Navigator3d.push`: the
/// route goes on the navigator over the overlay above [context], and the
/// future completes when the route is popped — by a control inside the
/// dialog, by a tap on the scrim, or by the application.
///
/// ```dart
/// final choice = await showDialog3d<String>(
///   context: context,
///   builder: (context) => Dialog3d(child: choices),
/// );
/// ```
///
/// **The modal is in the tree on the frame after the call** — the barrier and
/// the scrim with it, since all three are one widget subtree. That is
/// `WidgetOverlay3dEntry`'s one-frame rule, and Flutter's own `showDialog`
/// has it too: inserting an overlay entry marks the overlay for a rebuild
/// rather than editing the tree in place. A test pumps once.
///
/// There need not be a `Navigator3d` already: one is made over the overlay if
/// there is none, and an application that made its own gets that one, because
/// a navigator registers itself against its overlay.
///
/// [barrierDismissible] false makes the scrim inert without making it
/// invisible — the press is still swallowed, which is what modal means.
Future<T?> showDialog3d<T>({
  required BuildContext context,
  required Widget Function(BuildContext context) builder,
  bool barrierDismissible = true,
  DialogStyle3d? style,
  Alignment3d alignment = Alignment3d.center,
  bool restoreFocus = true,
  String? debugLabel,
}) {
  final theme = Theme3d.of(context);
  final metrics = Layout3dMetricsScope.of(context);
  final resolved = style ?? DialogStyle3d.of(theme);
  final navigator = navigatorOf3d(context);

  late final WidgetPageRoute3d<T> route;
  route = WidgetPageRoute3d<T>(
    layer: overlayLayer3d(theme, metrics),
    // The barrier is built inside the content, not by the entry: the entry's
    // own modal stack has no depth step between the scrim and what it covers.
    modal: false,
    trapFocus: true,
    restoreFocus: restoreFocus,
    alignment: alignment,
    debugLabel: debugLabel ?? 'Dialog3d',
    builder: (context, self) => modalFrame3d(
      alignment: alignment,
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
