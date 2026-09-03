// `CardStyle3d.of` against Flutter's own card defaults.
//
// The standard phase 3 set: where a figure is reachable through Flutter's
// public API, read it rather than transcribing it, so the suite is a drift
// alarm as well as a check.
//
// A card is the *weaker* of the two lanes phase 3 found, and for the reason
// the floating action button was: `_CardDefaultsM3` and its two siblings are
// private, and `CardTheme.of(context)` returns an application's overrides
// rather than the resolved defaults, so there is no accessor to call. What is
// reachable is what a real `Card` **renders** — the `Material` it builds, and
// the `Padding` around it — so that is what this reads. It catches a colour
// role changing, an elevation moving and the surface tint coming back; it
// cannot catch a change Flutter makes somewhere a card does not render.

import 'package:flutter/material.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `Material` a real Flutter [card] renders, and the `Padding` around it.
Future<(Material, Padding)> renderCard(WidgetTester tester, Card card) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      home: Scaffold(body: Center(child: card)),
    ),
  );
  final material = tester.widget<Material>(
    find.descendant(of: find.byType(Card), matching: find.byType(Material)),
  );
  final padding = tester.widget<Padding>(
    find
        .descendant(of: find.byType(Card), matching: find.byType(Padding))
        .first,
  );
  return (material, padding);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const theme = Theme3dData.light;

  // Flutter's own light scheme, which `test/color_scheme_test.dart` already
  // pins `ColorScheme3d.light` against role by role. Naming it here as well
  // makes the comparisons below read as "the same role", not "the same
  // number I typed twice".
  final flutterScheme = ThemeData(brightness: Brightness.light).colorScheme;

  group('the container colour is the role Flutter uses', () {
    const pairs = <CardVariant3d, String>{
      CardVariant3d.elevated: 'surfaceContainerLow',
      CardVariant3d.filled: 'surfaceContainerHighest',
      CardVariant3d.outlined: 'surface',
    };

    testWidgets('elevated', (tester) async {
      final (material, _) = await renderCard(tester, const Card());
      final style = CardStyle3d.of(theme, CardVariant3d.elevated);
      // `toARGB32` rather than `==`: a `Color` built from a double and one
      // built from a byte are the same colour everywhere it matters and are
      // not `==`. Phase 3's first drift test failed on exactly this.
      expect(style.container.toARGB32(), material.color!.toARGB32());
      expect(
        style.container.toARGB32(),
        flutterScheme.surfaceContainerLow.toARGB32(),
        reason: pairs[CardVariant3d.elevated],
      );
    });

    testWidgets('filled', (tester) async {
      final (material, _) = await renderCard(tester, const Card.filled());
      final style = CardStyle3d.of(theme, CardVariant3d.filled);
      expect(style.container.toARGB32(), material.color!.toARGB32());
      expect(
        style.container.toARGB32(),
        flutterScheme.surfaceContainerHighest.toARGB32(),
        reason: pairs[CardVariant3d.filled],
      );
    });

    testWidgets('outlined', (tester) async {
      final (material, _) = await renderCard(tester, const Card.outlined());
      final style = CardStyle3d.of(theme, CardVariant3d.outlined);
      expect(style.container.toARGB32(), material.color!.toARGB32());
      expect(
        style.container.toARGB32(),
        flutterScheme.surface.toARGB32(),
        reason: pairs[CardVariant3d.outlined],
      );
    });
  });

  group('the depth figures', () {
    testWidgets('an elevated card rests at level 1 and the others are flat', (
      tester,
    ) async {
      final (elevated, _) = await renderCard(tester, const Card());
      final (filled, _) = await renderCard(tester, const Card.filled());
      final (outlined, _) = await renderCard(tester, const Card.outlined());

      expect(
        CardStyle3d.of(theme, CardVariant3d.elevated).elevation,
        elevated.elevation,
      );
      expect(
        CardStyle3d.of(theme, CardVariant3d.filled).elevation,
        filled.elevation,
      );
      expect(
        CardStyle3d.of(theme, CardVariant3d.outlined).elevation,
        outlined.elevation,
      );
      expect(
        elevated.elevation,
        theme.elevation.level1,
        reason: 'and Flutter\'s figure really is the level-1 token',
      );
    });

    testWidgets('every card turns the surface tint off', (tester) async {
      // The correction phase 3 made for buttons, holding for cards too — and
      // Flutter is where the figure comes from rather than this package's own
      // reasoning about double-counting.
      for (final card in const <Card>[Card(), Card.filled(), Card.outlined()]) {
        final (material, _) = await renderCard(tester, card);
        expect(
          material.surfaceTintColor,
          Colors.transparent,
          reason: 'Flutter stopped tinting a card, so this package must too',
        );
      }
    });
  });

  group('the shape and the margin', () {
    testWidgets('a card has a 12dp radius, which is the medium shape token', (
      tester,
    ) async {
      final (material, _) = await renderCard(tester, const Card());
      final shape = material.shape! as RoundedRectangleBorder;
      final radius = shape.borderRadius.resolve(TextDirection.ltr).topLeft.x;

      expect(radius, 12.0);
      expect(
        CardStyle3d.of(theme, CardVariant3d.elevated).shape,
        theme.shape.medium,
      );
      expect(theme.shape.medium.topLeft, radius);
    });

    testWidgets('an outlined card draws a 1dp outlineVariant side', (
      tester,
    ) async {
      final (material, _) = await renderCard(tester, const Card.outlined());
      final shape = material.shape! as RoundedRectangleBorder;
      final style = CardStyle3d.of(theme, CardVariant3d.outlined);

      expect(style.outlineWidth, shape.side.width);
      expect(style.outline!.toARGB32(), shape.side.color.toARGB32());
      expect(
        style.outline!.toARGB32(),
        flutterScheme.outlineVariant.toARGB32(),
        reason: 'outlineVariant, not outline: a card is quieter than a button',
      );
    });

    testWidgets('the margin is 4dp all round', (tester) async {
      final (_, padding) = await renderCard(tester, const Card());
      final margin = padding.padding.resolve(TextDirection.ltr);
      final style = CardStyle3d.of(theme, CardVariant3d.elevated);

      expect(style.margin.left, margin.left);
      expect(style.margin.top, margin.top);
      expect(style.margin.right, margin.right);
      expect(style.margin.bottom, margin.bottom);
      expect(
        style.margin.front,
        0.0,
        reason:
            'a margin is in-plane: a front one would be an elevation by '
            'another name, and the two would then disagree',
      );
      expect(style.margin.back, 0.0);
    });
  });

  group('the figures Flutter cannot be asked for', () {
    test('the thickness is this package\'s invention, and says so', () {
      // Material publishes nothing about depth, so there is nothing to check
      // this against and this test exists to say that out loud rather than to
      // verify anything. The figure is a *token*, `Thickness3d.raised`, and
      // the scale is checked for internal consistency in `depth_test.dart`.
      final style = CardStyle3d.of(theme, CardVariant3d.elevated);
      expect(style.thickness, theme.thickness.raised);
      expect(
        theme.thickness.separates(style.thickness, style.thickness),
        isTrue,
        reason: 'two cards on the theme\'s own depth step do not z-fight',
      );
    });
  });
}
