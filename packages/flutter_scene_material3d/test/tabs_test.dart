// TabBar3d and TabBarView3d: Flutter's controller driving tabs on a plane,
// an indicator that slides on the node tier, and pages that follow it.

import 'dart:ui' show Color, SemanticsRole;

import 'package:flutter/material.dart' show Icons, TabController;
import 'package:flutter/widgets.dart' show TextDirection, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/testing.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'surfaces_support.dart';

const Theme3dData _theme = Theme3dData.light;
const double _dp = 0.01;

const List<Tab3d> _tabs = <Tab3d>[
  Tab3d(text: 'Day'),
  Tab3d(text: 'Week'),
  Tab3d(text: 'Month'),
];

TabController _controller({int initialIndex = 0, int length = 3}) =>
    TabController(
      length: length,
      initialIndex: initialIndex,
      vsync: const TestVSync(),
    );

/// A bar 3 units wide at the top of a column, the shape a screen gives one.
Widget _bar(Widget bar) => SceneSizedBox3d(
  width: 3,
  child: SceneColumn3d(
    mainAxisSize: MainAxisSize3d.min,
    crossAxisAlignment: CrossAxisAlignment3d.stretch,
    children: <Widget>[bar],
  ),
);

/// A bar over pages, 3 units by 2.
Widget _barOverPages(TabController controller, List<Widget> pages) =>
    SceneSizedBox3d(
      width: 3,
      height: 2,
      child: SceneColumn3d(
        crossAxisAlignment: CrossAxisAlignment3d.stretch,
        children: <Widget>[
          TabBar3d(controller: controller, tabs: _tabs),
          SceneExpanded3d(
            child: TabBarView3d(controller: controller, children: pages),
          ),
        ],
      ),
    );

/// The tab bar's own box.
MultiChildLayout3d _barBox(Layout3dSurface surface) =>
    namedBox(surface, 'TabBar3d') as MultiChildLayout3d;

/// The indicator: the third child of the bar's box.
Layout3d _indicator(Layout3dSurface surface) => _barBox(surface).childAt(2);

/// The box a label measured, by its index.
Layout3d _label(Layout3dSurface surface, int index) =>
    namedBox(surface, 'TabBar3d label $index');

Layout3d _slot(Layout3dSurface surface, int index) =>
    namedBox(surface, 'TabBar3d tab $index');

/// [box]'s left edge in the bar's frame.
double _xInBar(Layout3dSurface surface, Layout3d box) {
  final bar = _barBox(surface);
  var x = 0.0;
  for (var walk = box; !identical(walk, bar); walk = walk.parent!) {
    x += walk.offset.x;
  }
  return x;
}

/// Where the indicator is drawn, as its left and right edges in the bar's
/// frame: where it was laid out, moved and stretched by its node tier.
(double, double) _drawn(Layout3dSurface surface) {
  final indicator = _indicator(surface);
  final scale = indicator.nodeTransform?.storage[0] ?? 1.0;
  final left = indicator.offset.x + indicator.nodeOffset.x;
  return (left, left + indicator.size.width * scale);
}

/// The semantics node of the tab announcing [label].
Semantics3d _announced(Layout3dSurface surface, String label) =>
    boxesOf<Semantics3d>(
      surface,
    ).firstWhere((box) => box.properties.label == label);

Future<void> _pressAt(PumpedSurface pumped, Layout3d box) async {
  pumped.pointer.down(
    rayAt(pumped.surface, box.drawnOffsetInSurface + box.size.center),
  );
  pumped.pointer.up();
}

void main() {
  group('TabBar3d', () {
    testWidgets('is 48dp tall, a 46dp tab and the 2dp under it', (
      tester,
    ) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final pumped = await pumpComponent(
        tester,
        () => _bar(TabBar3d(controller: controller, tabs: _tabs)),
      );
      final style = TabBarStyle3d.of(_theme, TabBarVariant3d.primary);
      expect(
        _barBox(pumped.surface).size.height,
        closeTo((style.tabHeight + style.reservedHeight) * _dp, 1e-9),
      );
      // Three equal tabs across the bar.
      for (var i = 0; i < 3; i++) {
        expect(_slot(pumped.surface, i).size.width, closeTo(1.0, 1e-9));
      }
    });

    testWidgets('and 74dp when a tab has an icon and a label', (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final pumped = await pumpComponent(
        tester,
        () => _bar(
          TabBar3d(
            controller: controller,
            tabs: const <Tab3d>[
              Tab3d(text: 'Flights', icon: Icon3d(Icons.flight)),
              Tab3d(text: 'Trips'),
              Tab3d(text: 'Explore'),
            ],
          ),
        ),
      );
      final style = TabBarStyle3d.of(_theme, TabBarVariant3d.primary);
      expect(
        _barBox(pumped.surface).size.height,
        closeTo(
          (style.textAndIconTabHeight + style.reservedHeight) * _dp,
          1e-9,
        ),
      );
      // The tab with only a label is padded to the same height.
      for (var i = 0; i < 3; i++) {
        expect(
          _slot(pumped.surface, i).size.height,
          closeTo(_barBox(pumped.surface).size.height, 1e-9),
        );
      }
    });

    testWidgets('the chosen label is primary and the others onSurfaceVariant', (
      tester,
    ) async {
      final controller = _controller(initialIndex: 1);
      addTearDown(controller.dispose);
      final pumped = await pumpComponent(
        tester,
        () => _bar(TabBar3d(controller: controller, tabs: _tabs)),
      );
      final scheme = _theme.colorScheme;
      Color colourOf(int index) {
        final found = <Text3d>[];
        void walk(Layout3d box) {
          if (box is Text3d) found.add(box);
          box.visitChildren(walk);
        }

        walk(_label(pumped.surface, index));
        return found.single.style.color!;
      }

      expect(colourOf(1), scheme.primary);
      expect(colourOf(0), scheme.onSurfaceVariant);
      expect(colourOf(2), scheme.onSurfaceVariant);
    });

    testWidgets('at rest the primary indicator is under the chosen label, '
        'as wide as it', (tester) async {
      final controller = _controller(initialIndex: 2);
      addTearDown(controller.dispose);
      final pumped = await pumpComponent(
        tester,
        () => _bar(TabBar3d(controller: controller, tabs: _tabs)),
      );
      final style = TabBarStyle3d.of(_theme, TabBarVariant3d.primary);
      final label = _label(pumped.surface, 2);
      final indicator = _indicator(pumped.surface);
      expect(indicator.size.width, closeTo(label.size.width, 1e-9));
      expect(indicator.offset.x, closeTo(_xInBar(pumped.surface, label), 1e-9));
      expect(indicator.size.height, closeTo(style.indicatorWeight * _dp, 1e-9));
      // On the bar's foot, and honest: nothing on the node tier at rest.
      expect(
        indicator.offset.y + indicator.size.height,
        closeTo(_barBox(pumped.surface).size.height, 1e-9),
      );
      expect(indicator.nodeOffset, Offset3d.zero);
      expect(indicator.nodeTransform, isNull);
      final decoration =
          boxesOf<DecoratedBox3d>(pumped.surface)
                  .firstWhere(
                    (box) =>
                        (box.decoration as BoxDecoration3d).color ==
                        _theme.colorScheme.primary,
                  )
                  .decoration
              as BoxDecoration3d;
      expect(decoration.borderRadius, const BorderRadius3d.vertical(top: 3));
    });

    testWidgets('the secondary indicator is as wide as the tab, and square', (
      tester,
    ) async {
      final controller = _controller(initialIndex: 1);
      addTearDown(controller.dispose);
      final pumped = await pumpComponent(
        tester,
        () => _bar(TabBar3d.secondary(controller: controller, tabs: _tabs)),
      );
      final indicator = _indicator(pumped.surface);
      expect(indicator.size.width, closeTo(1.0, 1e-9));
      expect(indicator.offset.x, closeTo(1.0, 1e-9));
      expect(indicator.size.height, closeTo(2 * _dp, 1e-9));
    });

    testWidgets('the rule is across the foot, behind the indicator', (
      tester,
    ) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final pumped = await pumpComponent(
        tester,
        () => _bar(TabBar3d(controller: controller, tabs: _tabs)),
      );
      final style = TabBarStyle3d.of(_theme, TabBarVariant3d.primary);
      final bar = _barBox(pumped.surface);
      final rule = bar.childAt(1);
      expect(rule.size.width, closeTo(3.0, 1e-9));
      expect(rule.size.height, closeTo(style.dividerHeight * _dp, 1e-9));
      expect(rule.offset.y + rule.size.height, closeTo(bar.size.height, 1e-9));
      // Toward the viewer is negative z: the rule one step in front of the
      // tabs, the indicator one more.
      expect(
        rule.parentData!.sceneOffset.z,
        closeTo(-style.depthStep * _dp, 1e-9),
      );
      expect(
        bar.childAt(2).parentData!.sceneOffset.z,
        closeTo(-2 * style.depthStep * _dp, 1e-9),
      );
      expect(
        _theme.thickness.separates(
          style.thickness,
          style.thickness,
          step: style.depthStep,
        ),
        isTrue,
      );
    });

    testWidgets('a press animates the controller to its tab', (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final tapped = <int>[];
      final pumped = await pumpComponent(
        tester,
        () => _bar(
          TabBar3d(controller: controller, tabs: _tabs, onTap: tapped.add),
        ),
      );
      await _pressAt(pumped, _slot(pumped.surface, 2));
      await tester.pump();
      expect(controller.index, 2);
      expect(controller.indexIsChanging, isTrue);
      expect(tapped, <int>[2]);
      await tester.pumpAndSettle();
      expect(controller.indexIsChanging, isFalse);
      expect(_announced(pumped.surface, 'Month').properties.selected, isTrue);
      expect(_announced(pumped.surface, 'Day').properties.selected, isFalse);
      // At rest under its new label, honestly.
      final indicator = _indicator(pumped.surface);
      expect(indicator.nodeOffset, Offset3d.zero);
      expect(
        indicator.offset.x,
        closeTo(_xInBar(pumped.surface, _label(pumped.surface, 2)), 1e-9),
      );
    });

    testWidgets('the slide lays nothing out and builds only once, at its end', (
      tester,
    ) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final pumped = await pumpComponent(
        tester,
        () => _bar(TabBar3d(controller: controller, tabs: _tabs)),
      );
      // Started outside the watch: the start is the frame the indicator is
      // laid out to rest under the new tab, and the bar rebuilds for its
      // labels' colours. What is watched is everything after.
      controller.animateTo(1);
      await tester.pump();
      final watched = await watchFrames(tester, pumped.surface, frames: 25);
      expect(watched.laidOut, isEmpty, reason: 'frames that laid out');
      // The end of a change notifies, and Flutter's bar rebuilds then too;
      // nothing before it.
      final frames = watched.rebuilt
          .map((entry) => entry.split(' on frame ').last)
          .toSet();
      expect(frames.length, lessThanOrEqualTo(1), reason: '${watched.rebuilt}');
      expect(controller.indexIsChanging, isFalse);
    });

    testWidgets('in flight the indicator is between the two tabs', (
      tester,
    ) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final pumped = await pumpComponent(
        tester,
        () => _bar(TabBar3d.secondary(controller: controller, tabs: _tabs)),
      );
      controller.animateTo(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final (left, right) = _drawn(pumped.surface);
      expect(left, greaterThan(0.0));
      expect(left, lessThan(1.0));
      // Linear: one width, carried across.
      expect(right - left, closeTo(1.0, 1e-9));
      // And it is the node tier doing it: the box rests under the new tab.
      expect(_indicator(pumped.surface).offset.x, closeTo(1.0, 1e-9));
      await tester.pumpAndSettle();
    });

    testWidgets('the primary indicator stretches, its leading edge ahead', (
      tester,
    ) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final pumped = await pumpComponent(
        tester,
        () => _bar(TabBar3d(controller: controller, tabs: _tabs)),
      );
      double left(int index) =>
          _xInBar(pumped.surface, _label(pumped.surface, index));
      double right(int index) =>
          left(index) + _label(pumped.surface, index).size.width;
      final from = (left(0), right(0));
      final to = (left(1), right(1));
      controller.animateTo(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final (l, r) = _drawn(pumped.surface);
      final leftProgress = (l - from.$1) / (to.$1 - from.$1);
      final rightProgress = (r - from.$2) / (to.$2 - from.$2);
      expect(leftProgress, inExclusiveRange(0.0, 1.0));
      expect(rightProgress, inExclusiveRange(0.0, 1.0));
      expect(rightProgress, greaterThan(leftProgress));
      await tester.pumpAndSettle();
    });

    testWidgets('right to left: the first tab and its indicator at the right', (
      tester,
    ) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final pumped = await pumpComponent(
        tester,
        () => _bar(TabBar3d.secondary(controller: controller, tabs: _tabs)),
        textDirection: TextDirection.rtl,
      );
      expect(
        _xInBar(pumped.surface, _slot(pumped.surface, 0)),
        closeTo(2.0, 1e-9),
      );
      expect(_indicator(pumped.surface).offset.x, closeTo(2.0, 1e-9));
      controller.animateTo(1);
      await tester.pumpAndSettle();
      expect(_indicator(pumped.surface).offset.x, closeTo(1.0, 1e-9));
    });

    testWidgets('each tab announces itself as a tab, and the bar as nothing', (
      tester,
    ) async {
      final controller = _controller(initialIndex: 1);
      addTearDown(controller.dispose);
      final pumped = await pumpComponent(
        tester,
        () => _bar(TabBar3d(controller: controller, tabs: _tabs)),
      );
      final tabs = boxesOf<Semantics3d>(
        pumped.surface,
      ).where((box) => box.properties.role == SemanticsRole.tab).toList();
      expect(tabs.map((box) => box.properties.label), <String>[
        'Day',
        'Week',
        'Month',
      ]);
      expect(tabs.map((box) => box.properties.selected), <bool>[
        false,
        true,
        false,
      ]);
      // And no node for the bar: Flutter checks that a tab bar's children
      // are tabs, and a `Semantics3d` has none, so a `tabBar` node is an empty
      // bar that stops a frame building once semantics are on.
      expect(
        boxesOf<Semantics3d>(
          pumped.surface,
        ).where((box) => box.properties.role == SemanticsRole.tabBar),
        isEmpty,
      );
    });

    testWidgets('refuses a controller of the wrong length', (tester) async {
      final controller = _controller(length: 2);
      addTearDown(controller.dispose);
      await pumpComponent(
        tester,
        () => _bar(TabBar3d(controller: controller, tabs: _tabs)),
      );
      expect(tester.takeException(), isA<AssertionError>());
    });
  });

  group('TabBarView3d', () {
    List<Widget> pages() => <Widget>[
      for (var i = 0; i < 3; i++) SceneText3d('Page $i'),
    ];

    /// The page view's position, counted in pages.
    double pageOf(Layout3dSurface surface) {
      final view = boxesOf<PageView3d>(surface).single;
      return view.controller.offset / view.controller.viewportExtent;
    }

    testWidgets('opens on the controller\'s tab, with no jump', (tester) async {
      final controller = _controller(initialIndex: 2);
      addTearDown(controller.dispose);
      final pumped = await pumpComponent(
        tester,
        () => _barOverPages(controller, pages()),
      );
      expect(pageOf(pumped.surface), closeTo(2.0, 1e-9));
    });

    testWidgets('a press on a tab turns the pages to it', (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final pumped = await pumpComponent(
        tester,
        () => _barOverPages(controller, pages()),
      );
      await _pressAt(pumped, _slot(pumped.surface, 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(pageOf(pumped.surface), inExclusiveRange(0.0, 1.0));
      await tester.pumpAndSettle();
      expect(pageOf(pumped.surface), closeTo(1.0, 1e-9));
      expect(controller.index, 1);
    });

    testWidgets('a swipe moves the controller as it goes and chooses the tab '
        'it settles on', (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final pumped = await pumpComponent(
        tester,
        () => _barOverPages(controller, pages()),
      );
      final view = boxesOf<PageView3d>(pumped.surface).single;
      final middle = view.drawnOffsetInSurface + view.size.center;
      final pointer = pumped.pointer;
      pointer.down(rayAt(pumped.surface, middle));
      for (var i = 1; i <= 10; i++) {
        pointer.move(
          rayAt(pumped.surface, middle - Offset3d(0.2 * i, 0, 0)),
          timeStamp: Duration(milliseconds: 16 * i),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      // Two thirds of a page across: the indicator is following the finger.
      expect(controller.index, 0);
      expect(controller.offset, closeTo(2.0 / 3.0, 0.05));
      pointer.up(timeStamp: const Duration(milliseconds: 176));
      await tester.pumpAndSettle();
      expect(controller.index, 1);
      expect(controller.offset, closeTo(0.0, 1e-9));
      expect(pageOf(pumped.surface), closeTo(1.0, 1e-9));
    });

    testWidgets('right to left reads the pages backwards', (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final pumped = await pumpComponent(
        tester,
        () => _barOverPages(controller, pages()),
        textDirection: TextDirection.rtl,
      );
      // The first tab's page is the last in the view, and the view opens on
      // it.
      expect(pageOf(pumped.surface), closeTo(2.0, 1e-9));
      controller.animateTo(1);
      await tester.pumpAndSettle();
      expect(pageOf(pumped.surface), closeTo(1.0, 1e-9));
      controller.animateTo(2);
      await tester.pumpAndSettle();
      expect(pageOf(pumped.surface), closeTo(0.0, 1e-9));
    });

    testWidgets('mid-turn, a label that has left the window draws nothing', (
      tester,
    ) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final pumped = await pumpComponent(
        tester,
        () => _barOverPages(controller, <Widget>[
          for (var i = 0; i < 3; i++)
            SceneRow3d(
              mainAxisAlignment: MainAxisAlignment3d.spaceBetween,
              children: <Widget>[
                SceneText3d('Start $i'),
                SceneText3d('End $i'),
              ],
            ),
        ]),
      );
      Text3d label(String text) =>
          boxesOf<Text3d>(pumped.surface).firstWhere((box) => box.data == text);
      controller.animateTo(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // About half across: the first page's start has left the window and
      // its end has not; the second page's end is still to come.
      expect(pageOf(pumped.surface), inExclusiveRange(0.3, 0.7));
      expect(label('Start 0').node.visible, isFalse);
      expect(label('End 0').node.visible, isTrue);
      expect(label('Start 1').node.visible, isTrue);
      expect(label('End 1').node.visible, isFalse);
      await tester.pumpAndSettle();
      expect(label('Start 1').node.visible, isTrue);
      expect(label('End 1').node.visible, isTrue);
    });

    testWidgets('every page is a tab panel', (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final pumped = await pumpComponent(
        tester,
        () => _barOverPages(controller, pages()),
      );
      expect(
        boxesOf<Semantics3d>(
          pumped.surface,
        ).where((box) => box.properties.role == SemanticsRole.tabPanel),
        isNotEmpty,
      );
    });
  });
}
