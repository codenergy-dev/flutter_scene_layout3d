// Where a component's content sits in the depth of the slab it is drawn on.
//
// One rule, asked of every component that has both a surface and something
// written on it: **nothing is behind the face of the slab it belongs to.**
//
// It is worth a file of its own because it is invisible to every other kind
// of test here. A label half a thickness inside a card measures the same, lays
// out the same, hit-tests the same and announces the same; the only thing it
// does differently is not be there. And until the panel shader's slab was
// wound the right way round it was not even reliably absent — a card did not
// occlude what was inside it, so a buried label drew or did not according to
// which way the translucent sort happened to fall that frame, which is what a
// person saw as the gallery blinking. See
// `packages/flutter_scene_layout3d/plans/2026_09_10_a_letter_on_a_slab.md`.

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'surfaces_support.dart';

/// Every label in [surface] with the depth of the face of the nearest slab
/// around it, in world units, nearer the viewer being larger.
///
/// Node transforms rather than layout offsets, deliberately: a lift on the
/// node tier — an elevation's `sceneOffset`, a `Stack3d.depthStep`, a
/// `NodeShift3d` — moves the geometry without moving the box, and what is
/// being asked here is where the *geometry* ends up.
List<(String, double, double)> labelsAgainstTheirSlab(Layout3dSurface surface) {
  final found = <(String, double, double)>[];
  void walk(Layout3d box, double face) {
    final z = box.node.globalTransform.getTranslation().z;
    final slab = box is DecoratedBox3d ? z : face;
    if (box is Text3d && box.data.isNotEmpty) found.add((box.data, z, slab));
    box.visitChildren((child) => walk(child, slab));
  }

  final child = surface.child;
  if (child != null) walk(child, double.negativeInfinity);
  return found;
}

/// Fails naming the label that sank into the surface it is written on.
void expectNothingBuried(Layout3dSurface surface) {
  final labels = labelsAgainstTheirSlab(surface);
  expect(labels, isNotEmpty, reason: 'the component drew no labels at all');
  for (final (text, z, face) in labels) {
    expect(
      z,
      greaterThanOrEqualTo(face - 1e-9),
      reason:
          '"$text" is ${((face - z) * 100).toStringAsFixed(1)} hundredths of '
          'a unit behind the face of the slab it is written on, where the '
          'slab hides it',
    );
  }
}

Future<void> expectContentOnTheFace(
  WidgetTester tester,
  Widget Function() build,
) async {
  final pumped = await pumpComponent(tester, build);
  expectNothingBuried(pumped.surface);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a label sits on the face of what it is written on', () {
    testWidgets('a list tile, the case that started it', (tester) async {
      // The tile's row is as deep as the tile, because a `Material3d` hands
      // its child a tight depth, and a row centred in that depth is a row
      // half a thickness inside the card.
      await expectContentOnTheFace(
        tester,
        () => const ElevatedCard3d(
          child: ListTile3d(
            leading: Icon3d(Icons.person),
            title: SceneText3d('Ada Lovelace'),
            subtitle: SceneText3d('The engine weaves algebraic patterns'),
          ),
        ),
      );
    });

    testWidgets('an app bar and its title', (tester) async {
      await expectContentOnTheFace(tester, () => AppBar3d.text(title: 'Inbox'));
    });

    testWidgets('a navigation bar, selected destination and all', (
      tester,
    ) async {
      await expectContentOnTheFace(
        tester,
        () => NavigationBar3d(
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          destinations: const <NavigationDestination3d>[
            NavigationDestination3d(icon: Icon3d(Icons.inbox), label: 'Inbox'),
            NavigationDestination3d(
              icon: Icon3d(Icons.tune),
              label: 'Settings',
            ),
          ],
        ),
      );
    });

    testWidgets('a navigation rail', (tester) async {
      await expectContentOnTheFace(
        tester,
        () => NavigationRail3d(
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          destinations: const <NavigationDestination3d>[
            NavigationDestination3d(icon: Icon3d(Icons.inbox), label: 'Inbox'),
            NavigationDestination3d(
              icon: Icon3d(Icons.tune),
              label: 'Settings',
            ),
          ],
        ),
      );
    });

    testWidgets('the buttons, filled and outlined', (tester) async {
      await expectContentOnTheFace(
        tester,
        () => SceneRow3d(
          children: <Widget>[
            FilledButton3d(onPressed: () {}, child: const SceneText3d('Save')),
            OutlinedButton3d(
              onPressed: () {},
              child: const SceneText3d('Undo'),
            ),
          ],
        ),
      );
    });

    testWidgets('a chip, which always had it right', (tester) async {
      await expectContentOnTheFace(
        tester,
        () => FilterChip3d(
          label: const SceneText3d('All'),
          selected: true,
          onSelected: (_) {},
        ),
      );
    });

    testWidgets('a dialog and a snack bar', (tester) async {
      await expectContentOnTheFace(
        tester,
        () => const Dialog3d(child: SceneText3d('This cannot be undone.')),
      );
      await expectContentOnTheFace(
        tester,
        () => const SnackBar3d(message: 'Composing a message'),
      );
    });
  });

  group('the rule itself', () {
    testWidgets('is a rule this test can fail', (tester) async {
      // The guard on the guard: a label deliberately centred in the depth of
      // the slab it is on has to trip `expectNothingBuried`, or every case
      // above is passing vacuously.
      final pumped = await pumpComponent(
        tester,
        () => const Material3d(
          thickness: 40,
          alignment: null,
          child: SceneCenter3d(child: SceneText3d('sunk')),
        ),
      );
      expect(
        () => expectNothingBuried(pumped.surface),
        throwsA(isA<TestFailure>()),
      );
    });
  });
}
