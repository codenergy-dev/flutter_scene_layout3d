// Viewport3d and ListView3d: a window onto content longer than itself.

import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  final window = Constraints3d.tight(const Size3d(10, 4, 10));

  group('Viewport3d', () {
    test('measures the scrollable range and slides the child', () {
      final content = Column3d(
        mainAxisSize: MainAxisSize3d.min,
        children: List.generate(5, (_) => TestBox(const Size3d(2, 2, 2))),
      );
      final viewport = Viewport3d(child: content);
      final surface = laidOut(viewport, constraints: window);

      expect(content.size.height, 10);
      expect(viewport.size, const Size3d(10, 4, 10));
      expect(viewport.controller.maxScrollExtent, 6);
      expect(viewport.controller.viewportExtent, 4);
      expect(content.offset.y, 0);

      viewport.controller.jumpTo(3);
      surface.flush();
      expect(content.offset.y, -3);
    });

    test('clamps the offset to the content', () {
      final viewport = Viewport3d(child: TestBox(const Size3d(2, 6, 2)));
      final surface = laidOut(viewport, constraints: window);
      viewport.controller.jumpTo(100);
      surface.flush();
      expect(viewport.controller.offset, 2);
    });

    test('does not scroll when the content fits', () {
      final viewport = Viewport3d(child: TestBox(const Size3d(2, 2, 2)));
      laidOut(viewport, constraints: window);
      expect(viewport.controller.canScroll, isFalse);
      expect(viewport.controller.maxScrollExtent, 0);
    });
  });

  group('ListView3d with explicit children', () {
    test('itemCount follows the child list', () {
      final list = ListView3d(children: [TestBox(const Size3d(2, 2, 2))]);
      expect(list.itemCount, 1);

      final extra = TestBox(const Size3d(2, 2, 2));
      list.add(extra);
      expect(list.itemCount, 2);

      list.remove(extra);
      expect(list.itemCount, 1);
    });

    test('stacks items along the scroll axis', () {
      final items = List.generate(5, (_) => TestBox(const Size3d(2, 2, 2)));
      final list = ListView3d(children: items);
      laidOut(list, constraints: window);

      expect(list.size, const Size3d(10, 4, 10));
      expect(items[0].offset.y, 0);
      expect(items[2].offset.y, 4);
      expect(list.controller.maxScrollExtent, 6);
    });

    test('centres items across the cross axes by default', () {
      final item = TestBox(const Size3d(2, 2, 2));
      laidOut(ListView3d(children: [item]), constraints: window);
      expect(item.offset.x, 4);
      expect(item.offset.z, 4);
    });

    test('stretch fills the cross axis, as a Flutter ListView does', () {
      final item = TestBox(const Size3d(2, 2, 2));
      laidOut(
        ListView3d(
          crossAxisAlignment: CrossAxisAlignment3d.stretch,
          children: [item],
        ),
        constraints: window,
      );
      expect(item.size.width, 10);
      expect(item.offset.x, 0);
    });

    test('hides what is outside the window', () {
      final items = List.generate(5, (_) => TestBox(const Size3d(2, 2, 2)));
      final list = ListView3d(children: items);
      final surface = laidOut(list, constraints: window);

      expect(items[0].node.visible, isTrue);
      expect(items[1].node.visible, isTrue);
      expect(items[2].node.visible, isFalse);

      list.controller.jumpTo(4);
      surface.flush();
      expect(items[0].node.visible, isFalse);
      expect(items[2].node.visible, isTrue);
      expect(items[2].offset.y, 0);
    });

    test('a cache extent keeps neighbours alive', () {
      final items = List.generate(5, (_) => TestBox(const Size3d(2, 2, 2)));
      laidOut(ListView3d(cacheExtent: 2, children: items), constraints: window);
      expect(items[2].node.visible, isTrue);
      expect(items[3].node.visible, isFalse);
    });

    test('spacing separates the items', () {
      final items = List.generate(3, (_) => TestBox(const Size3d(2, 2, 2)));
      final list = ListView3d(spacing: 1, children: items);
      laidOut(list, constraints: window);
      expect(items[1].offset.y, 3);
      // Three items of two, two gaps of one.
      expect(list.controller.contentExtent, 8);
    });

    test('scrolls horizontally when asked', () {
      final items = List.generate(5, (_) => TestBox(const Size3d(2, 2, 2)));
      final list = ListView3d(
        scrollDirection: Axis3d.horizontal,
        children: items,
      );
      final surface = laidOut(
        list,
        constraints: Constraints3d.tight(const Size3d(4, 10, 10)),
      );
      expect(items[1].offset.x, 2);
      expect(list.controller.maxScrollExtent, 6);
      list.controller.jumpTo(2);
      surface.flush();
      expect(items[1].offset.x, 0);
    });
  });

  group('ListView3d.builder', () {
    test('with an item extent, builds only what the window shows', () {
      var built = 0;
      final list = ListView3d.builder(
        itemCount: 1000,
        itemExtent: 2,
        itemBuilder: (index) {
          built++;
          return TestBox(const Size3d(2, 2, 2));
        },
      );
      final surface = laidOut(list, constraints: window);

      expect(built, lessThan(5));
      expect(list.activeIndices, containsAll(<int>[0, 1, 2]));
      expect(list.controller.maxScrollExtent, 2 * 1000 - 4);

      list.controller.jumpTo(100);
      surface.flush();
      expect(list.activeIndices, containsAll(<int>[50, 51, 52]));
      expect(list.activeIndices, isNot(contains(0)));
    });

    test('items are positioned by index, not by build order', () {
      final list = ListView3d.builder(
        itemCount: 100,
        itemExtent: 2,
        itemBuilder: (index) => TestBox(const Size3d(2, 2, 2)),
      );
      final surface = laidOut(list, constraints: window);
      list.controller.jumpTo(10);
      surface.flush();

      final indices = list.activeIndices.toList()..sort();
      final first = indices.first;
      for (final index in indices) {
        final child = list.children.firstWhere(
          (candidate) => candidate.offset.y == (index - 5) * 2,
          orElse: () => throw StateError('no child placed for $index'),
        );
        expect(child.size.height, 2);
      }
      expect(first, 5);
    });

    test('without an item extent, measures forward as it goes', () {
      var built = 0;
      final list = ListView3d.builder(
        itemCount: 20,
        itemBuilder: (index) {
          built++;
          return TestBox(const Size3d(2, 2, 2));
        },
      );
      final surface = laidOut(list, constraints: window);

      // Only the items covering the window are kept.
      expect(list.activeIndices, containsAll(<int>[0, 1]));
      expect(list.activeIndices.length, lessThan(4));
      // The total is estimated from what has been measured so far.
      expect(list.controller.contentExtent, 40);

      final builtAtStart = built;
      list.controller.jumpTo(10);
      surface.flush();
      expect(built, greaterThan(builtAtStart));
      expect(list.activeIndices, containsAll(<int>[5, 6]));
      expect(list.activeIndices, isNot(contains(0)));
    });

    test('refuses a child list edit, which its bookkeeping would not survive', () {
      // A built list tracks items by index. A child pushed in from outside is
      // in the child list but not in that map, so it is never laid out and
      // never released; the failure would surface later, as a size assert on
      // a box nobody remembers adding.
      final list = ListView3d.builder(
        itemCount: 3,
        itemExtent: 2,
        itemBuilder: (index) => TestBox(const Size3d(2, 2, 2)),
      );
      laidOut(list, constraints: window);

      expect(
        () => list.add(TestBox(const Size3d(2, 2, 2))),
        throwsA(
          isA<AssertionError>().having(
            (error) => error.message,
            'message',
            allOf(contains('ListView3d.builder'), contains('refresh()')),
          ),
        ),
      );
    });

    test('refresh still edits the child list it owns', () {
      // The guard is on the public entry points; the list's own bookkeeping
      // goes straight to the mixin, or refresh would trip its own assert.
      final list = ListView3d.builder(
        itemCount: 3,
        itemExtent: 2,
        itemBuilder: (index) => TestBox(const Size3d(2, 2, 2)),
      );
      final surface = laidOut(list, constraints: window);
      expect(list.refresh, returnsNormally);
      surface.flush();
      expect(list.activeIndices, isNotEmpty);
    });

    test('refresh rebuilds every item', () {
      var built = 0;
      final list = ListView3d.builder(
        itemCount: 10,
        itemExtent: 2,
        itemBuilder: (index) {
          built++;
          return TestBox(const Size3d(2, 2, 2));
        },
      );
      final surface = laidOut(list, constraints: window);
      final first = built;
      list.refresh();
      surface.flush();
      expect(built, greaterThan(first));
    });
  });
}
