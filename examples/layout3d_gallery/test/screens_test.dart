// The one app a person actually runs, built headlessly.
//
// Nothing here draws — a `BoxDecoration3d` with no painter installed lays out
// perfectly and paints nothing, which is exactly what the package does before
// `initializeMaterial3d()` — so this is no substitute for looking at the
// window, and the phase that added these screens looked. What it does catch is
// the failure that would otherwise reach a person: a screen that stops laying
// out after a refactor of the catalogue, an assert in `Scaffold3d`'s depth
// ordering, a slot that is no longer satisfiable. Those are cheap to pin down
// and expensive to find by starting a GPU.

import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layout3d_gallery/screens.dart';
import 'package:vector_math/vector_math.dart' show Ray, Vector3;

/// Every box of type [T] in [surface], outermost first.
List<T> boxesOf<T extends Layout3d>(Layout3dSurface surface) {
  final found = <T>[];
  void walk(Layout3d box) {
    if (box is T) found.add(box);
    box.visitChildren(walk);
  }

  final child = surface.child;
  if (child != null) walk(child);
  return found;
}

/// Where [box] sits in the surface's own frame, summing what its parents
/// gave it.
Offset3d offsetInSurface(Layout3d box) {
  var total = Offset3d.zero;
  Layout3d? node = box;
  while (node != null && node is! Layout3dSurface) {
    total += node.offset;
    node = node.parent;
  }
  return total;
}

/// Every semantic label published anywhere in [surface].
Set<String> labelsIn(Layout3dSurface surface) => <String>{
  for (final box in boxesOf<Semantics3d>(surface))
    if (box.properties.label case final String label) label,
};

/// Mounts [screen] on a surface the size the gallery gives it.
///
/// No `textRendererFactory`: a `Text3d` with no renderer measures and lays out
/// fine, and rasterizing a glyph wants a GPU that `flutter test` does not
/// have. The gallery installs one; this asks the arithmetic questions.
Future<Layout3dController> pump(
  WidgetTester tester,
  Widget screen, {
  Size3d size = const Size3d(3.5, 4.8, 0.6),
  LayoutBasis3d? basis,
  Layout3dMetrics metrics = Layout3dMetrics.standard,
}) async {
  final controller = Layout3dController();
  await tester.pumpWidget(
    SceneLayout3d(
      parent: Node(),
      controller: controller,
      size: size,
      basis: basis,
      metrics: metrics,
      child: SceneTheme3d(
        data: Theme3dData.dark,
        child: SceneOverlay3d(child: screen),
      ),
    ),
  );
  return controller;
}

/// A ray aimed straight at [point] on [surface]'s plane, from in front of it.
Ray rayAt(Layout3dSurface surface, Offset3d point) {
  final toWorld = surface.node.globalTransform;
  final origin = toWorld.transformed3(
    Vector3(point.x, point.y, point.z - 10.0),
  );
  final direction = toWorld.rotated3(Vector3(0, 0, 1));
  return Ray.originDirection(origin, direction);
}

void main() {
  testWidgets('the upright screen fills the panel it is given', (tester) async {
    final controller = await pump(tester, const MaterialScreen());
    final surface = controller.surface!;

    expect(surface.child!.size, const Size3d(3.5, 4.8, 0.6));
    // A screen is a stack of panels: the scaffold's backing, the bar, the
    // navigation bar, the button, the chips, the cards and the tiles. If the
    // decoration ever stops reaching a component, this says so long before
    // anyone starts a GPU.
    expect(boxesOf<DecoratedBox3d>(surface).length, greaterThan(10));
    expect(
      labelsIn(surface),
      containsAll(<String>['Inbox', 'Settings', 'Compose', 'Ada Lovelace']),
    );
  });

  testWidgets('the inbox scrolls, and the destination swaps it for the '
      'controls', (tester) async {
    final controller = await pump(tester, const MaterialScreen());
    final surface = controller.surface!;

    expect(
      boxesOf<ListView3d>(surface),
      isNotEmpty,
      reason: 'the inbox is a list taller than the body it sits in',
    );
    expect(labelsIn(surface), isNot(contains('Volume')));

    // A press on a 3D surface is a ray, not a widget tap: aim one at the
    // middle of the second destination's touch target. Aiming by *target*
    // rather than by a guessed fraction of the panel is what makes this a
    // test of the screen rather than of arithmetic done twice.
    final destination = boxesOf<Semantics3d>(
      surface,
    ).firstWhere((box) => box.properties.label == 'Settings');
    final pointer = Layout3dPointer(surface);
    final ray = rayAt(
      surface,
      offsetInSurface(destination) + destination.size.center,
    );
    expect(
      surface.hitTestRay(ray).firstOf<Semantics3d>(),
      same(destination),
      reason: 'a lifted scaffold slot has to stay reachable by a ray',
    );
    pointer
      ..down(ray)
      ..up();
    await tester.pump();

    expect(labelsIn(surface), contains('Volume'));
    expect(boxesOf<ListView3d>(surface), isEmpty);
    pointer.dispose();
  });

  testWidgets('the table screen lays out on the ground plane', (tester) async {
    final controller = await pump(
      tester,
      const TableScreen(),
      size: const Size3d(4.6, 2.6, 0.6),
      basis: LayoutBasis3d.xz,
      // The rate the gallery gives this plane, and the reason it is repeated
      // here: an overflow depends on how many logical pixels the surface is
      // across, so a test at the default rate would measure a screen the app
      // never draws.
      metrics: const Layout3dMetrics(unitsPerLogicalPixel: 0.012),
    );
    final surface = controller.surface!;

    expect(surface.child!.size, const Size3d(4.6, 2.6, 0.6));
    expect(
      labelsIn(surface),
      containsAll(<String>['Card 1', 'Card 2', 'Card 3']),
    );
    // The basis is the only difference between this screen and the upright
    // one, and it is a property of the plane rather than of the layout: the
    // boxes below it never hear about it.
    expect(surface.basis, LayoutBasis3d.xz);
  });
}
