// The divider: three figures that are not the same figure, the one that has
// to be non-zero, and what a rule announces.

import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'surfaces_support.dart';

/// The `BorderSide` a real Flutter `Divider` would draw.
///
/// `Divider.createBorderSide(context)` is **public**, which makes this the
/// strongest lane phase 3's standard asks for: the colour role and the width
/// come from Flutter's own resolution rather than from a transcription, so
/// the suite is a drift alarm.
Future<material.BorderSide> flutterDividerSide(WidgetTester tester) async {
  late material.BorderSide side;
  await tester.pumpWidget(
    material.MaterialApp(
      theme: material.ThemeData(brightness: material.Brightness.light),
      home: material.Builder(
        builder: (context) {
          side = material.Divider.createBorderSide(context);
          return const material.Scaffold(body: material.Divider());
        },
      ),
    ),
  );
  return side;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const theme = Theme3dData.light;

  group('the figures, against Flutter\'s own', () {
    testWidgets('the rule is 1dp of outlineVariant', (tester) async {
      final side = await flutterDividerSide(tester);
      expect(Divider3d.defaultThickness, side.width);
      // `toARGB32` rather than `==`, for the reason phase 3 found: a colour
      // built from a double and one built from a byte are the same colour
      // everywhere it matters and are not `==`.
      expect(
        theme.colorScheme.outlineVariant.toARGB32(),
        side.color.toARGB32(),
      );
    });

    testWidgets('and it takes 16dp of space', (tester) async {
      // `_DividerDefaultsM3.space` is private, so this figure is a
      // **transcription** rather than a check, and saying so is the point of
      // the test. What is reachable is the height a real `Divider` lays out
      // at, which is the same number by construction.
      await tester.pumpWidget(
        const material.MaterialApp(
          home: material.Scaffold(body: material.Divider()),
        ),
      );
      expect(
        tester.getSize(find.byType(material.Divider)).height,
        Divider3d.defaultSpace,
      );
    });
  });

  group('the three figures are three different things', () {
    testWidgets('the space is 16dp and the rule inside it is 1dp', (
      tester,
    ) async {
      final it = await pumpComponent(tester, () => const Divider3d());
      // The outer box is the space; the panel is the rule.
      final space = outermostOf<SizedBox3d>(it.surface);
      expect(space.size.height, closeTo(Divider3d.defaultSpace / 100.0, 1e-9));
      expect(
        it.panel.size.height,
        closeTo(Divider3d.defaultThickness / 100.0, 1e-9),
        reason: 'the rule is a sliver in the middle of the space',
      );
      expect(it.decoration.color, theme.colorScheme.outlineVariant);
    });

    testWidgets('the depth is a third dial and it is not zero', (tester) async {
      // The decision this component exists to make. A rule looks flat, so a
      // zero-depth slab is the tempting answer — and it is wrong, because a
      // `Material3d` aligns its child to its **front face**, so a divider
      // drawn on a card would be exactly coplanar with the card and z-fight
      // it. A `Thickness3d.thin` slab stands its own half-thickness proud
      // instead.
      final it = await pumpComponent(tester, () => const Divider3d());
      expect(it.panel.size.depth, closeTo(theme.thickness.thin / 100.0, 1e-9));
      expect(it.panel.size.depth, greaterThan(0.0));
      expect(
        it.decoration.bevel,
        0.0,
        reason:
            'at 1dp a quarter-thickness bevel is a quarter of a logical '
            'pixel: a shader term that shows nothing',
      );
    });

    testWidgets('a zero depth is expressible, for a caller who wants it', (
      tester,
    ) async {
      final it = await pumpComponent(tester, () => const Divider3d(depth: 0.0));
      expect(it.panel.size.depth, 0.0);
    });

    testWidgets('and the depth is separated from the surface it sits on', (
      tester,
    ) async {
      // The rule that comes with any thickness, applied to the thinnest thing
      // in the catalogue: a 1dp divider against a 4dp card is a mean of
      // 2.5dp, which the theme's 12dp step clears several times over.
      expect(
        theme.thickness.separates(theme.thickness.raised, theme.thickness.thin),
        isTrue,
      );
    });
  });

  group('the caller\'s dials', () {
    testWidgets('an indent insets the rule and not the space', (tester) async {
      final it = await pumpComponent(
        tester,
        () => const Divider3d(indent: 16.0, endIndent: 32.0),
      );
      final space = outermostOf<SizedBox3d>(it.surface);
      expect(space.size.width, closeTo(4.0, 1e-9));
      expect(
        it.panel.size.width,
        closeTo(4.0 - 0.16 - 0.32, 1e-9),
        reason: 'the rule is inset by 16dp and 32dp; the space is not',
      );
    });

    testWidgets('an explicit thickness and colour reach the panel', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => Divider3d(
          space: 24.0,
          thickness: 4.0,
          color: theme.colorScheme.primary,
        ),
      );
      expect(it.panel.size.height, closeTo(0.04, 1e-9));
      expect(it.decoration.color, theme.colorScheme.primary);
      expect(
        outermostOf<SizedBox3d>(it.surface).size.height,
        closeTo(0.24, 1e-9),
      );
    });
  });

  group('what it announces', () {
    testWidgets('nothing, by default, and that is the right answer', (
      tester,
    ) async {
      // Flutter's own `Divider` publishes no semantics either. A reader that
      // announced "divider" between every pair of rows would be worse than
      // one that skipped it — so the honest default is silence, and the
      // component says so rather than leaving it to look like an omission.
      final it = await pumpComponent(tester, () => const Divider3d());
      expect(boxesOf<Semantics3d>(it.surface), isEmpty);
    });

    testWidgets('and a section break can name itself', (tester) async {
      final it = await pumpComponent(
        tester,
        () => const Divider3d(semanticLabel: 'End of unread'),
      );
      expect(it.semantics.properties.label, 'End of unread');
      expect(
        it.semantics.properties.button,
        isNull,
        reason: 'a rule is not a control',
      );
    });
  });

  group('in a column of tiles', () {
    testWidgets('it separates two rows and costs nothing to lay out', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => SceneColumn3d(
          mainAxisSize: MainAxisSize3d.min,
          children: <Widget>[
            ListTile3d.text(title: 'Inbox'),
            const Divider3d(),
            ListTile3d.text(title: 'Archive'),
          ],
        ),
      );
      // Three panels: two tiles and a rule. The rule is between them.
      final panels = it.panels;
      expect(panels.length, 3);
      expect(panels[1].size.height, closeTo(0.01, 1e-9));
      // Summed up the parent chain: a box's own `offset` is relative to its
      // parent, and these three sit at different depths in the tree.
      final ys = <double>[for (final p in panels) offsetInSurface(p).y];
      expect(
        ys[0],
        lessThan(ys[1]),
        reason: 'the rule is under the first tile',
      );
      expect(ys[1], lessThan(ys[2]));
    });
  });
}
