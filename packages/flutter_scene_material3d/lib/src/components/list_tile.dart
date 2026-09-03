import 'dart:ui' show Color;

import 'package:flutter/gestures.dart'
    show GestureLongPressCallback, GestureTapCallback;
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart'
    show BuildContext, StatelessWidget, TextDirection, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show
        Constraints3d,
        CrossAxisAlignment3d,
        EdgeInsets3d,
        MainAxisAlignment3d,
        MainAxisSize3d,
        Size3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dMetricsScope,
        SceneColumn3d,
        SceneConstrainedBox3d,
        SceneExpanded3d,
        SceneRow3d,
        SceneSemantics3d,
        SceneTapTarget3d,
        SceneText3d;

import '../theme/theme.dart';
import '../tokens/typography.dart';
import 'ink_well.dart';
import 'material.dart';
import 'text_style.dart';

/// A single fixed-height row: a leading slot, one or two lines of text, and a
/// trailing slot.
///
/// ```dart
/// ListTile3d.text(
///   title: 'Inbox',
///   subtitle: '12 unread',
///   leading: const Icon3d(Icons.inbox),
///   onTap: _open,
/// )
/// ```
///
/// This is the component that meets the scrolling machinery, and it is meant
/// to: a `SceneListView3d` of these is the shape a real screen has, and
/// `test/list_tile_test.dart` builds one so that the tile's height, its wash
/// and its layout cost are measured where they will actually be paid.
///
/// ## The heights, and what a density does to them
///
/// Material publishes three: **56dp** for a title alone, **72dp** with a
/// subtitle, **88dp** for [isThreeLine]. [dense] takes them to 48, 64 and 76.
/// They are *minimums* — a tile whose text wraps is taller — and they go
/// through `Theme3dData.effectiveConstraints`, so the theme's
/// `VisualDensity3d` moves them by 4dp a step, in-plane and in depth, exactly
/// as Flutter's `VisualDensity` moves a `ListTile`'s.
///
/// The density lives on the theme rather than on this widget on purpose. The
/// layout package's metrics carries one too and applies it in
/// `Layout3dMetrics.effectiveConstraints`; two dials for one number is the
/// drift the "a component reads the theme" rule exists to prevent, and
/// `Theme3dData.density` is the stated winner.
///
/// ## What it announces, and why it takes strings
///
/// A tile has a title *and* a subtitle, so "what does it announce" is a real
/// question rather than a formality — and the answer this package can give is
/// constrained by a fact from phase 3: **a `Semantics3d` publishes what it is
/// given and gathers nothing.** Flutter's `ListTile` announces "Inbox, 12
/// unread" because `Semantics(container: true)` merges the labels below it.
/// There is no such merge here.
///
/// So the tile states its own label, and [ListTile3d.text] exists to make
/// that free: hand it the two strings and it builds both the labels and the
/// announcement — the title, then the subtitle, joined the way a reader would
/// speak them. The general constructor takes widgets and a [semanticLabel],
/// and a tile built that way with no label announces a row with no name.
///
/// ## The type roles it installs
///
/// The title is `bodyLarge` in `onSurface`, the subtitle `bodyMedium` in
/// `onSurfaceVariant`, and the leading and trailing slots `labelSmall` in
/// `onSurfaceVariant` — Material's own roles, which is why a bare
/// `SceneText3d` in any slot comes out right without saying anything. An
/// `Icon3d` in a slot picks up the same colour, because `Icon3d` with no
/// colour of its own reads the ambient `DefaultTextStyle`.
class ListTile3d extends StatelessWidget {
  /// Creates a tile out of widgets, announcing [semanticLabel].
  const ListTile3d({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.isThreeLine = false,
    this.dense = false,
    this.selected = false,
    this.enabled = true,
    this.onTap,
    this.onLongPress,
    this.tileColor,
    this.selectedColor,
    this.contentPadding,
    this.minHeight,
    this.semanticLabel,
    this.textDirection,
  }) : assert(!isThreeLine || subtitle != null);

  /// Creates a tile out of two strings, which is also what it announces.
  ///
  /// The convenience that answers this component's own hard question. It
  /// builds the labels *and* the [semanticLabel] — `'$title, $subtitle'`, or
  /// just the title when there is no subtitle — so a tile written this way
  /// says something a screen reader user can act on without anyone
  /// remembering to. Pass [semanticLabel] to override what it composed.
  ListTile3d.text({
    super.key,
    required String title,
    String? subtitle,
    this.leading,
    this.trailing,
    this.isThreeLine = false,
    this.dense = false,
    this.selected = false,
    this.enabled = true,
    this.onTap,
    this.onLongPress,
    this.tileColor,
    this.selectedColor,
    this.contentPadding,
    this.minHeight,
    String? semanticLabel,
    this.textDirection,
  }) : title = SceneText3d(title),
       subtitle = subtitle == null ? null : SceneText3d(subtitle),
       semanticLabel =
           semanticLabel ?? (subtitle == null ? title : '$title, $subtitle'),
       assert(!isThreeLine || subtitle != null);

  /// Material's one-line tile height, in logical pixels.
  static const double oneLineHeight = 56.0;

  /// Material's two-line tile height, in logical pixels.
  static const double twoLineHeight = 72.0;

  /// Material's three-line tile height, in logical pixels.
  static const double threeLineHeight = 88.0;

  /// The one-line height of a [dense] tile, in logical pixels.
  static const double denseOneLineHeight = 48.0;

  /// The two-line height of a [dense] tile, in logical pixels.
  static const double denseTwoLineHeight = 64.0;

  /// The three-line height of a [dense] tile, in logical pixels.
  static const double denseThreeLineHeight = 76.0;

  /// Material's default content padding, in logical pixels.
  ///
  /// 16dp at the leading edge and 24dp at the trailing one — Flutter's own
  /// `_LisTileDefaultsM3` figures, and the asymmetry is deliberate: a
  /// trailing control usually has visual weight of its own and wants more
  /// room than a leading icon does. The 8dp top and bottom are its
  /// `minVerticalPadding`.
  ///
  /// **In-plane only**, like every Material inset here: a front inset would
  /// push the row into the slab it is drawn on, where the surface wins the
  /// depth test.
  static const EdgeInsets3d defaultContentPadding = EdgeInsets3d.only(
    left: 16.0,
    right: 24.0,
    top: 8.0,
    bottom: 8.0,
  );

  /// The gap between the leading or trailing slot and the text, in logical
  /// pixels. Material's 16dp.
  static const double horizontalTitleGap = 16.0;

  /// What sits at the leading edge: an icon, an avatar, a checkbox.
  final Widget? leading;

  /// The tile's first line.
  final Widget? title;

  /// The supporting line under the title.
  final Widget? subtitle;

  /// What sits at the trailing edge.
  final Widget? trailing;

  /// Whether the subtitle is allowed two lines, which makes the tile 88dp.
  ///
  /// Asserts when there is no [subtitle], exactly as Flutter's `ListTile`
  /// does: three lines of a one-line tile is not a shape Material has.
  final bool isThreeLine;

  /// Whether the tile uses the shorter height scale.
  final bool dense;

  /// Whether the tile is drawn as selected.
  ///
  /// Selection here is a **token substitution**, not a wash: the text and the
  /// leading and trailing content take [selectedColor] — `primary` by
  /// default, Material's own figure — while the container is unchanged. That
  /// is why `Material3dState` has no `selected`, and it means a selection is
  /// a rebuild rather than a uniform write. It is not on a per-frame path.
  final bool selected;

  /// Whether the tile responds to a pointer at all.
  ///
  /// A disabled tile is drawn in `disabledContent` — there is no opacity in
  /// this stack to fade one with — takes no focus and lights up for nothing.
  final bool enabled;

  /// Called when the tile is tapped, or null for a tile that is not
  /// interactive.
  final GestureTapCallback? onTap;

  /// Called when the tile is long-pressed.
  final GestureLongPressCallback? onLongPress;

  /// The slab's colour, or null for a fully transparent one.
  ///
  /// Transparent is Material's own default, and it is what lets a list of
  /// tiles sit on whatever surface is behind it. The slab is still *there* —
  /// it is what the state-layer wash is drawn on — it simply contributes no
  /// colour of its own.
  final Color? tileColor;

  /// The content colour when [selected], or null for `colorScheme.primary`.
  final Color? selectedColor;

  /// Space between the tile's faces and its content, or null for
  /// [defaultContentPadding].
  final EdgeInsets3d? contentPadding;

  /// An explicit minimum height in logical pixels, overriding the line-count
  /// scale.
  final double? minHeight;

  /// What a screen reader announces this tile as.
  ///
  /// [ListTile3d.text] composes one out of the title and the subtitle. This
  /// constructor cannot: it is handed widgets, and there is nothing here that
  /// gathers a label out of them.
  final String? semanticLabel;

  /// The direction [semanticLabel] reads in.
  final TextDirection? textDirection;

  /// Whether the tile responds to a pointer.
  bool get interactive => enabled && (onTap != null || onLongPress != null);

  /// The tile's minimum height in logical pixels, before the density has its
  /// say.
  ///
  /// Material's table: 56, 72 and 88 for one, two and three lines, and 48, 64
  /// and 76 when [dense]. `test/list_tile_test.dart` checks these against the
  /// height a real Flutter `ListTile` lays out at rather than against a
  /// second transcription.
  double get lineHeight {
    if (minHeight != null) return minHeight!;
    if (isThreeLine) return dense ? denseThreeLineHeight : threeLineHeight;
    if (subtitle != null) return dense ? denseTwoLineHeight : twoLineHeight;
    return dense ? denseOneLineHeight : oneLineHeight;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final scheme = theme.colorScheme;

    final Color titleColor;
    final Color supportColor;
    if (!enabled) {
      titleColor = supportColor = scheme.disabledContent;
    } else if (selected) {
      titleColor = supportColor = selectedColor ?? scheme.primary;
    } else {
      titleColor = scheme.onSurface;
      supportColor = scheme.onSurfaceVariant;
    }

    final gap = metrics.dp(horizontalTitleGap);
    final text = <Widget>[
      if (title != null)
        SceneTextStyle3d(
          style: Typography3dToken.bodyLarge,
          color: titleColor,
          child: title!,
        ),
      if (subtitle != null)
        SceneTextStyle3d(
          style: Typography3dToken.bodyMedium,
          color: supportColor,
          child: subtitle!,
        ),
    ];

    final row = SceneRow3d(
      mainAxisAlignment: MainAxisAlignment3d.start,
      crossAxisAlignment: CrossAxisAlignment3d.center,
      // The gap is the flex's own `spacing`, which puts 16dp between every
      // adjacent pair and nothing at the ends — exactly the tile's rule, and
      // it needs no filler boxes to express.
      spacing: gap,
      children: <Widget>[
        if (leading != null) leading!,
        SceneExpanded3d(
          child: SceneColumn3d(
            mainAxisSize: MainAxisSize3d.min,
            mainAxisAlignment: MainAxisAlignment3d.center,
            crossAxisAlignment: CrossAxisAlignment3d.start,
            children: text,
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );

    // The whole row inherits the supporting role, so a bare `SceneText3d` or
    // an `Icon3d` in the leading or trailing slot is `onSurfaceVariant`
    // without being told. The title and the subtitle override it above.
    final content = SceneTextStyle3d(
      style: Typography3dToken.labelSmall,
      color: supportColor,
      child: row,
    );

    final surface = Material3d(
      color: tileColor ?? const Color(0x00000000),
      contentColor: titleColor,
      shape: theme.shape.none,
      elevation: theme.elevation.level0,
      thickness: theme.thickness.standard,
      padding: contentPadding ?? defaultContentPadding,
      // The row fills the tile rather than being centred in it, so a trailing
      // control really does sit at the trailing edge.
      alignment: null,
      surfaceTint: const Color(0x00000000),
      child: interactive
          ? InkWell3d(
              // One target, and it is the one outside this panel.
              minimumSize: Size3d.zero,
              enabled: enabled,
              onTap: onTap,
              onLongPress: onLongPress,
              child: content,
            )
          : content,
    );

    // The density is applied through the theme's own arithmetic rather than
    // by adding `4 * density` here, so there is one implementation of what a
    // density means and the theme is the stated winner over the metrics.
    final constrained = SceneConstrainedBox3d(
      constraints: theme.effectiveConstraints(
        Constraints3d(minHeight: metrics.dp(lineHeight)),
        metrics,
      ),
      child: surface,
    );

    final announced = SceneSemantics3d(
      properties: SemanticsProperties(
        button: interactive ? true : null,
        enabled: onTap != null || onLongPress != null ? enabled : null,
        selected: selected ? true : null,
        label: semanticLabel,
        textDirection: textDirection,
        onTap: interactive ? onTap : null,
        onLongPress: interactive ? onLongPress : null,
      ),
      child: constrained,
    );

    if (!interactive) return announced;
    // Outermost, for the reason `Button3d`'s is: a target reaches past its
    // own extent and every ancestor gates a ray on its own extent. A tile is
    // 56dp tall and needs none of the reach vertically — it is here so that
    // the rule holds everywhere rather than only where it is load-bearing,
    // and so a `dense` 48dp tile is exactly at the minimum rather than under
    // it.
    return SceneTapTarget3d(child: announced);
  }
}
