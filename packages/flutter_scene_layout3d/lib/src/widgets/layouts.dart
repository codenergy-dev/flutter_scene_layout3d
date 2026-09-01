import 'package:flutter/gestures.dart'
    show
        GestureDragCancelCallback,
        GestureDragEndCallback,
        GestureDragStartCallback,
        GestureDragUpdateCallback,
        GestureLongPressCallback,
        GestureTapCallback,
        GestureTapCancelCallback,
        GestureTapDownCallback,
        GestureTapUpCallback;
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        DefaultTextStyle,
        Directionality,
        FocusNode,
        IndexedWidgetBuilder,
        TextAlign,
        TextDirection,
        TextOverflow,
        TextStyle,
        ValueChanged,
        Widget;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:vector_math/vector_math.dart' show Matrix4;

import '../boxes/aspect_ratio.dart';
import '../boxes/container.dart';
import '../boxes/custom_layout.dart';
import '../boxes/fitted.dart';
import '../boxes/flex.dart';
import '../boxes/flow.dart';
import '../boxes/ignore_pointer.dart';
import '../boxes/indexed_stack.dart';
import '../boxes/intrinsic.dart';
import '../boxes/layout_builder.dart';
import '../boxes/node_box.dart';
import '../boxes/overflow.dart';
import '../boxes/shifted.dart';
import '../boxes/sized.dart';
import '../boxes/stack.dart';
import '../boxes/table.dart';
import '../boxes/wrap.dart';
import '../decoration/decorated_box.dart';
import '../decoration/decoration.dart';
import '../geometry/alignment3d.dart';
import '../geometry/constraints3d.dart';
import '../geometry/edge_insets3d.dart';
import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../input/events.dart';
import '../input/focus.dart';
import '../input/gesture_detector.dart';
import '../input/listener.dart';
import '../input/tap_target.dart';
import '../scroll/grid_delegate.dart';
import '../scroll/grid_view.dart';
import '../scroll/list_view.dart';
import '../scroll/page_view.dart';
import '../scroll/scroll_controller.dart';
import '../scroll/scroll_physics.dart';
import '../scroll/viewport.dart';
import '../semantics.dart';
import '../slot.dart';
import '../sliver/custom_scroll_view.dart';
import '../sliver/sliver.dart';
import '../sliver/sliver_grid.dart';
import '../sliver/sliver_list.dart';
import '../sliver/sliver_padding.dart';
import '../text/break_rules.dart';
import '../text/text3d.dart';
import '../text/text_measurement.dart';
import '../text/text_renderer.dart';
import 'default_text_renderer.dart';
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

/// Publishes its subtree to assistive technology, the widget form of
/// [Semantics3d].
///
/// The same [SemanticsProperties] a 2D `Semantics` widget takes, so a control
/// declares its accessibility once and in one vocabulary whether it is drawn
/// with pixels or with geometry.
///
/// ```dart
/// SceneSemantics3d(
///   properties: const SemanticsProperties(
///     label: 'Play',
///     button: true,
///     textDirection: TextDirection.ltr,
///   ),
///   child: SceneGestureDetector3d(onTap: play, child: playButton),
/// )
/// ```
class SceneSemantics3d extends SingleChildLayout3dWidget {
  /// Creates a semantics box over [child].
  const SceneSemantics3d({
    super.key,
    required this.properties,
    this.sortOrder,
    this.enabled = true,
    super.child,
  });

  /// What this box tells the platform its subtree is.
  final SemanticsProperties properties;

  /// Where this box reads in traversal order, or null to follow layout order.
  final double? sortOrder;

  /// Whether the subtree is published at all.
  final bool enabled;

  @override
  Semantics3d createLayout(BuildContext context) => Semantics3d(
    properties: properties,
    sortOrder: sortOrder,
    enabled: enabled,
  );

  @override
  void updateLayout(BuildContext context, Semantics3d layout) {
    layout
      ..properties = properties
      ..sortOrder = sortOrder
      ..enabled = enabled;
  }
}

/// Claims a region of the plane for the pointer, the widget form of
/// [HitTestArea3d].
class SceneHitTestArea3d extends SingleChildLayout3dWidget {
  /// Creates a hit-test region, opaque by default.
  const SceneHitTestArea3d({
    super.key,
    this.behavior = HitTestBehavior3d.opaque,
    super.child,
  });

  /// How the box takes part in a hit test.
  final HitTestBehavior3d behavior;

  @override
  HitTestArea3d createLayout(BuildContext context) =>
      HitTestArea3d(behavior: behavior);

  @override
  void updateLayout(BuildContext context, HitTestArea3d layout) {
    layout.behavior = behavior;
  }
}

/// Guarantees the pointer a minimum area to aim at, the widget form of
/// [TapTarget3d].
class SceneTapTarget3d extends SingleChildLayout3dWidget {
  /// Creates a target at least [minimumSize] across, or 48dp square by
  /// default.
  const SceneTapTarget3d({super.key, this.minimumSize, super.child});

  /// The smallest area the pointer is given, in world units.
  final Size3d? minimumSize;

  @override
  TapTarget3d createLayout(BuildContext context) =>
      TapTarget3d(minimumSize: minimumSize);

  @override
  void updateLayout(BuildContext context, TapTarget3d layout) {
    layout.minimumSize = minimumSize;
  }
}

/// Reports the pointer events inside it, the widget form of [Listener3d].
class SceneListener3d extends SingleChildLayout3dWidget {
  /// Creates a box that reports the pointer events it is handed.
  const SceneListener3d({
    super.key,
    this.onPointerDown,
    this.onPointerMove,
    this.onPointerUp,
    this.onPointerCancel,
    this.onPointerHover,
    this.onPointerEnter,
    this.onPointerExit,
    this.behavior = HitTestBehavior3d.deferToChild,
    super.child,
  });

  /// Called when a pointer comes down on this box.
  final PointerEvent3dCallback? onPointerDown;

  /// Called when a pointer that came down on this box moves.
  final PointerEvent3dCallback? onPointerMove;

  /// Called when a pointer that came down on this box is lifted.
  final PointerEvent3dCallback? onPointerUp;

  /// Called when the press is abandoned without an up.
  final PointerEvent3dCallback? onPointerCancel;

  /// Called when an unpressed pointer moves over this box.
  final PointerEvent3dCallback? onPointerHover;

  /// Called when an unpressed pointer arrives over this box.
  final PointerEvent3dCallback? onPointerEnter;

  /// Called when an unpressed pointer leaves this box.
  final PointerEvent3dCallback? onPointerExit;

  /// How the box takes part in a hit test.
  final HitTestBehavior3d behavior;

  @override
  Listener3d createLayout(BuildContext context) => Listener3d(
    onPointerDown: onPointerDown,
    onPointerMove: onPointerMove,
    onPointerUp: onPointerUp,
    onPointerCancel: onPointerCancel,
    onPointerHover: onPointerHover,
    onPointerEnter: onPointerEnter,
    onPointerExit: onPointerExit,
    behavior: behavior,
  );

  @override
  void updateLayout(BuildContext context, Listener3d layout) {
    layout
      ..onPointerDown = onPointerDown
      ..onPointerMove = onPointerMove
      ..onPointerUp = onPointerUp
      ..onPointerCancel = onPointerCancel
      ..onPointerHover = onPointerHover
      ..onPointerEnter = onPointerEnter
      ..onPointerExit = onPointerExit
      ..behavior = behavior;
  }
}

/// Recognizes gestures on the plane, the widget form of [GestureDetector3d].
class SceneGestureDetector3d extends SingleChildLayout3dWidget {
  /// Creates a gesture detector.
  const SceneGestureDetector3d({
    super.key,
    this.onTapDown,
    this.onTapUp,
    this.onTap,
    this.onTapCancel,
    this.onDoubleTap,
    this.onLongPress,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onPanCancel,
    this.behavior = HitTestBehavior3d.opaque,
    super.child,
  });

  /// Called when a pointer that might turn into a tap comes down.
  final GestureTapDownCallback? onTapDown;

  /// Called when the pointer that will produce a tap is lifted.
  final GestureTapUpCallback? onTapUp;

  /// Called when a tap has happened.
  final GestureTapCallback? onTap;

  /// Called when the press will not become a tap after all.
  final GestureTapCancelCallback? onTapCancel;

  /// Called when the box is tapped twice in quick succession.
  final GestureTapCallback? onDoubleTap;

  /// Called when a long press is recognized.
  final GestureLongPressCallback? onLongPress;

  /// Called when a pan begins.
  final GestureDragStartCallback? onPanStart;

  /// Called as a recognized pan moves.
  final GestureDragUpdateCallback? onPanUpdate;

  /// Called when a recognized pan ends.
  final GestureDragEndCallback? onPanEnd;

  /// Called when a pan is abandoned.
  final GestureDragCancelCallback? onPanCancel;

  /// How the box takes part in a hit test.
  final HitTestBehavior3d behavior;

  @override
  GestureDetector3d createLayout(BuildContext context) => GestureDetector3d(
    onTapDown: onTapDown,
    onTapUp: onTapUp,
    onTap: onTap,
    onTapCancel: onTapCancel,
    onDoubleTap: onDoubleTap,
    onLongPress: onLongPress,
    onPanStart: onPanStart,
    onPanUpdate: onPanUpdate,
    onPanEnd: onPanEnd,
    onPanCancel: onPanCancel,
    behavior: behavior,
  );

  @override
  void updateLayout(BuildContext context, GestureDetector3d layout) {
    layout
      ..onTapDown = onTapDown
      ..onTapUp = onTapUp
      ..onTap = onTap
      ..onTapCancel = onTapCancel
      ..onDoubleTap = onDoubleTap
      ..onLongPress = onLongPress
      ..onPanStart = onPanStart
      ..onPanUpdate = onPanUpdate
      ..onPanEnd = onPanEnd
      ..onPanCancel = onPanCancel
      ..behavior = behavior;
  }
}

/// Ties a [FocusNode] to a box, the widget form of [Focus3d].
///
/// Pass a [focusNode] to drive it from a `Focus` widget above, or leave it
/// null and let the box own one; dropping the node between rebuilds gives the
/// box a fresh one rather than leaving it tied to the old.
class SceneFocus3d extends SingleChildLayout3dWidget {
  /// Creates a focusable box.
  const SceneFocus3d({
    super.key,
    this.focusNode,
    this.onFocusChange,
    this.focusOnPointerDown = true,
    this.autofocus = false,
    this.canRequestFocus = true,
    super.child,
  });

  /// The node holding this box's place in the focus tree, or null for one of
  /// its own.
  final FocusNode? focusNode;

  /// Called when this box gains or loses focus.
  final ValueChanged<bool>? onFocusChange;

  /// Whether a press inside this box focuses it.
  final bool focusOnPointerDown;

  /// Whether this box takes focus as soon as it is in a laid-out tree.
  final bool autofocus;

  /// Whether this box can take focus at all.
  final bool canRequestFocus;

  @override
  Focus3d createLayout(BuildContext context) => Focus3d(
    focusNode: focusNode,
    onFocusChange: onFocusChange,
    focusOnPointerDown: focusOnPointerDown,
    autofocus: autofocus,
    canRequestFocus: canRequestFocus,
  );

  @override
  void updateLayout(BuildContext context, Focus3d layout) {
    layout
      ..focusNode = focusNode
      ..onFocusChange = onFocusChange
      ..focusOnPointerDown = focusOnPointerDown
      ..canRequestFocus = canRequestFocus
      ..autofocus = autofocus;
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

/// Puts a value where every box on the surface can read it, the widget form
/// of [SlotProvider3d].
///
/// The declarative half of the owner's typed slots. Wrap the part of the tree
/// the value belongs to — in practice the whole of it — and any box below
/// reads it inside `performLayout` as `slot(themeSlot)`, with no
/// `BuildContext` and nothing threaded through constructors:
///
/// ```dart
/// SceneLayout3d(
///   size: const Size3d(4, 3, 0.2),
///   child: SceneSlotProvider3d<Theme3dData>(
///     slot: themeSlot,
///     value: Theme3dData.light(),
///     child: screen,
///   ),
/// )
/// ```
///
/// A component library pairs this with an `InheritedWidget` of its own, so
/// the widget layer reads the value through a `BuildContext` and the
/// imperative layer reads it through the owner — one value, written once.
///
/// **The slot is the surface's, not this widget's subtree.** Two providers
/// for the same slot on one surface overwrite each other in attachment
/// order; there is no scoping, because tree-wide state is exactly what the
/// owner is for. Changing [value] relayouts the subtree, because a slot is
/// read during layout and never arrives as a constraint — so nothing on a
/// per-frame path may write one.
///
/// [SceneLayout3d.slots] is the same write, stated on the surface itself, for
/// an application that knows its slots at the root.
class SceneSlotProvider3d<T extends Object> extends SingleChildLayout3dWidget {
  /// Creates a provider writing [value] under [slot].
  const SceneSlotProvider3d({
    super.key,
    required this.slot,
    required this.value,
    super.child,
  });

  /// The slot to write.
  final Layout3dSlot<T> slot;

  /// What the slot holds while this widget is in the tree.
  final T? value;

  @override
  SlotProvider3d<T> createLayout(BuildContext context) =>
      SlotProvider3d<T>(slot: slot, value: value);

  @override
  void updateLayout(BuildContext context, SlotProvider3d<T> layout) {
    assert(
      layout.slotKey == slot,
      'A SceneSlotProvider3d cannot change which slot it writes. Give the '
      'widget a key, or use two providers.',
    );
    layout.value = value;
  }
}

/// A box that makes itself visible, the widget form of [DecoratedBox3d].
///
/// The declarative layer's one way of drawing something. Everything else here
/// arranges; this widget hands its box's own size to a
/// [Decoration3dPainter], which puts a mesh under the box's node and keeps it
/// the right size.
///
/// ```dart
/// SceneDecoratedBox3d(
///   decoration: const BoxDecoration3d(
///     color: Color(0xFF1B6EF3),
///     borderRadius: BorderRadius3d.circular(12),
///     elevation: 3,
///   ),
///   stateLayer: hovered
///       ? const StateLayer3d(color: Color(0xFFFFFFFF), opacity: 0.08)
///       : StateLayer3d.none,
///   child: const ScenePadding3d(
///     padding: EdgeInsets3d.all(0.12),
///     child: SceneText3d('Continue'),
///   ),
/// )
/// ```
///
/// **Every figure on the decoration is in logical pixels** — a 12dp corner, a
/// 3dp elevation — which the metrics turn into world units at paint time.
/// `circular(0.6)` is six thousandths of a unit and looks square.
///
/// **Neither property touches layout, and that is the point of the class.**
/// A rebuild that changes only [stateLayer] writes one shader uniform and
/// asks for a frame; a rebuild that changes only [decoration] writes
/// parameters and, when the elevation moved, one matrix. Nothing is marked
/// dirty for layout either way, so a pointer crossing a screen of controls
/// costs no layout at all. That is what makes the hover of a catalogue
/// affordable, and `test/widgets_decoration_test.dart` states it.
///
/// **It draws nothing until an application installs a painter.**
/// [BoxDecoration3d.painterFactory] is null by default, because building
/// geometry needs a GPU context that `flutter test` does not have. See the
/// package README under *Making a box visible*.
class SceneDecoratedBox3d extends SingleChildLayout3dWidget {
  /// Creates a decorated box.
  const SceneDecoratedBox3d({
    super.key,
    required this.decoration,
    this.stateLayer = StateLayer3d.none,
    super.child,
  });

  /// What this box looks like.
  final Decoration3d decoration;

  /// The hover, focus, press or drag overlay in force.
  final StateLayer3d stateLayer;

  @override
  DecoratedBox3d createLayout(BuildContext context) =>
      DecoratedBox3d(decoration: decoration, stateLayer: stateLayer);

  @override
  void updateLayout(BuildContext context, DecoratedBox3d layout) {
    layout
      ..decoration = decoration
      ..stateLayer = stateLayer;
  }
}

/// Margin, constraints, padding, and alignment in one box, the widget form of
/// [Container3d].
///
/// Unlike Flutter's `Container` it has no `decoration`, for the reason
/// [Container3d]'s own doc gives: wrap it in a [SceneDecoratedBox3d], which
/// makes the order of margin and panel explicit instead of implied.
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
/// Two shapes, the same two Flutter's `ListView` has. Given [children], every
/// one of them is built when the enclosing widget builds and laid out whether
/// it is in the window or not. Given an [itemBuilder] and an `itemCount`, an
/// item is built when the window reaches it and released when the window and
/// its cache have left it again, so a list of ten thousand rows costs the
/// dozen that are visible.
///
/// A built item is a widget like any other: it reads inherited state, keeps
/// its own [State], and rebuilds on its own. It is not kept alive, though —
/// scrolling far enough disposes it, and its [State] goes with it, so put
/// anything that has to survive that outside the list.
///
/// ```dart
/// SceneListView3d.builder(
///   itemCount: rows.length,
///   itemExtent: 0.6,
///   itemBuilder: (context, index) => SceneContainer3d(
///     padding: const EdgeInsets3d.all(0.05),
///     child: SceneText3d(rows[index].label),
///   ),
/// )
/// ```
///
/// An [itemExtent] is worth giving when the items are uniform: the offsets
/// become arithmetic, so nothing outside the window is ever built, where a
/// list that has to measure builds forward from the first item to reach a
/// deep scroll offset. The imperative [ListView3d.builder] takes a
/// `prototypeItem` for the same reason; there is no widget form of that,
/// because a prototype is measured rather than mounted and a widget cannot be
/// laid out without being in the tree.
class SceneListView3d extends LazyLayout3dWidget {
  /// Creates a scrollable list over an explicit set of children.
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

  /// Creates a scrollable list that builds its items as it reaches them.
  const SceneListView3d.builder({
    super.key,
    required int itemCount,
    required IndexedWidgetBuilder itemBuilder,
    this.scrollDirection = Axis3d.vertical,
    this.controller,
    this.spacing = 0.0,
    this.itemExtent,
    this.crossAxisAlignment = CrossAxisAlignment3d.center,
    this.depthAxisAlignment = CrossAxisAlignment3d.center,
    this.cacheExtent = 0.0,
  }) : super(itemCount: itemCount, itemBuilder: itemBuilder);

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
///
/// The same two shapes [SceneListView3d] has: an explicit list of children,
/// or an [itemBuilder] and a count. A grid knows where every cell goes by
/// arithmetic, so a built grid is exactly lazy — only the cells the window
/// covers are ever built, however deep the scroll offset is.
class SceneGridView3d extends LazyLayout3dWidget {
  /// Creates a grid over an explicit set of children.
  const SceneGridView3d({
    super.key,
    required this.gridDelegate,
    this.scrollDirection = Axis3d.vertical,
    this.controller,
    this.depthAxisAlignment = CrossAxisAlignment3d.center,
    this.cacheExtent = 0.0,
    super.children,
  });

  /// Creates a grid that builds its cells as it reaches them.
  const SceneGridView3d.builder({
    super.key,
    required this.gridDelegate,
    required int itemCount,
    required IndexedWidgetBuilder itemBuilder,
    this.scrollDirection = Axis3d.vertical,
    this.controller,
    this.depthAxisAlignment = CrossAxisAlignment3d.center,
    this.cacheExtent = 0.0,
  }) : super(itemCount: itemCount, itemBuilder: itemBuilder);

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
///
/// The same two shapes [SceneListView3d] has, and the same caveats: a built
/// item is an ordinary widget, it is not kept alive once the window and its
/// cache have left it, and an [itemExtent] is what stops a long list from
/// measuring its way to a deep offset.
class SceneSliverList3d extends LazyLayout3dWidget {
  /// Creates a sliver list over an explicit set of children.
  const SceneSliverList3d({
    super.key,
    this.spacing = 0.0,
    this.itemExtent,
    this.crossAxisAlignment = CrossAxisAlignment3d.center,
    this.depthAxisAlignment = CrossAxisAlignment3d.center,
    super.children,
  });

  /// Creates a sliver list that builds its items as it reaches them.
  const SceneSliverList3d.builder({
    super.key,
    required int itemCount,
    required IndexedWidgetBuilder itemBuilder,
    this.spacing = 0.0,
    this.itemExtent,
    this.crossAxisAlignment = CrossAxisAlignment3d.center,
    this.depthAxisAlignment = CrossAxisAlignment3d.center,
  }) : super(itemCount: itemCount, itemBuilder: itemBuilder);

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
///
/// The same two shapes [SceneGridView3d] has, and lazy in the same exact way:
/// cell offsets are arithmetic, so only what the window covers is built.
class SceneSliverGrid3d extends LazyLayout3dWidget {
  /// Creates a sliver grid over an explicit set of children.
  const SceneSliverGrid3d({
    super.key,
    required this.gridDelegate,
    this.depthAxisAlignment = CrossAxisAlignment3d.center,
    super.children,
  });

  /// Creates a sliver grid that builds its cells as it reaches them.
  const SceneSliverGrid3d.builder({
    super.key,
    required this.gridDelegate,
    required int itemCount,
    required IndexedWidgetBuilder itemBuilder,
    this.depthAxisAlignment = CrossAxisAlignment3d.center,
  }) : super(itemCount: itemCount, itemBuilder: itemBuilder);

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

  /// What turns the layout into geometry.
  ///
  /// Null takes the ambient [DefaultTextRenderer3d]'s factory, and draws
  /// nothing when there is none. A renderer given here is owned by this
  /// label's box, so do not hand the same instance to two of them; install a
  /// [DefaultTextRenderer3d] instead, which gives each label one of its own.
  final Text3dRenderer? renderer;

  /// Writes whichever of the two renderer sources applies onto [layout].
  ///
  /// An explicit renderer wins. Otherwise the inherited factory is written,
  /// including when it is null — which is what makes a label stop drawing
  /// when its default is taken away. Writing the same factory again is a
  /// no-op inside [Text3d], so a rebuild does not churn renderers.
  void _applyRenderer(BuildContext context, Text3d layout) {
    final renderer = this.renderer;
    if (renderer != null) {
      layout.renderer = renderer;
      return;
    }
    layout.rendererFactory = DefaultTextRenderer3d.maybeOf(context);
  }

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
    rendererFactory: renderer == null
        ? DefaultTextRenderer3d.maybeOf(context)
        : null,
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
      ..measurement = measurement ?? SegmentedTextMeasurement3d.shared;
    _applyRenderer(context, layout);
  }
}

/// Caps an unbounded axis, the widget form of [LimitedBox3d].
class SceneLimitedBox3d extends SingleChildLayout3dWidget {
  /// Creates a box that limits its child's unbounded axes.
  const SceneLimitedBox3d({
    super.key,
    this.maxWidth = double.infinity,
    this.maxHeight = double.infinity,
    this.maxDepth = double.infinity,
    super.child,
  });

  /// The width to use when the incoming width is unbounded.
  final double maxWidth;

  /// The height to use when the incoming height is unbounded.
  final double maxHeight;

  /// The depth to use when the incoming depth is unbounded.
  final double maxDepth;

  @override
  LimitedBox3d createLayout(BuildContext context) => LimitedBox3d(
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    maxDepth: maxDepth,
  );

  @override
  void updateLayout(BuildContext context, LimitedBox3d layout) {
    layout
      ..maxWidth = maxWidth
      ..maxHeight = maxHeight
      ..maxDepth = maxDepth;
  }
}

/// Frees its child's constraints, the widget form of [UnconstrainedBox3d].
class SceneUnconstrainedBox3d extends SingleChildLayout3dWidget {
  /// Creates a box that hands its child unbounded room.
  const SceneUnconstrainedBox3d({
    super.key,
    this.alignment = Alignment3d.center,
    this.constrainedAxes = const <Axis3d>{},
    super.child,
  });

  /// Where the child sits inside the room this box was given.
  final Alignment3d alignment;

  /// The axes that keep the constraints this box was given.
  final Set<Axis3d> constrainedAxes;

  @override
  UnconstrainedBox3d createLayout(BuildContext context) => UnconstrainedBox3d(
    alignment: alignment,
    constrainedAxes: constrainedAxes,
  );

  @override
  void updateLayout(BuildContext context, UnconstrainedBox3d layout) {
    layout
      ..alignment = alignment
      ..constrainedAxes = constrainedAxes;
  }
}

/// Lets its child spill out of the size it reports, the widget form of
/// [OverflowBox3d].
class SceneOverflowBox3d extends SingleChildLayout3dWidget {
  /// Creates a box that overrides the bounds given, per axis.
  const SceneOverflowBox3d({
    super.key,
    this.minWidth,
    this.maxWidth,
    this.minHeight,
    this.maxHeight,
    this.minDepth,
    this.maxDepth,
    this.alignment = Alignment3d.center,
    super.child,
  });

  /// The minimum width handed down, or null to keep the incoming one.
  final double? minWidth;

  /// The maximum width handed down, or null to keep the incoming one.
  final double? maxWidth;

  /// The minimum height handed down, or null to keep the incoming one.
  final double? minHeight;

  /// The maximum height handed down, or null to keep the incoming one.
  final double? maxHeight;

  /// The minimum depth handed down, or null to keep the incoming one.
  final double? minDepth;

  /// The maximum depth handed down, or null to keep the incoming one.
  final double? maxDepth;

  /// Where the child sits inside the room this box reports.
  final Alignment3d alignment;

  @override
  OverflowBox3d createLayout(BuildContext context) => OverflowBox3d(
    minWidth: minWidth,
    maxWidth: maxWidth,
    minHeight: minHeight,
    maxHeight: maxHeight,
    minDepth: minDepth,
    maxDepth: maxDepth,
    alignment: alignment,
  );

  @override
  void updateLayout(BuildContext context, OverflowBox3d layout) {
    layout
      ..minWidth = minWidth
      ..maxWidth = maxWidth
      ..minHeight = minHeight
      ..maxHeight = maxHeight
      ..minDepth = minDepth
      ..maxDepth = maxDepth
      ..alignment = alignment;
  }
}

/// Sizes its child to a fraction of the room available, the widget form of
/// [FractionallySizedBox3d].
class SceneFractionallySizedBox3d extends SingleChildLayout3dWidget {
  /// Creates a box sizing its child to a fraction of its own room.
  const SceneFractionallySizedBox3d({
    super.key,
    this.widthFactor,
    this.heightFactor,
    this.depthFactor,
    this.alignment = Alignment3d.center,
    super.child,
  });

  /// The fraction of the available width the child is given.
  final double? widthFactor;

  /// The fraction of the available height the child is given.
  final double? heightFactor;

  /// The fraction of the available depth the child is given.
  final double? depthFactor;

  /// Where the child sits inside this box.
  final Alignment3d alignment;

  @override
  FractionallySizedBox3d createLayout(BuildContext context) =>
      FractionallySizedBox3d(
        widthFactor: widthFactor,
        heightFactor: heightFactor,
        depthFactor: depthFactor,
        alignment: alignment,
      );

  @override
  void updateLayout(BuildContext context, FractionallySizedBox3d layout) {
    layout
      ..widthFactor = widthFactor
      ..heightFactor = heightFactor
      ..depthFactor = depthFactor
      ..alignment = alignment;
  }
}

/// Shows one of its children, the widget form of [IndexedStack3d].
///
/// Every child keeps its state and its place while it is hidden, so this is
/// how a tab body or a wizard step is built.
class SceneIndexedStack3d extends Layout3dWidget {
  /// Creates a stack showing the child at [index].
  const SceneIndexedStack3d({
    super.key,
    this.index = 0,
    this.alignment = Alignment3d.topLeftFront,
    this.fit = StackFit3d.loose,
    this.depthStep = 0.0,
    super.children,
  });

  /// Which child is shown, or null for none.
  final int? index;

  /// Where the children sit inside the stack.
  final Alignment3d alignment;

  /// How the children are sized.
  final StackFit3d fit;

  /// How far toward the viewer each successive child's geometry is pulled.
  final double depthStep;

  @override
  IndexedStack3d createLayout(BuildContext context) => IndexedStack3d(
    index: index,
    alignment: alignment,
    fit: fit,
    depthStep: depthStep,
  );

  @override
  void updateLayout(BuildContext context, IndexedStack3d layout) {
    layout
      ..alignment = alignment
      ..fit = fit
      ..depthStep = depthStep
      ..index = index;
  }
}

/// Holds two of its axes in a fixed ratio, the widget form of [AspectRatio3d].
class SceneAspectRatio3d extends SingleChildLayout3dWidget {
  /// Creates a box with a fixed ratio between [axis] and [relativeTo].
  const SceneAspectRatio3d({
    super.key,
    required this.aspectRatio,
    this.axis = Axis3d.horizontal,
    this.relativeTo = Axis3d.vertical,
    super.child,
  });

  /// The extent along [axis] divided by the extent along [relativeTo].
  final double aspectRatio;

  /// The numerator of the ratio.
  final Axis3d axis;

  /// The denominator of the ratio.
  final Axis3d relativeTo;

  @override
  AspectRatio3d createLayout(BuildContext context) => AspectRatio3d(
    aspectRatio: aspectRatio,
    axis: axis,
    relativeTo: relativeTo,
  );

  @override
  void updateLayout(BuildContext context, AspectRatio3d layout) {
    layout
      ..aspectRatio = aspectRatio
      ..axis = axis
      ..relativeTo = relativeTo;
  }
}

/// Scales its child into the room available, the widget form of
/// [FittedBox3d].
class SceneFittedBox3d extends SingleChildLayout3dWidget {
  /// Creates a box that scales its child.
  const SceneFittedBox3d({
    super.key,
    this.fit = BoxFit3d.contain,
    this.alignment = Alignment3d.center,
    super.child,
  });

  /// How the child is scaled into the room available.
  final BoxFit3d fit;

  /// Where the scaled child sits inside this box.
  final Alignment3d alignment;

  @override
  FittedBox3d createLayout(BuildContext context) =>
      FittedBox3d(fit: fit, alignment: alignment);

  @override
  void updateLayout(BuildContext context, FittedBox3d layout) {
    layout
      ..fit = fit
      ..alignment = alignment;
  }
}

/// A grid of cells whose columns are negotiated across every row, the widget
/// form of [Table3d].
class SceneTable3d extends Layout3dWidget {
  /// Creates a table of [columnCount] columns from cells in row-major order.
  const SceneTable3d({
    super.key,
    required this.columnCount,
    this.columnWidths = const <int, TableColumnWidth3d>{},
    this.defaultColumnWidth = const FlexColumnWidth3d(),
    this.defaultVerticalAlignment = TableCellAlignment3d.top,
    this.depthAxisAlignment = CrossAxisAlignment3d.center,
    this.columnSpacing = 0.0,
    this.rowSpacing = 0.0,
    super.children,
  });

  /// How many cells make a row.
  final int columnCount;

  /// The width policy of individual columns, by index.
  final Map<int, TableColumnWidth3d> columnWidths;

  /// The width policy of every other column.
  final TableColumnWidth3d defaultColumnWidth;

  /// Where a cell sits in its row.
  final TableCellAlignment3d defaultVerticalAlignment;

  /// Where a cell sits in the table's depth.
  final CrossAxisAlignment3d depthAxisAlignment;

  /// The gap between adjacent columns.
  final double columnSpacing;

  /// The gap between adjacent rows.
  final double rowSpacing;

  @override
  Table3d createLayout(BuildContext context) => Table3d(
    columnCount: columnCount,
    columnWidths: columnWidths,
    defaultColumnWidth: defaultColumnWidth,
    defaultVerticalAlignment: defaultVerticalAlignment,
    depthAxisAlignment: depthAxisAlignment,
    columnSpacing: columnSpacing,
    rowSpacing: rowSpacing,
  );

  @override
  void updateLayout(BuildContext context, Table3d layout) {
    layout
      ..columnCount = columnCount
      ..columnWidths = columnWidths
      ..defaultColumnWidth = defaultColumnWidth
      ..defaultVerticalAlignment = defaultVerticalAlignment
      ..depthAxisAlignment = depthAxisAlignment
      ..columnSpacing = columnSpacing
      ..rowSpacing = rowSpacing;
  }
}

/// Tags a child of a [SceneCustomMultiChildLayout3d], the widget form of
/// [LayoutId3d].
class SceneLayoutId3d extends SingleChildLayout3dWidget {
  /// Tags [child] with [id].
  const SceneLayoutId3d({super.key, required this.id, super.child});

  /// The name the delegate knows this child by.
  final Object id;

  @override
  LayoutId3d createLayout(BuildContext context) => LayoutId3d(id: id);

  @override
  void updateLayout(BuildContext context, LayoutId3d layout) {
    layout.id = id;
  }
}

/// Arranges children a delegate knows by name, the widget form of
/// [CustomMultiChildLayout3d].
///
/// Every child is a [SceneLayoutId3d].
class SceneCustomMultiChildLayout3d extends Layout3dWidget {
  /// Creates a box arranged by [delegate].
  const SceneCustomMultiChildLayout3d({
    super.key,
    required this.delegate,
    super.children,
  });

  /// The delegate deciding the arrangement.
  final MultiChildLayout3dDelegate delegate;

  @override
  CustomMultiChildLayout3d createLayout(BuildContext context) =>
      CustomMultiChildLayout3d(delegate: delegate);

  @override
  void updateLayout(BuildContext context, CustomMultiChildLayout3d layout) {
    layout.delegate = delegate;
  }
}

/// Arranges its children by moving their geometry, the widget form of
/// [Flow3d].
class SceneFlow3d extends Layout3dWidget {
  /// Creates a flow arranged by [delegate].
  const SceneFlow3d({super.key, required this.delegate, super.children});

  /// The delegate deciding where the children go.
  final Flow3dDelegate delegate;

  @override
  Flow3d createLayout(BuildContext context) => Flow3d(delegate: delegate);

  @override
  void updateLayout(BuildContext context, Flow3d layout) {
    layout.delegate = delegate;
  }
}

/// Insets a sliver, the widget form of [SliverPadding3d].
class SceneSliverPadding3d extends SingleChildLayout3dWidget {
  /// Creates a sliver that insets [sliver].
  const SceneSliverPadding3d({
    super.key,
    this.padding = EdgeInsets3d.zero,
    Widget? sliver,
  }) : super(child: sliver);

  /// The inset on each of the six faces.
  final EdgeInsets3d padding;

  @override
  SliverPadding3d createLayout(BuildContext context) =>
      SliverPadding3d(padding: padding);

  @override
  void updateLayout(BuildContext context, SliverPadding3d layout) {
    layout.padding = padding;
  }
}

/// Builds a subtree from the constraints a [SceneLayoutBuilder3d] was given,
/// the 3D analogue of [LayoutWidgetBuilder].
typedef Layout3dWidgetBuilder =
    Widget Function(BuildContext context, Constraints3d constraints);

/// Builds its child from the constraints it is given, the widget form of
/// [LayoutBuilder3d].
///
/// The one widget here that runs its builder during layout, which is what
/// lets a component change *shape* with the room it is given:
///
/// ```dart
/// SceneLayoutBuilder3d(
///   builder: (context, constraints) => constraints.maxWidth > 6
///       ? SceneRow3d(children: [rail, body])
///       : SceneColumn3d(children: [body, bar]),
/// )
/// ```
///
/// The builder is called on the first layout and again whenever the
/// constraints change; a rebuild reconciles onto the element already there,
/// so state below survives a resize. It must not have side effects on the
/// tree above it — no `setState` on an ancestor from inside it — because the
/// pass it runs in has already been past that point. See [LayoutBuilder3d].
class SceneLayoutBuilder3d extends LazyLayout3dWidget {
  /// Creates a box that builds its child from its constraints.
  const SceneLayoutBuilder3d({super.key, required this.builder})
    : super(itemCount: 1);

  /// Builds the child from the constraints this box was given.
  final Layout3dWidgetBuilder builder;

  /// Always: the child is built during layout, through the element that is
  /// this widget's child manager, however the child is described.
  @override
  bool get isLazy => true;

  /// Never in the build phase. The constraints are only true inside the pass,
  /// so a rebuild here asks the layout to build and waits for it.
  @override
  bool get rebuildsItemsOnBuild => false;

  @override
  Widget? buildChild(BuildContext context, int index, LayoutBuilder3d layout) =>
      index == 0 ? builder(context, layout.constraints) : null;

  @override
  LayoutBuilder3d createLayout(BuildContext context) => LayoutBuilder3d();

  @override
  void updateLayout(BuildContext context, LayoutBuilder3d layout) {
    // A new closure may build anything, so the child is rebuilt — in the next
    // pass, where the constraints it is built from are the ones in force.
    layout.markNeedsBuild();
  }
}

/// A scrolling view whose children are each as big as the window, the widget
/// form of [PageView3d].
///
/// The same two shapes [SceneListView3d] has. The position snaps to a page
/// boundary unless a [controller] of your own says otherwise; see
/// [PageScroll3dPhysics].
class ScenePageView3d extends LazyLayout3dWidget {
  /// Creates a page view over an explicit set of pages.
  const ScenePageView3d({
    super.key,
    this.scrollDirection = Axis3d.horizontal,
    this.controller,
    this.crossAxisAlignment = CrossAxisAlignment3d.stretch,
    this.depthAxisAlignment = CrossAxisAlignment3d.center,
    super.children,
  });

  /// Creates a page view that builds its pages as it reaches them.
  const ScenePageView3d.builder({
    super.key,
    required int itemCount,
    required IndexedWidgetBuilder itemBuilder,
    this.scrollDirection = Axis3d.horizontal,
    this.controller,
    this.crossAxisAlignment = CrossAxisAlignment3d.stretch,
    this.depthAxisAlignment = CrossAxisAlignment3d.center,
  }) : super(itemCount: itemCount, itemBuilder: itemBuilder);

  /// The axis the pages are laid out along.
  final Axis3d scrollDirection;

  /// The scroll position. One is created and owned, with page physics, when
  /// this is null.
  final Scroll3dController? controller;

  /// How pages are positioned on the first cross axis.
  final CrossAxisAlignment3d crossAxisAlignment;

  /// How pages are positioned on the second cross axis.
  final CrossAxisAlignment3d depthAxisAlignment;

  @override
  PageView3d createLayout(BuildContext context) => PageView3d(
    scrollDirection: scrollDirection,
    controller: controller,
    crossAxisAlignment: crossAxisAlignment,
    depthAxisAlignment: depthAxisAlignment,
  );

  @override
  void updateLayout(BuildContext context, PageView3d layout) {
    layout
      ..scrollDirection = scrollDirection
      ..crossAxisAlignment = crossAxisAlignment
      ..depthAxisAlignment = depthAxisAlignment;
    layout.controller = controller;
  }
}
