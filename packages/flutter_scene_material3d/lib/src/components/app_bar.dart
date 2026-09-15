import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart'
    show BuildContext, Directionality, StatelessWidget, TextDirection, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show
        Alignment3d,
        Constraints3d,
        CrossAxisAlignment3d,
        EdgeInsetsDirectional3d,
        Layout3dMetrics,
        MainAxisAlignment3d,
        MainAxisSize3d,
        MultiChildLayout3dDelegate,
        Offset3d,
        Size3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dMetricsScope,
        SceneAlign3d,
        SceneConstrainedBox3d,
        SceneCustomMultiChildLayout3d,
        SceneExpanded3d,
        SceneLayoutId3d,
        ScenePadding3d,
        SceneRow3d,
        SceneSemantics3d,
        SceneSizedBox3d,
        SceneSliverPersistentHeader3d,
        SceneSpacer3d,
        SceneText3d;

import '../theme/theme.dart';
import '../theme/theme_data.dart';
import '../tokens/typography.dart';
import 'app_bar_style.dart';
import 'material.dart';
import 'text_style.dart';
import 'reading_direction.dart';

/// The bar across the top of a screen: a leading widget, a title, and
/// actions.
///
/// ```dart
/// AppBar3d.text(
///   title: 'Inbox',
///   leading: IconButton3d(icon: Icons.menu, onPressed: _openDrawer),
///   actions: <Widget>[
///     IconButton3d(icon: Icons.search, onPressed: _search),
///   ],
/// )
/// ```
///
/// A fixed-height bar for a screen that does not scroll under it. When the
/// body *does* scroll under it, use [SliverAppBar3d], which is the same
/// tokens over a `SliverPersistentHeader3d` and is where every interesting
/// question in this component actually lives.
///
/// ## It is the deepest thing on a screen, and that is not decoration
///
/// The slab is `Thickness3d.structural` — 8dp, the token named for exactly
/// this — because a bar is the thing everything else passes *behind*. On a
/// screen that reads as a shadow; here it reads as an object, and it only
/// reads at all if the bar's geometry is genuinely nearer the viewer than the
/// rows sliding under it. Two slabs are separated when the step between them
/// exceeds the **mean** of their thicknesses, so an 8dp bar over a 4dp card
/// needs more than 6dp of separation. [Scaffold3d.depthStep] is where that
/// number is stated once for a whole screen; `SliverAppBar3d.lift` is the
/// same number for a bar inside a scroll view.
///
/// ## What it announces
///
/// A `Semantics3d` gathers nothing, so a bar states its own label — and a bar
/// has the same problem `ListTile3d` has, a title plus content that is not
/// the title. [AppBar3d.text] takes the title as a string and announces it,
/// marked as a **header**, which is what Flutter's `AppBar` publishes and
/// what lets a screen reader jump between sections. The widget-taking
/// constructor announces only the [semanticLabel] it is given.
class AppBar3d extends StatelessWidget {
  /// Creates a bar out of widgets, announcing [semanticLabel].
  const AppBar3d({
    super.key,
    this.leading,
    this.title,
    this.actions = const <Widget>[],
    this.variant = AppBarVariant3d.small,
    this.style,
    this.backgroundColor,
    this.foregroundColor,
    this.toolbarHeight,
    this.elevation,
    this.thickness,
    this.centerTitle,
    this.semanticLabel,
    this.textDirection,
  });

  /// Creates a bar whose title is a string, which is also what it announces.
  AppBar3d.text({
    super.key,
    required String title,
    this.leading,
    this.actions = const <Widget>[],
    this.variant = AppBarVariant3d.small,
    this.style,
    this.backgroundColor,
    this.foregroundColor,
    this.toolbarHeight,
    this.elevation,
    this.thickness,
    this.centerTitle,
    String? semanticLabel,
    this.textDirection,
  }) : title = SceneText3d(title),
       semanticLabel = semanticLabel ?? title;

  /// What sits at the leading edge: a menu button, a back button.
  final Widget? leading;

  /// The bar's title.
  final Widget? title;

  /// What sits at the trailing edge, in order.
  final List<Widget> actions;

  /// Which of Material's four bars this is.
  final AppBarVariant3d variant;

  /// The whole token set, or null for `AppBarStyle3d.of(theme, variant)`.
  final AppBarStyle3d? style;

  /// The slab's colour, or null for the style's.
  final Color? backgroundColor;

  /// The colour of the title, the leading widget and the actions, or null for
  /// the style's.
  final Color? foregroundColor;

  /// How tall the bar is, in logical pixels, or null for the style's.
  final double? toolbarHeight;

  /// How far the bar stands off the screen, in logical pixels, or null for
  /// the style's.
  final double? elevation;

  /// How deep the slab is, in logical pixels, or null for the style's
  /// `thickness.structural`.
  final double? thickness;

  /// Whether the title is centred, or null for the style's.
  ///
  /// Centred in the whole bar, not in the room between the leading widget and
  /// the actions — and, as Flutter's is, pulled back inside that room when
  /// centring would put it under one of them.
  final bool? centerTitle;

  /// What a screen reader announces this bar as.
  final String? semanticLabel;

  /// The direction [semanticLabel] reads in.
  final TextDirection? textDirection;

  /// The style in force: [style], or the variant's out of the theme.
  AppBarStyle3d styleOf(Theme3dData theme) =>
      style ?? AppBarStyle3d.of(theme, variant);

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final resolved = styleOf(theme);
    final height = toolbarHeight ?? resolved.toolbarHeight;
    return announce(
      context,
      SceneSizedBox3d(
        height: Layout3dMetricsScope.of(context).dp(height),
        child: buildBar(
          context,
          theme: theme,
          style: resolved,
          titleStyle: resolved.titleStyle,
        ),
      ),
    );
  }

  /// The bar's surface and toolbar, without a height of its own.
  ///
  /// Shared with [SliverAppBar3d], which gives the same tree a height that
  /// changes with the scroll offset instead of a fixed one, and which is why
  /// this is a method rather than the body of [build]. A caller outside this
  /// package has no reason to use it, and it is not exported.
  Widget buildBar(
    BuildContext context, {
    required Theme3dData theme,
    required AppBarStyle3d style,
    required Typography3dToken titleStyle,
  }) {
    final metrics = Layout3dMetricsScope.of(context);
    final content = foregroundColor ?? style.contentColor;
    final spacing = metrics.dp(style.titleSpacing);
    final barHeight = toolbarHeight ?? style.toolbarHeight;

    final titled = title == null
        ? null
        : SceneTextStyle3d(style: titleStyle, color: content, child: title!);

    final centred = centerTitle ?? style.centerTitle;
    // The toolbar's own order follows the application, as Flutter's
    // `NavigationToolbar` does: the leading widget at the start, the actions
    // at the end. The row below reads the same direction on its own.
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;

    // The toolbar row: one fixed-height line at the *bottom* of the bar.
    // Material puts it there so that an expanded medium or large bar grows
    // upward and the controls stay where the hand is.
    Widget toolbar;
    if (centred && titled != null) {
      // Not a row, because centring a title in the bar is not the same as
      // centring it in what is left over between the leading widget and the
      // actions; and not a stack, because a stack shrink-wraps its title and
      // squeezes the controls into the title's width. The arithmetic is
      // Flutter's `NavigationToolbar`'s, and it needs every width measured
      // before the title is placed.
      toolbar = SceneCustomMultiChildLayout3d(
        delegate: _CentredToolbar3dLayout(
          spacing: spacing,
          textDirection: direction,
        ),
        children: <Widget>[
          if (leading != null)
            SceneLayoutId3d(
              id: _ToolbarSlot3d.leading,
              child: _leadingSlot(metrics, style, direction, leading!),
            ),
          SceneLayoutId3d(id: _ToolbarSlot3d.middle, child: titled),
          if (actions.isNotEmpty)
            SceneLayoutId3d(
              id: _ToolbarSlot3d.trailing,
              child: SceneRow3d(
                mainAxisSize: MainAxisSize3d.min,
                crossAxisAlignment: CrossAxisAlignment3d.center,
                children: actions,
              ),
            ),
        ],
      );
    } else {
      toolbar = SceneRow3d(
        mainAxisSize: MainAxisSize3d.max,
        mainAxisAlignment: MainAxisAlignment3d.start,
        crossAxisAlignment: CrossAxisAlignment3d.center,
        spacing: spacing,
        children: <Widget>[
          if (leading != null)
            _leadingSlot(metrics, style, direction, leading!),
          if (titled != null)
            SceneExpanded3d(
              child: _clearOfEmptyEdges(metrics, style, direction, titled),
            )
          else
            const SceneSpacer3d(),
          ...actions,
        ],
      );
    }

    final line = SceneSizedBox3d(height: metrics.dp(barHeight), child: toolbar);

    return Material3d(
      color: backgroundColor ?? style.container,
      contentColor: content,
      shape: style.shape,
      elevation: elevation ?? style.elevation,
      thickness: thickness ?? style.thickness,
      surfaceTint: const Color(0x00000000),
      padding: style.padding,
      // The surface fills whatever it is given and the toolbar is aligned
      // inside it, rather than the surface shrink-wrapping the toolbar.
      alignment: null,
      // Aligned to the bottom face in the plane and to the *front* face in
      // depth: a toolbar centred in an 8dp slab is 4dp inside it, where the
      // surface it is drawn on wins the depth test and the title vanishes
      // with nothing to say why.
      child: SceneAlign3d(alignment: const Alignment3d(0, 1, -1), child: line),
    );
  }

  /// [leading] in its slot: [AppBarStyle3d.leadingWidth] from the bar's
  /// leading edge, the bar's padding on that edge counted toward it, with the
  /// widget centred in it.
  ///
  /// Flutter gives a leading widget a slot `kToolbarHeight` wide and measures
  /// the title from the end of the slot, so the title lands in the same place
  /// whatever the leading widget's own width. Without the slot the title
  /// followed the widget: 68dp in behind a 48dp icon button, where Flutter's
  /// is 72dp. Centred, because Flutter lays a leading widget out in a tight
  /// slot, and both the icon button it centres and an icon forced to the
  /// slot's width draw in its middle. Aligned to the front in depth, as the
  /// rest of the toolbar is, so the widget stays on the bar's face.
  static Widget _leadingSlot(
    Layout3dMetrics metrics,
    AppBarStyle3d style,
    TextDirection direction,
    Widget leading,
  ) => SceneSizedBox3d(
    width: metrics.dp(
      math.max(0.0, style.leadingWidth - _startPadding(style, direction)),
    ),
    child: SceneAlign3d(alignment: const Alignment3d(0, 0, -1), child: leading),
  );

  /// [title], kept [AppBarStyle3d.titleSpacing] off each edge of the bar that
  /// has nothing on it.
  ///
  /// The row's `spacing` is the gap *between* its children, so it separates a
  /// title from a leading widget or an action and does nothing at an edge with
  /// neither: a bar with no leading widget used to put its title against its
  /// own edge. Flutter's `NavigationToolbar` keeps the title `middleSpacing`
  /// clear of both slots whether they hold anything or not, so the bar's edge
  /// is where the spacing is measured from here — the bar's own padding counts
  /// toward it rather than being added to it.
  ///
  /// Start and end rather than left and right, because the row mirrors in a
  /// right-to-left application: the edge with no leading widget on it is the
  /// right one there. [AppBarStyle3d.padding] is physical, so the padding
  /// that counts toward each inset is whichever side that edge is on.
  Widget _clearOfEmptyEdges(
    Layout3dMetrics metrics,
    AppBarStyle3d style,
    TextDirection direction,
    Widget title,
  ) {
    double inset(bool empty, double padding) =>
        empty ? math.max(0.0, style.titleSpacing - padding) : 0.0;
    final start = inset(leading == null, _startPadding(style, direction));
    final end = inset(actions.isEmpty, _endPadding(style, direction));
    if (start == 0.0 && end == 0.0) return title;
    return ScenePadding3d(
      padding: EdgeInsetsDirectional3d.only(
        start: metrics.dp(start),
        end: metrics.dp(end),
      ),
      child: title,
    );
  }

  /// The bar's padding on the edge the leading widget is on.
  static double _startPadding(AppBarStyle3d style, TextDirection direction) =>
      direction == TextDirection.rtl ? style.padding.right : style.padding.left;

  /// The bar's padding on the edge the actions are on.
  static double _endPadding(AppBarStyle3d style, TextDirection direction) =>
      direction == TextDirection.rtl ? style.padding.left : style.padding.right;

  /// The semantics wrapper both constructors' bars get.
  ///
  /// Takes a [BuildContext] because the reading direction a bar announces in
  /// falls back to the enclosing `Directionality`, and a bar with a label and
  /// no direction at all is a framework assertion the moment semantics are
  /// switched on — see [readingDirection3d].
  Widget announce(BuildContext context, Widget bar) {
    final label = semanticLabel;
    if (label == null) return bar;
    return SceneSemantics3d(
      properties: SemanticsProperties(
        header: true,
        label: label,
        textDirection: readingDirection3d(context, textDirection),
      ),
      child: bar,
    );
  }
}

/// The bar at the top of a scroll view, which the content passes behind.
///
/// ```dart
/// SceneCustomScrollView3d(
///   controller: scroll,
///   slivers: <Widget>[
///     SliverAppBar3d.text(title: 'Inbox', pinned: true),
///     SceneSliverList3d(children: rows),
///   ],
/// )
/// ```
///
/// This is the component the whole clip contract exists for, and the one that
/// finally exercised it. Two mechanisms keep a row out of the bar, and
/// **neither is enough on its own**:
///
///  * The bar's geometry is pulled toward the viewer by [lift], so a row
///    passes *behind* it rather than through it. That is a depth-buffer
///    separation, and it has to clear the mean of the two slabs' thicknesses
///    — an 8dp bar over a 4dp card needs more than 6dp — which is why the
///    default here is the theme's own `thickness.depthStep` and **not**
///    `SliverPersistentHeader3d`'s one logical pixel. One pixel separates two
///    decals; it does not separate two Material components.
///  * `CustomScrollView3d` publishes a clip plane at the bar's trailing edge,
///    which is what cuts a row *in half* at that edge. A `Material3d`'s panel
///    shader honours it; a leaf holding an application's own material does
///    not, and is merely behind the bar rather than cut by it.
///
/// `examples/render_probe`'s `sliver_app_bar_clip` is the picture of the
/// second one, and it is the scene that found the plane tier had never fired
/// for a header at all.
///
/// ## What a collapse can and cannot change
///
/// The bar shrinks from [expandedHeight] to `toolbarHeight` as the content
/// scrolls, and it does that through the **constraints** the header gives it:
/// the surface fills what it is offered and the toolbar stays at the bottom.
/// Nothing rebuilds, which is the point — a collapse happens inside a layout
/// pass, and a widget cannot be inflated there.
///
/// So two things Flutter's `SliverAppBar` does are deliberately not here.
/// The title does **not** grow from `titleLarge` to `headlineSmall` partway
/// through a collapse, because a type role is a rebuild; a medium or large
/// bar states its expanded role and keeps it. And the bar does **not** raise
/// itself to `scrolledUnderElevation` when content goes beneath it, because
/// that too is a rebuild, and one that would run every frame of a scroll. A
/// screen that wants either drives it from a scroll listener, off the layout
/// path, and pays for the rebuild knowingly.
class SliverAppBar3d extends StatelessWidget {
  /// Creates a sliver bar out of widgets, announcing [semanticLabel].
  const SliverAppBar3d({
    super.key,
    this.leading,
    this.title,
    this.actions = const <Widget>[],
    this.variant = AppBarVariant3d.small,
    this.style,
    this.pinned = false,
    this.floating = false,
    this.expandedHeight,
    this.toolbarHeight,
    this.backgroundColor,
    this.foregroundColor,
    this.elevation,
    this.thickness,
    this.centerTitle,
    this.lift,
    this.semanticLabel,
    this.textDirection,
  });

  /// Creates a sliver bar whose title is a string, which it also announces.
  SliverAppBar3d.text({
    super.key,
    required String title,
    this.leading,
    this.actions = const <Widget>[],
    this.variant = AppBarVariant3d.small,
    this.style,
    this.pinned = false,
    this.floating = false,
    this.expandedHeight,
    this.toolbarHeight,
    this.backgroundColor,
    this.foregroundColor,
    this.elevation,
    this.thickness,
    this.centerTitle,
    this.lift,
    String? semanticLabel,
    this.textDirection,
  }) : title = SceneText3d(title),
       semanticLabel = semanticLabel ?? title;

  /// What sits at the leading edge.
  final Widget? leading;

  /// The bar's title.
  final Widget? title;

  /// What sits at the trailing edge, in order.
  final List<Widget> actions;

  /// Which of Material's four bars this is.
  final AppBarVariant3d variant;

  /// The whole token set, or null for `AppBarStyle3d.of(theme, variant)`.
  final AppBarStyle3d? style;

  /// Whether the bar holds the leading edge once it has collapsed.
  final bool pinned;

  /// Whether the bar comes back as soon as the viewer scrolls backwards.
  final bool floating;

  /// How tall the bar is at rest, in logical pixels, or null for the style's.
  final double? expandedHeight;

  /// How tall the bar is once collapsed, in logical pixels, or null for the
  /// style's 64.
  final double? toolbarHeight;

  /// The slab's colour, or null for the style's.
  final Color? backgroundColor;

  /// The content colour, or null for the style's.
  final Color? foregroundColor;

  /// How far the bar stands off the screen, in logical pixels.
  final double? elevation;

  /// How deep the slab is, in logical pixels, or null for
  /// `thickness.structural`.
  final double? thickness;

  /// Whether the title is centred, or null for the style's.
  ///
  /// Centred in the whole bar, not in the room between the leading widget and
  /// the actions — and, as Flutter's is, pulled back inside that room when
  /// centring would put it under one of them.
  final bool? centerTitle;

  /// How far toward the viewer the bar's geometry is pulled while it is
  /// covering content, in **logical pixels**, or null for the theme's
  /// `thickness.depthStep`.
  ///
  /// The default is the whole reason this property is not simply forwarded.
  /// `SliverPersistentHeader3d.lift` defaults to one logical pixel, which
  /// separates two things with no thickness and does nothing for two slabs:
  /// a `Thickness3d.raised` card passing under a `Thickness3d.structural`
  /// bar pokes through it everywhere they overlap. `Thickness3d.depthStep` is
  /// the number the scale was designed against, and
  /// `Thickness3d.separates(raised, structural)` is the assertion that says
  /// so out loud.
  final double? lift;

  /// What a screen reader announces this bar as.
  final String? semanticLabel;

  /// The direction [semanticLabel] reads in.
  final TextDirection? textDirection;

  /// The style in force: [style], or the variant's out of the theme.
  AppBarStyle3d styleOf(Theme3dData theme) =>
      style ?? AppBarStyle3d.of(theme, variant);

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final resolved = styleOf(theme);

    final collapsed = toolbarHeight ?? resolved.toolbarHeight;
    final expanded = expandedHeight ?? resolved.expandedHeight;
    assert(
      expanded >= collapsed,
      'A SliverAppBar3d cannot expand to ${expanded}dp, which is less than '
      'the ${collapsed}dp it collapses to. A bar shrinks from the first '
      'toward the second.',
    );

    final bar = AppBar3d(
      leading: leading,
      title: title,
      actions: actions,
      variant: variant,
      style: resolved,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      toolbarHeight: collapsed,
      elevation: elevation,
      thickness: thickness,
      centerTitle: centerTitle,
      semanticLabel: semanticLabel,
      textDirection: textDirection,
    );

    // The surface takes every bit of the extent the header offers it, which
    // is how the collapse happens without anything rebuilding: the header
    // lays its child out loose against whatever is left of the maximum, and
    // a box that asks for an infinite minimum gets exactly that.
    final filling = SceneConstrainedBox3d(
      constraints: const Constraints3d(minHeight: double.infinity),
      child: bar.buildBar(
        context,
        theme: theme,
        style: resolved,
        titleStyle: resolved.expandedTitleStyle,
      ),
    );

    return SceneSliverPersistentHeader3d(
      minExtent: metrics.dp(collapsed),
      maxExtent: metrics.dp(expanded),
      pinned: pinned,
      floating: floating,
      lift: metrics.dp(lift ?? theme.thickness.depthStep),
      child: bar.announce(context, filling),
    );
  }
}

/// The three children of a toolbar whose title is centred.
enum _ToolbarSlot3d { leading, middle, trailing }

/// Flutter's `NavigationToolbar` layout, for a centred title.
///
/// The leading widget goes against the start of the bar and the actions
/// against its end. The title is given the width between them less
/// [spacing] on each side, centred in the **whole** bar, and then pulled back
/// inside that room when centring would put it under a control: never closer
/// than [spacing] to the leading slot, and never running into the actions.
/// Everything is centred in the toolbar's height and sits on its front face,
/// and in right to left the whole arrangement is mirrored, as
/// `NavigationToolbar`'s is.
class _CentredToolbar3dLayout extends MultiChildLayout3dDelegate {
  _CentredToolbar3dLayout({required this.spacing, required this.textDirection});

  /// The space around the title, in world units.
  final double spacing;

  /// Which edge the leading widget is on. Everything is worked out left to
  /// right and mirrored at the end, which is what `NavigationToolbar` does.
  final TextDirection textDirection;

  @override
  void performLayout(Size3d size) {
    final loose = Constraints3d(
      maxWidth: size.width,
      maxHeight: size.height,
      maxDepth: size.depth,
    );
    double middleY(Size3d child) => (size.height - child.height) / 2;
    Offset3d at(double x, Size3d child) => Offset3d(
      textDirection == TextDirection.rtl ? size.width - x - child.width : x,
      middleY(child),
      0,
    );

    var leadingWidth = 0.0;
    if (hasChild(_ToolbarSlot3d.leading)) {
      final leading = layoutChild(_ToolbarSlot3d.leading, loose);
      leadingWidth = leading.width;
      positionChild(_ToolbarSlot3d.leading, at(0, leading));
    }

    var trailingWidth = 0.0;
    if (hasChild(_ToolbarSlot3d.trailing)) {
      final trailing = layoutChild(_ToolbarSlot3d.trailing, loose);
      trailingWidth = trailing.width;
      positionChild(
        _ToolbarSlot3d.trailing,
        at(size.width - trailing.width, trailing),
      );
    }

    final room = math.max(
      0.0,
      size.width - leadingWidth - trailingWidth - spacing * 2,
    );
    final middle = layoutChild(
      _ToolbarSlot3d.middle,
      loose.copyWith(maxWidth: room),
    );
    final earliest = leadingWidth + spacing;
    var start = (size.width - middle.width) / 2;
    if (start + middle.width > size.width - trailingWidth) {
      start = size.width - trailingWidth - middle.width - spacing;
    } else if (start < earliest) {
      start = earliest;
    }
    positionChild(_ToolbarSlot3d.middle, at(start, middle));
  }

  @override
  bool shouldRelayout(_CentredToolbar3dLayout oldDelegate) =>
      oldDelegate.spacing != spacing ||
      oldDelegate.textDirection != textDirection;
}
