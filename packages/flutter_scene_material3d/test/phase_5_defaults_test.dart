// The figures phase 5's styles carry, against the Flutter widgets they stand
// in for.
//
// The grades `test/phase_4_defaults_test.dart` names. Where a figure is a
// fact about a laid-out Flutter widget — a height, a width, the colour on the
// `Material` it builds or the `DefaultTextStyle` over a label — it is read
// off one, so this is a drift alarm. Where it is only in Flutter's source, as
// a private constant or a painter's arithmetic, the test says *transcribed*
// and states the figure, which catches a change here and not one upstream.

import 'package:flutter/material.dart' as m;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show BorderRadius3d, EdgeInsets3d;
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

const Theme3dData _theme = Theme3dData.light;

/// Flutter's own light scheme, which `test/color_scheme_test.dart` pins
/// `ColorScheme3d.light` against role by role.
final m.ColorScheme _flutter = m.ThemeData(
  brightness: m.Brightness.light,
).colorScheme;

int _argb(m.Color color) => color.toARGB32();

Future<void> _pump(WidgetTester tester, m.Widget home) => tester.pumpWidget(
  m.MaterialApp(
    theme: m.ThemeData(brightness: m.Brightness.light),
    home: m.Scaffold(body: home),
  ),
);

/// The style in force over the text [label].
m.TextStyle _styleOver(WidgetTester tester, String label) => tester
    .widget<m.DefaultTextStyle>(
      find
          .ancestor(
            of: find.text(label),
            matching: find.byType(m.DefaultTextStyle),
          )
          .first,
    )
    .style;

void main() {
  group('SegmentedButton', () {
    m.Widget segmented({
      required List<m.ButtonSegment<int>> segments,
      required Set<int> selected,
      bool enabled = true,
      bool showSelectedIcon = true,
    }) => m.Center(
      child: m.SegmentedButton<int>(
        segments: segments,
        selected: selected,
        showSelectedIcon: showSelectedIcon,
        onSelectionChanged: enabled ? (_) {} : null,
      ),
    );

    Finder segmentOf(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(m.TextButton),
    );

    m.Material materialOf(WidgetTester tester, String label) =>
        tester.widget<m.Material>(
          find
              .descendant(
                of: segmentOf(label),
                matching: find.byType(m.Material),
              )
              .first,
        );

    testWidgets('lays out 48dp tall, every segment as wide as the widest', (
      tester,
    ) async {
      await _pump(
        tester,
        segmented(
          segments: const <m.ButtonSegment<int>>[
            m.ButtonSegment<int>(value: 0, label: m.Text('Day')),
            m.ButtonSegment<int>(value: 1, label: m.Text('Month')),
          ],
          selected: const <int>{0},
        ),
      );
      final style = SegmentedButtonStyle3d.of(_theme);
      final button = tester.getRect(find.byType(m.SegmentedButton<int>));
      expect(button.height, style.tapTargetHeight);
      final day = tester.getRect(segmentOf('Day'));
      final month = tester.getRect(segmentOf('Month'));
      expect(day.width, month.width);
      expect(button.width, day.width * 2);
    });

    testWidgets('a label is 12dp in from each side, and a segment with a '
        'check 12 before it and 16 after', (tester) async {
      final style = SegmentedButtonStyle3d.of(_theme);
      await _pump(
        tester,
        segmented(
          segments: const <m.ButtonSegment<int>>[
            m.ButtonSegment<int>(value: 0, label: m.Text('Calendar')),
          ],
          selected: const <int>{0},
        ),
      );
      final checked = tester.getRect(segmentOf('Calendar'));
      final label = tester.getRect(find.text('Calendar'));
      final iconPadding = style.iconPadding.resolve(m.TextDirection.ltr);
      expect(
        checked.width,
        iconPadding.left +
            style.iconSize +
            style.iconGap +
            label.width +
            iconPadding.right,
      );

      await _pump(
        tester,
        segmented(
          segments: const <m.ButtonSegment<int>>[
            m.ButtonSegment<int>(value: 0, label: m.Text('Calendar')),
          ],
          selected: const <int>{0},
          showSelectedIcon: false,
        ),
      );
      final plain = tester.getRect(segmentOf('Calendar'));
      final plainLabel = tester.getRect(find.text('Calendar'));
      final padding = style.padding.resolve(m.TextDirection.ltr);
      expect(plainLabel.center.dx, plain.center.dx);
      expect(plain.width, plainLabel.width + padding.left + padding.right);
    });

    testWidgets('and never narrower than a text button, 64dp', (tester) async {
      await _pump(
        tester,
        segmented(
          segments: const <m.ButtonSegment<int>>[
            m.ButtonSegment<int>(value: 0, label: m.Text('A')),
          ],
          selected: const <int>{0},
          showSelectedIcon: false,
        ),
      );
      expect(
        tester.getRect(segmentOf('A')).width,
        SegmentedButtonStyle3d.of(_theme).minimumSegmentWidth,
      );
    });

    testWidgets('the chosen fill and the colours of the labels', (
      tester,
    ) async {
      await _pump(
        tester,
        segmented(
          segments: const <m.ButtonSegment<int>>[
            m.ButtonSegment<int>(value: 0, label: m.Text('Day')),
            m.ButtonSegment<int>(value: 1, label: m.Text('Week')),
          ],
          selected: const <int>{1},
        ),
      );
      final style = SegmentedButtonStyle3d.of(_theme);
      expect(
        _argb(materialOf(tester, 'Week').color!),
        _argb(_flutter.secondaryContainer),
      );
      expect(
        _argb(style.selectedContainer),
        _argb(_flutter.secondaryContainer),
      );
      expect(materialOf(tester, 'Day').color!.a, 0.0);
      expect(
        _argb(_styleOver(tester, 'Week').color!),
        _argb(_flutter.onSecondaryContainer),
      );
      expect(
        _argb(style.selectedContent),
        _argb(_flutter.onSecondaryContainer),
      );
      expect(
        _argb(_styleOver(tester, 'Day').color!),
        _argb(_flutter.onSurface),
      );
      expect(_argb(style.content), _argb(_flutter.onSurface));
      expect(
        _styleOver(tester, 'Day').fontSize,
        _theme.textStyle(style.labelStyle).fontSize,
      );
    });

    testWidgets('disabled: no fill even when chosen, and a faded label', (
      tester,
    ) async {
      await _pump(
        tester,
        segmented(
          segments: const <m.ButtonSegment<int>>[
            m.ButtonSegment<int>(value: 0, label: m.Text('Day')),
          ],
          selected: const <int>{0},
          enabled: false,
        ),
      );
      final style = SegmentedButtonStyle3d.of(_theme);
      expect(materialOf(tester, 'Day').color!.a, 0.0);
      expect(
        _argb(_styleOver(tester, 'Day').color!),
        _argb(_flutter.onSurface.withValues(alpha: 0.38)),
      );
      expect(
        _argb(style.disabledContent),
        _argb(_theme.colorScheme.disabledContent),
      );
    });

    test('the outline, transcribed', () {
      // `_RenderSegmentedButton` paints the border, and its side is a private
      // resolution: `outline`, and `onSurface` at 12% when disabled, 1dp, a
      // stadium.
      final style = SegmentedButtonStyle3d.of(_theme);
      expect(style.outline, _theme.colorScheme.outline);
      expect(style.disabledOutline, _theme.colorScheme.disabledContainer);
      expect(style.outlineWidth, 1.0);
      expect(style.shape, _theme.shape.full);
      expect(style.height, 40.0);
    });
  });

  group('TabBar', () {
    Future<void> bars(WidgetTester tester, {int index = 1}) => _pump(
      tester,
      m.DefaultTabController(
        length: 3,
        initialIndex: index,
        child: const m.Column(
          children: <m.Widget>[
            m.TabBar(
              tabs: <m.Widget>[
                m.Tab(text: 'Day'),
                m.Tab(text: 'Week'),
                m.Tab(text: 'Month'),
              ],
            ),
            m.TabBar.secondary(
              tabs: <m.Widget>[
                m.Tab(text: 'One'),
                m.Tab(text: 'Two'),
                m.Tab(text: 'Three'),
              ],
            ),
            m.TabBar(
              tabs: <m.Widget>[
                m.Tab(text: 'Flights', icon: m.Icon(m.Icons.flight)),
                m.Tab(text: 'Trips'),
                m.Tab(text: 'Explore'),
              ],
            ),
          ],
        ),
      ),
    );

    testWidgets('48dp tall, 74 with an icon and a label', (tester) async {
      await bars(tester);
      final style = TabBarStyle3d.of(_theme, TabBarVariant3d.primary);
      final heights = find
          .byType(m.TabBar)
          .evaluate()
          .map(
            (element) => tester.getSize(find.byWidget(element.widget)).height,
          )
          .toList();
      expect(heights, <double>[
        style.tabHeight + style.reservedHeight,
        style.tabHeight + style.reservedHeight,
        style.textAndIconTabHeight + style.reservedHeight,
      ]);
      // A tab is as wide as its label and centred in its share of the bar.
      final week = tester.getRect(find.text('Week'));
      final tab = tester.getRect(
        find.ancestor(of: find.text('Week'), matching: find.byType(m.Tab)),
      );
      expect(tab.width, week.width);
      expect(tab.height, style.tabHeight);
    });

    testWidgets('the labels\' colours and their type', (tester) async {
      await bars(tester);
      final primary = TabBarStyle3d.of(_theme, TabBarVariant3d.primary);
      final secondary = TabBarStyle3d.of(_theme, TabBarVariant3d.secondary);
      expect(_argb(_styleOver(tester, 'Week').color!), _argb(_flutter.primary));
      expect(_argb(primary.labelColor), _argb(_flutter.primary));
      expect(
        _argb(_styleOver(tester, 'Day').color!),
        _argb(_flutter.onSurfaceVariant),
      );
      expect(
        _argb(primary.unselectedLabelColor),
        _argb(_flutter.onSurfaceVariant),
      );
      expect(
        _argb(_styleOver(tester, 'Two').color!),
        _argb(_flutter.onSurface),
      );
      expect(_argb(secondary.labelColor), _argb(_flutter.onSurface));
      expect(
        _styleOver(tester, 'Week').fontSize,
        _theme.textStyle(primary.labelStyle).fontSize,
      );
    });

    test('the indicator and the rule, transcribed', () {
      // `_TabsPrimaryDefaultsM3.indicatorWeight` and `_getIndicator`: 3dp and
      // as wide as the label with its top corners rounded by its weight on a
      // primary bar, 2dp, as wide as the tab and square on a secondary one;
      // an `outlineVariant` rule 1dp tall, `dividerColor` and
      // `dividerHeight`. The indicator is painted, so nothing of it can be
      // read off a laid-out widget.
      final primary = TabBarStyle3d.of(_theme, TabBarVariant3d.primary);
      final secondary = TabBarStyle3d.of(_theme, TabBarVariant3d.secondary);
      expect(primary.indicatorWeight, 3.0);
      expect(primary.indicatorSize, TabBarIndicatorSize3d.label);
      expect(primary.indicatorShape, const BorderRadius3d.vertical(top: 3.0));
      expect(primary.indicatorAnimation, TabIndicatorAnimation3d.elastic);
      expect(secondary.indicatorWeight, 2.0);
      expect(secondary.indicatorSize, TabBarIndicatorSize3d.tab);
      expect(secondary.indicatorShape, BorderRadius3d.zero);
      expect(secondary.indicatorAnimation, TabIndicatorAnimation3d.linear);
      expect(primary.indicatorColor, _theme.colorScheme.primary);
      expect(primary.dividerColor, _theme.colorScheme.outlineVariant);
      expect(primary.dividerHeight, 1.0);
      expect(
        primary.labelPadding,
        EdgeInsets3d.symmetric(horizontal: m.kTabLabelPadding.left),
      );
      expect(m.kTabLabelPadding.left, m.kTabLabelPadding.right);
    });
  });
}
