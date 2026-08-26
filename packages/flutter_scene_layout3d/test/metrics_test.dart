// The unit contract: how many world units a logical pixel is worth, who owns
// the number, and what changing it costs.

import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('Layout3dMetrics', () {
    test('the default is one unit to a hundred logical pixels', () {
      const metrics = Layout3dMetrics.standard;
      expect(metrics.unitsPerLogicalPixel, 0.01);
      expect(metrics.logicalPixelsPerUnit, 100);
      expect(metrics.dp(48), closeTo(0.48, 1e-12));
    });

    test('dp and toLogicalPixels invert each other', () {
      const metrics = Layout3dMetrics(unitsPerLogicalPixel: 0.0025);
      expect(metrics.dp(48), closeTo(0.12, 1e-12));
      expect(metrics.toLogicalPixels(metrics.dp(48)), closeTo(48, 1e-12));
    });

    test('sp scales type and dp does not', () {
      const metrics = Layout3dMetrics(
        unitsPerLogicalPixel: 0.01,
        textScaleFactor: 1.5,
      );
      expect(metrics.sp(14), closeTo(0.21, 1e-12));
      expect(metrics.dp(14), closeTo(0.14, 1e-12));
    });

    test('dpSize leaves depth at zero unless asked', () {
      const metrics = Layout3dMetrics();
      expect(metrics.dpSize(100, 50), const Size3d(1, 0.5, 0));
      expect(metrics.dpSize(100, 50, 10), const Size3d(1, 0.5, 0.1));
    });

    test('equality is by value, so an unchanged assignment is a no-op', () {
      const a = Layout3dMetrics(unitsPerLogicalPixel: 0.02);
      const b = Layout3dMetrics(unitsPerLogicalPixel: 0.02);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const Layout3dMetrics(unitsPerLogicalPixel: 0.03)));
      expect(
        a,
        isNot(
          const Layout3dMetrics(
            unitsPerLogicalPixel: 0.02,
            density: VisualDensity3d.compact,
          ),
        ),
      );
    });

    test('copyWith replaces one dial and keeps the rest', () {
      const metrics = Layout3dMetrics(
        unitsPerLogicalPixel: 0.02,
        textScaleFactor: 1.3,
      );
      final scaled = metrics.copyWith(density: VisualDensity3d.compact);
      expect(scaled.unitsPerLogicalPixel, 0.02);
      expect(scaled.textScaleFactor, 1.3);
      expect(scaled.density, VisualDensity3d.compact);
    });
  });

  group('VisualDensity3d', () {
    test('a unit of density is four logical pixels, on all three axes', () {
      const density = VisualDensity3d(horizontal: -1, vertical: 2, depth: -3);
      expect(density.baseSizeAdjustment, const Offset3d(-4, 8, -12));
    });

    test('the built-in densities match Flutter\'s', () {
      expect(VisualDensity3d.standard.baseSizeAdjustment, Offset3d.zero);
      expect(
        VisualDensity3d.comfortable.baseSizeAdjustment,
        const Offset3d(-4, -4, 0),
      );
      expect(
        VisualDensity3d.compact.baseSizeAdjustment,
        const Offset3d(-8, -8, 0),
      );
    });

    test('lerp walks each dial', () {
      final half = VisualDensity3d.lerp(
        VisualDensity3d.standard,
        VisualDensity3d.compact,
        0.5,
      );
      expect(half.horizontal, -1);
      expect(half.vertical, -1);
      expect(half.depth, 0);
    });
  });

  group('effectiveConstraints', () {
    test(
      'converts the adjustment out of logical pixels before applying it',
      () {
        const metrics = Layout3dMetrics(
          unitsPerLogicalPixel: 0.01,
          density: VisualDensity3d(horizontal: 1, vertical: 1, depth: 1),
        );
        // One unit of density is four logical pixels, and a logical pixel is a
        // hundredth of a world unit, so each minimum grows by 0.04.
        final grown = metrics.effectiveConstraints(
          Constraints3d.tight(const Size3d(1, 1, 1)),
        );
        expect(grown.minWidth, closeTo(1.0, 1e-12));
        expect(grown.minHeight, closeTo(1.0, 1e-12));
        // A tight constraint has nowhere to grow: the minimum is clamped to the
        // maximum it already had.
        expect(grown.maxWidth, 1.0);

        final loose = metrics.effectiveConstraints(
          Constraints3d.loose(const Size3d(2, 2, 2)),
        );
        expect(loose.minWidth, closeTo(0.04, 1e-12));
        expect(loose.minHeight, closeTo(0.04, 1e-12));
        expect(loose.minDepth, closeTo(0.04, 1e-12));
      },
    );

    test('a negative density never pulls a minimum below zero', () {
      const metrics = Layout3dMetrics(density: VisualDensity3d.compact);
      final tightened = metrics.effectiveConstraints(
        Constraints3d.loose(const Size3d(2, 2, 2)),
      );
      expect(tightened.minWidth, 0.0);
      expect(tightened.minHeight, 0.0);
    });

    test('the standard density is identity, and returns the same object', () {
      const metrics = Layout3dMetrics();
      final constraints = Constraints3d.loose(const Size3d(2, 2, 2));
      expect(
        identical(metrics.effectiveConstraints(constraints), constraints),
        isTrue,
      );
    });
  });

  group('the tree-wide channel', () {
    test('a detached layout reads the standard contract', () {
      final box = DpBox(100, 40);
      expect(box.attached, isFalse);
      expect(box.metrics, Layout3dMetrics.standard);
    });

    test('metrics reach a deep child through the owner', () {
      final box = DpBox(100, 40);
      final surface = laidOut(
        Padding3d(
          padding: const EdgeInsets3d.all(0.1),
          child: Center3d(child: box),
        ),
        metrics: const Layout3dMetrics(unitsPerLogicalPixel: 0.005),
      );
      expect(box.metrics, surface.metrics);
      expect(box.metrics.unitsPerLogicalPixel, 0.005);
      // 100 dp at 0.005 units to the pixel is half a unit.
      expect(box.size.width, closeTo(0.5, 1e-12));
    });

    test('changing the metrics relayouts the tree', () {
      final box = DpBox(100, 40);
      final surface = laidOut(Center3d(child: box));
      expect(box.layoutCount, 1);
      expect(box.size.width, closeTo(1.0, 1e-12));

      surface.metrics = const Layout3dMetrics(unitsPerLogicalPixel: 0.02);
      expect(surface.needsFlush, isTrue);
      surface.flush();
      expect(box.layoutCount, 2);
      expect(box.size.width, closeTo(2.0, 1e-12));
    });

    test('assigning an equal contract writes nothing', () {
      final box = DpBox(100, 40);
      final surface = laidOut(Center3d(child: box));
      surface.metrics = const Layout3dMetrics();
      expect(surface.needsFlush, isFalse);
      surface.flush();
      expect(box.layoutCount, 1);
    });

    test('the owner carries it beside the basis', () {
      final surface = laidOut(
        DpBox(100, 40),
        metrics: const Layout3dMetrics(unitsPerLogicalPixel: 0.004),
      );
      expect(surface.owner!.metrics.unitsPerLogicalPixel, 0.004);
      expect(surface.owner!.basis, LayoutBasis3d.xy);
    });
  });
}
