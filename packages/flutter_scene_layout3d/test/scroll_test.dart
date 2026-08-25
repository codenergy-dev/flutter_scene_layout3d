// Viewport3d and ListView3d: a window onto content longer than itself, and
// the controller ownership every scrolling view here shares.

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

    test('refuses an itemCount in its own name', () {
      // The mirror of the guard a built list puts on its child list, and it
      // has to name the class the caller wrote: the SliverList3d underneath
      // is not something they ever mentioned.
      final list = ListView3d(children: [TestBox(const Size3d(2, 2, 2))]);

      expect(
        () => list.itemCount = 5,
        throwsA(
          isA<AssertionError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('ListView3d.builder'),
              isNot(contains('SliverList3d')),
            ),
          ),
        ),
      );
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

    test('a cache extent builds past the window without showing it', () {
      // The cache decides what is built and kept alive, not what is drawn:
      // an item inside it is ready for the scroll that reaches it, and hidden
      // until then. Items 0 and 1 fill the window of 4; item 3 ends at 8 and
      // is built only because the cache reaches it.
      final list = ListView3d.builder(
        itemCount: 10,
        itemExtent: 2,
        cacheExtent: 2,
        itemBuilder: (index) => TestBox(const Size3d(2, 2, 2)),
      );
      laidOut(list, constraints: window);

      expect(list.activeIndices, containsAll(<int>[0, 1, 2, 3]));
      expect(list.children[1].node.visible, isTrue);
      expect(list.children[3].node.visible, isFalse);
    });

    test('spacing separates the items', () {
      final items = List.generate(3, (_) => TestBox(const Size3d(2, 2, 2)));
      final list = ListView3d(spacing: 1, children: items);
      laidOut(list, constraints: window);
      expect(items[1].offset.y, 3);
      // Three items of two, two gaps of one.
      expect(list.controller.contentExtent, 8);
    });

    test('shrink-wraps when the scroll axis has no edge', () {
      // A list with no window to fill is as long as its items, and has
      // nothing left to scroll. The cross axes still need an edge: that is
      // what an item is given to span, as in Flutter.
      final items = List.generate(3, (_) => TestBox(const Size3d(2, 2, 2)));
      final list = ListView3d(children: items);
      laidOut(
        list,
        constraints: const Constraints3d.tightFor(width: 10, depth: 10),
      );

      expect(list.size.height, 6);
      expect(list.controller.maxScrollExtent, 0);
      expect(items[2].offset.y, 4);
      expect(items[2].node.visible, isTrue);
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

  // What the class is underneath: a viewport over one sliver, the shape
  // Flutter's ListView has. None of it changes what a caller sees.
  group('ListView3d is a viewport over one SliverList3d', () {
    test('holds the sliver, and answers children with the items in it', () {
      final items = List.generate(3, (_) => TestBox(const Size3d(2, 2, 2)));
      final list = ListView3d(children: items);
      laidOut(list, constraints: window);

      // The child list a caller reads is the items, not the sliver.
      expect(list.children, items);
      expect(list.childCount, 3);
      expect(list.childAt(1), same(items[1]));
      // The child it holds and lays out is the sliver, and the items are the
      // sliver's, both in the layout tree and in the scene graph.
      expect(list.sliver.children, items);
      expect(items[0].parent, same(list.sliver));
      expect(list.node.children, <Object>[list.sliver.node]);
      // And the sections are the view's own: replacing them would put
      // slivers inside the list of items.
      expect(list.slivers, <Object>[list.sliver]);
      expect(
        () => list.syncSlivers(<Sliver3d>[SliverList3d()]),
        throwsAssertionError,
      );
    });

    test('is the Scrollable3d a hit finds, and the sliver is not', () {
      final item = TestBox(const Size3d(2, 2, 2), pointable: true);
      final list = ListView3d(children: [item]);
      final surface = laidOut(list, constraints: window);

      final hit = surface.hitTestAt(const Offset3d(5, 1, 5));

      expect(hit.target, same(item));
      // The drag handlers reach for this, and the answer has to stay the
      // list: the sliver in between holds no scroll position.
      expect(hit.firstOf<Scrollable3d>(), same(list));
      expect(list.sliver, isNot(isA<Scrollable3d>()));
      expect(hit.path.map((entry) => entry.layout), contains(list.sliver));
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

    test(
      'refuses a child list edit, which its bookkeeping would not survive',
      () {
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
      },
    );

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

  // A measured list guesses its own length and pays for a deep offset by
  // building everything before it. A prototype is the way out that asks
  // nothing of the caller but one item.
  group('ListView3d.builder with a prototypeItem', () {
    test('builds the window and nothing else, however deep the offset', () {
      var built = 0;
      final list = ListView3d.builder(
        itemCount: 5000,
        prototypeItem: () => TestBox(const Size3d(2, 2, 2)),
        itemBuilder: (index) {
          built++;
          return TestBox(const Size3d(2, 2, 2));
        },
      );
      final surface = laidOut(list, constraints: window);
      final atStart = built;
      expect(atStart, lessThan(5));
      expect(list.controller.contentExtent, 10000);

      list.controller.jumpTo(4000);
      surface.flush();

      // Measuring its way here would have built the two thousand items before
      // this one and thrown all but three away.
      expect(built - atStart, lessThan(5));
      expect(list.activeIndices, containsAll(<int>[2000, 2001]));
    });

    test('reports the same range at every offset', () {
      // Items that would measure raggedly: the prototype makes every one of
      // them 3 long, so the total is 400 * 3 wherever the window sits.
      final list = ListView3d.builder(
        itemCount: 400,
        prototypeItem: () => TestBox(const Size3d(2, 3, 2)),
        itemBuilder: (index) => TestBox(Size3d(2, index.isEven ? 1 : 9, 2)),
      );
      final surface = laidOut(list, constraints: window);

      expect(list.controller.contentExtent, 1200);
      for (final offset in <double>[10, 500, 1196]) {
        list.controller.jumpTo(offset);
        surface.flush();
        expect(list.controller.contentExtent, 1200);
      }
    });

    test('measures one prototype, and never shows it', () {
      final prototypes = <TestBox>[];
      final list = ListView3d.builder(
        itemCount: 100,
        prototypeItem: () {
          final box = TestBox(const Size3d(2, 2, 2), name: 'prototype');
          prototypes.add(box);
          return box;
        },
        itemBuilder: (index) => TestBox(const Size3d(2, 2, 2)),
      );
      final surface = laidOut(list, constraints: window);
      list.controller.jumpTo(50);
      surface.flush();

      expect(prototypes, hasLength(1));
      final prototype = prototypes.single;
      expect(prototype.layoutCount, 1);
      // Not an item: not in the child list, and its node is not in the scene
      // at all, so there is nothing to cull, hit, or draw.
      expect(list.children, isNot(contains(prototype)));
      expect(list.node.children, isNot(contains(prototype.node)));
      expect(prototype.node.visible, isFalse);
    });

    test('measures it again when the constraints an item gets change', () {
      final prototypes = <TestBox>[];
      final list = ListView3d.builder(
        itemCount: 100,
        prototypeItem: () {
          final box = TestBox(const Size3d(2, 2, 2));
          prototypes.add(box);
          return box;
        },
        itemBuilder: (index) => TestBox(const Size3d(2, 2, 2)),
      );
      final surface = laidOut(list, constraints: window);
      expect(prototypes.single.layoutCount, 1);

      list.crossAxisAlignment = CrossAxisAlignment3d.stretch;
      surface.flush();

      // The same prototype, measured against the new constraints.
      expect(prototypes, hasLength(1));
      expect(prototypes.single.layoutCount, 2);
      expect(prototypes.single.size.width, 10);
    });

    test('refresh builds a new one, the data behind it having changed', () {
      var prototypes = 0;
      final list = ListView3d.builder(
        itemCount: 100,
        prototypeItem: () {
          prototypes++;
          return TestBox(const Size3d(2, 2, 2));
        },
        itemBuilder: (index) => TestBox(const Size3d(2, 2, 2)),
      );
      final surface = laidOut(list, constraints: window);
      expect(prototypes, 1);

      list.refresh();
      surface.flush();
      expect(prototypes, 2);
    });

    test('refuses an itemExtent alongside it', () {
      expect(
        () => ListView3d.builder(
          itemCount: 10,
          itemExtent: 2,
          prototypeItem: () => TestBox(const Size3d(2, 2, 2)),
          itemBuilder: (index) => TestBox(const Size3d(2, 2, 2)),
        ),
        throwsA(
          isA<AssertionError>().having(
            (error) => error.message,
            'message',
            allOf(contains('itemExtent'), contains('prototypeItem')),
          ),
        ),
      );
    });
  });

  group('ListView3d.builder with a contentExtentEstimator', () {
    // Five long items and thirty-five short ones, so the average of what has
    // been measured starts far too long and shrinks as the list is read.
    Size3d sizeOf(int index) =>
        index < 5 ? const Size3d(2, 10, 2) : const Size3d(2, 1, 2);

    ListView3d listOf([Layout3dContentExtentEstimator? estimator]) =>
        ListView3d.builder(
          itemCount: 40,
          contentExtentEstimator: estimator,
          itemBuilder: (index) => TestBox(sizeOf(index)),
        );

    test('holds a range still that the average moves', () {
      final guessing = listOf();
      final guessingSurface = laidOut(guessing, constraints: window);
      final firstGuess = guessing.controller.contentExtent;
      guessing.controller.jumpTo(60);
      guessingSurface.flush();
      expect(guessing.controller.contentExtent, isNot(firstGuess));

      // 5 * 10 + 35 * 1, which the caller knows and the list cannot.
      final told = listOf((count) => 85);
      final toldSurface = laidOut(told, constraints: window);
      expect(told.controller.contentExtent, 85);
      expect(told.controller.maxScrollExtent, 81);

      told.controller.jumpTo(60);
      toldSurface.flush();
      expect(told.controller.contentExtent, 85);
    });

    test('never claims the content is shorter than what was measured', () {
      // Where an item sits comes from the measurement and is exact; a total
      // under it would put items outside the range they are sitting in.
      final list = ListView3d.builder(
        itemCount: 100,
        contentExtentEstimator: (count) => 1,
        itemBuilder: (index) => TestBox(const Size3d(2, 2, 2)),
      );
      laidOut(list, constraints: window);

      expect(list.controller.contentExtent, 6);
    });
  });

  group('the measuring pass complains about work it throws away', () {
    ListView3d longList() => ListView3d.builder(
      itemCount: 2000,
      itemBuilder: (index) => TestBox(const Size3d(2, 2, 2)),
    );

    test('a deep offset measures its way there and says so', () {
      // The cost of the measured mode, made loud: reaching a deep offset
      // builds every item before it and keeps two. Debug only, and it names
      // both ways out.
      final list = longList();
      final surface = laidOut(list, constraints: window);
      list.controller.jumpTo(3000);

      expect(
        surface.flush,
        throwsA(
          isA<AssertionError>().having(
            (error) => error.message,
            'message',
            allOf(contains('itemExtent'), contains('prototypeItem')),
          ),
        ),
      );
    });

    test('a long window measuring hundreds of items does not', () {
      // The items measured here are the items on screen: a window 1400 long
      // holds seven hundred of them, and measuring those is the work rather
      // than a symptom of it. Counting measurements alone called this a
      // runaway pass and turned a working layout into a debug crash.
      final list = longList();
      laidOut(list, constraints: Constraints3d.tight(const Size3d(10, 1400, 10)));

      expect(list.size.height, 1400);
      expect(list.activeIndices, hasLength(greaterThan(500)));
      expect(list.children.last.node.visible, isTrue);
    });

    test('an unbounded window measuring everything does not either', () {
      final list = longList();
      laidOut(
        list,
        constraints: const Constraints3d.tightFor(width: 10, depth: 10),
      );

      expect(list.activeIndices, hasLength(2000));
      expect(list.size.height, 4000);
    });
  });

  // Every scrolling view holds a Scroll3dController the same way, through
  // Scroll3dHolderMixin, so the rule is checked on all four at once: content
  // 10 long in a window 4 long, and the first box slides by whatever the
  // controller in force says.
  group('controller ownership', () {
    final views =
        <String, Scroll3dHolderMixin Function(Scroll3dController?, Layout3d)>{
          'Viewport3d': (controller, probe) =>
              Viewport3d(controller: controller, child: probe),
          'ListView3d': (controller, probe) =>
              ListView3d(controller: controller, children: [probe]),
          'GridView3d': (controller, probe) => GridView3d(
            gridDelegate: const Grid3dDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              childAspectRatio: 0.2,
            ),
            controller: controller,
            children: [probe],
          ),
          'CustomScrollView3d': (controller, probe) => CustomScrollView3d(
            controller: controller,
            slivers: [SliverToBoxAdapter3d(child: probe)],
          ),
        };

    for (final entry in views.entries) {
      final name = entry.key;
      final build = entry.value;

      test('$name disposes the controller it made, and only that one', () {
        final made = build(null, TestBox(const Size3d(2, 10, 2)));
        final own = made.controller;
        made.dispose();
        expect(isDisposed(own), isTrue);

        final supplied = Scroll3dController();
        build(supplied, TestBox(const Size3d(2, 10, 2))).dispose();
        expect(isDisposed(supplied), isFalse);
        supplied.dispose();
      });

      test('$name takes a fresh controller back when given null', () {
        final supplied = Scroll3dController();
        final probe = TestBox(const Size3d(2, 10, 2));
        final view = build(supplied, probe);
        final surface = laidOut(view, constraints: window);

        supplied.jumpTo(3);
        surface.flush();
        expect(probe.offset.y, -3);

        view.controller = null;
        surface.flush();
        final held = view.controller;
        expect(identical(held, supplied), isFalse);
        // The one that was handed in belongs to whoever handed it in.
        expect(isDisposed(supplied), isFalse);

        // The fresh one starts at the top and drives the view; the old one
        // no longer does.
        expect(probe.offset.y, 0);
        supplied.jumpTo(1);
        surface.flush();
        expect(probe.offset.y, 0);
        held.jumpTo(2);
        surface.flush();
        expect(probe.offset.y, -2);

        supplied.dispose();
      });
    }
  });
}
