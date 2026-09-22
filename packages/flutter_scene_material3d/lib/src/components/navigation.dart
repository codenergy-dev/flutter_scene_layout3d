import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart'
    show BuildContext, Directionality, StatelessWidget, TextDirection, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show
        Alignment3d,
        CrossAxisAlignment3d,
        MainAxisAlignment3d,
        MainAxisSize3d,
        Size3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dMetricsScope,
        SceneAlign3d,
        SceneColumn3d,
        SceneExpanded3d,
        SceneIgnorePointer3d,
        SceneRow3d,
        SceneSemantics3d,
        SceneSizedBox3d,
        SceneStack3d,
        MediaQuery3d,
        SceneSafeArea3d,
        SceneTapTarget3d,
        SceneText3d,
        SceneTextScaling3d;

import '../theme/theme.dart';
import '../theme/theme_data.dart';
import 'ink_well.dart';
import 'material.dart';
import 'navigation_style.dart';
import 'text_style.dart';
import 'reading_direction.dart';

/// One place a [NavigationBar3d] or a [NavigationRail3d] can take you.
///
/// ```dart
/// const NavigationDestination3d(
///   icon: Icon3d(Icons.inbox),
///   selectedIcon: Icon3d(Icons.inbox),
///   label: 'Inbox',
/// )
/// ```
///
/// **The label is a `String`, not a widget**, and that is the phase-4 rule
/// applied rather than a shortcut: a `Semantics3d` publishes what it is given
/// and gathers nothing from below, so a destination that took a widget would
/// have to be told its own name twice. Taking the string means the component
/// builds the visible label *and* the announcement out of one thing that
/// cannot disagree with itself.
@immutable
class NavigationDestination3d {
  /// Creates a destination.
  const NavigationDestination3d({
    required this.icon,
    required this.label,
    this.selectedIcon,
    this.enabled = true,
  });

  /// The glyph shown when this destination is not selected.
  final Widget icon;

  /// What the destination is called, shown under the icon and announced.
  final String label;

  /// The glyph shown when it is, or null to keep [icon].
  final Widget? selectedIcon;

  /// Whether this destination responds to a pointer.
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is NavigationDestination3d &&
      other.icon == icon &&
      other.label == label &&
      other.selectedIcon == selectedIcon &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(icon, label, selectedIcon, enabled);

  @override
  String toString() => 'NavigationDestination3d($label)';
}

/// Called with the index of the destination the viewer chose.
typedef NavigationDestination3dCallback = void Function(int index);

/// The bar across the bottom of a compact screen.
///
/// ```dart
/// NavigationBar3d(
///   selectedIndex: index,
///   destinations: const <NavigationDestination3d>[
///     NavigationDestination3d(icon: Icon3d(Icons.inbox), label: 'Inbox'),
///     NavigationDestination3d(icon: Icon3d(Icons.send), label: 'Sent'),
///   ],
///   onDestinationSelected: (i) => setState(() => index = i),
/// )
/// ```
///
/// 80dp tall, at elevation level 2, on `surfaceContainer`, with the selected
/// destination marked by a pill. Everything it is made of is in
/// [NavigationStyle3d].
///
/// ## The pill, and why it needed nothing new
///
/// Material's selection indicator is a stadium behind the selected icon. A
/// stadium is a rounded rectangle whose radius clears half its shorter side,
/// which `ShapeScale3d.full` already is, so the indicator is one more
/// `Material3d` — 64 by 32, `secondaryContainer`, `shape.full` — and the
/// catalogue's own primitive draws it.
///
/// What it *did* need is a depth step. The pill and the glyph on it are
/// coplanar otherwise, and two coplanar surfaces z-fight: the icon comes out
/// in patches, differently on every frame and every driver, with nothing to
/// say why. `NavigationStyle3d.indicatorDepthStep` is that step, and it is a
/// token rather than a constant because the pill's own depth is one.
///
/// ## Why every destination is its own surface
///
/// An `InkWell3d` finds the **enclosing** `Material3d` and washes it. A well
/// placed straight inside the bar would therefore light the entire bar up
/// under one finger — the trap `docs/traps.md` records for a chip's delete
/// icon, in a component where it would be much more visible. So each
/// destination is a `Material3d` of its own, transparent, one thickness step
/// proud of the bar, with its own well inside it.
///
/// ## What it announces
///
/// Each destination announces its own label, as a button, with `selected`
/// set on the one that is. The bar itself announces nothing: there is no
/// single sentence for "a navigation bar" that a reader would rather hear
/// than the destination it has landed on.
class NavigationBar3d extends StatelessWidget {
  /// Creates a navigation bar.
  const NavigationBar3d({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    this.onDestinationSelected,
    this.style,
    this.backgroundColor,
    this.elevation,
    this.thickness,
    this.height,
    this.textDirection,
  }) : assert(selectedIndex >= 0);

  /// Why a bar with one destination is refused, in `build`.
  ///
  /// The check cannot be a constructor assert: a `const` constructor's
  /// asserts are evaluated at compile time, and `List.length` is not a
  /// constant expression there, so keeping the widget `const`-constructible
  /// — which is what makes an unchanged rebuild free — means the check moves
  /// to `build`. The same is true of `NavigationRail3d`.
  /// How far a destination's label grows with the reader's font setting:
  /// 1.3, Flutter's `_kMaxLabelTextScaleFactor`.
  ///
  /// The labels grow, and then stop, so that a bar of 12sp labels under 24dp
  /// icons keeps that hierarchy at any setting. The icons do not grow at
  /// all, which is `Icon3d`'s own rule. The rail has no ceiling, as
  /// Flutter's has none: its destinations stack along its length, which has
  /// room for them.
  static const double maxLabelTextScaleFactor = 1.3;

  static const String tooFewDestinations =
      'A NavigationBar3d needs at least two destinations. Material has no '
      'appearance for a bar with one, and a bar that cannot take you '
      'anywhere else is a label.';

  /// Where the bar can take you, in order.
  final List<NavigationDestination3d> destinations;

  /// Which destination is current.
  final int selectedIndex;

  /// Called with the index of the destination the viewer chose, or null for
  /// a bar that is not interactive.
  final NavigationDestination3dCallback? onDestinationSelected;

  /// The whole token set, or null for
  /// `NavigationStyle3d.of(theme, NavigationVariant3d.bar)`.
  final NavigationStyle3d? style;

  /// The slab's colour, or null for the style's `surfaceContainer`.
  final Color? backgroundColor;

  /// How far the bar stands off the screen, in logical pixels.
  final double? elevation;

  /// How deep the slab is, in logical pixels.
  final double? thickness;

  /// How tall the bar is, in logical pixels, or null for the style's 80.
  final double? height;

  /// The direction the destination labels read in.
  final TextDirection? textDirection;

  /// The style in force.
  NavigationStyle3d styleOf(Theme3dData theme) =>
      style ?? NavigationStyle3d.of(theme, NavigationVariant3d.bar);

  @override
  Widget build(BuildContext context) {
    assert(destinations.length >= 2, tooFewDestinations);
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final resolved = styleOf(theme);
    final inset = MediaQuery3d.of(context).padding;

    // Grown by the part of the surface the platform has spent at the bottom,
    // as Flutter's bar is: the container runs down behind the home indicator
    // and the destinations stay clear of it. The top inset is normally zero
    // by the time a bar sees it — a `Scaffold3d` takes it away from this
    // slot — and is added for the same reason if it is not.
    return SceneSizedBox3d(
      height: metrics.dp(
        (height ?? resolved.extent) + inset.top + inset.bottom,
      ),
      child: Material3d(
        color: backgroundColor ?? resolved.container,
        contentColor: resolved.contentColor,
        shape: theme.shape.none,
        elevation: elevation ?? resolved.elevation,
        thickness: thickness ?? resolved.thickness,
        surfaceTint: const Color(0x00000000),
        padding: resolved.padding,
        alignment: null,
        child: SceneSafeArea3d(
          child: SceneRow3d(
            mainAxisSize: MainAxisSize3d.max,
            crossAxisAlignment: CrossAxisAlignment3d.center,
            children: <Widget>[
              for (var i = 0; i < destinations.length; i++)
                SceneExpanded3d(
                  child: buildNavigationDestination3d(
                    context,
                    theme: theme,
                    style: resolved,
                    destination: destinations[i],
                    maxLabelTextScaleFactor: maxLabelTextScaleFactor,
                    selected: i == selectedIndex,
                    onSelected: onDestinationSelected == null
                        ? null
                        : () => onDestinationSelected!(i),
                    textDirection: textDirection,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The rail down the leading edge of a wide screen.
///
/// ```dart
/// SceneRow3d(
///   children: <Widget>[
///     NavigationRail3d(
///       selectedIndex: index,
///       destinations: destinations,
///       onDestinationSelected: (i) => setState(() => index = i),
///     ),
///     const VerticalDivider3d(),
///     SceneExpanded3d(child: body),
///   ],
/// )
/// ```
///
/// The same component as [NavigationBar3d] with its axes swapped, and
/// Material gives it different tokens anyway: 80dp wide, flat, on `surface`,
/// with a 56dp pill instead of a 64dp one. It takes a [leading] and a
/// [trailing] slot, which is where a floating action button and a settings
/// button go.
///
/// **A rail wants a `VerticalDivider3d` beside it**, and that is why the
/// vertical rule exists at all — phase 4 left it out with the note that
/// nothing yet had two things to separate. The rail does not draw one
/// itself, for the same reason Flutter's does not: whether the seam belongs
/// to the rail or to the body is the application's decision.
class NavigationRail3d extends StatelessWidget {
  /// Creates a navigation rail.
  const NavigationRail3d({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    this.onDestinationSelected,
    this.leading,
    this.trailing,
    this.style,
    this.backgroundColor,
    this.elevation,
    this.thickness,
    this.width,
    this.textDirection,
  }) : assert(selectedIndex >= 0);

  /// Why a rail with one destination is refused; see
  /// [NavigationBar3d.tooFewDestinations] for why it is not a constructor
  /// assert.
  static const String tooFewDestinations =
      'A NavigationRail3d needs at least two destinations. Material has no '
      'appearance for a rail with one.';

  /// Where the rail can take you, in order.
  final List<NavigationDestination3d> destinations;

  /// Which destination is current.
  final int selectedIndex;

  /// Called with the index of the destination the viewer chose.
  final NavigationDestination3dCallback? onDestinationSelected;

  /// What sits above the destinations: usually a floating action button.
  final Widget? leading;

  /// What sits below them.
  final Widget? trailing;

  /// The whole token set, or null for
  /// `NavigationStyle3d.of(theme, NavigationVariant3d.rail)`.
  final NavigationStyle3d? style;

  /// The slab's colour, or null for the style's `surface`.
  final Color? backgroundColor;

  /// How far the rail stands off the screen, in logical pixels.
  final double? elevation;

  /// How deep the slab is, in logical pixels.
  final double? thickness;

  /// How wide the rail is, in logical pixels, or null for the style's 80.
  final double? width;

  /// The direction the destination labels read in.
  final TextDirection? textDirection;

  /// The style in force.
  NavigationStyle3d styleOf(Theme3dData theme) =>
      style ?? NavigationStyle3d.of(theme, NavigationVariant3d.rail);

  @override
  Widget build(BuildContext context) {
    assert(destinations.length >= 2, tooFewDestinations);
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final resolved = styleOf(theme);
    final inset = MediaQuery3d.of(context).padding;
    final rightToLeft = Directionality.maybeOf(context) == TextDirection.rtl;
    final leadingInset = rightToLeft ? inset.right : inset.left;

    // Grown by the inset on its leading side and no other, as Flutter's rail
    // is: a rail stands against the leading edge of a landscape phone, which
    // is where the notch is, and the edge it does not touch is the body's.
    return SceneSizedBox3d(
      width: metrics.dp((width ?? resolved.extent) + leadingInset),
      child: Material3d(
        color: backgroundColor ?? resolved.container,
        contentColor: resolved.contentColor,
        shape: theme.shape.none,
        elevation: elevation ?? resolved.elevation,
        thickness: thickness ?? resolved.thickness,
        surfaceTint: const Color(0x00000000),
        padding: resolved.padding,
        alignment: null,
        child: SceneSafeArea3d(
          left: !rightToLeft,
          right: rightToLeft,
          child: SceneColumn3d(
            mainAxisSize: MainAxisSize3d.max,
            mainAxisAlignment: MainAxisAlignment3d.start,
            crossAxisAlignment: CrossAxisAlignment3d.center,
            spacing: metrics.dp(resolved.labelGap),
            children: <Widget>[
              if (leading != null) leading!,
              for (var i = 0; i < destinations.length; i++)
                buildNavigationDestination3d(
                  context,
                  theme: theme,
                  style: resolved,
                  destination: destinations[i],
                  selected: i == selectedIndex,
                  onSelected: onDestinationSelected == null
                      ? null
                      : () => onDestinationSelected!(i),
                  textDirection: textDirection,
                ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// One destination: a pill, a glyph on it, and a label under it.
///
/// Shared by the bar and the rail because there is exactly one of these and
/// two places it goes. Not exported — a caller states a
/// [NavigationDestination3d] and the component builds this.
Widget buildNavigationDestination3d(
  BuildContext context, {
  required Theme3dData theme,
  required NavigationStyle3d style,
  required NavigationDestination3d destination,
  required bool selected,
  required void Function()? onSelected,
  TextDirection? textDirection,
  double? maxLabelTextScaleFactor,
}) {
  final metrics = Layout3dMetricsScope.of(context);
  final enabled = destination.enabled && onSelected != null;
  final content = selected
      ? style.selectedContentColor
      : (destination.enabled
            ? style.contentColor
            : theme.colorScheme.disabledContent);

  final glyph = selected
      ? (destination.selectedIcon ?? destination.icon)
      : destination.icon;

  // The pill and the glyph on it. A stack rather than a decoration, so that
  // the indicator is a `Material3d` like everything else here — and with a
  // depth step, because a glyph drawn exactly on the pill's front face is
  // coplanar with it and z-fights.
  final indicator = SceneSizedBox3d(
    width: metrics.dp(style.indicatorSize.width),
    height: metrics.dp(style.indicatorSize.height),
    child: SceneStack3d(
      alignment: Alignment3d.frontCenter,
      depthStep: metrics.dp(style.indicatorDepthStep),
      children: <Widget>[
        if (selected)
          Material3d(
            color: style.indicatorColor,
            shape: style.indicatorShape,
            elevation: theme.elevation.level0,
            thickness: style.destinationThickness,
            surfaceTint: const Color(0x00000000),
          )
        else
          // A placeholder rather than nothing, so the glyph is the second
          // child either way and the depth step it gets does not change when
          // the selection moves.
          const SceneSizedBox3d(),
        // The glyph answers hit tests on its own account, and everything a
        // ray needs to find here is the well below it.
        SceneIgnorePointer3d(child: glyph),
      ],
    ),
  );

  final labelled = SceneColumn3d(
    mainAxisSize: MainAxisSize3d.min,
    mainAxisAlignment: MainAxisAlignment3d.center,
    crossAxisAlignment: CrossAxisAlignment3d.center,
    spacing: metrics.dp(style.labelGap),
    children: <Widget>[
      indicator,
      SceneTextStyle3d(
        style: style.labelStyle,
        color: content,
        child: SceneIgnorePointer3d(
          child: maxLabelTextScaleFactor == null
              ? SceneText3d(destination.label)
              : SceneTextScaling3d.clamped(
                  maxScaleFactor: maxLabelTextScaleFactor,
                  child: SceneText3d(destination.label),
                ),
        ),
      ),
    ],
  );

  // Its own surface, so its own state layer: an InkWell3d washes the
  // *enclosing* Material3d, and one placed straight inside the bar would
  // light the whole bar up under one finger.
  final surface = Material3d(
    color: const Color(0x00000000),
    contentColor: content,
    shape: theme.shape.full,
    elevation: theme.elevation.level0,
    thickness: style.destinationThickness,
    surfaceTint: const Color(0x00000000),
    alignment: null,
    child: SceneAlign3d(
      alignment: Alignment3d.frontCenter,
      child: onSelected == null
          ? labelled
          : InkWell3d(
              // One target, and it is the one outside this panel.
              minimumSize: Size3d.zero,
              enabled: enabled,
              onTap: enabled ? onSelected : null,
              child: labelled,
            ),
    ),
  );

  final announced = SceneSemantics3d(
    properties: SemanticsProperties(
      button: true,
      enabled: enabled,
      selected: selected,
      label: destination.label,
      textDirection: readingDirection3d(context, textDirection),
      onTap: enabled ? onSelected : null,
    ),
    child: surface,
  );

  // Outermost, for the reason every component here puts it there: a target
  // reaches past its own extent and its parent does not.
  return SceneTapTarget3d(child: announced);
}
