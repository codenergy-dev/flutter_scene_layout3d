// DecoratedBox3d, BoxDecoration3d and its uniforms, the painter cache,
// Visibility3d and Offstage3d.

import 'dart:ui' show Color;

import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A painter that records what it was asked to do and builds nothing.
///
/// Stands in for the real one, which needs a GPU context: everything the box
/// promises about *when* a painter is created, shared and told about a size
/// is checkable without ever compiling a shader.
class RecordingPainter extends Decoration3dPainter {
  RecordingPainter(this.shape) {
    created.add(this);
  }

  /// Every painter made since the last [reset], oldest first.
  static final List<RecordingPainter> created = <RecordingPainter>[];

  static void reset() => created.clear();

  final String shape;
  final List<Decoration3dPaintRequest> paints = <Decoration3dPaintRequest>[];
  final List<Node> released = <Node>[];
  bool disposed = false;

  Decoration3dPaintRequest get last => paints.last;

  @override
  void paint(Decoration3dPaintRequest request) => paints.add(request);

  @override
  void release(Node node) => released.add(node);

  @override
  void dispose() => disposed = true;
}

/// A decoration whose shape — and so whose painter — is whatever it is told.
class TestDecoration3d extends Decoration3d {
  const TestDecoration3d(this.shape, {this.rebuild = false, this.tag = 0});

  final String shape;
  final bool rebuild;

  /// A dial that changes the value without changing the shape, standing in
  /// for the colour a real decoration would vary.
  final int tag;

  @override
  Object get cacheKey => shape;

  @override
  bool shouldRebuild(TestDecoration3d old) => rebuild;

  @override
  Decoration3dPainter? createPainter() => RecordingPainter(shape);

  @override
  bool operator ==(Object other) =>
      other is TestDecoration3d &&
      other.shape == shape &&
      other.rebuild == rebuild &&
      other.tag == tag;

  @override
  int get hashCode => Object.hash(shape, rebuild, tag);
}

void main() {
  setUp(RecordingPainter.reset);
  tearDown(() {
    RecordingPainter.reset();
    BoxDecoration3d.painterFactory = null;
  });

  group('DecoratedBox3d', () {
    test('sizes itself to its child and passes the constraints through', () {
      final child = TestBox(const Size3d(2, 3, 0.5));
      final box = DecoratedBox3d(
        decoration: const TestDecoration3d('panel'),
        child: child,
      );
      laidOut(box);
      expect(box.size, const Size3d(2, 3, 0.5));
      expect(child.offset, Offset3d.zero);
    });

    test('is the smallest it may be with no child', () {
      final box = DecoratedBox3d(decoration: const TestDecoration3d('panel'));
      laidOut(box, constraints: const Constraints3d(minWidth: 1, maxWidth: 4));
      expect(box.size, const Size3d(1, 0, 0));
    });

    test('two sizes are one painter and two paints', () {
      // The whole bet, stated as a test: a box that changes size does not get
      // new geometry, it gets the same painter told a different number.
      final child = TestBox(const Size3d(2, 2, 0));
      final box = DecoratedBox3d(
        decoration: const TestDecoration3d('panel'),
        child: child,
      );
      final surface = laidOut(box);
      child.preferred = const Size3d(5, 1, 0);
      surface.flush();

      expect(RecordingPainter.created, hasLength(1));
      final painter = RecordingPainter.created.single;
      expect(painter.paints.map((p) => p.size), <Size3d>[
        const Size3d(2, 2, 0),
        const Size3d(5, 1, 0),
      ]);
    });

    test('equal decorations share a painter, unequal ones do not', () {
      final a = DecoratedBox3d(decoration: const TestDecoration3d('panel'));
      final b = DecoratedBox3d(decoration: const TestDecoration3d('panel'));
      final c = DecoratedBox3d(decoration: const TestDecoration3d('pill'));
      laidOut(Column3d(children: <Layout3d>[a, b, c]));

      expect(RecordingPainter.created, hasLength(2));
      expect(a.painter, same(b.painter));
      expect(a.painter, isNot(same(c.painter)));
    });

    test('the cache disposes a painter when the last box lets go', () {
      final a = DecoratedBox3d(decoration: const TestDecoration3d('panel'));
      final b = DecoratedBox3d(decoration: const TestDecoration3d('panel'));
      laidOut(Column3d(children: <Layout3d>[a, b]));
      final painter = RecordingPainter.created.single;

      a.decoration = const TestDecoration3d('pill');
      expect(painter.released, <Node>[a.node]);
      expect(painter.disposed, isFalse);

      b.decoration = const TestDecoration3d('pill');
      expect(painter.disposed, isTrue);
    });

    test(
      'a decoration change keeps the painter when the shape is the same',
      () {
        final box = DecoratedBox3d(decoration: const TestDecoration3d('panel'));
        laidOut(box);
        final painter = RecordingPainter.created.single;
        final paintsBefore = painter.paints.length;

        box.decoration = const TestDecoration3d('panel', tag: 1);
        expect(RecordingPainter.created, hasLength(1));
        expect(painter.paints.length, paintsBefore + 1);

        box.decoration = const TestDecoration3d('panel', tag: 2, rebuild: true);
        expect(RecordingPainter.created, hasLength(2));
      },
    );

    test('a decoration change does not relayout', () {
      final child = TestBox(const Size3d(1, 1, 0));
      final box = DecoratedBox3d(
        decoration: const TestDecoration3d('panel'),
        child: child,
      );
      final surface = laidOut(box);
      final layouts = child.layoutCount;

      box.decoration = const TestDecoration3d('panel', tag: 1, rebuild: true);
      expect(surface.needsFlush, isFalse);
      expect(child.layoutCount, layouts);
    });

    test(
      'a state-layer change repaints, asks for a frame, and dirties nothing',
      () {
        var frames = 0;
        final child = TestBox(const Size3d(1, 1, 0));
        final box = DecoratedBox3d(
          decoration: const TestDecoration3d('panel'),
          child: child,
        );
        final surface = Layout3dSurface(child: box)
          ..onNeedVisualUpdate = () => frames++;
        surface.flush();
        final painter = RecordingPainter.created.single;
        final paints = painter.paints.length;
        final layouts = child.layoutCount;

        box.stateLayer = const StateLayer3d(
          color: Color(0xFFFFFFFF),
          opacity: 0.08,
        );

        expect(frames, 1);
        expect(painter.paints.length, paints + 1);
        expect(painter.last.stateLayer.opacity, 0.08);
        expect(surface.needsFlush, isFalse);
        expect(child.layoutCount, layouts);
      },
    );

    test('the painter is told the metrics and the clip', () {
      final box = DecoratedBox3d(decoration: const TestDecoration3d('panel'));
      laidOut(box, metrics: const Layout3dMetrics(unitsPerLogicalPixel: 0.02));
      final request = RecordingPainter.created.single.last;
      expect(request.metrics.unitsPerLogicalPixel, 0.02);
      expect(request.clip.isUnbounded, isTrue);
      expect(request.node, same(box.node));
    });
  });

  group('elevation', () {
    test('lifts the geometry toward the viewer by dp', () {
      final box = DecoratedBox3d(
        decoration: const BoxDecoration3d(elevation: 6),
        child: TestBox(const Size3d(1, 1, 0)),
      );
      laidOut(box, metrics: const Layout3dMetrics(unitsPerLogicalPixel: 0.01));
      expect(box.elevationUnits, closeTo(0.06, 1e-9));
      // z runs away from the viewer, so standing off is a step back toward it.
      // The node's transform is single-precision, hence the loose bound.
      expect(translationOf(box).z, closeTo(-0.06, 1e-6));
    });

    test('scales with the unit contract, like every other dp figure', () {
      final box = DecoratedBox3d(
        decoration: const BoxDecoration3d(elevation: 6),
        child: TestBox(const Size3d(1, 1, 0)),
      );
      final surface = laidOut(box);
      surface.metrics = const Layout3dMetrics(unitsPerLogicalPixel: 0.05);
      surface.flush();
      expect(box.elevationUnits, closeTo(0.3, 1e-9));
    });

    test('moves neither the layout box nor what a ray reaches', () {
      final flat = DecoratedBox3d(
        decoration: const BoxDecoration3d(),
        child: TestBox(const Size3d(2, 2, 0.2)),
      );
      final raised = DecoratedBox3d(
        decoration: const BoxDecoration3d(elevation: 12),
        child: TestBox(const Size3d(2, 2, 0.2)),
      );
      final flatSurface = laidOut(flat, origin: Alignment3d.topLeft);
      final raisedSurface = laidOut(raised, origin: Alignment3d.topLeft);

      expect(raised.size, flat.size);
      expect(raised.offset, flat.offset);
      expect(
        raisedSurface
            .hitTestAt(const Offset3d(1, 1, 0))
            .firstOf<DecoratedBox3d>(),
        same(raised),
      );
      expect(
        flatSurface
            .hitTestAt(const Offset3d(1, 1, 0))
            .firstOf<DecoratedBox3d>(),
        same(flat),
      );
    });

    test('a decoration with no elevation carries no transform', () {
      final box = DecoratedBox3d(decoration: const TestDecoration3d('panel'));
      laidOut(box);
      expect(box.elevationUnits, 0.0);
      expect(box.localTransform, isNull);
    });
  });

  group('BoxDecoration3d', () {
    test('every panel shares one painter, whatever its numbers', () {
      BoxDecoration3d.painterFactory = (_) => RecordingPainter('box');
      final a = DecoratedBox3d(
        decoration: const BoxDecoration3d(color: Color(0xFFFF0000)),
      );
      final b = DecoratedBox3d(
        decoration: const BoxDecoration3d(
          color: Color(0xFF00FF00),
          borderRadius: BorderRadius3d.circular(12),
          elevation: 3,
        ),
      );
      laidOut(Column3d(children: <Layout3d>[a, b]));
      expect(RecordingPainter.created, hasLength(1));
      expect(a.painter, same(b.painter));
    });

    test('nothing about a panel ever needs a rebuild', () {
      const a = BoxDecoration3d(color: Color(0xFFFF0000));
      const b = BoxDecoration3d(
        color: Color(0xFF00FF00),
        border: Border3d(width: 2),
      );
      expect(b.shouldRebuild(a), isFalse);
      expect(a.cacheKey, b.cacheKey);
    });

    test('no factory means no painter and no drawing', () {
      final box = DecoratedBox3d(decoration: const BoxDecoration3d());
      laidOut(box, constraints: Constraints3d.tight(const Size3d(1, 1, 0)));
      expect(box.painter, isNull);
      expect(box.size, const Size3d(1, 1, 0));
    });

    test('lerp interpolates every dial', () {
      const a = BoxDecoration3d(color: Color(0xFF000000), elevation: 0);
      const b = BoxDecoration3d(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius3d.circular(10),
        border: Border3d(width: 4),
        elevation: 8,
      );
      final mid = BoxDecoration3d.lerp(a, b, 0.5);
      expect(mid.elevation, 4.0);
      expect(mid.borderRadius.topLeft, 5.0);
      expect(mid.border.width, 2.0);
    });

    test("Material's surface-tint table, at the levels and between them", () {
      expect(BoxDecoration3d.surfaceTintOpacityFor(0), 0.0);
      expect(BoxDecoration3d.surfaceTintOpacityFor(1), closeTo(0.05, 1e-9));
      expect(BoxDecoration3d.surfaceTintOpacityFor(2), closeTo(0.065, 1e-9));
      expect(BoxDecoration3d.surfaceTintOpacityFor(12), closeTo(0.14, 1e-9));
      expect(BoxDecoration3d.surfaceTintOpacityFor(40), closeTo(0.14, 1e-9));
    });
  });

  group('BorderRadius3d', () {
    test('holds the radii down to what the box can fit', () {
      const radius = BorderRadius3d.circular(10);
      final resolved = radius.resolve(const Size3d(10, 40, 0));
      // Two 10s share a 10-wide edge, so everything halves.
      expect(resolved.topLeft, 5.0);
      expect(resolved.bottomRight, 5.0);
    });

    test('scales every corner by the same factor', () {
      const radius = BorderRadius3d(topLeft: 8, topRight: 2);
      final resolved = radius.resolve(const Size3d(5, 100, 0));
      expect(resolved.topLeft, 4.0);
      expect(resolved.topRight, 1.0);
    });

    test('a box that can fit them is left alone', () {
      const radius = BorderRadius3d.circular(4);
      expect(radius.resolve(const Size3d(100, 100, 0)), radius);
    });

    test('a box with nothing to it takes them all away', () {
      const radius = BorderRadius3d.circular(4);
      expect(radius.resolve(Size3d.zero).isZero, isTrue);
    });
  });

  group('BoxDecoration3dUniforms', () {
    const metrics = Layout3dMetrics(unitsPerLogicalPixel: 0.01);

    test('turns logical pixels into world units', () {
      final uniforms = BoxDecoration3dUniforms.resolve(
        decoration: const BoxDecoration3d(
          borderRadius: BorderRadius3d.circular(12),
          border: Border3d(width: 2),
          bevel: 1,
        ),
        size: const Size3d(4, 2, 0.5),
        metrics: metrics,
      );
      expect(uniforms.halfExtent, const Size3d(2, 1, 0.25));
      expect(uniforms.radius.topLeft, closeTo(0.12, 1e-9));
      expect(uniforms.borderWidth, closeTo(0.02, 1e-9));
      expect(uniforms.bevel, closeTo(0.01, 1e-9));
    });

    test('clamps the radii against the box it was resolved for', () {
      final uniforms = BoxDecoration3dUniforms.resolve(
        decoration: const BoxDecoration3d(
          borderRadius: BorderRadius3d.circular(100),
        ),
        size: const Size3d(1, 1, 0),
        metrics: metrics,
      );
      // 100dp is a whole unit, and two of them cannot share a one-unit edge.
      expect(uniforms.radius.topLeft, closeTo(0.5, 1e-9));
    });

    test('a border cannot cross itself', () {
      final uniforms = BoxDecoration3dUniforms.resolve(
        decoration: const BoxDecoration3d(border: Border3d(width: 100)),
        size: const Size3d(0.5, 4, 0),
        metrics: metrics,
      );
      expect(uniforms.borderWidth, closeTo(0.25, 1e-9));
    });

    test('folds the state layer opacity into its alpha', () {
      final uniforms = BoxDecoration3dUniforms.resolve(
        decoration: const BoxDecoration3d(),
        size: const Size3d(1, 1, 0),
        metrics: metrics,
        stateLayer: const StateLayer3d(color: Color(0xFFFFFFFF), opacity: 0.12),
      );
      expect(uniforms.stateLayerColor.a, closeTo(0.12, 1e-6));
    });

    test('derives the surface tint amount from the elevation', () {
      final uniforms = BoxDecoration3dUniforms.resolve(
        decoration: const BoxDecoration3d(
          elevation: 6,
          surfaceTint: Color(0xFF6750A4),
        ),
        size: const Size3d(1, 1, 0),
        metrics: metrics,
      );
      expect(uniforms.surfaceTintColor.a, closeTo(0.11, 1e-6));
    });

    test('no tint colour means no tint, however high the panel', () {
      final uniforms = BoxDecoration3dUniforms.resolve(
        decoration: const BoxDecoration3d(elevation: 24),
        size: const Size3d(1, 1, 0),
        metrics: metrics,
      );
      expect(uniforms.surfaceTintColor.a, 0.0);
    });

    test('packs the radii clockwise from the origin corner', () {
      final uniforms = BoxDecoration3dUniforms.resolve(
        decoration: const BoxDecoration3d(
          borderRadius: BorderRadius3d(
            topLeft: 1,
            topRight: 2,
            bottomLeft: 3,
            bottomRight: 4,
          ),
        ),
        size: const Size3d(100, 100, 0),
        metrics: metrics,
      );
      expect(uniforms.radiusVector.map((v) => (v * 100).round()), <int>[
        1,
        2,
        4,
        3,
      ]);
    });

    test('an unclipped box still packs a full plane block', () {
      final uniforms = BoxDecoration3dUniforms.resolve(
        decoration: const BoxDecoration3d(),
        size: const Size3d(1, 1, 0),
        metrics: metrics,
      );
      expect(uniforms.clipPlanes, hasLength(Clip3dRegion.maxPlanes * 4));
    });
  });

  group('StateLayer3d', () {
    test('none changes nothing', () {
      expect(StateLayer3d.none.isNone, isTrue);
      expect(StateLayer3d.none.resolvedColor.a, 0.0);
    });

    test('lerp takes the colour from whichever end is visible', () {
      const a = StateLayer3d(color: Color(0xFFFF0000), opacity: 0.0);
      const b = StateLayer3d(color: Color(0xFF00FF00), opacity: 0.12);
      expect(StateLayer3d.lerp(a, b, 0.25).color, a.color);
      expect(StateLayer3d.lerp(a, b, 0.75).color, b.color);
      expect(StateLayer3d.lerp(a, b, 0.5).opacity, closeTo(0.06, 1e-9));
    });
  });

  group('Visibility3d', () {
    test('keeps the space and hides the node', () {
      final child = TestBox(const Size3d(2, 2, 0), pointable: true);
      final box = Visibility3d(visible: false, child: child);
      laidOut(box);
      expect(box.size, const Size3d(2, 2, 0));
      expect(box.node.visible, isFalse);
    });

    test('an invisible child is out of reach of a ray', () {
      final child = TestBox(const Size3d(2, 2, 0), pointable: true);
      final box = Visibility3d(child: child);
      final surface = laidOut(box, origin: Alignment3d.topLeft);
      expect(surface.hitTestAt(const Offset3d(1, 1, 0)).isEmpty, isFalse);

      box.visible = false;
      expect(surface.hitTestAt(const Offset3d(1, 1, 0)).isEmpty, isTrue);
    });

    test('toggling it does not relayout', () {
      final child = TestBox(const Size3d(2, 2, 0));
      final box = Visibility3d(child: child);
      final surface = laidOut(box);
      final layouts = child.layoutCount;
      box.visible = false;
      expect(surface.needsFlush, isFalse);
      expect(child.layoutCount, layouts);
    });
  });

  group('Offstage3d', () {
    test('reports no size and hides the node', () {
      final child = TestBox(const Size3d(2, 2, 0), pointable: true);
      final box = Offstage3d(child: child);
      laidOut(box);
      expect(box.size, Size3d.zero);
      expect(box.node.visible, isFalse);
    });

    test('takes its space out of the row it is in', () {
      final visible = TestBox(const Size3d(1, 1, 0));
      final column = Column3d(
        children: <Layout3d>[
          Offstage3d(child: TestBox(const Size3d(1, 5, 0))),
          visible,
        ],
      );
      laidOut(column);
      expect(column.size.height, 1.0);
      expect(visible.offset.y, 0.0);
    });

    test('answers intrinsic queries with nothing', () {
      final box = Offstage3d(child: TestBox(const Size3d(3, 3, 0)));
      expect(
        box.getMaxIntrinsicExtent(Axis3d.horizontal, Size3d.infinite),
        0.0,
      );
      box.offstage = false;
      expect(
        box.getMaxIntrinsicExtent(Axis3d.horizontal, Size3d.infinite),
        3.0,
      );
    });

    test('an offstage child is out of reach of a ray', () {
      final child = TestBox(const Size3d(2, 2, 0), pointable: true);
      final box = Offstage3d(offstage: false, child: child);
      final surface = laidOut(box, origin: Alignment3d.topLeft);
      expect(surface.hitTestAt(const Offset3d(1, 1, 0)).isEmpty, isFalse);

      box.offstage = true;
      surface.flush();
      expect(surface.hitTestAt(const Offset3d(1, 1, 0)).isEmpty, isTrue);
    });

    test('going back onstage relayouts and restores the size', () {
      final child = TestBox(const Size3d(2, 2, 0));
      final box = Offstage3d(child: child);
      final surface = laidOut(box);
      box.offstage = false;
      expect(surface.needsFlush, isTrue);
      surface.flush();
      expect(box.size, const Size3d(2, 2, 0));
      expect(box.node.visible, isTrue);
    });
  });
}
