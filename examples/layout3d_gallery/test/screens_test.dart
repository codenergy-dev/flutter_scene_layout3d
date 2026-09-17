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
    expect(find3d.bySubtype<ListView3d>(), findsNothing);
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

    for (final label in <String>['Notifications', 'Compact rows', 'Volume']) {
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
    // And the same question of every label on the screen at once.
    expect(find3d.bySubtype<Text3d>(), standsOnItsPanel3d);
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
}
