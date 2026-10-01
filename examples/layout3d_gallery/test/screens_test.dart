// The one app a person actually runs, built headlessly.
//
// Nothing here draws — a `BoxDecoration3d` with no painter installed lays out
// perfectly and paints nothing, which is exactly what the package does before
// `initializeMaterial3d()` — so this is no substitute for looking at the
// window, and the phase that added these screens looked. What it does catch is
// the failure that would otherwise reach a person: a screen that stops laying
// out after a refactor of the catalogue, an assert in `Scaffold3d`'s depth
// ordering, a slot that is no longer satisfiable. Those are cheap to pin down
// and expensive to find by starting a GPU.

import 'package:flutter/widgets.dart';
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/testing.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layout3d_gallery/screens.dart';

/// Mounts [screen] on a surface the size the gallery gives it, under a
/// camera that looks straight at it.
///
/// No `textRendererFactory`: a `Text3d` with no renderer measures and lays out
/// fine, and rasterizing a glyph wants a GPU that `flutter test` does not
/// have. The gallery installs one; this asks the arithmetic questions.
Future<Layout3dSurface> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  Size3d size = const Size3d(3.5, 4.8, 0.6),
  LayoutBasis3d? basis,
  Layout3dMetrics? metrics,
}) => tester.pumpSurface3d(
  SceneTheme3d(
    data: Theme3dData.dark,
    child: SceneOverlay3d(child: screen),
  ),
  size: size,
  basis: basis,
  metrics: metrics,
);

void main() {
  testWidgets('the upright screen fills the panel it is given', (tester) async {
    final surface = await pumpScreen(tester, const MaterialScreen());

    expect(surface.child!.size, const Size3d(3.5, 4.8, 0.6));
    // A screen is a stack of panels: the scaffold's backing, the bar, the
    // navigation bar, the button, the chips, the cards and the tiles. If the
    // decoration ever stops reaching a component, this says so long before
    // anyone starts a GPU.
    expect(find3d.bySubtype<DecoratedBox3d>(), findsAtLeast(11));
    for (final label in <String>['Inbox', 'Settings', 'Compose']) {
      expect(find3d.bySemanticsLabel(label), findsAny);
    }
    expect(find3d.bySemanticsLabel('Ada Lovelace'), isReachable3d);
  });

  testWidgets('the inbox scrolls, and the destination swaps it for the '
      'controls', (tester) async {
    await pumpScreen(tester, const MaterialScreen());

    expect(
      find3d.bySubtype<ListView3d>(),
      findsAny,
      reason: 'the inbox is a list taller than the body it sits in',
    );
    expect(find3d.bySemanticsLabel('Volume'), findsNothing);

    // A regression as much as a check: every slot of every `Scaffold3d` used
    // to be unreachable by a ray. `tap3d` presses the destination through the
    // camera and the host, and fails — naming what it hit instead — if a
    // press there would not reach it.
    await tester.tap3d(find3d.bySemanticsLabel('Settings'));
    await tester.pump();

    expect(find3d.bySemanticsLabel('Volume'), findsOne);
    // The inbox's own rows are gone. This used to ask whether *any*
    // `ListView3d` was left, which stopped meaning "the inbox is gone" the
    // day the settings tab became a list of its own — it had to, because the
    // theme picker is one row more than the panel holds.
    expect(find3d.bySemanticsLabel('Ada Lovelace'), findsNothing);
    // And the settings are on pages: a page view, holding a list per page
    // that has been reached.
    expect(find3d.bySubtype<PageView3d>(), findsOne);
  });

  testWidgets('every control on the settings screen stands on the face of '
      'the card it is in, and can be pressed', (tester) async {
    // The slider in the settings screen's second card was laid out, labelled
    // and reachable, and nobody could see it: the card's padding was
    // `EdgeInsets3d.all`, which insets the *front* too, so the slider and its
    // label sat 12dp behind a card 4dp thick and the card's face hid them.
    // The test above passed the whole time, because a label that is there
    // and a label you can see are different claims. This is the second one,
    // asked of the layout.
    await pumpScreen(tester, const MaterialScreen());
    await tester.tap3d(find3d.bySemanticsLabel('Settings'));
    await tester.pump();

    void standsAndAnswers(List<String> labels) {
      for (final label in labels) {
        final control = find3d.bySemanticsLabel(label);
        expect(
          find3d.ancestor(
            of: control,
            matching: find3d.bySubtype<DecoratedBox3d>(),
          ),
          findsAny,
          reason: '"$label" is on no surface at all',
        );
        expect(control, standsOnItsPanel3d);
        expect(control, isReachable3d);
      }
    }

    standsAndAnswers(<String>['Notifications', 'Volume']);
    // The tabs are on the body itself, as a navigation bar's destinations
    // are on the bar: no card under them, but a press reaches them.
    for (final tab in <String>['General', 'Display']) {
      expect(find3d.bySemanticsLabel(tab), isReachable3d);
    }
    // The second tab's controls, once its page has been turned to. The
    // swatches are here because they are the smallest interactive control
    // on the screen — a 40dp disc with a 48dp reach, the shape the catalogue
    // has got wrong before — and the segments and the radio rows because
    // they are the newest.
    await tester.tap3d(find3d.bySemanticsLabel('Display'));
    await tester.pumpAndSettle();
    standsAndAnswers(<String>[
      'Light theme',
      'Dark theme',
      'Violet theme',
      'Teal theme',
      'Newest',
      'Oldest',
      // 'Sender' is the next row, under the navigation bar: below the fold of
      // a panel this size, and the lane asks of what a press can reach.
    ]);
    // And the same question of every label on the screen at once.
    expect(find3d.bySubtype<Text3d>(), standsOnItsPanel3d);
  });

  testWidgets('save spins for a moment, and the volume has a bar', (
    tester,
  ) async {
    // The headless half of the two indicators the gallery shows: the spinner
    // replaces the button's label while the pretend save runs and gives it
    // back, and the bar follows the slider. Whether the arc reads as turning
    // is a question only the window answers.
    await pumpScreen(tester, const MaterialScreen());
    await tester.tap3d(find3d.bySemanticsLabel('Settings'));
    await tester.pump();
    expect(find3d.bySemanticsLabel('Volume level'), standsOnItsPanel3d);

    // The settings are a list taller than the screen, and the actions are
    // its last row: under the navigation bar until it is scrolled to, which
    // is what a person does too.
    await tester.scroll3d(
      find3d.bySemanticsLabel('Volume'),
      const Offset(0, 400),
    );
    await tester.pumpAndSettle();
    await tester.tap3d(find3d.bySemanticsLabel('Save'));
    await tester.pump();
    expect(find3d.bySemanticsLabel('Saving'), findsOne);
    // Not settled: an indeterminate spinner never settles, exactly as
    // Flutter's does not.
    await tester.pump(const Duration(milliseconds: 1300));
    expect(find3d.bySemanticsLabel('Saving'), findsNothing);
    // And the snack bar it ends with, arrived and gone again.
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('the table screen lays out on the ground plane', (tester) async {
    final surface = await pumpScreen(
      tester,
      const TableScreen(),
      size: const Size3d(4.6, 2.6, 0.6),
      basis: LayoutBasis3d.xz,
      // The rate the gallery gives this plane, and the reason it is repeated
      // here: an overflow depends on how many logical pixels the surface is
      // across, so a test at the default rate would measure a screen the app
      // never draws.
      metrics: const Layout3dMetrics(unitsPerLogicalPixel: 0.012),
    );

    expect(surface.child!.size, const Size3d(4.6, 2.6, 0.6));
    for (final label in <String>['Card 1', 'Card 2', 'Card 3']) {
      // Looked at from above, the way the gallery's camera sees the table.
      expect(find3d.bySemanticsLabel(label), isReachable3d);
    }
    // The basis is the only difference between this screen and the upright
    // one, and it is a property of the plane rather than of the layout: the
    // boxes below it never hear about it.
    expect(surface.basis, LayoutBasis3d.xz);
    expect(find3d.bySubtype<Text3d>(), standsOnItsPanel3d);
  });
  testWidgets('the overflow menu opens, and the dialog it opens arrives', (
    tester,
  ) async {
    // The gallery is where a person sees an arrival, so this is the headless
    // half of that: the menu and the dialog are wired, reachable, and gone
    // when they are closed. Whether they *read* as arriving is a question
    // only the window answers.
    await pumpScreen(tester, const MaterialScreen());
    expect(find3d.bySemanticsLabel('About'), findsNothing);

    await tester.tap3d(find3d.bySemanticsLabel('More'));
    // Settled, not pumped once: a menu is pressable where layout put it
    // rather than where a growing menu is drawn.
    await tester.pumpAndSettle();
    expect(find3d.bySemanticsLabel('About'), isReachable3d);

    await tester.tap3d(find3d.bySemanticsLabel('About'));
    await tester.pumpAndSettle();
    expect(find3d.bySemanticsLabel('About'), findsNothing);
    expect(find3d.bySemanticsLabel('About this gallery'), findsOne);

    // Popped rather than tapped on the scrim: a barrier's centre is behind
    // the dialog it dims, so aiming a press there presses the dialog. That
    // the scrim closes a dialog is the catalogue's own test to make.
    final navigator = Navigator3d.of(
      tester.layout3d<Layout3d>(find3d.bySubtype<ModalBarrier3d>()),
    );
    expect(navigator!.pop(), isTrue);
    await tester.pumpAndSettle();
    expect(find3d.bySemanticsLabel('About this gallery'), findsNothing);
  });

  testWidgets('a row opens its message, and its avatar flies there', (
    tester,
  ) async {
    // The headless half again: that a flight goes up, stands in for both
    // ends while it is up, and puts them back afterwards. Whether it reads
    // as one object moving is a question only the window answers.
    final surface = await pumpScreen(tester, const MaterialScreen());
    final rows = <Hero3d>{};
    void collect(Layout3d box) {
      if (box is Hero3d) rows.add(box);
      box.visitChildren(collect);
    }

    collect(surface);
    expect(rows, isNotEmpty, reason: 'every row carries its avatar as a hero');
    expect(rows.every((hero) => !hero.isFlying), isTrue);

    await tester.tap3d(find3d.bySemanticsLabel('Ada Lovelace'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    // Mid-arrival: the row's avatar has handed over to a flight.
    expect(rows.any((hero) => hero.isFlying), isTrue);

    await tester.pumpAndSettle();
    expect(find3d.bySemanticsLabel('Ada Lovelace'), findsWidgets);
    expect(
      rows.every((hero) => !hero.isFlying),
      isTrue,
      reason: 'a settled flight gives both ends back',
    );
  });

  testWidgets('the picker re-themes the scene from one colour, and the '
      'segmented button changes its brightness', (tester) async {
    // The headless half of what the gallery is for. Whether a generated
    // scheme *looks* like a scheme is a question only the window answers —
    // this asks the one the layout can: that pressing a swatch reaches the
    // theme both surfaces read, rather than only the callback beside it.
    var seed = GalleryTheme3d.defaultSeed;
    var brightness = Brightness.light;

    await tester.pumpSurface3d(
      StatefulBuilder(
        builder: (context, setState) => GalleryTheme3d(
          seed: seed,
          brightness: brightness,
          onSeedChanged: (value) => setState(() => seed = value),
          onBrightnessChanged: (value) => setState(() => brightness = value),
          child: SceneTheme3d(
            data: Theme3dData(
              colorScheme: ColorScheme3d.fromSeed(
                seedColor: seed,
                brightness: brightness,
              ),
            ),
            child: const SceneOverlay3d(child: MaterialScreen()),
          ),
        ),
      ),
      size: const Size3d(3.5, 4.8, 0.6),
    );

    // Read off the tree rather than off the local variable: what is being
    // asked is whether the screen sees it, not whether the callback ran.
    ColorScheme3d onScreen() =>
        Theme3d.of(tester.element(find.byType(MaterialScreen))).colorScheme;

    await tester.tap3d(find3d.bySemanticsLabel('Settings'));
    await tester.pump();
    await tester.tap3d(find3d.bySemanticsLabel('Display'));
    await tester.pumpAndSettle();
    expect(
      onScreen().primary,
      ColorScheme3d.fromSeed(seedColor: GalleryTheme3d.defaultSeed).primary,
    );

    const teal = Color(0xFF00696E);
    await tester.tap3d(find3d.bySemanticsLabel('Teal theme'));
    await tester.pumpAndSettle();
    expect(seed, teal);
    expect(
      onScreen().primary,
      ColorScheme3d.fromSeed(seedColor: teal).primary,
      reason: 'the swatch re-themed the screen it is drawn on',
    );

    await tester.tap3d(find3d.bySemanticsLabel('Dark theme'));
    await tester.pumpAndSettle();
    expect(brightness, Brightness.dark);
    expect(onScreen().brightness, Brightness.dark);
    // And the seed survived the change of brightness: they are two knobs.
    expect(
      onScreen().primary,
      ColorScheme3d.fromSeed(
        seedColor: teal,
        brightness: Brightness.dark,
      ).primary,
    );
  });

  group('phase 5 of the components a screen still needs', () {
    /// How far down the inbox the card announcing [name] is.
    double down(WidgetTester tester, String name) => tester
        .layout3d<Layout3d>(find3d.bySemanticsLabel(name))
        .drawnOffsetInSurface
        .y;

    testWidgets('a tab turns the settings to their second page, and a radio '
        'row there sorts the inbox', (tester) async {
      await pumpScreen(tester, const MaterialScreen());
      expect(
        down(tester, 'Ada Lovelace'),
        lessThan(down(tester, 'Edsger Dijkstra')),
      );

      await tester.tap3d(find3d.bySemanticsLabel('Settings'));
      await tester.pump();
      // Built, perhaps — a page view lays out the page beside the one it
      // shows — but off to the side of the window, where nothing reaches it.
      expect(find3d.bySemanticsLabel('Oldest'), isNot(isReachable3d));
      await tester.tap3d(find3d.bySemanticsLabel('Display'));
      await tester.pumpAndSettle();
      expect(find3d.bySemanticsLabel('Oldest'), isReachable3d);

      await tester.tap3d(find3d.bySemanticsLabel('Oldest'));
      await tester.pumpAndSettle();
      await tester.tap3d(find3d.bySemanticsLabel('Inbox').first);
      await tester.pumpAndSettle();
      // Oldest first: the last message is at the top now.
      expect(
        down(tester, 'Edsger Dijkstra'),
        lessThan(down(tester, 'Ada Lovelace')),
      );
    });
  });

  group('phase 4 of the components a screen still needs', () {
    /// Every label on [surface], in tree order.
    List<String> labels(Layout3dSurface surface) {
      final found = <String>[];
      void walk(Layout3d box) {
        if (box is Text3d) found.add(box.data);
        box.visitChildren(walk);
      }

      walk(surface);
      return found;
    }

    testWidgets('the inbox badge counts what nobody has opened', (
      tester,
    ) async {
      final surface = await pumpScreen(tester, const MaterialScreen());
      expect(labels(surface), contains('5'));

      await tester.tap3d(find3d.bySemanticsLabel('Ada Lovelace'));
      await tester.pumpAndSettle();
      Navigator3d.of(
        tester.layout3d<Layout3d>(find3d.bySubtype<ModalBarrier3d>()),
      )!.pop();
      await tester.pumpAndSettle();
      expect(labels(surface), contains('4'));
      expect(labels(surface), isNot(contains('5')));
    });

    testWidgets('the menu opens a drawer, and a destination in it changes '
        'the tab and closes it', (tester) async {
      await pumpScreen(tester, const MaterialScreen());
      expect(find3d.bySemanticsLabel('Gallery'), findsNothing);

      await tester.tap3d(find3d.bySemanticsLabel('Menu'));
      await tester.pumpAndSettle();
      expect(find3d.bySemanticsLabel('Gallery'), findsOne);

      // The drawer's own Settings, which is the last one in the tree: the
      // overlay is built after the screen it is in front of.
      await tester.tap3d(find3d.bySemanticsLabel('Settings').last);
      await tester.pumpAndSettle();
      expect(find3d.bySemanticsLabel('Gallery'), findsNothing);
      expect(find3d.bySemanticsLabel('Volume'), findsOne);
    });

    testWidgets('turning notifications off raises a banner that turns them '
        'back on', (tester) async {
      await pumpScreen(tester, const MaterialScreen());
      await tester.tap3d(find3d.bySemanticsLabel('Settings'));
      await tester.pump();
      expect(find3d.bySemanticsLabel('Turn on'), findsNothing);

      await tester.tap3d(find3d.bySemanticsLabel('Notifications'));
      await tester.pumpAndSettle();
      expect(find3d.bySemanticsLabel('Turn on'), isReachable3d);
      expect(find3d.bySemanticsLabel('Turn on'), standsOnItsPanel3d);

      await tester.tap3d(find3d.bySemanticsLabel('Turn on'));
      await tester.pumpAndSettle();
      expect(find3d.bySemanticsLabel('Turn on'), findsNothing);
    });

    testWidgets('the table\'s bar lifts the card its button names', (
      tester,
    ) async {
      final surface = await pumpScreen(
        tester,
        const TableScreen(),
        size: const Size3d(4.6, 2.6, 0.6),
        basis: LayoutBasis3d.xz,
        metrics: const Layout3dMetrics(unitsPerLogicalPixel: 0.012),
      );
      for (final label in <String>[
        'Lift Route',
        'Lift Break',
        'Lift Agenda',
        'Lift the next card',
      ]) {
        expect(find3d.bySemanticsLabel(label), isReachable3d);
      }
      await tester.tap3d(find3d.bySemanticsLabel('Lift Agenda'));
      await tester.pump();
      // The labels read card by card, and the third now says it is up.
      final levels = labels(
        surface,
      ).where((label) => label.startsWith('level')).toList();
      expect(levels, <String>['level 1', 'level 1', 'level 5']);
    });
  });
}
