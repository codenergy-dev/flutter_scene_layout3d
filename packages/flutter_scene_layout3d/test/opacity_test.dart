// Opacity3d, FadeTransition3d, the inherited value they publish, and what
// the three things this package draws with do when they are told about it.
//
// What is checkable here is the arithmetic and the plumbing: which value is in
// force on which box, that it composes, that it reaches a painter and a
// label's material, and that changing it lays nothing out. What a fade *looks
// like* is a frame, and lives in `examples/render_probe` —
// `faded_panel_lets_the_backdrop_through` and `faded_panel_at_full_opacity`.

import 'dart:ui' show Color;

import 'package:flutter/animation.dart'
    show AnimationController, AnimationStatus;
import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter_scene/scene.dart' show Material, Node, TextureSource;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A painter that records the requests it was handed and builds nothing.
class FadeRecordingPainter extends Decoration3dPainter {
  FadeRecordingPainter();

  final List<Decoration3dPaintRequest> paints = <Decoration3dPaintRequest>[];

  double get lastOpacity => paints.last.opacity;

  @override
  void paint(Decoration3dPaintRequest request) => paints.add(request);

  @override
  void release(Node node) {}

  @override
  void dispose() {}
}

/// A glyph material that records what it is told rather than drawing.
class FadeRecordingGlyphMaterial implements GlyphMaterial3d {
  static final List<FadeRecordingGlyphMaterial> created =
      <FadeRecordingGlyphMaterial>[];

  FadeRecordingGlyphMaterial() {
    created.add(this);
  }

  double opacity = 1.0;
  int fades = 0;

  @override
  Material get material => throw UnimplementedError();

  @override
  void bindAtlas(TextureSource? atlas) {}

  @override
  void tint(Color color) {}

  @override
  void fade(double value) {
    opacity = value;
    fades++;
  }
}

void main() {
  tearDown(() {
    BoxDecoration3d.painterFactory = null;
    FadeRecordingGlyphMaterial.created.clear();
  });

  group('the value in force', () {
    test('is one when nothing above fades', () {
      final box = TestBox(const Size3d(1, 1, 0));
      laidOut(box);
      expect(box.inheritedOpacity, 1.0);
    });

    test(
      'an Opacity3d imposes its own on everything below it, not on itself',
      () {
        final box = TestBox(const Size3d(1, 1, 0));
        final fade = Opacity3d(opacity: 0.4, child: box);
        laidOut(fade);
        // The same distinction ClipBox3d draws: a box imposes on its children
        // and is not itself inside what it imposes.
        expect(fade.inheritedOpacity, 1.0);
        expect(fade.opacity, 0.4);
        expect(box.inheritedOpacity, closeTo(0.4, 1e-9));
      },
    );

    test('two of them multiply, as two nested Opacity widgets do', () {
      final box = TestBox(const Size3d(1, 1, 0));
      laidOut(
        Opacity3d(opacity: 0.5, child: Opacity3d(opacity: 0.5, child: box)),
      );
      expect(box.inheritedOpacity, closeTo(0.25, 1e-9));
    });

    test('it reaches through the boxes in between', () {
      final box = TestBox(const Size3d(0.4, 0.4, 0));
      laidOut(
        Opacity3d(
          opacity: 0.6,
          child: Padding3d(
            padding: const EdgeInsets3d.all(0.1),
            child: Center3d(child: box),
          ),
        ),
      );
      expect(box.inheritedOpacity, closeTo(0.6, 1e-9));
    });

    test('it is clamped rather than trusted', () {
      final box = TestBox(const Size3d(1, 1, 0));
      final fade = Opacity3d(opacity: 4.0, child: box);
      laidOut(fade);
      expect(fade.opacity, 1.0);
      fade.opacity = -2.0;
      expect(fade.opacity, 0.0);
    });
  });

  group('republishing', () {
    test('a change reaches the whole subtree without laying anything out', () {
      final box = TestBox(const Size3d(1, 1, 0));
      final fade = Opacity3d(opacity: 1.0, child: box);
      laidOut(fade);
      final layouts = box.layoutCount;

      fade.opacity = 0.25;

      expect(box.inheritedOpacity, closeTo(0.25, 1e-9));
      // The whole promise of the tier: a frame of a fade is a uniform write.
      expect(box.layoutCount, layouts);
    });

    test('writing the same value again does nothing', () {
      var refreshes = 0;
      final box = _CountingBox(() => refreshes++);
      final fade = Opacity3d(opacity: 0.5, child: box);
      laidOut(fade);
      final after = refreshes;

      fade.opacity = 0.5;

      expect(refreshes, after);
    });

    test('a box laid out inside a faded subtree is born faded', () {
      // The difference from the clip, and the reason this needs no second
      // pass: an opacity is known before the subtree is laid out, so the
      // first value a box ever sees is already the right one.
      var seen = -1.0;
      final box = _CountingBox(null, onRefresh: (value) => seen = value);
      laidOut(Opacity3d(opacity: 0.3, child: box));
      expect(box.inheritedOpacity, closeTo(0.3, 1e-9));
      expect(seen, -1.0, reason: 'nothing changed, so nothing was republished');
    });
  });

  group('what it reaches', () {
    test('a decorated panel is handed the opacity on every paint', () {
      final painter = FadeRecordingPainter();
      BoxDecoration3d.painterFactory = (_) => painter;

      final panel = DecoratedBox3d(
        decoration: const BoxDecoration3d(color: Color(0xFF203040)),
      );
      final fade = Opacity3d(opacity: 1.0, child: panel);
      laidOut(fade, constraints: Constraints3d.tight(const Size3d(1, 1, 0.1)));
      expect(painter.lastOpacity, 1.0);

      fade.opacity = 0.2;
      expect(painter.lastOpacity, closeTo(0.2, 1e-9));
    });

    test('the uniforms carry it as a fade rather than folding it in', () {
      const color = Color(0xFF3366CC);
      final uniforms = BoxDecoration3dUniforms.resolve(
        decoration: const BoxDecoration3d(color: color),
        size: const Size3d(1, 1, 0.1),
        metrics: Layout3dMetrics.standard,
        opacity: 0.4,
      );
      expect(uniforms.opacity, 0.4);
      // **The colour is untouched**, which is the whole design: folding the
      // opacity in here would mean folding it into the border, the tint, the
      // state layer and every gradient stop as well, and would still leave a
      // partly transparent slab writing depth.
      expect(uniforms.color, color);
    });

    test('a label hands it to its glyph material', () {
      final original = GlyphMaterial3d.factory;
      addTearDown(() => GlyphMaterial3d.factory = original);
      GlyphMaterial3d.factory = FadeRecordingGlyphMaterial.new;

      final renderer = _RecordingTextRenderer();
      final label = Text3d(
        'Ag',
        style: const TextStyle(fontSize: 14),
        renderer: renderer,
      );
      final fade = Opacity3d(opacity: 1.0, child: label);
      laidOut(fade);
      expect(renderer.lastOpacity, 1.0);

      fade.opacity = 0.35;
      expect(renderer.lastOpacity, closeTo(0.35, 1e-9));
      // A republish and not a relayout: the renderer is asked again with the
      // same layout object it was given before.
      expect(renderer.renders, greaterThan(1));
      expect(
        identical(
          renderer.requests.last.layout,
          renderer.requests.first.layout,
        ),
        isTrue,
      );
    });

    test('a NodeBox3d spends it on the callback it was given', () {
      final seen = <double>[];
      final box = NodeBox3d(
        content: Node(),
        explicitSize: const Size3d(1, 1, 0),
        onFade: seen.add,
      );
      final fade = Opacity3d(opacity: 1.0, child: box);
      laidOut(fade);
      expect(seen.last, 1.0);

      fade.opacity = 0.5;
      expect(seen.last, closeTo(0.5, 1e-9));
    });

    test('a NodeBox3d that cannot fade says so instead of drawing solid', () {
      final box = NodeBox3d(
        content: Node(),
        explicitSize: const Size3d(1, 1, 0),
        name: 'model',
      );
      final fade = Opacity3d(opacity: 1.0, child: box);
      laidOut(fade);

      expect(() => fade.opacity = 0.5, throwsA(isA<AssertionError>()));
    });
  });

  group('FadeTransition3d', () {
    testWidgets('follows its animation without laying anything out', (
      tester,
    ) async {
      final controller = AnimationController(
        duration: const Duration(milliseconds: 100),
        vsync: tester,
      );
      addTearDown(controller.dispose);

      final box = TestBox(const Size3d(1, 1, 0));
      final fade = FadeTransition3d(opacity: controller, child: box);
      laidOut(fade);
      expect(box.inheritedOpacity, 0.0);
      final layouts = box.layoutCount;

      controller.value = 0.5;
      expect(box.inheritedOpacity, closeTo(0.5, 1e-9));

      controller.forward();
      await tester.pumpAndSettle();
      expect(controller.status, AnimationStatus.completed);
      expect(box.inheritedOpacity, 1.0);
      expect(box.layoutCount, layouts);
    });

    testWidgets('lets go of an animation it is taken off', (tester) async {
      final first = AnimationController(vsync: tester, value: 0.2);
      final second = AnimationController(vsync: tester, value: 0.8);
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      final box = TestBox(const Size3d(1, 1, 0));
      final fade = FadeTransition3d(opacity: first, child: box);
      laidOut(fade);
      expect(box.inheritedOpacity, closeTo(0.2, 1e-9));

      fade.animation = second;
      expect(box.inheritedOpacity, closeTo(0.8, 1e-9));

      first.value = 0.0;
      expect(
        box.inheritedOpacity,
        closeTo(0.8, 1e-9),
        reason: 'the box is still listening to the animation it was taken off',
      );
    });
  });

  group('Motion3d', () {
    test('carries no fade unless it is asked for one', () {
      expect(Motion3d.none.opacity, 1.0);
      expect(const Motion3d.grow().opacity, 1.0);
      expect(Motion3d.none.isAtRest, isTrue);
      expect(const Motion3d.fade().opacity, 0.0);
      expect(const Motion3d.fade().isAtRest, isFalse);
    });

    test('arrives at full strength', () {
      const motion = Motion3d.fade();
      expect(motion.arrived(0.0).opacity, 0.0);
      expect(motion.arrived(0.5).opacity, closeTo(0.5, 1e-9));
      expect(motion.arrived(1.0).opacity, 1.0);
    });

    testWidgets('a transition imposes it on the subtree', (tester) async {
      final controller = AnimationController(
        duration: const Duration(milliseconds: 100),
        vsync: tester,
      );
      addTearDown(controller.dispose);

      final box = TestBox(const Size3d(1, 1, 0));
      final transition = MotionTransition3d(
        animation: controller,
        motion: const Motion3d(scale: 0.8, opacity: 0.0),
        child: box,
      );
      laidOut(transition);
      expect(box.inheritedOpacity, 0.0);

      controller.value = 0.5;
      expect(box.inheritedOpacity, closeTo(0.5, 1e-9));

      controller.value = 1.0;
      expect(box.inheritedOpacity, 1.0);
      // At rest the transition carries nothing at all, which is the rule
      // every node-tier box here keeps.
      expect(transition.nodeTransform, isNull);
    });

    testWidgets('a motion with no fade in it imposes nothing', (tester) async {
      final controller = AnimationController(
        duration: const Duration(milliseconds: 100),
        vsync: tester,
      );
      addTearDown(controller.dispose);

      final box = TestBox(const Size3d(1, 1, 0));
      laidOut(
        MotionTransition3d(
          animation: controller,
          motion: Motion3d.fromBelow,
          child: box,
        ),
      );
      expect(box.inheritedOpacity, 1.0);
    });
  });
}

/// A leaf that counts how often it is told the opacity changed.
class _CountingBox extends Layout3d {
  _CountingBox(this._onRefresh, {this.onRefresh});

  final void Function()? _onRefresh;
  final void Function(double opacity)? onRefresh;

  @override
  void refreshOpacity() {
    _onRefresh?.call();
    onRefresh?.call(inheritedOpacity);
  }

  @override
  void performLayout() {
    size = constraints.constrain(const Size3d(1, 1, 0));
  }
}

/// A renderer that records the requests it is handed and draws nothing.
class _RecordingTextRenderer extends Text3dRenderer {
  final List<Text3dRenderRequest> requests = <Text3dRenderRequest>[];

  int get renders => requests.length;

  double get lastOpacity => requests.last.opacity;

  @override
  void render(Text3dRenderRequest request) => requests.add(request);

  @override
  void dispose() {}
}
