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
}
