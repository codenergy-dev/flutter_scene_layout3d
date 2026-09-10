// Scaffold3d: what each slot is given, where in depth it is put, and the
// window the body is clipped to.

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'surfaces_support.dart';

const Theme3dData _theme = Theme3dData.light;
const double _dp = 0.01;

const List<NavigationDestination3d> _destinations = <NavigationDestination3d>[
  NavigationDestination3d(icon: Icon3d(Icons.inbox), label: 'Inbox'),
  NavigationDestination3d(icon: Icon3d(Icons.send), label: 'Sent'),
];

/// The box tagged [slot] inside the pumped scaffold, and where it ended up.
LayoutId3d slotOf(Layout3dSurface surface, Scaffold3dSlot slot) =>
    boxesOf<LayoutId3d>(surface).firstWhere((box) => box.id == slot);

void main() {
  group('the arrangement', () {
    testWidgets('the body gets what the bars left over', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => Scaffold3d(
          appBar: AppBar3d.text(title: 'Inbox'),
          body: const SceneSizedBox3d(),
          bottomNavigationBar: const NavigationBar3d(
            destinations: _destinations,
            selectedIndex: 0,
          ),
        ),
        centred: false,
      );
      final surface = pumped.surface;
      final body = slotOf(surface, Scaffold3dSlot.body);
      // The surface is 4 x 3; the bar is 64dp and the navigation bar 80dp.
      expect(body.size.height, closeTo(3 - 64 * _dp - 80 * _dp, 1e-9));
      expect(body.offset.y, closeTo(64 * _dp, 1e-9));
      expect(
        slotOf(surface, Scaffold3dSlot.bottomNavigationBar).offset.y,
        closeTo(3 - 80 * _dp, 1e-9),
      );
    });

    testWidgets('extendBody and extendBodyBehindAppBar give it back', (
      tester,
    ) async {
      final pumped = await pumpComponent(
        tester,
        () => Scaffold3d(
          extendBody: true,
          extendBodyBehindAppBar: true,
          appBar: AppBar3d.text(title: 'Inbox'),
          body: const SceneSizedBox3d(),
          bottomNavigationBar: const NavigationBar3d(
            destinations: _destinations,
            selectedIndex: 0,
          ),
        ),
        centred: false,
      );
      final body = slotOf(pumped.surface, Scaffold3dSlot.body);
      expect(body.size.height, closeTo(3, 1e-9));
      expect(body.offset.y, 0.0);
    });

    testWidgets('a scaffold with only a body fills it', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => const Scaffold3d(body: SceneSizedBox3d()),
        centred: false,
      );
      final body = slotOf(pumped.surface, Scaffold3dSlot.body);
      expect(body.size.width, closeTo(4, 1e-9));
      expect(body.size.height, closeTo(3, 1e-9));
    });

    testWidgets('the floating action button sits above the bottom bar', (
      tester,
    ) async {
      final pumped = await pumpComponent(
        tester,
        () => Scaffold3d(
          body: const SceneSizedBox3d(),
          bottomNavigationBar: const NavigationBar3d(
            destinations: _destinations,
            selectedIndex: 0,
          ),
          floatingActionButton: FloatingActionButton3d(
            semanticLabel: 'Compose',
            onPressed: () {},
            child: const Icon3d(Icons.edit),
          ),
        ),
        centred: false,
      );
      final fab = slotOf(pumped.surface, Scaffold3dSlot.floatingActionButton);
      final margin = Scaffold3d.defaultFloatingActionButtonMargin * _dp;
      expect(fab.offset.x, closeTo(4 - fab.size.width - margin, 1e-9));
      expect(
        fab.offset.y,
        closeTo(3 - 80 * _dp - fab.size.height - margin, 1e-9),
      );
    });
  });

  group('the depths, which are the guarantee', () {
    testWidgets('every slot is a step in front of the one behind it', (
      tester,
    ) async {
      final pumped = await pumpComponent(
        tester,
        () => Scaffold3d(
          appBar: AppBar3d.text(title: 'Inbox'),
          body: const SceneSizedBox3d(),
          bottomNavigationBar: const NavigationBar3d(
            destinations: _destinations,
            selectedIndex: 0,
          ),
          floatingActionButton: FloatingActionButton3d(
            semanticLabel: 'Compose',
            onPressed: () {},
            child: const Icon3d(Icons.edit),
          ),
        ),
        centred: false,
      );
      final step = _theme.thickness.depthStep * _dp;
      for (final slot in Scaffold3dSlot.values) {
        final box = slotOf(pumped.surface, slot);
        // The slot's *box* is at z zero, and its geometry is what moves.
        // Toward the viewer is negative depth, the direction every lift in
        // this stack goes.
        expect(box.offset.z, 0.0, reason: '$slot');
        expect(
          (box.child! as NodeShift3d).shift.z,
          closeTo(-Scaffold3d.liftFor(slot, step), 1e-9),
          reason: '$slot',
        );
      }
    });

    testWidgets('and a slot gets a real depth budget, not the backing\'s', (
      tester,
    ) async {
      // The backing is a `thickness.thin` slab and a `Material3d`'s thickness
      // is a *tight* depth constraint on everything below it. While the
      // arrangement was the backing's child, every slot inherited a 1dp
      // budget: an 8dp app bar came out 1dp and its title, aligned to the
      // bar's front face, ended up coplanar with the bar and lost the depth
      // test. Nothing said so — the arithmetic was all correct — and only a
      // drawn frame showed a screen with no titles on it.
      final pumped = await pumpComponent(
        tester,
        () => Scaffold3d(
          appBar: AppBar3d.text(title: 'Inbox'),
          body: const SceneSizedBox3d(),
        ),
        centred: false,
      );
      final bar = slotOf(pumped.surface, Scaffold3dSlot.appBar);
      expect(
        bar.size.depth,
        closeTo(_theme.thickness.structural * _dp, 1e-9),
        reason: 'an 8dp bar is 8dp deep inside a screen',
      );
    });

    testWidgets('and a ray still reaches what is lifted', (tester) async {
      // The regression this arrangement exists for. A lift written into the
      // slot's *position* is a negative z, which puts the slot outside its
      // parent's own extent — and a ray is clamped to the stretch inside each
      // box before its children are asked. A screen lifted that way draws
      // perfectly and cannot be pressed anywhere: the scaffold's backing
      // answers every hit and nothing below it is ever reached. Only running
      // the gallery found it.
      final chosen = <int>[];
      final pumped = await pumpComponent(
        tester,
        () => Scaffold3d(
          appBar: AppBar3d.text(title: 'Inbox'),
          body: const SceneSizedBox3d(),
          bottomNavigationBar: NavigationBar3d(
            destinations: _destinations,
            selectedIndex: 0,
            onDestinationSelected: chosen.add,
          ),
        ),
        centred: false,
      );
      final target = boxesOf<TapTarget3d>(
        pumped.surface,
      ).where((t) => t.effectiveMinimumSize.width > 0.0).toList()[1];
      final middle = offsetInSurface(target) + target.size.center;
      pumped.pointer.down(rayAt(pumped.surface, middle));
      pumped.pointer.up();
      await tester.pump();
      expect(chosen, <int>[1]);
    });

    testWidgets('and the default step really does separate a bar from a card', (
      tester,
    ) async {
      // The arithmetic the assert states, checked rather than assumed: two
      // slabs are separated only when the step exceeds the mean of their
      // thicknesses, so an 8dp bar over a 4dp card needs more than 6dp.
      expect(Thickness3d.minimumStepFor(4.0, 8.0), 6.0);
      expect(_theme.thickness.depthStep, 12.0);
      expect(
        _theme.thickness.separates(
          _theme.thickness.raised,
          _theme.thickness.structural,
        ),
        isTrue,
      );
    });

    testWidgets('a step that does not separate is refused', (tester) async {
      await pumpComponent(
        tester,
        () => const Scaffold3d(depthStep: 4.0, body: SceneSizedBox3d()),
        centred: false,
      );
      expect(tester.takeException(), isA<AssertionError>());
    });

    test('liftFor is the enum order, one-based', () {
      expect(Scaffold3d.liftFor(Scaffold3dSlot.body, 12), 12);
      expect(Scaffold3d.liftFor(Scaffold3dSlot.bottomNavigationBar, 12), 24);
      expect(Scaffold3d.liftFor(Scaffold3dSlot.appBar, 12), 36);
      expect(Scaffold3d.liftFor(Scaffold3dSlot.floatingActionButton, 12), 48);
    });
  });

  group('the body\'s window', () {
    testWidgets('the body is inside a clip box', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => Scaffold3d(
          appBar: AppBar3d.text(title: 'Inbox'),
          body: const SceneSizedBox3d(),
        ),
        centred: false,
      );
      final clip = oneOf<ClipBox3d>(pumped.surface);
      expect(clip.clipDepth, isFalse, reason: 'a raised card stands proud');
      expect(clip.ownRegion.planes, hasLength(4));
    });

    testWidgets('and a row overflowing the body is cut at the bar', (
      tester,
    ) async {
      // The window is what stops a list drawing over the bars. A card taller
      // than the body's slot is neither wholly in nor wholly out, which is
      // exactly what culling cannot express.
      final pumped = await pumpComponent(
        tester,
        () => Scaffold3d(
          appBar: AppBar3d.text(title: 'Inbox'),
          // A list rather than a column: a column that overflows reports it
          // as a layout error, and what this test is about is the row that
          // is *half* out of the window rather than one that should not
          // have been laid out there at all.
          body: SceneListView3d(
            children: <Widget>[
              for (var i = 0; i < 20; i++)
                const SceneSizedBox3d(height: 0.5, child: Card3d()),
            ],
          ),
        ),
        centred: false,
      );
      final cards = pumped.panels
          .where((box) => !box.clipRegion.isUnbounded)
          .toList(growable: false);
      expect(cards, isNotEmpty);
      // Four planes, which is a window on the face and nothing in depth.
      expect(cards.first.clipRegion.planes, hasLength(4));
    });
  });

  group('what a scaffold owns', () {
    testWidgets('it draws its own backing at the surface colour', (
      tester,
    ) async {
      final pumped = await pumpComponent(
        tester,
        () => const Scaffold3d(body: SceneSizedBox3d()),
        centred: false,
      );
      final backing = pumped.decoration;
      expect(backing.color, _theme.colorScheme.surface);
      expect(backing.elevation, _theme.elevation.level0);
    });

    testWidgets('and binds no surface of its own', (tester) async {
      // The decision stated as a test: a scaffold is a box like any other,
      // so nothing in it touches the surface's metrics or constraints. An
      // application that wants a full-view screen says so where it mounts
      // the surface, with a Layout3dCameraBinding.
      final pumped = await pumpComponent(
        tester,
        () => const Scaffold3d(body: SceneSizedBox3d()),
        centred: false,
      );
      expect(pumped.surface.metrics, Layout3dMetrics.standard);
      expect(
        pumped.surface.constraints,
        Constraints3d.tight(const Size3d(4, 3, 0.5)),
      );
    });

    testWidgets('a rebuild that changes nothing lays nothing out again', (
      tester,
    ) async {
      final boxes = <TestBox>[];
      final pumped = await pumpComponent(
        tester,
        () => Scaffold3d(
          appBar: AppBar3d.text(title: 'Inbox'),
          body: SceneTestBox(const Size3d(1, 1, 0), boxes.add),
        ),
        centred: false,
      );
      final laid = boxes.single.layoutCount;
      await tester.pump();
      expect(boxes.single.layoutCount, laid);
      expect(pumped.surface.needsFlush, isFalse);
    });
  });
}
