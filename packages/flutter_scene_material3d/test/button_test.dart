// The seven buttons: the tree they build, the token table they resolve, what
// a state costs, the 48dp target, and what they announce.
//
// The claim under all of it is the one phase 3 exists to prove: the seven
// variants are one widget with seven token sets. Most of the tests below
// therefore run over `ButtonVariant3d.values` rather than over seven copies —
// if a variant ever needs a special case here, the design has slipped.

import 'package:flutter/gestures.dart' show kPressTimeout;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart'
    show Builder, BuildContext, FocusManager, Widget;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The one box of type [T] in [surface].
T only<T extends Layout3d>(Layout3dSurface surface) {
  final found = <T>[];
  void walk(Layout3d box) {
    if (box is T) found.add(box);
    box.visitChildren(walk);
  }

  walk(surface.child!);
  if (found.length != 1) {
    throw StateError('expected one $T, found ${found.length}');
  }
  return found.single;
}

/// The outermost of the boxes of type [T] in [surface].
T outermost<T extends Layout3d>(Layout3dSurface surface) {
  T? found;
  void walk(Layout3d box) {
    if (found != null) return;
    if (box is T) {
      found = box;
      return;
    }
    box.visitChildren(walk);
  }

  walk(surface.child!);
  return found!;
}

/// One of the seven, with the same arguments whichever it is.
Widget buttonFor(
  ButtonVariant3d variant, {
  void Function()? onPressed,
  String? semanticLabel,
  Widget? child,
}) => switch (variant) {
  ButtonVariant3d.filled => FilledButton3d(
    onPressed: onPressed,
    semanticLabel: semanticLabel,
    child: child,
  ),
  ButtonVariant3d.filledTonal => FilledTonalButton3d(
    onPressed: onPressed,
    semanticLabel: semanticLabel,
    child: child,
  ),
  ButtonVariant3d.outlined => OutlinedButton3d(
    onPressed: onPressed,
    semanticLabel: semanticLabel,
    child: child,
  ),
  ButtonVariant3d.text => TextButton3d(
    onPressed: onPressed,
    semanticLabel: semanticLabel,
    child: child,
  ),
  ButtonVariant3d.elevated => ElevatedButton3d(
    onPressed: onPressed,
    semanticLabel: semanticLabel,
    child: child,
  ),
  ButtonVariant3d.icon => IconButton3d(
    icon: Icons.add,
    onPressed: onPressed,
    semanticLabel: semanticLabel,
  ),
  ButtonVariant3d.floatingAction => FloatingActionButton3d(
    onPressed: onPressed,
    semanticLabel: semanticLabel,
    child: child,
  ),
};

/// A pumped button and everything a test wants to ask about it.
class Pumped {
  Pumped(this.controller, this.builds, this.child);

  final Layout3dController controller;
  final List<int> builds;

  /// The box standing in for the button's content, when one was asked for.
  ///
  /// A `TestBox` counts its own layouts, which is how the interaction tests
  /// measure what a hover costs rather than trusting the code path — the same
  /// method `test/ink_well_test.dart` uses.
  final TestBox? child;

  Layout3dSurface get surface => controller.surface!;
  DecoratedBox3d get panel => decoratedBoxIn(surface);
  BoxDecoration3d get decoration => panel.decoration as BoxDecoration3d;
  StateLayer3d get layer => panel.stateLayer;
  Semantics3d get semantics => only<Semantics3d>(surface);
  TapTarget3d get target => outermost<TapTarget3d>(surface);

  Layout3dPointer? _pointer;

  /// One pointer for the whole test, and it has to be one: a `down` and the
  /// `up` that completes it are two calls on the *same* object, because the
  /// sequence between them is what holds the captured path and the arena
  /// entry. A getter that built a fresh pointer each time would press one and
  /// release another, and every tap would silently count zero.
  Layout3dPointer get pointer => _pointer ??= Layout3dPointer(surface);
}

/// Pumps one button, centred on a 4 x 3 surface at the standard hundred
/// logical pixels to the unit.
Future<Pumped> pump(
  WidgetTester tester,
  ButtonVariant3d variant, {
  void Function()? onPressed,
  String? semanticLabel = 'Save',
  Theme3dData theme = Theme3dData.light,
  bool countLayouts = false,
}) async {
  final controller = Layout3dController();
  final builds = <int>[0];
  TestBox? child;
  await tester.pumpWidget(
    SceneLayout3d(
      parent: Node(),
      size: const Size3d(4, 3, 0.5),
      controller: controller,
      child: SceneTheme3d(
        data: theme,
        child: SceneCenter3d(
          child: Builder(
            builder: (BuildContext context) {
              builds[0]++;
              return buttonFor(
                variant,
                onPressed: onPressed,
                semanticLabel: semanticLabel,
                child: countLayouts
                    ? SceneTestBox(
                        const Size3d(0.5, 0.2, 0),
                        (box) => child = box,
                      )
                    : const SceneText3d('Save'),
              );
            },
          ),
        ),
      ),
    ),
  );
  return Pumped(controller, builds, child);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The focus manager is global and outlives a pumped tree, exactly as the
  // ink-well tests say.
  tearDown(() {
    FocusManager.instance.primaryFocus?.unfocus();
    FocusManager.instance.applyFocusChangesIfNeeded();
  });

  const theme = Theme3dData.light;

  group('the tree every variant builds', () {
    for (final variant in ButtonVariant3d.values) {
      testWidgets('$variant is a target over a panel over an ink well', (
        tester,
      ) async {
        final it = await pump(tester, variant, onPressed: () {});
        final style = ButtonStyle3d.of(theme, variant);

        expect(
          it.target.effectiveMinimumSize.width,
          closeTo(0.48, 1e-9),
          reason: 'Material\'s 48dp, through the surface\'s metrics',
        );
        expect(
          it.panel.size.height,
          closeTo(style.minimumHeight / 100.0, 1e-9),
          reason: 'the specification\'s height, not the target\'s',
        );
        expect(
          it.panel.size.width,
          greaterThanOrEqualTo(style.minimumWidth / 100.0 - 1e-9),
        );
        expect(
          it.panel.size.depth,
          closeTo(style.thickness / 100.0, 1e-9),
          reason: 'a button is a slab, and the theme said how deep',
        );
        expect(it.decoration.borderRadius, style.shape);
        expect(
          it.decoration.bevel,
          closeTo(theme.shape.bevelFor(style.thickness), 1e-9),
          reason: 'the rim is rounded in proportion, from the shape scale',
        );
      });
    }

    testWidgets('it shrink-wraps its label rather than filling the surface', (
      tester,
    ) async {
      // `SceneCenter3d` hands down loose but *bounded* constraints, so a
      // button that simply aligned its child would come out four units wide.
      // The `SceneAlign3d(widthFactor: 1)` inside is what stops that, the way
      // Flutter's own button does it.
      final it = await pump(tester, ButtonVariant3d.text, onPressed: () {});
      expect(it.panel.size.width, lessThan(2.0));
      expect(
        it.panel.size.width,
        greaterThan(0.24),
        reason: 'the 12dp padding either side is in there',
      );
    });

    testWidgets('a wider minimum is honoured by a short label', (tester) async {
      final it = await pump(tester, ButtonVariant3d.filled, onPressed: () {});
      expect(it.panel.size.width, greaterThanOrEqualTo(0.64));
    });
  });

  group('the token table', () {
    for (final variant in ButtonVariant3d.values) {
      testWidgets('$variant draws its enabled tokens', (tester) async {
        final it = await pump(tester, variant, onPressed: () {});
        final style = ButtonStyle3d.of(theme, variant);
        expect(it.decoration.color, style.container);
        expect(it.decoration.elevation, style.elevation);
        if (style.outline == null) {
          expect(it.decoration.border.isNone, isTrue);
        } else {
          expect(it.decoration.border.color, style.outline);
          expect(it.decoration.border.width, style.outlineWidth);
        }
      });

      testWidgets('$variant substitutes colours when disabled', (tester) async {
        final it = await pump(tester, variant);
        final style = ButtonStyle3d.of(theme, variant);

        expect(
          it.decoration.color,
          style.disabledContainer,
          reason: 'onSurface at 12%, or nothing where there was nothing',
        );
        expect(
          it.decoration.elevation,
          0.0,
          reason: 'a disabled control does not float',
        );
        if (style.outline != null) {
          expect(it.decoration.border.color, style.disabledOutline);
        }
        expect(
          it.layer,
          StateLayer3d.none,
          reason: 'and it lights up for nothing',
        );
      });
    }

    testWidgets('the wash is the content colour, and it follows disabled', (
      tester,
    ) async {
      // The one place the substitution and the wash channel meet: a disabled
      // button's ink is `disabledContent`, so if anything ever did light it
      // up it would light up in the right colour.
      final enabled = await pump(
        tester,
        ButtonVariant3d.filled,
        onPressed: () {},
      );
      enabled.pointer.hover(rayAt(enabled.surface, const Offset3d(2, 1.5, 0)));
      expect(enabled.layer.color, theme.colorScheme.onPrimary);
      expect(enabled.layer.opacity, theme.stateLayer.hover);

      final disabled = await pump(tester, ButtonVariant3d.filled);
      disabled.pointer.hover(
        rayAt(disabled.surface, const Offset3d(2, 1.5, 0)),
      );
      expect(disabled.layer, StateLayer3d.none);
    });

    testWidgets('a hover raises a filled button and a press puts it down', (
      tester,
    ) async {
      final it = await pump(tester, ButtonVariant3d.filled, onPressed: () {});
      final style = ButtonStyle3d.of(theme, ButtonVariant3d.filled);
      final centre = const Offset3d(2, 1.5, 0);
      expect(it.decoration.elevation, style.elevation);

      it.pointer.hover(rayAt(it.surface, centre));
      await tester.pump();
      expect(it.decoration.elevation, style.hoveredElevation);
      expect(style.hoveredElevation, theme.elevation.level1);

      it.pointer.down(rayAt(it.surface, centre));
      await tester.pump(kPressTimeout + const Duration(milliseconds: 1));
      it.pointer.move(rayAt(it.surface, centre));
      await tester.pump();
      expect(
        it.decoration.elevation,
        style.elevation,
        reason: 'pressed beats hovered, which is what resolve() encodes',
      );
      it.pointer.up();
    });

    testWidgets('the focus moves an outlined button\'s border', (tester) async {
      final it = await pump(tester, ButtonVariant3d.outlined, onPressed: () {});
      final style = ButtonStyle3d.of(theme, ButtonVariant3d.outlined);
      expect(it.decoration.border.color, style.outline);

      focusIn(it.surface).requestFocus();
      FocusManager.instance.applyFocusChangesIfNeeded();
      await tester.pump();
      expect(it.decoration.border.color, theme.colorScheme.primary);
    });
  });

  group('what a state costs', () {
    testWidgets(
      'a text button\'s hover rebuilds nothing and lays out nothing',
      (tester) async {
        // The variant whose tokens do not move with a state: the whole
        // interaction is one uniform write, exactly as `InkWell3d` promises.
        final it = await pump(
          tester,
          ButtonVariant3d.text,
          onPressed: () {},
          countLayouts: true,
        );
        final built = it.builds[0];
        final laidOut = it.child!.layoutCount;

        it.pointer.hover(rayAt(it.surface, const Offset3d(2, 1.5, 0)));

        expect(it.layer.opacity, theme.stateLayer.hover);
        expect(it.builds[0], built, reason: 'nothing rebuilt');
        expect(it.child!.layoutCount, laidOut, reason: 'nothing laid out');
        expect(it.surface.needsFlush, isFalse);
      },
    );

    for (final variant in ButtonVariant3d.values) {
      testWidgets('$variant lays nothing out for a hover or a focus', (
        tester,
      ) async {
        // The guarantee that has to hold for *every* variant, including the
        // two whose tokens move: an elevation and a border colour are shader
        // uniforms on a box that is already the right size.
        final it = await pump(tester, variant, onPressed: () {});

        it.pointer.hover(rayAt(it.surface, const Offset3d(2, 1.5, 0)));
        expect(
          it.surface.needsFlush,
          isFalse,
          reason: 'a hover marked nothing dirty for layout',
        );
        await tester.pump();
        expect(
          it.surface.needsFlush,
          isFalse,
          reason: 'and neither did the rebuild it may have caused',
        );

        focusIn(it.surface).requestFocus();
        FocusManager.instance.applyFocusChangesIfNeeded();
        expect(it.surface.needsFlush, isFalse);
        await tester.pump();
        expect(it.surface.needsFlush, isFalse);
      });
    }
  });

  group('the 48dp target', () {
    testWidgets('a press 4dp above a 40dp button lands', (tester) async {
      // The claim phase 2 recorded as broken and this phase closed, stated in
      // the terms a user would: a small button's margin is pressable.
      //
      // The button is 40dp tall and centred at y = 1.5, so it spans
      // 1.30 to 1.70 and the target reaches 0.04 either side.
      var taps = 0;
      final it = await pump(
        tester,
        ButtonVariant3d.filled,
        onPressed: () => taps++,
      );
      expect(it.panel.size.height, closeTo(0.40, 1e-9));

      it.pointer.down(rayAt(it.surface, const Offset3d(2, 1.5, 0)));
      it.pointer.up();
      expect(taps, 1, reason: 'inside');

      it.pointer.down(rayAt(it.surface, const Offset3d(2, 1.28, 0)));
      it.pointer.up();
      expect(taps, 2, reason: '2dp above the edge, inside the 48dp reach');

      it.pointer.down(rayAt(it.surface, const Offset3d(2, 1.24, 0)));
      it.pointer.up();
      expect(taps, 2, reason: '6dp above: past the reach, and it stops');
    });

    testWidgets('the target grows no box, so neighbours do not move', (
      tester,
    ) async {
      final it = await pump(tester, ButtonVariant3d.filled, onPressed: () {});
      expect(it.target.size, it.panel.size);
      expect(
        it.target.effectiveMinimumSize.height,
        greaterThan(it.target.size.height),
        reason: 'the reach is bigger than the box, and only the reach',
      );
    });

    testWidgets('a disabled button takes no tap in the margin either', (
      tester,
    ) async {
      var taps = 0;
      final it = await pump(tester, ButtonVariant3d.filled, onPressed: null);
      // Nothing to press: `onPressed: null` is the disabled spelling, so the
      // counter cannot move. Asserting it is still worth a line, because the
      // ray *does* reach the target out here and a component that dispatched
      // regardless would be found by exactly this.
      it.pointer.down(rayAt(it.surface, const Offset3d(2, 1.28, 0)));
      it.pointer.up();
      it.pointer.down(rayAt(it.surface, const Offset3d(2, 1.5, 0)));
      it.pointer.up();
      expect(taps, 0);
      expect(it.layer, StateLayer3d.none, reason: 'and it never lit up');
    });
  });

  group('what it announces', () {
    for (final variant in ButtonVariant3d.values) {
      testWidgets('$variant announces itself as an enabled button', (
        tester,
      ) async {
        final it = await pump(
          tester,
          variant,
          onPressed: () {},
          semanticLabel: 'Save',
        );
        final properties = it.semantics.properties;
        expect(properties.button, isTrue);
        expect(properties.enabled, isTrue);
        expect(properties.label, 'Save');
        expect(properties.onTap, isNotNull);
      });

      testWidgets('$variant announces a disabled button as disabled', (
        tester,
      ) async {
        final it = await pump(tester, variant, semanticLabel: 'Save');
        final properties = it.semantics.properties;
        expect(properties.button, isTrue);
        expect(
          properties.enabled,
          isFalse,
          reason: 'the reader has to be told, since it cannot see the colour',
        );
        expect(properties.onTap, isNull);
      });
    }

    testWidgets('the semantics box is inside the target, not around it', (
      tester,
    ) async {
      // Not a style question. `TapTarget3d` reaches past its own extent and
      // every ancestor gates a ray on its own extent, so a semantics box
      // wrapped around the target — Flutter's order — would reject a press in
      // the margin before the target ever saw it.
      final it = await pump(tester, ButtonVariant3d.filled, onPressed: () {});
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

  group('restyling', () {
    testWidgets('a copied style reaches the panel', (tester) async {
      // The reason `ButtonStyle3d` is public: a catalogue whose buttons
      // cannot be restyled is a demonstration.
      final controller = Layout3dController();
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 3, 0.5),
          controller: controller,
          child: SceneTheme3d(
            data: theme,
            child: SceneCenter3d(
              child: FilledButton3d(
                style: ButtonStyle3d.of(theme, ButtonVariant3d.filled).copyWith(
                  shape: theme.shape.small,
                  thickness: theme.thickness.structural,
                ),
                onPressed: () {},
                child: const SceneText3d('Save'),
              ),
            ),
          ),
        ),
      );
      final panel = decoratedBoxIn(controller.surface!);
      final decoration = panel.decoration as BoxDecoration3d;
      expect(decoration.borderRadius, theme.shape.small);
      expect(panel.size.depth, closeTo(theme.thickness.structural / 100, 1e-9));
    });

    testWidgets('a dark theme reskins every variant without a special case', (
      tester,
    ) async {
      for (final variant in ButtonVariant3d.values) {
        final it = await pump(
          tester,
          variant,
          onPressed: () {},
          theme: Theme3dData.dark,
        );
        expect(
          it.decoration.color,
          ButtonStyle3d.of(Theme3dData.dark, variant).container,
        );
      }
    });
  });
}
