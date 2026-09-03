// Shared scaffolding for the phase-4 surfaces and rows: cards, tiles,
// dividers and chips.
//
// It sits beside `support.dart` rather than in it because everything here is
// about *widgets* — pumping a component into a real surface and asking the
// laid-out tree what came out — while `support.dart` is mostly imperative
// helpers the token tests use.

import 'package:flutter/widgets.dart'
    show BuildContext, StatelessWidget, Widget;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every box of type [T] in [surface], outermost first.
///
/// Not named `allOf`: `package:matcher` exports one, and the collision is a
/// compile error in every test that imports both.
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

/// The one box of type [T] in [surface].
T oneOf<T extends Layout3d>(Layout3dSurface surface) {
  final found = boxesOf<T>(surface);
  if (found.length != 1) {
    throw StateError('expected one $T, found ${found.length}');
  }
  return found.single;
}

/// The outermost box of type [T] in [surface].
T outermostOf<T extends Layout3d>(Layout3dSurface surface) =>
    boxesOf<T>(surface).first;

/// Where [box] sits in the surface's own frame, summing the offsets its
/// parents gave it.
///
/// A box's `offset` is relative to its own parent, so two boxes at different
/// depths in the tree cannot be compared by it — both a tile's panel and a
/// divider's are at zero inside their own containers. This is what "which one
/// is above the other" actually means.
Offset3d offsetInSurface(Layout3d box) {
  var total = Offset3d.zero;
  Layout3d? node = box;
  while (node != null && node is! Layout3dSurface) {
    total += node.offset;
    node = node.parent;
  }
  return total;
}

/// A pumped component and the handles a test wants on it.
class PumpedSurface {
  PumpedSurface(this.controller, this.builds);

  /// The surface's controller, which is how a test reaches the laid-out tree.
  final Layout3dController controller;

  /// How many times the component's own builder has run, so a test can say
  /// what a state actually cost.
  final List<int> builds;

  Layout3dSurface get surface => controller.surface!;

  /// Every decorated box in the tree, outermost first.
  List<DecoratedBox3d> get panels => boxesOf<DecoratedBox3d>(surface);

  /// The outermost panel, which is the component's own surface.
  DecoratedBox3d get panel => panels.first;

  BoxDecoration3d get decoration => panel.decoration as BoxDecoration3d;

  StateLayer3d get layer => panel.stateLayer;

  Semantics3d get semantics => outermostOf<Semantics3d>(surface);

  TapTarget3d get target => outermostOf<TapTarget3d>(surface);

  Layout3dPointer? _pointer;

  /// One pointer for the whole test, because the sequence between a `down`
  /// and its `up` is what holds the captured path and the arena entry.
  Layout3dPointer get pointer => _pointer ??= Layout3dPointer(surface);
}

/// Pumps [build] centred on a 4 x 3 surface at a hundred logical pixels to
/// the unit, under [theme].
Future<PumpedSurface> pumpComponent(
  WidgetTester tester,
  Widget Function() build, {
  Theme3dData theme = Theme3dData.light,
  Size3d size = const Size3d(4, 3, 0.5),
  bool centred = true,
}) async {
  final controller = Layout3dController();
  final builds = <int>[0];
  await tester.pumpWidget(
    SceneLayout3d(
      parent: Node(),
      size: size,
      controller: controller,
      child: SceneTheme3d(
        data: theme,
        child: _Counting(builds, build, centred: centred),
      ),
    ),
  );
  return PumpedSurface(controller, builds);
}

class _Counting extends StatelessWidget {
  const _Counting(this.builds, this.builder, {required this.centred});

  final List<int> builds;
  final Widget Function() builder;
  final bool centred;

  @override
  Widget build(BuildContext context) {
    builds[0]++;
    final child = builder();
    return centred ? SceneCenter3d(child: child) : child;
  }
}
