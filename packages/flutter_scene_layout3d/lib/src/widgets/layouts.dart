import 'package:flutter/widgets.dart'
    show
        BuildContext,
        DefaultTextStyle,
        Directionality,
        TextAlign,
        TextDirection,
        TextOverflow,
        TextStyle,
        Widget;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:vector_math/vector_math.dart' show Matrix4;

import '../boxes/container.dart';
import '../boxes/flex.dart';
import '../boxes/ignore_pointer.dart';
import '../boxes/intrinsic.dart';
import '../boxes/node_box.dart';
import '../boxes/shifted.dart';
import '../boxes/sized.dart';
import '../boxes/stack.dart';
import '../boxes/wrap.dart';
import '../geometry/alignment3d.dart';
import '../geometry/constraints3d.dart';
import '../geometry/edge_insets3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../scroll/grid_delegate.dart';
import '../scroll/grid_view.dart';
import '../scroll/list_view.dart';
import '../scroll/scroll_controller.dart';
import '../scroll/viewport.dart';
import '../sliver/custom_scroll_view.dart';
import '../sliver/sliver.dart';
import '../sliver/sliver_grid.dart';
import '../sliver/sliver_list.dart';
import '../text/break_rules.dart';
import '../text/text3d.dart';
import '../text/text_measurement.dart';
import '../text/text_renderer.dart';
import 'framework.dart';

/// Puts engine content into a declarative layout, the widget form of
/// [NodeBox3d].
///
/// The [content] node is app-owned: this widget positions and scales it, and
/// detaches it when the widget goes away, but never disposes it.
class SceneNodeBox3d extends Layout3dWidget {
  /// Creates a box around [content].
  const SceneNodeBox3d({
    super.key,
    required this.content,
    this.fit = BoxFit3d.none,
    this.alignment = Alignment3d.center,
    this.explicitSize,
    this.fallbackSize = Size3d.zero,
  });

  /// The engine content to lay out.
  final Node content;

  /// How the content is scaled into the space available.
  final BoxFit3d fit;

  /// Where the content sits inside the box.
  final Alignment3d alignment;

  /// A size to use instead of measuring the content.
  final Size3d? explicitSize;

  /// The size to use when the content cannot report bounds.
  final Size3d fallbackSize;

  @override
  NodeBox3d createLayout(BuildContext context) => NodeBox3d(
    content: content,
    fit: fit,
    alignment: alignment,
    explicitSize: explicitSize,
    fallbackSize: fallbackSize,
  );

  @override
  void updateLayout(BuildContext context, NodeBox3d layout) {
    layout
      ..content = content
      ..fit = fit
      ..alignment = alignment
      ..explicitSize = explicitSize
      ..fallbackSize = fallbackSize;
  }
}

/// Insets its child, the widget form of [Padding3d].
class ScenePadding3d extends SingleChildLayout3dWidget {
  /// Creates a padded box.
  const ScenePadding3d({
    super.key,
    this.padding = EdgeInsets3d.zero,
    super.child,
  });

  /// The inset on each of the six faces.
  final EdgeInsets3d padding;

  @override
  Padding3d createLayout(BuildContext context) => Padding3d(padding: padding);

  @override
  void updateLayout(BuildContext context, Padding3d layout) {
    layout.padding = padding;
  }
}

/// Aligns its child, the widget form of [Align3d].
class SceneAlign3d extends SingleChildLayout3dWidget {
  /// Creates an aligning box.
  const SceneAlign3d({
    super.key,
    this.alignment = Alignment3d.center,
    this.widthFactor,
    this.heightFactor,
    this.depthFactor,
    super.child,
  });

  /// Where the child sits inside this box.
  final Alignment3d alignment;

  /// If non-null, this box's width is the child's times this factor.
  final double? widthFactor;

  /// If non-null, this box's height is the child's times this factor.
  final double? heightFactor;

  /// If non-null, this box's depth is the child's times this factor.
  final double? depthFactor;

  @override
  Align3d createLayout(BuildContext context) => Align3d(
    alignment: alignment,
    widthFactor: widthFactor,
    heightFactor: heightFactor,
    depthFactor: depthFactor,
  );

  @override
  void updateLayout(BuildContext context, Align3d layout) {
    layout
      ..alignment = alignment
      ..widthFactor = widthFactor
      ..heightFactor = heightFactor
      ..depthFactor = depthFactor;
  }
}

/// Centres its child, the widget form of [Center3d].
class SceneCenter3d extends SceneAlign3d {
  /// Creates a centring box.
  const SceneCenter3d({
    super.key,
    super.widthFactor,
    super.heightFactor,
    super.depthFactor,
    super.child,
  });
}

/// A box with a fixed size, the widget form of [SizedBox3d].
class SceneSizedBox3d extends SingleChildLayout3dWidget {
  /// Creates a box fixed on the axes given.
  const SceneSizedBox3d({
    super.key,
    this.width,
    this.height,
    this.depth,
    super.child,
  });

  /// A cube [extent] on a side.
  const SceneSizedBox3d.cube(double extent, {super.key, super.child})
    : width = extent,
      height = extent,
      depth = extent;

  /// The fixed width, or null to leave the width to the child.
  final double? width;

  /// The fixed height, or null to leave the height to the child.
  final double? height;

  /// The fixed depth, or null to leave the depth to the child.
  final double? depth;

  @override
  SizedBox3d createLayout(BuildContext context) =>
      SizedBox3d(width: width, height: height, depth: depth);

  @override
  void updateLayout(BuildContext context, SizedBox3d layout) {
    layout
      ..width = width
      ..height = height
      ..depth = depth;
  }
}

/// Hides its subtree from hit testing, the widget form of [IgnorePointer3d].
class SceneIgnorePointer3d extends SingleChildLayout3dWidget {
  /// Creates a box that hides [child] from hit tests while [ignoring].
  const SceneIgnorePointer3d({super.key, this.ignoring = true, super.child});

  /// Whether the subtree is out of reach.
  final bool ignoring;

  @override
  IgnorePointer3d createLayout(BuildContext context) =>
      IgnorePointer3d(ignoring: ignoring);

  @override
  void updateLayout(BuildContext context, IgnorePointer3d layout) {
    layout.ignoring = ignoring;
  }
}

/// Takes the hits its subtree would have taken, the widget form of
/// [AbsorbPointer3d].
class SceneAbsorbPointer3d extends SingleChildLayout3dWidget {
  /// Creates a box that answers hits for [child] while [absorbing].
  const SceneAbsorbPointer3d({super.key, this.absorbing = true, super.child});

  /// Whether this box swallows hits meant for its subtree.
  final bool absorbing;

  @override
  AbsorbPointer3d createLayout(BuildContext context) =>
      AbsorbPointer3d(absorbing: absorbing);

  @override
  void updateLayout(BuildContext context, AbsorbPointer3d layout) {
    layout.absorbing = absorbing;
  }
}

/// Imposes extra constraints on its child, the widget form of
/// [ConstrainedBox3d].
class SceneConstrainedBox3d extends SingleChildLayout3dWidget {
  /// Creates a constraining box.
  const SceneConstrainedBox3d({
    super.key,
    required this.constraints,
    super.child,
  });

  /// The constraints added to those the box receives.
  final Constraints3d constraints;

  @override
  ConstrainedBox3d createLayout(BuildContext context) =>
      ConstrainedBox3d(additionalConstraints: constraints);

  @override
  void updateLayout(BuildContext context, ConstrainedBox3d layout) {
    layout.additionalConstraints = constraints;
  }
}

/// Sizes its child to the child's own preferred width, the widget form of
/// [IntrinsicWidth3d].
class SceneIntrinsicWidth3d extends SingleChildLayout3dWidget {
  /// Creates a width-shrinking box.
  const SceneIntrinsicWidth3d({super.key, this.step, super.child});

  /// If non-null, the width is rounded up to a multiple of this.
  final double? step;

  @override
  IntrinsicWidth3d createLayout(BuildContext context) =>
      IntrinsicWidth3d(step: step);

  @override
  void updateLayout(BuildContext context, IntrinsicWidth3d layout) {
    layout.step = step;
  }
}

/// Sizes its child to the child's own preferred height, the widget form of
/// [IntrinsicHeight3d].
class SceneIntrinsicHeight3d extends SingleChildLayout3dWidget {
  /// Creates a height-shrinking box.
  const SceneIntrinsicHeight3d({super.key, this.step, super.child});

  /// If non-null, the height is rounded up to a multiple of this.
  final double? step;

  @override
  IntrinsicHeight3d createLayout(BuildContext context) =>
      IntrinsicHeight3d(step: step);

  @override
  void updateLayout(BuildContext context, IntrinsicHeight3d layout) {
    layout.step = step;
  }
}

/// Sizes its child to the child's own preferred depth, the widget form of
/// [IntrinsicDepth3d].
class SceneIntrinsicDepth3d extends SingleChildLayout3dWidget {
  /// Creates a depth-shrinking box.
  const SceneIntrinsicDepth3d({super.key, this.step, super.child});

  /// If non-null, the depth is rounded up to a multiple of this.
  final double? step;

  @override
  IntrinsicDepth3d createLayout(BuildContext context) =>
      IntrinsicDepth3d(step: step);

  @override
  void updateLayout(BuildContext context, IntrinsicDepth3d layout) {
    layout.step = step;
  }
}

/// Puts its child's baseline at a fixed distance, the widget form of
/// [Baseline3d].
class SceneBaseline3d extends SingleChildLayout3dWidget {
  /// Creates a box that declares where its child's baseline sits.
  const SceneBaseline3d({
    super.key,
    required this.baseline,
    this.axis = Axis3d.vertical,
    super.child,
  });

  /// Where the child's baseline sits, from this box's origin corner.
  final double baseline;

  /// The axis the baseline is measured along.
  final Axis3d axis;

  @override
  Baseline3d createLayout(BuildContext context) =>
      Baseline3d(baseline: baseline, axis: axis);

  @override
  void updateLayout(BuildContext context, Baseline3d layout) {
    layout
      ..baseline = baseline
      ..axis = axis;
  }
}

/// Transforms its child without affecting layout, the widget form of
/// [Transform3d].
class SceneTransform3d extends SingleChildLayout3dWidget {
  /// Creates a transformed box.
  const SceneTransform3d({
    super.key,
    required this.transform,
    this.alignment = Alignment3d.center,
    super.child,
  });

  /// The transform applied to the child, in layout space.
  final Matrix4 transform;

  /// The point in this box the transform pivots around.
  final Alignment3d alignment;

  @override
  Transform3d createLayout(BuildContext context) =>
      Transform3d(transform: transform, alignment: alignment);

  @override
  void updateLayout(BuildContext context, Transform3d layout) {
    layout
      ..transform = transform
      ..alignment = alignment;
  }
}

/// Margin, constraints, padding, and alignment in one box, the widget form of
/// [Container3d].
class SceneContainer3d extends SingleChildLayout3dWidget {
  /// Creates a container.
  const SceneContainer3d({
    super.key,
    this.alignment,
    this.padding = EdgeInsets3d.zero,
    this.margin = EdgeInsets3d.zero,
    this.constraints,
    this.width,
    this.height,
    this.depth,
    this.transform,
    this.transformAlignment = Alignment3d.center,
    super.child,
  });

  /// Where the child sits inside the padded content box.
  final Alignment3d? alignment;

  /// Space between the container's faces and its child.
  final EdgeInsets3d padding;

  /// Space around the container.
  final EdgeInsets3d margin;

  /// Extra constraints imposed on the content.
  final Constraints3d? constraints;

  /// A fixed width.
  final double? width;

  /// A fixed height.
  final double? height;

  /// A fixed depth.
  final double? depth;

  /// A transform applied to the contents, in layout space.
  final Matrix4? transform;

  /// The point [transform] pivots around.
  final Alignment3d transformAlignment;

  @override
  Container3d createLayout(BuildContext context) => Container3d(
    alignment: alignment,
    padding: padding,
    margin: margin,
    constraints: constraints,
    width: width,
    height: height,
    depth: depth,
    transform: transform,
    transformAlignment: transformAlignment,
  );

  @override
  void updateLayout(BuildContext context, Container3d layout) {
    layout
      ..alignment = alignment
      ..padding = padding
      ..margin = margin
      ..additionalConstraints = Container3d.resolveConstraints(
        constraints,
        width,
        height,
        depth,
      )
      ..transform = transform
      ..transformAlignment = transformAlignment;
  }
}

/// Lays children out in a line, the widget form of [Flex3d].
abstract class SceneFlex3d extends Layout3dWidget {
  /// Creates a flex line.
  const SceneFlex3d({
    super.key,
    this.mainAxisAlignment = MainAxisAlignment3d.start,
    this.mainAxisSize = MainAxisSize3d.max,
    this.crossAxisAlignment = CrossAxisAlignment3d.center,
    this.depthAxisAlignment = CrossAxisAlignment3d.center,
    this.spacing = 0.0,
    super.children,
  });

  /// The axis children are laid out along.
  Axis3d get direction;

  /// How leftover main-axis space is distributed.
  final MainAxisAlignment3d mainAxisAlignment;

  /// Whether to fill or shrink-wrap the main axis.
  final MainAxisSize3d mainAxisSize;

  /// How children are positioned on the first cross axis.
  final CrossAxisAlignment3d crossAxisAlignment;

  /// How children are positioned on the second cross axis.
  final CrossAxisAlignment3d depthAxisAlignment;

  /// A fixed gap between adjacent children.
  final double spacing;

  @override
  Flex3d createLayout(BuildContext context) => Flex3d(
    direction: direction,
    mainAxisAlignment: mainAxisAlignment,
    mainAxisSize: mainAxisSize,
    crossAxisAlignment: crossAxisAlignment,
    depthAxisAlignment: depthAxisAlignment,
    spacing: spacing,
  );

  @override
  void updateLayout(BuildContext context, Flex3d layout) {
    layout
      ..direction = direction
      ..mainAxisAlignment = mainAxisAlignment
      ..mainAxisSize = mainAxisSize
      ..crossAxisAlignment = crossAxisAlignment
      ..depthAxisAlignment = depthAxisAlignment
      ..spacing = spacing;
  }
}

/// A line of children running left to right, the widget form of [Row3d].
class SceneRow3d extends SceneFlex3d {
  /// Creates a horizontal line.
  const SceneRow3d({
    super.key,
    super.mainAxisAlignment,
    super.mainAxisSize,
    super.crossAxisAlignment,
    super.depthAxisAlignment,
    super.spacing,
    super.children,
  });

  @override
  Axis3d get direction => Axis3d.horizontal;
}

/// A line of children running top to bottom, the widget form of [Column3d].
class SceneColumn3d extends SceneFlex3d {
  /// Creates a vertical line.
  const SceneColumn3d({
    super.key,
    super.mainAxisAlignment,
    super.mainAxisSize,
    super.crossAxisAlignment,
    super.depthAxisAlignment,
    super.spacing,
    super.children,
  });

  @override
  Axis3d get direction => Axis3d.vertical;
}

/// A line of children running away from the viewer, the widget form of
/// [Depth3d].
class SceneDepth3d extends SceneFlex3d {
  /// Creates a line receding from the viewer.
  const SceneDepth3d({
    super.key,
    super.mainAxisAlignment,
    super.mainAxisSize,
    super.crossAxisAlignment,
    super.depthAxisAlignment,
    super.spacing,
    super.children,
  });

  @override
  Axis3d get direction => Axis3d.depth;
}

/// Gives a child of a [SceneFlex3d] a share of the leftover space, the widget
/// form of [Flexible3d].
class SceneFlexible3d extends SingleChildLayout3dWidget {
  /// Creates a flexible child.
  const SceneFlexible3d({
    super.key,
    this.flex = 1,
    this.fit = FlexFit3d.loose,
    super.child,
  });

  /// This child's share, relative to its siblings.
  final int flex;

  /// Whether the child must fill its share.
  final FlexFit3d fit;

  @override
  Flexible3d createLayout(BuildContext context) =>
      Flexible3d(flex: flex, fit: fit);

  @override
  void updateLayout(BuildContext context, Flexible3d layout) {
    layout
      ..flex = flex
      ..fit = fit;
  }
}

/// A flexible child that must fill its share, the widget form of [Expanded3d].
class SceneExpanded3d extends SceneFlexible3d {
  /// Creates an expanding child.
  const SceneExpanded3d({super.key, super.flex, super.child})
    : super(fit: FlexFit3d.tight);
}

/// Empty flexible space, the widget form of [Spacer3d].
class SceneSpacer3d extends Layout3dWidget {
  /// Creates a flexible gap.
  const SceneSpacer3d({super.key, this.flex = 1});

  /// This gap's share, relative to its siblings.
  final int flex;

  @override
  Spacer3d createLayout(BuildContext context) => Spacer3d(flex: flex);

  @override
  void updateLayout(BuildContext context, Spacer3d layout) {
    layout.flex = flex;
  }
}

/// Overlays its children, the widget form of [Stack3d].
class SceneStack3d extends Layout3dWidget {
  /// Creates a stack.
  const SceneStack3d({
    super.key,
    this.alignment = Alignment3d.topLeftFront,
    this.fit = StackFit3d.loose,
    this.depthStep = 0.0,
    super.children,
  });

  /// Where non-positioned children sit.
  final Alignment3d alignment;

  /// How non-positioned children are sized.
  final StackFit3d fit;

  /// How far toward the viewer each successive child is pulled.
  final double depthStep;

  @override
  Stack3d createLayout(BuildContext context) =>
      Stack3d(alignment: alignment, fit: fit, depthStep: depthStep);

  @override
  void updateLayout(BuildContext context, Stack3d layout) {
    layout
      ..alignment = alignment
      ..fit = fit
      ..depthStep = depthStep;
  }
}

/// Pins a child of a [SceneStack3d] to the stack's faces, the widget form of
/// [Positioned3d].
class ScenePositioned3d extends SingleChildLayout3dWidget {
  /// Creates a positioned child.
  const ScenePositioned3d({
    super.key,
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.front,
    this.back,
    this.width,
    this.height,
    this.depth,
    super.child,
  });

  /// Inset from the stack's left face.
  final double? left;

  /// Inset from the stack's top face.
  final double? top;

  /// Inset from the stack's right face.
  final double? right;

  /// Inset from the stack's bottom face.
  final double? bottom;

  /// Inset from the stack's front face.
  final double? front;

  /// Inset from the stack's back face.
  final double? back;

  /// A fixed width.
  final double? width;

  /// A fixed height.
  final double? height;

  /// A fixed depth.
  final double? depth;

  @override
  Positioned3d createLayout(BuildContext context) => Positioned3d(
    left: left,
    top: top,
    right: right,
    bottom: bottom,
    front: front,
    back: back,
    width: width,
    height: height,
    depth: depth,
  );

  @override
  void updateLayout(BuildContext context, Positioned3d layout) {
    layout
      ..left = left
      ..top = top
      ..right = right
      ..bottom = bottom
      ..front = front
      ..back = back
      ..width = width
      ..height = height
      ..depth = depth;
  }
}

/// A scrolling window onto a taller child, the widget form of [Viewport3d].
class SceneViewport3d extends SingleChildLayout3dWidget {
  /// Creates a scrolling window.
  const SceneViewport3d({
    super.key,
    this.axis = Axis3d.vertical,
    this.controller,
    super.child,
  });

  /// The axis the content scrolls along.
  final Axis3d axis;

  /// The scroll position. One is created and owned when this is null.
  final Scroll3dController? controller;

  @override
  Viewport3d createLayout(BuildContext context) =>
      Viewport3d(axis: axis, controller: controller);

  @override
  void updateLayout(BuildContext context, Viewport3d layout) {
    layout.axis = axis;
    layout.controller = controller;
  }
}

/// A scrollable line of children, the widget form of [ListView3d].
///
/// Takes an explicit list of children, and every one of them is built when the
/// enclosing widget builds. Lazy building lives on the imperative
/// [ListView3d.builder]: building *widgets* on demand needs a
/// `RenderObjectElement` of its own and a build scope to create children
/// during layout, which this layer does not have yet.
class SceneListView3d extends Layout3dWidget {
  /// Creates a scrollable list.
  const SceneListView3d({
    super.key,
    this.scrollDirection = Axis3d.vertical,
    this.controller,
    this.spacing = 0.0,
    this.itemExtent,
    this.crossAxisAlignment = CrossAxisAlignment3d.center,
    this.depthAxisAlignment = CrossAxisAlignment3d.center,
    this.cacheExtent = 0.0,
    super.children,
  });

  /// The axis the list scrolls along.
  final Axis3d scrollDirection;

  /// The scroll position. One is created and owned when this is null.
  final Scroll3dController? controller;

  /// The gap between adjacent items.
  final double spacing;

  /// A fixed extent for every item along the scroll axis.
  final double? itemExtent;

  /// How items are positioned on the first cross axis.
  final CrossAxisAlignment3d crossAxisAlignment;

  /// How items are positioned on the second cross axis.
  final CrossAxisAlignment3d depthAxisAlignment;

  /// How far beyond the window items stay visible.
  final double cacheExtent;

  @override
  ListView3d createLayout(BuildContext context) => ListView3d(
    scrollDirection: scrollDirection,
    controller: controller,
    spacing: spacing,
    itemExtent: itemExtent,
    crossAxisAlignment: crossAxisAlignment,
    depthAxisAlignment: depthAxisAlignment,
    cacheExtent: cacheExtent,
  );

  @override
  void updateLayout(BuildContext context, ListView3d layout) {
    layout
      ..scrollDirection = scrollDirection
      ..spacing = spacing
      ..itemExtent = itemExtent
      ..crossAxisAlignment = crossAxisAlignment
      ..depthAxisAlignment = depthAxisAlignment
      ..cacheExtent = cacheExtent;
    layout.controller = controller;
  }
}

/// Lays children out in runs, the widget form of [Wrap3d].
class SceneWrap3d extends Layout3dWidget {
  /// Creates a wrapping box.
  const SceneWrap3d({
    super.key,
    this.direction = Axis3d.horizontal,
    this.alignment = WrapAlignment3d.start,
    this.spacing = 0.0,
    this.runAlignment = WrapAlignment3d.start,
    this.runSpacing = 0.0,
    this.crossAxisAlignment = WrapCrossAlignment3d.start,
    this.depthAxisAlignment = WrapCrossAlignment3d.center,
    super.children,
  });

  /// The axis a run advances along.
  final Axis3d direction;

  /// How the children of one run are distributed along it.
  final WrapAlignment3d alignment;

  /// The gap between adjacent children in a run.
  final double spacing;

  /// How the runs are distributed across the first cross axis.
  final WrapAlignment3d runAlignment;

  /// The gap between adjacent runs.
  final double runSpacing;

  /// How a child sits across its own run.
  final WrapCrossAlignment3d crossAxisAlignment;

  /// How a child sits on the axis that does not wrap.
  final WrapCrossAlignment3d depthAxisAlignment;

  @override
  Wrap3d createLayout(BuildContext context) => Wrap3d(
    direction: direction,
    alignment: alignment,
    spacing: spacing,
    runAlignment: runAlignment,
    runSpacing: runSpacing,
    crossAxisAlignment: crossAxisAlignment,
    depthAxisAlignment: depthAxisAlignment,
  );

  @override
  void updateLayout(BuildContext context, Wrap3d layout) {
    layout
      ..direction = direction
      ..alignment = alignment
      ..spacing = spacing
      ..runAlignment = runAlignment
      ..runSpacing = runSpacing
      ..crossAxisAlignment = crossAxisAlignment
      ..depthAxisAlignment = depthAxisAlignment;
  }
}

/// A scrollable grid of equal cells, the widget form of [GridView3d].
class SceneGridView3d extends Layout3dWidget {
  /// Creates a grid.
  const SceneGridView3d({
    super.key,
    required this.gridDelegate,
    this.scrollDirection = Axis3d.vertical,
    this.controller,
    this.depthAxisAlignment = CrossAxisAlignment3d.center,
    this.cacheExtent = 0.0,
    super.children,
  });

  /// Decides the cell grid from the room available.
  final Grid3dDelegate gridDelegate;

  /// The axis the grid scrolls along.
  final Axis3d scrollDirection;

  /// The scroll position. One is created and owned when this is null.
  final Scroll3dController? controller;

  /// How a cell's child sits on the depth axis.
  final CrossAxisAlignment3d depthAxisAlignment;

  /// How far beyond the window cells stay alive.
  final double cacheExtent;

  @override
  GridView3d createLayout(BuildContext context) => GridView3d(
    gridDelegate: gridDelegate,
    scrollDirection: scrollDirection,
    controller: controller,
    depthAxisAlignment: depthAxisAlignment,
    cacheExtent: cacheExtent,
  );

  @override
  void updateLayout(BuildContext context, GridView3d layout) {
    layout
      ..gridDelegate = gridDelegate
      ..scrollDirection = scrollDirection
      ..depthAxisAlignment = depthAxisAlignment
      ..cacheExtent = cacheExtent;
    layout.controller = controller;
  }
}

/// A window over a sequence of slivers, the widget form of
/// [CustomScrollView3d].
///
/// The children must be slivers ([SceneSliverList3d], [SceneSliverGrid3d],
/// [SceneSliverToBoxAdapter3d]); ordinary boxes go in an adapter.
class SceneCustomScrollView3d extends Layout3dWidget {
  /// Creates a viewport over slivers.
  const SceneCustomScrollView3d({
    super.key,
    this.scrollDirection = Axis3d.vertical,
    this.controller,
    this.cacheExtent = 0.0,
    List<Widget> slivers = const <Widget>[],
  }) : super(children: slivers);

  /// The axis the viewport scrolls along.
  final Axis3d scrollDirection;

  /// The scroll position shared by every sliver. One is created and owned
  /// when this is null.
  final Scroll3dController? controller;

  /// How far beyond the window slivers stay alive.
  final double cacheExtent;

  @override
  CustomScrollView3d createLayout(BuildContext context) => CustomScrollView3d(
    scrollDirection: scrollDirection,
    controller: controller,
    cacheExtent: cacheExtent,
  );

  @override
  void updateLayout(BuildContext context, CustomScrollView3d layout) {
    layout
      ..scrollDirection = scrollDirection
      ..cacheExtent = cacheExtent;
    layout.controller = controller;
  }
}

/// Puts one box in a sliver world, the widget form of
/// [SliverToBoxAdapter3d].
class SceneSliverToBoxAdapter3d extends SingleChildLayout3dWidget {
  /// Creates an adapter around [child].
  const SceneSliverToBoxAdapter3d({super.key, super.child});

  @override
  SliverToBoxAdapter3d createLayout(BuildContext context) =>
      SliverToBoxAdapter3d();

  @override
  void updateLayout(BuildContext context, SliverToBoxAdapter3d layout) {}
}

/// A run of items in a sliver world, the widget form of [SliverList3d].
class SceneSliverList3d extends Layout3dWidget {
  /// Creates a sliver list.
  const SceneSliverList3d({
    super.key,
    this.spacing = 0.0,
    this.itemExtent,
    this.crossAxisAlignment = CrossAxisAlignment3d.center,
    this.depthAxisAlignment = CrossAxisAlignment3d.center,
    super.children,
  });

  /// The gap between adjacent items.
  final double spacing;

  /// A fixed extent for every item along the scroll axis.
  final double? itemExtent;

  /// How items are positioned on the first cross axis.
  final CrossAxisAlignment3d crossAxisAlignment;

  /// How items are positioned on the second cross axis.
  final CrossAxisAlignment3d depthAxisAlignment;

  @override
  SliverList3d createLayout(BuildContext context) => SliverList3d(
    spacing: spacing,
    itemExtent: itemExtent,
    crossAxisAlignment: crossAxisAlignment,
    depthAxisAlignment: depthAxisAlignment,
  );

  @override
  void updateLayout(BuildContext context, SliverList3d layout) {
    layout
      ..spacing = spacing
      ..itemExtent = itemExtent
      ..crossAxisAlignment = crossAxisAlignment
      ..depthAxisAlignment = depthAxisAlignment;
  }
}

/// A grid of cells in a sliver world, the widget form of [SliverGrid3d].
class SceneSliverGrid3d extends Layout3dWidget {
  /// Creates a sliver grid.
  const SceneSliverGrid3d({
    super.key,
    required this.gridDelegate,
    this.depthAxisAlignment = CrossAxisAlignment3d.center,
    super.children,
  });

  /// Decides the cell grid from the room across the scroll axis.
  final Grid3dDelegate gridDelegate;

  /// How a cell's child sits on the depth axis.
  final CrossAxisAlignment3d depthAxisAlignment;

  @override
  SliverGrid3d createLayout(BuildContext context) => SliverGrid3d(
    gridDelegate: gridDelegate,
    depthAxisAlignment: depthAxisAlignment,
  );

  @override
  void updateLayout(BuildContext context, SliverGrid3d layout) {
    layout
      ..gridDelegate = gridDelegate
      ..depthAxisAlignment = depthAxisAlignment;
  }
}

/// A string laid out as a box, the widget form of [Text3d].
///
/// Unlike the imperative box, this one has a `BuildContext` to ask, so it
/// picks up the ambient [DefaultTextStyle] and [Directionality] the way a
/// Flutter [Text] does — with the caveat that both come from the *widget*
/// tree the scene is hosted in, not from anything in the scene. A style
/// passed here is merged onto the inherited one, so a `SceneText3d` under a
/// `DefaultTextStyle` only has to say what differs.
class SceneText3d extends Layout3dWidget {
  /// Creates a text box over [data].
  const SceneText3d(
    this.data, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.textDirection,
    this.softWrap = true,
    this.overflow = TextOverflow.clip,
    this.maxLines,
    this.depth = 0.0,
    this.rules = TextBreakRules3d.standard,
    this.measurement,
    this.renderer,
  });

  /// The string to lay out.
  final String data;

  /// The style to draw it in, merged onto the inherited [DefaultTextStyle].
  final TextStyle? style;

  /// How lines sit inside the box's width.
  final TextAlign textAlign;

  /// Which way the text runs; the ambient [Directionality] by default.
  final TextDirection? textDirection;

  /// Whether a line may end because it ran out of room.
  final bool softWrap;

  /// What text that does not fit does.
  final TextOverflow overflow;

  /// The most lines the text may take.
  final int? maxLines;

  /// How thick the box is, in world units.
  final double depth;

  /// Where a line is allowed to end.
  final TextBreakRules3d rules;

  /// The measurement policy, or null for the shared segmented one.
  final TextMeasurement3d? measurement;

  /// What turns the layout into geometry, or null to draw nothing.
  final Text3dRenderer? renderer;

  TextStyle _resolveStyle(BuildContext context) {
    final inherited = DefaultTextStyle.of(context).style;
    final style = this.style;
    if (style == null) {
      return inherited.fontSize == null
          ? inherited.merge(Text3d.defaultStyle)
          : inherited;
    }
    return style.inherit ? inherited.merge(style) : style;
  }

  TextDirection _resolveDirection(BuildContext context) =>
      textDirection ?? Directionality.maybeOf(context) ?? TextDirection.ltr;

  @override
  Text3d createLayout(BuildContext context) => Text3d(
    data,
    style: _resolveStyle(context),
    textAlign: textAlign,
    textDirection: _resolveDirection(context),
    softWrap: softWrap,
    overflow: overflow,
    maxLines: maxLines,
    depth: depth,
    rules: rules,
    measurement: measurement,
    renderer: renderer,
  );

  @override
  void updateLayout(BuildContext context, Text3d layout) {
    layout
      ..data = data
      ..style = _resolveStyle(context)
      ..textAlign = textAlign
      ..textDirection = _resolveDirection(context)
      ..softWrap = softWrap
      ..overflow = overflow
      ..maxLines = maxLines
      ..depth = depth
      ..rules = rules
      ..measurement = measurement ?? SegmentedTextMeasurement3d.shared
      ..renderer = renderer;
  }
}
