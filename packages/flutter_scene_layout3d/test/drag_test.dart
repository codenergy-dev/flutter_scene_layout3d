// Drag and drop: a payload in flight, and the targets it passes over.
//
// Two halves. `Drag3dSession` is the machinery, and it is driven by hand here
// — no pointer, no components — because a drag is arithmetic and state and
// almost all of it can be pinned down that way. `Draggable3d` and
// `DragTarget3d` are the components over it, and what they mostly have to
// prove is a negative: that a whole drag touches the layout path exactly
// twice, when the feedback is put into the overlay and when it is taken out.
//
// These need Flutter's gesture binding, because the arena is global and a
// drag competes in it.

import 'package:flutter/gestures.dart'
    show GestureArenaEntry, GestureArenaMember, GestureDisposition;
import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dController,
        SceneDismissible3d,
        SceneDragTarget3d,
        SceneDraggable3d,
        SceneLayout3d,
        SceneRow3d,
        SceneSizedBox3d;
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A drop target that writes down what reached it.
class Recorder extends DragTarget3d<String> {
  Recorder(this.label, this.log, {super.child, super.onWillAccept})
    : super(behavior: HitTestBehavior3d.translucent);

  final String label;
  final List<String> log;

  @override
  void handleDrag3d(Drag3dEvent event) {
    log.add('$label ${event.kind.name}');
    super.handleDrag3d(event);
  }
}

/// A hit-test path made by hand, deepest first, standing in for one a ray
/// found.
///
/// The session takes a [HitTestResult3d] and asks nothing about where it came
/// from, which is exactly what makes the state machine testable without a
/// pointer.
HitTestResult3d pathOf(List<Layout3d> layouts, {Offset3d at = Offset3d.zero}) {
  final result = HitTestResult3d();
  for (final layout in layouts) {
    result.add(HitTestEntry3d(layout, at));
  }
  return result;
}

/// An arena member that only writes down what the arena told it.
class Bystander implements GestureArenaMember {
  Bystander(this.log);

  final List<String> log;

  @override
  void acceptGesture(int pointer) => log.add('accepted');

  @override
  void rejectGesture(int pointer) => log.add('rejected');
}

/// A box that competes for the pointer through the new arena seam.
class ArenaProbe extends Listener3d {
  ArenaProbe(this.members, {super.child})
    : super(behavior: HitTestBehavior3d.opaque);

  /// Everything to enter in the arena, in order.
  ///
  /// They all have to go in during the down: the arena refuses a member added
  /// after it closes, and `_Sequence` closes it at the end of the dispatch.
  final List<GestureArenaMember> members;

  /// The entries handed back, so a test can resolve one whenever it likes.
  final List<GestureArenaEntry> entries = <GestureArenaEntry>[];

  /// The sequence this box was handed a down on.
  ///
  /// Its [PointerSequence3d.arenaPointer] is the id the sequence competes
  /// under, which is not the device's — a private one, so a gesture on the
  /// plane cannot collide with the widget-level gesture the same finger is
  /// driving. Reading it is how a test joins the same arena.
  PointerSequence3d? sequence;

  @override
  void handleEvent(PointerEvent3d event, HitTestEntry3d entry) {
    super.handleEvent(event, entry);
    if (sequence != null) return;
    sequence = event.sequence;
    for (final member in members) {
      final arenaEntry = event.addArenaMember(member);
      if (arenaEntry != null) entries.add(arenaEntry);
    }
  }
}

/// A leaf that answers hit tests, which is what a real piece of content does.
TestBox solid([Size3d size = const Size3d(1, 1, 0)]) =>
    TestBox(size, pointable: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the session', () {
    test('enter, move, leave, and enter again', () {
      final log = <String>[];
      final target = Recorder('zone', log, child: solid());
      laidOut(target, constraints: Constraints3d.tight(const Size3d(1, 1, 0)));
      final session = Drag3dSession(data: 'photo');

      session.update(pathOf(<Layout3d>[target]));
      session.update(pathOf(<Layout3d>[target]));
      session.update(pathOf(const <Layout3d>[]));
      session.update(pathOf(<Layout3d>[target]));

      expect(log, ['zone enter', 'zone move', 'zone leave', 'zone enter']);
    });

    test('enter reaches every acceptor, outermost first', () {
      final log = <String>[];
      final row = Recorder('row', log, child: solid());
      final list = Recorder('list', log, child: row);
      laidOut(list, constraints: Constraints3d.tight(const Size3d(1, 1, 0)));
      final session = Drag3dSession(data: 'photo');

      session.update(pathOf(<Layout3d>[row, list]));

      // The list learns before the row does, the same order hover uses.
      expect(log, ['list enter', 'row enter']);
    });

    test('leave reaches every acceptor, deepest first', () {
      final log = <String>[];
      final row = Recorder('row', log, child: solid());
      final list = Recorder('list', log, child: row);
      laidOut(list, constraints: Constraints3d.tight(const Size3d(1, 1, 0)));
      final session = Drag3dSession(data: 'photo')
        ..update(pathOf(<Layout3d>[row, list]));
      log.clear();

      session.update(pathOf(const <Layout3d>[]));

      expect(log, ['row leave', 'list leave']);
    });

    test('the drop goes to the deepest acceptor, and the rest are left', () {
      final log = <String>[];
      final row = Recorder('row', log, child: solid());
      final list = Recorder('list', log, child: row);
      laidOut(list, constraints: Constraints3d.tight(const Size3d(1, 1, 0)));
      final session = Drag3dSession(data: 'photo')
        ..update(pathOf(<Layout3d>[row, list]));
      log.clear();

      expect(session.drop(), isTrue);

      expect(log, ['list leave', 'row drop']);
      expect(session.wasAccepted, isTrue);
      expect(session.acceptedBy, same(row));
      expect(session.isActive, isFalse);
    });

    test('a release over nothing is not a drop', () {
      final session = Drag3dSession(data: 'photo');

      expect(session.drop(), isFalse);
      expect(session.wasAccepted, isFalse);
      expect(session.acceptedBy, isNull);
      expect(session.isActive, isFalse);
    });

    test('a cancel tells every target it has left', () {
      final log = <String>[];
      final target = Recorder('zone', log, child: solid());
      laidOut(target, constraints: Constraints3d.tight(const Size3d(1, 1, 0)));
      final session = Drag3dSession(data: 'photo')
        ..update(pathOf(<Layout3d>[target]));
      log.clear();

      session
        ..cancel()
        ..cancel();

      expect(log, ['zone leave']);
      expect(session.wasAccepted, isFalse);
    });

    test('a target that refuses by type never hears about the drag', () {
      final log = <String>[];
      final wrongType = DragTarget3d<int>(
        onEnter: (_, _) => log.add('int enter'),
        child: solid(),
      );
      final rightType = Recorder('string', log, child: wrongType);
      laidOut(
        rightType,
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      final session = Drag3dSession(data: 'photo');

      session.update(pathOf(<Layout3d>[wrongType, rightType]));

      expect(log, ['string enter']);
      expect(session.target, same(rightType));
    });

    test('onWillAccept can refuse, and can change its mind', () {
      final log = <String>[];
      var welcome = false;
      final target = Recorder(
        'zone',
        log,
        onWillAccept: (_, _) => welcome,
        child: solid(),
      );
      laidOut(target, constraints: Constraints3d.tight(const Size3d(1, 1, 0)));
      final session = Drag3dSession(data: 'photo');

      session.update(pathOf(<Layout3d>[target]));
      expect(log, isEmpty);

      welcome = true;
      session.update(pathOf(<Layout3d>[target]));
      expect(log, ['zone enter']);

      welcome = false;
      session.update(pathOf(<Layout3d>[target]));
      expect(log, ['zone enter', 'zone leave']);
    });

    test('the details carry the payload, the origin and the local point', () {
      Drag3dDetails? seen;
      final target = DragTarget3d<String>(
        onEnter: (_, details) => seen = details,
        child: solid(),
      );
      laidOut(target, constraints: Constraints3d.tight(const Size3d(1, 1, 0)));
      final session = Drag3dSession(
        data: 'photo',
        origin: const Offset3d(0.25, 0.5, 0),
      );

      session.update(
        pathOf(<Layout3d>[target], at: const Offset3d(0.1, 0.2, 0)),
      );

      expect(seen, isNotNull);
      expect(seen!.data, 'photo');
      expect(seen!.origin, const Offset3d(0.25, 0.5, 0));
      expect(seen!.localPosition, const Offset3d(0.1, 0.2, 0));
      expect(seen!.session, same(session));
    });

    test('a candidate target knows what is over it', () {
      final target = DragTarget3d<String>(child: solid());
      laidOut(target, constraints: Constraints3d.tight(const Size3d(1, 1, 0)));
      final session = Drag3dSession(data: 'photo');

      expect(target.isCandidate, isFalse);
      session.update(pathOf(<Layout3d>[target]));
      expect(target.isCandidate, isTrue);
      expect(target.candidateData, ['photo']);

      session.drop();
      expect(target.isCandidate, isFalse);
    });

    test('an end listener fires once, whatever ended the session', () {
      var ends = 0;
      final dropped = Drag3dSession(data: 'photo')
        ..addEndListener(() => ends++);
      dropped.drop();
      expect(ends, 1);

      final cancelled = Drag3dSession(data: 'photo')
        ..addEndListener(() => ends++);
      cancelled
        ..cancel()
        ..cancel();
      expect(ends, 2);
    });

    test('a listener added to an ended session is called at once', () {
      var ends = 0;
      final session = Drag3dSession(data: 'photo')..cancel();

      session.addEndListener(() => ends++);

      expect(ends, 1);
    });

    test('refresh re-resolves against the path it last saw', () {
      final log = <String>[];
      var welcome = false;
      final target = Recorder(
        'zone',
        log,
        onWillAccept: (_, _) => welcome,
        child: solid(),
      );
      laidOut(target, constraints: Constraints3d.tight(const Size3d(1, 1, 0)));
      final session = Drag3dSession(data: 'photo')
        ..update(pathOf(<Layout3d>[target]));

      welcome = true;
      // Nothing moved: the world changed underneath, which is what an
      // autoscroll tick looks like.
      session.refresh();

      expect(log, ['zone enter']);
    });
  });

  group('the pointer registry', () {
    test('a session in flight resolves against the fresh hit, not the '
        'captured path', () {
      final log = <String>[];
      final source = Recorder('source', log, child: solid());
      final zone = Recorder('zone', log, child: solid());
      final surface = laidOut(
        Row3d(children: <Layout3d>[source, zone]),
        constraints: Constraints3d.tight(const Size3d(2, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);
      final session = Drag3dSession(data: 'photo');

      pointer.down(rayAt(surface, const Offset3d(0.5, 0.5, 0)));
      pointer.startDrag(session);
      expect(log, ['source enter']);
      expect(pointer.dragFor(0), same(session));

      // The captured path is still the source's. The drag search ignores it.
      pointer.move(rayAt(surface, const Offset3d(1.5, 0.5, 0)));

      expect(log, ['source enter', 'source leave', 'zone enter']);
      expect(session.target, same(zone));
    });

    test('the up drops on what the release was over', () {
      final log = <String>[];
      final source = Recorder('source', log, child: solid());
      final zone = Recorder('zone', log, child: solid());
      final surface = laidOut(
        Row3d(children: <Layout3d>[source, zone]),
        constraints: Constraints3d.tight(const Size3d(2, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);
      final session = Drag3dSession(data: 'photo');

      pointer
        ..down(rayAt(surface, const Offset3d(0.5, 0.5, 0)))
        ..startDrag(session)
        ..up(worldRay: rayAt(surface, const Offset3d(1.5, 0.5, 0)));

      expect(log.last, 'zone drop');
      expect(session.acceptedBy, same(zone));
      expect(pointer.dragFor(0), isNull);
    });

    test('a cancelled pointer cancels the drag', () {
      final log = <String>[];
      final zone = Recorder('zone', log, child: solid());
      final surface = laidOut(
        zone,
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);
      final session = Drag3dSession(data: 'photo');

      pointer
        ..down(rayAt(surface, const Offset3d(0.5, 0.5, 0)))
        ..startDrag(session)
        ..cancel();

      expect(log, ['zone enter', 'zone leave']);
      expect(session.isActive, isFalse);
      expect(pointer.dragFor(0), isNull);
    });

    test('disposing the pointer cancels what is in flight', () {
      final surface = laidOut(
        solid(),
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);
      final session = Drag3dSession(data: 'photo');

      pointer
        ..down(rayAt(surface, const Offset3d(0.5, 0.5, 0)))
        ..startDrag(session)
        ..dispose();

      expect(session.isActive, isFalse);
      expect(pointer.isDraggingPayload, isFalse);
    });

    test('a second session on one pointer cancels the first', () {
      final surface = laidOut(
        solid(),
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);
      final first = Drag3dSession(data: 'one');
      final second = Drag3dSession(data: 'two');

      pointer
        ..down(rayAt(surface, const Offset3d(0.5, 0.5, 0)))
        ..startDrag(first)
        ..startDrag(second);

      expect(first.isActive, isFalse);
      expect(pointer.dragFor(0), same(second));
    });
  });

  group('the arena seam', () {
    // The question the plan named as its phase-1 uncertainty: `_Sequence`
    // closes the arena at the end of the down, and a long-press drag resolves
    // long after that. These three settle it.

    test('a member resolves long after the arena closed', () async {
      final log = <String>[];
      final probe = ArenaProbe(<GestureArenaMember>[
        Bystander(log),
        Bystander(<String>[]),
      ], child: solid());
      final surface = laidOut(
        probe,
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer.down(rayAt(surface, const Offset3d(0.5, 0.5, 0)));
      expect(log, isEmpty, reason: 'two members: nothing wins by default');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      probe.entries.last.resolve(GestureDisposition.accepted);

      // This is the question the plan asked, and the answer is yes: `close`
      // ends the window for *adding*, not the arena. A long-press drag that
      // claims the pointer half a second in works, and the scroll drag under
      // it is rejected then and there.
      expect(log, ['rejected']);
    });

    test('a lone member wins by default as soon as the arena closes', () async {
      final log = <String>[];
      final probe = ArenaProbe(<GestureArenaMember>[
        Bystander(log),
      ], child: solid());
      final surface = laidOut(
        probe,
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer.down(rayAt(surface, const Offset3d(0.5, 0.5, 0)));
      await Future<void>.microtask(() {});

      // Which is why winning the arena and recognizing the gesture have to be
      // kept apart: nothing about the finger has happened yet.
      expect(log, ['accepted']);
    });

    test('a resolution after the up is silently dropped', () async {
      final log = <String>[];
      final probe = ArenaProbe(<GestureArenaMember>[
        Bystander(<String>[]),
        Bystander(log),
      ], child: solid());
      final surface = laidOut(
        probe,
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer
        ..down(rayAt(surface, const Offset3d(0.5, 0.5, 0)))
        ..up();
      // The sweep at the up gave the pointer to the first member and rejected
      // the rest, which is the whole of what an up means to the arena.
      expect(log, ['rejected']);
      log.clear();

      probe.entries.last.resolve(GestureDisposition.accepted);

      // And after that the arena is gone: a late resolution does nothing at
      // all, silently. Which is why a long-press timer has to be cancelled by
      // the up rather than left to lose the arena.
      expect(log, isEmpty);
    });

    test('adding a member marks the sequence contested', () {
      PointerSequence3d? sequence;
      final probe = Listener3d(
        behavior: HitTestBehavior3d.opaque,
        onPointerDown: (event) {
          sequence = event.sequence;
          event.addArenaMember(Bystander(<String>[]));
        },
        child: solid(),
      );
      final surface = laidOut(
        probe,
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer.down(rayAt(surface, const Offset3d(0.5, 0.5, 0)));

      expect(sequence, isNotNull);
      expect(sequence!.isContested, isTrue);
    });
  });

  group('Draggable3d', () {
    test('travel past the slop starts the drag; travel under it does not', () {
      final log = <String>[];
      final source = Draggable3d<String>(
        data: 'photo',
        onDragStarted: () => log.add('started'),
        child: solid(),
      );
      final zone = Recorder('zone', log, child: solid());
      final surface = laidOut(
        Row3d(children: <Layout3d>[source, zone]),
        constraints: Constraints3d.tight(const Size3d(2, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer.down(rayAt(surface, const Offset3d(0.5, 0.5, 0)));
      // The slop is 18dp, which at a hundred logical pixels to the unit is
      // 0.18 units. A tenth of a unit is not a drag.
      pointer.move(rayAt(surface, const Offset3d(0.6, 0.5, 0)));
      expect(source.isDragging, isFalse);
      expect(log, isEmpty);

      pointer.move(rayAt(surface, const Offset3d(0.9, 0.5, 0)));
      expect(source.isDragging, isTrue);
      expect(log, ['started']);
    });

    test('an axis keeps a row and the list it is in out of each other way', () {
      final source = Draggable3d<String>(
        data: 'photo',
        axis: Axis3d.horizontal,
        child: solid(),
      );
      final surface = laidOut(
        source,
        constraints: Constraints3d.tight(const Size3d(1, 2, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer
        ..down(rayAt(surface, const Offset3d(0.5, 0.5, 0)))
        ..move(rayAt(surface, const Offset3d(0.5, 1.5, 0)));

      // A whole unit down the other axis, which is five times the slop.
      expect(source.isDragging, isFalse);

      pointer.move(rayAt(surface, const Offset3d(0.9, 1.5, 0)));
      expect(source.isDragging, isTrue);
    });

    test('the drag lands on a target and the payload arrives', () {
      String? accepted;
      final source = Draggable3d<String>(data: 'photo', child: solid());
      final zone = DragTarget3d<String>(
        onAccept: (data, _) => accepted = data,
        child: solid(),
      );
      final surface = laidOut(
        Row3d(children: <Layout3d>[source, zone]),
        constraints: Constraints3d.tight(const Size3d(2, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer
        ..down(rayAt(surface, const Offset3d(0.5, 0.5, 0)))
        ..move(rayAt(surface, const Offset3d(1.0, 0.5, 0)))
        ..move(rayAt(surface, const Offset3d(1.5, 0.5, 0)))
        ..up();

      expect(accepted, 'photo');
      expect(source.isDragging, isFalse);
    });

    test('a lift with no travel is not a drag and drops nothing', () {
      var accepts = 0;
      final source = Draggable3d<String>(data: 'photo', child: solid());
      final zone = DragTarget3d<String>(
        onAccept: (_, _) => accepts++,
        child: solid(),
      );
      final surface = laidOut(
        Row3d(children: <Layout3d>[source, zone]),
        constraints: Constraints3d.tight(const Size3d(2, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer
        ..down(rayAt(surface, const Offset3d(0.5, 0.5, 0)))
        ..up();

      expect(accepts, 0);
      expect(source.isDragging, isFalse);
    });

    test('a scrolling view under a draggable waits for the slop', () {
      final controller = Scroll3dController();
      addTearDown(controller.dispose);
      final source = Draggable3d<String>(data: 'photo', child: solid());
      final list = ListView3d(
        controller: controller,
        children: <Layout3d>[
          source,
          TestBox(const Size3d(1, 4, 0), pointable: true),
        ],
      );
      final surface = laidOut(
        list,
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer
        ..down(rayAt(surface, const Offset3d(0.5, 0.5, 0)))
        ..move(rayAt(surface, const Offset3d(0.5, 0.1, 0)));

      // The draggable crossed its slop first and claimed the pointer, which
      // rejects the view: the list did not move out from under the card.
      expect(source.isDragging, isTrue);
      expect(controller.offset, 0.0);
    });

    test('a scroll that claims first cancels the pending drag', () {
      final controller = Scroll3dController();
      addTearDown(controller.dispose);
      final source = Draggable3d<String>(
        data: 'photo',
        axis: Axis3d.horizontal,
        child: solid(),
      );
      final list = ListView3d(
        controller: controller,
        children: <Layout3d>[
          source,
          TestBox(const Size3d(1, 4, 0), pointable: true),
        ],
      );
      final surface = laidOut(
        list,
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer
        ..down(rayAt(surface, const Offset3d(0.5, 0.5, 0)))
        ..move(rayAt(surface, const Offset3d(0.5, 0.1, 0)));

      expect(controller.offset, greaterThan(0.0));

      // The row is horizontal and never gets its chance: the pointer is gone.
      pointer.move(rayAt(surface, const Offset3d(0.0, 0.1, 0)));
      expect(source.isDragging, isFalse);
    });

    test('disposing a draggable mid-drag cancels the session', () {
      final log = <String>[];
      final source = Draggable3d<String>(data: 'photo', child: solid());
      final zone = Recorder('zone', log, child: solid());
      final surface = laidOut(
        Row3d(children: <Layout3d>[source, zone]),
        constraints: Constraints3d.tight(const Size3d(2, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer
        ..down(rayAt(surface, const Offset3d(0.5, 0.5, 0)))
        ..move(rayAt(surface, const Offset3d(1.5, 0.5, 0)));
      final session = source.session;
      expect(session, isNotNull);
      expect(log, ['zone enter', 'zone move']);

      source.dispose();

      expect(session!.isActive, isFalse);
      expect(log.last, 'zone leave');
    });
  });

  group('the feedback', () {
    test('goes into the overlay on start and comes out on the drop', () {
      final overlay = Overlay3d();
      final source = Draggable3d<String>(
        data: 'photo',
        dropDuration: Duration.zero,
        feedbackBuilder: (_) => TestBox(const Size3d(0.4, 0.4, 0)),
        child: solid(),
      );
      overlay.syncChildren(<Layout3d>[source]);
      final surface = laidOut(
        overlay,
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer
        ..down(rayAt(surface, const Offset3d(0.5, 0.5, 0)))
        ..move(rayAt(surface, const Offset3d(0.9, 0.5, 0)));
      expect(overlay.entries, hasLength(1));

      pointer.up();
      expect(overlay.entries, isEmpty);
    });

    test('is moved by nodeOffset and never by sceneOffset', () {
      final overlay = Overlay3d();
      late final Layout3d feedback;
      final source = Draggable3d<String>(
        data: 'photo',
        dropDuration: Duration.zero,
        feedbackBuilder: (_) => feedback = TestBox(const Size3d(0.4, 0.4, 0)),
        child: solid(),
      );
      overlay.syncChildren(<Layout3d>[source]);
      final surface = laidOut(
        overlay,
        constraints: Constraints3d.tight(const Size3d(2, 2, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer
        ..down(rayAt(surface, const Offset3d(1.0, 1.0, 0)))
        ..move(rayAt(surface, const Offset3d(1.4, 1.0, 0)));
      surface.flush();
      // The `IgnorePointer3d` wrapper is what carries the offset; the built
      // subtree hangs under it.
      final host = feedback.parent!;
      pointer.move(rayAt(surface, const Offset3d(1.45, 1.0, 0)));
      final before = host.nodeOffset;

      pointer.move(rayAt(surface, const Offset3d(1.25, 1.0, 0)));

      expect(host.nodeOffset.x, closeTo(before.x - 0.2, 1e-6));
      // `Stack3d.depthStep` owns `sceneOffset` and rewrites it on every
      // placement; anything stored there would be silently erased.
      expect(host.sceneOffset, isNot(equals(host.nodeOffset)));
    });

    test('follows the pointer, and starts over the box it came from', () {
      late final Layout3d feedback;
      final source = Draggable3d<String>(
        data: 'photo',
        dropDuration: Duration.zero,
        feedbackBuilder: (_) => feedback = TestBox(const Size3d(0.4, 0.4, 0)),
        child: solid(const Size3d(0.4, 0.4, 0)),
      );
      // The source is pushed off centre, so that "over the source" and "where
      // the overlay would have put it" are different places.
      final overlay = Overlay3d(
        alignment: Alignment3d.topLeft,
        children: <Layout3d>[
          Padding3d(
            padding: const EdgeInsets3d.only(left: 1.0, top: 0.5),
            child: source,
          ),
        ],
      );
      final surface = laidOut(
        overlay,
        constraints: Constraints3d.tight(const Size3d(3, 3, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer
        ..down(rayAt(surface, const Offset3d(1.2, 0.7, 0)))
        ..move(rayAt(surface, const Offset3d(1.6, 0.7, 0)));
      surface.flush();
      // The feedback was only laid out on the flush, so the correction is
      // computed on this move rather than the one that started the drag.
      pointer.move(rayAt(surface, const Offset3d(1.6, 0.7, 0)));
      final host = feedback.parent!;

      // The overlay put the entry at its top-left corner and the source is a
      // unit right and half a unit down of it, so covering the source is a
      // correction of exactly that — plus the 0.4 the finger has travelled.
      // In layout units: `nodeOffset` is measured in the frame the parent
      // placed the box in, not in world space.
      expect(host.nodeOffset.x, closeTo(1.4, 1e-6));
      expect(host.nodeOffset.y, closeTo(0.5, 1e-6));
    });

    test('nothing a live drag does reaches the relayout path', () {
      final overlay = Overlay3d();
      final zone = DragTarget3d<String>(child: solid());
      final source = Draggable3d<String>(
        data: 'photo',
        dropDuration: Duration.zero,
        feedbackBuilder: (_) => TestBox(const Size3d(0.4, 0.4, 0)),
        child: solid(),
      );
      overlay.syncChildren(<Layout3d>[
        Row3d(children: <Layout3d>[source, zone]),
      ]);
      final surface = laidOut(
        overlay,
        constraints: Constraints3d.tight(const Size3d(2, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer
        ..down(rayAt(surface, const Offset3d(0.5, 0.5, 0)))
        ..move(rayAt(surface, const Offset3d(0.9, 0.5, 0)));
      // Putting the feedback into the overlay is a layout, and it is the only
      // one: an overlay entry is a child of a stack and adding a child is a
      // layout pass. Everything after this is a matrix write.
      expect(surface.needsFlush, isTrue);
      surface.flush();

      for (var i = 0; i <= 20; i++) {
        pointer.move(rayAt(surface, Offset3d(0.9 + i * 0.05, 0.5, 0)));
        expect(surface.needsFlush, isFalse, reason: 'move $i dirtied layout');
      }
      pointer.up();

      // And the removal at the end is the second and last one.
      expect(surface.needsFlush, isTrue);
    });

    test(
      'an overlay disposed under a live drag takes the feedback with it',
      () {
        final overlay = Overlay3d();
        final source = Draggable3d<String>(
          data: 'photo',
          overlay: overlay,
          dropDuration: Duration.zero,
          feedbackBuilder: (_) => TestBox(const Size3d(0.4, 0.4, 0)),
          child: solid(),
        );
        final surface = laidOut(
          Stack3d(children: <Layout3d>[source, overlay]),
          constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
        );
        final pointer = Layout3dPointer(surface);

        pointer
          ..down(rayAt(surface, const Offset3d(0.5, 0.5, 0)))
          ..move(rayAt(surface, const Offset3d(0.9, 0.5, 0)));
        overlay.clearEntries();

        // The removal path is the entry's, and it is idempotent: the drop finds
        // nothing left to take out and says nothing about it.
        pointer.up();
        expect(overlay.entries, isEmpty);
      },
    );

    test('a draggable with no overlay above it still drags', () {
      String? accepted;
      final source = Draggable3d<String>(
        data: 'photo',
        feedbackBuilder: (_) => TestBox(const Size3d(0.4, 0.4, 0)),
        child: solid(),
      );
      final zone = DragTarget3d<String>(
        onAccept: (data, _) => accepted = data,
        child: solid(),
      );
      final surface = laidOut(
        Row3d(children: <Layout3d>[source, zone]),
        constraints: Constraints3d.tight(const Size3d(2, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer
        ..down(rayAt(surface, const Offset3d(0.5, 0.5, 0)))
        ..move(rayAt(surface, const Offset3d(1.5, 0.5, 0)))
        ..up();

      expect(accepted, 'photo');
    });
  });

  group('under a clock', () {
    testWidgets('a long press starts the drag where the finger is', (
      tester,
    ) async {
      final source = Draggable3d<String>(
        data: 'photo',
        startMode: const Drag3dStartMode.longPress(Duration(milliseconds: 300)),
        child: solid(),
      );
      final surface = laidOut(
        source,
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      addTearDown(surface.dispose);
      final pointer = Layout3dPointer(surface);

      pointer.down(rayAt(surface, const Offset3d(0.5, 0.5, 0)));
      await tester.pump(const Duration(milliseconds: 200));
      expect(source.isDragging, isFalse);

      await tester.pump(const Duration(milliseconds: 200));
      expect(source.isDragging, isTrue);

      pointer.up();
    });

    testWidgets('movement before the delay cancels the long press', (
      tester,
    ) async {
      final source = Draggable3d<String>(
        data: 'photo',
        startMode: const Drag3dStartMode.longPress(Duration(milliseconds: 300)),
        child: solid(),
      );
      final surface = laidOut(
        source,
        constraints: Constraints3d.tight(const Size3d(2, 2, 0)),
      );
      addTearDown(surface.dispose);
      final pointer = Layout3dPointer(surface);

      pointer.down(rayAt(surface, const Offset3d(0.5, 0.5, 0)));
      await tester.pump(const Duration(milliseconds: 100));
      pointer.move(rayAt(surface, const Offset3d(1.5, 0.5, 0)));
      await tester.pump(const Duration(milliseconds: 400));

      expect(source.isDragging, isFalse);
      pointer.up();
    });

    testWidgets('the up cancels the long press timer', (tester) async {
      final source = Draggable3d<String>(
        data: 'photo',
        startMode: const Drag3dStartMode.longPress(Duration(milliseconds: 300)),
        child: solid(),
      );
      final surface = laidOut(
        source,
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      addTearDown(surface.dispose);
      final pointer = Layout3dPointer(surface);

      pointer
        ..down(rayAt(surface, const Offset3d(0.5, 0.5, 0)))
        ..up();
      await tester.pump(const Duration(milliseconds: 400));

      expect(source.isDragging, isFalse);
    });

    testWidgets('the drop animation delays the removal and nothing else', (
      tester,
    ) async {
      final overlay = Overlay3d();
      late final Layout3d feedback;
      final source = Draggable3d<String>(
        data: 'photo',
        dropDuration: const Duration(milliseconds: 200),
        feedbackBuilder: (_) => feedback = TestBox(const Size3d(0.4, 0.4, 0)),
        child: solid(),
      );
      overlay.syncChildren(<Layout3d>[source]);
      final surface = laidOut(
        overlay,
        constraints: Constraints3d.tight(const Size3d(2, 2, 0)),
      );
      addTearDown(surface.dispose);
      final pointer = Layout3dPointer(surface);

      pointer
        ..down(rayAt(surface, const Offset3d(0.5, 0.5, 0)))
        ..move(rayAt(surface, const Offset3d(1.5, 0.5, 0)));
      surface.flush();
      pointer.move(rayAt(surface, const Offset3d(1.5, 0.5, 0)));
      final host = feedback.parent!;
      final away = host.nodeOffset;

      pointer.up();
      expect(overlay.entries, hasLength(1), reason: 'still settling');

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(host.nodeOffset.x, isNot(closeTo(away.x, 1e-6)));
      expect(surface.needsFlush, isFalse, reason: 'the tween is node-tier');

      await tester.pump(const Duration(milliseconds: 200));
      expect(overlay.entries, isEmpty);
    });
  });

  group('the widget layer', () {
    testWidgets('mirrors a draggable and a target onto the layout tree', (
      tester,
    ) async {
      final parent = Node();
      final controller = Layout3dController();
      String? accepted;

      Widget frame(String payload) => SceneLayout3d(
        parent: parent,
        size: const Size3d(4, 2, 0),
        controller: controller,
        child: SceneRow3d(
          children: <Widget>[
            SceneDraggable3d<String>(
              data: payload,
              child: const SceneSizedBox3d(width: 2, height: 2),
            ),
            SceneDragTarget3d<String>(
              onAccept: (data, _) => accepted = data,
              child: const SceneSizedBox3d(width: 2, height: 2),
            ),
          ],
        ),
      );

      await tester.pumpWidget(frame('photo'));
      final row = controller.surface!.child! as MultiChildLayout3d;
      final source = row.children.first as Draggable3d<String>;
      expect(source.data, 'photo');
      expect(row.children.last, isA<DragTarget3d<String>>());

      // A rebuild reconciles onto the same layout objects and writes the new
      // payload through, which is the whole contract of the widget layer.
      await tester.pumpWidget(frame('drawing'));
      expect(controller.surface!.child! as MultiChildLayout3d, same(row));
      expect(source.data, 'drawing');

      final surface = controller.surface!;
      final pointer = Layout3dPointer(surface);
      pointer
        ..down(rayAt(surface, const Offset3d(1.0, 1.0, 0)))
        ..move(rayAt(surface, const Offset3d(3.0, 1.0, 0)))
        ..up();

      expect(accepted, 'drawing');
    });
  });
  group('across surfaces', () {
    // Two coincident planes, one in front of the other, which is what a
    // dialog standing over a panel is: the same layout coordinates on both,
    // so a ray aimed at a point reaches whichever surface answers there
    // first. `plate` in `overlay_test.dart` builds them the same way.
    Layout3dSurface plate(Layout3d child) {
      final surface = laidOut(
        child,
        constraints: Constraints3d.tight(const Size3d(2, 1, 0)),
      );
      addTearDown(surface.dispose);
      return surface;
    }

    test('a drag started on the panel drops on the dialog in front', () {
      final log = <String>[];
      final source = Draggable3d<String>(data: 'photo', child: solid());
      final behind = Recorder('behind', log, child: solid());
      final panel = plate(Row3d(children: <Layout3d>[source, behind]));
      final front = Recorder('front', log, child: solid());
      final dialog = plate(
        // Nothing in the left half of the dialog answers, so the press at
        // 0.5 goes straight past it to the panel behind.
        Padding3d(padding: const EdgeInsets3d.only(left: 1.0), child: front),
      );
      final group = Layout3dPointerGroup()
        ..addSurface(panel)
        ..addSurface(dialog, zOrder: 1);
      addTearDown(group.dispose);

      group
        ..down(rayAt(panel, const Offset3d(0.5, 0.5, 0)))
        ..move(rayAt(panel, const Offset3d(0.9, 0.5, 0)));

      // The press landed on the panel and only the panel: capture is what
      // events follow, and it is not what the drag search follows.
      expect(group.capturedBy(0), <Layout3dSurface>[panel]);
      expect(group.dragFor(0), isNotNull);
      expect(group.isDraggingPayload, isTrue);

      group
        ..move(rayAt(panel, const Offset3d(1.5, 0.5, 0)))
        ..up(worldRay: rayAt(panel, const Offset3d(1.5, 0.5, 0)));

      // The dialog answered where the panel's own target sits, so the target
      // behind it never heard about the drag at all: a drop lands where a tap
      // would land.
      expect(log, ['front enter', 'front move', 'front drop']);
      expect(group.capturedBy(0), isEmpty);
    });

    test('the captured surface no longer resolves the drag on its own', () {
      final panel = plate(solid(const Size3d(2, 1, 0)));
      final group = Layout3dPointerGroup()..addSurface(panel);
      addTearDown(group.dispose);

      // The group answers "what is this drag over" for every pointer it
      // holds, so a session would otherwise be resolved twice a move — the
      // first time against a path that stops at one plane.
      expect(group.pointerFor(panel)!.resolvesDrags, isFalse);

      final pointer = group.removeSurface(panel)!;
      expect(pointer.resolvesDrags, isTrue);
    });

    test('a surface that answers nothing is walked straight past', () {
      final log = <String>[];
      final source = Draggable3d<String>(data: 'photo', child: solid());
      final panel = plate(Row3d(children: <Layout3d>[source, solid()]));
      final front = Recorder('front', log, child: solid());
      final dialog = plate(
        Padding3d(padding: const EdgeInsets3d.only(left: 1.0), child: front),
      );
      // What a detached piece of feedback is: a surface of its own, whose
      // root is an `IgnorePointer3d`, sitting in front of everything. It
      // answers empty, so it absorbs nothing and the drag it is the feedback
      // *for* can still find its target.
      final feedback = plate(
        IgnorePointer3d(child: solid(const Size3d(2, 1, 0))),
      );
      final group = Layout3dPointerGroup()
        ..addSurface(panel)
        ..addSurface(dialog, zOrder: 1)
        ..addSurface(feedback, zOrder: 2);
      addTearDown(group.dispose);

      group
        ..down(rayAt(panel, const Offset3d(0.5, 0.5, 0)))
        ..move(rayAt(panel, const Offset3d(0.9, 0.5, 0)))
        ..move(rayAt(panel, const Offset3d(1.5, 0.5, 0)));

      expect(log, ['front enter']);
    });

    test('a drop over nothing on any surface is not a drop', () {
      var accepts = 0;
      final source = Draggable3d<String>(data: 'photo', child: solid());
      final panel = plate(Row3d(children: <Layout3d>[source, solid()]));
      final zone = DragTarget3d<String>(
        onAccept: (_, _) => accepts++,
        child: solid(),
      );
      final dialog = plate(
        Padding3d(padding: const EdgeInsets3d.only(left: 1.0), child: zone),
      );
      final group = Layout3dPointerGroup()
        ..addSurface(panel)
        ..addSurface(dialog, zOrder: 1);
      addTearDown(group.dispose);

      group
        ..down(rayAt(panel, const Offset3d(0.5, 0.5, 0)))
        ..move(rayAt(panel, const Offset3d(1.5, 0.5, 0)))
        // Back over the half of the dialog that answers nothing, and over
        // nothing on the panel either.
        ..move(rayAt(panel, const Offset3d(0.5, 0.5, 0)))
        ..up(worldRay: rayAt(panel, const Offset3d(0.5, 0.5, 0)));

      expect(accepts, 0);
    });

    test('nothing a cross-surface drag does reaches the relayout path', () {
      final overlay = Overlay3d();
      final source = Draggable3d<String>(
        data: 'photo',
        dropDuration: Duration.zero,
        feedbackBuilder: (_) => TestBox(const Size3d(0.4, 0.4, 0)),
        child: solid(),
      );
      overlay.syncChildren(<Layout3d>[
        Row3d(children: <Layout3d>[source, solid()]),
      ]);
      final panel = plate(overlay);
      final dialog = plate(
        Padding3d(
          padding: const EdgeInsets3d.only(left: 1.0),
          child: DragTarget3d<String>(child: solid()),
        ),
      );
      final group = Layout3dPointerGroup()
        ..addSurface(panel)
        ..addSurface(dialog, zOrder: 1);
      addTearDown(group.dispose);

      group
        ..down(rayAt(panel, const Offset3d(0.5, 0.5, 0)))
        ..move(rayAt(panel, const Offset3d(0.9, 0.5, 0)));
      // The feedback going into the overlay is a layout pass, and it is the
      // panel's alone: the dialog is only ever hit-tested.
      expect(panel.needsFlush, isTrue);
      expect(dialog.needsFlush, isFalse);
      panel.flush();

      for (var i = 0; i <= 20; i++) {
        group.move(rayAt(panel, Offset3d(0.9 + i * 0.05, 0.5, 0)));
        expect(panel.needsFlush, isFalse, reason: 'move $i dirtied the panel');
        expect(
          dialog.needsFlush,
          isFalse,
          reason: 'move $i dirtied the dialog',
        );
      }
      group.up(worldRay: rayAt(panel, const Offset3d(1.9, 0.5, 0)));

      // And the removal is the second and last one, again on the panel only.
      expect(panel.needsFlush, isTrue);
      expect(dialog.needsFlush, isFalse);
    });
  });
  group('Dismissible3d', () {
    // A two-unit-wide row on the standard metrics: the touch slop is 18dp,
    // which is 0.18 units, and the default threshold of 0.4 is 0.8 of them.
    ({Layout3dSurface surface, Layout3dPointer pointer}) swiper(
      Dismissible3d row,
    ) {
      final surface = laidOut(
        row,
        constraints: Constraints3d.tight(const Size3d(2, 1, 0)),
      );
      addTearDown(surface.dispose);
      return (surface: surface, pointer: Layout3dPointer(surface));
    }

    test('a swipe past the threshold dismisses, the way it went', () {
      Dismiss3dDirection? dismissed;
      final row = Dismissible3d(
        movementDuration: Duration.zero,
        resizeDuration: null,
        onDismissed: (direction) => dismissed = direction,
        child: solid(const Size3d(2, 1, 0)),
      );
      final it = swiper(row);

      it.pointer
        ..down(rayAt(it.surface, const Offset3d(0.5, 0.5, 0)))
        ..move(rayAt(it.surface, const Offset3d(1.0, 0.5, 0)))
        ..move(rayAt(it.surface, const Offset3d(1.6, 0.5, 0)))
        ..up();

      expect(dismissed, Dismiss3dDirection.forward);
      expect(row.isDismissed, isTrue);
      expect(row.resizeFactor, 0.0);
    });

    test('a slow swipe under the threshold settles back', () {
      var dismissals = 0;
      final row = Dismissible3d(
        movementDuration: Duration.zero,
        resizeDuration: null,
        onDismissed: (_) => dismissals++,
        child: solid(const Size3d(2, 1, 0)),
      );
      final it = swiper(row);

      // Real timestamps, because the velocity estimate is what tells this
      // apart from a flick: half a unit over three hundred milliseconds is
      // 1.7 units a second, well under the 7 that 700dp/s comes to.
      it.pointer
        ..down(
          rayAt(it.surface, const Offset3d(0.5, 0.5, 0)),
          timeStamp: Duration.zero,
        )
        ..move(
          rayAt(it.surface, const Offset3d(0.7, 0.5, 0)),
          timeStamp: const Duration(milliseconds: 100),
        )
        ..move(
          rayAt(it.surface, const Offset3d(0.9, 0.5, 0)),
          timeStamp: const Duration(milliseconds: 200),
        )
        ..move(
          rayAt(it.surface, const Offset3d(1.0, 0.5, 0)),
          timeStamp: const Duration(milliseconds: 300),
        );
      expect(row.swipeOffset, closeTo(0.5, 1e-6));
      expect(row.progress, closeTo(0.25, 1e-6));

      it.pointer.up(timeStamp: const Duration(milliseconds: 320));

      expect(dismissals, 0);
      expect(row.swipeOffset, 0.0);
      expect(row.isDismissed, isFalse);
    });

    test('a flick dismisses whatever distance it covered', () {
      Dismiss3dDirection? dismissed;
      final row = Dismissible3d(
        movementDuration: Duration.zero,
        resizeDuration: null,
        onDismissed: (direction) => dismissed = direction,
        child: solid(const Size3d(2, 1, 0)),
      );
      final it = swiper(row);

      // The same half unit as the test above, in twelve milliseconds instead
      // of three hundred: forty units a second, which is a flick.
      it.pointer
        ..down(
          rayAt(it.surface, const Offset3d(1.5, 0.5, 0)),
          timeStamp: Duration.zero,
        )
        ..move(
          rayAt(it.surface, const Offset3d(1.3, 0.5, 0)),
          timeStamp: const Duration(milliseconds: 4),
        )
        ..move(
          rayAt(it.surface, const Offset3d(1.1, 0.5, 0)),
          timeStamp: const Duration(milliseconds: 8),
        )
        ..move(
          rayAt(it.surface, const Offset3d(1.0, 0.5, 0)),
          timeStamp: const Duration(milliseconds: 12),
        )
        ..up(timeStamp: const Duration(milliseconds: 13));

      expect(dismissed, Dismiss3dDirection.reverse);
    });

    test('a direction refuses the swipe that goes the other way', () {
      var dismissals = 0;
      final row = Dismissible3d(
        direction: Dismiss3dDirection.forward,
        movementDuration: Duration.zero,
        resizeDuration: null,
        onDismissed: (_) => dismissals++,
        child: solid(const Size3d(2, 1, 0)),
      );
      final it = swiper(row);

      it.pointer
        ..down(rayAt(it.surface, const Offset3d(1.5, 0.5, 0)))
        ..move(rayAt(it.surface, const Offset3d(1.0, 0.5, 0)))
        ..move(rayAt(it.surface, const Offset3d(0.4, 0.5, 0)))
        ..up();

      // Committed the way this row does not go: the pointer was left to
      // whatever else wanted it, and nothing moved.
      expect(row.isSwiping, isFalse);
      expect(row.swipeOffset, 0.0);
      expect(dismissals, 0);
    });

    test('an axis keeps a row and the list it is in out of each other way', () {
      final row = Dismissible3d(
        axis: Axis3d.vertical,
        movementDuration: Duration.zero,
        resizeDuration: null,
        child: solid(const Size3d(2, 1, 0)),
      );
      final it = swiper(row);

      it.pointer
        ..down(rayAt(it.surface, const Offset3d(0.5, 0.5, 0)))
        ..move(rayAt(it.surface, const Offset3d(1.9, 0.5, 0)));

      // A whole unit and more across, which is seven times the slop, and none
      // of it on the axis this row swipes along.
      expect(row.isSwiping, isFalse);
      expect(row.swipeOffset, 0.0);
      it.pointer.up();
    });

    test('the backgrounds show on the side the child came off', () {
      final background = TestBox(const Size3d(2, 1, 0));
      final secondary = TestBox(const Size3d(2, 1, 0));
      final row = Dismissible3d(
        movementDuration: Duration.zero,
        resizeDuration: null,
        background: background,
        secondaryBackground: secondary,
        child: solid(const Size3d(2, 1, 0)),
      );
      final it = swiper(row);

      // At rest neither is drawn, so neither fights the child for the depth
      // buffer, and `node.visible` costs no layout either way.
      expect(background.node.visible, isFalse);
      expect(secondary.node.visible, isFalse);

      it.pointer
        ..down(rayAt(it.surface, const Offset3d(1.0, 0.5, 0)))
        ..move(rayAt(it.surface, const Offset3d(1.5, 0.5, 0)));
      expect(background.node.visible, isTrue);
      expect(secondary.node.visible, isFalse);

      it.pointer.move(rayAt(it.surface, const Offset3d(0.5, 0.5, 0)));
      expect(background.node.visible, isFalse);
      expect(secondary.node.visible, isTrue);

      it.pointer.up();
      expect(background.node.visible, isFalse);
      expect(secondary.node.visible, isFalse);
    });

    test('the swipe is node-tier and only the resize is not', () {
      final row = Dismissible3d(
        movementDuration: Duration.zero,
        resizeDuration: null,
        child: solid(const Size3d(2, 1, 0)),
      );
      final it = swiper(row);
      expect(it.surface.needsFlush, isFalse);

      it.pointer.down(rayAt(it.surface, const Offset3d(0.2, 0.5, 0)));
      for (var i = 0; i <= 20; i++) {
        it.pointer.move(rayAt(it.surface, Offset3d(0.4 + i * 0.05, 0.5, 0)));
        expect(row.swipeOffset, greaterThan(0.0));
        expect(it.surface.needsFlush, isFalse, reason: 'move $i laid out');
      }

      // The dismissal is the one thing here that genuinely changes an extent,
      // and an extent that changed is a relayout. That is the whole reason
      // this one animation is on the implicit tier.
      it.pointer.up();
      expect(it.surface.needsFlush, isTrue);

      it.surface.flush();
      expect(row.size.width, 0.0);
    });

    test('a refused confirmation puts the row back', () async {
      var dismissals = 0;
      var asked = 0;
      final row = Dismissible3d(
        movementDuration: Duration.zero,
        resizeDuration: null,
        confirmDismiss: (_) async {
          asked++;
          return false;
        },
        onDismissed: (_) => dismissals++,
        child: solid(const Size3d(2, 1, 0)),
      );
      final it = swiper(row);

      it.pointer
        ..down(rayAt(it.surface, const Offset3d(0.2, 0.5, 0)))
        ..move(rayAt(it.surface, const Offset3d(0.6, 0.5, 0)))
        ..move(rayAt(it.surface, const Offset3d(1.6, 0.5, 0)))
        ..up();
      // The row waits off to one side while the question is open, which is
      // what makes the confirmation worth awaiting at all.
      expect(row.swipeOffset, closeTo(2.0, 1e-6));

      await Future<void>.delayed(Duration.zero);

      expect(asked, 1);
      expect(dismissals, 0);
      expect(row.swipeOffset, 0.0);
      expect(row.isDismissed, isFalse);
    });

    test('a dismissed row can be put back', () {
      final row = Dismissible3d(
        movementDuration: Duration.zero,
        resizeDuration: null,
        child: solid(const Size3d(2, 1, 0)),
      );
      final it = swiper(row);

      it.pointer
        ..down(rayAt(it.surface, const Offset3d(0.2, 0.5, 0)))
        ..move(rayAt(it.surface, const Offset3d(1.6, 0.5, 0)))
        ..up();
      it.surface.flush();
      expect(row.size.width, 0.0);

      row.reset();
      it.surface.flush();

      expect(row.isDismissed, isFalse);
      expect(row.size.width, 2.0);
      expect(row.child!.node.visible, isTrue);
    });

    test(
      'a horizontal row and the list it is in each claim their own axis',
      () {
        final controller = Scroll3dController();
        addTearDown(controller.dispose);
        final row = Dismissible3d(
          movementDuration: Duration.zero,
          resizeDuration: null,
          child: solid(),
        );
        final list = ListView3d(
          controller: controller,
          children: <Layout3d>[
            row,
            TestBox(const Size3d(1, 4, 0), pointable: true),
          ],
        );
        final surface = laidOut(
          list,
          constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
        );
        addTearDown(surface.dispose);
        final pointer = Layout3dPointer(surface);

        // Down the list, which is not the row's axis: entering the arena still
        // marked the sequence contested, so the view waited for the slop rather
        // than scrolling out from under a swipe that never came.
        pointer
          ..down(rayAt(surface, const Offset3d(0.5, 0.5, 0)))
          ..move(rayAt(surface, const Offset3d(0.5, 0.1, 0)));
        expect(row.isSwiping, isFalse);
        expect(controller.offset, greaterThan(0.0));
        pointer.up();

        // Across it, which is: the row claims the pointer and the list is left
        // where it was.
        final scrolled = controller.offset;
        pointer
          ..down(rayAt(surface, const Offset3d(0.5, 0.5, 0)))
          ..move(rayAt(surface, const Offset3d(0.9, 0.5, 0)));
        expect(row.isSwiping, isTrue);
        expect(controller.offset, scrolled);
        pointer.up();
      },
    );

    testWidgets('a row disposed mid-swipe stops what it was running', (
      tester,
    ) async {
      var dismissals = 0;
      final row = Dismissible3d(
        onDismissed: (_) => dismissals++,
        child: solid(const Size3d(2, 1, 0)),
      );
      final surface = laidOut(
        row,
        constraints: Constraints3d.tight(const Size3d(2, 1, 0)),
      );
      final pointer = Layout3dPointer(surface);

      pointer
        ..down(rayAt(surface, const Offset3d(0.2, 0.5, 0)))
        ..move(rayAt(surface, const Offset3d(1.6, 0.5, 0)))
        ..up();

      // A fly-out is running, which is a scheduler callback the row holds.
      // Tearing the tree down has to let go of it: a ticker left behind fails
      // the test binding, and would go on animating a disposed box.
      surface.dispose();
      await tester.pump(const Duration(milliseconds: 400));

      expect(dismissals, 0);
    });
  });

  group('a dismissal under a clock', () {
    testWidgets('flies out, then closes the gap it left', (tester) async {
      Dismiss3dDirection? dismissed;
      var resizes = 0;
      final row = Dismissible3d(
        movementDuration: const Duration(milliseconds: 200),
        resizeDuration: const Duration(milliseconds: 300),
        onResize: () => resizes++,
        onDismissed: (direction) => dismissed = direction,
        child: solid(const Size3d(2, 1, 0)),
      );
      final surface = laidOut(
        row,
        constraints: Constraints3d.tight(const Size3d(2, 1, 0)),
      );
      addTearDown(surface.dispose);
      final pointer = Layout3dPointer(surface);

      pointer
        ..down(rayAt(surface, const Offset3d(0.2, 0.5, 0)))
        ..move(rayAt(surface, const Offset3d(0.6, 0.5, 0)))
        ..move(rayAt(surface, const Offset3d(1.4, 0.5, 0)))
        ..up();

      // The fly-out is a tween on the node tier, so the box is still its full
      // size and nothing has been laid out again.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(row.swipeOffset, greaterThan(1.2));
      expect(row.swipeOffset, lessThan(2.0));
      expect(surface.needsFlush, isFalse, reason: 'the fly-out is node-tier');
      expect(dismissed, isNull);

      // The fly-out finishes, which is what arms the resize — the one
      // animation here that has to relayout, because the extent really is
      // changing.
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 100));
      expect(row.resizeFactor, lessThan(1.0));
      expect(surface.needsFlush, isTrue);
      surface.flush();
      expect(row.size.width, lessThan(2.0));
      expect(row.size.width, greaterThan(0.0));
      expect(resizes, greaterThan(0));

      await tester.pump(const Duration(milliseconds: 400));
      surface.flush();
      expect(dismissed, Dismiss3dDirection.forward);
      expect(row.size.width, 0.0);
    });
  });

  group('the widget form of a dismissible', () {
    testWidgets('mirrors its three slots onto the layout', (tester) async {
      final parent = Node();
      final controller = Layout3dController();
      var dismissals = 0;

      Widget frame(Dismiss3dDirection direction) => SceneLayout3d(
        parent: parent,
        size: const Size3d(2, 1, 0),
        controller: controller,
        child: SceneDismissible3d(
          direction: direction,
          movementDuration: Duration.zero,
          resizeDuration: null,
          onDismissed: (_) => dismissals++,
          background: const SceneSizedBox3d(width: 2, height: 1),
          child: const SceneSizedBox3d(width: 2, height: 1),
        ),
      );

      await tester.pumpWidget(frame(Dismiss3dDirection.forward));
      final row = controller.surface!.child! as Dismissible3d;
      expect(row.direction, Dismiss3dDirection.forward);
      expect(row.child, isNotNull);
      expect(row.background, isNotNull);
      expect(row.secondaryBackground, isNull);

      // A rebuild reconciles onto the same layout object and writes the new
      // properties through, slots included.
      await tester.pumpWidget(frame(Dismiss3dDirection.both));
      expect(controller.surface!.child!, same(row));
      expect(row.direction, Dismiss3dDirection.both);

      final surface = controller.surface!;
      final pointer = Layout3dPointer(surface);
      pointer
        ..down(rayAt(surface, const Offset3d(0.2, 0.5, 0)))
        ..move(rayAt(surface, const Offset3d(1.6, 0.5, 0)))
        ..up();

      expect(dismissals, 1);
    });
  });
}
