import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:flutter/foundation.dart' show ValueChanged, VoidCallback;
import 'package:flutter/scheduler.dart' show TickerProvider;
import 'package:flutter/widgets.dart' show BuildContext, Widget;

import '../geometry/offset3d.dart';
import '../input/dismissible.dart';
import '../input/drag.dart';
import '../input/draggable.dart';
import '../input/events.dart';
import '../overlay/overlay.dart';
import 'framework.dart';

/// A box whose contents can be picked up, the widget form of [Draggable3d].
///
/// ```dart
/// SceneDraggable3d<Photo>(
///   data: photo,
///   startMode: const Drag3dStartMode.longPress(),
///   feedbackBuilder: (_) => Container3d(
///     size: const Size3d(0.6, 0.4, 0.02),
///     decoration: cardDecoration,
///   ),
///   child: SceneDecoratedBox3d(decoration: thumbnail, child: label),
/// )
/// ```
///
/// The feedback is built by a [Drag3dFeedbackBuilder] rather than by a
/// `Widget`, because it is inserted into an [Overlay3d] by the layout tier
/// while a drag is being recognized — outside any build phase. It is the same
/// arrangement [SceneOverlay3d] uses for its entries, and for the same
/// reason.
class SceneDraggable3d<T extends Object> extends SingleChildLayout3dWidget {
  /// Creates a draggable box carrying [data].
  const SceneDraggable3d({
    super.key,
    this.data,
    this.feedbackBuilder,
    this.startMode = const Drag3dStartMode.immediate(),
    this.axis,
    this.anchor = Drag3dAnchor.originPlane,
    this.overlay,
    this.feedbackLayer = const OverlayLayer3d.inPlane(),
    this.dropDuration = const Duration(milliseconds: 200),
    this.dropCurve = Curves.easeOutCubic,
    this.vsync,
    this.onDragStarted,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCompleted,
    this.onDraggableCanceled,
    this.behavior = HitTestBehavior3d.opaque,
    super.child,
  });

  /// What this box carries.
  final T? data;

  /// Builds what is carried under the pointer.
  final Drag3dFeedbackBuilder? feedbackBuilder;

  /// When a press here becomes a drag.
  final Drag3dStartMode startMode;

  /// The axis travel is measured on, or null for travel in any direction.
  final Axis3d? axis;

  /// Which plane the feedback is carried on.
  final Drag3dAnchor anchor;

  /// The overlay the feedback goes into, or null for the nearest one above.
  final Overlay3d? overlay;

  /// Which layer of the overlay the feedback goes on.
  final OverlayLayer3d feedbackLayer;

  /// How long the feedback takes to settle when the drag ends.
  final Duration dropDuration;

  /// The curve the drop animation follows.
  final Curve dropCurve;

  /// The ticker provider for the drop animation, or null for a bare `Ticker`.
  final TickerProvider? vsync;

  /// Called when a drag begins here.
  final VoidCallback? onDragStarted;

  /// Called as the drag moves, with how far it has travelled from the press.
  final ValueChanged<Offset3d>? onDragUpdate;

  /// Called when the drag ends, with the session that ended.
  final ValueChanged<Drag3dSession>? onDragEnd;

  /// Called when a target took the payload.
  final VoidCallback? onDragCompleted;

  /// Called when the drag ended over nothing, with where it ended.
  final ValueChanged<Offset3d>? onDraggableCanceled;

  /// How the box takes part in a hit test.
  final HitTestBehavior3d behavior;

  @override
  Draggable3d<T> createLayout(BuildContext context) => Draggable3d<T>(
    data: data,
    feedbackBuilder: feedbackBuilder,
    startMode: startMode,
    axis: axis,
    anchor: anchor,
    overlay: overlay,
    feedbackLayer: feedbackLayer,
    dropDuration: dropDuration,
    dropCurve: dropCurve,
    vsync: vsync,
    onDragStarted: onDragStarted,
    onDragUpdate: onDragUpdate,
    onDragEnd: onDragEnd,
    onDragCompleted: onDragCompleted,
    onDraggableCanceled: onDraggableCanceled,
    behavior: behavior,
  );

  @override
  void updateLayout(BuildContext context, Draggable3d<T> layout) {
    layout
      ..data = data
      ..feedbackBuilder = feedbackBuilder
      ..startMode = startMode
      ..axis = axis
      ..anchor = anchor
      ..overlay = overlay
      ..feedbackLayer = feedbackLayer
      ..dropDuration = dropDuration
      ..dropCurve = dropCurve
      ..vsync = vsync
      ..onDragStarted = onDragStarted
      ..onDragUpdate = onDragUpdate
      ..onDragEnd = onDragEnd
      ..onDragCompleted = onDragCompleted
      ..onDraggableCanceled = onDraggableCanceled
      ..behavior = behavior;
  }
}

/// A box that catches a payload, the widget form of [DragTarget3d].
///
/// ```dart
/// SceneDragTarget3d<Photo>(
///   onWillAccept: (photo, _) => photo.album != album,
///   onAccept: (photo, _) => setState(() => album.add(photo)),
///   child: dropZone,
/// )
/// ```
///
/// The callbacks are the layout's, not the widget's: a highlight driven from
/// [onEnter] and [onLeave] should write a decoration or a state layer rather
/// than call `setState`, because a rebuild during a drag is exactly what the
/// node tier exists to avoid.
class SceneDragTarget3d<T extends Object> extends SingleChildLayout3dWidget {
  /// Creates a drop target for payloads of type [T].
  const SceneDragTarget3d({
    super.key,
    this.onWillAccept,
    this.onEnter,
    this.onMove,
    this.onLeave,
    this.onAccept,
    this.behavior = HitTestBehavior3d.translucent,
    super.child,
  });

  /// Whether this target wants a particular payload, beyond its type.
  final Drag3dWillAccept<T>? onWillAccept;

  /// Called when an acceptable drag arrives over this target.
  final Drag3dTargetCallback<T>? onEnter;

  /// Called as an acceptable drag moves over this target.
  final Drag3dTargetCallback<T>? onMove;

  /// Called when an acceptable drag leaves without dropping here.
  final Drag3dTargetCallback<T>? onLeave;

  /// Called when a payload is dropped here.
  final Drag3dTargetCallback<T>? onAccept;

  /// How the box takes part in a hit test.
  final HitTestBehavior3d behavior;

  @override
  DragTarget3d<T> createLayout(BuildContext context) => DragTarget3d<T>(
    onWillAccept: onWillAccept,
    onEnter: onEnter,
    onMove: onMove,
    onLeave: onLeave,
    onAccept: onAccept,
    behavior: behavior,
  );

  @override
  void updateLayout(BuildContext context, DragTarget3d<T> layout) {
    layout
      ..onWillAccept = onWillAccept
      ..onEnter = onEnter
      ..onMove = onMove
      ..onLeave = onLeave
      ..onAccept = onAccept
      ..behavior = behavior;
  }
}

/// A box that is swiped away, the widget form of [Dismissible3d].
///
/// ```dart
/// SceneDismissible3d(
///   background: SceneDecoratedBox3d(decoration: deleteRed),
///   onDismissed: (_) => setState(() => items.removeAt(index)),
///   child: row,
/// )
/// ```
///
/// The three slots are mirrored onto the layout as one ordered child list, so
/// the same two rules apply here as there: a background needs a child, and a
/// secondary background needs a background.
///
/// [onDismissed] is the one callback that usually *does* call `setState`, and
/// it is the only one that should: it fires once, after the gap has closed,
/// and taking the item out of the list is a rebuild by definition. [onUpdate]
/// runs every frame of the swipe — write a decoration or a state layer from
/// it, never a rebuild.
class SceneDismissible3d extends Layout3dWidget {
  /// Creates a box that can be swiped away.
  const SceneDismissible3d({
    super.key,
    this.child,
    this.background,
    this.secondaryBackground,
    this.axis = Axis3d.horizontal,
    this.direction = Dismiss3dDirection.both,
    this.dismissThreshold = 0.4,
    this.flingVelocity = 700.0,
    this.movementDuration = const Duration(milliseconds: 200),
    this.resizeDuration = const Duration(milliseconds: 300),
    this.movementCurve = Curves.easeOut,
    this.resizeCurve = Curves.easeInOut,
    this.backgroundDepthStep = 0.0,
    this.behavior = HitTestBehavior3d.opaque,
    this.vsync,
    this.confirmDismiss,
    this.onUpdate,
    this.onResize,
    this.onDismissed,
  }) : assert(
         child != null || (background == null && secondaryBackground == null),
         'SceneDismissible3d has nothing to swipe: a background needs a '
         'child.',
       ),
       assert(
         background != null || secondaryBackground == null,
         'SceneDismissible3d.secondaryBackground needs a background beside '
         'it.',
       );

  /// What is swiped.
  final Widget? child;

  /// What shows behind a [Dismiss3dDirection.forward] swipe.
  final Widget? background;

  /// What shows behind a [Dismiss3dDirection.reverse] swipe.
  final Widget? secondaryBackground;

  /// The axis the swipe runs along.
  final Axis3d axis;

  /// Which way along [axis] a swipe may go.
  final Dismiss3dDirection direction;

  /// The fraction of the extent a swipe must reach to count.
  final double dismissThreshold;

  /// The flick speed that dismisses whatever distance it covered, in logical
  /// pixels a second.
  final double flingVelocity;

  /// How long the child takes to settle back, or to fly out.
  final Duration movementDuration;

  /// How long the box takes to close up, or null to skip the resize.
  final Duration? resizeDuration;

  /// The curve the settle and the fly-out follow.
  final Curve movementCurve;

  /// The curve the resize follows.
  final Curve resizeCurve;

  /// How far behind the child the backgrounds are pushed, in world units.
  final double backgroundDepthStep;

  /// How the box takes part in a hit test.
  final HitTestBehavior3d behavior;

  /// The ticker provider for the two animations, or null for bare `Ticker`s.
  final TickerProvider? vsync;

  /// Asked before a swipe past the threshold becomes a dismiss.
  final Dismiss3dConfirmCallback? confirmDismiss;

  /// Called as the swipe moves, with the signed progress.
  final ValueChanged<double>? onUpdate;

  /// Called on every tick of the resize.
  final VoidCallback? onResize;

  /// Called once the box has closed up.
  final ValueChanged<Dismiss3dDirection>? onDismissed;

  @override
  List<Widget> get children => <Widget>[
    if (child != null) child!,
    if (background != null) background!,
    if (secondaryBackground != null) secondaryBackground!,
  ];

  @override
  Dismissible3d createLayout(BuildContext context) => Dismissible3d(
    axis: axis,
    direction: direction,
    dismissThreshold: dismissThreshold,
    flingVelocity: flingVelocity,
    movementDuration: movementDuration,
    resizeDuration: resizeDuration,
    movementCurve: movementCurve,
    resizeCurve: resizeCurve,
    backgroundDepthStep: backgroundDepthStep,
    behavior: behavior,
    vsync: vsync,
    confirmDismiss: confirmDismiss,
    onUpdate: onUpdate,
    onResize: onResize,
    onDismissed: onDismissed,
  );

  @override
  void updateLayout(BuildContext context, Dismissible3d layout) {
    // The slots are not written here: they are children, and the framework
    // mirrors the reconciled child list onto the layout for us.
    layout
      ..axis = axis
      ..direction = direction
      ..dismissThreshold = dismissThreshold
      ..flingVelocity = flingVelocity
      ..movementDuration = movementDuration
      ..resizeDuration = resizeDuration
      ..movementCurve = movementCurve
      ..resizeCurve = resizeCurve
      ..backgroundDepthStep = backgroundDepthStep
      ..behavior = behavior
      ..vsync = vsync
      ..confirmDismiss = confirmDismiss
      ..onUpdate = onUpdate
      ..onResize = onResize
      ..onDismissed = onDismissed;
  }
}
