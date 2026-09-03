// The three cards: the token table, the geometry, what a state costs, what a
// card announces, and the one thing phase 4 is the first consumer of — the
// clip contract's deliberate decision to leave depth alone.

import 'package:flutter/widgets.dart' show BuildContext, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'surfaces_support.dart';

/// One of the three, with the same arguments whichever it is.
Widget cardFor(
  CardVariant3d variant, {
  void Function()? onTap,
  String? semanticLabel,
  Widget? child,
}) => switch (variant) {
  CardVariant3d.elevated => ElevatedCard3d(
    onTap: onTap,
    semanticLabel: semanticLabel,
    child: child,
  ),
  CardVariant3d.filled => FilledCard3d(
    onTap: onTap,
    semanticLabel: semanticLabel,
    child: child,
  ),
  CardVariant3d.outlined => OutlinedCard3d(
    onTap: onTap,
    semanticLabel: semanticLabel,
    child: child,
  ),
};

/// A `ClipBox3d` in the widget tree.
///
/// The layout package publishes `ClipBox3d` imperatively and has no
/// `SceneClipBox3d` widget yet, so a test that wants a clipped widget subtree
/// writes this four-line adapter. It is exactly what a `Scaffold3d` will need
/// in phase 5, and it is recorded as a gap in the phase-4 plan notes rather
/// than fixed here, because a new widget in the layout package wants a plan
/// of its own.
class SceneClipBox3d extends SingleChildLayout3dWidget {
  const SceneClipBox3d({super.key, this.clipDepth = false, super.child});

  final bool clipDepth;

  @override
  ClipBox3d createLayout(BuildContext context) =>
      ClipBox3d(clipDepth: clipDepth);

  @override
  void updateLayout(BuildContext context, ClipBox3d layout) {
    layout.clipDepth = clipDepth;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const theme = Theme3dData.light;

  group('the token table', () {
    for (final variant in CardVariant3d.values) {
      testWidgets('$variant draws its own tokens', (tester) async {
        final it = await pumpComponent(
          tester,
          () => cardFor(variant, child: const SceneText3d('Yesterday')),
        );
        final style = CardStyle3d.of(theme, variant);

        expect(it.decoration.color, style.container);
        expect(it.decoration.elevation, style.elevation);
        expect(it.decoration.borderRadius, style.shape);
        expect(
          it.decoration.borderRadius,
          theme.shape.medium,
          reason: 'Material 3 gives all three cards a 12dp radius',
        );
        if (style.outline == null) {
          expect(it.decoration.border.isNone, isTrue);
        } else {
          expect(it.decoration.border.color, style.outline);
          expect(it.decoration.border.width, style.outlineWidth);
        }
      });

      testWidgets('$variant is a 4dp slab with a bevelled rim', (tester) async {
        final it = await pumpComponent(
          tester,
          () => cardFor(variant, child: const SceneText3d('Yesterday')),
        );
        expect(
          it.panel.size.depth,
          closeTo(theme.thickness.raised / 100.0, 1e-9),
          reason:
              'a card is thickness.raised deep, which is the token the '
              'scale was named around',
        );
        expect(
          it.decoration.bevel,
          closeTo(theme.shape.bevelFor(theme.thickness.raised), 1e-9),
          reason: 'a knife-edged card reads as a cut-out under a grazing light',
        );
      });

      testWidgets('$variant turns the surface tint off', (tester) async {
        // The correction phase 3 made for buttons applies to cards too, and
        // Flutter agrees: `_CardDefaultsM3` and both its siblings resolve
        // `surfaceTintColor` to transparent. An elevated card's container is
        // `surfaceContainerLow`, which already *is* the level-1 tint baked
        // into a colour; applying it again double-counts.
        final it = await pumpComponent(
          tester,
          () => cardFor(variant, child: const SceneText3d('Yesterday')),
        );
        expect(it.decoration.surfaceTint?.a, 0.0);
      });
    }

    testWidgets('only the elevated card floats', (tester) async {
      for (final variant in CardVariant3d.values) {
        final style = CardStyle3d.of(theme, variant);
        expect(
          style.elevation,
          variant == CardVariant3d.elevated
              ? theme.elevation.level1
              : theme.elevation.level0,
        );
      }
    });

    testWidgets('a copied style reaches the panel', (tester) async {
      final it = await pumpComponent(
        tester,
        () => Card3d(
          style: CardStyle3d.of(
            theme,
            CardVariant3d.filled,
          ).copyWith(shape: theme.shape.extraLarge),
          child: const SceneText3d('Yesterday'),
        ),
      );
      expect(it.decoration.borderRadius, theme.shape.extraLarge);
    });
  });

  group('the margin', () {
    testWidgets('sits outside the panel rather than inside it', (tester) async {
      // Flutter puts its `Padding` outside its `Material` for a reason a wash
      // makes visible: a margin inside the panel would be 4dp of card that
      // lights up under a pointer and is not the card.
      final it = await pumpComponent(
        tester,
        () => const FilledCard3d(child: SceneText3d('Yesterday')),
      );
      final padding = outermostOf<Padding3d>(it.surface);
      var sawPadding = false;
      var panelIsInside = false;
      void walk(Layout3d box) {
        if (identical(box, padding)) sawPadding = true;
        if (box is DecoratedBox3d && sawPadding) panelIsInside = true;
        box.visitChildren(walk);
      }

      walk(it.surface.child!);
      expect(panelIsInside, isTrue);
      expect(
        padding.padding.left,
        closeTo(0.04, 1e-9),
        reason: "Material's 4dp, through the surface's metrics",
      );
    });
  });

  group('what a state costs', () {
    testWidgets('a hover rebuilds nothing and lays nothing out', (
      tester,
    ) async {
      // The claim `CardStyle3d` makes and a button cannot: **no card token
      // varies with a state**, so the whole interaction is one uniform write
      // and there is nothing for the widget layer to do.
      final it = await pumpComponent(
        tester,
        () => ElevatedCard3d(
          onTap: () {},
          semanticLabel: 'Yesterday',
          child: const SceneText3d('Yesterday'),
        ),
      );
      final built = it.builds[0];
      final elevation = it.decoration.elevation;

      it.pointer.hover(rayAt(it.surface, const Offset3d(2, 1.5, 0)));

      expect(it.layer.opacity, theme.stateLayer.hover);
      expect(it.layer.color, theme.colorScheme.onSurface);
      expect(it.builds[0], built, reason: 'nothing rebuilt');
      expect(it.surface.needsFlush, isFalse, reason: 'nothing laid out');
      expect(
        it.decoration.elevation,
        elevation,
        reason: 'Material 3 does not raise a card under a pointer',
      );
    });

    testWidgets('a card with no callbacks installs no ink well at all', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => const FilledCard3d(child: SceneText3d('Yesterday')),
      );
      expect(boxesOf<Focus3d>(it.surface), isEmpty);
      expect(boxesOf<TapTarget3d>(it.surface), isEmpty);
      expect(
        it.semantics.properties.button,
        isNull,
        reason: 'a card that does nothing is not a button',
      );
    });
  });

  group('the target and what it announces', () {
    testWidgets('a tappable card is a button with a name', (tester) async {
      var taps = 0;
      final it = await pumpComponent(
        tester,
        () => ElevatedCard3d(
          onTap: () => taps++,
          semanticLabel: 'Yesterday',
          child: const SceneText3d('Yesterday'),
        ),
      );
      final properties = it.semantics.properties;
      expect(properties.button, isTrue);
      expect(properties.enabled, isTrue);
      expect(properties.label, 'Yesterday');
      expect(properties.onTap, isNotNull);

      it.pointer.down(rayAt(it.surface, const Offset3d(2, 1.5, 0)));
      it.pointer.up();
      expect(taps, 1);
    });

    testWidgets('the target is outside the semantics box', (tester) async {
      // Not a style question, and the same rule `Button3d` is arranged
      // around: a target reaches past its own extent and every ancestor gates
      // a ray on its own extent.
      final it = await pumpComponent(
        tester,
        () => ElevatedCard3d(onTap: () {}, child: const SceneText3d('x')),
      );
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

  group('a card inside a clip keeps its depth', () {
    testWidgets('the clip a scrolling list imposes has no depth planes', (
      tester,
    ) async {
      // The decision this phase is the first consumer of.
      // `Clip3dRegion.rect` is **four** planes and leaves the thickness
      // alone, and `lib/src/clip.dart` says why in as many words: "a raised
      // card inside a scrolling list should still stand proud of it". Nobody
      // had built that scene before; this is it, in arithmetic, and
      // `examples/render_probe`'s `card_in_clipped_list` is it in a picture.
      final it = await pumpComponent(
        tester,
        () => const SceneClipBox3d(
          child: SceneSizedBox3d(
            width: 2.0,
            height: 1.0,
            child: ElevatedCard3d(child: SceneText3d('Yesterday')),
          ),
        ),
      );

      final region = it.panel.clipRegion;
      expect(region.isUnbounded, isFalse, reason: 'the clip did not reach it');
      expect(
        region.planes.length,
        4,
        reason: 'a rect clip is four planes: two in x, two in y, none in z',
      );
      for (final plane in region.planes) {
        expect(
          plane.normal.z,
          0.0,
          reason:
              'a depth plane would slice a raised card off flush with the '
              'list, which is exactly what the contract refuses to do',
        );
      }
    });

    testWidgets('and asking for one adds them', (tester) async {
      // The other half of the same decision: `clipDepth` exists, it is
      // opt-in, and a caller who wants a card sliced flat can have it.
      final it = await pumpComponent(
        tester,
        () => const SceneClipBox3d(
          clipDepth: true,
          child: SceneSizedBox3d(
            width: 2.0,
            height: 1.0,
            child: ElevatedCard3d(child: SceneText3d('Yesterday')),
          ),
        ),
      );
      expect(it.panel.clipRegion.planes.length, 6);
    });

    testWidgets('a raised card really does reach in front of the list', (
      tester,
    ) async {
      // The claim the clip is protecting, stated as geometry. An elevated
      // card lifts by `metrics.dp(1)` and is 4dp deep, so its front face is
      // 1 + 2 = 3dp in front of the plane the list sits on. A depth clip at
      // the list's own thickness would cut that off.
      final it = await pumpComponent(
        tester,
        () => const ElevatedCard3d(child: SceneText3d('Yesterday')),
      );
      expect(it.decoration.elevation, theme.elevation.level1);
      expect(it.panel.size.depth, closeTo(0.04, 1e-9));
      final reach = it.decoration.elevation / 100.0 + it.panel.size.depth / 2.0;
      expect(reach, closeTo(0.03, 1e-9));
    });
  });
}
