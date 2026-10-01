import 'dart:math' as math;
import 'dart:ui' show Color, SemanticsRole, lerpDouble;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/foundation.dart' show ValueChanged;
// The controller is Flutter's own, and so is the widget that hands one down:
// neither has a render object in it, so nothing about a plane stands in their
// way, and a ported screen keeps the controller it already has.
import 'package:flutter/material.dart' show DefaultTabController, TabController;
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        Directionality,
        State,
        StatefulWidget,
        StatelessWidget,
        TextDirection,
        TickerProviderStateMixin,
        Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show
        Alignment3d,
        Axis3d,
        Constraints3d,
        EdgeInsets3d,
        Layout3d,
        MainAxisAlignment3d,
        MainAxisSize3d,
        MultiChildLayout3d,
        Offset3d,
        PageScroll3dPhysics,
        ParentData3d,
        ProxyLayout3d,
        Scroll3dController,
        Size3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dMetricsScope,
        Layout3dWidget,
        SceneAlign3d,
        SceneClipBox3d,
        SceneColumn3d,
        SceneConstrainedBox3d,
        SceneExpanded3d,
        SceneIgnorePointer3d,
        ScenePadding3d,
        ScenePageView3d,
        SceneRow3d,
        SceneSemantics3d,
        SceneSizedBox3d,
        SceneTapTarget3d,
        SceneText3d,
        SingleChildLayout3dWidget;
import 'package:vector_math/vector_math.dart' show Matrix4;

import '../theme/theme.dart';
import 'divider.dart';
import 'ink_well.dart';
import 'material.dart';
import 'reading_direction.dart';
import 'tab_bar_style.dart';
import 'text_style.dart';

/// Transparent: a tab's own slab, which is there for its wash.
const Color _none = Color(0x00000000);

/// One tab of a [TabBar3d]: a label, an icon, or an icon over a label.
///
/// ```dart
/// const Tab3d(text: 'Flights', icon: Icon3d(Icons.flight))
/// ```
///
/// Flutter's `Tab`: 46dp tall with one of the two, 72dp with both, the label
/// centred and as wide as it is. **The label is a `String`**, for
/// `NavigationDestination3d`'s reason — a `Semantics3d` gathers nothing from
/// below, and this one string is both what is drawn and what the tab
/// announces. [child] stands in for it when a tab needs more than a word,
/// and then [semanticLabel] is the only name it has.
///
/// The heights are minimums here and fixed in Flutter, which is the rule
/// phase 2 of the catalogue settled on: a label at a large type setting makes
/// its tab taller rather than overflowing it.
class Tab3d extends StatelessWidget {
  /// Creates a tab. It needs [text], [child] or [icon], and not both of the
  /// first two.
  const Tab3d({
    super.key,
    this.text,
    this.icon,
    this.child,
    this.height,
    this.semanticLabel,
  }) : assert(text != null || child != null || icon != null),
       assert(text == null || child == null);

  /// What the tab says, and what it announces.
  final String? text;

  /// The glyph above the label, or the whole tab when there is no label.
  final Widget? icon;

  /// The label, when it is not a string.
  final Widget? child;

  /// The tab's height in logical pixels, or null for 46, or 72 with both an
  /// icon and a label.
  final double? height;

  /// What a screen reader announces the tab as, or null for [text].
  final String? semanticLabel;

  /// Whether this tab has an icon and a label, which makes it — and every
  /// other tab in its bar — 72dp tall.
  bool get hasTextAndIcon => icon != null && (text != null || child != null);

  /// What the tab announces.
  String? get announcement => semanticLabel ?? text;

  @override
  Widget build(BuildContext context) {
    final metrics = Layout3dMetricsScope.of(context);
    final style = TabBarStyle3d.of(
      Theme3d.of(context),
      TabBarVariant3d.primary,
    );
    final Widget label = child ?? SceneText3d(text ?? '');
    final Widget content;
    if (icon == null) {
      content = label;
    } else if (text == null && child == null) {
      content = icon!;
    } else {
      content = SceneColumn3d(
        mainAxisSize: MainAxisSize3d.min,
        mainAxisAlignment: MainAxisAlignment3d.center,
        children: <Widget>[
          ScenePadding3d(
            padding: metrics.dpInsets(style.iconMargin),
            child: icon,
          ),
          label,
        ],
      );
    }
    final tall =
        height ??
        (hasTextAndIcon ? style.textAndIconTabHeight : style.tabHeight);
    return SceneConstrainedBox3d(
      constraints: Constraints3d(minHeight: metrics.dp(tall)),
      child: SceneAlign3d(
        alignment: Alignment3d.frontCenter,
        widthFactor: 1.0,
        heightFactor: 1.0,
        child: content,
      ),
    );
  }
}

/// A row of tabs over a set of pages, with an indicator under the one shown.
///
/// ```dart
/// DefaultTabController(
///   length: 2,
///   child: SceneColumn3d(
///     crossAxisAlignment: CrossAxisAlignment3d.stretch,
///     children: const <Widget>[
///       TabBar3d(tabs: <Tab3d>[Tab3d(text: 'Inbox'), Tab3d(text: 'Sent')]),
///       SceneExpanded3d(
///         child: TabBarView3d(children: <Widget>[inbox, sent]),
///       ),
///     ],
///   ),
/// )
/// ```
///
/// Flutter's `TabBar`, both of it: this constructor is the primary bar, for
/// a screen's main sections, and [TabBar3d.secondary] is the one inside a
/// section. Everything either is made of is in [TabBarStyle3d].
///
/// ## The controller is Flutter's
///
/// [controller] is a `TabController`, and with none given this finds a
/// `DefaultTabController` above it — Flutter's own two classes, unchanged.
/// Neither has a render object in it: one is a `ChangeNotifier` around an
/// `AnimationController`, the other an inherited widget handing one down, so
/// a `DefaultTabController` can sit anywhere above this bar, inside the
/// surface or above it, and a ported screen keeps the one it has.
///
/// ## The indicator slides on the node tier
///
/// Where the indicator goes is a fact about layout — where each tab ended up
/// and how wide each label measured — and how it gets there is a fact about
/// the controller's animation, which moves every frame of a change. So a
/// private box lays the tabs out, then lays the indicator out at the chosen
/// tab's width under it, and from then on answers each tick of the animation
/// with a translation and a stretch: `docs/traps.md`'s answer for a bar that
/// fills its parent, applied to one that moves. **Across a change the bar
/// lays out on the frame it starts and the frame it ends and on none
/// between**, and rebuilds on the same two, for its labels' colours.
///
/// The primary indicator stretches toward the tab it is going to and draws
/// in behind, one edge on an accelerating curve and the other on a
/// decelerating one, transcribed from Flutter's `_applyElasticEffect`; the
/// secondary one moves straight across. At rest it is exact. In flight its
/// 3dp corners stretch with it, which is the price `Switch3d`'s thumb pays
/// for the same tier.
///
/// ## What differs from Flutter's
///
///  * **The labels change colour at once.** Flutter cross-fades the old and
///    the new tab's labels over the slide; a colour here is a token, and
///    fading one is a rebuild a frame. The switch made the same choice.
///  * **An unchosen tab washes in `onSurface`** whatever the state, where a
///    primary bar's pressed one washes `primary`: a wash here is one colour
///    per surface.
///  * **No `isScrollable`.** A scrolling bar is a horizontal scroll view
///    that has to start at the right in right to left, which needs the
///    `reverse` phase 6 of the catalogue plan is for.
///  * **No "Tab 1 of 3".** Flutter appends a localized position to each
///    tab's announcement; a string the catalogue would have to invent is the
///    language item's.
///
/// ## What it announces
///
/// Each tab announces its label with Flutter's `tab` role, `selected` on the
/// one shown. **The bar publishes nothing of its own**, where Flutter's wears
/// the `tabBar` role: Flutter checks that a tab bar's children are tabs, and a
/// `Semantics3d` has no children in that tree — a `tabBar` node here is an
/// empty bar, and with semantics on the frame will not build. The pages each
/// wear `tabPanel`, which asks nothing of its children.
class TabBar3d extends StatefulWidget {
  /// Creates a primary tab bar.
  const TabBar3d({
    super.key,
    required this.tabs,
    this.controller,
    this.onTap,
    this.style,
    this.textDirection,
  }) : variant = TabBarVariant3d.primary;

  /// Creates a secondary tab bar, for the subsections of one section.
  const TabBar3d.secondary({
    super.key,
    required this.tabs,
    this.controller,
    this.onTap,
    this.style,
    this.textDirection,
  }) : variant = TabBarVariant3d.secondary;

  /// Why a bar whose controller counts a different number of tabs is
  /// refused, in `build` — where Flutter checks it too, a frame later.
  static const String lengthMismatch =
      "A TabBar3d's controller must count exactly as many tabs as it has.";

  /// Why a bar with no controller is refused.
  static const String noController =
      'A TabBar3d needs a TabController: give it one, or put a '
      'DefaultTabController above it.';

  /// The tabs, in reading order.
  final List<Tab3d> tabs;

  /// The controller, or null for the nearest `DefaultTabController`'s.
  final TabController? controller;

  /// Called with the index of a tab that was pressed, after the controller
  /// has been told to animate to it.
  final ValueChanged<int>? onTap;

  /// The whole token set, or null for the variant's.
  final TabBarStyle3d? style;

  /// Which of Material's two bars this is.
  final TabBarVariant3d variant;

  /// The direction the tabs' labels are announced in.
  final TextDirection? textDirection;

  @override
  State<TabBar3d> createState() => _TabBar3dState();
}

class _TabBar3dState extends State<TabBar3d> {
  TabController? _controller;

  /// Where each tab and each label ended up, written by the boxes that
  /// measure them and read by the box that places the indicator.
  final _TabGeometry3d _geometry = _TabGeometry3d();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateController();
  }

  @override
  void didUpdateWidget(TabBar3d oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) _updateController();
  }

  @override
  void dispose() {
    _controller?.removeListener(_changed);
    super.dispose();
  }

  void _updateController() {
    final next = widget.controller ?? DefaultTabController.maybeOf(context);
    assert(next != null, TabBar3d.noController);
    if (identical(next, _controller)) return;
    _controller?.removeListener(_changed);
    _controller = next?..addListener(_changed);
  }

  /// The controller says the index moved, or a change started or ended:
  /// rebuild, for the labels' colours. Flutter's bar does the same.
  void _changed() {
    if (mounted) setState(() {});
  }

  void _pressed(int index) {
    _controller?.animateTo(index);
    widget.onTap?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    assert(controller.length == widget.tabs.length, TabBar3d.lengthMismatch);
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final resolved = widget.style ?? TabBarStyle3d.of(theme, widget.variant);
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    _geometry.length = widget.tabs.length;

    final anyTall = widget.tabs.any((tab) => tab.hasTextAndIcon);
    final lift = (resolved.textAndIconTabHeight - resolved.tabHeight) / 2.0;

    final row = SceneRow3d(
      children: <Widget>[
        for (var i = 0; i < widget.tabs.length; i++)
          SceneExpanded3d(
            child: _tab(
              context,
              resolved,
              index: i,
              chosen: i == controller.index,
              // A tab with only one of the two, in a bar where another has
              // both, is padded to the same height, as Flutter's is.
              raise: anyTall && !widget.tabs[i].hasTextAndIcon ? lift : 0.0,
            ),
          ),
      ],
    );

    final divider = SceneIgnorePointer3d(
      child: resolved.dividerHeight > 0.0
          ? Divider3d(
              space: resolved.dividerHeight,
              thickness: resolved.dividerHeight,
              depth: resolved.thickness,
              color: resolved.dividerColor,
            )
          : const SceneSizedBox3d(),
    );

    final indicator = SceneIgnorePointer3d(
      child: Material3d(
        color: resolved.indicatorColor,
        shape: resolved.indicatorShape,
        elevation: theme.elevation.level0,
        thickness: resolved.thickness,
        surfaceTint: _none,
      ),
    );

    // No `tabBar` node around the tabs. Flutter checks, whenever semantics
    // are on, that a tab bar's children are tabs — and a `Semantics3d` has no
    // children in that tree, so the node read as an empty bar and the frame
    // would not build. The gallery found it with a screen reader's semantics
    // on; no headless test turns them on through a scene.
    return _SceneTabBarLayout3d(
      controller: controller,
      geometry: _geometry,
      labelSized: resolved.indicatorSize == TabBarIndicatorSize3d.label,
      animation: resolved.indicatorAnimation,
      direction: direction,
      indicatorWeight: metrics.dp(resolved.indicatorWeight),
      dividerHeight: metrics.dp(resolved.dividerHeight),
      depthStep: metrics.dp(resolved.depthStep),
      children: <Widget>[row, divider, indicator],
    );
  }

  Widget _tab(
    BuildContext context,
    TabBarStyle3d resolved, {
    required int index,
    required bool chosen,
    required double raise,
  }) {
    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final tab = widget.tabs[index];
    final color = chosen ? resolved.labelColor : resolved.unselectedLabelColor;
    void tap() => _pressed(index);

    final label = _SceneTabMeasure3d(
      geometry: _geometry,
      index: index,
      label: true,
      child: SceneTextStyle3d(
        style: resolved.labelStyle,
        color: color,
        child: SceneIgnorePointer3d(child: tab),
      ),
    );

    // Its own surface, so its own wash: an `InkWell3d` washes the enclosing
    // `Material3d`, and one shared slab would light the whole bar up.
    final surface = Material3d(
      color: _none,
      contentColor: chosen ? resolved.labelColor : theme.colorScheme.onSurface,
      shape: theme.shape.none,
      elevation: theme.elevation.level0,
      thickness: resolved.thickness,
      surfaceTint: _none,
      alignment: null,
      child: InkWell3d(
        // One target, and it is the one outside this panel.
        minimumSize: Size3d.zero,
        onTap: tap,
        // The space under the tab is the tab's, as Flutter's `InkWell` wraps
        // its padding: a press on the indicator is a press on its tab.
        child: ScenePadding3d(
          padding: metrics.dpInsets(
            EdgeInsets3d.only(bottom: resolved.reservedHeight),
          ),
          child: ScenePadding3d(
            padding: metrics.dpInsets(
              resolved.labelPadding + EdgeInsets3d.symmetric(vertical: raise),
            ),
            child: SceneAlign3d(
              alignment: Alignment3d.frontCenter,
              child: label,
            ),
          ),
        ),
      ),
    );

    final announced = SceneSemantics3d(
      properties: SemanticsProperties(
        role: SemanticsRole.tab,
        selected: chosen,
        enabled: true,
        label: tab.announcement,
        textDirection: readingDirection3d(context, widget.textDirection),
        onTap: tap,
      ),
      child: surface,
    );

    return _SceneTabMeasure3d(
      geometry: _geometry,
      index: index,
      label: false,
      // Outermost, for the reason every control here puts it there.
      child: SceneTapTarget3d(child: announced),
    );
  }
}

/// Where the tabs of one bar ended up, by index: the box each tab fills and
/// the box its label is.
///
/// Written by [_TabMeasure3d] when a box is made or handed a new index, and
/// read by [_TabBarLayout3d] once the row of tabs has been laid out — so it
/// holds boxes, not numbers, and the numbers are always this pass's.
class _TabGeometry3d {
  final List<Layout3d?> _slots = <Layout3d?>[];
  final List<Layout3d?> _labels = <Layout3d?>[];

  set length(int value) {
    while (_slots.length < value) {
      _slots.add(null);
      _labels.add(null);
    }
    _slots.length = value;
    _labels.length = value;
  }

  int get length => _slots.length;

  void put(int index, Layout3d box, {required bool label}) {
    if (index >= length) length = index + 1;
    (label ? _labels : _slots)[index] = box;
  }

  void release(Layout3d box) {
    for (var i = 0; i < length; i++) {
      if (identical(_slots[i], box)) _slots[i] = null;
      if (identical(_labels[i], box)) _labels[i] = null;
    }
  }

  /// Each tab's left and right edges, in [row]'s frame, or as wide as its
  /// label when [labelSized]: null until every one of them has a size.
  List<(double, double)>? spansIn(Layout3d row, {required bool labelSized}) {
    final spans = <(double, double)>[];
    for (var i = 0; i < length; i++) {
      final box = (labelSized ? _labels : _slots)[i];
      if (box == null || !box.hasSize) return null;
      final left = _xIn(box, row);
      if (left == null) return null;
      spans.add((left, left + box.size.width));
    }
    return spans;
  }

  /// Where [box]'s left edge is in [ancestor]'s frame, summing the layout
  /// offsets between them — never the node tier, which is the indicator's
  /// own to write.
  static double? _xIn(Layout3d box, Layout3d ancestor) {
    var x = 0.0;
    for (Layout3d? walk = box; walk != null; walk = walk.parent) {
      if (identical(walk, ancestor)) return x;
      x += walk.offset.x;
    }
    return null;
  }
}

/// Records a tab's box, or its label's, in a [_TabGeometry3d].
class _TabMeasure3d extends ProxyLayout3d {
  _TabMeasure3d({
    required _TabGeometry3d geometry,
    required int index,
    required bool label,
  }) : _geometry = geometry,
       _index = index,
       _label = label,
       super(name: 'TabBar3d ${label ? 'label' : 'tab'} $index') {
    geometry.put(index, this, label: label);
  }

  _TabGeometry3d _geometry;
  int _index;
  final bool _label;

  void update(_TabGeometry3d geometry, int index) {
    if (identical(geometry, _geometry) && index == _index) return;
    _geometry.release(this);
    _geometry = geometry;
    _index = index;
    geometry.put(index, this, label: _label);
  }

  @override
  void dispose() {
    _geometry.release(this);
    super.dispose();
  }
}

class _SceneTabMeasure3d extends SingleChildLayout3dWidget {
  const _SceneTabMeasure3d({
    required this.geometry,
    required this.index,
    required this.label,
    super.child,
  });

  final _TabGeometry3d geometry;
  final int index;
  final bool label;

  @override
  _TabMeasure3d createLayout(BuildContext context) =>
      _TabMeasure3d(geometry: geometry, index: index, label: label);

  @override
  void updateLayout(BuildContext context, _TabMeasure3d layout) =>
      layout.update(geometry, index);
}

/// The tab bar's own box: the row of tabs, the rule under them, and the
/// indicator, in that order and in depth.
///
/// It exists for the indicator. Where the indicator rests is decided by the
/// row's layout, so the row is laid out first and the indicator is then
/// handed **tight** constraints at the chosen tab's width — the protocol's
/// own way of saying the parent decides — and is laid out again only when
/// that width changes. Everything between two resting places is the node
/// tier: [_applyNode] writes a translation and a stretch on every tick of the
/// controller's animation and marks nothing for layout.
class _TabBarLayout3d extends MultiChildLayout3d<ParentData3d> {
  _TabBarLayout3d({
    required TabController controller,
    required this.geometry,
    required this.labelSized,
    required this.animation,
    required this.direction,
    required this.indicatorWeight,
    required this.dividerHeight,
    required this.depthStep,
  }) : _controller = controller,
       super(name: 'TabBar3d') {
    _listen(controller);
  }

  TabController _controller;
  _TabGeometry3d geometry;
  bool labelSized;
  TabIndicatorAnimation3d animation;
  TextDirection direction;
  double indicatorWeight;
  double dividerHeight;
  double depthStep;

  /// The index the indicator was last laid out to rest under.
  int? _laidOutIndex;

  /// Every tab's span, from the last layout.
  List<(double, double)>? _spans;

  /// Where the indicator rests: its left edge and its width.
  (double, double)? _rest;

  TabController get controller => _controller;

  set controller(TabController value) {
    if (identical(value, _controller)) return;
    _unlisten(_controller);
    _controller = value;
    _listen(value);
    markNeedsLayout();
  }

  void _listen(TabController controller) {
    controller.addListener(_indexMoved);
    controller.animation?.addListener(_applyNode);
  }

  void _unlisten(TabController controller) {
    controller.removeListener(_indexMoved);
    // A controller replaced and disposed by its owner has no animation left.
    controller.animation?.removeListener(_applyNode);
  }

  /// A new index rests the indicator under a different tab, which is a
  /// different width: one relayout, of the indicator alone. The end of a
  /// change notifies too, and moves nothing.
  void _indexMoved() {
    if (_controller.index != _laidOutIndex) markNeedsLayout();
  }

  @override
  void dispose() {
    _unlisten(_controller);
    super.dispose();
  }

  Layout3d? get _row => childCount > 0 ? childAt(0) : null;

  @override
  double computeMinIntrinsicExtent(Axis3d axis, Size3d limits) =>
      _row?.getMinIntrinsicExtent(axis, limits) ?? 0.0;

  @override
  double computeMaxIntrinsicExtent(Axis3d axis, Size3d limits) =>
      _row?.getMaxIntrinsicExtent(axis, limits) ?? 0.0;

  @override
  void performLayout() {
    final row = _row;
    if (row == null) {
      size = constraints.smallest;
      return;
    }
    // As wide as it is offered, and as tall as its tabs.
    row.layout(
      Constraints3d(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
        maxHeight: constraints.maxHeight,
        maxDepth: constraints.maxDepth,
      ),
      parentUsesSize: true,
    );
    size = constraints.constrain(row.size);
    row.place(Offset3d.zero);

    if (childCount > 1) {
      final rule = childAt(1);
      rule.layout(
        Constraints3d(
          minWidth: size.width,
          maxWidth: size.width,
          minHeight: dividerHeight,
          maxHeight: dividerHeight,
          maxDepth: size.depth,
        ),
      );
      // In front of the tabs, so a tab's wash does not cover it.
      parentDataOf(rule).sceneOffset = Offset3d(0.0, 0.0, -depthStep);
      rule.place(Offset3d(0.0, size.height - dividerHeight, 0.0));
    }

    if (childCount > 2) {
      final indicator = childAt(2);
      _spans = geometry.spansIn(row, labelSized: labelSized);
      final index = _controller.index;
      final spans = _spans;
      _rest = spans == null || index >= spans.length
          ? null
          : (spans[index].$1, spans[index].$2 - spans[index].$1);
      _laidOutIndex = index;
      final width = _rest?.$2 ?? 0.0;
      indicator.layout(
        Constraints3d(
          minWidth: width,
          maxWidth: width,
          minHeight: indicatorWeight,
          maxHeight: indicatorWeight,
          maxDepth: size.depth,
        ),
      );
      // In front of the rule, which it is drawn over.
      parentDataOf(indicator).sceneOffset = Offset3d(
        0.0,
        0.0,
        -2.0 * depthStep,
      );
      indicator.place(
        Offset3d(_rest?.$1 ?? 0.0, size.height - indicatorWeight, 0.0),
      );
      _applyNode();
    }
  }

  /// Moves the indicator from where it rests to where the animation has it,
  /// on the node tier.
  void _applyNode() {
    if (childCount < 3) return;
    final indicator = childAt(2);
    final spans = _spans;
    final rest = _rest;
    final value = _controller.animation?.value;
    if (spans == null || rest == null || value == null || rest.$2 <= 0.0) {
      indicator.nodeOffset = Offset3d.zero;
      indicator.nodeTransform = null;
      return;
    }
    final (left, right) = tabIndicatorSpan3d(
      spans,
      value: value,
      index: _controller.index,
      previousIndex: _controller.previousIndex,
      indexIsChanging: _controller.indexIsChanging,
      completed: _controller.animation!.isCompleted,
      direction: direction,
      animation: animation,
    );
    final scale = (right - left) / rest.$2;
    indicator.nodeOffset = Offset3d(left - rest.$1, 0.0, 0.0);
    // About the indicator's own left edge, which is where a node transform
    // pivots: the same arithmetic `NodeShift3d` does for a slider's fill.
    indicator.nodeTransform = (scale - 1.0).abs() < 1e-9
        ? null
        : Matrix4.diagonal3Values(scale, 1.0, 1.0);
  }
}

class _SceneTabBarLayout3d extends Layout3dWidget {
  const _SceneTabBarLayout3d({
    required this.controller,
    required this.geometry,
    required this.labelSized,
    required this.animation,
    required this.direction,
    required this.indicatorWeight,
    required this.dividerHeight,
    required this.depthStep,
    super.children,
  });

  final TabController controller;
  final _TabGeometry3d geometry;
  final bool labelSized;
  final TabIndicatorAnimation3d animation;
  final TextDirection direction;
  final double indicatorWeight;
  final double dividerHeight;
  final double depthStep;

  @override
  _TabBarLayout3d createLayout(BuildContext context) => _TabBarLayout3d(
    controller: controller,
    geometry: geometry,
    labelSized: labelSized,
    animation: animation,
    direction: direction,
    indicatorWeight: indicatorWeight,
    dividerHeight: dividerHeight,
    depthStep: depthStep,
  );

  @override
  void updateLayout(BuildContext context, _TabBarLayout3d layout) {
    layout.controller = controller;
    if (layout.labelSized != labelSized ||
        layout.indicatorWeight != indicatorWeight ||
        layout.dividerHeight != dividerHeight ||
        layout.depthStep != depthStep ||
        layout.direction != direction ||
        !identical(layout.geometry, geometry)) {
      layout
        ..geometry = geometry
        ..labelSized = labelSized
        ..indicatorWeight = indicatorWeight
        ..dividerHeight = dividerHeight
        ..depthStep = depthStep
        ..direction = direction
        ..markNeedsLayout();
    }
    layout.animation = animation;
  }
}

/// Where a tab bar's indicator is drawn, as its left and right edges, for
/// the controller's animation at [value].
///
/// [spans] is each tab's resting place, left to right on the plane — which
/// in right to left is not the order of the tabs. Flutter's `_IndicatorPainter`
/// is the source, `_applyLinearEffect` and `_applyElasticEffect`, transcribed
/// with its own variable names so the two can be read side by side.
(double, double) tabIndicatorSpan3d(
  List<(double, double)> spans, {
  required double value,
  required int index,
  required int previousIndex,
  required bool indexIsChanging,
  required bool completed,
  required TextDirection direction,
  required TabIndicatorAnimation3d animation,
}) {
  final maxTabIndex = spans.length - 1;
  (double, double) lerp((double, double) a, (double, double) b, double t) =>
      (lerpDouble(a.$1, b.$1, t)!, lerpDouble(a.$2, b.$2, t)!);

  if (animation == TabIndicatorAnimation3d.linear) {
    final ltr = index > value;
    final from = (ltr ? value.floor() : value.ceil()).clamp(0, maxTabIndex);
    final to = (ltr ? from + 1 : from - 1).clamp(0, maxTabIndex);
    return lerp(spans[from], spans[to], (value - from).abs());
  }

  var progressLeft = (index - value).abs();
  final settled = progressLeft == 0.0 || !indexIsChanging;
  final to = settled
      ? (direction == TextDirection.ltr ? value.ceil() : value.floor()).clamp(
          0,
          maxTabIndex,
        )
      : index;
  final from = settled
      ? (direction == TextDirection.ltr ? to - 1 : to + 1).clamp(0, maxTabIndex)
      : previousIndex;
  final toSpan = spans[to];
  final fromSpan = spans[from];
  final rect = lerp(fromSpan, toSpan, (value - from).abs());
  if (completed) return rect;

  final double tabChangeProgress;
  if (indexIsChanging) {
    final tabsDelta = (index - previousIndex).abs();
    if (tabsDelta != 0) progressLeft /= tabsDelta;
    tabChangeProgress = 1 - progressLeft.clamp(0.0, 1.0);
  } else {
    tabChangeProgress = (index - value).abs();
  }
  if (tabChangeProgress == 1.0) return rect;

  // Ease in and ease out on a quarter sine.
  double accelerate(double t) => 1.0 - math.cos((t * math.pi) / 2.0);
  double decelerate(double t) => math.sin((t * math.pi) / 2.0);

  final isMovingRight = switch (direction) {
    TextDirection.ltr => indexIsChanging ? index > value : value > index,
    TextDirection.rtl => indexIsChanging ? value > index : index > value,
  };
  final leftFraction = isMovingRight
      ? accelerate(tabChangeProgress)
      : decelerate(tabChangeProgress);
  final rightFraction = isMovingRight
      ? decelerate(tabChangeProgress)
      : accelerate(tabChangeProgress);

  final double left;
  final double right;
  if (indexIsChanging) {
    left = lerpDouble(fromSpan.$1, toSpan.$1, leftFraction)!;
    right = lerpDouble(fromSpan.$2, toSpan.$2, rightFraction)!;
  } else {
    left = isMovingRight
        ? lerpDouble(fromSpan.$1, toSpan.$1, leftFraction)!
        : lerpDouble(toSpan.$1, fromSpan.$1, leftFraction)!;
    right = isMovingRight
        ? lerpDouble(fromSpan.$2, toSpan.$2, rightFraction)!
        : lerpDouble(toSpan.$2, fromSpan.$2, rightFraction)!;
  }
  return (left, right);
}

/// The pages under a [TabBar3d], one per tab, turned by its controller and
/// turning it.
///
/// ```dart
/// TabBarView3d(children: <Widget>[inbox, sent])
/// ```
///
/// Flutter's `TabBarView`: a page view whose pages are the tabs' contents.
/// A press on a tab animates the pages to it, with the controller's own
/// duration on `Curves.ease`; a swipe writes the controller's `offset` as it
/// goes, so the indicator follows the finger, and its `index` when the pages
/// come to rest. It is a [ScenePageView3d], snapping a page at a time, and it
/// needs a bounded extent along its width, as every page view does.
///
/// **It clips its pages to its own window**, as Flutter's does by default: a
/// scroll view here does not clip on its own, so the view is a `ClipBox3d`
/// around one. A page half across it has its panels cut at the edge by their
/// shader, and its labels — which a clip plane does not reach — are not drawn
/// once they are wholly outside. A label straddling the edge is drawn whole
/// for the frames it straddles.
///
/// ## Right to left reads the pages backwards
///
/// A horizontal page view here starts at the left in every language, because
/// no scroll view has `reverse`. Flutter reverses the axis; for a view whose
/// length is known the same thing is a renumbering, so in right to left the
/// first page is laid out last, the view opens at its far end, and a swipe
/// toward the right brings the next tab in from the left.
///
/// ## A list in a page takes the swipe
///
/// A drag here takes hold of the nearest scrolling view on its path, whatever
/// way the finger then moves — the layout package does not let two views on
/// different axes compete for it the way Flutter's recognizers do. So a page
/// that is a vertical list scrolls under a sideways swipe and the pages do
/// not turn; only a press on a tab does. A page without a scroll view of its
/// own swipes as Flutter's does.
///
/// ## What differs from Flutter's
///
/// A press two or more tabs away slides straight across the pages between,
/// where Flutter swaps the neighbouring page out of the way first so only
/// the two ends are ever seen; the pages between are built on the way.
class TabBarView3d extends StatefulWidget {
  /// Creates the pages under a tab bar.
  const TabBarView3d({super.key, required this.children, this.controller});

  /// The pages, one per tab, in the tabs' order.
  final List<Widget> children;

  /// The controller, or null for the nearest `DefaultTabController`'s.
  final TabController? controller;

  @override
  State<TabBarView3d> createState() => _TabBarView3dState();
}

class _TabBarView3dState extends State<TabBarView3d>
    with TickerProviderStateMixin {
  TabController? _controller;
  late final _TabPages3d _pages = _TabPages3d(vsync: this, onSettled: _settled);

  /// The index this view last turned to.
  int _currentIndex = 0;

  /// How many programmatic turns are under way: while one is, the pages are
  /// following the controller rather than driving it.
  int _warping = 0;

  /// Whether this view is writing the controller, so its own notifications
  /// are not read as a press.
  bool _syncing = false;

  bool get _rightToLeft =>
      (Directionality.maybeOf(context) ?? TextDirection.ltr) ==
      TextDirection.rtl;

  /// The position in the view of the page for tab [index].
  int _positionOf(int index) =>
      _rightToLeft ? widget.children.length - 1 - index : index;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateController();
    _pages.page = _positionOf(_currentIndex).toDouble();
  }

  @override
  void didUpdateWidget(TabBarView3d oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) _updateController();
  }

  @override
  void dispose() {
    _unlisten();
    _pages
      ..onSettled = null
      ..dispose();
    super.dispose();
  }

  void _unlisten() {
    _controller?.animation?.removeListener(_animated);
    _pages.removeListener(_scrolled);
  }

  void _updateController() {
    final next = widget.controller ?? DefaultTabController.maybeOf(context);
    assert(next != null, TabBar3d.noController);
    if (identical(next, _controller)) return;
    _unlisten();
    _controller = next;
    if (next == null) return;
    next.animation?.addListener(_animated);
    _pages.addListener(_scrolled);
    _currentIndex = next.index;
    _pages.jumpToPage(_positionOf(_currentIndex));
  }

  /// The controller is animating to a tab a press chose: follow it.
  void _animated() {
    final controller = _controller;
    if (controller == null || _syncing || !controller.indexIsChanging) return;
    if (controller.index == _currentIndex) return;
    _currentIndex = controller.index;
    _warp(controller);
  }

  Future<void> _warp(TabController controller) async {
    final target = _positionOf(_currentIndex);
    _warping++;
    try {
      if (controller.animationDuration == Duration.zero) {
        _pages.jumpToPage(target);
      } else {
        await _pages.animateTo(
          target * _pages.viewportExtent,
          duration: controller.animationDuration,
          curve: Curves.ease,
        );
      }
    } finally {
      _warping--;
    }
  }

  /// Where the pages are, counted in tabs rather than in positions.
  double? get _page {
    final extent = _pages.viewportExtent;
    if (extent <= 0.0) return null;
    final position = _pages.offset / extent;
    return _rightToLeft ? widget.children.length - 1 - position : position;
  }

  /// A finger, or the settle after one, moved the pages: tell the controller.
  void _scrolled() {
    final controller = _controller;
    final page = _page;
    if (controller == null || page == null || _warping > 0) return;
    if (controller.indexIsChanging) return;
    _syncing = true;
    try {
      if ((page - controller.index).abs() > 1.0) {
        controller.index = page.round();
        _currentIndex = controller.index;
      }
      controller.offset = (page - controller.index).clamp(-1.0, 1.0);
    } finally {
      _syncing = false;
    }
  }

  /// The pages came to rest: the tab under them is the chosen one.
  void _settled() {
    final controller = _controller;
    final page = _page;
    if (!mounted || controller == null || page == null || _warping > 0) {
      return;
    }
    _syncing = true;
    try {
      controller.index = page.round().clamp(0, controller.length - 1);
      _currentIndex = controller.index;
      if (!controller.indexIsChanging) {
        controller.offset = (page - controller.index).clamp(-1.0, 1.0);
      }
    } finally {
      _syncing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    assert(
      controller.length == widget.children.length,
      "A TabBarView3d's controller must count exactly as many tabs as it "
      'has pages.',
    );
    final count = widget.children.length;
    final rightToLeft = _rightToLeft;
    // Clipped to its own window, as Flutter's `TabBarView` is by default: a
    // scroll view here does not clip on its own, and a page half across it
    // would otherwise draw its panels and its labels outside the view.
    return SceneClipBox3d(
      child: ScenePageView3d.builder(
        controller: _pages,
        itemCount: count,
        itemBuilder: (context, position) => SceneSemantics3d(
          properties: const SemanticsProperties(role: SemanticsRole.tabPanel),
          child: widget.children[rightToLeft ? count - 1 - position : position],
        ),
      ),
    );
  }
}

/// The scroll position under a [TabBarView3d].
///
/// A `Scroll3dController` with page physics and two things a tab view needs
/// that a page view does not:
///
///  * **It keeps its page when the window's extent changes**, which includes
///    the first layout, where the extent goes from nothing to something. That
///    is how the view opens on the controller's tab rather than on the first
///    page and then jumping: reporting the metrics may move the offset, and a
///    viewport that sees it move lays the pass out again from there.
///  * **It says when it comes to rest**, which is when a swipe has chosen a
///    tab. A drag let go with nothing left to settle, and a settle that runs
///    out, both end here.
class _TabPages3d extends Scroll3dController {
  _TabPages3d({super.vsync, required this.onSettled})
    : super(physics: PageScroll3dPhysics());

  /// Called when the position stops moving and nothing is holding it.
  void Function()? onSettled;

  /// The page to show, in positions, until the window has an extent.
  double page = 0.0;

  void jumpToPage(int position) {
    page = position.toDouble();
    if (viewportExtent > 0.0) jumpTo(position * viewportExtent);
  }

  @override
  void applyViewportMetrics({
    required double maxScrollExtent,
    required double viewportExtent,
    double? contentExtent,
    double? unitsPerLogicalPixel,
  }) {
    final previous = this.viewportExtent;
    final keep = previous > 0.0 ? offset / previous : page;
    super.applyViewportMetrics(
      maxScrollExtent: maxScrollExtent,
      viewportExtent: viewportExtent,
      contentExtent: contentExtent,
      unitsPerLogicalPixel: unitsPerLogicalPixel,
    );
    if (viewportExtent > 0.0 &&
        viewportExtent != previous &&
        !isDragging &&
        !isAnimating) {
      // Silently: this runs during layout, and the viewport lays the pass out
      // again when it sees the offset move.
      correctBy(keep.round() * viewportExtent - offset);
    }
  }

  @override
  void endUserScroll({double velocity = 0.0}) {
    super.endUserScroll(velocity: velocity);
    if (!isAnimating) onSettled?.call();
  }

  @override
  void stopAnimation() {
    final wasAnimating = isAnimating;
    super.stopAnimation();
    if (wasAnimating && !isDragging) onSettled?.call();
  }
}
