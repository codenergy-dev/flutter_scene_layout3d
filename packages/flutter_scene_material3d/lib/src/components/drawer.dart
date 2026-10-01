import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show ValueChanged;
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        Directionality,
        InheritedWidget,
        StatelessWidget,
        TextDirection,
        Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show
        Constraints3d,
        CrossAxisAlignment3d,
        EdgeInsetsGeometry3d,
        MainAxisSize3d,
        Size3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dMetricsScope,
        SceneColumn3d,
        SceneConstrainedBox3d,
        SceneExpanded3d,
        SceneIgnorePointer3d,
        SceneListView3d,
        SceneMotionTransition3d,
        ScenePadding3d,
        SceneRow3d,
        SceneSafeArea3d,
        SceneSemantics3d,
        SceneSizedBox3d,
        SceneTapTarget3d,
        SceneText3d,
        WidgetPageRoute3d;

import '../theme/theme.dart';
import 'bottom_sheet.dart' show Sheet3dEdge;
import 'drawer_style.dart';
import 'ink_well.dart';
import 'material.dart';
import 'overlay_support.dart';
import 'reading_direction.dart';
import 'text_style.dart';

/// Which side of the screen a drawer comes in from, in reading order.
///
/// Flutter's `DrawerAlignment`. **The start is the left in left to right and
/// the right in right to left**, which is the one thing a drawer has that a
/// side sheet's `Sheet3dEdge.left` does not: a drawer is anchored to where
/// reading begins.
enum DrawerAlignment3d {
  /// The edge reading starts from: Flutter's `Scaffold.drawer`.
  start,

  /// The edge reading ends at: Flutter's `Scaffold.endDrawer`.
  end;

  /// Whether a drawer here is against the left edge of the screen, reading in
  /// [direction].
  bool isLeftIn(TextDirection direction) =>
      (this == DrawerAlignment3d.start) == (direction == TextDirection.ltr);
}

/// A Material drawer: a full-height surface against one edge of the screen.
///
/// ```dart
/// IconButton3d(
///   icon: Icons.menu,
///   semanticLabel: 'Open the menu',
///   onPressed: () => showDrawer3d<void>(
///     context: context,
///     builder: (context) => Drawer3d(
///       semanticLabel: 'Menu',
///       child: SceneListView3d(
///         crossAxisAlignment: CrossAxisAlignment3d.stretch,
///         depthAxisAlignment: CrossAxisAlignment3d.start,
///         children: entries,
///       ),
///     ),
///   ),
/// )
/// ```
///
/// **A list in a drawer wants `depthAxisAlignment: start`.** A list centres
/// its items in depth unless told otherwise, and a drawer is an 8dp slab: a
/// centred item sits behind the face that hides it. `NavigationDrawer3d`
/// says so for its own list; a drawer of your own has to.
///
/// Flutter's `Drawer`: 304dp wide, `surfaceContainerLow`, level 1, as tall
/// as the room it is given, with the two corners away from its edge rounded
/// 16dp. It is the surface alone — [NavigationDrawer3d] is this with
/// Material's list of destinations in it — and everything it is made of is
/// in [DrawerStyle3d].
///
/// ## It is shown, rather than being a slot
///
/// Flutter's drawer belongs to a `Scaffold` and opens with
/// `Scaffold.of(context).openDrawer()`. Here it opens with [showDrawer3d],
/// because a `Scaffold3d` has no overlay slots at all: a dialog, a sheet or a
/// menu belongs to the surface rather than to the screen, so that it can
/// outlive the screen that opened it and its scrim can cover the whole view.
/// A drawer is a modal side sheet in every way that matters, and it is shown
/// the way one is.
///
/// It can also stand in a row beside a body, as Material's *standard*
/// drawer does on a wide screen; then it is a surface like a rail, and
/// nothing opens it.
///
/// ## The corners follow the edge
///
/// Shown by [showDrawer3d], it rounds the side away from the edge it came
/// from — the right corners for a start drawer in left to right, the left
/// ones in right to left. Anywhere else it rounds its end side, as Flutter's
/// start drawer does.
///
/// ## What it announces
///
/// [semanticLabel] names the route, as a dialog's does. Flutter's drawer
/// falls back to a localized "Navigation menu" on Android; that is a string
/// the catalogue would be inventing, in one language, and the work of giving
/// the catalogue its words belongs to the language plan rather than to each
/// component that wants one. So **state it**.
class Drawer3d extends StatelessWidget {
  /// Creates a drawer.
  const Drawer3d({
    super.key,
    this.backgroundColor,
    this.elevation,
    this.width,
    this.style,
    this.semanticLabel,
    this.textDirection,
    this.child,
  });

  /// The surface's colour, or null for the style's `surfaceContainerLow`.
  final Color? backgroundColor;

  /// How far the drawer stands off what it is in front of, in logical pixels,
  /// or null for the style's level 1.
  final double? elevation;

  /// How wide it is, in logical pixels, or null for the style's 304.
  final double? width;

  /// The whole token set, or null for `DrawerStyle3d.of(theme)`.
  final DrawerStyle3d? style;

  /// What a screen reader announces the drawer as. **State it.**
  final String? semanticLabel;

  /// The direction [semanticLabel] reads in.
  final TextDirection? textDirection;

  /// What the drawer holds.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final resolved = style ?? DrawerStyle3d.of(theme);
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final edge = _DrawerPlacement3d.maybeOf(context) ?? DrawerAlignment3d.start;

    return SceneSemantics3d(
      properties: SemanticsProperties(
        scopesRoute: true,
        namesRoute: semanticLabel != null,
        label: semanticLabel,
        textDirection: readingDirection3d(context, textDirection),
      ),
      // As wide as the style says and as tall as the room it is given, which
      // is Flutter's `BoxConstraints.expand(width: 304)` — and loose in depth,
      // so the surface below is as deep as its own thickness rather than as
      // deep as the overlay it was put in.
      child: SceneConstrainedBox3d(
        constraints: Constraints3d(
          minWidth: metrics.dp(width ?? resolved.width),
          maxWidth: metrics.dp(width ?? resolved.width),
          minHeight: double.infinity,
        ),
        child: Material3d(
          color: backgroundColor ?? resolved.container,
          contentColor: resolved.contentColor,
          shape: resolved.shapeFor(leftEdge: edge.isLeftIn(direction)),
          elevation: elevation ?? resolved.elevation,
          thickness: resolved.thickness,
          // The container token already says how raised the drawer is.
          surfaceTint: const Color(0x00000000),
          alignment: null,
          child: child,
        ),
      ),
    );
  }
}

/// Which edge [showDrawer3d] put a drawer against, for the drawer to round
/// the right corners.
///
/// Not exported. Flutter's `Drawer` asks its `DrawerController` the same
/// question; here the route is what knows.
class _DrawerPlacement3d extends InheritedWidget {
  const _DrawerPlacement3d({required this.alignment, required super.child});

  final DrawerAlignment3d alignment;

  static DrawerAlignment3d? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_DrawerPlacement3d>()
      ?.alignment;

  @override
  bool updateShouldNotify(_DrawerPlacement3d oldWidget) =>
      alignment != oldWidget.alignment;
}

/// Material's navigation drawer: a [Drawer3d] holding a list of
/// destinations, with whatever headings and dividers go between them.
///
/// ```dart
/// NavigationDrawer3d(
///   selectedIndex: screen,
///   onDestinationSelected: (index) {
///     setState(() => screen = index);
///     Navigator3d.of(SceneOverlay3d.of(context))?.pop();
///   },
///   semanticLabel: 'Mail',
///   children: const <Widget>[
///     NavigationDrawerDestination3d(icon: Icon3d(Icons.inbox), label: 'Inbox'),
///     NavigationDrawerDestination3d(icon: Icon3d(Icons.send), label: 'Sent'),
///     Divider3d(),
///     NavigationDrawerDestination3d(icon: Icon3d(Icons.delete), label: 'Trash'),
///   ],
/// )
/// ```
///
/// Flutter's `NavigationDrawer`, and the API is Flutter's on purpose:
/// [children] is a list of widgets, and the ones that are a
/// [NavigationDrawerDestination3d] are numbered from zero, in order, skipping
/// everything else. A ported drawer keeps its section headings and its
/// dividers exactly where they were, and [selectedIndex] still counts only
/// the destinations.
///
/// ## The indicator is the destination
///
/// Flutter draws the selection as a pill behind the destination's icon and
/// label, 336dp wide in a tile 280dp wide, so it fills the tile. Here that is
/// the destination's own surface taking `secondaryContainer`, a stadium the
/// size of the tile, with nothing behind it — which is why this component,
/// unlike `NavigationBar3d`, needs no depth step between a pill and the glyph
/// on it. The selection is a token substitution and does not animate; nor
/// does the bar's.
///
/// ## What it holds, and how it scrolls
///
/// A [header] at the top, a [footer] at the foot, and the [children] in a
/// list between them that scrolls when there are more than fit, clear of the
/// status bar and the notch on a surface that stands in for the view — and
/// not of the home indicator, which Flutter's drawer runs under too.
class NavigationDrawer3d extends StatelessWidget {
  /// Creates a navigation drawer.
  const NavigationDrawer3d({
    super.key,
    required this.children,
    this.header,
    this.footer,
    this.selectedIndex = 0,
    this.onDestinationSelected,
    this.backgroundColor,
    this.elevation,
    this.indicatorColor,
    this.tilePadding,
    this.style,
    this.drawerStyle,
    this.semanticLabel,
    this.textDirection,
  });

  /// The destinations, and whatever goes between them.
  final List<Widget> children;

  /// What sits above the list, and does not scroll with it.
  final Widget? header;

  /// What sits below it.
  final Widget? footer;

  /// Which destination is current, counting destinations only, or null for
  /// none.
  final int? selectedIndex;

  /// Called with the index of the destination the viewer chose.
  ///
  /// The drawer does not close itself, as Flutter's does not: an
  /// application that wants it closed pops the route in here.
  final ValueChanged<int>? onDestinationSelected;

  /// The surface's colour, or null for the drawer style's.
  final Color? backgroundColor;

  /// How far the drawer stands off what it is in front of, or null for the
  /// drawer style's.
  final double? elevation;

  /// The selected destination's colour, or null for `secondaryContainer`.
  final Color? indicatorColor;

  /// Space either side of each destination, or null for 12dp.
  final EdgeInsetsGeometry3d? tilePadding;

  /// The destinations' tokens, or null for
  /// `NavigationDrawerStyle3d.of(theme)`.
  final NavigationDrawerStyle3d? style;

  /// The surface's tokens, or null for `DrawerStyle3d.of(theme)`.
  final DrawerStyle3d? drawerStyle;

  /// What a screen reader announces the drawer as.
  final String? semanticLabel;

  /// The direction the announcements read in.
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final resolved = style ?? NavigationDrawerStyle3d.of(theme);
    var index = 0;
    final numbered = <Widget>[
      for (final child in children)
        if (child is NavigationDrawerDestination3d)
          _DestinationInfo3d(
            index: index,
            selected: index == selectedIndex,
            onTap: _tapFor(index++),
            style: resolved,
            indicatorColor: indicatorColor,
            tilePadding: tilePadding,
            textDirection: textDirection,
            child: child,
          )
        else
          child,
    ];

    return Drawer3d(
      backgroundColor: backgroundColor,
      elevation: elevation,
      style: drawerStyle,
      semanticLabel: semanticLabel,
      textDirection: textDirection,
      child: SceneSafeArea3d(
        bottom: false,
        child: SceneColumn3d(
          crossAxisAlignment: CrossAxisAlignment3d.stretch,
          // On the drawer's face, for the reason every column on a surface
          // is: a flex centres in depth only when it is told to.
          depthAxisAlignment: CrossAxisAlignment3d.start,
          children: <Widget>[
            ?header,
            SceneExpanded3d(
              child: SceneListView3d(
                crossAxisAlignment: CrossAxisAlignment3d.stretch,
                // On the face. A list centres its items in depth unless it is
                // told otherwise — the right default for a list of objects —
                // and a drawer is an 8dp slab, so centred, every destination
                // sat behind the face that hid it.
                depthAxisAlignment: CrossAxisAlignment3d.start,
                children: numbered,
              ),
            ),
            ?footer,
          ],
        ),
      ),
    );
  }

  void Function()? _tapFor(int index) {
    final callback = onDestinationSelected;
    return callback == null ? null : () => callback(index);
  }
}

/// What a destination needs to know about its place in the drawer.
///
/// Flutter's `_NavigationDrawerDestinationInfo`, and the reason a destination
/// can be a widget in a list of widgets rather than a description handed to
/// the drawer: the drawer numbers the ones it finds and tells each its number.
class _DestinationInfo3d extends InheritedWidget {
  const _DestinationInfo3d({
    required this.index,
    required this.selected,
    required this.onTap,
    required this.style,
    required this.indicatorColor,
    required this.tilePadding,
    required this.textDirection,
    required super.child,
  });

  final int index;
  final bool selected;
  final void Function()? onTap;
  final NavigationDrawerStyle3d style;
  final Color? indicatorColor;
  final EdgeInsetsGeometry3d? tilePadding;
  final TextDirection? textDirection;

  static _DestinationInfo3d of(BuildContext context) {
    final info = context
        .dependOnInheritedWidgetOfExactType<_DestinationInfo3d>();
    assert(
      info != null,
      'A NavigationDrawerDestination3d has to be one of a '
      'NavigationDrawer3d\'s children: the drawer is what numbers it.',
    );
    return info!;
  }

  @override
  bool updateShouldNotify(_DestinationInfo3d oldWidget) =>
      index != oldWidget.index ||
      selected != oldWidget.selected ||
      onTap != oldWidget.onTap ||
      style != oldWidget.style ||
      indicatorColor != oldWidget.indicatorColor ||
      tilePadding != oldWidget.tilePadding ||
      textDirection != oldWidget.textDirection;
}

/// One place a [NavigationDrawer3d] can take you.
///
/// A widget, as Flutter's `NavigationDrawerDestination` is, so that it can
/// sit among headings and dividers in the drawer's list. Its [label] is a
/// **string**, for the reason a `NavigationDestination3d`'s is: a
/// `Semantics3d` gathers nothing from below it, and taking the string lets
/// the destination build the visible label and the announcement out of one
/// thing that cannot disagree with itself.
///
/// It announces its label as a button, with `selected` on the current one.
class NavigationDrawerDestination3d extends StatelessWidget {
  /// Creates a destination.
  const NavigationDrawerDestination3d({
    super.key,
    required this.icon,
    required this.label,
    this.selectedIcon,
    this.enabled = true,
    this.backgroundColor,
  });

  /// The glyph shown when this destination is not selected.
  final Widget icon;

  /// What the destination is called, shown beside the icon and announced.
  final String label;

  /// The glyph shown when it is, or null to keep [icon].
  final Widget? selectedIcon;

  /// Whether this destination responds to a pointer.
  final bool enabled;

  /// The tile's colour when it is not selected, or null for none.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final info = _DestinationInfo3d.of(context);
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final style = info.style;
    final active = enabled && info.onTap != null;
    final content = !enabled
        ? theme.colorScheme.disabledContent
        : (info.selected ? style.selectedContentColor : style.contentColor);

    final row = SceneRow3d(
      mainAxisSize: MainAxisSize3d.max,
      crossAxisAlignment: CrossAxisAlignment3d.center,
      depthAxisAlignment: CrossAxisAlignment3d.start,
      children: <Widget>[
        SceneSizedBox3d(width: metrics.dp(style.iconInset)),
        // Glyphs answer hit tests on their own account; the well is what a
        // ray is meant to find here.
        SceneIgnorePointer3d(
          child: info.selected ? (selectedIcon ?? icon) : icon,
        ),
        SceneSizedBox3d(width: metrics.dp(style.labelGap)),
        SceneExpanded3d(
          child: SceneTextStyle3d(
            style: style.labelStyle,
            color: content,
            child: SceneIgnorePointer3d(child: SceneText3d(label)),
          ),
        ),
      ],
    );

    // Its own surface, so its own wash: an `InkWell3d` washes the enclosing
    // `Material3d`, and one placed straight on the drawer would light the
    // whole drawer up under one finger. Selected, the surface *is* the
    // indicator.
    final surface = Material3d(
      color: info.selected
          ? (info.indicatorColor ?? style.indicatorColor)
          : (backgroundColor ?? const Color(0x00000000)),
      contentColor: content,
      shape: style.indicatorShape,
      elevation: theme.elevation.level0,
      thickness: style.destinationThickness,
      surfaceTint: const Color(0x00000000),
      alignment: null,
      child: active
          ? InkWell3d(
              // One target, and it is the one outside this panel.
              minimumSize: Size3d.zero,
              onTap: info.onTap,
              child: row,
            )
          : row,
    );

    return ScenePadding3d(
      padding: metrics.dpInsets(info.tilePadding ?? style.tilePadding),
      child: SceneTapTarget3d(
        child: SceneSemantics3d(
          properties: SemanticsProperties(
            button: true,
            enabled: active,
            selected: info.selected,
            label: label,
            textDirection: readingDirection3d(context, info.textDirection),
            onTap: active ? info.onTap : null,
          ),
          child: SceneSizedBox3d(
            height: metrics.dp(style.tileHeight),
            child: surface,
          ),
        ),
      ),
    );
  }
}

/// Slides a drawer in from an edge over a scrim, and returns what it is
/// popped with.
///
/// The way a drawer opens here, in place of Flutter's
/// `Scaffold.of(context).openDrawer()`; see [Drawer3d] for why. Everything a
/// modal sheet does — input goes to the drawer, a tap on the scrim or Escape
/// closes it, focus is trapped inside it and handed back after — from the
/// [alignment] edge, which is the left in left to right and the right in
/// right to left for [DrawerAlignment3d.start].
///
/// The scrim is Flutter's `Colors.black54` rather than Material's 32%, and
/// the drawer arrives over `medium1` on the emphasized curves: see
/// [DrawerStyle3d].
///
/// ```dart
/// IconButton3d(
///   icon: Icons.menu,
///   semanticLabel: 'Open the menu',
///   onPressed: () => showDrawer3d<void>(
///     context: context,
///     builder: (context) => NavigationDrawer3d(children: destinations),
///   ),
/// )
/// ```
Future<T?> showDrawer3d<T>({
  required BuildContext context,
  required Widget Function(BuildContext context) builder,
  DrawerAlignment3d alignment = DrawerAlignment3d.start,
  bool barrierDismissible = true,
  DrawerStyle3d? style,
  bool restoreFocus = true,
  String? debugLabel,
}) {
  final theme = Theme3d.of(context);
  final metrics = Layout3dMetricsScope.of(context);
  final resolved = style ?? DrawerStyle3d.of(theme);
  final navigator = navigatorOf3d(context);
  final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
  final edge = alignment.isLeftIn(direction)
      ? Sheet3dEdge.left
      : Sheet3dEdge.right;
  final arrival = resolved.arrival.copyWith(motion: edge.offscreen);

  late final WidgetPageRoute3d<T> route;
  route = WidgetPageRoute3d<T>(
    layer: overlayLayer3d(theme, metrics),
    transition: arrival.transition,
    modal: false,
    trapFocus: true,
    // The route's too, not only the barrier's: it is what Escape asks.
    barrierDismissible: barrierDismissible,
    restoreFocus: restoreFocus,
    alignment: edge.alignment,
    debugLabel: debugLabel ?? 'Drawer3d',
    builder: (context, self) => modalFrame3d(
      alignment: edge.alignment,
      scrimColor: resolved.scrimColor,
      scrimThickness: metrics.dp(resolved.scrimThickness),
      depthStep: metrics.dp(theme.thickness.depthStep),
      dismissible: barrierDismissible,
      onDismiss: route.pop,
      scrimFade: route.animation,
      child: SceneMotionTransition3d(
        animation: route.animation,
        motion: arrival.motion,
        child: _DrawerPlacement3d(
          alignment: alignment,
          child: builder(context),
        ),
      ),
    ),
  );
  return navigator.push(route);
}
