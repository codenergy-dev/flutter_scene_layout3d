// SceneDecoratedBox3d: the declarative layer's one way of drawing something,
// and the promise that neither of its properties touches layout.

import 'dart:ui' show Color;

import 'package:flutter/widgets.dart' show BuildContext, Widget;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A painter that records what it was told and builds nothing, standing in
/// for the real one, which needs a GPU context.
class _RecordingPainter extends Decoration3dPainter {
  _RecordingPainter() {
    created.add(this);
  }

  static final List<_RecordingPainter> created = <_RecordingPainter>[];

  final List<Decoration3dPaintRequest> paints = <Decoration3dPaintRequest>[];

  @override
  void paint(Decoration3dPaintRequest request) => paints.add(request);

  @override
  void release(Node node) {}

  @override
  void dispose() {}
}

class _TestDecoration3d extends Decoration3d {
  const _TestDecoration3d({this.tag = 0});

  final int tag;

  @override
  Object get cacheKey => 'panel';

  @override
  bool shouldRebuild(_TestDecoration3d old) => false;

  @override
  Decoration3dPainter? createPainter() => _RecordingPainter();

  @override
  bool operator ==(Object other) =>
      other is _TestDecoration3d && other.tag == tag;

  @override
  int get hashCode => tag;
}

/// Hosts a [TestBox] in the widget tree, so a test can count the layouts the
/// declarative layer actually causes.
class _SceneTestBox extends Layout3dWidget {
  const _SceneTestBox(this.preferred, this.sink);

  final Size3d preferred;
  final void Function(TestBox) sink;

  @override
  Layout3d createLayout(BuildContext context) {
    final box = TestBox(preferred);
    sink(box);
    return box;
  }

  @override
  void updateLayout(BuildContext context, TestBox layout) {
    layout.preferred = preferred;
  }
}

void main() {
  setUp(_RecordingPainter.created.clear);
  tearDown(_RecordingPainter.created.clear);

  testWidgets('builds a DecoratedBox3d and updates it in place', (
    tester,
  ) async {
    final controller = Layout3dController();

    Widget frame(Decoration3d decoration) => SceneLayout3d(
      parent: Node(),
      constraints: Constraints3d.loose(const Size3d(10, 10, 10)),
      controller: controller,
      child: SceneDecoratedBox3d(
        decoration: decoration,
        child: const SceneSizedBox3d.cube(2),
      ),
    );

    await tester.pumpWidget(frame(const _TestDecoration3d()));
    final layout = controller.surface!.child!;
    expect(layout, isA<DecoratedBox3d>());
    expect((layout as DecoratedBox3d).decoration, const _TestDecoration3d());
    expect(layout.size, const Size3d(2, 2, 2));

    await tester.pumpWidget(frame(const _TestDecoration3d(tag: 1)));
    expect(controller.surface!.child!, same(layout));
    expect(layout.decoration, const _TestDecoration3d(tag: 1));
  });

  testWidgets('a rebuild that changes only the state layer lays nothing out', (
    tester,
  ) async {
    // The whole reason DecoratedBox3d keeps decoration and stateLayer as
    // setters: a pointer crossing a screen of controls writes one of these on
    // every box it touches, and a design where that relayouts is a design
    // where hovering a list is a stutter. The widget form has to keep the
    // promise, which means updateLayout may not go near markNeedsLayout.
    late TestBox child;
    final controller = Layout3dController();

    Widget frame(StateLayer3d stateLayer) => SceneLayout3d(
      parent: Node(),
      size: const Size3d(10, 10, 10),
      controller: controller,
      child: SceneDecoratedBox3d(
        decoration: const _TestDecoration3d(),
        stateLayer: stateLayer,
        child: _SceneTestBox(const Size3d(2, 2, 0), (box) => child = box),
      ),
    );

    await tester.pumpWidget(frame(StateLayer3d.none));
    final painter = _RecordingPainter.created.single;
    final laidOutOnce = child.layoutCount;
    final paints = painter.paints.length;

    await tester.pumpWidget(
      frame(const StateLayer3d(color: Color(0xFFFFFFFF), opacity: 0.08)),
    );

    expect(child.layoutCount, laidOutOnce, reason: 'nothing was laid out');
    expect(painter.paints.length, paints + 1, reason: 'but it repainted');
    expect(painter.paints.last.stateLayer.opacity, 0.08);
    expect(controller.surface!.needsFlush, isFalse);
  });

  testWidgets('a decoration change repaints without laying out either', (
    tester,
  ) async {
    late TestBox child;
    final controller = Layout3dController();

    Widget frame(int tag) => SceneLayout3d(
      parent: Node(),
      size: const Size3d(10, 10, 10),
      controller: controller,
      child: SceneDecoratedBox3d(
        decoration: _TestDecoration3d(tag: tag),
        child: _SceneTestBox(const Size3d(2, 2, 0), (box) => child = box),
      ),
    );

    await tester.pumpWidget(frame(0));
    final painter = _RecordingPainter.created.single;
    final laidOutOnce = child.layoutCount;
    final paints = painter.paints.length;

    await tester.pumpWidget(frame(1));

    expect(child.layoutCount, laidOutOnce);
    expect(painter.paints.length, paints + 1);
    // The cache key did not change and the decoration does not ask to be
    // rebuilt, so the same painter kept drawing it.
    expect(_RecordingPainter.created, hasLength(1));
  });

  testWidgets('a decorated box answers a ray for its whole face', (
    tester,
  ) async {
    final controller = Layout3dController();
    await tester.pumpWidget(
      SceneLayout3d(
        parent: Node(),
        size: const Size3d(4, 4, 1),
        controller: controller,
        child: const SceneDecoratedBox3d(
          decoration: _TestDecoration3d(),
          child: SceneSizedBox3d(width: 4, height: 4, depth: 1),
        ),
      ),
    );

    final surface = controller.surface!;
    final hit = surface.hitTestAt(const Offset3d(2, 2, 0.5));
    expect(hit.firstOf<DecoratedBox3d>(), isNotNull);
  });
}
