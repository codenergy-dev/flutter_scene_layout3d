// The list tile: the heights, what a density does to them, the slots, the
// type roles, what it announces, and a list of real tiles in a real
// scrolling view.
//
// This is the component that meets the scrolling machinery, so the last group
// puts tiles in a `SceneListView3d` and measures them there rather than in a
// centred box — because that is where a real screen pays for them.

import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'surfaces_support.dart';

/// The height a real Flutter [material.ListTile] lays out at.
///
/// The strongest check available for these figures. `_LisTileDefaultsM3` is
/// private and `ListTileTheme.of(context)` returns an application's
/// overrides rather than the resolved defaults — but the *height* is a fact
/// about a laid-out widget, and `tester.getSize` reads it. So the table below
/// is Flutter's own arithmetic rather than a second transcription of the
/// specification.
Future<double> flutterTileHeight(
  WidgetTester tester, {
  bool subtitle = false,
  bool isThreeLine = false,
  bool dense = false,
  material.VisualDensity density = material.VisualDensity.standard,
}) async {
  await tester.pumpWidget(
    material.MaterialApp(
      theme: material.ThemeData(
        brightness: material.Brightness.light,
        visualDensity: density,
      ),
      home: material.Scaffold(
        body: material.Column(
          children: <Widget>[
            material.ListTile(
              dense: dense,
              isThreeLine: isThreeLine,
              title: const material.Text('Inbox'),
              subtitle: subtitle ? const material.Text('12 unread') : null,
            ),
          ],
        ),
      ),
    ),
  );
  return tester.getSize(find.byType(material.ListTile)).height;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const theme = Theme3dData.light;

  group('the heights, against Flutter\'s own', () {
    testWidgets('one line is 56dp', (tester) async {
      expect(await flutterTileHeight(tester), ListTile3d.oneLineHeight);
    });

    testWidgets('two lines are 72dp', (tester) async {
      expect(
        await flutterTileHeight(tester, subtitle: true),
        ListTile3d.twoLineHeight,
      );
    });

    testWidgets('three lines are 88dp', (tester) async {
      expect(
        await flutterTileHeight(tester, subtitle: true, isThreeLine: true),
        ListTile3d.threeLineHeight,
      );
    });

    testWidgets('and dense is 48, 64 and 76', (tester) async {
      expect(
        await flutterTileHeight(tester, dense: true),
        ListTile3d.denseOneLineHeight,
      );
      expect(
        await flutterTileHeight(tester, subtitle: true, dense: true),
        ListTile3d.denseTwoLineHeight,
      );
      expect(
        await flutterTileHeight(
          tester,
          subtitle: true,
          isThreeLine: true,
          dense: true,
        ),
        ListTile3d.denseThreeLineHeight,
      );
    });

    testWidgets('a compact density takes 8dp off, exactly as Flutter\'s does', (
      tester,
    ) async {
      // Two dials, one arithmetic. Flutter's `VisualDensity.compact` is
      // `(-2, -2)` and its `baseSizeAdjustment` is four logical pixels a
      // step, so a 56dp tile becomes 48dp. `VisualDensity3d.compact` is the
      // same pair of numbers, and `Theme3dData.effectiveConstraints` applies
      // it through the metrics' own conversion.
      final height = await flutterTileHeight(
        tester,
        density: material.VisualDensity.compact,
      );
      expect(height, ListTile3d.oneLineHeight - 8.0);
    });
  });

  group('the tile this package lays out', () {
    for (final (name, tile, expected) in <(String, ListTile3d, double)>[
      ('one line', ListTile3d.text(title: 'Inbox'), ListTile3d.oneLineHeight),
      (
        'two lines',
        ListTile3d.text(title: 'Inbox', subtitle: '12 unread'),
        ListTile3d.twoLineHeight,
      ),
      (
        'three lines',
        ListTile3d.text(
          title: 'Inbox',
          subtitle: '12 unread',
          isThreeLine: true,
        ),
        ListTile3d.threeLineHeight,
      ),
      (
        'one dense line',
        ListTile3d.text(title: 'Inbox', dense: true),
        ListTile3d.denseOneLineHeight,
      ),
    ]) {
      testWidgets('$name is ${expected}dp tall', (tester) async {
        final it = await pumpComponent(tester, () => tile);
        expect(it.panel.size.height, closeTo(expected / 100.0, 1e-9));
      });
    }

    testWidgets('the theme\'s density moves it, and the theme is the winner', (
      tester,
    ) async {
      // `Layout3dMetrics` carries a density too. The tile reads the theme's,
      // through `Theme3dData.effectiveConstraints`, which is the stated
      // precedence — so a surface whose metrics says one thing and a theme
      // that says another produce the theme's answer, once.
      final it = await pumpComponent(
        tester,
        () => ListTile3d.text(title: 'Inbox'),
        theme: theme.copyWith(density: VisualDensity3d.compact),
      );
      expect(
        it.panel.size.height,
        closeTo((ListTile3d.oneLineHeight - 8.0) / 100.0, 1e-9),
        reason: 'two steps of four logical pixels off a 56dp tile',
      );
    });

    testWidgets('the height is a minimum, not a fixed extent', (tester) async {
      // A tile whose text wraps is taller than the table says, exactly as
      // Flutter's is. The constraint is `minHeight`, and this is what says so.
      final it = await pumpComponent(
        tester,
        () => ListTile3d.text(
          title: 'A title long enough to break over several lines',
        ),
        size: const Size3d(1.2, 6, 0.5),
      );
      expect(
        it.panel.size.height,
        greaterThan(ListTile3d.oneLineHeight / 100.0),
      );
    });

    testWidgets('it is a 2dp slab that fills the width it is given', (
      tester,
    ) async {
      final it = await pumpComponent(tester, () => ListTile3d.text(title: 'x'));
      expect(it.panel.size.width, closeTo(4.0, 1e-9));
      expect(
        it.panel.size.depth,
        closeTo(theme.thickness.standard / 100.0, 1e-9),
      );
      expect(
        it.decoration.color.a,
        0.0,
        reason:
            'a tile is transparent by default and sits on what is behind '
            'it — the slab is only what the wash is drawn on',
      );
    });
  });

  group('the slots and the type roles', () {
    testWidgets('the title is bodyLarge on onSurface', (tester) async {
      final it = await pumpComponent(
        tester,
        () => ListTile3d.text(title: 'Inbox', subtitle: '12 unread'),
      );
      final labels = boxesOf<Text3d>(it.surface);
      expect(labels.length, 2);
      expect(labels[0].data, 'Inbox');
      expect(labels[0].style.color, theme.colorScheme.onSurface);
      expect(labels[0].style.fontSize, theme.typography.bodyLarge.fontSize);
    });

    testWidgets('the subtitle is bodyMedium on onSurfaceVariant', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => ListTile3d.text(title: 'Inbox', subtitle: '12 unread'),
      );
      final labels = boxesOf<Text3d>(it.surface);
      expect(labels[1].data, '12 unread');
      expect(labels[1].style.color, theme.colorScheme.onSurfaceVariant);
      expect(labels[1].style.fontSize, theme.typography.bodyMedium.fontSize);
    });

    testWidgets('a leading and a trailing slot are 16dp from the text', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => ListTile3d.text(
          title: 'Inbox',
          leading: const SceneText3d('L'),
          trailing: const SceneText3d('T'),
        ),
      );
      // The outermost flex is the row; the inner one is the text column.
      final row = outermostOf<Flex3d>(it.surface);
      expect(
        row.spacing,
        closeTo(ListTile3d.horizontalTitleGap / 100.0, 1e-9),
        reason:
            'the gap is the flex\'s own spacing, which is between every '
            'adjacent pair and at neither end',
      );
    });

    testWidgets('the content padding is 16dp leading and 24dp trailing', (
      tester,
    ) async {
      final it = await pumpComponent(tester, () => ListTile3d.text(title: 'x'));
      final container = oneOf<Container3d>(it.surface);
      expect(container.padding.left, closeTo(0.16, 1e-9));
      expect(container.padding.right, closeTo(0.24, 1e-9));
      expect(
        container.padding.front,
        0.0,
        reason:
            'a front inset would push the row into the slab it is drawn '
            'on, where the surface wins the depth test and hides it',
      );
      expect(container.padding.back, 0.0);
    });

    testWidgets('selection substitutes the content colour', (tester) async {
      // Selection is a substitution, not a wash — which is why
      // `Material3dState` has no `selected` — so it costs a rebuild and moves
      // a token.
      final it = await pumpComponent(
        tester,
        () => ListTile3d.text(title: 'Inbox', selected: true, onTap: () {}),
      );
      expect(
        boxesOf<Text3d>(it.surface).single.style.color,
        theme.colorScheme.primary,
      );
      expect(it.semantics.properties.selected, isTrue);
    });

    testWidgets('a disabled tile is drawn in disabledContent', (tester) async {
      final it = await pumpComponent(
        tester,
        () => ListTile3d.text(title: 'Inbox', enabled: false, onTap: () {}),
      );
      expect(
        boxesOf<Text3d>(it.surface).single.style.color,
        theme.colorScheme.disabledContent,
        reason: 'there is no opacity in this stack to fade a subtree with',
      );
      expect(it.semantics.properties.enabled, isFalse);
    });
  });

  group('what it announces', () {
    testWidgets('a tile built from strings announces both of them', (
      tester,
    ) async {
      // The phase's own hard question. `Semantics3d` gathers nothing, so a
      // tile with a title *and* a subtitle would announce neither unless it
      // stated one — and `ListTile3d.text` is what makes stating it free.
      final it = await pumpComponent(
        tester,
        () => ListTile3d.text(
          title: 'Inbox',
          subtitle: '12 unread',
          onTap: () {},
        ),
      );
      expect(it.semantics.properties.label, 'Inbox, 12 unread');
      expect(it.semantics.properties.button, isTrue);
      expect(it.semantics.properties.onTap, isNotNull);
    });

    testWidgets('with no subtitle it announces the title alone', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => ListTile3d.text(title: 'Inbox'),
      );
      expect(it.semantics.properties.label, 'Inbox');
    });

    testWidgets('an explicit label wins over the composed one', (tester) async {
      final it = await pumpComponent(
        tester,
        () => ListTile3d.text(
          title: 'Inbox',
          subtitle: '12 unread',
          semanticLabel: 'Inbox, twelve unread messages',
        ),
      );
      expect(it.semantics.properties.label, 'Inbox, twelve unread messages');
    });

    testWidgets('a tile built from widgets announces what it was told to', (
      tester,
    ) async {
      // The honest half: this constructor is handed widgets and there is
      // nothing here that reads a label out of them, so a tile written this
      // way with no label announces a row with no name.
      final it = await pumpComponent(
        tester,
        () => const ListTile3d(title: SceneText3d('Inbox')),
      );
      expect(it.semantics.properties.label, isNull);
    });
  });

  group('interaction', () {
    testWidgets('a hover rebuilds nothing and lays nothing out', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => ListTile3d.text(title: 'Inbox', onTap: () {}),
      );
      final built = it.builds[0];

      it.pointer.hover(rayAt(it.surface, const Offset3d(2, 1.5, 0)));

      expect(it.layer.opacity, theme.stateLayer.hover);
      expect(it.layer.color, theme.colorScheme.onSurface);
      expect(it.builds[0], built, reason: 'nothing rebuilt');
      expect(it.surface.needsFlush, isFalse, reason: 'nothing laid out');
    });

    testWidgets('a tap lands, and a disabled tile takes none', (tester) async {
      var taps = 0;
      final it = await pumpComponent(
        tester,
        () => ListTile3d.text(title: 'Inbox', onTap: () => taps++),
      );
      it.pointer.down(rayAt(it.surface, const Offset3d(2, 1.5, 0)));
      it.pointer.up();
      expect(taps, 1);

      final off = await pumpComponent(
        tester,
        () => ListTile3d.text(
          title: 'Inbox',
          enabled: false,
          onTap: () => taps++,
        ),
      );
      off.pointer.down(rayAt(off.surface, const Offset3d(2, 1.5, 0)));
      off.pointer.up();
      expect(taps, 1);
      expect(off.layer, StateLayer3d.none);
    });

    testWidgets('the target is at least 48dp and is outermost', (tester) async {
      final it = await pumpComponent(
        tester,
        () => ListTile3d.text(title: 'Inbox', onTap: () {}),
      );
      expect(it.target.effectiveMinimumSize.height, closeTo(0.48, 1e-9));
      var sawTarget = false;
      var semanticsIsInside = false;
      void walk(Layout3d box) {
        if (box is TapTarget3d) sawTarget = true;
        if (box is Semantics3d && sawTarget) semanticsIsInside = true;
        box.visitChildren(walk);
      }

      walk(it.surface.child!);
      expect(semanticsIsInside, isTrue);
    });
  });

  group('tiles in a real scrolling view', () {
    testWidgets('a list of tiles stacks them at the published height', (
      tester,
    ) async {
      final controller = Scroll3dController();
      final it = await pumpComponent(
        tester,
        () => SceneSizedBox3d(
          width: 2.0,
          height: 2.0,
          child: SceneListView3d(
            controller: controller,
            children: <Widget>[
              for (var i = 0; i < 8; i++)
                ListTile3d.text(title: 'Row $i', onTap: () {}),
            ],
          ),
        ),
      );

      final panels = it.panels;
      expect(panels.length, greaterThan(2), reason: 'the list built rows');
      for (final panel in panels) {
        expect(
          panel.size.height,
          closeTo(ListTile3d.oneLineHeight / 100.0, 1e-9),
          reason:
              'a tile keeps its height inside a viewport, which hands its '
              'children a *loose* cross-axis constraint and an unbounded '
              'main-axis one',
        );
        expect(panel.size.width, closeTo(2.0, 1e-9));
      }
    });

    testWidgets('scrolling the list lays out no more than it has to', (
      tester,
    ) async {
      final controller = Scroll3dController();
      final it = await pumpComponent(
        tester,
        () => SceneSizedBox3d(
          width: 2.0,
          height: 2.0,
          // `.builder` rather than an explicit list, and the difference is
          // the point: a `SceneListView3d` given `children` has forty widgets
          // in the tree and forty layouts under it whatever the window shows,
          // because the widgets were already built by the caller. Only the
          // builder form reaches an item as the viewport gets to it.
          child: SceneListView3d.builder(
            controller: controller,
            itemCount: 40,
            itemBuilder: (context, i) =>
                ListTile3d.text(title: 'Row $i', onTap: () {}),
          ),
        ),
      );
      // A 2-unit window over 56dp rows holds about four of them, plus the
      // partial ones at each edge. If a tile ever started measuring its text
      // on the layout path, this is the number that would explode.
      expect(it.panels.length, lessThan(10));

      // Scrolled, and driven through Flutter's pipeline rather than by
      // calling `surface.flush()` here. That distinction is not cosmetic: a
      // lazily built child is created inside `RenderObject.invokeLayoutCallback`,
      // which asserts it is inside Flutter's own layout phase, so a flush
      // from a test body blows up with `_debugDoingLayout is not true`.
      controller.jumpTo(1.0);
      await tester.pump();
      expect(it.panels.length, lessThan(10));
    });

    testWidgets('a hover over one tile in a list washes only that tile', (
      tester,
    ) async {
      // The claim the whole ink-controller design exists for, measured where
      // it is actually paid: a pointer crossing a list is one uniform write
      // per tile and no layout at all.
      final it = await pumpComponent(
        tester,
        () => SceneSizedBox3d(
          width: 2.0,
          height: 2.0,
          child: SceneListView3d(
            children: <Widget>[
              for (var i = 0; i < 8; i++)
                ListTile3d.text(title: 'Row $i', onTap: () {}),
            ],
          ),
        ),
      );
      final built = it.builds[0];

      // The list is centred on a 4 x 3 surface, so the window spans
      // x 1..3 and y 0.5..2.5. The first row is at the top of it.
      it.pointer.hover(rayAt(it.surface, const Offset3d(2, 0.78, 0)));

      final washed = it.panels.where((p) => p.stateLayer.opacity > 0.0);
      expect(washed.length, 1, reason: 'exactly one tile lit up');
      expect(washed.single.stateLayer.opacity, theme.stateLayer.hover);
      expect(it.builds[0], built);
      expect(it.surface.needsFlush, isFalse);
    });
  });
}
