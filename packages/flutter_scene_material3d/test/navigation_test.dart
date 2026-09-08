// NavigationBar3d and NavigationRail3d: destinations, the selected state,
// the pill, and what a hover costs.

import 'dart:ui' show Color;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'surfaces_support.dart';

const Theme3dData _theme = Theme3dData.light;
const double _dp = 0.01;

const List<NavigationDestination3d> _destinations = <NavigationDestination3d>[
  NavigationDestination3d(icon: Icon3d(Icons.inbox), label: 'Inbox'),
  NavigationDestination3d(icon: Icon3d(Icons.send), label: 'Sent'),
  NavigationDestination3d(icon: Icon3d(Icons.delete), label: 'Trash'),
];

/// A bar at the bottom of a screen-shaped column; see `app_bar_test.dart`
/// for why a bar cannot be pumped straight onto a surface.
Widget screenWith(Widget bar) => SceneColumn3d(
  crossAxisAlignment: CrossAxisAlignment3d.stretch,
  children: <Widget>[
    const SceneExpanded3d(child: SceneSizedBox3d()),
    bar,
  ],
);

Widget railBeside(Widget rail) => SceneRow3d(
  crossAxisAlignment: CrossAxisAlignment3d.stretch,
  children: <Widget>[
    rail,
    const SceneExpanded3d(child: SceneSizedBox3d()),
  ],
);

void main() {
  group('NavigationBar3d', () {
    testWidgets('is 80dp tall, on surfaceContainer, at level 2', (
      tester,
    ) async {
      final pumped = await pumpComponent(
        tester,
        () => screenWith(
          const NavigationBar3d(destinations: _destinations, selectedIndex: 0),
        ),
        centred: false,
      );
      final bar = pumped.panels.first;
      expect(bar.size.height, closeTo(80 * _dp, 1e-9));
      expect(bar.size.depth, closeTo(_theme.thickness.structural * _dp, 1e-9));
      final decoration = bar.decoration as BoxDecoration3d;
      expect(decoration.color, _theme.colorScheme.surfaceContainer);
      expect(decoration.elevation, _theme.elevation.level2);
    });

    testWidgets('draws a pill behind the selected destination and no other', (
      tester,
    ) async {
      final pumped = await pumpComponent(
        tester,
        () => screenWith(
          const NavigationBar3d(destinations: _destinations, selectedIndex: 1),
        ),
        centred: false,
      );
      final pills = pumped.panels
          .map((box) => box.decoration as BoxDecoration3d)
          .where((d) => d.color == _theme.colorScheme.secondaryContainer)
          .toList(growable: false);
      expect(pills, hasLength(1));
      expect(pills.single.borderRadius, _theme.shape.full);
    });

    testWidgets('and the pill is 64 by 32, the size Flutter publishes', (
      tester,
    ) async {
      final pumped = await pumpComponent(
        tester,
        () => screenWith(
          const NavigationBar3d(destinations: _destinations, selectedIndex: 0),
        ),
        centred: false,
      );
      final pill = pumped.panels.firstWhere(
        (box) =>
            (box.decoration as BoxDecoration3d).color ==
            _theme.colorScheme.secondaryContainer,
      );
      expect(pill.size.width, closeTo(64 * _dp, 1e-9));
      expect(pill.size.height, closeTo(32 * _dp, 1e-9));
    });

    testWidgets('the glyph stands in front of the pill rather than on it', (
      tester,
    ) async {
      // Two coplanar surfaces z-fight, and a glyph drawn exactly on the
      // pill's front face is one. The stack's depth step is what separates
      // them, and it has to clear the mean of the two thicknesses — which
      // for a glyph with no depth is half the pill's.
      final pumped = await pumpComponent(
        tester,
        () => screenWith(
          const NavigationBar3d(destinations: _destinations, selectedIndex: 0),
        ),
        centred: false,
      );
      final stacks = boxesOf<Stack3d>(pumped.surface);
      expect(stacks, hasLength(_destinations.length));
      final step = stacks.first.depthStep;
      expect(step, closeTo(_theme.thickness.thin * _dp, 1e-9));
      expect(
        _theme.thickness.separates(
          _theme.thickness.thin,
          0.0,
          step: _theme.thickness.thin,
        ),
        isTrue,
      );
    });

    testWidgets('every destination announces itself, one of them selected', (
      tester,
    ) async {
      final pumped = await pumpComponent(
        tester,
        () => screenWith(
          NavigationBar3d(
            destinations: _destinations,
            selectedIndex: 2,
            onDestinationSelected: (_) {},
          ),
        ),
        centred: false,
      );
      final announced = boxesOf<Semantics3d>(pumped.surface);
      expect(announced, hasLength(3));
      expect(announced.map((s) => s.properties.label), <String>[
        'Inbox',
        'Sent',
        'Trash',
      ]);
      expect(announced.map((s) => s.properties.selected), <bool>[
        false,
        false,
        true,
      ]);
      expect(announced.every((s) => s.properties.button == true), isTrue);
    });

    testWidgets('and each has a 48dp target of its own', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => screenWith(
          NavigationBar3d(
            destinations: _destinations,
            selectedIndex: 0,
            onDestinationSelected: (_) {},
          ),
        ),
        centred: false,
      );
      // Six, not three: the outer one per destination that carries the
      // reach, and the InkWell3d's own inside it at `Size3d.zero`, which is
      // the arrangement `ListTile3d` uses and for the same reason — one
      // target rather than two nested ones disagreeing about where the
      // control is.
      final all = boxesOf<TapTarget3d>(pumped.surface);
      expect(all, hasLength(6));
      final targets = all
          .where((t) => t.effectiveMinimumSize.width > 0.0)
          .toList(growable: false);
      expect(targets, hasLength(3));
      for (final target in targets) {
        expect(target.effectiveMinimumSize.width, closeTo(48 * _dp, 1e-9));
        expect(target.effectiveMinimumSize.height, closeTo(48 * _dp, 1e-9));
      }
    });

    testWidgets('a tap picks the destination under it', (tester) async {
      final chosen = <int>[];
      final pumped = await pumpComponent(
        tester,
        () => screenWith(
          NavigationBar3d(
            destinations: _destinations,
            selectedIndex: 0,
            onDestinationSelected: chosen.add,
          ),
        ),
        centred: false,
      );
      final targets = boxesOf<TapTarget3d>(pumped.surface)
          .where((t) => t.effectiveMinimumSize.width > 0.0)
          .toList(growable: false);
      final middle = offsetInSurface(targets[1]) + targets[1].size.center;
      pumped.pointer.down(rayAt(pumped.surface, middle));
      pumped.pointer.up();
      await tester.pump();
      expect(chosen, <int>[1]);
    });

    testWidgets('a wash costs no layout at all', (tester) async {
      // Every interactive component in this catalogue gets the animation
      // plan's guard.
      final pumped = await pumpComponent(
        tester,
        () => screenWith(
          NavigationBar3d(
            destinations: _destinations,
            selectedIndex: 0,
            onDestinationSelected: (_) {},
          ),
        ),
        centred: false,
      );
      final target = boxesOf<TapTarget3d>(
        pumped.surface,
      ).firstWhere((t) => t.effectiveMinimumSize.width > 0.0);
      final middle = offsetInSurface(target) + target.size.center;
      final builds = pumped.builds[0];

      pumped.pointer.hover(rayAt(pumped.surface, middle));
      await tester.pump();
      expect(pumped.builds[0], builds);
      expect(pumped.surface.needsFlush, isFalse, reason: 'nothing laid out');
    });

    testWidgets('refuses a bar with one destination', (tester) async {
      // In build rather than in the constructor: a const constructor's
      // asserts are compile-time, and `List.length` is not a constant there.
      await pumpComponent(
        tester,
        () => screenWith(
          const NavigationBar3d(
            destinations: <NavigationDestination3d>[
              NavigationDestination3d(
                icon: Icon3d(Icons.inbox),
                label: 'Inbox',
              ),
            ],
            selectedIndex: 0,
          ),
        ),
        centred: false,
      );
      expect(tester.takeException(), isA<AssertionError>());
    });
  });

  group('NavigationRail3d', () {
    testWidgets('is 80dp wide, on surface, flat', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => railBeside(
          const NavigationRail3d(destinations: _destinations, selectedIndex: 0),
        ),
        centred: false,
      );
      final rail = pumped.panels.first;
      expect(rail.size.width, closeTo(80 * _dp, 1e-9));
      final decoration = rail.decoration as BoxDecoration3d;
      expect(decoration.color, _theme.colorScheme.surface);
      expect(decoration.elevation, _theme.elevation.level0);
    });

    testWidgets('its pill is 56 wide rather than 64', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => railBeside(
          const NavigationRail3d(destinations: _destinations, selectedIndex: 0),
        ),
        centred: false,
      );
      final pill = pumped.panels.firstWhere(
        (box) =>
            (box.decoration as BoxDecoration3d).color ==
            _theme.colorScheme.secondaryContainer,
      );
      expect(pill.size.width, closeTo(56 * _dp, 1e-9));
      expect(pill.size.height, closeTo(32 * _dp, 1e-9));
    });

    testWidgets('takes a leading and a trailing slot', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => railBeside(
          NavigationRail3d(
            destinations: _destinations,
            selectedIndex: 0,
            leading: FloatingActionButton3d(
              semanticLabel: 'Compose',
              onPressed: () {},
              child: const Icon3d(Icons.edit),
            ),
            trailing: const Icon3d(Icons.settings),
          ),
        ),
        centred: false,
      );
      // Three destinations plus the button's own announcement.
      final announced = boxesOf<Semantics3d>(pumped.surface);
      expect(announced.map((s) => s.properties.label), contains('Compose'));
      expect(announced.map((s) => s.properties.label), contains('Trash'));
    });

    testWidgets('and a VerticalDivider3d beside it separates the two', (
      tester,
    ) async {
      // The rule phase 4 deliberately deferred to this phase, because the
      // rail is the first thing with something to separate.
      final pumped = await pumpComponent(
        tester,
        () => SceneRow3d(
          crossAxisAlignment: CrossAxisAlignment3d.stretch,
          children: <Widget>[
            const NavigationRail3d(
              destinations: _destinations,
              selectedIndex: 0,
            ),
            const VerticalDivider3d(),
            const SceneExpanded3d(child: SceneSizedBox3d()),
          ],
        ),
        centred: false,
      );
      final rule = pumped.panels.firstWhere(
        (box) =>
            (box.decoration as BoxDecoration3d).color ==
            _theme.colorScheme.outlineVariant,
      );
      expect(rule.size.width, closeTo(_dp, 1e-9));
      expect(rule.size.depth, closeTo(_theme.thickness.thin * _dp, 1e-9));
    });
  });

  group('the navigation tokens', () {
    test('a bar and a rail differ in exactly four figures', () {
      final bar = NavigationStyle3d.of(_theme, NavigationVariant3d.bar);
      final rail = NavigationStyle3d.of(_theme, NavigationVariant3d.rail);
      expect(bar.container, _theme.colorScheme.surfaceContainer);
      expect(rail.container, _theme.colorScheme.surface);
      expect(bar.elevation, _theme.elevation.level2);
      expect(rail.elevation, _theme.elevation.level0);
      expect(bar.indicatorSize, NavigationStyle3d.barIndicatorSize);
      expect(rail.indicatorSize, NavigationStyle3d.railIndicatorSize);
      // And in nothing else.
      expect(
        rail.copyWith(
          container: bar.container,
          elevation: bar.elevation,
          indicatorSize: bar.indicatorSize,
          extent: bar.extent,
        ),
        bar,
      );
    });

    test('the content colours are the selection, not a wash', () {
      final style = NavigationStyle3d.of(_theme, NavigationVariant3d.bar);
      expect(style.contentColor, _theme.colorScheme.onSurfaceVariant);
      expect(
        style.selectedContentColor,
        _theme.colorScheme.onSecondaryContainer,
      );
      expect(style.indicatorColor, _theme.colorScheme.secondaryContainer);
    });

    test('copyWith replaces one thing and equality is by value', () {
      final style = NavigationStyle3d.of(_theme, NavigationVariant3d.bar);
      expect(style, NavigationStyle3d.of(_theme, NavigationVariant3d.bar));
      expect(style.copyWith(container: const Color(0xFF00FF00)), isNot(style));
    });
  });
}
