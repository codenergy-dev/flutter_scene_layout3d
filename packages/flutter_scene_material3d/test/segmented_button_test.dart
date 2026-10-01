// SegmentedButton3d: equal segments in one outline, the fill carved to the
// stadium where Flutter clips it, and a press that lands on the segment it
// was aimed at even in the margin above it.

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart'
    show StatefulBuilder, TextDirection, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/testing.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'surfaces_support.dart';

const Theme3dData _theme = Theme3dData.light;
const double _dp = 0.01;

const List<ButtonSegment3d<int>> _segments = <ButtonSegment3d<int>>[
  ButtonSegment3d<int>(value: 0, label: 'Day'),
  ButtonSegment3d<int>(value: 1, label: 'Week'),
  ButtonSegment3d<int>(value: 2, label: 'Month'),
];

/// The segment announcing [label].
Semantics3d _segment(Layout3dSurface surface, String label) =>
    boxesOf<Semantics3d>(
      surface,
    ).firstWhere((box) => box.properties.label == label);

/// The panel a segment draws: the one decorated box under its announcement.
DecoratedBox3d _panelOf(Layout3dSurface surface, String label) {
  final found = <DecoratedBox3d>[];
  void walk(Layout3d box) {
    if (box is DecoratedBox3d) found.add(box);
    box.visitChildren(walk);
  }

  walk(_segment(surface, label));
  return found.first;
}

BoxDecoration3d _decorationOf(Layout3dSurface surface, String label) =>
    _panelOf(surface, label).decoration as BoxDecoration3d;

/// The one panel with a border: the outline in front of the segments.
DecoratedBox3d _outline(Layout3dSurface surface) => boxesOf<DecoratedBox3d>(
  surface,
).firstWhere((box) => !(box.decoration as BoxDecoration3d).border.isNone);

/// A button holding its own selection, so a test can press it and read back
/// both what it was told and what it shows.
Widget _holding(
  Set<int> selection,
  List<Set<int>> reported, {
  bool multi = false,
  bool empty = false,
}) => StatefulBuilder(
  builder: (context, setState) => SegmentedButton3d<int>(
    segments: _segments,
    selected: selection,
    multiSelectionEnabled: multi,
    emptySelectionAllowed: empty,
    onSelectionChanged: (next) {
      reported.add(next);
      setState(() {
        selection
          ..clear()
          ..addAll(next);
      });
    },
  ),
);

/// Whether [box] is [ancestor] or somewhere under it.
bool isAtOrBelow(Layout3d box, Layout3d ancestor) {
  for (Layout3d? walk = box; walk != null; walk = walk.parent) {
    if (identical(walk, ancestor)) return true;
  }
  return false;
}

Future<void> _press(PumpedSurface pumped, Offset3d at) async {
  pumped.pointer.down(rayAt(pumped.surface, at));
  pumped.pointer.up();
}

void main() {
  testWidgets('lays out 48dp tall, with the outline the middle 40', (
    tester,
  ) async {
    final pumped = await pumpComponent(
      tester,
      () => SegmentedButton3d<int>(
        segments: _segments,
        selected: const <int>{1},
        onSelectionChanged: (_) {},
      ),
    );
    final style = SegmentedButtonStyle3d.of(_theme);
    final outline = _outline(pumped.surface);
    expect(outline.size.height, closeTo(style.height * _dp, 1e-9));
    for (final label in <String>['Day', 'Week', 'Month']) {
      expect(
        _panelOf(pumped.surface, label).size.height,
        closeTo(style.height * _dp, 1e-9),
      );
    }
    final slot = boxesOf<Flex3d>(pumped.surface).first;
    expect(slot.size.height, closeTo(style.tapTargetHeight * _dp, 1e-9));
  });

  testWidgets('every segment is as wide as the widest', (tester) async {
    final pumped = await pumpComponent(
      tester,
      () => SegmentedButton3d<int>(
        segments: _segments,
        selected: const <int>{0},
        onSelectionChanged: (_) {},
      ),
    );
    final widths = <double>[
      for (final label in <String>['Day', 'Week', 'Month'])
        _panelOf(pumped.surface, label).size.width,
    ];
    expect(widths[0], closeTo(widths[1], 1e-9));
    expect(widths[1], closeTo(widths[2], 1e-9));
    // The widest is 'Month' with its padding, and no wider: the button
    // shrink-wraps rather than filling the 4-unit surface.
    expect(_outline(pumped.surface).size.width, closeTo(widths[0] * 3, 1e-9));
    expect(_outline(pumped.surface).size.width, lessThan(4.0));
  });

  testWidgets('expandedInsets fills the width, the segments still equal', (
    tester,
  ) async {
    final pumped = await pumpComponent(
      tester,
      () => SceneSizedBox3d(
        width: 3,
        child: SegmentedButton3d<int>(
          segments: _segments,
          selected: const <int>{0},
          expandedInsets: const EdgeInsets3d.symmetric(horizontal: 10),
          onSelectionChanged: (_) {},
        ),
      ),
    );
    expect(_outline(pumped.surface).size.width, closeTo(3.0 - 0.2, 1e-9));
    expect(
      _panelOf(pumped.surface, 'Day').size.width,
      closeTo((3.0 - 0.2) / 3, 1e-9),
    );
  });

  testWidgets('the chosen segment is filled and wears a check', (tester) async {
    final pumped = await pumpComponent(
      tester,
      () => SegmentedButton3d<int>(
        segments: _segments,
        selected: const <int>{1},
        onSelectionChanged: (_) {},
      ),
    );
    final scheme = _theme.colorScheme;
    expect(
      _decorationOf(pumped.surface, 'Week').color,
      scheme.secondaryContainer,
    );
    expect(_decorationOf(pumped.surface, 'Day').color.a, 0.0);
    expect(_decorationOf(pumped.surface, 'Month').color.a, 0.0);
    // One glyph in the whole button, and it is the check.
    final glyphs = boxesOf<Text3d>(pumped.surface)
        .where(
          (text) =>
              text.data ==
              String.fromCharCode(
                SegmentedButton3d.defaultSelectedIcon.codePoint,
              ),
        )
        .toList();
    expect(glyphs, hasLength(1));
    expect(
      isAtOrBelow(glyphs.single, _segment(pumped.surface, 'Week')),
      isTrue,
    );
  });

  testWidgets('the ends are carved to the stadium and the inside is square', (
    tester,
  ) async {
    for (final direction in TextDirection.values) {
      final pumped = await pumpComponent(
        tester,
        () => SegmentedButton3d<int>(
          segments: _segments,
          selected: const <int>{0},
          onSelectionChanged: (_) {},
        ),
        textDirection: direction,
      );
      final outer = _theme.shape.full;
      final first = _decorationOf(pumped.surface, 'Day').borderRadius;
      final middle = _decorationOf(pumped.surface, 'Week').borderRadius;
      final last = _decorationOf(pumped.surface, 'Month').borderRadius;
      expect(middle.isZero, isTrue, reason: '$direction');
      if (direction == TextDirection.ltr) {
        expect(first, BorderRadius3d.horizontal(left: outer.topLeft));
        expect(last, BorderRadius3d.horizontal(right: outer.topRight));
        // And the first segment is the one at the left.
        expect(
          _panelOf(pumped.surface, 'Day').drawnOffsetInSurface.x,
          lessThan(_panelOf(pumped.surface, 'Month').drawnOffsetInSurface.x),
        );
      } else {
        expect(first, BorderRadius3d.horizontal(right: outer.topRight));
        expect(last, BorderRadius3d.horizontal(left: outer.topLeft));
        expect(
          _panelOf(pumped.surface, 'Day').drawnOffsetInSurface.x,
          greaterThan(_panelOf(pumped.surface, 'Month').drawnOffsetInSurface.x),
        );
      }
    }
  });

  testWidgets('a lone segment is the whole stadium', (tester) async {
    final pumped = await pumpComponent(
      tester,
      () => SegmentedButton3d<int>(
        segments: const <ButtonSegment3d<int>>[
          ButtonSegment3d<int>(value: 0, label: 'Only'),
        ],
        selected: const <int>{0},
        onSelectionChanged: (_) {},
      ),
    );
    expect(
      _decorationOf(pumped.surface, 'Only').borderRadius,
      _theme.shape.full,
    );
  });

  testWidgets('the outline stands in front of the segments and takes no ray', (
    tester,
  ) async {
    final pumped = await pumpComponent(
      tester,
      () => SegmentedButton3d<int>(
        segments: _segments,
        selected: const <int>{0},
        onSelectionChanged: (_) {},
      ),
    );
    final style = SegmentedButtonStyle3d.of(_theme);
    final outline = _outline(pumped.surface);
    final decoration = outline.decoration as BoxDecoration3d;
    expect(decoration.color.a, 0.0);
    expect(decoration.border.width, style.outlineWidth);
    expect(decoration.border.color, _theme.colorScheme.outline);
    expect(decoration.borderRadius, style.shape);
    final stack = boxesOf<Stack3d>(pumped.surface).first;
    expect(stack.depthStep, closeTo(style.outlineDepthStep * _dp, 1e-9));
    expect(
      _theme.thickness.separates(
        style.thickness,
        style.outlineThickness,
        step: style.outlineDepthStep,
      ),
      isTrue,
    );
    expect(
      boxesOf<IgnorePointer3d>(
        pumped.surface,
      ).any((box) => isAtOrBelow(outline, box)),
      isTrue,
    );
    // Two rules, between the three segments, in the outline's colour.
    final rules = boxesOf<DecoratedBox3d>(pumped.surface)
        .where(
          (box) =>
              isAtOrBelow(box, outline) &&
              !identical(box, outline) &&
              (box.decoration as BoxDecoration3d).color ==
                  _theme.colorScheme.outline,
        )
        .toList();
    expect(rules, hasLength(2));
    for (final rule in rules) {
      expect(rule.size.width, closeTo(style.outlineWidth * _dp, 1e-9));
    }
  });

  testWidgets('a press chooses its segment alone', (tester) async {
    final selection = <int>{1};
    final reported = <Set<int>>[];
    final pumped = await pumpComponent(
      tester,
      () => _holding(selection, reported),
    );
    final day = _panelOf(pumped.surface, 'Day');
    await _press(pumped, day.drawnOffsetInSurface + day.size.center);
    await tester.pumpAndSettle();
    expect(reported, <Set<int>>[
      <int>{0},
    ]);
    expect(_segment(pumped.surface, 'Day').properties.selected, isTrue);
    expect(_segment(pumped.surface, 'Week').properties.selected, isFalse);

    // Pressing the chosen one again changes nothing, and says nothing.
    await _press(pumped, day.drawnOffsetInSurface + day.size.center);
    await tester.pumpAndSettle();
    expect(reported, hasLength(1));
  });

  testWidgets('a press 4dp above a segment chooses that segment', (
    tester,
  ) async {
    // The reason the button lays out 48dp tall: a reach that arrived at the
    // whole control's centre would choose the middle segment.
    final selection = <int>{1};
    final reported = <Set<int>>[];
    final pumped = await pumpComponent(
      tester,
      () => _holding(selection, reported),
    );
    final day = _panelOf(pumped.surface, 'Day');
    final above =
        day.drawnOffsetInSurface + Offset3d(day.size.width / 2, -0.03, 0);
    await _press(pumped, above);
    await tester.pumpAndSettle();
    expect(reported, <Set<int>>[
      <int>{0},
    ]);

    final month = _panelOf(pumped.surface, 'Month');
    final below =
        month.drawnOffsetInSurface +
        Offset3d(month.size.width / 2, month.size.height + 0.03, 0);
    await _press(pumped, below);
    await tester.pumpAndSettle();
    expect(reported.last, <int>{2});
  });

  testWidgets('with multiple selection a press toggles, down to empty only '
      'when allowed', (tester) async {
    final button = SegmentedButton3d<int>(
      segments: _segments,
      selected: const <int>{0, 2},
      multiSelectionEnabled: true,
    );
    expect(button.selectionAfterPressing(1), <int>{0, 1, 2});
    expect(button.selectionAfterPressing(2), <int>{0});
    final last = SegmentedButton3d<int>(
      segments: _segments,
      selected: const <int>{2},
      multiSelectionEnabled: true,
    );
    expect(last.selectionAfterPressing(2), isNull);
    final allowed = SegmentedButton3d<int>(
      segments: _segments,
      selected: const <int>{2},
      emptySelectionAllowed: true,
    );
    expect(allowed.selectionAfterPressing(2), <int>{});
    expect(allowed.selectionAfterPressing(0), <int>{0});

    final selection = <int>{0};
    final reported = <Set<int>>[];
    final pumped = await pumpComponent(
      tester,
      () => _holding(selection, reported, multi: true),
    );
    final month = _panelOf(pumped.surface, 'Month');
    await _press(pumped, month.drawnOffsetInSurface + month.size.center);
    await tester.pumpAndSettle();
    expect(reported.single, <int>{0, 2});
    expect(_segment(pumped.surface, 'Month').properties.selected, isTrue);
    expect(_segment(pumped.surface, 'Day').properties.selected, isTrue);
    // Several can be chosen, so the segments are not a mutually exclusive
    // group.
    expect(
      _segment(pumped.surface, 'Day').properties.inMutuallyExclusiveGroup,
      isNull,
    );
  });

  testWidgets('a disabled button has no fill and a faded outline', (
    tester,
  ) async {
    final pumped = await pumpComponent(
      tester,
      () =>
          const SegmentedButton3d<int>(segments: _segments, selected: <int>{1}),
    );
    final scheme = _theme.colorScheme;
    expect(_decorationOf(pumped.surface, 'Week').color.a, 0.0);
    expect(
      (_outline(pumped.surface).decoration as BoxDecoration3d).border.color,
      scheme.disabledContainer,
    );
    expect(_segment(pumped.surface, 'Week').properties.enabled, isFalse);
    expect(_segment(pumped.surface, 'Week').properties.selected, isTrue);
  });

  testWidgets('a disabled segment in an enabled button cannot be pressed', (
    tester,
  ) async {
    final reported = <Set<int>>[];
    final pumped = await pumpComponent(
      tester,
      () => SegmentedButton3d<int>(
        segments: const <ButtonSegment3d<int>>[
          ButtonSegment3d<int>(value: 0, label: 'Day'),
          ButtonSegment3d<int>(value: 1, label: 'Week', enabled: false),
        ],
        selected: const <int>{0},
        onSelectionChanged: reported.add,
      ),
    );
    expect(_segment(pumped.surface, 'Week').properties.enabled, isFalse);
    final week = _panelOf(pumped.surface, 'Week');
    await _press(pumped, week.drawnOffsetInSurface + week.size.center);
    await tester.pumpAndSettle();
    expect(reported, isEmpty);
  });

  testWidgets('an icon-only segment announces its tooltip', (tester) async {
    final pumped = await pumpComponent(
      tester,
      () => SegmentedButton3d<int>(
        segments: const <ButtonSegment3d<int>>[
          ButtonSegment3d<int>(
            value: 0,
            icon: Icons.light_mode,
            tooltip: 'Light',
          ),
          ButtonSegment3d<int>(
            value: 1,
            icon: Icons.dark_mode,
            semanticLabel: 'Dark',
          ),
        ],
        selected: const <int>{0},
        onSelectionChanged: (_) {},
      ),
    );
    expect(_segment(pumped.surface, 'Light').properties.button, isTrue);
    expect(_segment(pumped.surface, 'Dark').properties.selected, isFalse);
  });

  testWidgets('refuses a selection the flags do not allow', (tester) async {
    await pumpComponent(
      tester,
      () =>
          const SegmentedButton3d<int>(segments: _segments, selected: <int>{}),
    );
    expect(tester.takeException(), isA<AssertionError>());
    await pumpComponent(
      tester,
      () => const SegmentedButton3d<int>(
        segments: _segments,
        selected: <int>{0, 1},
      ),
    );
    expect(tester.takeException(), isA<AssertionError>());
  });

  testWidgets('a hover costs no layout at all', (tester) async {
    final pumped = await pumpComponent(
      tester,
      () => SegmentedButton3d<int>(
        segments: _segments,
        selected: const <int>{0},
        onSelectionChanged: (_) {},
      ),
    );
    final week = _panelOf(pumped.surface, 'Week');
    final builds = pumped.builds[0];
    pumped.pointer.hover(
      rayAt(pumped.surface, week.drawnOffsetInSurface + week.size.center),
    );
    await tester.pump();
    expect(pumped.builds[0], builds);
    expect(pumped.surface.needsFlush, isFalse);
    expect(
      _panelOf(pumped.surface, 'Week').stateLayer.opacity,
      _theme.stateLayer.hover,
      reason: 'the segment washed itself',
    );
  });
}
