// The unit contract as a `build` method reads it: what a surface publishes,
// when a dependent hears about a change, and where that lands relative to the
// layout the change governs.

import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter/widgets.dart'
    show BuildContext, StatelessWidget, Widget;
import 'package:flutter_scene/scene.dart' show Node, PerspectiveCamera;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

/// A camera in front of the plane, on the side [LayoutBasis3d.xy] puts the
/// viewer.
PerspectiveCamera frontCamera() => PerspectiveCamera(
  fovRadiansY: math.pi / 4,
  position: Vector3(0, 0, 5),
  target: Vector3(0, 0, 0),
);

/// A leaf of a fixed *world* size that records every layout it is put
/// through, and the rate in force when it happened.
///
/// It never reads the scope, which is the point of it: a metrics change has to
/// relayout this box too, and no rebuild would ever tell it so.
class RecorderBox extends Layout3d {
  RecorderBox(this.log);

  final List<String> log;

  int layoutCount = 0;

  @override
  void performLayout() {
    layoutCount++;
    log.add('layout@${metrics.unitsPerLogicalPixel}');
    size = constraints.constrain(const Size3d(0.5, 0.5, 0.5));
  }
}

/// The widget form of [RecorderBox].
class SceneRecorder3d extends Layout3dWidget {
  const SceneRecorder3d(this.log, {super.key});

  final List<String> log;

  @override
  List<Widget> get children => const <Widget>[];

  @override
  RecorderBox createLayout(BuildContext context) => RecorderBox(log);

  @override
  void updateLayout(BuildContext context, RecorderBox layout) {}
}

/// A leaf that writes the surface's contract from inside its own layout.
///
/// The shape `Overlay3d` has when it pushes the host's metrics onto a detached
/// entry's surface: a write from inside a layout pass, which no rebuild can be
/// scheduled for.
class WriterBox extends Layout3d {
  WriterBox(this.write);

  final void Function() write;

  bool _written = false;

  @override
  void performLayout() {
    if (!_written) {
      _written = true;
      write();
    }
    size = constraints.constrain(Size3d.zero);
  }
}

/// The widget form of [WriterBox].
class SceneWriter3d extends Layout3dWidget {
  const SceneWriter3d(this.write, {super.key});

  final void Function() write;

  @override
  List<Widget> get children => const <Widget>[];

  @override
  WriterBox createLayout(BuildContext context) => WriterBox(write);

  @override
  void updateLayout(BuildContext context, WriterBox layout) {}
}

/// A component-shaped widget: it states its figures in logical pixels and
/// converts them in `build`, the way a Material component will.
class DpPanel extends StatelessWidget {
  const DpPanel({
    super.key,
    this.widthDp = 120,
    this.heightDp = 40,
    this.paddingDp = 8,
    this.log,
    this.child,
  });

  final double widthDp;
  final double heightDp;
  final double paddingDp;
  final List<String>? log;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final metrics = Layout3dMetricsScope.of(context);
    log?.add('build@${metrics.unitsPerLogicalPixel}');
    return ScenePadding3d(
      padding: metrics.dpInsets(EdgeInsets3d.all(paddingDp)),
      child: SceneSizedBox3d(
        width: metrics.dp(widthDp),
        height: metrics.dp(heightDp),
        child: child,
      ),
    );
  }
}

/// The padded box the [DpPanel] built.
Padding3d paddingOf(Layout3dController controller) =>
    controller.surface!.child! as Padding3d;

/// The sized box inside it.
SizedBox3d sizedOf(Layout3dController controller) =>
    paddingOf(controller).child! as SizedBox3d;

void main() {
  group('reading the contract from a build method', () {
    testWidgets('a dp figure resolves at the rate the surface states', (
      tester,
    ) async {
      final controller = Layout3dController();
      Widget frame(double unitsPerLogicalPixel) => SceneLayout3d(
        parent: Node(),
        controller: controller,
        constraints: Constraints3d.loose(const Size3d(10, 10, 10)),
        metrics: Layout3dMetrics(unitsPerLogicalPixel: unitsPerLogicalPixel),
        child: const DpPanel(),
      );

      // A hundred logical pixels to the unit: 120dp is 1.2 units, and an 8dp
      // padding is 0.08 on each face.
      await tester.pumpWidget(frame(0.01));
      expect(sizedOf(controller).size.width, closeTo(1.2, 1e-9));
      expect(sizedOf(controller).size.height, closeTo(0.4, 1e-9));
      expect(paddingOf(controller).padding.left, closeTo(0.08, 1e-9));

      // Two hundred to the unit: the same sentence, half the world.
      await tester.pumpWidget(frame(0.005));
      expect(sizedOf(controller).size.width, closeTo(0.6, 1e-9));
      expect(sizedOf(controller).size.height, closeTo(0.2, 1e-9));
      expect(paddingOf(controller).padding.left, closeTo(0.04, 1e-9));
    });

    testWidgets('and follows a contract written on the surface itself', (
      tester,
    ) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          controller: controller,
          constraints: Constraints3d.loose(const Size3d(10, 10, 10)),
          child: const DpPanel(),
        ),
      );
      expect(sizedOf(controller).size.width, closeTo(1.2, 1e-9));

      // Nothing rebuilt this widget: the surface was written imperatively,
      // the way a binding writes it.
      controller.surface!.metrics = const Layout3dMetrics(
        unitsPerLogicalPixel: 0.02,
      );
      await tester.pump();
      expect(sizedOf(controller).size.width, closeTo(2.4, 1e-9));
      expect(paddingOf(controller).padding.left, closeTo(0.16, 1e-9));
    });

    testWidgets('an equal contract rebuilds nothing', (tester) async {
      final controller = Layout3dController();
      final log = <String>[];
      // The same widget instance twice: an identical widget is not rebuilt,
      // so every build in the log came from the scope.
      final frame = SceneLayout3d(
        parent: Node(),
        controller: controller,
        constraints: Constraints3d.loose(const Size3d(10, 10, 10)),
        child: DpPanel(log: log),
      );

      await tester.pumpWidget(frame);
      expect(log, <String>['build@0.01']);

      controller.surface!.metrics = const Layout3dMetrics();
      await tester.pump();
      expect(log, <String>['build@0.01']);

      controller.surface!.metrics = const Layout3dMetrics(
        unitsPerLogicalPixel: 0.02,
      );
      await tester.pump();
      expect(log, <String>['build@0.01', 'build@0.02']);
    });

    testWidgets('a box that never reads the scope is relaid out anyway', (
      tester,
    ) async {
      final controller = Layout3dController();
      final log = <String>[];
      final frame = SceneLayout3d(
        parent: Node(),
        controller: controller,
        constraints: Constraints3d.loose(const Size3d(10, 10, 10)),
        child: SceneRecorder3d(log),
      );

      await tester.pumpWidget(frame);
      final recorder = controller.surface!.child! as RecorderBox;
      expect(recorder.layoutCount, 1);

      // Writing the contract relayouts the subtree, by design, and that is
      // what keeps a `metrics.dp(48)` box correct when no widget rebuilt it.
      controller.surface!.metrics = const Layout3dMetrics(
        unitsPerLogicalPixel: 0.02,
      );
      await tester.pump();
      expect(recorder.layoutCount, 2);
      expect(log, <String>['layout@0.01', 'layout@0.02']);
    });

    testWidgets('maybeOf is null with no surface above, and of asserts', (
      tester,
    ) async {
      Layout3dMetrics? seen;
      var sawAssert = false;
      await tester.pumpWidget(
        Builder3dProbe(
          onBuild: (context) {
            seen = Layout3dMetricsScope.maybeOf(context);
            try {
              Layout3dMetricsScope.of(context);
            } on AssertionError {
              sawAssert = true;
            }
          },
        ),
      );
      expect(seen, isNull);
      expect(sawAssert, isTrue);
    });
  });

  group('when the change lands', () {
    testWidgets('a derived contract reaches build before it reaches layout', (
      tester,
    ) async {
      final controller = Layout3dController();
      final log = <String>[];
      Widget frame(Size viewSize) => SceneLayout3d(
        parent: Node(),
        controller: controller,
        camera: frontCamera(),
        viewSize: viewSize,
        binding: const Layout3dCameraBinding.screenFilling(distance: 2),
        child: DpPanel(log: log, child: SceneRecorder3d(log)),
      );

      await tester.pumpWidget(frame(const Size(800, 600)));
      // The binding runs after the frame, so its contract lands on the next
      // one — the same one-frame lag the constraints have had all along.
      await tester.pump();
      final first = controller.surface!.metrics.unitsPerLogicalPixel;

      log.clear();
      await tester.pumpWidget(frame(const Size(800, 300)));
      await tester.pump();
      final second = controller.surface!.metrics.unitsPerLogicalPixel;
      expect(second, isNot(closeTo(first, 1e-12)));

      // The claim, stated as an order of events: nothing was laid out at the
      // new rate before a build had run at it. A padding computed in `build`
      // is therefore never measured against a rate the boxes below do not
      // have.
      final firstAtNewRate = log.indexWhere(
        (event) => event.endsWith('$second'),
      );
      expect(firstAtNewRate, isNonNegative);
      expect(log[firstAtNewRate], 'build@$second');
      expect(
        log.indexOf('build@$second'),
        lessThan(log.indexOf('layout@$second')),
      );

      // And what `build` computed is the new rate's figure. A screen-filling
      // surface is tight, so the padding is the honest witness: a SizedBox3d
      // under it is stretched to the panel whatever it asked for.
      expect(paddingOf(controller).padding.left, closeTo(8 * second, 1e-9));
    });

    testWidgets('a write from inside a layout pass defers to the next frame', (
      tester,
    ) async {
      final controller = Layout3dController();
      final log = <String>[];
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          controller: controller,
          constraints: Constraints3d.loose(const Size3d(10, 10, 10)),
          child: DpPanel(
            log: log,
            child: SceneWriter3d(
              () => controller.surface!.metrics = const Layout3dMetrics(
                unitsPerLogicalPixel: 0.02,
              ),
            ),
          ),
        ),
      );

      // The shape `Overlay3d` really has: it pushes the host's contract onto a
      // detached entry's surface from inside `performLayout`. Marking an
      // element dirty for a pass already running is either illegal or too late
      // to help it, so the rebuild is deferred to the next frame — and what
      // `build` converted is stale until then, which is why nothing on a
      // per-frame path may write the contract.
      expect(tester.takeException(), isNull);
      expect(controller.surface!.metrics.unitsPerLogicalPixel, 0.02);
      expect(log, <String>['build@0.01']);
      expect(sizedOf(controller).size.width, closeTo(1.2, 1e-9));

      // Deferred, not lost, and in the order every other path has: the build
      // that converts the figure, then the layout that uses what it converted.
      await tester.pump();
      expect(log, <String>['build@0.01', 'build@0.02']);
      expect(sizedOf(controller).size.width, closeTo(2.4, 1e-9));
    });
  });

  group('who owns the contract', () {
    testWidgets('a metrics-deriving binding refuses a metrics of its own', (
      tester,
    ) async {
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 3, 0.5),
          metrics: const Layout3dMetrics(unitsPerLogicalPixel: 0.01),
          binding: const Layout3dCameraBinding.fixedDensity(0.005),
        ),
      );
      expect(tester.takeException(), isAssertionError);
    });

    testWidgets('a billboard binding leaves the authored contract alone', (
      tester,
    ) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          controller: controller,
          camera: frontCamera(),
          size: const Size3d(4, 3, 0.5),
          metrics: const Layout3dMetrics(unitsPerLogicalPixel: 0.004),
          binding: const Layout3dCameraBinding.billboard(),
          child: const DpPanel(),
        ),
      );
      await tester.pump();
      expect(controller.surface!.metrics.unitsPerLogicalPixel, 0.004);
      expect(paddingOf(controller).padding.left, closeTo(0.032, 1e-9));
    });

    testWidgets('dropping the property puts the standard contract back', (
      tester,
    ) async {
      final controller = Layout3dController();
      Widget frame({Layout3dMetrics? metrics}) => SceneLayout3d(
        parent: Node(),
        controller: controller,
        constraints: Constraints3d.loose(const Size3d(10, 10, 10)),
        metrics: metrics,
        child: const DpPanel(),
      );

      await tester.pumpWidget(
        frame(metrics: const Layout3dMetrics(unitsPerLogicalPixel: 0.02)),
      );
      expect(sizedOf(controller).size.width, closeTo(2.4, 1e-9));

      await tester.pumpWidget(frame());
      expect(controller.surface!.metrics, Layout3dMetrics.standard);
      expect(sizedOf(controller).size.width, closeTo(1.2, 1e-9));
    });
  });
}

/// A widget that runs [onBuild] with its own context and draws nothing.
class Builder3dProbe extends StatelessWidget {
  const Builder3dProbe({super.key, required this.onBuild});

  final void Function(BuildContext context) onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild(context);
    return SceneLayout3d(parent: Node(), size: const Size3d(1, 1, 1));
  }
}
