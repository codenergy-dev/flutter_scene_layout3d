import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:flutter/foundation.dart' show ValueChanged, VoidCallback;
import 'package:flutter/scheduler.dart' show TickerProvider;
import 'package:flutter/widgets.dart' show BuildContext;

import '../geometry/offset3d.dart';
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
