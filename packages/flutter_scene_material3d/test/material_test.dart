// Material3d: the one primitive, and the promise that a token becomes a
// BoxDecoration3d in exactly one place.

import 'dart:ui' show Color;

import 'package:flutter/widgets.dart'
    show Builder, BuildContext, DefaultTextStyle, TextStyle, Widget;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('the decoration a token resolves to', () {
    testWidgets('a bare surface is the theme, family by family', (
      tester,
    ) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 3, 0.5),
          controller: controller,
          child: const SceneTheme3d(
            data: Theme3dData.light,
            child: Material3d(),
          ),
        ),
      );

      final box = decoratedBoxIn(controller.surface!);
      final decoration = box.decoration as BoxDecoration3d;
      const theme = Theme3dData.light;
      expect(decoration.color, theme.colorScheme.surface);
      expect(decoration.borderRadius, theme.shape.none);
      expect(decoration.elevation, theme.elevation.level0);
      expect(decoration.surfaceTint, theme.colorScheme.surfaceTint);
      // The bevel is a quarter of the thickness, which is the rule a flat
      // specification has no reason to state and a slab cannot do without.
      expect(decoration.bevel, theme.shape.bevelFor(theme.thickness.standard));
    });

    testWidgets('every property overrides its token', (tester) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 3, 0.5),
          controller: controller,
          child: SceneTheme3d(
            data: Theme3dData.light,
            child: Material3d(
              color: const Color(0xFF112233),
              shape: Theme3dData.light.shape.large,
              elevation: 6.0,
              thickness: 8.0,
              border: const Border3d(width: 2, color: Color(0xFF445566)),
              surfaceTint: const Color(0xFF778899),
            ),
          ),
        ),
      );

      final decoration =
          decoratedBoxIn(controller.surface!).decoration as BoxDecoration3d;
      expect(decoration.color, const Color(0xFF112233));
      expect(decoration.borderRadius, Theme3dData.light.shape.large);
      expect(decoration.elevation, 6.0);
      expect(decoration.border.width, 2.0);
      expect(decoration.surfaceTint, const Color(0xFF778899));
      expect(decoration.bevel, 2.0, reason: 'a quarter of 8dp');
    });

    testWidgets('the dark theme changes only the colours', (tester) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 3, 0.5),
          controller: controller,
          child: const SceneTheme3d(
            data: Theme3dData.dark,
            child: Material3d(),
          ),
        ),
      );

      final decoration =
          decoratedBoxIn(controller.surface!).decoration as BoxDecoration3d;
      expect(decoration.color, ColorScheme3d.dark.surface);
      expect(decoration.bevel, Theme3dData.light.shape.bevelFor(2.0));
    });
  });

  group('the slab it lays out', () {
    testWidgets('is the thickness token deep, in world units', (tester) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          // Loose, so the surface does not decide the depth for it. A tight
          // constraint wins over a dp figure exactly as it does in Flutter,
          // which is the first thing that catches a component author out.
          constraints: Constraints3d.loose(const Size3d(4, 3, 1)),
          controller: controller,
          child: const SceneTheme3d(
            data: Theme3dData.light,
            child: Material3d(thickness: 8.0),
          ),
        ),
      );

      // 8dp at the default rate of 0.01 units per logical pixel.
      expect(
        decoratedBoxIn(controller.surface!).size.depth,
        closeTo(0.08, 1e-9),
      );
    });

    testWidgets('follows the surface unit contract', (tester) async {
      final controller = Layout3dController();
      Widget frame(Layout3dMetrics metrics) => SceneLayout3d(
        parent: Node(),
        constraints: Constraints3d.loose(const Size3d(4, 3, 1)),
        metrics: metrics,
        controller: controller,
        child: const SceneTheme3d(
          data: Theme3dData.light,
          child: Material3d(thickness: 8.0),
        ),
      );

      await tester.pumpWidget(frame(Layout3dMetrics.standard));
      expect(
        decoratedBoxIn(controller.surface!).size.depth,
        closeTo(0.08, 1e-9),
      );

      // The whole point of reading the metrics in build: the token is still
      // 8dp and the slab is twice as deep.
      await tester.pumpWidget(
        frame(const Layout3dMetrics(unitsPerLogicalPixel: 0.02)),
      );
      expect(
        decoratedBoxIn(controller.surface!).size.depth,
        closeTo(0.16, 1e-9),
      );
    });

    testWidgets('pads its child in logical pixels', (tester) async {
      final controller = Layout3dController();
      late TestBox child;
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 3, 0.5),
          controller: controller,
          child: SceneTheme3d(
            data: Theme3dData.light,
            child: Material3d(
              padding: const EdgeInsets3d.symmetric(
                horizontal: 24,
                vertical: 10,
              ),
              child: SceneTestBox(const Size3d(10, 10, 0), (b) => child = b),
            ),
          ),
        ),
      );

      // The surface is 4 units wide; 24dp either side is 0.24 units each.
      expect(child.size.width, closeTo(4.0 - 0.48, 1e-9));
      expect(child.size.height, closeTo(3.0 - 0.20, 1e-9));
    });

    testWidgets('sits its child on the front face, not in the middle', (
      tester,
    ) async {
      // A label centred in depth is a label inside the slab, which the panel
      // wins the depth test against. frontCenter is the default for exactly
      // that reason, and it is a claim about an offset rather than a picture.
      final controller = Layout3dController();
      late TestBox child;
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 3, 0.5),
          controller: controller,
          child: SceneTheme3d(
            data: Theme3dData.light,
            child: Material3d(
              thickness: 8.0,
              child: SceneTestBox(const Size3d(1, 1, 0), (b) => child = b),
            ),
          ),
        ),
      );

      expect(child.offset.z, 0.0);
    });
  });

  group('the text style it installs', () {
    testWidgets('is the theme body style in the content colour', (
      tester,
    ) async {
      late TextStyle seen;
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 3, 0.5),
          child: SceneTheme3d(
            data: Theme3dData.light,
            child: Material3d(
              child: Builder(
                builder: (BuildContext context) {
                  seen = DefaultTextStyle.of(context).style;
                  return const SceneSizedBox3d.cube(0.1);
                },
              ),
            ),
          ),
        ),
      );

      expect(seen.fontSize, Theme3dData.light.typography.bodyMedium.fontSize);
      expect(seen.color, ColorScheme3d.light.onSurface);
    });

    testWidgets('takes the content colour a component hands it', (
      tester,
    ) async {
      late TextStyle seen;
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 3, 0.5),
          child: SceneTheme3d(
            data: Theme3dData.light,
            child: Material3d(
              color: ColorScheme3d.light.primary,
              contentColor: ColorScheme3d.light.onPrimary,
              textStyle: Theme3dData.light.textStyle(
                Typography3dToken.labelLarge,
                color: ColorScheme3d.light.onPrimary,
              ),
              child: Builder(
                builder: (BuildContext context) {
                  seen = DefaultTextStyle.of(context).style;
                  return const SceneSizedBox3d.cube(0.1);
                },
              ),
            ),
          ),
        ),
      );

      expect(seen.fontSize, Theme3dData.light.typography.labelLarge.fontSize);
      expect(seen.color, ColorScheme3d.light.onPrimary);
    });
  });
}
