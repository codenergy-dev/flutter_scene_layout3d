// What a screen knows about itself: the reader's own font setting reaching a
// label on a plane, the extent a build method branches on, and the part of a
// surface the platform has already spent.
//
// The test font makes every glyph exactly `fontSize` wide, so a five-letter
// word at 10pt is 50 logical pixels — 0.5 world units at the default rate.

import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter/painting.dart' show EdgeInsets, TextScaler, TextStyle;
import 'package:flutter/widgets.dart'
    show
        Builder,
        BuildContext,
        MediaQuery,
        MediaQueryData,
        Orientation,
        SizedBox,
        StatelessWidget,
        Widget;
import 'package:flutter_scene/scene.dart' show Node, PerspectiveCamera;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/testing.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

const TextStyle style = TextStyle(fontSize: 10);

/// A camera in front of the plane, on the side [LayoutBasis3d.xy] puts the
/// viewer.
PerspectiveCamera frontCamera() => PerspectiveCamera(
  fovRadiansY: math.pi / 4,
  position: Vector3(0, 0, 5),
  target: Vector3(0, 0, 0),
);

/// Reports what the enclosing surface says about itself, and lays nothing out.
class ScreenReporter extends StatelessWidget {
  const ScreenReporter(this.seen, {super.key});

  final List<MediaQuery3dData> seen;

  @override
  Widget build(BuildContext context) {
    seen.add(MediaQuery3d.of(context));
    return const SceneSizedBox3d(width: 0.1, height: 0.1);
  }
}

/// A scaler that grows small type and leaves large type alone.
class ClampedScaler extends TextScaler {
  const ClampedScaler(this.factor, {required this.upTo});

  final double factor;
  final double upTo;

  @override
  double scale(double fontSize) =>
      fontSize <= upTo ? fontSize * factor : fontSize;

  @override
  double get textScaleFactor => factor;

  @override
  bool operator ==(Object other) =>
      other is ClampedScaler && other.factor == factor && other.upTo == upTo;

  @override
  int get hashCode => Object.hash(factor, upTo);
}

/// Wraps [child] in a platform view of [data]'s description.
Widget view(MediaQueryData data, Widget child) => MediaQuery(
  data: data,
  child: SizedBox.expand(child: child),
);

/// The one box the surface holds.
T childOf<T extends Layout3d>(Layout3dController controller) =>
    controller.surface!.child! as T;

/// The label under a centring box on [controller]'s surface.
Text3d labelOf(Layout3dController controller) =>
    childOf<Align3d>(controller).child! as Text3d;

void main() {
  group('the reader\'s font setting', () {
    testWidgets('reaches a label on a plane', (tester) async {
      final controller = Layout3dController();
      Widget frame(TextScaler scaler) => view(
        MediaQueryData(textScaler: scaler),
        SceneLayout3d(
          parent: Node(),
          controller: controller,
          size: const Size3d(4, 3, 0.5),
          child: const SceneCenter3d(
            child: ScenePadding3d(
              padding: EdgeInsets3d.all(0.1),
              child: SceneText3d('hello', style: style),
            ),
          ),
        ),
      );

      await tester.pumpWidget(frame(TextScaler.noScaling));
      // The same box across both pumps: a rebuild updates the layout object
      // rather than replacing it.
      final label = tester.layout3d<Text3d>(find3d.bySubtype<Text3d>());
      expect(label.size.width, closeTo(0.5, 1e-9));

      // The setting changes, and the label three boxes down is a different
      // box afterwards — through the metrics, which is the only channel a
      // performLayout has.
      await tester.pumpWidget(frame(TextScaler.linear(2)));
      expect(label.size.width, closeTo(1.0, 1e-9));
      expect(label.size.height, closeTo(0.2, 1e-9));
      expect(controller.surface!.metrics.textScaler, TextScaler.linear(2));
    });

    testWidgets('is TextScaler.noScaling with no MediaQuery above', (
      tester,
    ) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          controller: controller,
          size: const Size3d(4, 3, 0.5),
          child: const SceneCenter3d(child: SceneText3d('hello', style: style)),
        ),
      );
      expect(controller.surface!.metrics.textScaler, TextScaler.noScaling);
      expect(labelOf(controller).size.width, closeTo(0.5, 1e-9));
    });

    testWidgets('is written onto an authored contract, not over it', (
      tester,
    ) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        view(
          MediaQueryData(textScaler: TextScaler.linear(1.5)),
          SceneLayout3d(
            parent: Node(),
            controller: controller,
            // A smaller screen, the way the gallery's table panel states one.
            metrics: const Layout3dMetrics(unitsPerLogicalPixel: 0.02),
            size: const Size3d(4, 3, 0.5),
            child: const SceneCenter3d(
              child: SceneText3d('hello', style: style),
            ),
          ),
        ),
      );
      final metrics = controller.surface!.metrics;
      expect(metrics.unitsPerLogicalPixel, 0.02);
      expect(metrics.textScaler, TextScaler.linear(1.5));
      // Five glyphs of 10dp, grown by half, at fifty logical pixels to the
      // unit.
      expect(labelOf(controller).size.width, closeTo(1.5, 1e-9));
    });

    testWidgets('a metrics that states a scaler of its own is an error', (
      tester,
    ) async {
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 3, 0.5),
          metrics: Layout3dMetrics(textScaler: TextScaler.linear(2)),
        ),
      );
      expect(tester.takeException(), isAssertionError);
    });

    testWidgets('a binding that derives the metrics takes it from the view', (
      tester,
    ) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        view(
          MediaQueryData(textScaler: TextScaler.linear(1.5)),
          SceneLayout3d(
            parent: Node(),
            controller: controller,
            size: const Size3d(4, 3, 0.5),
            binding: const Layout3dCameraBinding.fixedDensity(0.005),
          ),
        ),
      );
      await tester.pump();
      expect(controller.surface!.metrics.textScaler, TextScaler.linear(1.5));
      expect(controller.surface!.metrics.unitsPerLogicalPixel, 0.005);
    });

    testWidgets('and a binding that states one ignores the platform', (
      tester,
    ) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        view(
          MediaQueryData(textScaler: TextScaler.linear(1.5)),
          SceneLayout3d(
            parent: Node(),
            controller: controller,
            size: const Size3d(4, 3, 0.5),
            binding: Layout3dCameraBinding.fixedDensity(
              0.005,
              textScaler: TextScaler.noScaling,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(controller.surface!.metrics.textScaler, TextScaler.noScaling);
    });

    testWidgets('a scaler that is not linear grows each size by its own', (
      tester,
    ) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        view(
          const MediaQueryData(textScaler: ClampedScaler(1.5, upTo: 15)),
          SceneLayout3d(
            parent: Node(),
            controller: controller,
            size: const Size3d(8, 3, 0.5),
            child: const SceneRow3d(
              children: <Widget>[
                SceneText3d('aa', style: TextStyle(fontSize: 10)),
                SceneText3d('bb', style: TextStyle(fontSize: 40)),
              ],
            ),
          ),
        ),
      );
      final labels = tester
          .layouts3d<Text3d>(find3d.bySubtype<Text3d>())
          .toList();
      // Ten-point type grows by half; forty-point type is already big enough
      // and does not — which is what a single multiplier could not say.
      expect(labels.first.size.width, closeTo(2 * 15 * 0.01, 1e-9));
      expect(labels.last.size.width, closeTo(2 * 40 * 0.01, 1e-9));
    });
  });

  group('what a screen knows about itself', () {
    testWidgets('an authored panel reports its own extent, in dp', (
      tester,
    ) async {
      final seen = <MediaQuery3dData>[];
      await tester.pumpWidget(
        view(
          const MediaQueryData(
            size: Size(800, 600),
            padding: EdgeInsets.only(top: 44, bottom: 34),
          ),
          SceneLayout3d(
            parent: Node(),
            size: const Size3d(4, 3, 0.5),
            child: ScreenReporter(seen),
          ),
        ),
      );
      final data = seen.last;
      // Four world units at a hundred logical pixels each.
      expect(data.size, const Size3d(400, 300, 50));
      expect(data.orientation, Orientation.landscape);
      // The whole decision, in one expectation: a plane in a room has no
      // notch, whatever the window it happens to be drawn in has.
      expect(data.padding, EdgeInsets3d.zero);
    });

    testWidgets('a taller panel is portrait, and a smaller rate is dp', (
      tester,
    ) async {
      final seen = <MediaQuery3dData>[];
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(3, 4, 0.5),
          metrics: const Layout3dMetrics(unitsPerLogicalPixel: 0.02),
          child: ScreenReporter(seen),
        ),
      );
      expect(seen.last.size, const Size3d(150, 200, 25));
      expect(seen.last.orientation, Orientation.portrait);
    });

    testWidgets('a surface that shrink-wraps has no screen size', (
      tester,
    ) async {
      final seen = <MediaQuery3dData>[];
      await tester.pumpWidget(
        SceneLayout3d(parent: Node(), child: ScreenReporter(seen)),
      );
      expect(seen.last.size.width, double.infinity);
      expect(seen.last.size.height, double.infinity);
    });

    testWidgets('a screen-filling surface reports the view and its insets', (
      tester,
    ) async {
      final controller = Layout3dController();
      final seen = <MediaQuery3dData>[];
      await tester.pumpWidget(
        view(
          const MediaQueryData(
            size: Size(800, 600),
            padding: EdgeInsets.only(top: 44, bottom: 34),
          ),
          SceneLayout3d(
            parent: Node(),
            controller: controller,
            camera: frontCamera(),
            binding: const Layout3dCameraBinding.screenFilling(
              distance: 2,
              depth: 0.5,
            ),
            child: ScreenReporter(seen),
          ),
        ),
      );
      await tester.pump();

      final data = seen.last;
      expect(data.size.width, closeTo(800, 1e-6));
      expect(data.size.height, closeTo(600, 1e-6));
      // The depth is the thickness the binding was given, stated in dp: the
      // round trip through the contract comes back where it started.
      expect(
        controller.surface!.metrics.dp(data.size.depth),
        closeTo(0.5, 1e-9),
      );
      // The panel covers the view exactly, so the view's safe area is its
      // own, dp for dp.
      expect(data.padding.top, 44);
      expect(data.padding.bottom, 34);
      expect(data.padding.left, 0);
    });

    testWidgets('of asserts with no surface above, maybeOf is null', (
      tester,
    ) async {
      MediaQuery3dData? outside;
      var threw = false;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            outside = MediaQuery3d.maybeOf(context);
            try {
              MediaQuery3d.of(context);
            } on AssertionError {
              threw = true;
            }
            return const SizedBox.shrink();
          },
        ),
      );
      expect(outside, isNull);
      expect(threw, isTrue);
    });
  });

  group('SceneSafeArea3d', () {
    Widget screen(
      Widget child, {
      EdgeInsets3d padding = const EdgeInsets3d.only(top: 44, bottom: 34),
      Layout3dController? controller,
    }) => SceneLayout3d(
      parent: Node(),
      controller: controller,
      size: const Size3d(4, 3, 0.5),
      child: MediaQuery3d(
        data: MediaQuery3dData(
          size: const Size3d(400, 300, 50),
          padding: padding,
        ),
        child: child,
      ),
    );

    testWidgets('insets the child by what the platform spent', (tester) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        screen(
          const SceneSafeArea3d(child: SceneSizedBox3d(width: 1, height: 1)),
          controller: controller,
        ),
      );
      final padding = childOf<Padding3d>(controller).padding as EdgeInsets3d;
      // Logical pixels in, world units out: 44dp is 0.44 at the default rate.
      expect(padding.top, closeTo(0.44, 1e-9));
      expect(padding.bottom, closeTo(0.34, 1e-9));
      expect(padding.left, 0);
      expect(padding.front, 0);
    });

    testWidgets('a second one inside it pads nothing', (tester) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        screen(
          const SceneSafeArea3d(
            child: SceneSafeArea3d(child: SceneSizedBox3d(width: 1, height: 1)),
          ),
          controller: controller,
        ),
      );
      final outer = childOf<Padding3d>(controller);
      final inner = outer.child! as Padding3d;
      expect((outer.padding as EdgeInsets3d).top, closeTo(0.44, 1e-9));
      expect(inner.padding, EdgeInsets3d.zero);
    });

    testWidgets('a side it is told to leave alone is left alone', (
      tester,
    ) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        screen(
          const SceneSafeArea3d(
            top: false,
            child: SceneSizedBox3d(width: 1, height: 1),
          ),
          controller: controller,
        ),
      );
      final padding = childOf<Padding3d>(controller).padding as EdgeInsets3d;
      expect(padding.top, 0);
      expect(padding.bottom, closeTo(0.34, 1e-9));
    });

    testWidgets('the minimum applies where it is the larger', (tester) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        screen(
          const SceneSafeArea3d(
            minimum: EdgeInsets3d.all(50),
            child: SceneSizedBox3d(width: 1, height: 1),
          ),
          controller: controller,
        ),
      );
      final padding = childOf<Padding3d>(controller).padding as EdgeInsets3d;
      // The platform's 44 loses to the stated 50; its 34 does too; the sides
      // it says nothing about get the minimum outright.
      expect(padding.top, closeTo(0.5, 1e-9));
      expect(padding.bottom, closeTo(0.5, 1e-9));
      expect(padding.left, closeTo(0.5, 1e-9));
    });

    testWidgets('on a panel with no safe area it insets nothing', (
      tester,
    ) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          controller: controller,
          size: const Size3d(4, 3, 0.5),
          child: const SceneSafeArea3d(
            child: SceneSizedBox3d(width: 1, height: 1),
          ),
        ),
      );
      expect(childOf<Padding3d>(controller).padding, EdgeInsets3d.zero);
    });
  });
}
