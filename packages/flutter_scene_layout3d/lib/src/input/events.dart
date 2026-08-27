import 'dart:ui' show Offset;

import 'package:flutter/gestures.dart'
    show GestureRecognizer, PointerDownEvent, PointerEvent;

import '../geometry/offset3d.dart';
import '../hit_test.dart';
import '../layout3d.dart';

/// A box that can be handed the events a hit test found it for.
///
/// The 3D analogue of `HitTestTarget`, and the seam between the two halves of
/// input. A hit test answers *what is under the pointer*; this answers *what
/// happens next*. `Layout3dPointer` walks the recorded
/// [HitTestResult3d.path] deepest first and calls [handleEvent] on every
/// layout that implements this, so a box that wants events only has to say so
/// — there is no registration and no listener list.
///
/// [Listener3d], [GestureDetector3d] and [Focus3d] are the implementations
/// that ship here. A layout of your own can implement it directly when the
/// event *is* the behaviour: a knob that turns, a slider that tracks, a piece
/// of geometry that answers a poke.
abstract interface class HitTestTarget3d {
  /// Handles [event], which reached this box because [entry] is on the path
  /// the pointer captured.
  ///
  /// [entry] is the entry recorded at the press, so it is the same object for
  /// every event of one sequence even after the pointer has left the box;
  /// [PointerEvent3d.localPosition] is recomputed for each event and is where
  /// the pointer is *now*, on the plane the press happened on.
  void handleEvent(PointerEvent3d event, HitTestEntry3d entry);
}

/// How a box takes part in a hit test, the 3D analogue of `HitTestBehavior`.
///
/// The default in this package, as in Flutter, is that a box which merely
/// arranges other boxes is not a target: a ray through the padding around a
/// button's label passes straight through. That is right for layout and wrong
/// for a control, which is why every interactive box takes one of these.
enum HitTestBehavior3d {
  /// The box is hit only where one of its children is.
  ///
  /// The padding around a label is not part of the target, and neither are
  /// the gaps between the children of a row.
  deferToChild,

  /// The box answers for its whole extent, and stops the ray.
  ///
  /// What a button, a card and an app bar want: the component is one target,
  /// including the room its own padding opened, and nothing behind it is
  /// reachable through it.
  opaque,

  /// The box receives the events its extent covers, and lets the ray carry on
  /// to whatever stands behind it.
  ///
  /// Two boxes can then be hovered at once, which is what a decorative
  /// overlay that wants to know about the pointer without stealing it needs.
  translucent,
}

/// The live pointer sequence one [PointerEvent3d] belongs to.
///
/// A target reaches for this when it wants to *compete* for the pointer
/// rather than merely watch it: handing a recognizer to
/// [addPointerToRecognizer] enters that recognizer in Flutter's gesture arena
/// for this sequence, and tells the sequence that the pointer is contested,
/// which is what makes a scrolling view wait for the touch slop instead of
/// scrolling out from under a tap.
abstract interface class PointerSequence3d {
  /// The pointer id this sequence uses in Flutter's gesture arena.
  ///
  /// Not the device's pointer id: see `Layout3dPointer.down`, which explains
  /// why a sequence gets an id of its own.
  int get arenaPointer;

  /// Whether anything has claimed a stake in this sequence.
  bool get isContested;

  /// Enters [recognizer] in this sequence's arena, handing it [event].
  ///
  /// [event] must be the [PointerEvent3d.event] of a *down*, already carrying
  /// the target's transform, which is what makes the recognizer report
  /// positions in the target's own frame.
  void addPointerToRecognizer(
    GestureRecognizer recognizer,
    PointerDownEvent event,
  );
}

/// A pointer event delivered to one box, in that box's own frame.
///
/// Flutter's [PointerEvent] is not reinvented here: [event] is the real
/// thing, synthesized in the surface's plane and measured in **logical
/// pixels**, so that Flutter's own gesture recognizers — and the constants
/// they are tuned with, `kTouchSlop`, `kDoubleTapSlop`, `kLongPressTimeout` —
/// mean what they mean. What this adds is the three-dimensional half of the
/// story: the [ray] that produced the event, the [entry] the hit test
/// recorded, and the [localPosition] on the box's own frame, in world units.
///
/// A box that only needs to know *that* it was pressed can look at [event];
/// a box that needs to know *where*, in its own space — a ripple's centre, a
/// knob's angle — wants [localPosition], which is recomputed by intersecting
/// the ray with the plane the press landed on and stays exact however the
/// surface is turned.
class PointerEvent3d {
  /// Creates an event for one target.
  const PointerEvent3d({
    required this.event,
    required this.entry,
    required this.localPosition,
    required this.metricsScale,
    this.ray,
    this.sequence,
  });

  /// The Flutter event, in the surface's logical-pixel frame.
  ///
  /// [PointerEvent.position] is where the pointer is on the surface plane and
  /// [PointerEvent.localPosition] is that point in the target's own frame,
  /// both in logical pixels: exactly the contract a `RenderPointerListener`
  /// hands a recognizer, so `recognizer.addPointer(event)` is all a gesture
  /// box has to do.
  final PointerEvent event;

  /// The hit-test entry this box was recorded with when the sequence began.
  final HitTestEntry3d entry;

  /// Where the pointer is now, in the target's own frame, in world units.
  ///
  /// Computed by intersecting [ray] with the plane the press landed on, so it
  /// keeps tracking after the pointer has left the box — and keeps meaning
  /// the same thing when the surface is seen at an angle, because the
  /// perspective divide happened before the number was taken.
  final Offset3d localPosition;

  /// The ray that produced this event, in the target's own frame, or null for
  /// an event no ray stands behind (a cancel, an exit).
  final Ray3d? ray;

  /// World units per logical pixel, as the tree's metrics had it when the
  /// event was made.
  ///
  /// The conversion between [localPosition] and [PointerEvent.localPosition],
  /// carried along so a target can move between the two frames without
  /// reaching for its own [Layout3d.metrics].
  final double metricsScale;

  /// The sequence this event belongs to, or null for a synthesized event
  /// that no pointer is driving.
  final PointerSequence3d? sequence;

  /// The box this event was delivered to.
  Layout3d get layout => entry.layout;

  /// The pointer id, in Flutter's arena.
  int get pointer => event.pointer;

  /// [localPosition] in logical pixels, discarding depth.
  ///
  /// The 2D position on the box's own plane, which is the coordinate a
  /// gesture recognizer works in.
  Offset get localOffset =>
      Offset(localPosition.x / metricsScale, localPosition.y / metricsScale);

  /// Enters [recognizer] in the arena for this sequence.
  ///
  /// Only meaningful on a down event, and only while a [sequence] is driving
  /// this event; a call at any other time is ignored, the same way
  /// `GestureRecognizer.addPointer` is only ever handed a down.
  void addPointerToRecognizer(GestureRecognizer recognizer) {
    final event = this.event;
    if (event is! PointerDownEvent) return;
    sequence?.addPointerToRecognizer(recognizer, event);
  }

  @override
  String toString() =>
      'PointerEvent3d(${event.runtimeType} on ${layout.runtimeType} '
      'at $localPosition)';
}
