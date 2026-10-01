import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/animation.dart'
    show Animation, AnimationController, Curve, CurvedAnimation, Curves;
import 'package:flutter/foundation.dart' show ValueChanged, immutable;
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        DefaultTextStyle,
        SingleTickerProviderStateMixin,
        State,
        StatefulWidget,
        TextDirection,
        Widget;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show
        Align3d,
        Alignment3d,
        AlignmentGeometry3d,
        CrossAxisAlignment3d,
        EdgeInsets3d,
        EdgeInsetsGeometry3d,
        MainAxisSize3d,
        ProxyLayout3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dMetricsScope,
        SceneClipBox3d,
        SceneColumn3d,
        SceneOffstage3d,
        ScenePadding3d,
        SceneSizedBox3d,
        SceneText3d,
        SingleChildLayout3dWidget;
import 'package:vector_math/vector_math.dart' show Matrix4;

import '../theme/theme.dart';
import '../theme/theme_data.dart';
import 'divider.dart';
import 'icon.dart';
import 'list_tile.dart';
import 'material.dart';
import 'reading_direction.dart';
import 'selection_list_tile.dart' show ListTileControlAffinity3d;

/// Everything an [ExpansionTile3d] is made of.
///
/// `_ExpansionTileDefaultsM3`'s colours, the rules Flutter draws round an
/// open tile in the theme's divider colour — which in Material 3 is
/// `outline`, not the `outlineVariant` a `Divider` draws in — and `Expansible`'s clock: Flutter's `_kExpand` 200ms on `Curves.easeIn`,
/// with the chevron's half turn eased again on top of the raw clock. The
/// colours are read off a real `ExpansionTile` in
/// `test/phase_4_defaults_test.dart`; the clock is transcribed.
///
/// Every figure is in **logical pixels**.
@immutable
class ExpansionTileStyle3d {
  /// Creates an expansion tile style. Every field is required.
  const ExpansionTileStyle3d({
    required this.textColor,
    required this.collapsedTextColor,
    required this.iconColor,
    required this.collapsedIconColor,
    required this.dividerColor,
    required this.duration,
    required this.curve,
    required this.iconCurve,
  });

  /// The style Material publishes, out of [theme]'s tokens.
  factory ExpansionTileStyle3d.of(Theme3dData theme) {
    final scheme = theme.colorScheme;
    return ExpansionTileStyle3d(
      textColor: scheme.onSurface,
      collapsedTextColor: scheme.onSurface,
      iconColor: scheme.primary,
      collapsedIconColor: scheme.onSurfaceVariant,
      // `ThemeData.dividerColor`, which Material 3 sets to `outline`. A
      // `Divider` uses `outlineVariant`; the tile's border does not.
      dividerColor: scheme.outline,
      // `short4`, which is Flutter's figure exactly.
      duration: theme.motion.short4,
      // Flutter's tile uses `Curves.easeIn` rather than one of Material's
      // motion curves, and a port should move as it did.
      curve: Curves.easeIn,
      iconCurve: Curves.easeIn,
    );
  }

  /// The title's and the subtitle's colour when open: `onSurface`.
  final Color textColor;

  /// Their colour when closed: `onSurface` too.
  final Color collapsedTextColor;

  /// The chevron's colour when open: `primary`.
  final Color iconColor;

  /// Its colour when closed: `onSurfaceVariant`.
  final Color collapsedIconColor;

  /// The rules above and below an open tile: `outline`.
  final Color dividerColor;

  /// How long opening or closing takes: 200ms.
  final Duration duration;

  /// The curve the children are revealed on: `Curves.easeIn`.
  final Curve curve;

  /// The curve the chevron turns on, applied to the raw clock: also
  /// `Curves.easeIn`.
  final Curve iconCurve;
}

/// A list tile that opens to show more tiles under it.
///
/// ```dart
/// ExpansionTile3d.text(
///   title: 'Advanced',
///   subtitle: 'Sync and storage',
///   children: <Widget>[
///     SwitchListTile3d.text(title: 'Sync over mobile data', value: sync, onChanged: setSync),
///     ListTile3d.text(title: 'Clear the cache', onTap: clear),
///   ],
/// )
/// ```
///
/// Flutter's `ExpansionTile`: a `ListTile3d` whose trailing chevron turns
/// half a turn as its [children] are revealed under it, over 200ms on
/// `Curves.easeIn`. An open tile has a rule of `outline` above and below it, and a 1dp space where the rules go when it is closed, so opening
/// it does not move its own title. Everything it is made of is in
/// [ExpansionTileStyle3d].
///
/// ## The reveal lays out, and that is the honest tier for it
///
/// Every animation in this catalogue before this one stays off the relayout
/// path, because none of them changed a size. This one does: the tile grows
/// and every row under it moves, and only layout can move them — Flutter
/// lays out on every frame of its reveal too. What is kept is the part that
/// matters: **a frame of the reveal builds nothing and measures no text.** A
/// box listens to the clock and writes an `Align3d`'s height factor inside a
/// clip, which is arithmetic over the boxes the tile already has. The
/// chevron's turn is the node tier, a rotation about its own centre. The tile
/// rebuilds when it starts to move and once more when a close finishes, which
/// is when the children leave the tree — unless [maintainState], which keeps
/// them, offstage, as Flutter does.
///
/// The children are revealed from their **middle**, because Flutter's reveal
/// is an `Align` at its default centre alignment; [expandedAlignment] moves
/// that.
///
/// ## Where it differs, and why
///
///  * **The colours change when the tile is pressed**, where Flutter eases
///    them over the run. Easing a colour here is either a rebuild every frame
///    or a decoration channel `Material3d` does not have; the switch made the
///    same trade.
///  * **A label straddling the reveal's edge draws whole** for the frames it
///    straddles. The panel shader cuts at a clip plane and the glyph shader
///    does not, so a half-revealed row has its panel cut and its text culled
///    only once it is wholly outside. A scrolling list here does the same at
///    its edge.
///  * **It takes no `ExpansibleController`.** That class postdates this
///    package's Flutter floor; [initiallyExpanded] and [onExpansionChanged]
///    are the API until the floor moves.
///
/// ## What it announces
///
/// The header announces itself as a list tile does, with `expanded` set to
/// whether it is open — the flag a screen reader reads as "expanded" or
/// "collapsed", where Flutter publishes a localized hint string. The
/// children announce themselves. [ExpansionTile3d.text] composes the label
/// out of the title and the subtitle, as `ListTile3d.text` does.
class ExpansionTile3d extends StatefulWidget {
  /// Creates an expansion tile out of widgets, announcing [semanticLabel].
  const ExpansionTile3d({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.showTrailingIcon = true,
    this.children = const <Widget>[],
    this.initiallyExpanded = false,
    this.maintainState = false,
    this.onExpansionChanged,
    this.tilePadding,
    this.childrenPadding,
    this.expandedAlignment,
    this.expandedCrossAxisAlignment,
    this.backgroundColor,
    this.collapsedBackgroundColor,
    this.textColor,
    this.collapsedTextColor,
    this.iconColor,
    this.collapsedIconColor,
    this.controlAffinity,
    this.dense = false,
    this.enabled = true,
    this.style,
    this.semanticLabel,
    this.textDirection,
  });

  /// Creates an expansion tile out of two strings, which is also what it
  /// announces: `'$title, $subtitle'`, or the title alone.
  ExpansionTile3d.text({
    super.key,
    required String title,
    String? subtitle,
    this.leading,
    this.trailing,
    this.showTrailingIcon = true,
    this.children = const <Widget>[],
    this.initiallyExpanded = false,
    this.maintainState = false,
    this.onExpansionChanged,
    this.tilePadding,
    this.childrenPadding,
    this.expandedAlignment,
    this.expandedCrossAxisAlignment,
    this.backgroundColor,
    this.collapsedBackgroundColor,
    this.textColor,
    this.collapsedTextColor,
    this.iconColor,
    this.collapsedIconColor,
    this.controlAffinity,
    this.dense = false,
    this.enabled = true,
    this.style,
    String? semanticLabel,
    this.textDirection,
  }) : title = SceneText3d(title),
       subtitle = subtitle == null ? null : SceneText3d(subtitle),
       semanticLabel =
           semanticLabel ?? (subtitle == null ? title : '$title, $subtitle');

  /// What the box carrying the chevron calls itself in a tree dump.
  static const String chevronName = 'ExpansionTile3d chevron';

  /// What the box revealing the children calls itself.
  static const String revealName = 'ExpansionTile3d reveal';

  /// The header's first line.
  final Widget title;

  /// The header's supporting line.
  final Widget? subtitle;

  /// What sits at the header's leading edge, or null — or the chevron, when
  /// [controlAffinity] puts it there.
  final Widget? leading;

  /// What sits at the trailing edge in place of the chevron, or null for the
  /// chevron.
  final Widget? trailing;

  /// Whether there is anything at the trailing edge at all.
  final bool showTrailingIcon;

  /// What is revealed under the header.
  final List<Widget> children;

  /// Whether the tile starts open.
  final bool initiallyExpanded;

  /// Whether the children stay in the tree, offstage, while the tile is
  /// closed — and so keep their state.
  final bool maintainState;

  /// Called with whether the tile is now open, when it is pressed.
  final ValueChanged<bool>? onExpansionChanged;

  /// The header's padding, or null for the list tile's.
  final EdgeInsetsGeometry3d? tilePadding;

  /// Space round the children, in logical pixels, or null for none.
  final EdgeInsetsGeometry3d? childrenPadding;

  /// Where the children sit as they are revealed, or null for the centre.
  final AlignmentGeometry3d? expandedAlignment;

  /// How the children line up across the tile, or null for centred.
  final CrossAxisAlignment3d? expandedCrossAxisAlignment;

  /// The tile's colour when open, or null for none.
  final Color? backgroundColor;

  /// Its colour when closed, or null for none.
  final Color? collapsedBackgroundColor;

  /// The header's text colour when open, or null for the style's.
  final Color? textColor;

  /// Its text colour when closed, or null for the style's.
  final Color? collapsedTextColor;

  /// The chevron's and the leading icon's colour when open, or null for the
  /// style's `primary`.
  final Color? iconColor;

  /// Their colour when closed, or null for the style's `onSurfaceVariant`.
  final Color? collapsedIconColor;

  /// Which end the chevron goes at, or null for the trailing one. `platform`
  /// means trailing, as Flutter's does.
  final ListTileControlAffinity3d? controlAffinity;

  /// Whether the header uses the shorter list tile heights.
  final bool dense;

  /// Whether the tile can be opened and closed.
  final bool enabled;

  /// The whole token set, or null for `ExpansionTileStyle3d.of(theme)`.
  final ExpansionTileStyle3d? style;

  /// What a screen reader announces the header as.
  final String? semanticLabel;

  /// The direction [semanticLabel] reads in.
  final TextDirection? textDirection;

  @override
  State<ExpansionTile3d> createState() => _ExpansionTile3dState();
}

class _ExpansionTile3dState extends State<ExpansionTile3d>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    value: widget.initiallyExpanded ? 1.0 : 0.0,
  );
  late final CurvedAnimation _reveal = CurvedAnimation(
    parent: _clock,
    curve: Curves.easeIn,
  );
  late final CurvedAnimation _turn = CurvedAnimation(
    parent: _clock,
    curve: Curves.easeIn,
  );

  /// Where the tile is going, which is where it is when it is not moving.
  late bool _expanded = widget.initiallyExpanded;

  @override
  void dispose() {
    _reveal.dispose();
    _turn.dispose();
    _clock.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _clock.forward();
    } else {
      _clock.reverse().then<void>((_) {
        // The one other build a close costs: the children leave the tree.
        if (mounted) setState(() {});
      });
    }
    widget.onExpansionChanged?.call(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final style = widget.style ?? ExpansionTileStyle3d.of(theme);
    _clock.duration = style.duration;
    _reveal.curve = style.curve;
    _turn.curve = style.iconCurve;

    final textColor = _expanded
        ? (widget.textColor ?? style.textColor)
        : (widget.collapsedTextColor ?? style.collapsedTextColor);
    final iconColor = _expanded
        ? (widget.iconColor ?? style.iconColor)
        : (widget.collapsedIconColor ?? style.collapsedIconColor);
    final background = _expanded
        ? widget.backgroundColor
        : widget.collapsedBackgroundColor;

    final chevronLeading =
        widget.controlAffinity == ListTileControlAffinity3d.leading;
    final chevron = _SceneTurn3d(
      animation: _turn,
      child: Icon3d(Icons.expand_more, color: iconColor),
    );

    // Flutter's `ListTileTheme.merge(iconColor: …)`: an `Icon3d` with no
    // colour of its own reads the ambient style's.
    Widget? iconColoured(Widget? icon) => icon == null
        ? null
        : DefaultTextStyle.merge(
            style: TextStyle(color: iconColor),
            child: icon,
          );

    final header = buildListTile3d(
      context,
      ListTile3d(
        leading: widget.leading != null
            ? iconColoured(widget.leading)
            : (chevronLeading ? chevron : null),
        title: widget.title,
        subtitle: widget.subtitle,
        trailing: !widget.showTrailingIcon
            ? null
            : (widget.trailing != null
                  ? iconColoured(widget.trailing)
                  : (chevronLeading ? null : chevron)),
        dense: widget.dense,
        enabled: widget.enabled,
        onTap: _toggle,
        contentPadding: widget.tilePadding,
      ),
      SemanticsProperties(
        button: true,
        enabled: widget.enabled,
        expanded: _expanded,
        label: widget.semanticLabel,
        textDirection: readingDirection3d(context, widget.textDirection),
        onTap: widget.enabled ? _toggle : null,
      ),
      contentColor: textColor,
    );

    final closed = !_expanded && _clock.isDismissed;
    Widget? body;
    if (!closed || widget.maintainState) {
      final revealed = SceneClipBox3d(
        child: _SceneReveal3d(
          animation: _reveal,
          alignment: widget.expandedAlignment ?? const Alignment3d(0, 0, -1),
          child: ScenePadding3d(
            padding: metrics.dpInsets(
              widget.childrenPadding ?? EdgeInsets3d.zero,
            ),
            child: SceneColumn3d(
              mainAxisSize: MainAxisSize3d.min,
              crossAxisAlignment:
                  widget.expandedCrossAxisAlignment ??
                  CrossAxisAlignment3d.center,
              depthAxisAlignment: CrossAxisAlignment3d.start,
              children: widget.children,
            ),
          ),
        ),
      );
      body = closed ? SceneOffstage3d(child: revealed) : revealed;
    }

    // Flutter's border is a 1dp line top and bottom, transparent while the
    // tile is closed, so the room for it is always there and opening the
    // tile does not move its title. A transparent slab here draws nothing and
    // writes no depth, but an empty box is plainer still.
    Widget rule() => _expanded
        ? Divider3d(space: 1.0, color: style.dividerColor)
        : SceneSizedBox3d(height: metrics.dp(1.0));

    final tile = SceneColumn3d(
      mainAxisSize: MainAxisSize3d.min,
      crossAxisAlignment: CrossAxisAlignment3d.stretch,
      depthAxisAlignment: CrossAxisAlignment3d.start,
      children: <Widget>[rule(), header, ?body, rule()],
    );

    if (background == null) return tile;
    return Material3d(
      color: background,
      shape: theme.shape.none,
      elevation: theme.elevation.level0,
      thickness: theme.thickness.standard,
      surfaceTint: const Color(0x00000000),
      alignment: null,
      child: tile,
    );
  }
}

/// The box that reveals the children: an [Align3d] whose height factor is
/// the clock, written from a listener so that no frame of the reveal builds
/// anything.
class _Reveal3d extends Align3d {
  _Reveal3d({required Animation<double> animation, super.alignment})
    : _animation = animation,
      super(heightFactor: animation.value, name: ExpansionTile3d.revealName) {
    _animation.addListener(_apply);
  }

  Animation<double> _animation;

  set animation(Animation<double> value) {
    if (identical(value, _animation)) return;
    _animation.removeListener(_apply);
    _animation = value..addListener(_apply);
    _apply();
  }

  // Clamped, because an overshooting curve handed in by a style would ask an
  // `Align3d` for a negative height.
  void _apply() => heightFactor = math.max(0.0, _animation.value);

  @override
  void dispose() {
    _animation.removeListener(_apply);
    super.dispose();
  }
}

class _SceneReveal3d extends SingleChildLayout3dWidget {
  const _SceneReveal3d({
    required this.animation,
    required this.alignment,
    super.child,
  });

  final Animation<double> animation;
  final AlignmentGeometry3d alignment;

  @override
  _Reveal3d createLayout(BuildContext context) =>
      _Reveal3d(animation: animation, alignment: alignment);

  @override
  void updateLayout(BuildContext context, _Reveal3d layout) {
    layout
      ..animation = animation
      ..alignment = alignment;
  }
}

/// The box that turns the chevron: half a turn about its own centre, on the
/// node tier, as the clock runs.
class _Turn3d extends ProxyLayout3d {
  _Turn3d({required Animation<double> animation})
    : _animation = animation,
      super(name: ExpansionTile3d.chevronName) {
    _animation.addListener(_apply);
  }

  Animation<double> _animation;

  set animation(Animation<double> value) {
    if (identical(value, _animation)) return;
    _animation.removeListener(_apply);
    _animation = value..addListener(_apply);
    _apply();
  }

  @override
  void performLayout() {
    super.performLayout();
    _apply();
  }

  void _apply() {
    if (!hasSize) return;
    final angle = math.pi * _animation.value;
    if (angle == 0.0) {
      nodeTransform = null;
      return;
    }
    // A node transform pivots on the box's origin corner, so a turn in place
    // is about the centre: across to it, round, and back.
    final cx = size.width / 2.0;
    final cy = size.height / 2.0;
    nodeTransform = Matrix4.translationValues(cx, cy, 0.0)
      ..multiply(Matrix4.rotationZ(angle))
      ..multiply(Matrix4.translationValues(-cx, -cy, 0.0));
  }

  @override
  void dispose() {
    _animation.removeListener(_apply);
    super.dispose();
  }
}

class _SceneTurn3d extends SingleChildLayout3dWidget {
  const _SceneTurn3d({required this.animation, super.child});

  final Animation<double> animation;

  @override
  _Turn3d createLayout(BuildContext context) => _Turn3d(animation: animation);

  @override
  void updateLayout(BuildContext context, _Turn3d layout) {
    layout.animation = animation;
  }
}
