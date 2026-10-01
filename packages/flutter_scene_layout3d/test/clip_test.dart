// ClipPlane3d, Clip3dRegion and ClipBox3d: the clip contract the rest of the
// package consumes.

import 'dart:ui' show Color;

import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Matrix4;

import 'support.dart';

void main() {
  group('ClipPlane3d', () {
    test('keeps the side its normal points at', () {
      const plane = ClipPlane3d(Offset3d(1, 0, 0), 0);
      expect(plane.signedDistance(const Offset3d(2, 0, 0)), 2.0);
      expect(plane.signedDistance(const Offset3d(-2, 0, 0)), -2.0);
    });

    test('through() puts the boundary at the point', () {
      final plane = ClipPlane3d.through(
        const Offset3d(0, 3, 0),
        const Offset3d(0, -1, 0),
      );
      expect(plane.signedDistance(const Offset3d(0, 3, 0)), 0.0);
      expect(plane.signedDistance(const Offset3d(0, 1, 0)), 2.0);
    });

    test('shifting moves the boundary with the delta', () {
      const plane = ClipPlane3d(Offset3d(1, 0, 0), 0);
      final moved = plane.shifted(const Offset3d(5, 0, 0));
      expect(moved.signedDistance(const Offset3d(5, 0, 0)), 0.0);
      expect(moved.signedDistance(Offset3d.zero), -5.0);
    });

    test('a plane pulls back through a transform, not forward', () {
      const plane = ClipPlane3d(Offset3d(1, 0, 0), 0);
      // A frame scaled by two: the child's x = -1 is the parent's x = -2.
      final child = plane.transformed(Matrix4.diagonal3Values(2, 2, 2));
      expect(child.signedDistance(const Offset3d(-1, 0, 0)), lessThan(0.0));
      expect(child.signedDistance(const Offset3d(1, 0, 0)), greaterThan(0.0));
      // Renormalized, so the number is still a distance in the child's frame.
      expect(child.normal.distance, closeTo(1.0, 1e-9));
    });
  });

  group('Clip3dRegion', () {
    test('a rect clips the face and leaves the thickness alone', () {
      final region = Clip3dRegion.rect(const Size3d(4, 2, 1));
      expect(region.planes, hasLength(4));
      expect(region.contains(const Offset3d(2, 1, 100)), isTrue);
      expect(region.contains(const Offset3d(5, 1, 0)), isFalse);
    });

    test('a box clips the thickness too', () {
      final region = Clip3dRegion.box(const Size3d(4, 2, 1));
      expect(region.planes, hasLength(Clip3dRegion.maxPlanes));
      expect(region.contains(const Offset3d(2, 1, 100)), isFalse);
      expect(region.contains(const Offset3d(2, 1, 0.5)), isTrue);
    });

    test('containsBox and excludes are the two ends of the question', () {
      final region = Clip3dRegion.rect(const Size3d(10, 10, 0));
      expect(
        region.containsBox(const Offset3d(1, 1, 0), const Size3d(2, 2, 0)),
        isTrue,
      );
      expect(
        region.excludes(const Offset3d(1, 1, 0), const Size3d(2, 2, 0)),
        isFalse,
      );
      // Straddling: neither wholly in nor wholly out.
      expect(
        region.containsBox(const Offset3d(9, 1, 0), const Size3d(4, 2, 0)),
        isFalse,
      );
      expect(
        region.excludes(const Offset3d(9, 1, 0), const Size3d(4, 2, 0)),
        isFalse,
      );
      expect(
        region.excludes(const Offset3d(20, 1, 0), const Size3d(2, 2, 0)),
        isTrue,
      );
    });

    test('nesting axis-aligned clips folds to one box, not two', () {
      // The property the whole plane budget rests on: however deep clips are
      // stacked, an axis-aligned one stays six planes.
      final outer = Clip3dRegion.box(const Size3d(10, 10, 10));
      final inner = Clip3dRegion.box(const Size3d(4, 4, 4));
      final merged = outer.intersect(inner);
      expect(merged.planes, hasLength(Clip3dRegion.maxPlanes));
      expect(merged.contains(const Offset3d(3, 3, 3)), isTrue);
      expect(merged.contains(const Offset3d(6, 3, 3)), isFalse);
    });

    test('intersecting with nothing changes nothing', () {
      final region = Clip3dRegion.rect(const Size3d(2, 2, 0));
      expect(region.intersect(Clip3dRegion.none), same(region));
      expect(Clip3dRegion.none.intersect(region), same(region));
    });

    test('the plane block is padded out with planes that keep everything', () {
      final block = Clip3dRegion.rect(const Size3d(2, 2, 0)).toPlaneBlock();
      expect(block, hasLength(Clip3dRegion.maxPlanes * 4));
      // The two unused slots at the end are the disabled pattern.
      expect(block.sublist(16), <double>[0, 0, 0, 1, 0, 0, 0, 1]);
    });

    test(
      'a region too big for the block says so rather than clipping less',
      () {
        final tilted = Clip3dRegion.box(
          const Size3d(1, 1, 1),
        ).transformed(Matrix4.rotationZ(0.4));
        final region = Clip3dRegion.box(
          const Size3d(1, 1, 1),
        ).intersect(tilted);
        expect(region.planes.length, greaterThan(Clip3dRegion.maxPlanes));
        expect(region.toPlaneBlock, throwsStateError);
      },
    );
  });

  group('the clip a box inherits', () {
    test('is nothing without a ClipBox3d above it', () {
      final child = TestBox(const Size3d(1, 1, 0));
      laidOut(Padding3d(padding: const EdgeInsets3d.all(1), child: child));
      expect(child.clipRegion.isUnbounded, isTrue);
    });

    test('arrives in the child\'s own frame', () {
      final child = TestBox(const Size3d(1, 1, 0));
      laidOut(
        ClipBox3d(
          child: Padding3d(padding: const EdgeInsets3d.all(1), child: child),
        ),
        constraints: Constraints3d.tight(const Size3d(4, 4, 0)),
      );
      // The clip box is 4 wide; the child sits one unit in, so in the child's
      // frame the right edge is at 3.
      final region = child.clipRegion;
      expect(region.contains(const Offset3d(2.5, 0, 0)), isTrue);
      expect(region.contains(const Offset3d(3.5, 0, 0)), isFalse);
      expect(region.contains(const Offset3d(-1.5, 0, 0)), isFalse);
    });

    test('is pulled back through a transform on the way down', () {
      final child = TestBox(const Size3d(1, 1, 0));
      laidOut(
        ClipBox3d(
          child: Transform3d(
            transform: Matrix4.diagonal3Values(2, 2, 1),
            alignment: Alignment3d.topLeft,
            child: child,
          ),
        ),
        constraints: Constraints3d.tight(const Size3d(4, 4, 0)),
      );
      // The child's frame is scaled by two, so the clip's four units of room
      // are two units of the child's.
      final region = child.clipRegion;
      expect(region.contains(const Offset3d(1.5, 0, 0)), isTrue);
      expect(region.contains(const Offset3d(2.5, 0, 0)), isFalse);
    });

    test('reaches the painter of a decorated box inside it', () {
      final box = DecoratedBox3d(
        decoration: const BoxDecoration3d(),
        child: TestBox(const Size3d(8, 8, 0)),
      );
      laidOut(
        ClipBox3d(child: box),
        constraints: Constraints3d.tight(const Size3d(4, 4, 0)),
      );
      expect(box.clipRegion.planes, hasLength(4));
    });
  });

  group('a label wholly outside its clip', () {
    // A panel is cut at a clip plane by its shader; a glyph reads no planes.
    // So a page half across a page view used to carry every label on it a
    // page's width outside the window, drawn, while the panels around them
    // were cut away — which is what a tab bar's pages showed on every turn.

    const style = TextStyle(fontSize: 20);

    /// Two pages two units wide in a window two units wide, each with a label
    /// at either end. The window is a [ClipBox3d], because a scroll view here
    /// does not clip on its own: a `Scaffold3d`'s body is one, and a
    /// `TabBarView3d` puts one around its pages as Flutter's clips its own.
    ({PageView3d view, List<Text3d> labels, Layout3dSurface surface}) pages() {
      final labels = <Text3d>[
        Text3d('L0', style: style, name: 'L0'),
        Text3d('R0', style: style, name: 'R0'),
        Text3d('L1', style: style, name: 'L1'),
        Text3d('R1', style: style, name: 'R1'),
      ];
      final view = PageView3d(
        children: <Layout3d>[
          Row3d(
            mainAxisAlignment: MainAxisAlignment3d.spaceBetween,
            children: <Layout3d>[labels[0], labels[1]],
          ),
          Row3d(
            mainAxisAlignment: MainAxisAlignment3d.spaceBetween,
            children: <Layout3d>[labels[2], labels[3]],
          ),
        ],
      );
      final surface = laidOut(
        SizedBox3d(
          width: 2,
          height: 1,
          depth: 0,
          child: ClipBox3d(child: view),
        ),
        origin: Alignment3d.topLeft,
      );
      return (view: view, labels: labels, surface: surface);
    }

    test('at rest, the page in the window shows its labels', () {
      final p = pages();
      expect(p.labels[0].node.visible, isTrue);
      expect(p.labels[1].node.visible, isTrue);
    });

    test('half a page across, the labels wholly outside draw nothing', () {
      final p = pages();
      p.view.controller.jumpTo(1.0);
      p.surface.flush();
      // The first page runs from -1 to 1: its left label is gone, its right
      // one is in. The second runs from 1 to 3, the other way round.
      expect(p.labels[0].node.visible, isFalse, reason: 'L0');
      expect(p.labels[1].node.visible, isTrue, reason: 'R0');
      expect(p.labels[2].node.visible, isTrue, reason: 'L1');
      expect(p.labels[3].node.visible, isFalse, reason: 'R1');
      // And the pages themselves are both still drawn: the label is culled,
      // not the box it belongs to.
      expect(p.labels[0].parent!.node.visible, isTrue);
    });

    test('and they come back when the page does', () {
      final p = pages();
      p.view.controller.jumpTo(1.0);
      p.surface.flush();
      p.view.controller.jumpTo(0.0);
      p.surface.flush();
      expect(p.labels[0].node.visible, isTrue);
      expect(p.labels[1].node.visible, isTrue);
    });

    test('a label half in is drawn whole, as before', () {
      final p = pages();
      final width = p.labels[1].size.width;
      // The right label of the first page straddles the window's left edge.
      p.view.controller.jumpTo(2.0 - width / 2);
      p.surface.flush();
      expect(p.labels[1].node.visible, isTrue);
    });

    test('nothing is laid out to do it', () {
      final p = pages();
      final before = p.labels.map((label) => label.size).toList();
      p.view.controller.jumpTo(1.0);
      expect(p.labels.every((label) => !label.needsLayout), isTrue);
      p.surface.flush();
      expect(p.labels.map((label) => label.size).toList(), before);
    });

    test('a label stretched across its page is tested by its ink', () {
      // A column that stretches makes a label as wide as the page, and its
      // letters sit at the start of that width: the box is half in while
      // every letter is out. That is what the gallery's "Volume" did.
      final label = Text3d('Volume', style: style, name: 'Volume');
      final view = PageView3d(
        children: <Layout3d>[
          Column3d(
            crossAxisAlignment: CrossAxisAlignment3d.stretch,
            children: <Layout3d>[label],
          ),
          Column3d(children: <Layout3d>[Text3d('x', style: style)]),
        ],
      );
      final surface = laidOut(
        SizedBox3d(
          width: 2,
          height: 1,
          depth: 0,
          child: ClipBox3d(child: view),
        ),
        origin: Alignment3d.topLeft,
      );
      expect(label.size.width, closeTo(2.0, 1e-9));
      view.controller.jumpTo(1.5);
      surface.flush();
      // The box runs from -1.5 to 0.5, so half of it is in; the six letters
      // end well before -1.
      expect(label.node.visible, isFalse);
    });

    test('a label hidden by someone else is not shown by its clip', () {
      final p = pages();
      p.labels[1].node.visible = false;
      p.view.controller.jumpTo(1.0);
      p.surface.flush();
      p.view.controller.jumpTo(0.0);
      p.surface.flush();
      expect(p.labels[1].node.visible, isFalse);
    });
  });

  group('ClipBox3d', () {
    /// Three stacked unit-tall boxes inside a two-unit window: the first two
    /// fit, the third does not.
    ({ClipBox3d clip, List<TestBox> items, Layout3dSurface surface}) window() {
      final items = <TestBox>[
        TestBox(const Size3d(2, 1, 0), pointable: true, name: 'a'),
        TestBox(const Size3d(2, 1, 0), pointable: true, name: 'b'),
        TestBox(const Size3d(2, 1, 0), pointable: true, name: 'c'),
      ];
      final clip = ClipBox3d(child: Column3d(children: items));
      final surface = laidOut(
        SizedBox3d(width: 2, height: 2, depth: 0, child: clip),
        origin: Alignment3d.topLeft,
      );
      return (clip: clip, items: items, surface: surface);
    }

    test('lays its child out exactly as a pass-through would', () {
      final w = window();
      expect(w.clip.size, const Size3d(2, 2, 0));
      expect(w.items[2].offset.y, 2.0);
      expect(w.items[2].size, const Size3d(2, 1, 0));
    });

    test('hides what falls entirely outside and keeps what does not', () {
      final w = window();
      expect(w.items[0].node.visible, isTrue);
      expect(w.items[1].node.visible, isTrue);
      expect(w.items[2].node.visible, isFalse);
    });

    test('what it hid is out of reach of a ray', () {
      final w = window();
      expect(
        w.surface.hitTestAt(const Offset3d(1, 0.5, 0)).firstOf<TestBox>(),
        same(w.items[0]),
      );
      expect(
        w.surface.hitTestAt(const Offset3d(1, 2.5, 0)).firstOf<TestBox>(),
        isNull,
      );
    });

    test(
      'a box that is half in is left visible, because a node is all or nothing',
      () {
        final items = <TestBox>[
          TestBox(const Size3d(2, 1.5, 0)),
          TestBox(const Size3d(2, 1.5, 0)),
        ];
        laidOut(
          SizedBox3d(
            width: 2,
            height: 2,
            depth: 0,
            child: ClipBox3d(child: Column3d(children: items)),
          ),
        );
        // The second sits at y = 1.5 and runs to 3, so half of it is outside;
        // culling whole nodes cannot express that and must not hide it. This is
        // exactly the case clip planes exist for.
        expect(items[1].node.visible, isTrue);
      },
    );

    test('restores what it hid when the window grows', () {
      final items = <TestBox>[
        TestBox(const Size3d(2, 1, 0)),
        TestBox(const Size3d(2, 1, 0)),
        TestBox(const Size3d(2, 1, 0)),
      ];
      final sized = SizedBox3d(
        width: 2,
        height: 2,
        depth: 0,
        child: ClipBox3d(child: Column3d(children: items)),
      );
      final surface = laidOut(sized);
      expect(items[2].node.visible, isFalse);

      sized.height = 4;
      surface.flush();
      expect(items[2].node.visible, isTrue);
    });

    test('culling can be turned off without giving up the planes', () {
      final items = <TestBox>[
        TestBox(const Size3d(2, 1, 0)),
        TestBox(const Size3d(2, 1, 0)),
        TestBox(const Size3d(2, 1, 0)),
      ];
      final clip = ClipBox3d(
        cullNodes: false,
        child: Column3d(children: items),
      );
      laidOut(SizedBox3d(width: 2, height: 2, depth: 0, child: clip));
      expect(items[2].node.visible, isTrue);
      expect(items[2].clipRegion.planes, hasLength(4));
    });

    test('depth is left alone unless it is asked for', () {
      final child = TestBox(const Size3d(2, 2, 0));
      final clip = ClipBox3d(child: child);
      laidOut(clip, constraints: Constraints3d.tight(const Size3d(2, 2, 0)));
      expect(child.clipRegion.contains(const Offset3d(1, 1, -5)), isTrue);

      clip.clipDepth = true;
      clip.owner!.flushLayout();
      expect(child.clipRegion.contains(const Offset3d(1, 1, -5)), isFalse);
    });
  });

  group('the clip actually reaches a painter', () {
    // The plane tier of the contract is a shader block, and the block is
    // written when a decorated box paints. A box paints from inside its own
    // `performLayout` — where an enclosing `ClipBox3d` has not been given a
    // size yet, because a proxy takes its size *from its child*. So the
    // first block every panel under a clip ever got was the unbounded one,
    // and nothing afterwards replaced it: a row half inside a window drew
    // straight through the edge, and the whole tier was dead in a way no
    // arithmetic test could see. `Layout3d.refreshClipRegion` is what closes
    // that, and these are the two paths it has to cover.

    setUp(ClipRecorder.reset);
    tearDown(() {
      ClipRecorder.reset();
      BoxDecoration3d.painterFactory = null;
    });

    test(
      'a panel under a clip is told the clip on the layout that made it',
      () {
        BoxDecoration3d.painterFactory = (_) => ClipRecorder();
        final panel = DecoratedBox3d(
          decoration: const BoxDecoration3d(color: Color(0xFFFFFFFF)),
        );
        laidOut(
          ClipBox3d(child: SizedBox3d(width: 4, height: 1, child: panel)),
          constraints: Constraints3d.tight(const Size3d(2, 1, 0)),
        );

        expect(
          ClipRecorder.seen.last.planes,
          hasLength(4),
          reason:
              'the last block the painter was given is the real clip, not '
              'the unbounded one the box was born with',
        );
      },
    );

    test('and again whenever it is moved without being laid out again', () {
      // Scrolling. The rows are not relaid out — their constraints do not
      // change — they are *placed* somewhere else, so nothing but the
      // placement can notice that they are under a different part of the
      // window now.
      BoxDecoration3d.painterFactory = (_) => ClipRecorder();
      final panel = DecoratedBox3d(
        decoration: const BoxDecoration3d(color: Color(0xFFFFFFFF)),
      );
      final controller = Scroll3dController();
      final surface = laidOut(
        ClipBox3d(
          child: ListView3d(
            controller: controller,
            children: <Layout3d>[
              for (var i = 0; i < 6; i++)
                SizedBox3d(
                  width: 2,
                  height: 0.5,
                  child: i == 0 ? panel : TestBox(const Size3d(2, 0.5, 0)),
                ),
            ],
          ),
        ),
        constraints: Constraints3d.tight(const Size3d(2, 1, 0)),
      );
      final before = ClipRecorder.seen.last;
      expect(before.planes, hasLength(4));

      controller.jumpTo(0.25);
      surface.flush();

      final after = ClipRecorder.seen.last;
      expect(after.planes, hasLength(4));
      expect(
        after.planes.map((p) => p.distance).toList(),
        isNot(before.planes.map((p) => p.distance).toList()),
        reason:
            'the row slid a quarter of a unit under the window\'s edge '
            'and the block it draws with says so',
      );
    });

    test('and a tree with no clip in it pays nothing for the check', () {
      // The gate: `place` walks the subtree only when something above
      // actually clips, which is one walk up the parent chain that returns
      // immediately when nothing does.
      BoxDecoration3d.painterFactory = (_) => ClipRecorder();
      final panel = DecoratedBox3d(
        decoration: const BoxDecoration3d(color: Color(0xFFFFFFFF)),
      );
      laidOut(
        SizedBox3d(width: 2, height: 1, child: panel),
        constraints: Constraints3d.tight(const Size3d(2, 1, 0)),
      );
      expect(ClipRecorder.seen, hasLength(1));
      expect(ClipRecorder.seen.single.isUnbounded, isTrue);
    });
  });
}

/// A painter that records the clip every paint request carried.
///
/// The only way to see the plane tier from a headless test: the block itself
/// is a shader uniform, and there is no shader here.
class ClipRecorder extends Decoration3dPainter {
  static final List<Clip3dRegion> seen = <Clip3dRegion>[];

  static void reset() => seen.clear();

  @override
  void paint(Decoration3dPaintRequest request) => seen.add(request.clip);

  @override
  void release(Node node) {}

  @override
  void dispose() {}
}
