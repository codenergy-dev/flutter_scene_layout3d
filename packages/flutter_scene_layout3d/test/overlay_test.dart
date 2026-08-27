// Overlays: what "in front" means on a plane, the barrier that stops a ray
// short of what is behind it, and the route stack over both.

import 'dart:math' as math;

import 'package:flutter/widgets.dart' show Builder, FocusManager, SizedBox;
import 'package:flutter_scene/scene.dart' show Node, PerspectiveCamera;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart'
    show
        Layout3dController,
        Overlay3dController,
        SceneLayout3d,
        SceneOverlay3d,
        SceneSizedBox3d;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Quaternion, Vector3;

import 'support.dart';

/// Applies whatever focus change was asked for, which the manager otherwise
/// does on a microtask of its own.
void settleFocus() => FocusManager.instance.applyFocusChangesIfNeeded();

/// A camera in front of the plane, on the `+z` side, which is the side
/// [LayoutBasis3d.xy] puts the viewer on.
PerspectiveCamera frontCamera({double distance = 5}) => PerspectiveCamera(
  position: Vector3(0, 0, distance),
  target: Vector3(0, 0, 0),
);

/// The rotation part of [transform], as a flat list, rounded.
List<double> rotationOf(Matrix4 transform) => <double>[
  for (var column = 0; column < 3; column++)
    for (var row = 0; row < 3; row++)
      double.parse(transform.entry(row, column).toStringAsFixed(6)),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    FocusManager.instance.primaryFocus?.unfocus();
    settleFocus();
  });

  ({Layout3dSurface surface, Overlay3d overlay, TestBox page}) panel({
    Size3d size = const Size3d(4, 3, 0.5),
    Alignment3d alignment = Alignment3d.center,
  }) {
    final page = TestBox(size, pointable: true, name: 'page');
    final overlay = Overlay3d(alignment: alignment, children: <Layout3d>[page]);
    final surface = laidOut(overlay, constraints: Constraints3d.tight(size));
    addTearDown(surface.dispose);
    return (surface: surface, overlay: overlay, page: page);
  }

  group('entries', () {
    test('an entry inserted from a descendant is in front of every sibling', () {
      final host = panel();
      // The insertion a component makes: it has a box deep in the tree and no
      // handle, and finds the overlay by walking up from it.
      final found = Overlay3d.of(host.page);
      expect(found, same(host.overlay));

      final dialog = TestBox(const Size3d(1, 1, 0), pointable: true);
      final entry = Overlay3dEntry(builder: (_) => dialog);
      found!.insertEntry(entry);
      host.surface.flush();

      expect(host.overlay.entries, <Overlay3dEntry>[entry]);
      // Dead centre, where the page and the dialog overlap: the entry answers.
      final hit = host.surface.hitTestAt(const Offset3d(2, 1.5, 0));
      expect(hit.target, same(dialog));
      // And the page is still on the path behind it, since a ray that reached
      // the dialog passed through the overlay, not through the page.
      expect(hit.firstOf<Overlay3d>(), same(host.overlay));
    });

    test('entries stack in order, and can be inserted around each other', () {
      final host = panel();
      final first = Overlay3dEntry(
        builder: (_) => TestBox(const Size3d(1, 1, 0)),
      );
      final second = Overlay3dEntry(
        builder: (_) => TestBox(const Size3d(1, 1, 0)),
      );
      final third = Overlay3dEntry(
        builder: (_) => TestBox(const Size3d(1, 1, 0)),
      );

      host.overlay
        ..insertEntry(first)
        ..insertEntry(third)
        ..insertEntry(second, below: third);

      expect(host.overlay.entries, <Overlay3dEntry>[first, second, third]);

      host.overlay.rearrangeEntries(<Overlay3dEntry>[third, second, first]);
      expect(host.overlay.entries, <Overlay3dEntry>[third, second, first]);

      host.overlay.removeEntry(second);
      expect(host.overlay.entries, <Overlay3dEntry>[third, first]);
      expect(second.isInserted, isFalse);
      expect(second.content, isNull);
    });

    test('the base children survive the entries coming and going', () {
      final host = panel();
      final entry = Overlay3dEntry(
        builder: (_) => TestBox(const Size3d(1, 1, 0)),
      );

      host.overlay.insertEntry(entry);
      expect(host.overlay.children.first, same(host.page));
      expect(host.overlay.children.length, 2);

      host.overlay.removeEntry(entry);
      expect(host.overlay.children, <Layout3d>[host.page]);
    });

    test('removing an entry disposes what it built', () {
      final host = panel();
      final dialog = TestBox(const Size3d(1, 1, 0));
      final entry = Overlay3dEntry(builder: (_) => dialog);
      host.overlay.insertEntry(entry);
      host.surface.flush();

      host.overlay.removeEntry(entry);
      expect(dialog.debugDisposed, isTrue);
    });

    test('markNeedsBuild swaps the content in place', () {
      final host = panel();
      var built = 0;
      final boxes = <TestBox>[];
      final entry = Overlay3dEntry(
        builder: (_) {
          built++;
          final box = TestBox(const Size3d(1, 1, 0));
          boxes.add(box);
          return box;
        },
      );
      host.overlay.insertEntry(entry);
      host.surface.flush();
      expect(built, 1);

      entry.markNeedsBuild();
      host.surface.flush();

      expect(built, 2);
      expect(boxes.first.debugDisposed, isTrue);
      expect(entry.content, same(boxes.last));
      expect(boxes.last.layoutCount, greaterThan(0));
    });
  });

  group('the lift', () {
    test('moves the geometry and leaves the box where it was', () {
      final host = panel();
      final dialog = TestBox(const Size3d(1, 1, 0));
      final entry = Overlay3dEntry(builder: (_) => dialog);
      host.overlay.insertEntry(entry);
      host.surface.flush();

      final entryHost = dialog.parent!;
      final lift = Layout3dMetrics.standard.dp(Overlay3d.defaultLift);

      // The box is where a centred stack child goes, inside the overlay.
      expect(entryHost.size, const Size3d(1, 1, 0));
      expect(entryHost.offset, const Offset3d(1.5, 1, 0.25));
      // The node is that, pulled toward the viewer.
      expect(
        rounded(translationOf(entryHost)),
        rounded(Offset3d(1.5, 1, 0.25 - lift)),
      );
      expect(lift, greaterThan(0));
    });

    test('an explicit lift overrides the one taken from the metrics', () {
      final host = panel();
      final dialog = TestBox(const Size3d(1, 1, 0));
      final entry = Overlay3dEntry(
        layer: const OverlayLayer3d.inPlane(lift: 0.2),
        builder: (_) => dialog,
      );
      host.overlay.insertEntry(entry);
      host.surface.flush();

      expect(translationOf(dialog.parent!).z, closeTo(0.05, 1e-9));
    });

    test('a pin inside a lifted entry still lands where it was pinned', () {
      final host = panel();
      final pinned = TestBox(const Size3d(1, 1, 0));
      late final Stack3d inner;
      final entry = Overlay3dEntry(
        builder: (_) => inner = Stack3d(
          children: <Layout3d>[
            Positioned3d(right: 0, bottom: 0, child: pinned),
          ],
        ),
      );
      host.overlay.insertEntry(entry);
      host.surface.flush();

      // The stack fills the overlay, and the pin is against its far corner:
      // the lift moved the geometry, and layout never heard about it.
      expect(inner.size, const Size3d(4, 3, 0.5));
      // The pin is the Positioned3d wrapping the box, which is what the
      // stack placed.
      expect(pinned.parent!.offset, const Offset3d(3, 2, 0));
      expect(pinned.hasSize, isTrue);
    });

    test('a ray reaches the entry at the box, not at the lifted geometry', () {
      final host = panel();
      final dialog = TestBox(const Size3d(1, 1, 0), pointable: true);
      final entry = Overlay3dEntry(
        layer: const OverlayLayer3d.inPlane(lift: 0.2),
        builder: (_) => dialog,
      );
      host.overlay.insertEntry(entry);
      host.surface.flush();

      final hit = host.surface.hitTestAt(const Offset3d(2, 1.5, 0.25));
      expect(hit.target, same(dialog));
      // Where the ray met it, in the entry's own frame: the middle of the box
      // the overlay placed, not a quarter of a unit in front of it.
      expect(
        rounded(hit.targetEntry!.localPosition),
        const Offset3d(0.5, 0.5, 0),
      );
    });
  });

  group('the barrier', () {
    ({
      Layout3dSurface surface,
      Overlay3d overlay,
      TestBox page,
      TestBox dialog,
      Overlay3dEntry entry,
      List<int> dismissals,
    })
    modal({bool dismissible = true}) {
      final host = panel();
      final dialog = TestBox(const Size3d(1, 1, 0), pointable: true);
      final dismissals = <int>[];
      final entry = Overlay3dEntry(
        modal: true,
        dismissible: dismissible,
        onDismiss: () => dismissals.add(1),
        builder: (_) => dialog,
      );
      host.overlay.insertEntry(entry);
      host.surface.flush();
      return (
        surface: host.surface,
        overlay: host.overlay,
        page: host.page,
        dialog: dialog,
        entry: entry,
        dismissals: dismissals,
      );
    }

    test('it absorbs a ray aimed at the content behind it', () {
      final control = modal();

      // Away from the dialog, over the page: the barrier answers instead.
      final hit = control.surface.hitTestAt(const Offset3d(0.2, 0.2, 0));
      expect(hit.target, isA<ModalBarrier3d>());
      expect(hit.firstOf<TestBox>(), isNull);
    });

    test('a tap outside dismisses, and a tap inside does not', () {
      final control = modal();
      final pointer = Layout3dPointer(control.surface);

      pointer.down(rayAt(control.surface, const Offset3d(0.2, 0.2, 0)));
      pointer.up();
      expect(control.dismissals, hasLength(1));

      pointer.down(rayAt(control.surface, const Offset3d(2, 1.5, 0)));
      pointer.up();
      expect(control.dismissals, hasLength(1));
    });

    test('an inert barrier still swallows the press', () {
      final control = modal(dismissible: false);
      final pointer = Layout3dPointer(control.surface);

      pointer.down(rayAt(control.surface, const Offset3d(0.2, 0.2, 0)));
      pointer.up();

      expect(control.dismissals, isEmpty);
      expect(pointer.lastHit.target, isA<ModalBarrier3d>());
    });

    test('it fills the overlay and is as deep as it was told to be', () {
      final host = panel();
      final barrier = ModalBarrier3d(thickness: 0.1);
      final entry = Overlay3dEntry(builder: (_) => barrier);
      host.overlay.insertEntry(entry);
      host.surface.flush();

      expect(barrier.size, const Size3d(4, 3, 0.1));
    });

    test('a scrim is geometry inside the barrier, sized to it', () {
      final host = panel();
      final scrim = TestBox(const Size3d(0.1, 0.1, 0));
      final entry = Overlay3dEntry(
        modal: true,
        scrimBuilder: (_) => scrim,
        builder: (_) => TestBox(const Size3d(1, 1, 0)),
      );
      host.overlay.insertEntry(entry);
      host.surface.flush();

      expect(scrim.size, const Size3d(4, 3, 0));
    });
  });

  group('detached entries', () {
    test('an entry gets a surface of its own, constrained by the host', () {
      final host = panel();
      final dialog = TestBox(const Size3d(1, 1, 0), pointable: true);
      final entry = Overlay3dEntry(
        layer: const OverlayLayer3d.detached(),
        builder: (_) => dialog,
      );
      host.overlay.insertEntry(entry);
      host.surface.flush();

      final detached = entry.surface!;
      expect(detached.size, const Size3d(1, 1, 0));
      expect(detached.configuration.maxWidth, 4);
      expect(detached.configuration.maxHeight, 3);
      // Unbounded in depth: escaping the panel's thickness is half the reason
      // to detach at all.
      expect(detached.configuration.maxDepth, double.infinity);
      expect(host.overlay.detachedSurfaces, <Layout3dSurface>[detached]);

      // The entry is not reachable through the host surface at all; it is a
      // surface of its own, and the router is what finds it.
      expect(
        host.surface.hitTestAt(const Offset3d(2, 1.5, 0)).target,
        same(host.page),
      );
      expect(
        detached.hitTestAt(const Offset3d(0.5, 0.5, 0)).target,
        same(dialog),
      );
    });

    test('it may overhang the panel, which an in-plane entry cannot', () {
      final host = panel();
      final wide = TestBox(const Size3d(6, 1, 0));
      final entry = Overlay3dEntry(
        layer: const OverlayLayer3d.detached(constraints: Constraints3d()),
        builder: (_) => wide,
      );
      host.overlay.insertEntry(entry);
      host.surface.flush();

      expect(wide.size.width, 6);
      expect(entry.surface!.size.width, 6);
    });

    test('the overlay is still found from inside a detached entry', () {
      final host = panel();
      final inside = TestBox(const Size3d(1, 1, 0));
      final entry = Overlay3dEntry(
        layer: const OverlayLayer3d.detached(),
        builder: (_) => inside,
      );
      host.overlay.insertEntry(entry);
      host.surface.flush();

      expect(Overlay3d.of(inside), same(host.overlay));
    });

    test('it follows the panel when the panel turns', () {
      final host = panel();
      final entry = Overlay3dEntry(
        layer: const OverlayLayer3d.detached(offset: Offset3d(1, 0, 0)),
        builder: (_) => TestBox(const Size3d(1, 1, 0)),
      );
      host.overlay.insertEntry(entry);
      host.surface.flush();

      final before = scenePositionOf(entry.surface!.plane);
      // Layout x runs to scene -x through the default basis.
      expect(before.x, closeTo(-1, 1e-9));

      host.surface.plane.rotation = Quaternion.axisAngle(
        Vector3(0, 1, 0),
        math.pi,
      );
      final after = scenePositionOf(entry.surface!.plane);
      expect(after.x, closeTo(1, 1e-6));
    });

    test('a bound entry keeps facing the camera when the panel turns', () {
      final host = panel();
      final camera = frontCamera();
      final entry = Overlay3dEntry(
        layer: const OverlayLayer3d.detached(
          offset: Offset3d(1, 0, 0),
          binding: Layout3dCameraBinding.billboard(),
        ),
        builder: (_) => TestBox(const Size3d(1, 1, 0)),
      );
      host.overlay.insertEntry(entry);
      host.surface.flush();
      host.overlay.updateCameraBindings(camera: camera);

      final facing = rotationOf(entry.surface!.plane.globalTransform);
      final anchored = scenePositionOf(entry.surface!.plane).clone();

      host.surface.plane.rotation = Quaternion.axisAngle(
        Vector3(0, 1, 0),
        math.pi / 3,
      );
      host.overlay.updateCameraBindings(camera: camera);

      // The panel turned; the entry did not.
      expect(rotationOf(entry.surface!.plane.globalTransform), facing);
      // And it is still where the panel anchored it, which did turn: the
      // same distance from the panel's origin, in a different direction.
      final position = scenePositionOf(entry.surface!.plane);
      expect(position.x, isNot(closeTo(anchored.x, 1e-3)));
      expect(position.length, closeTo(anchored.length, 1e-6));
    });

    test('the unit contract reaches the entry from the host', () {
      final host = panel();
      final inside = DpBox(48, 48);
      final entry = Overlay3dEntry(
        layer: const OverlayLayer3d.detached(),
        builder: (_) => inside,
      );
      host.overlay.insertEntry(entry);
      host.surface.flush();

      expect(inside.size.width, closeTo(0.48, 1e-9));

      host.surface.metrics = const Layout3dMetrics(unitsPerLogicalPixel: 0.02);
      host.surface.flush();

      expect(entry.surface!.metrics.unitsPerLogicalPixel, 0.02);
      expect(inside.size.width, closeTo(0.96, 1e-9));
    });

    test('dirt inside a detached entry reaches the host flush', () {
      var updates = 0;
      final page = TestBox(const Size3d(4, 3, 0.5));
      final overlay = Overlay3d(children: <Layout3d>[page]);
      final surface = Layout3dSurface(
        constraints: Constraints3d.tight(const Size3d(4, 3, 0.5)),
        onNeedVisualUpdate: () => updates++,
        child: overlay,
      );
      addTearDown(surface.dispose);
      surface.flush();

      final inside = TestBox(const Size3d(1, 1, 0));
      final entry = Overlay3dEntry(
        layer: const OverlayLayer3d.detached(),
        builder: (_) => inside,
      );
      overlay.insertEntry(entry);
      surface.flush();
      updates = 0;

      inside.preferred = const Size3d(2, 2, 0);
      expect(updates, greaterThan(0));
      expect(surface.needsFlush, isTrue);

      surface.flush();
      expect(inside.size, const Size3d(2, 2, 0));
    });

    test('removing a detached entry disposes its surface and its content', () {
      final host = panel();
      final inside = TestBox(const Size3d(1, 1, 0));
      final entry = Overlay3dEntry(
        layer: const OverlayLayer3d.detached(),
        builder: (_) => inside,
      );
      host.overlay.insertEntry(entry);
      host.surface.flush();
      final detached = entry.surface!;

      host.overlay.removeEntry(entry);

      expect(entry.surface, isNull);
      expect(inside.debugDisposed, isTrue);
      expect(detached.debugDisposed, isTrue);
      expect(host.overlay.detachedSurfaces, isEmpty);
    });
  });

  group('routing a ray across surfaces', () {
    ({Layout3dSurface surface, TestBox content}) plate(String name) {
      final content = TestBox(
        const Size3d(1, 1, 0),
        pointable: true,
        name: name,
      );
      final surface = laidOut(
        content,
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      addTearDown(surface.dispose);
      return (surface: surface, content: content);
    }

    test(
      'the front surface answers, and the back one only when it is gone',
      () {
        final back = plate('back');
        final front = plate('front');
        final group = Layout3dPointerGroup()
          ..addSurface(back.surface)
          ..addSurface(front.surface, zOrder: 1);
        addTearDown(group.dispose);

        expect(group.surfaces, <Layout3dSurface>[front.surface, back.surface]);

        final hit = group.hitTest(
          rayAt(front.surface, const Offset3d(0.5, 0.5, 0)),
        );
        expect(hit.target, same(front.content));

        group.removeSurface(front.surface);

        final second = group.hitTest(
          rayAt(back.surface, const Offset3d(0.5, 0.5, 0)),
        );
        expect(second.target, same(back.content));
      },
    );

    test('a press is captured by the surface that answered it', () {
      final back = plate('back');
      final front = plate('front');
      final group = Layout3dPointerGroup()
        ..addSurface(back.surface)
        ..addSurface(front.surface, zOrder: 1);
      addTearDown(group.dispose);

      group.down(rayAt(front.surface, const Offset3d(0.5, 0.5, 0)));

      expect(group.capturedBy(0), <Layout3dSurface>[front.surface]);
      expect(group.pointerFor(front.surface)!.isDown(0), isTrue);
      expect(group.pointerFor(back.surface)!.isDown(0), isFalse);

      group.up();
      expect(group.capturedBy(0), isEmpty);
    });

    test('a surface that does not absorb lets the walk carry on', () {
      final back = plate('back');
      final front = plate('front');
      final group = Layout3dPointerGroup()
        ..addSurface(back.surface)
        ..addSurface(front.surface, zOrder: 1, absorbs: false);
      addTearDown(group.dispose);

      group.down(rayAt(front.surface, const Offset3d(0.5, 0.5, 0)));

      expect(group.capturedBy(0), <Layout3dSurface>[
        front.surface,
        back.surface,
      ]);
    });

    test('the camera breaks a tie between equal z-orders', () {
      final near = plate('near');
      final far = plate('far');
      near.surface.plane.position = Vector3(0, 0, 2);
      far.surface.plane.position = Vector3(0, 0, -2);
      final group = Layout3dPointerGroup(camera: frontCamera())
        ..addSurface(far.surface)
        ..addSurface(near.surface);
      addTearDown(group.dispose);

      expect(group.surfaces.first, same(near.surface));

      group.camera = frontCamera(distance: -5);
      expect(group.surfaces.first, same(far.surface));
    });

    test('an overlay hands its detached entries to the group', () {
      final host = panel();
      final group = Layout3dPointerGroup()..addSurface(host.surface);
      addTearDown(group.dispose);

      final dialog = TestBox(const Size3d(1, 1, 0), pointable: true);
      final entry = Overlay3dEntry(
        layer: const OverlayLayer3d.detached(),
        builder: (_) => dialog,
      );
      host.overlay.insertEntry(entry);
      host.surface.flush();
      group.syncDetachedEntries(host.overlay);

      expect(group.surfaces.first, same(entry.surface));
      final hit = group.hitTest(
        rayAt(entry.surface!, const Offset3d(0.5, 0.5, 0)),
      );
      expect(hit.target, same(dialog));

      host.overlay.removeEntry(entry);
      group.syncDetachedEntries(host.overlay);

      expect(group.surfaces, <Layout3dSurface>[host.surface]);
    });

    test('hover goes to the front surface and leaves the others', () {
      final back = plate('back');
      final front = plate('front');
      final group = Layout3dPointerGroup()
        ..addSurface(back.surface)
        ..addSurface(front.surface, zOrder: 1);
      addTearDown(group.dispose);

      group.hover(rayAt(back.surface, const Offset3d(0.5, 0.5, 0)));

      expect(group.pointerFor(front.surface)!.hoveredFor(0), isNotEmpty);
      expect(group.pointerFor(back.surface)!.hoveredFor(0), isEmpty);
    });
  });

  group('focus', () {
    test('a modal entry traps focus in a scope of its own', () {
      final host = panel();
      final background = Focus3d(child: TestBox(const Size3d(1, 1, 0)));
      host.overlay.add(background);
      host.surface.flush();

      final inside = Focus3d(child: TestBox(const Size3d(1, 1, 0)));
      final entry = Overlay3dEntry(modal: true, builder: (_) => inside);
      host.overlay.insertEntry(entry);
      host.surface.flush();

      expect(entry.focusScope, isNotNull);
      expect(inside.enclosingScope, same(entry.focusScope!.scopeNode));
      expect(background.enclosingScope, same(host.surface.owner!.focusScope));
      expect(Focus3dTraversal.traversalRootFor(inside), same(entry.focusScope));
      expect(Focus3dTraversal.traversalRootFor(background), same(host.surface));
    });

    test('traversal from inside a modal stays inside it', () {
      final host = panel();
      final background = Focus3d(child: TestBox(const Size3d(1, 1, 0)));
      host.overlay.add(background);

      final first = Focus3d(child: TestBox(const Size3d(1, 1, 0)));
      final second = Focus3d(child: TestBox(const Size3d(1, 1, 0)));
      final entry = Overlay3dEntry(
        modal: true,
        builder: (_) => Column3d(children: <Layout3d>[first, second]),
      );
      host.overlay.insertEntry(entry);
      host.surface.flush();

      const traversal = Focus3dTraversal();
      final root = Focus3dTraversal.traversalRootFor(first);
      expect(traversal.next(root, first), same(second));
      // And round again, rather than out into the page behind.
      expect(traversal.next(root, second), same(first));
    });

    test('pushing and popping restores focus', () async {
      final host = panel();
      final background = Focus3d(child: TestBox(const Size3d(1, 1, 0)));
      host.overlay.add(background);
      host.surface.flush();

      background.requestFocus();
      settleFocus();
      expect(background.hasPrimaryFocus, isTrue);

      final navigator = Navigator3d(host.overlay);
      final inside = Focus3d(
        autofocus: true,
        child: TestBox(const Size3d(1, 1, 0)),
      );
      final popped = navigator.push(
        PageRoute3d<String>(builder: (_) => inside),
      );
      host.surface.flush();
      settleFocus();

      expect(inside.hasPrimaryFocus, isTrue);
      expect(background.hasPrimaryFocus, isFalse);

      navigator.pop('answer');
      settleFocus();

      expect(background.hasPrimaryFocus, isTrue);
      expect(await popped, 'answer');
    });
  });

  group('the route stack', () {
    test('a push shows a route and a pop completes its future', () async {
      final host = panel();
      final navigator = Navigator3d(host.overlay);
      final dialog = TestBox(const Size3d(1, 1, 0), pointable: true);

      final popped = navigator.push(PageRoute3d<int>(builder: (_) => dialog));
      host.surface.flush();

      expect(navigator.canPop, isTrue);
      expect(host.overlay.entries, hasLength(1));
      expect(
        host.surface.hitTestAt(const Offset3d(2, 1.5, 0)).target,
        same(dialog),
      );

      expect(navigator.pop(7), isTrue);
      expect(await popped, 7);
      expect(host.overlay.entries, isEmpty);
      expect(navigator.canPop, isFalse);
      expect(navigator.pop(), isFalse);
    });

    test('a tap on the barrier pops the route', () async {
      final host = panel();
      final navigator = Navigator3d(host.overlay);
      final popped = navigator.push(
        PageRoute3d<String>(
          builder: (_) => TestBox(const Size3d(1, 1, 0), pointable: true),
        ),
      );
      host.surface.flush();

      final pointer = Layout3dPointer(host.surface);
      pointer.down(rayAt(host.surface, const Offset3d(0.2, 0.2, 0)));
      pointer.up();

      expect(await popped, isNull);
      expect(host.overlay.entries, isEmpty);
    });

    test('a route pops itself, wherever it is on the stack', () async {
      final host = panel();
      final navigator = Navigator3d(host.overlay);
      final under = PageRoute3d<int>(
        builder: (_) => TestBox(const Size3d(1, 1, 0)),
      );
      final over = PageRoute3d<int>(
        builder: (_) => TestBox(const Size3d(1, 1, 0)),
      );
      final first = navigator.push(under);
      navigator.push(over);
      host.surface.flush();

      expect(navigator.currentRoute, same(over));
      expect(under.pop(3), isTrue);

      expect(await first, 3);
      expect(navigator.routes, <Route3d<Object?>>[over]);
      expect(host.overlay.entries, hasLength(1));
    });

    test(
      'the transition hook runs, and the entry outlives the reverse',
      () async {
        final host = panel();
        final events = <String>[];
        final navigator = Navigator3d(
          host.overlay,
          transition: _RecordingTransition(events, host.overlay),
        );

        final popped = navigator.push(
          PageRoute3d<void>(builder: (_) => TestBox(const Size3d(1, 1, 0))),
        );
        await Future<void>.delayed(Duration.zero);
        expect(events, <String>['forward:1']);

        navigator.pop();
        await popped;

        // One entry still in the overlay while the reverse ran, none after.
        expect(events, <String>['forward:1', 'reverse:1']);
        expect(host.overlay.entries, isEmpty);
      },
    );

    test('a control deep inside a route finds the navigator', () {
      final host = panel();
      final navigator = Navigator3d(host.overlay);
      final inside = TestBox(const Size3d(1, 1, 0));
      navigator.push(PageRoute3d<void>(builder: (_) => inside));
      host.surface.flush();

      expect(Navigator3d.of(inside), same(navigator));
    });

    test('popUntil and popAll unwind the stack', () async {
      final host = panel();
      final navigator = Navigator3d(host.overlay);
      final bottom = PageRoute3d<void>(
        builder: (_) => TestBox(const Size3d(1, 1, 0)),
      );
      navigator.push(bottom);
      navigator.push(
        PageRoute3d<void>(builder: (_) => TestBox(const Size3d(1, 1, 0))),
      );
      navigator.push(
        PageRoute3d<void>(builder: (_) => TestBox(const Size3d(1, 1, 0))),
      );

      navigator.popUntil((route) => identical(route, bottom));
      expect(navigator.routes, <Route3d<Object?>>[bottom]);

      navigator.popAll();
      expect(navigator.routes, isEmpty);
      expect(host.overlay.entries, isEmpty);
    });
  });

  group('the declarative layer', widgetTests);

  group('teardown', () {
    test('disposing the surface takes the entries with it', () {
      final page = TestBox(const Size3d(4, 3, 0.5));
      final overlay = Overlay3d(children: <Layout3d>[page]);
      final surface = Layout3dSurface(
        constraints: Constraints3d.tight(const Size3d(4, 3, 0.5)),
        child: overlay,
      );
      final inPlane = TestBox(const Size3d(1, 1, 0));
      final detached = TestBox(const Size3d(1, 1, 0));
      overlay
        ..insertEntry(Overlay3dEntry(builder: (_) => inPlane))
        ..insertEntry(
          Overlay3dEntry(
            layer: const OverlayLayer3d.detached(),
            builder: (_) => detached,
          ),
        );
      surface.flush();

      surface.dispose();

      expect(inPlane.debugDisposed, isTrue);
      expect(detached.debugDisposed, isTrue);
      expect(overlay.entries, isEmpty);
    });
  });
}

/// A transition that records when it ran, and how much was still in the
/// overlay at the time.
class _RecordingTransition extends Route3dTransition {
  _RecordingTransition(this.events, this.overlay);

  final List<String> events;
  final Overlay3d overlay;

  @override
  Future<void> forward(Route3d<Object?> route) async {
    await Future<void>.delayed(Duration.zero);
    events.add('forward:${overlay.entries.length}');
  }

  @override
  Future<void> reverse(Route3d<Object?> route) async {
    await Future<void>.delayed(Duration.zero);
    events.add('reverse:${overlay.entries.length}');
  }
}

/// The declarative half: the overlay a widget owns, and the handle a
/// descendant finds through the element tree.
void widgetTests() {
  testWidgets('a descendant finds the overlay and puts something in it', (
    tester,
  ) async {
    final controller = Layout3dController();
    final overlays = <Overlay3d>[];

    await tester.pumpWidget(
      SceneLayout3d(
        parent: Node(),
        size: const Size3d(10, 10, 10),
        controller: controller,
        child: SceneOverlay3d(
          child: Builder(
            builder: (context) {
              overlays.add(SceneOverlay3d.of(context));
              return const SceneSizedBox3d.cube(2);
            },
          ),
        ),
      ),
    );

    final overlay = overlays.single;
    expect(controller.surface!.child, same(overlay));
    expect(overlay.children, hasLength(1));

    final dialog = TestBox(const Size3d(1, 1, 0), pointable: true);
    overlay.insertEntry(Overlay3dEntry(builder: (_) => dialog));
    await tester.pump();

    // The base child described in widgets and the entry inserted by hand are
    // both there, the entry last: the widget layer mirrors the base onto the
    // overlay and the entries are appended after whatever it mirrored.
    expect(overlay.children.first, isA<SizedBox3d>());
    expect(overlay.children.length, 2);
    expect(dialog.hasSize, isTrue);
    expect(
      controller.surface!.hitTestAt(const Offset3d(5, 5, 0)).target,
      same(dialog),
    );

    // A rebuild does not disturb the entries.
    await tester.pump();
    expect(overlay.children.length, 2);
    expect(overlay.entries, hasLength(1));
  });

  testWidgets('unmounting the overlay releases its entries', (tester) async {
    final controller = Overlay3dController();
    final detached = TestBox(const Size3d(1, 1, 0));

    await tester.pumpWidget(
      SceneLayout3d(
        parent: Node(),
        size: const Size3d(10, 10, 10),
        child: SceneOverlay3d(
          controller: controller,
          child: const SceneSizedBox3d.cube(2),
        ),
      ),
    );

    final entry = Overlay3dEntry(
      layer: const OverlayLayer3d.detached(),
      builder: (_) => detached,
    );
    controller.overlay!.insertEntry(entry);
    await tester.pump();
    expect(entry.surface, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());

    expect(detached.debugDisposed, isTrue);
    expect(controller.overlay, isNull);
  });
}
