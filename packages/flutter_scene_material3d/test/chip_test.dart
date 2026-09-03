// The four chips: the token table across selection and enablement, the 32dp
// height the 48dp target has to cover, the delete affordance, and what a chip
// announces.

import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'surfaces_support.dart';

/// One of the four, with the same arguments whichever it is.
Widget chipFor(
  ChipVariant3d variant, {
  bool selected = false,
  bool enabled = true,
  void Function()? onPressed,
  void Function(bool)? onSelected,
  void Function()? onDeleted,
  String? semanticLabel,
}) => switch (variant) {
  ChipVariant3d.assist => AssistChip3d(
    label: const SceneText3d('Track'),
    enabled: enabled,
    onPressed: onPressed,
    semanticLabel: semanticLabel,
  ),
  ChipVariant3d.filter => FilterChip3d(
    label: const SceneText3d('Unread'),
    selected: selected,
    enabled: enabled,
    onSelected: onSelected,
    semanticLabel: semanticLabel,
  ),
  ChipVariant3d.input => InputChip3d(
    label: const SceneText3d('lucas'),
    selected: selected,
    enabled: enabled,
    onPressed: onPressed,
    onSelected: onSelected,
    onDeleted: onDeleted,
    semanticLabel: semanticLabel,
  ),
  ChipVariant3d.suggestion => SuggestionChip3d(
    label: const SceneText3d('Sounds good'),
    selected: selected,
    enabled: enabled,
    onPressed: onPressed,
    onSelected: onSelected,
    semanticLabel: semanticLabel,
  ),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const theme = Theme3dData.light;

  group('the token table', () {
    for (final variant in ChipVariant3d.values) {
      testWidgets('$variant at rest is transparent inside an outline', (
        tester,
      ) async {
        final it = await pumpComponent(
          tester,
          () => chipFor(variant, onPressed: () {}, onSelected: (_) {}),
        );
        final style = ChipStyle3d.of(theme, variant);

        expect(it.decoration.color.a, 0.0, reason: 'no container at rest');
        expect(it.decoration.border.color, style.outline);
        expect(it.decoration.border.color, theme.colorScheme.outlineVariant);
        expect(it.decoration.border.width, 1.0);
        expect(it.decoration.borderRadius, theme.shape.small);
        expect(it.decoration.elevation, theme.elevation.level0);
      });

      testWidgets('$variant is a 32dp row on a 1dp slab', (tester) async {
        final it = await pumpComponent(
          tester,
          () => chipFor(variant, onPressed: () {}, onSelected: (_) {}),
        );
        expect(
          it.panel.size.height,
          closeTo(ChipStyle3d.defaultHeight / 100.0, 1e-9),
          reason:
              "Material's 32dp — a transcription, since `_kChipHeight` is "
              'private and no accessor reaches it',
        );
        expect(
          it.panel.size.depth,
          closeTo(theme.thickness.thin / 100.0, 1e-9),
          reason:
              'the thinnest component in the catalogue: a chip is a label '
              'with an edge, not an object',
        );
      });

      testWidgets('$variant disabled dims its label and its outline', (
        tester,
      ) async {
        final it = await pumpComponent(
          tester,
          () => chipFor(
            variant,
            enabled: false,
            onPressed: () {},
            onSelected: (_) {},
          ),
        );
        expect(it.decoration.border.color, theme.colorScheme.disabledContainer);
        expect(
          boxesOf<Text3d>(it.surface).single.style.color,
          theme.colorScheme.disabledContent,
          reason: 'there is no opacity in this stack; disabled is a colour',
        );
        expect(it.layer, StateLayer3d.none);
      });
    }

    testWidgets('a selected chip fills and drops its outline', (tester) async {
      for (final variant in <ChipVariant3d>[
        ChipVariant3d.filter,
        ChipVariant3d.input,
        ChipVariant3d.suggestion,
      ]) {
        final it = await pumpComponent(
          tester,
          () => chipFor(variant, selected: true, onSelected: (_) {}),
        );
        expect(it.decoration.color, theme.colorScheme.secondaryContainer);
        expect(
          it.decoration.border.isNone,
          isTrue,
          reason:
              'the container is the signal; an outline round it would be '
              'a second, competing one',
        );
        expect(
          boxesOf<Text3d>(it.surface).single.style.color,
          theme.colorScheme.onSecondaryContainer,
        );
      }
    });

    testWidgets('an assist chip cannot be selected, and the table says so', (
      tester,
    ) async {
      // The variant rule lives in the token table rather than in the widget,
      // so the two cannot disagree: `selectable` is false and `resolve` drops
      // the selection.
      final style = ChipStyle3d.of(theme, ChipVariant3d.assist);
      expect(style.selectable, isFalse);
      expect(
        style.resolve(const {}, selected: true, enabled: true).selected,
        isFalse,
      );

      final it = await pumpComponent(
        tester,
        () => Chip3d(
          variant: ChipVariant3d.assist,
          label: const SceneText3d('Track'),
          selected: true,
          onPressed: () {},
        ),
      );
      expect(it.decoration.color.a, 0.0, reason: 'still no container');
      expect(
        it.semantics.properties.selected,
        isNull,
        reason:
            'announcing "not selected" tells a reader about a state the '
            'control does not have',
      );
    });

    testWidgets('an assist chip labels itself onSurface, the rest quieter', (
      tester,
    ) async {
      expect(
        ChipStyle3d.of(theme, ChipVariant3d.assist).content,
        theme.colorScheme.onSurface,
      );
      for (final variant in <ChipVariant3d>[
        ChipVariant3d.filter,
        ChipVariant3d.input,
        ChipVariant3d.suggestion,
      ]) {
        expect(
          ChipStyle3d.of(theme, variant).content,
          theme.colorScheme.onSurfaceVariant,
        );
      }
    });

    testWidgets('a disabled selected chip keeps its container', (tester) async {
      // The one precedence question the table has to answer out loud:
      // disabled wins everything *except* the fact of the selection, which is
      // information a reader still needs.
      final style = ChipStyle3d.of(theme, ChipVariant3d.filter);
      final resolved = style.resolve(const {}, selected: true, enabled: false);
      expect(resolved.container, theme.colorScheme.secondaryContainer);
      expect(resolved.content, theme.colorScheme.disabledContent);
      expect(resolved.border.isNone, isTrue);
    });

    testWidgets('a copied style reaches the panel', (tester) async {
      final it = await pumpComponent(
        tester,
        () => Chip3d(
          style: ChipStyle3d.of(
            theme,
            ChipVariant3d.filter,
          ).copyWith(shape: theme.shape.full),
          label: const SceneText3d('Unread'),
          onPressed: () {},
        ),
      );
      expect(it.decoration.borderRadius, theme.shape.full);
    });
  });

  group('the 48dp target, where it earns its keep', () {
    testWidgets('a press 6dp above a 32dp chip lands', (tester) async {
      // The component that makes the reach load-bearing. A chip is 32dp tall
      // and centred at y = 1.5, so it spans 1.34 to 1.66, and the target
      // reaches 8dp either side — to 1.26 and 1.74.
      var taps = 0;
      final it = await pumpComponent(
        tester,
        () => AssistChip3d(
          label: const SceneText3d('Track'),
          onPressed: () => taps++,
          semanticLabel: 'Track',
        ),
      );
      expect(it.panel.size.height, closeTo(0.32, 1e-9));
      expect(it.target.effectiveMinimumSize.height, closeTo(0.48, 1e-9));

      it.pointer.down(rayAt(it.surface, const Offset3d(2, 1.5, 0)));
      it.pointer.up();
      expect(taps, 1, reason: 'inside');

      it.pointer.down(rayAt(it.surface, const Offset3d(2, 1.28, 0)));
      it.pointer.up();
      expect(taps, 2, reason: '6dp above the edge, inside the 48dp reach');

      it.pointer.down(rayAt(it.surface, const Offset3d(2, 1.20, 0)));
      it.pointer.up();
      expect(taps, 2, reason: '14dp above: past the reach, and it stops');
    });

    testWidgets('and the reach grows no box, so a row of chips stays 32dp', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => AssistChip3d(label: const SceneText3d('Track'), onPressed: () {}),
      );
      expect(it.target.size.height, closeTo(0.32, 1e-9));
      expect(
        it.target.effectiveMinimumSize.height,
        greaterThan(it.target.size.height),
      );
    });
  });

  group('selection and what a state costs', () {
    testWidgets('tapping a filter chip reports the value it would become', (
      tester,
    ) async {
      final reported = <bool>[];
      final it = await pumpComponent(
        tester,
        () => FilterChip3d(
          label: const SceneText3d('Unread'),
          onSelected: reported.add,
          semanticLabel: 'Unread only',
        ),
      );
      it.pointer.down(rayAt(it.surface, const Offset3d(2, 1.5, 0)));
      it.pointer.up();
      expect(reported, <bool>[true]);
    });

    testWidgets('a hover rebuilds nothing and lays nothing out', (
      tester,
    ) async {
      // The baseline chip table has no state-dependent token, so the whole
      // interaction is one uniform write — the same property `Card3d` has and
      // a filled button does not.
      final it = await pumpComponent(
        tester,
        () => AssistChip3d(label: const SceneText3d('Track'), onPressed: () {}),
      );
      final built = it.builds[0];

      it.pointer.hover(rayAt(it.surface, const Offset3d(2, 1.5, 0)));

      expect(it.layer.opacity, theme.stateLayer.hover);
      expect(
        it.layer.color,
        theme.colorScheme.onSurface,
        reason:
            'the wash is the surface\'s content colour, which for an '
            'assist chip is onSurface',
      );
      expect(it.builds[0], built, reason: 'nothing rebuilt');
      expect(it.surface.needsFlush, isFalse, reason: 'nothing laid out');
    });
  });

  group('the delete affordance', () {
    testWidgets('takes the tap the chip would otherwise have taken', (
      tester,
    ) async {
      // The innermost recognizer wins the arena, exactly as it does in
      // Flutter, so a press on the delete icon deletes rather than selects.
      var deleted = 0;
      var pressed = 0;
      final it = await pumpComponent(
        tester,
        () => InputChip3d(
          label: const SceneText3d('lucas'),
          onPressed: () => pressed++,
          onDeleted: () => deleted++,
          semanticLabel: 'lucas',
        ),
      );

      // The delete glyph is the last box in the chip's row. Ask the tree
      // where it is rather than guessing a coordinate.
      final glyphs = boxesOf<Text3d>(it.surface);
      expect(glyphs.length, 2, reason: 'the label and the delete glyph');
      final at = offsetInSurface(glyphs.last) + glyphs.last.size.center;
      it.pointer.down(rayAt(it.surface, at));
      it.pointer.up();
      expect(deleted, 1);
      expect(pressed, 0, reason: 'the inner recognizer won the arena');

      // And a press on the label reaches the chip itself.
      final label = offsetInSurface(glyphs.first) + glyphs.first.size.center;
      it.pointer.down(rayAt(it.surface, label));
      it.pointer.up();
      expect(pressed, 1);
      expect(deleted, 1);
    });

    testWidgets('announces itself as its own button', (tester) async {
      final it = await pumpComponent(
        tester,
        () => InputChip3d(
          label: const SceneText3d('lucas'),
          onDeleted: () {},
          semanticLabel: 'lucas',
        ),
      );
      final announced = boxesOf<Semantics3d>(it.surface);
      expect(announced.length, 2, reason: 'the chip, and the delete inside it');
      expect(announced.first.properties.label, 'lucas');
      expect(announced.last.properties.label, 'Delete');
      expect(announced.last.properties.button, isTrue);
      expect(announced.last.properties.onTap, isNotNull);
    });

    testWidgets('has no target of its own, and the class doc says why', (
      tester,
    ) async {
      // A second `TapTarget3d` inside the chip's panel would be gated by the
      // panel — a target reaches past its own extent and its ancestors do not
      // — so its reach would be silently inert. The delete affordance adds
      // none, and exactly one box in the whole chip reaches past itself.
      //
      // There are still *two* `TapTarget3d`s either way: the chip's, and the
      // one an `InkWell3d` always installs, which `Chip3d` asks for at
      // `Size3d.zero` so it is a box and not a reach. That is the same
      // arrangement `Button3d` uses, and counting the reaching ones is what
      // makes the claim mean something.
      // Read before re-pumping: a second `pumpWidget` replaces the tree, and
      // the first controller's surface is null from then on.
      final with_ = await pumpComponent(
        tester,
        () => InputChip3d(
          label: const SceneText3d('lucas'),
          onDeleted: () {},
          onPressed: () {},
        ),
      );
      final targets = boxesOf<TapTarget3d>(with_.surface);
      final reaching = targets
          .where((t) => t.effectiveMinimumSize.height > t.size.height)
          .toList();
      expect(reaching.length, 1);
      expect(identical(reaching.single, with_.target), isTrue);

      final without = await pumpComponent(
        tester,
        () => InputChip3d(label: const SceneText3d('lucas'), onPressed: () {}),
      );
      expect(
        targets.length,
        boxesOf<TapTarget3d>(without.surface).length,
        reason: 'the delete affordance added no target at all',
      );
    });
  });

  group('what it announces', () {
    for (final variant in ChipVariant3d.values) {
      testWidgets('$variant is a button with the name it was given', (
        tester,
      ) async {
        final it = await pumpComponent(
          tester,
          () => chipFor(
            variant,
            onPressed: () {},
            onSelected: (_) {},
            semanticLabel: 'Filter',
          ),
        );
        expect(it.semantics.properties.button, isTrue);
        expect(it.semantics.properties.enabled, isTrue);
        expect(it.semantics.properties.label, 'Filter');
      });
    }

    testWidgets('a selectable chip publishes its selection', (tester) async {
      final on = await pumpComponent(
        tester,
        () => FilterChip3d(
          label: const SceneText3d('Unread'),
          selected: true,
          onSelected: (_) {},
          semanticLabel: 'Unread only',
        ),
      );
      expect(on.semantics.properties.selected, isTrue);

      final off = await pumpComponent(
        tester,
        () => FilterChip3d(
          label: const SceneText3d('Unread'),
          onSelected: (_) {},
          semanticLabel: 'Unread only',
        ),
      );
      expect(off.semantics.properties.selected, isFalse);
    });
  });
}
