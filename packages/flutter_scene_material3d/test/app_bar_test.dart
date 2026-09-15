// AppBar3d and SliverAppBar3d: the bar's heights, what a scroll does to a
// collapsing one, and the two mechanisms that keep a row out of it.

import 'dart:ui' show Color;

import 'package:flutter/widgets.dart' show ValueKey, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/testing.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'surfaces_support.dart';

const Theme3dData _theme = Theme3dData.light;
const double _dp = 0.01;

/// A bar at the top of a screen-shaped column.
///
/// A surface's constraints are *tight*, and `SceneSizedBox3d` enforces the
/// parent's — so a bar pumped straight onto a surface comes out the height of
/// the whole surface and every figure in this file would be measuring the
/// surface instead of the bar. A column with a stretched cross axis is the
/// shape a real screen has and gives the bar a loose main axis to size
/// itself in.
Widget screenWith(Widget bar) => SceneColumn3d(
  crossAxisAlignment: CrossAxisAlignment3d.stretch,
  children: <Widget>[
    bar,
    const SceneExpanded3d(child: SceneSizedBox3d()),
  ],
);

void main() {
  group('AppBar3d', () {
    testWidgets('is 64dp tall, at the surface colour, and 8dp deep', (
      tester,
    ) async {
      final pumped = await pumpComponent(
        tester,
        () => screenWith(AppBar3d.text(title: 'Inbox')),
        centred: false,
      );
      final bar = outermostOf<DecoratedBox3d>(pumped.surface);
      expect(bar.size.height, closeTo(64 * _dp, 1e-9));
      expect(bar.size.depth, closeTo(_theme.thickness.structural * _dp, 1e-9));
      expect(pumped.decoration.color, _theme.colorScheme.surface);
      expect(pumped.decoration.elevation, _theme.elevation.level0);
    });

    testWidgets('takes an explicit toolbar height', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => screenWith(AppBar3d.text(title: 'Inbox', toolbarHeight: 56)),
        centred: false,
      );
      expect(
        outermostOf<DecoratedBox3d>(pumped.surface).size.height,
        closeTo(56 * _dp, 1e-9),
      );
    });

    testWidgets('the three sizes differ only in what they expand to', (
      tester,
    ) async {
      for (final variant in AppBarVariant3d.values) {
        final style = AppBarStyle3d.of(_theme, variant);
        expect(style.toolbarHeight, AppBarStyle3d.defaultToolbarHeight);
        expect(style.thickness, _theme.thickness.structural);
        expect(style.container, _theme.colorScheme.surface);
      }
      expect(
        AppBarStyle3d.of(_theme, AppBarVariant3d.small).expandedHeight,
        64.0,
      );
      expect(
        AppBarStyle3d.of(_theme, AppBarVariant3d.medium).expandedHeight,
        112.0,
      );
      expect(
        AppBarStyle3d.of(_theme, AppBarVariant3d.large).expandedHeight,
        152.0,
      );
      expect(
        AppBarStyle3d.of(_theme, AppBarVariant3d.centerAligned).centerTitle,
        isTrue,
      );
      expect(
        AppBarStyle3d.of(_theme, AppBarVariant3d.small).centerTitle,
        isFalse,
      );
    });

    testWidgets('announces its title as a header', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => screenWith(AppBar3d.text(title: 'Inbox')),
        centred: false,
      );
      final announced = pumped.semantics.properties;
      expect(announced.label, 'Inbox');
      expect(announced.header, isTrue);
    });

    testWidgets('and a widget title announces only what it is told', (
      tester,
    ) async {
      // The phase-3 rule, restated where it bites: a Semantics3d gathers
      // nothing, so a bar built from widgets has no name unless it is given
      // one.
      final pumped = await pumpComponent(
        tester,
        () => screenWith(const AppBar3d(title: SceneText3d('Inbox'))),
        centred: false,
      );
      expect(boxesOf<Semantics3d>(pumped.surface), isEmpty);
    });

    testWidgets('a leading widget and actions share the toolbar', (
      tester,
    ) async {
      final pumped = await pumpComponent(
        tester,
        () => screenWith(
          AppBar3d.text(
            title: 'Inbox',
            leading: const SceneSizedBox3d(width: 0.24, height: 0.24),
            actions: const <Widget>[
              SceneSizedBox3d(width: 0.24, height: 0.24),
              SceneSizedBox3d(width: 0.24, height: 0.24),
            ],
          ),
        ),
        centred: false,
      );
      final row = boxesOf<Flex3d>(pumped.surface).last;
      // Leading, the expanded title, and two actions.
      expect(row.children, hasLength(4));
    });
  });

  group('where the title sits', () {
    /// The title's edges, and the bar's, in logical pixels from the bar's
    /// leading edge. Measured through the nodes' single-precision transforms,
    /// so the figures are good to a ten-thousandth of a logical pixel.
    ({double titleStart, double titleEnd, double barWidth}) measure(
      PumpedSurface pumped,
    ) {
      final bar = outermostOf<DecoratedBox3d>(pumped.surface);
      final title = oneOf<Text3d>(pumped.surface);
      final start =
          (title.drawnOffsetInSurface.x - bar.drawnOffsetInSurface.x) / _dp;
      return (
        titleStart: start,
        titleEnd: start + title.size.width / _dp,
        barWidth: bar.size.width / _dp,
      );
    }

    // Flutter's `NavigationToolbar` starts the title `middleSpacing` past the
    // leading slot and stops it `middleSpacing` short of the trailing one,
    // whether or not either slot holds anything. A bar with no leading widget
    // therefore keeps its title 16dp off its edge — and this one used to put
    // it against the edge, which the gallery's inbox bar showed in every
    // photograph and no test asked about.
    testWidgets('keeps the title titleSpacing off an edge with nothing on it', (
      tester,
    ) async {
      final pumped = await pumpComponent(
        tester,
        () => screenWith(AppBar3d.text(title: 'Inbox')),
        centred: false,
      );
      final at = measure(pumped);

      expect(at.titleStart, closeTo(AppBarStyle3d.defaultTitleSpacing, 1e-4));
      expect(
        at.barWidth - at.titleEnd,
        closeTo(AppBarStyle3d.defaultTitleSpacing, 1e-4),
      );
    });

    testWidgets('puts a leading button where Flutter does, and the title a '
        'leading slot and titleSpacing in', (tester) async {
      // Flutter gives the leading widget a slot `kToolbarHeight` wide — 56dp —
      // and centres an icon button in it, so the button's middle is 28dp in
      // and the title starts at 56 + 16 = 72dp. The slot is what the title is
      // measured from, not the button.
      const button = 48.0;
      final pumped = await pumpComponent(
        tester,
        () => screenWith(
          AppBar3d.text(
            title: 'Inbox',
            leading: const SceneSizedBox3d(width: button * _dp),
            actions: const <Widget>[SceneSizedBox3d(width: button * _dp)],
          ),
        ),
        centred: false,
      );
      final at = measure(pumped);
      final style = AppBarStyle3d.of(_theme, AppBarVariant3d.small);
      final bar = outermostOf<DecoratedBox3d>(pumped.surface);
      final buttons =
          boxesOf<SizedBox3d>(pumped.surface)
              .where((box) => (box.size.width / _dp - button).abs() < 1e-4)
              .toList()
            ..sort(
              (a, b) =>
                  a.drawnOffsetInSurface.x.compareTo(b.drawnOffsetInSurface.x),
            );
      final leadingMiddle =
          (buttons.first.drawnOffsetInSurface.x - bar.drawnOffsetInSurface.x) /
              _dp +
          button / 2;

      expect(leadingMiddle, closeTo(style.leadingWidth / 2, 1e-4));
      expect(
        at.titleStart,
        closeTo(style.leadingWidth + style.titleSpacing, 1e-4),
      );
      expect(at.titleStart, closeTo(72, 1e-4));

      // And the last action against the bar's trailing edge, with nothing
      // between them: Flutter's M3 bar has no padding there
      // (`actionsPadding` is zero), so the title stops one action and
      // titleSpacing short of the edge.
      final actionEnd =
          (buttons.last.drawnOffsetInSurface.x - bar.drawnOffsetInSurface.x) /
              _dp +
          button;
      expect(actionEnd, closeTo(at.barWidth, 1e-4));
      expect(
        at.barWidth - at.titleEnd,
        closeTo(button + style.titleSpacing, 1e-4),
      );
    });

    testWidgets('centres a leading widget narrower than a button in its slot', (
      tester,
    ) async {
      // Flutter lays a leading widget out in a tight 56dp box, and an icon in
      // one draws its glyph in the middle of it. A 24dp leading widget is
      // centred in the slot here too, rather than pushed to one side of it.
      const icon = 24.0;
      final pumped = await pumpComponent(
        tester,
        () => screenWith(
          AppBar3d.text(
            title: 'Inbox',
            leading: const SceneSizedBox3d(width: icon * _dp),
          ),
        ),
        centred: false,
      );
      final style = AppBarStyle3d.of(_theme, AppBarVariant3d.small);
      final bar = outermostOf<DecoratedBox3d>(pumped.surface);
      final leading = boxesOf<SizedBox3d>(
        pumped.surface,
      ).firstWhere((box) => (box.size.width / _dp - icon).abs() < 1e-4);
      final middle =
          (leading.drawnOffsetInSurface.x - bar.drawnOffsetInSurface.x) / _dp +
          icon / 2;

      expect(middle, closeTo(style.leadingWidth / 2, 1e-4));
      expect(measure(pumped).titleStart, closeTo(72, 1e-4));
    });

    group('a centred title', () {
      const button = 48.0;
      const long = 'A title long enough to run under the controls';

      Future<PumpedSurface> centred(
        WidgetTester tester, {
        required String title,
        bool leading = true,
        int actions = 0,
      }) => pumpComponent(
        tester,
        () => screenWith(
          AppBar3d.text(
            title: title,
            centerTitle: true,
            leading: leading
                ? const SceneSizedBox3d(width: button * _dp)
                : null,
            actions: <Widget>[
              for (var i = 0; i < actions; i++)
                const SceneSizedBox3d(width: button * _dp),
            ],
          ),
        ),
        centred: false,
      );

      testWidgets('is centred in the whole bar when it fits', (tester) async {
        // One action: at the test font's figures, 'Inbox' is 110dp, and
        // centred it would end 3dp inside a row of three.
        final pumped = await centred(tester, title: 'Inbox', actions: 1);
        final at = measure(pumped);

        expect(
          (at.titleStart + at.titleEnd) / 2,
          closeTo(at.barWidth / 2, 1e-4),
          reason: 'the bar, not what is left between its controls',
        );
      });

      // Flutter's `NavigationToolbar` centres the middle and then pulls it
      // back inside the room between the slots: never closer than
      // `middleSpacing` to the leading slot, and never running under the
      // trailing one. A title centred in the whole bar used to be drawn over
      // the actions when it was long, because nothing measured it against
      // them.
      testWidgets('stops titleSpacing short of the actions when it does not', (
        tester,
      ) async {
        final pumped = await centred(tester, title: long, actions: 3);
        final at = measure(pumped);
        final style = AppBarStyle3d.of(_theme, AppBarVariant3d.small);

        final actionsStart = at.barWidth - 3 * button;
        expect(
          at.titleEnd,
          lessThanOrEqualTo(actionsStart - style.titleSpacing + 1e-4),
        );
        expect(
          at.titleStart,
          greaterThanOrEqualTo(style.leadingWidth + style.titleSpacing - 1e-4),
        );
      });

      testWidgets('starts no closer than titleSpacing past the leading slot', (
        tester,
      ) async {
        final pumped = await centred(tester, title: long);
        final at = measure(pumped);
        final style = AppBarStyle3d.of(_theme, AppBarVariant3d.small);

        expect(
          at.titleStart,
          greaterThanOrEqualTo(style.leadingWidth + style.titleSpacing - 1e-4),
        );
      });
    });

    testWidgets('a medium bar keeps its headline off the edge too', (
      tester,
    ) async {
      final pumped = await pumpComponent(
        tester,
        () => SceneCustomScrollView3d(
          slivers: <Widget>[
            SliverAppBar3d.text(
              title: 'Inbox',
              variant: AppBarVariant3d.medium,
            ),
          ],
        ),
        centred: false,
      );
      final at = measure(pumped);

      // Flutter's medium bar pads its expanded title 16dp at both ends.
      expect(at.titleStart, closeTo(16, 1e-4));
      expect(at.barWidth - at.titleEnd, closeTo(16, 1e-4));
    });
  });

  group('SliverAppBar3d', () {
    /// A pinned bar over a list of decorated rows, and the handles a test
    /// wants on it.
    Future<({PumpedSurface pumped, Scroll3dController scroll})> screen(
      WidgetTester tester, {
      bool pinned = true,
      double? expandedHeight,
      AppBarVariant3d variant = AppBarVariant3d.small,
    }) async {
      final scroll = Scroll3dController();
      final pumped = await pumpComponent(
        tester,
        () => SceneCustomScrollView3d(
          controller: scroll,
          slivers: <Widget>[
            SliverAppBar3d.text(
              title: 'Inbox',
              pinned: pinned,
              variant: variant,
              expandedHeight: expandedHeight,
            ),
            SceneSliverList3d(
              children: <Widget>[
                for (var i = 0; i < 8; i++)
                  SceneSizedBox3d(
                    height: 0.5,
                    child: Card3d(
                      key: ValueKey<int>(i),
                      child: const SceneSizedBox3d(),
                    ),
                  ),
              ],
            ),
          ],
        ),
        centred: false,
      );
      return (pumped: pumped, scroll: scroll);
    }

    testWidgets('collapses from its expanded height to the toolbar', (
      tester,
    ) async {
      final (:pumped, :scroll) = await screen(
        tester,
        variant: AppBarVariant3d.large,
      );
      final header = outermostOf<SliverPersistentHeader3d>(pumped.surface);
      expect(header.geometry.paintExtent, closeTo(152 * _dp, 1e-9));

      scroll.jumpTo(0.5);
      await tester.pump();
      expect(header.geometry.paintExtent, closeTo(152 * _dp - 0.5, 1e-9));

      // And it stops at the toolbar height rather than disappearing.
      scroll.jumpTo(3);
      await tester.pump();
      expect(header.geometry.paintExtent, closeTo(64 * _dp, 1e-9));
      expect(header.offset, Offset3d.zero);
    });

    testWidgets('an unpinned bar scrolls away entirely', (tester) async {
      final (:pumped, :scroll) = await screen(tester, pinned: false);
      final header = outermostOf<SliverPersistentHeader3d>(pumped.surface);
      scroll.jumpTo(1.0);
      await tester.pump();
      expect(header.geometry.paintExtent, 0.0);
      expect(header.obstructedExtent, 0.0);
    });

    testWidgets('lifts by the theme\'s depth step, not by one pixel', (
      tester,
    ) async {
      // The finding this phase is here to encode. SliverPersistentHeader3d
      // defaults its lift to one logical pixel, which separates two things
      // with no thickness and does nothing for two slabs: an 8dp bar over a
      // 4dp card needs a step above the mean of the two, 6dp.
      final (:pumped, :scroll) = await screen(tester);
      final header = outermostOf<SliverPersistentHeader3d>(pumped.surface);
      expect(
        header.effectiveLift,
        closeTo(_theme.thickness.depthStep * _dp, 1e-9),
      );
      expect(
        _theme.thickness.separates(
          _theme.thickness.raised,
          _theme.thickness.structural,
          step: _theme.thickness.depthStep,
        ),
        isTrue,
      );
      expect(
        _theme.thickness.separates(
          _theme.thickness.raised,
          _theme.thickness.structural,
          step: 1.0,
        ),
        isFalse,
        reason: 'which is what the layout package\'s default would give',
      );

      scroll.jumpTo(1.0);
      await tester.pump();
      // Toward the viewer is negative depth.
      expect(
        header.sceneOffset.z,
        closeTo(-_theme.thickness.depthStep * _dp, 1e-6),
      );
    });

    testWidgets('cuts a row passing under it at the bar\'s edge', (
      tester,
    ) async {
      // The claim two plans have made and nothing had ever checked: the
      // *published* block, not just what clipRegion answers afterwards.
      final (:pumped, :scroll) = await screen(tester);
      scroll.jumpTo(1.0);
      await tester.pump();

      final rows = boxesOf<DecoratedBox3d>(pumped.surface);
      // The first is the bar's own panel; the rest are the cards.
      final cut = rows
          .where((box) => !box.clipRegion.isUnbounded)
          .toList(growable: false);
      expect(cut, isNotEmpty);
      for (final box in cut) {
        expect(box.clipRegion.planes, hasLength(1));
        // The band runs from the row's leading edge to the bar's trailing
        // one, along the scroll axis.
        expect(box.clipRegion.planes.single.normal, const Offset3d(0, 1, 0));
      }
    });

    testWidgets('and nothing is cut while the bar covers nothing', (
      tester,
    ) async {
      final (:pumped, :scroll) = await screen(tester);
      for (final box in boxesOf<DecoratedBox3d>(pumped.surface)) {
        expect(box.clipRegion.isUnbounded, isTrue);
      }
      expect(
        outermostOf<SliverPersistentHeader3d>(pumped.surface).obstructedExtent,
        0.0,
      );
    });

    testWidgets('a scroll does not rebuild the bar', (tester) async {
      // The no-relayout guarantee's cousin: a collapse happens inside a
      // layout pass, through the constraints the header hands its child, and
      // nothing in the widget tree is rebuilt for it.
      final (:pumped, :scroll) = await screen(tester);
      final before = pumped.builds[0];
      scroll.jumpTo(0.4);
      await tester.pump();
      scroll.jumpTo(0.8);
      await tester.pump();
      expect(pumped.builds[0], before);
    });

    testWidgets('refuses to expand to less than it collapses to', (
      tester,
    ) async {
      await pumpComponent(
        tester,
        () => SceneCustomScrollView3d(
          slivers: const <Widget>[
            SliverAppBar3d(title: SceneText3d('Inbox'), expandedHeight: 32),
          ],
        ),
        centred: false,
      );
      expect(tester.takeException(), isA<AssertionError>());
    });
  });

  group('the bar\'s own tokens', () {
    test('a style says everything and copyWith replaces one thing', () {
      final style = AppBarStyle3d.of(_theme, AppBarVariant3d.small);
      expect(style, AppBarStyle3d.of(_theme, AppBarVariant3d.small));
      expect(style.copyWith(container: const Color(0xFF00FF00)), isNot(style));
      expect(
        style.copyWith(container: const Color(0xFF00FF00)).toolbarHeight,
        style.toolbarHeight,
      );
    });

    test('the surface tint is off, as it is on a card', () {
      // Phase 4's finding applied: a bar's container token already *is* the
      // colour, so a tint on top of it would be a second signal for one
      // thing. Flutter's own _AppBarDefaultsM3 resolves surfaceTintColor to
      // transparent for the same reason.
      final bar = AppBar3d.text(title: 'x');
      expect(bar.styleOf(_theme).container, _theme.colorScheme.surface);
    });
  });
}
