import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart'
    show BuildContext, Directionality, StatelessWidget, TextDirection, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show
        Alignment3d,
        AlignmentGeometry3d,
        Constraints3d,
        EdgeInsets3d,
        Layout3dChildIntrinsicsMixin,
        Offset3d,
        SingleChildLayout3d,
        Size3d;
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dMetricsScope,
        SceneAlign3d,
        SceneIgnorePointer3d,
        ScenePositioned3d,
        SceneSemantics3d,
        SceneSizedBox3d,
        SceneStack3d,
        SceneText3d,
        SingleChildLayout3dWidget;

import '../theme/theme.dart';
import 'badge_style.dart';
import 'material.dart';
import 'reading_direction.dart';

/// A small mark at the corner of something, saying there is news there.
///
/// ```dart
/// NavigationDestination3d(
///   icon: Badge3d.count(count: unread, child: const Icon3d(Icons.inbox)),
///   label: 'Inbox',
/// )
/// ```
///
/// Flutter's `Badge`: a 6dp dot with no [label], or a 16dp stadium with one,
/// in `error` with an `onError` `labelSmall` label, at the top-end corner of
/// [child]. [Badge3d.count] writes the number and caps it at `999+`. Everything
/// it is made of is in [BadgeStyle3d].
///
/// ## It is drawn in front of what it decorates, which is a distance here
///
/// Flutter paints a badge after its child and is done. Here the badge is a
/// slab and the child is geometry, and the child is very often an icon — a
/// glyph whose wall reaches a tenth of its size toward the viewer. So the
/// badge stands [BadgeStyle3d.depthStep] in front of the child's front face,
/// on the node tier, far enough that a 24dp icon's corner does not come
/// through it. The badge never moves the child, never takes space in a row,
/// and never answers a ray: a press on it is a press on whatever it is
/// decorating, as in Flutter.
///
/// ## It may be bigger than what it is on
///
/// A three-digit badge on a 24dp icon is wider than the icon. A
/// `Positioned3d` in a stack could not express that — a stack caps a
/// positioned child's free axes at its own size — so the badge is laid out
/// unconstrained by a box of its own, which is what Flutter's `_RenderBadge`
/// does for the same reason. The label grows with the reader's type, and the
/// badge stays a stadium: it is never narrower than it is tall.
///
/// ## What it announces
///
/// Nothing, unless it is given a [semanticLabel] — `Icon3d`'s rule, for the
/// same reason. A `Semantics3d` gathers nothing from below it, and a badge
/// does not know what it is counting: "3" is not a thing a reader can act
/// on, and "3 unread messages" is a sentence only the application can write.
class Badge3d extends StatelessWidget {
  /// Creates a badge, with a [label] or as a dot.
  const Badge3d({
    super.key,
    this.backgroundColor,
    this.textColor,
    this.smallSize,
    this.largeSize,
    this.padding,
    this.alignment,
    this.offset,
    this.label,
    this.isLabelVisible = true,
    this.style,
    this.semanticLabel,
    this.textDirection,
    this.child,
  });

  /// Creates a badge whose label is [count], written as `$maxCount+` once it
  /// passes [maxCount].
  Badge3d.count({
    super.key,
    this.backgroundColor,
    this.textColor,
    this.smallSize,
    this.largeSize,
    this.padding,
    this.alignment,
    this.offset,
    required int count,
    int maxCount = 999,
    this.isLabelVisible = true,
    this.style,
    this.semanticLabel,
    this.textDirection,
    this.child,
  }) : assert(count >= 0, 'count must be non-negative'),
       assert(maxCount > 0, 'maxCount must be positive'),
       label = SceneText3d(count > maxCount ? '$maxCount+' : '$count');

  /// The stadium's colour, or null for the style's `error`.
  final Color? backgroundColor;

  /// The label's colour, or null for the style's `onError`.
  final Color? textColor;

  /// The diameter of a badge with no label, in logical pixels, or null for
  /// the style's 6.
  final double? smallSize;

  /// The height of a badge with a label, in logical pixels, or null for the
  /// style's 16.
  final double? largeSize;

  /// Space either side of the label, in logical pixels, or null for the
  /// style's 4. **In-plane only**, as every Material inset here is.
  final EdgeInsets3d? padding;

  /// Which corner of [child] the badge sits at, or null for the top end.
  final AlignmentGeometry3d? alignment;

  /// How far a labelled badge is moved from its corner, in logical pixels,
  /// with x toward the end, or null for the style's.
  ///
  /// Mirrored in right to left, which Flutter does for its default and not
  /// for an offset an application states; here both mirror.
  final Offset3d? offset;

  /// What the badge says, usually a short `SceneText3d`, or null for a dot.
  final Widget? label;

  /// Whether the badge is drawn at all. False leaves [child] alone, laid out
  /// exactly as it would be with no badge.
  final bool isLabelVisible;

  /// The whole token set, or null for `BadgeStyle3d.of(theme)`.
  final BadgeStyle3d? style;

  /// What a screen reader announces the badge as, or null for nothing.
  final String? semanticLabel;

  /// The direction [semanticLabel] reads in.
  final TextDirection? textDirection;

  /// What the badge decorates, or null for a badge on its own.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (!isLabelVisible) return child ?? const SceneSizedBox3d();

    final theme = Theme3d.of(context);
    final metrics = Layout3dMetricsScope.of(context);
    final resolved = style ?? BadgeStyle3d.of(theme);
    final hasLabel = label != null;
    final background = backgroundColor ?? resolved.backgroundColor;
    final foreground = textColor ?? resolved.textColor;
    final small = smallSize ?? resolved.smallSize;
    final large = largeSize ?? resolved.largeSize;

    final surface = Material3d(
      color: background,
      contentColor: foreground,
      shape: theme.shape.full,
      elevation: theme.elevation.level0,
      thickness: resolved.thickness,
      surfaceTint: const Color(0x00000000),
      padding: hasLabel ? (padding ?? resolved.padding) : EdgeInsets3d.zero,
      textStyle: theme.textStyle(resolved.textStyle, color: foreground),
      // Null, with an align inside that shrink-wraps: an aligning surface
      // fills every bounded axis it is given, and a badge on its own in a
      // loose box would come out the size of the box.
      alignment: null,
      child: label == null
          ? null
          : SceneAlign3d(
              alignment: Alignment3d.frontCenter,
              widthFactor: 1.0,
              heightFactor: 1.0,
              child: label,
            ),
    );

    Widget badge = hasLabel
        ? _SceneBadgeStadium3d(minExtent: metrics.dp(large), child: surface)
        : SceneSizedBox3d(
            width: metrics.dp(small),
            height: metrics.dp(small),
            child: surface,
          );

    final announced = semanticLabel;
    if (announced != null) {
      badge = SceneSemantics3d(
        properties: SemanticsProperties(
          label: announced,
          textDirection: readingDirection3d(context, textDirection),
        ),
        child: badge,
      );
    }

    final decorated = child;
    if (decorated == null) return badge;

    final rightToLeft = Directionality.maybeOf(context) == TextDirection.rtl;
    final stated = offset ?? resolved.offset;
    // Flutter adds 8dp down to a labelled badge's offset, to keep the
    // placement it had before #146853 changed the arithmetic, and the badge
    // box then lifts the badge by half its own height. A dot ignores the
    // offset and sits inside its corner.
    final placed = hasLabel
        ? Offset3d(
            metrics.dp(rightToLeft ? -stated.x : stated.x),
            metrics.dp(stated.y + 8.0),
            0.0,
          )
        : Offset3d.zero;

    return SceneStack3d(
      // In front of the child by the style's step, on the node tier: the
      // stack's step is a scene offset, so the badge's geometry stands off the
      // icon while its box stays inside the stack.
      depthStep: metrics.dp(resolved.depthStep),
      children: <Widget>[
        decorated,
        ScenePositioned3d(
          left: 0,
          top: 0,
          right: 0,
          bottom: 0,
          // A badge never takes a press from what it is on.
          child: SceneIgnorePointer3d(
            child: _SceneBadgePlacement3d(
              alignment: alignment ?? resolved.alignment,
              offset: placed,
              widthOffset: metrics.dp(hasLabel ? large : small),
              hasLabel: hasLabel,
              child: badge,
            ),
          ),
        ),
      ],
    );
  }
}

/// The box that puts a badge at its child's corner: Flutter's `_RenderBadge`.
///
/// It fills the stack it is in — so it knows the child's size — and lays the
/// badge out **unconstrained**, so a badge wider than the icon under it is as
/// wide as its label rather than as wide as the icon. Then it places it by
/// Flutter's arithmetic: [alignment] along the box less [widthOffset], plus
/// [offset], and a labelled badge up by half its height.
class _BadgePlacement3d extends SingleChildLayout3d {
  _BadgePlacement3d({
    required AlignmentGeometry3d alignment,
    required TextDirection? textDirection,
    required Offset3d offset,
    required double widthOffset,
    required bool hasLabel,
  }) : _alignment = alignment,
       _textDirection = textDirection,
       _offset = offset,
       _widthOffset = widthOffset,
       _hasLabel = hasLabel,
       super(name: 'Badge3d placement');

  AlignmentGeometry3d _alignment;
  set alignment(AlignmentGeometry3d value) {
    if (_alignment == value) return;
    _alignment = value;
    markNeedsLayout();
  }

  TextDirection? _textDirection;
  set textDirection(TextDirection? value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  Offset3d _offset;
  set offset(Offset3d value) {
    if (_offset == value) return;
    _offset = value;
    markNeedsLayout();
  }

  double _widthOffset;
  set widthOffset(double value) {
    if (_widthOffset == value) return;
    _widthOffset = value;
    markNeedsLayout();
  }

  bool _hasLabel;
  set hasLabel(bool value) {
    if (_hasLabel == value) return;
    _hasLabel = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final constraints = this.constraints;
    size = Size3d(
      constraints.hasBoundedWidth ? constraints.maxWidth : constraints.minWidth,
      constraints.hasBoundedHeight
          ? constraints.maxHeight
          : constraints.minHeight,
      constraints.hasBoundedDepth ? constraints.maxDepth : constraints.minDepth,
    );
    final child = this.child;
    if (child == null) return;
    child.layout(const Constraints3d(), parentUsesSize: true);
    final resolved = _alignment.resolve(_textDirection);
    final x =
        (resolved.x + 1.0) / 2.0 * (size.width - _widthOffset) + _offset.x;
    var y = (resolved.y + 1.0) / 2.0 * size.height + _offset.y;
    if (_hasLabel) y -= child.size.height / 2.0;
    // In depth the badge starts at the stack's front face; what carries it in
    // front of the child is the stack's step, on the node tier.
    child.place(Offset3d(x, y, 0.0));
  }
}

class _SceneBadgePlacement3d extends SingleChildLayout3dWidget {
  const _SceneBadgePlacement3d({
    required this.alignment,
    required this.offset,
    required this.widthOffset,
    required this.hasLabel,
    super.child,
  });

  final AlignmentGeometry3d alignment;
  final Offset3d offset;
  final double widthOffset;
  final bool hasLabel;

  @override
  _BadgePlacement3d createLayout(BuildContext context) => _BadgePlacement3d(
    alignment: alignment,
    textDirection: Directionality.maybeOf(context),
    offset: offset,
    widthOffset: widthOffset,
    hasLabel: hasLabel,
  );

  @override
  void updateLayout(BuildContext context, _BadgePlacement3d layout) {
    layout
      ..alignment = alignment
      ..textDirection = Directionality.maybeOf(context)
      ..offset = offset
      ..widthOffset = widthOffset
      ..hasLabel = hasLabel;
  }
}

/// The box that keeps a labelled badge a stadium: at least [minExtent] tall,
/// and never narrower than it is tall.
///
/// Flutter's `_IntrinsicHorizontalStadium`, which does it with intrinsics.
/// Here it is two layouts of the child when the first comes out taller than
/// it is wide — a single digit at a large type setting — and one otherwise.
/// The label's measurement is cached, so the second is arithmetic.
class _BadgeStadium3d extends SingleChildLayout3d
    with Layout3dChildIntrinsicsMixin {
  _BadgeStadium3d({required double minExtent})
    : _minExtent = minExtent,
      super(name: 'Badge3d stadium');

  double _minExtent;
  set minExtent(double value) {
    if (_minExtent == value) return;
    _minExtent = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(Size3d(_minExtent, _minExtent, 0.0));
      return;
    }
    final floor = constraints
        .copyWith(
          minWidth: math.max(constraints.minWidth, _minExtent),
          minHeight: math.max(constraints.minHeight, _minExtent),
        )
        .normalize();
    child.layout(floor, parentUsesSize: true);
    if (child.size.height > child.size.width) {
      child.layout(
        floor.copyWith(minWidth: child.size.height).normalize(),
        parentUsesSize: true,
      );
    }
    size = child.size;
    child.place(Offset3d.zero);
  }
}

class _SceneBadgeStadium3d extends SingleChildLayout3dWidget {
  const _SceneBadgeStadium3d({required this.minExtent, super.child});

  final double minExtent;

  @override
  _BadgeStadium3d createLayout(BuildContext context) =>
      _BadgeStadium3d(minExtent: minExtent);

  @override
  void updateLayout(BuildContext context, _BadgeStadium3d layout) {
    layout.minExtent = minExtent;
  }
}
