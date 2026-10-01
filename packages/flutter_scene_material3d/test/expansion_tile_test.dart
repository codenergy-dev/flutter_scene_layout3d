// ExpansionTile3d: the two heights, the reveal and what a frame of it costs,
// the chevron's turn, the rules, and the children leaving the tree.

import 'dart:math' as math;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/widgets.dart' show TextDirection, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'support.dart';
import 'surfaces_support.dart';

const Theme3dData _theme = Theme3dData.light;
const double _dp = 0.01;

/// Where [box]'s origin is on the surface.
Offset3d _origin(Layout3d box) {
  var at = Offset3d.zero;
  Layout3d? walk = box;
  while (walk != null) {
    at += walk.offset;
    walk = walk.parent;
  }
  return at;
}

Semantics3d _header(Layout3dSurface surface) => boxesOf<Semantics3d>(
  surface,
).firstWhere((box) => box.properties.label == 'Advanced');

/// The tile at the top of a screen-shaped column, so its height is its own.
Widget _atTop(Widget tile) => SceneColumn3d(
  crossAxisAlignment: CrossAxisAlignment3d.stretch,
  children: <Widget>[
    tile,
    const SceneExpanded3d(child: SceneSizedBox3d()),
  ],
);

Widget _tile({
  bool initiallyExpanded = false,
  bool maintainState = false,
  ListTileControlAffinity3d? controlAffinity,
  void Function(bool expanded)? onExpansionChanged,
}) => _atTop(
  ExpansionTile3d.text(
    title: 'Advanced',
    initiallyExpanded: initiallyExpanded,
    maintainState: maintainState,
    controlAffinity: controlAffinity,
    onExpansionChanged: onExpansionChanged,
    children: <Widget>[
      ListTile3d.text(title: 'Sync'),
      ListTile3d.text(title: 'Storage'),
    ],
  ),
);

/// The whole tile: the column's first child.
Layout3d _tileBox(Layout3dSurface surface) {
  final column = outermostOf<Flex3d>(surface);
  return boxesOf<Layout3d>(
    surface,
  ).firstWhere((box) => identical(box.parent, column));
}

Future<void> _press(WidgetTester tester, PumpedSurface pumped) async {
  final header = _header(pumped.surface);
  final at = _origin(header);
  pumped.pointer.down(
    rayAt(
      pumped.surface,
      Offset3d(at.x + header.size.width / 2, at.y + header.size.height / 2, 0),
    ),
  );
  pumped.pointer.up();
}

bool _hasChildren(Layout3dSurface surface) =>
    boxesOf<Text3d>(surface).any((box) => box.data == 'Sync');

List<DecoratedBox3d> _rules(Layout3dSurface surface) =>
    boxesOf<DecoratedBox3d>(surface)
        .where(
          (box) =>
              (box.decoration as BoxDecoration3d).color ==
              _theme.colorScheme.outline,
        )
        .toList();

void main() {
  group('the tokens', () {
    test('are Flutter\'s', () {
      final style = ExpansionTileStyle3d.of(_theme);
      expect(style.textColor, _theme.colorScheme.onSurface);
      expect(style.collapsedTextColor, _theme.colorScheme.onSurface);
      expect(style.iconColor, _theme.colorScheme.primary);
      expect(style.collapsedIconColor, _theme.colorScheme.onSurfaceVariant);
      expect(style.dividerColor, _theme.colorScheme.outline);
      // `_kExpand`, which is `short4` exactly, on Flutter's `Curves.easeIn`.
      expect(style.duration, const Duration(milliseconds: 200));
      expect(style.curve, Curves.easeIn);
      expect(style.iconCurve, Curves.easeIn);
    });
  });

  group('closed and open', () {
    testWidgets('closed, it is a tile with room for its rules and no '
        'children', (tester) async {
      final pumped = await pumpComponent(tester, _tile, centred: false);
      expect(_tileBox(pumped.surface).size.height, closeTo(58 * _dp, 1e-9));
      expect(_hasChildren(pumped.surface), isFalse);
      expect(_rules(pumped.surface), isEmpty);
      expect(_header(pumped.surface).properties.expanded, isFalse);
    });

    testWidgets('pressed, it opens, with a rule above and below', (
      tester,
    ) async {
      final changes = <bool>[];
      final pumped = await pumpComponent(
        tester,
        () => _tile(onExpansionChanged: changes.add),
        centred: false,
      );
      await _press(tester, pumped);
      await tester.pumpAndSettle();
      expect(changes, <bool>[true]);
      expect(_hasChildren(pumped.surface), isTrue);
      expect(_rules(pumped.surface), hasLength(2));
      expect(_header(pumped.surface).properties.expanded, isTrue);
      // Two one-line tiles under a one-line header, and the two rules.
      expect(
        _tileBox(pumped.surface).size.height,
        closeTo((56 * 3 + 2) * _dp, 1e-9),
      );
    });

    testWidgets('pressed again, it closes and the children leave the tree', (
      tester,
    ) async {
      final changes = <bool>[];
      final pumped = await pumpComponent(
        tester,
        () => _tile(initiallyExpanded: true, onExpansionChanged: changes.add),
        centred: false,
      );
      expect(_hasChildren(pumped.surface), isTrue);
      await _press(tester, pumped);
      await tester.pumpAndSettle();
      expect(changes, <bool>[false]);
      expect(_hasChildren(pumped.surface), isFalse);
      expect(_tileBox(pumped.surface).size.height, closeTo(58 * _dp, 1e-9));
    });

    testWidgets('maintainState keeps them, offstage', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => _tile(initiallyExpanded: true, maintainState: true),
        centred: false,
      );
      await _press(tester, pumped);
      await tester.pumpAndSettle();
      expect(_hasChildren(pumped.surface), isTrue);
      expect(boxesOf<Offstage3d>(pumped.surface).single.offstage, isTrue);
      expect(_tileBox(pumped.surface).size.height, closeTo(58 * _dp, 1e-9));
    });
  });

  group('the reveal', () {
    testWidgets('part way, the children are revealed by the curve and the '
        'chevron has turned by it', (tester) async {
      final pumped = await pumpComponent(tester, _tile, centred: false);
      await _press(tester, pumped);
      await tester.pump();
      // A ticker's first tick is its own zero.
      await tester.pump(const Duration(milliseconds: 100));

      final eased = Curves.easeIn.transform(0.5);
      final reveal =
          namedBox(pumped.surface, ExpansionTile3d.revealName) as Align3d;
      expect(reveal.heightFactor, closeTo(eased, 1e-6));

      final chevron = namedBox(pumped.surface, ExpansionTile3d.chevronName);
      final turn = chevron.nodeTransform!;
      // A rotation about z by half a turn times the eased clock.
      expect(turn.entry(0, 0), closeTo(math.cos(math.pi * eased), 1e-6));
      expect(turn.entry(1, 0), closeTo(math.sin(math.pi * eased), 1e-6));
      // About the chevron's own centre: the centre is where it was.
      final centre = turn.transform3(
        Vector3(chevron.size.width / 2, chevron.size.height / 2, 0),
      );
      expect(centre.x, closeTo(chevron.size.width / 2, 1e-6));
      expect(centre.y, closeTo(chevron.size.height / 2, 1e-6));

      await tester.pumpAndSettle();
      expect(reveal.heightFactor, 1.0);
      expect(
        chevron.nodeTransform!.entry(0, 0),
        closeTo(-1.0, 1e-9),
        reason: 'half a turn, at rest',
      );
    });

    testWidgets('lays out on every frame, and builds and measures nothing', (
      tester,
    ) async {
      final pumped = await pumpComponent(tester, _tile, centred: false);
      await _press(tester, pumped);
      // The one build an opening costs: the press, which brings the children
      // into the tree.
      await tester.pump();

      final paragraphs = debugTextParagraphCount;
      final watched = await watchFrames(tester, pumped.surface, frames: 15);
      expect(watched.ticks, greaterThan(0));
      expect(watched.rebuilt, isEmpty, reason: 'widgets rebuilt');
      // Honestly: the tile grows, and only layout moves what is under it.
      expect(watched.laidOut, isNotEmpty);
      expect(
        debugTextParagraphCount,
        paragraphs,
        reason: 'a label was measured again',
      );
    });
  });

  group('the chevron', () {
    testWidgets('is at the trailing edge, which is the left in right to '
        'left', (tester) async {
      final ltr = await pumpComponent(tester, _tile, centred: false);
      final title = boxesOf<Text3d>(
        ltr.surface,
      ).singleWhere((box) => box.data == 'Advanced');
      expect(
        _origin(namedBox(ltr.surface, ExpansionTile3d.chevronName)).x,
        greaterThan(_origin(title).x),
      );

      final rtl = await pumpComponent(
        tester,
        _tile,
        centred: false,
        textDirection: TextDirection.rtl,
      );
      final rtlTitle = boxesOf<Text3d>(
        rtl.surface,
      ).singleWhere((box) => box.data == 'Advanced');
      expect(
        _origin(namedBox(rtl.surface, ExpansionTile3d.chevronName)).x,
        lessThan(_origin(rtlTitle).x),
      );
    });

    testWidgets('goes first when the affinity says leading', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => _tile(controlAffinity: ListTileControlAffinity3d.leading),
        centred: false,
      );
      final title = boxesOf<Text3d>(
        pumped.surface,
      ).singleWhere((box) => box.data == 'Advanced');
      expect(
        _origin(namedBox(pumped.surface, ExpansionTile3d.chevronName)).x,
        lessThan(_origin(title).x),
      );
    });

    testWidgets('is onSurfaceVariant closed and primary open', (tester) async {
      final pumped = await pumpComponent(tester, _tile, centred: false);
      Text3d glyph() => boxesOf<Text3d>(
        pumped.surface,
      ).firstWhere((box) => box.data.codeUnitAt(0) > 0xE000);
      expect(glyph().style.color, _theme.colorScheme.onSurfaceVariant);
      await _press(tester, pumped);
      await tester.pumpAndSettle();
      expect(glyph().style.color, _theme.colorScheme.primary);
    });
  });
}
