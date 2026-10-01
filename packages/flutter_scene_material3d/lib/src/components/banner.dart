import 'dart:ui' show Color;

import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart'
    show BuildContext, StatelessWidget, TextDirection, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show
        AlignmentDirectional3d,
        Constraints3d,
        CrossAxisAlignment3d,
        EdgeInsets3d,
        EdgeInsetsGeometry3d,
        MainAxisSize3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dMetricsScope,
        SceneAlign3d,
        SceneColumn3d,
        SceneConstrainedBox3d,
        SceneExpanded3d,
        ScenePadding3d,
        SceneRow3d,
        SceneSemantics3d,
        SceneText3d,
        SceneTextScaling3d;

import '../theme/theme.dart';
import 'banner_style.dart';
import 'divider.dart';
import 'material.dart';
import 'reading_direction.dart';
import 'text_style.dart';

/// A message that stays at the top of a screen until someone acts on it.
///
/// ```dart
/// SceneColumn3d(
///   crossAxisAlignment: CrossAxisAlignment3d.stretch,
///   children: <Widget>[
///     if (offline)
///       MaterialBanner3d.text(
///         content: 'You are offline. Changes will sync when you reconnect.',
///         leading: const Icon3d(Icons.cloud_off),
///         actions: <Widget>[
///           TextButton3d(onPressed: retry, child: const SceneText3d('Retry')),
///         ],
///       ),
///     SceneExpanded3d(child: list),
///   ],
/// )
/// ```
///
/// Flutter's `MaterialBanner`: a `surfaceContainerLow` strip, an optional
/// [leading] widget, the [content], and at least one action. One action
/// sits beside the content; two or more — or [forceActionsBelow] — sit in a
/// 52dp bar under it, at the trailing edge, which mirrors in right to left.
/// Everything it is made of is in [MaterialBannerStyle3d].
///
/// ## Static, and what that leaves out
///
/// This is the banner a screen writes into its own column, which is what
/// Flutter calls a static banner. Flutter also slides one in from under the
/// app bar through `ScaffoldMessenger.showMaterialBanner`, and that is two
/// things this package does not have: a scaffold slot under the app bar, and
/// a messenger that can reach one. Both are a change to `Scaffold3d` rather
/// than a component, so a ported screen that showed its banners through the
/// messenger puts them in its body instead.
///
/// ## Flat, with a rule, unless it is raised
///
/// By default the banner is flat, with an `outlineVariant` rule along its
/// foot — which is what Flutter's draws, though Flutter's own Material 3
/// token table gives a banner an elevation of 1: its build never reads that
/// figure. Given an [elevation], it stands that far off the screen, loses the
/// rule and gains a 10dp margin under it, which in Flutter is room for its
/// shadow and here is simply the space a port already lays out around.
///
/// ## What it announces
///
/// [MaterialBanner3d.text] takes the content as a string and announces it.
/// The widget-taking constructor announces only its [semanticLabel], because
/// a `Semantics3d` gathers nothing from the labels below it. The actions
/// announce themselves, as buttons do.
class MaterialBanner3d extends StatelessWidget {
  /// Creates a banner out of widgets, announcing [semanticLabel].
  const MaterialBanner3d({
    super.key,
    required this.content,
    required this.actions,
    this.leading,
    this.elevation,
    this.backgroundColor,
    this.dividerColor,
    this.padding,
    this.leadingPadding,
    this.margin,
    this.forceActionsBelow = false,
    this.minActionBarHeight,
    this.style,
    this.semanticLabel,
    this.textDirection,
  });

  /// Creates a banner whose content is a string, which is also what it
  /// announces.
  MaterialBanner3d.text({
    super.key,
    required String content,
    required this.actions,
    this.leading,
    this.elevation,
    this.backgroundColor,
    this.dividerColor,
    this.padding,
    this.leadingPadding,
    this.margin,
    this.forceActionsBelow = false,
    this.minActionBarHeight,
    this.style,
    String? semanticLabel,
    this.textDirection,
  }) : content = SceneText3d(content),
       semanticLabel = semanticLabel ?? content;

  /// Why a banner with no actions is refused, in `build`.
  ///
  /// Not a constructor assert, for `NavigationBar3d.tooFewDestinations`'
  /// reason: `List.length` is not a constant expression, and a `const`
  /// constructor's asserts are evaluated at compile time.
  static const String noActions =
      'A MaterialBanner3d needs at least one action. Material has no banner '
      'without one: a message nobody can act on is a snack bar.';

  /// What the banner says.
  final Widget content;

  /// What can be done about it, usually `TextButton3d`s, first to last.
  final List<Widget> actions;

  /// What sits before the content: usually an `Icon3d`, or an avatar.
  final Widget? leading;

  /// How far the banner stands off the screen, in logical pixels, or null
  /// for the style's none. Zero draws the rule along its foot.
  final double? elevation;

  /// The strip's colour, or null for the style's `surfaceContainerLow`.
  final Color? backgroundColor;

  /// The rule's colour at elevation zero, or null for `outlineVariant`.
  final Color? dividerColor;

  /// Space round the content, in logical pixels, or null for the style's —
  /// which depends on whether the actions are beside it or under it.
  final EdgeInsetsGeometry3d? padding;

  /// Space round [leading], or null for 16dp at its end.
  final EdgeInsetsGeometry3d? leadingPadding;

  /// Space outside the banner, or null for 10dp under it when it is raised
  /// and none when it is flat.
  final EdgeInsetsGeometry3d? margin;

  /// Whether a single action goes under the content anyway.
  final bool forceActionsBelow;

  /// The shortest the actions bar may be, in logical pixels, or null for 52.
  final double? minActionBarHeight;

  /// The whole token set, or null for `MaterialBannerStyle3d.of(theme)`.
  final MaterialBannerStyle3d? style;

  /// What a screen reader announces the banner as.
  final String? semanticLabel;

  /// The direction [semanticLabel] reads in.
  final TextDirection? textDirection;

  /// Whether the actions sit beside the content rather than under it.
  bool get isSingleRow => actions.length == 1 && !forceActionsBelow;

  @override
  Widget build(BuildContext context) {
    assert(actions.isNotEmpty, noActions);
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final resolved = style ?? MaterialBannerStyle3d.of(theme);
    final raised = elevation ?? resolved.elevation;
    final singleRow = isSingleRow;

    // Grows with type, and then stops: Flutter clamps both the content and
    // the actions to keep the banner's hierarchy at a large setting.
    Widget clamped(Widget child) => SceneTextScaling3d.clamped(
      maxScaleFactor: resolved.maxTextScaleFactor,
      child: child,
    );

    final actionsBar = SceneConstrainedBox3d(
      constraints: Constraints3d(
        minHeight: metrics.dp(
          minActionBarHeight ?? resolved.actionsBarMinHeight,
        ),
      ),
      child: ScenePadding3d(
        padding: metrics.dpInsets(resolved.actionsBarPadding),
        child: SceneAlign3d(
          // At the trailing edge, on the banner's face: an alignment that
          // centred in depth would sink the buttons into the slab.
          alignment: const AlignmentDirectional3d(1.0, 0.0, -1.0),
          child: SceneRow3d(
            mainAxisSize: MainAxisSize3d.min,
            depthAxisAlignment: CrossAxisAlignment3d.start,
            spacing: metrics.dp(resolved.actionsSpacing),
            children: actions,
          ),
        ),
      ),
    );

    final row = SceneRow3d(
      crossAxisAlignment: CrossAxisAlignment3d.center,
      depthAxisAlignment: CrossAxisAlignment3d.start,
      children: <Widget>[
        if (leading != null)
          ScenePadding3d(
            padding: metrics.dpInsets(
              leadingPadding ?? resolved.leadingPadding,
            ),
            child: leading,
          ),
        SceneExpanded3d(
          child: clamped(
            SceneTextStyle3d(
              style: resolved.textStyle,
              color: resolved.contentColor,
              child: content,
            ),
          ),
        ),
        if (singleRow) clamped(actionsBar),
      ],
    );

    final surface = Material3d(
      color: backgroundColor ?? resolved.container,
      contentColor: resolved.contentColor,
      shape: theme.shape.none,
      elevation: raised,
      thickness: resolved.thickness,
      // The container token already says how raised the strip is, as a
      // card's and a dialog's do.
      surfaceTint: const Color(0x00000000),
      alignment: null,
      child: SceneColumn3d(
        mainAxisSize: MainAxisSize3d.min,
        crossAxisAlignment: CrossAxisAlignment3d.stretch,
        // On the banner's face, for the reason every column on a surface is.
        depthAxisAlignment: CrossAxisAlignment3d.start,
        children: <Widget>[
          ScenePadding3d(
            padding: metrics.dpInsets(
              padding ??
                  (singleRow ? resolved.singleRowPadding : resolved.padding),
            ),
            child: row,
          ),
          if (!singleRow) clamped(actionsBar),
          if (raised == 0.0)
            // Flutter's `Divider(height: 0)` draws a 1dp rule in no room at
            // all, overhanging what is below it. A slab cannot overhang its
            // neighbour without fighting it, so this one takes its 1dp.
            Divider3d(space: 1.0, color: dividerColor ?? resolved.dividerColor),
        ],
      ),
    );

    final spaced = ScenePadding3d(
      padding: metrics.dpInsets(
        margin ??
            EdgeInsets3d.only(
              bottom: raised > 0.0 ? resolved.elevatedMargin : 0.0,
            ),
      ),
      child: surface,
    );

    final label = semanticLabel;
    if (label == null) return spaced;
    return SceneSemantics3d(
      properties: SemanticsProperties(
        label: label,
        textDirection: readingDirection3d(context, textDirection),
      ),
      child: spaced,
    );
  }
}
