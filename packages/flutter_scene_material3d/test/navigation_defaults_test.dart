// The navigation figures, against Flutter's own.
//
// Two of the three grades phase 4 named turn up here. The bar's height and
// the rail's width are private as data and public as a *fact about a
// laid-out widget*, so the test pumps a real one and reads `tester.getSize`.
// The indicator's size is better than that: `NavigationIndicator`'s width,
// height and radius are ordinary public constructor defaults, so they can be
// read outright.

import 'package:flutter/material.dart' as m;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show BorderRadius3d;
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

const Theme3dData _theme = Theme3dData.light;

const List<m.NavigationDestination> _destinations = <m.NavigationDestination>[
  m.NavigationDestination(icon: m.Icon(m.Icons.inbox), label: 'Inbox'),
  m.NavigationDestination(icon: m.Icon(m.Icons.send), label: 'Sent'),
];

const List<m.NavigationRailDestination> _railDestinations =
    <m.NavigationRailDestination>[
      m.NavigationRailDestination(
        icon: m.Icon(m.Icons.inbox),
        label: m.Text('Inbox'),
      ),
      m.NavigationRailDestination(
        icon: m.Icon(m.Icons.send),
        label: m.Text('Sent'),
      ),
    ];

void main() {
  group('read off a laid-out Flutter widget', () {
    testWidgets('a navigation bar is 80dp tall', (tester) async {
      await tester.pumpWidget(
        m.MaterialApp(
          theme: m.ThemeData(useMaterial3: true),
          home: m.Scaffold(
            bottomNavigationBar: m.NavigationBar(destinations: _destinations),
          ),
        ),
      );
      final height = tester.getSize(find.byType(m.NavigationBar)).height;
      expect(height, NavigationStyle3d.barExtent);
      expect(
        NavigationStyle3d.of(_theme, NavigationVariant3d.bar).extent,
        height,
      );
    });

    testWidgets('a navigation rail is 80dp wide', (tester) async {
      await tester.pumpWidget(
        m.MaterialApp(
          theme: m.ThemeData(useMaterial3: true),
          home: m.Scaffold(
            body: m.Row(
              children: <m.Widget>[
                m.NavigationRail(
                  destinations: _railDestinations,
                  selectedIndex: 0,
                ),
                const m.Expanded(child: m.SizedBox.shrink()),
              ],
            ),
          ),
        ),
      );
      final width = tester.getSize(find.byType(m.NavigationRail)).width;
      expect(width, NavigationStyle3d.railExtent);
      expect(
        NavigationStyle3d.of(_theme, NavigationVariant3d.rail).extent,
        width,
      );
    });
  });

  group('read straight off a public API', () {
    test('the bar\'s pill is NavigationIndicator\'s own default size', () {
      // A genuine drift alarm rather than a transcription: these are the
      // defaults on a public constructor.
      const indicator = m.NavigationIndicator(
        animation: m.AlwaysStoppedAnimation<double>(1),
      );
      expect(NavigationStyle3d.barIndicatorSize.width, indicator.width);
      expect(NavigationStyle3d.barIndicatorSize.height, indicator.height);
      // And its radius is 16 on a 32-tall pill, which is a stadium — which
      // is what `ShapeScale3d.full` is here.
      expect(
        indicator.borderRadius,
        const m.BorderRadius.all(m.Radius.circular(16)),
      );
      expect(
        NavigationStyle3d.of(_theme, NavigationVariant3d.bar).indicatorShape,
        _theme.shape.full,
      );
      expect(_theme.shape.full, isA<BorderRadius3d>());
    });
  });

  group('transcriptions, stated as such', () {
    test('the rail\'s pill is 56 by 32', () {
      // Flutter's `_kCircularIndicatorDiameter` and `_kIndicatorHeight`, both
      // private file-level constants in `navigation_rail.dart`. Transcribed.
      expect(NavigationStyle3d.railIndicatorSize.width, 56.0);
      expect(NavigationStyle3d.railIndicatorSize.height, 32.0);
    });

    test('a bar is at elevation level 2 and a rail is flat', () {
      // `_NavigationBarDefaultsM3.elevation` is 3.0 and
      // `_NavigationRailDefaultsM3.elevation` is 0.0, both private. Three
      // logical pixels is `Elevation3d.level2`, which is where the figure
      // goes rather than as a literal.
      expect(_theme.elevation.level2, 3.0);
      expect(
        NavigationStyle3d.of(_theme, NavigationVariant3d.bar).elevation,
        3.0,
      );
      expect(
        NavigationStyle3d.of(_theme, NavigationVariant3d.rail).elevation,
        0.0,
      );
    });
  });

  group('the colour roles, which are the same table', () {
    test('a bar is surfaceContainer and a rail is surface', () {
      expect(
        NavigationStyle3d.of(_theme, NavigationVariant3d.bar).container,
        _theme.colorScheme.surfaceContainer,
      );
      expect(
        NavigationStyle3d.of(_theme, NavigationVariant3d.rail).container,
        _theme.colorScheme.surface,
      );
    });

    test('and both indicate with secondaryContainer', () {
      for (final variant in NavigationVariant3d.values) {
        expect(
          NavigationStyle3d.of(_theme, variant).indicatorColor,
          _theme.colorScheme.secondaryContainer,
        );
      }
    });
  });
}
