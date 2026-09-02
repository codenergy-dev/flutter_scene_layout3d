// Elevation3d and Thickness3d: the two depth scales.
//
// One is Material's, re-derived because here the height is real and the
// shadow is gone. The other is invented here, because Material has no token
// for how deep a component is, and the two rules that come with it — a
// thickness fights the depth ordering, and a thick slab wants a bevel — are
// what this file mostly pins.

import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show BoxDecoration3d;
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const elevation = Elevation3d.baseline;
  const thickness = Thickness3d.baseline;

  group('Elevation3d', () {
    test('is Material 3\'s six levels, in logical pixels', () {
      expect(elevation.level0, 0.0);
      expect(elevation.level1, 1.0);
      expect(elevation.level2, 3.0);
      expect(elevation.level3, 6.0);
      expect(elevation.level4, 8.0);
      expect(elevation.level5, 12.0);
      expect(elevation.levels, <double>[0.0, 1.0, 3.0, 6.0, 8.0, 12.0]);
    });

    test('the levels are the same ladder the tint table is keyed on', () {
      // Material specifies both halves of elevation against one ladder, and
      // the tint is the half that survives the move to a real depth: it is
      // what tells a level-3 surface from a level-1 one when the camera is
      // head-on and parallax gives nothing.
      expect(elevation.tintOpacityFor(elevation.level0), 0.0);
      expect(elevation.tintOpacityFor(elevation.level1), closeTo(0.05, 1e-9));
      expect(elevation.tintOpacityFor(elevation.level2), closeTo(0.08, 1e-9));
      expect(elevation.tintOpacityFor(elevation.level3), closeTo(0.11, 1e-9));
      expect(elevation.tintOpacityFor(elevation.level4), closeTo(0.12, 1e-9));
      expect(elevation.tintOpacityFor(elevation.level5), closeTo(0.14, 1e-9));
    });

    test('the tint table is the shader\'s, not a second transcription', () {
      // Delegating rather than copying is what keeps a component and the
      // panel it draws through agreeing by construction.
      for (final dp in <double>[0.0, 0.5, 2.0, 4.5, 7.0, 11.0, 20.0]) {
        expect(
          elevation.tintOpacityFor(dp),
          BoxDecoration3d.surfaceTintOpacityFor(dp),
        );
      }
    });

    test('lerp is the ends, the middle, and never negative', () {
      final flat = elevation.copyWith(level1: 0.0, level5: 0.0);
      expect(Elevation3d.lerp(elevation, flat, 0.0), elevation);
      expect(Elevation3d.lerp(elevation, flat, 1.0), flat);
      final middle = Elevation3d.lerp(elevation, flat, 0.5);
      expect(middle.level1, closeTo(0.5, 1e-9));
      expect(middle.level5, closeTo(6.0, 1e-9));
      expect(middle.level3, elevation.level3);
      // BoxDecoration3d asserts on a negative elevation, so an overshooting
      // curve must not be able to produce one.
      expect(Elevation3d.lerp(elevation, flat, 1.5).level5, 0.0);
    });

    test('value semantics', () {
      expect(elevation.copyWith(), elevation);
      expect(elevation.copyWith().hashCode, elevation.hashCode);
      for (final one in <Elevation3d>[
        elevation.copyWith(level0: 0.5),
        elevation.copyWith(level1: 0.5),
        elevation.copyWith(level2: 0.5),
        elevation.copyWith(level3: 0.5),
        elevation.copyWith(level4: 0.5),
        elevation.copyWith(level5: 0.5),
      ]) {
        expect(one, isNot(elevation));
        expect(one.hashCode, isNot(elevation.hashCode));
      }
    });
  });

  group('Thickness3d', () {
    test('is four steps, in logical pixels, on a stated depth step', () {
      expect(thickness.thin, 1.0);
      expect(thickness.standard, 2.0);
      expect(thickness.raised, 4.0);
      expect(thickness.structural, 8.0);
      expect(thickness.depthStep, 12.0);
    });

    test('the step separates every pair the scale can produce', () {
      // The rule: a slab is centred on its own plane and reaches half its
      // thickness forward, so two stacked children are separated only when
      // the step exceeds the mean of their thicknesses. This is the check a
      // component author would otherwise learn from a stack that looks
      // inverted, or from a drop landing on the wrong target.
      final steps = <double>[
        thickness.thin,
        thickness.standard,
        thickness.raised,
        thickness.structural,
      ];
      for (final back in steps) {
        for (final front in steps) {
          expect(
            thickness.separates(back, front),
            isTrue,
            reason: '$back behind $front',
          );
        }
      }
      // With half again to spare against the worst pair.
      expect(
        Thickness3d.minimumStepFor(thickness.structural, thickness.structural),
        8.0,
      );
    });

    test('minimumStepFor is the mean, and separates is strict', () {
      expect(Thickness3d.minimumStepFor(2.0, 6.0), 4.0);
      expect(Thickness3d.minimumStepFor(0.0, 0.0), 0.0);
      // Equal is coplanar at the touching faces, which is the z-fight the
      // step exists to prevent.
      expect(thickness.separates(2.0, 6.0, step: 4.0), isFalse);
      expect(thickness.separates(2.0, 6.0, step: 4.001), isTrue);
    });

    test('a thickened scale outgrows its own step, and says so', () {
      // The failure this is here to catch: a theme that makes components
      // deeper without raising the step it stacks them on.
      final chunky = thickness.copyWith(structural: 16.0, raised: 12.0);
      expect(chunky.separates(chunky.structural, chunky.raised), isFalse);
      expect(
        chunky
            .copyWith(depthStep: 20.0)
            .separates(chunky.structural, chunky.raised),
        isTrue,
      );
    });

    test('the scale is ordered and small', () {
      expect(thickness.thin, lessThan(thickness.standard));
      expect(thickness.standard, lessThan(thickness.raised));
      expect(thickness.raised, lessThan(thickness.structural));
      // A component is a card, not a brick: the deepest token is 8dp, well
      // under the 40dp a small control is tall.
      expect(thickness.structural, lessThan(40.0));
    });

    test('lerp is the ends, the middle, and never negative', () {
      final flat = thickness.copyWith(raised: 0.0, structural: 0.0);
      expect(Thickness3d.lerp(thickness, flat, 0.0), thickness);
      expect(Thickness3d.lerp(thickness, flat, 1.0), flat);
      final middle = Thickness3d.lerp(thickness, flat, 0.5);
      expect(middle.raised, closeTo(2.0, 1e-9));
      expect(middle.structural, closeTo(4.0, 1e-9));
      expect(middle.thin, thickness.thin);
      expect(Thickness3d.lerp(thickness, flat, 1.5).structural, 0.0);
    });

    test('value semantics', () {
      expect(thickness.copyWith(), thickness);
      expect(thickness.copyWith().hashCode, thickness.hashCode);
      for (final one in <Thickness3d>[
        thickness.copyWith(thin: 0.5),
        thickness.copyWith(standard: 0.5),
        thickness.copyWith(raised: 0.5),
        thickness.copyWith(structural: 0.5),
        thickness.copyWith(depthStep: 0.5),
      ]) {
        expect(one, isNot(thickness));
        expect(one.hashCode, isNot(thickness.hashCode));
      }
    });
  });
}
