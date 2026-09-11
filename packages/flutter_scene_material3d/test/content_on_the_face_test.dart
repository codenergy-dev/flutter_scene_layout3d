// Where a component's content sits in the depth of the slab it is drawn on.
//
// Two rules, asked of every component that has both a surface and something
// on it: **nothing is behind the face of the slab it belongs to**, and
// **nothing is exactly on it either**. The first is a label that cannot be
// seen; the second is two surfaces that both write depth at the same plane,
// which comes out as stripes crawling across the painted area rather than as
// anything missing.
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
  expectNothingFlush(pumped.surface);
}

/// One opaque panel: where its front face is, and the rectangle it covers.
typedef Panel3dFace = ({double face, double left, double top, Size3d size});

/// Every panel in [surface] with ink in it.
///
/// The depth comes from the node — a lift on the node tier is exactly what
/// keeps two surfaces apart — and the rectangle from the layout offsets,
/// which is the frame a size is stated in.
List<Panel3dFace> opaquePanels(Layout3dSurface surface) {
  final found = <Panel3dFace>[];
  void walk(Layout3d box) {
    if (box is DecoratedBox3d) {
      final decoration = box.decoration;
      final ink = decoration is BoxDecoration3d ? decoration.color.a : 0.0;
      if (ink > 0.01) {
        final offset = offsetInSurface(box);
        found.add((
          face: box.node.globalTransform.getTranslation().z,
          left: offset.x,
          top: offset.y,
          size: box.size,
        ));
      }
    }
    box.visitChildren(walk);
  }

  final child = surface.child;
  if (child != null) walk(child);
  return found;
}

/// Fails naming two panels that share a face and overlap on it.
///
/// A transparent panel is not asked about: the panel shader discards where
/// its own alpha is zero, so it writes no depth and has nothing to fight
/// with. That is [docs/traps.md]'s "a panel with no ink in it draws nothing
/// *and writes no depth*", and it is why a navigation destination's own
/// colourless surface may sit wherever it likes.
void expectNothingFlush(Layout3dSurface surface) {
  final panels = opaquePanels(surface);
  for (var i = 0; i < panels.length; i++) {
    for (var j = i + 1; j < panels.length; j++) {
      final a = panels[i];
      final b = panels[j];
      if ((a.face - b.face).abs() > 1e-6) continue;
      final apart =
          a.left + a.size.width <= b.left ||
          b.left + b.size.width <= a.left ||
          a.top + a.size.height <= b.top ||
          b.top + b.size.height <= a.top;
      if (apart) continue;
      fail(
        'two panels share a front face at z=${a.face.toStringAsFixed(4)} and '
        'overlap on it — ${a.size.width.toStringAsFixed(2)} by '
        '${a.size.height.toStringAsFixed(2)} against '
        '${b.size.width.toStringAsFixed(2)} by '
        '${b.size.height.toStringAsFixed(2)}. Both write depth there, so the '
        'picture comes out striped. A surface lifts its own content by '
        'Material3d.contentLift; a slab that has to clear another slab\'s '
        'thickness wants Thickness3d.stepOver.',
      );
    }
  }
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

  group('and nothing is flush with the surface under it', () {
    // The switch and the navigation bar are the two the gallery showed as
    // stripes crawling across the painted area, once the panel shader began
    // writing the depth of the face a viewer can actually see.
    testWidgets('a switch on a card', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => FilledCard3d(child: Switch3d(value: true, onChanged: (_) {})),
      );
      expectNothingFlush(pumped.surface);
    });

    testWidgets('a navigation bar and its selection pill', (tester) async {
      final pumped = await pumpComponent(
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
      expectNothingFlush(pumped.surface);
    });

    testWidgets('a slider, a checkbox and a chip on a card', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => ElevatedCard3d(
          child: SceneColumn3d(
            mainAxisSize: MainAxisSize3d.min,
            children: <Widget>[
              Slider3d(value: 0.5, onChanged: (_) {}),
              Checkbox3d(value: true, onChanged: (_) {}),
              FilterChip3d(
                label: const SceneText3d('All'),
                selected: true,
                onSelected: (_) {},
              ),
            ],
          ),
        ),
      );
      expectNothingFlush(pumped.surface);
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

    testWidgets('and so is the one about being flush', (tester) async {
      // Two surfaces resting on each other with no lift between them, which
      // is what every component did until a panel began writing the depth of
      // its front face. The shift is `Material3d.contentLift` in world units
      // *away* from the viewer, which cancels the lift the outer surface
      // gives its content and puts the two faces back on one plane.
      final pumped = await pumpComponent(
        tester,
        () => const Material3d(
          thickness: 40,
          child: SceneNodeShift3d(
            shift: Offset3d(0, 0, 0.002),
            child: Material3d(thickness: 10, child: SceneText3d('flush')),
          ),
        ),
      );
      expect(
        () => expectNothingFlush(pumped.surface),
        throwsA(isA<TestFailure>()),
      );
    });
  });
}
