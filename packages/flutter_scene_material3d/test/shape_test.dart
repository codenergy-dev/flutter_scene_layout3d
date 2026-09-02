// ShapeScale3d: Material 3's corner radii, and the bevel rule a slab needs.

import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show BorderRadius3d, Layout3dMetrics, Size3d;
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const shape = ShapeScale3d.baseline;

  group('the baseline scale', () {
    test('is Material 3\'s published steps, in logical pixels', () {
      expect(shape.none, BorderRadius3d.zero);
      expect(shape.extraSmall, const BorderRadius3d.circular(4.0));
      expect(shape.small, const BorderRadius3d.circular(8.0));
      expect(shape.medium, const BorderRadius3d.circular(12.0));
      expect(shape.large, const BorderRadius3d.circular(16.0));
      expect(shape.extraLarge, const BorderRadius3d.circular(28.0));
    });

    test('climbs', () {
      final steps = <BorderRadius3d>[
        shape.none,
        shape.extraSmall,
        shape.small,
        shape.medium,
        shape.large,
        shape.extraLarge,
        shape.full,
      ];
      for (var i = 1; i < steps.length; i++) {
        expect(steps[i].largest, greaterThan(steps[i - 1].largest));
      }
    });

    test('every step is the same on all four corners', () {
      for (final step in <BorderRadius3d>[
        shape.extraSmall,
        shape.small,
        shape.medium,
        shape.large,
        shape.extraLarge,
        shape.full,
      ]) {
        expect(step.topLeft, step.topRight);
        expect(step.topLeft, step.bottomLeft);
        expect(step.topLeft, step.bottomRight);
      }
    });
  });

  group('full', () {
    test('resolves to a stadium on any box', () {
      // Material's `full` is "half the shorter side", which BorderRadius3d
      // has no rule for — but resolve() already scales radii down to what a
      // box can fit, so an absurdly large radius *is* a stadium once
      // resolved.
      const metrics = Layout3dMetrics.standard;
      final units = shape.full * metrics.unitsPerLogicalPixel;
      for (final size in <Size3d>[
        const Size3d(1.0, 0.4, 0.02),
        const Size3d(0.4, 1.0, 0.02),
        const Size3d(0.05, 0.05, 0.0),
      ]) {
        final resolved = units.resolve(size);
        final half =
            0.5 * (size.width < size.height ? size.width : size.height);
        expect(resolved.topLeft, closeTo(half, 1e-9), reason: '$size');
        expect(resolved.bottomRight, closeTo(half, 1e-9), reason: '$size');
      }
    });

    test(
      'is a finite absurdity, because infinity does not survive resolve',
      () {
        // The reason fullRadius is 1000 and not double.infinity: resolve()
        // scales every radius by extent / sum, which is zero against an
        // infinite sum, and infinity * 0 is NaN. In debug that trips
        // BorderRadius3d's own `>= 0` assert (NaN fails it); in release it is a
        // NaN radius reaching a shader uniform, which draws nothing at all with
        // no error anywhere. A large finite radius resolves cleanly instead.
        expect(ShapeScale3d.fullRadius, 1000.0);
        expect(ShapeScale3d.fullRadius.isFinite, isTrue);
        expect(
          () => const BorderRadius3d.circular(
            double.infinity,
          ).resolve(const Size3d(1.0, 0.4, 0.0)),
          throwsA(isA<AssertionError>()),
        );
        final resolved = shape.full.resolve(const Size3d(1.0, 0.4, 0.0));
        expect(resolved.topLeft.isNaN, isFalse);
        expect(resolved.topLeft, closeTo(0.2, 1e-9));
      },
    );
  });

  group('the bevel rule', () {
    test('is a fraction of the thickness, not a figure of its own', () {
      // A 1dp divider and an 8dp app bar want visibly different rims, and one
      // number that suits both does not exist.
      const thickness = Thickness3d.baseline;
      expect(shape.bevelFraction, 0.25);
      expect(shape.bevelFor(thickness.thin), 0.25);
      expect(shape.bevelFor(thickness.standard), 0.5);
      expect(shape.bevelFor(thickness.raised), 1.0);
      expect(shape.bevelFor(thickness.structural), 2.0);
    });

    test('never exceeds half the slab, so the painter never has to clamp', () {
      // The painter does clamp a bevel to depth / 2, but a scale that relied
      // on the clamp would be stating a rim it does not get.
      const thickness = Thickness3d.baseline;
      for (final t in <double>[
        thickness.thin,
        thickness.standard,
        thickness.raised,
        thickness.structural,
      ]) {
        expect(shape.bevelFor(t), lessThanOrEqualTo(t / 2.0));
      }
    });

    test('is zero for a flat component', () {
      expect(shape.bevelFor(0.0), 0.0);
    });

    test('follows a theme that changes the fraction', () {
      final soft = shape.copyWith(bevelFraction: 0.5);
      expect(soft.bevelFor(4.0), 2.0);
      expect(shape.bevelFor(4.0), 1.0);
    });
  });

  group('lerp', () {
    final square = shape.copyWith(
      medium: BorderRadius3d.zero,
      bevelFraction: 0.0,
    );

    test('is the ends at t = 0 and t = 1', () {
      expect(ShapeScale3d.lerp(shape, square, 0.0), shape);
      expect(ShapeScale3d.lerp(shape, square, 1.0), square);
    });

    test('is halfway in the middle', () {
      final middle = ShapeScale3d.lerp(shape, square, 0.5);
      expect(middle.medium.topLeft, closeTo(6.0, 1e-9));
      expect(middle.bevelFraction, closeTo(0.125, 1e-9));
      expect(middle.large, shape.large);
    });

    test('holds an overshooting radius and bevel at zero', () {
      // BorderRadius3d asserts on a negative radius, and an overshooting
      // curve evaluates its tween outside [0, 1] by construction — so
      // without the clamp, animating a rounded scale to a square one crashes
      // on some curves and not others.
      final under = ShapeScale3d.lerp(shape, square, 1.5);
      expect(under.bevelFraction, 0.0);
      expect(under.medium, BorderRadius3d.zero);
      // And it is still the interpolation everywhere it is legal.
      expect(under.large.topLeft, shape.large.topLeft);
    });
  });

  group('value semantics', () {
    test('two identical scales are equal and hash alike', () {
      expect(shape.copyWith(), shape);
      expect(shape.copyWith().hashCode, shape.hashCode);
    });

    test('each field reaches equality', () {
      final changed = <ShapeScale3d>[
        shape.copyWith(none: const BorderRadius3d.circular(1.0)),
        shape.copyWith(extraSmall: const BorderRadius3d.circular(1.0)),
        shape.copyWith(small: const BorderRadius3d.circular(1.0)),
        shape.copyWith(medium: const BorderRadius3d.circular(1.0)),
        shape.copyWith(large: const BorderRadius3d.circular(1.0)),
        shape.copyWith(extraLarge: const BorderRadius3d.circular(1.0)),
        shape.copyWith(full: const BorderRadius3d.circular(1.0)),
        shape.copyWith(bevelFraction: 0.9),
      ];
      for (final one in changed) {
        expect(one, isNot(shape));
        expect(one.hashCode, isNot(shape.hashCode));
      }
    });
  });
}
