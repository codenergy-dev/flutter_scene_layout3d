// Shared scaffolding for the phase-4 surfaces and rows: cards, tiles,
// dividers and chips.
//
// It sits beside `support.dart` rather than in it because everything here is
// about *widgets* — pumping a component into a real surface and asking the
// laid-out tree what came out — while `support.dart` is mostly imperative
// helpers the token tests use.

import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        Directionality,
        StatelessWidget,
        TextDirection,
        Widget,
        debugOnRebuildDirtyWidget;
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

/// The node-tier shifts a component built itself, in tree order.
///
/// Every `Material3d` puts one inside itself to lift its content clear of its
/// own face (`Material3d.contentLift`), so "the shift" a component test means
/// — a switch's thumb sliding, a slider's active track scaling — is whichever
/// one the component named.
List<NodeShift3d> componentShifts(Layout3dSurface surface) =>
    boxesOf<NodeShift3d>(
      surface,
    ).where((shift) => shift.node.name != Material3d.contentLiftName).toList();

/// The one shift a component built itself.
NodeShift3d oneComponentShift(Layout3dSurface surface) {
  final found = componentShifts(surface);
  if (found.length != 1) {
    throw StateError(
      'expected one component NodeShift3d, found ${found.length}',
    );
  }
  return found.single;
}

/// The one box in [surface] whose node is called [name].
///
/// How a test reaches a box a component built privately — a switch's thumb,
/// a progress bar's span — which has no type a test can name.
Layout3d namedBox(Layout3dSurface surface, String name) {
  final found = boxesOf<Layout3d>(
    surface,
  ).where((box) => box.node.name == name).toList();
  if (found.length != 1) {
    throw StateError('expected one box called "$name", found ${found.length}');
  }
  return found.single;
}

/// What [watchFrames] saw: how many frames it watched, the frames on which
/// something in the surface was marked for layout, and the widgets that
/// rebuilt.
typedef FramesWatched = ({int ticks, List<int> laidOut, List<String> rebuilt});

/// Pumps [frames] frames of [step] each, watching what every animation
/// running when it started costs on each of them.
///
/// **`needsFlush` after a `pump` proves nothing**, because the frame that
/// pump drew has already laid the surface out. The dirt has to be caught when
/// it is raised, and there is one place every piece of it passes: a box
/// marked for layout asks its surface for a visual update, and at that
/// moment the surface needs a flush. So this listens on
/// `Layout3dSurface.onNeedVisualUpdate` — which a node-tier write or a
/// repaint also calls, with nothing to flush — and records the frames on
/// which the surface was dirty when it was called. That catches dirt from a
/// tick and dirt from a rebuild alike. The builds are counted through
/// Flutter's own `debugOnRebuildDirtyWidget`, which every dirty element
/// reports to as it rebuilds, and a ticker of its own counts the frames.
Future<FramesWatched> watchFrames(
  WidgetTester tester,
  Layout3dSurface surface, {
  int frames = 60,
  Duration step = const Duration(milliseconds: 16),
}) async {
  var ticks = 0;
  final laidOut = <int>{};
  final rebuilt = <String>[];
  final previousRebuild = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    rebuilt.add('${element.widget.runtimeType} on frame $ticks');
  };
  final previousUpdate = surface.onNeedVisualUpdate;
  surface.onNeedVisualUpdate = () {
    if (surface.needsFlush) laidOut.add(ticks);
    previousUpdate?.call();
  };
  final watcher = Ticker((_) => ticks++)..start();
  try {
    for (var i = 0; i < frames; i++) {
      await tester.pump(step);
    }
  } finally {
    debugOnRebuildDirtyWidget = previousRebuild;
    surface.onNeedVisualUpdate = previousUpdate;
    watcher
      ..stop()
      ..dispose();
  }
  return (ticks: ticks, laidOut: laidOut.toList(), rebuilt: rebuilt);
}

/// [watchFrames], failing if anything was laid out on any frame — or, unless
/// [allowBuilds], if any widget was rebuilt.
Future<void> expectNothingLaidOut(
  WidgetTester tester,
  Layout3dSurface surface, {
  int frames = 60,
  Duration step = const Duration(milliseconds: 16),
  bool allowBuilds = false,
}) async {
  final watched = await watchFrames(
    tester,
    surface,
    frames: frames,
    step: step,
  );
  expect(watched.ticks, greaterThan(0), reason: 'the watcher saw no frames');
  expect(
    watched.laidOut,
    isEmpty,
    reason: 'frames on which something was laid out',
  );
  if (!allowBuilds) {
    expect(watched.rebuilt, isEmpty, reason: 'widgets rebuilt');
  }
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
/// the unit, under [theme] — and under a `Directionality` when [textDirection]
/// is given, which is how a right-to-left application reaches a component.
Future<PumpedSurface> pumpComponent(
  WidgetTester tester,
  Widget Function() build, {
  Theme3dData theme = Theme3dData.light,
  Size3d size = const Size3d(4, 3, 0.5),
  bool centred = true,
  TextDirection? textDirection,
}) async {
  final controller = Layout3dController();
  final builds = <int>[0];
  final Widget surface = SceneLayout3d(
    parent: Node(),
    size: size,
    controller: controller,
    child: SceneTheme3d(
      data: theme,
      child: _Counting(builds, build, centred: centred),
    ),
  );
  await tester.pumpWidget(
    textDirection == null
        ? surface
        : Directionality(textDirection: textDirection, child: surface),
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
