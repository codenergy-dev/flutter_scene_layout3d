// The button tokens, checked against Flutter's own tables rather than against
// a second hand-written copy.
//
// Phase 1 established the standard and the reason for it: Flutter generates
// its Material 3 colour and type tables from the Material token database, so
// comparing against Flutter makes the suite a **drift alarm** as well as a
// check. A test that compared these figures with a constant written beside
// them would only prove that one file matches another file.
//
// The seam is `ButtonStyleButton.defaultStyleOf(context)`, which is public
// even though the `_…DefaultsM3` classes behind it are not: pump a real
// Flutter button, ask it for its default style, and read the container
// colour, the padding, the minimum size, the shape and the type off the
// framework itself. `IconButton` goes the same way, because Material 3's
// icon button *is* a `ButtonStyleButton`.
//
// `FloatingActionButton` is the one that is not. Its defaults are a private
// `_FABDefaultsM3` reachable through no public accessor at all, so this file
// reads the `Material` widget the framework actually builds — its colour, its
// elevation and its shape — plus the rendered size. That is still the
// framework's own output rather than a transcription, and it is marked as the
// weaker check that it is: it can only see what a *rendered* FAB looks like.

import 'package:flutter/material.dart';
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show BorderRadius3d;
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Flutter default style of the first widget of type [T] in the tree.
///
/// `defaultStyleOf` is public and `@protected`: it is meant to be overridden
/// by a subclass rather than called from outside one. Calling it anyway is
/// deliberate and is the whole reason this file can be a drift alarm — the
/// alternative is transcribing `_FilledButtonDefaultsM3` by hand, which is
/// exactly the second copy these tests exist to avoid. One ignore is a small
/// price, and it is here rather than in `lib/`.
ButtonStyle defaultStyleOf<T extends ButtonStyleButton>(WidgetTester tester) {
  final element = tester.element(find.byType(T));
  // ignore: invalid_use_of_protected_member
  return (element.widget as ButtonStyleButton).defaultStyleOf(element);
}

/// The Flutter default style of Material 3's icon button, whose widget type is
/// private and therefore cannot be named.
ButtonStyle iconButtonStyle(WidgetTester tester) {
  for (final element in tester.allElements) {
    final widget = element.widget;
    // ignore: invalid_use_of_protected_member
    if (widget is ButtonStyleButton) return widget.defaultStyleOf(element);
  }
  throw StateError('no ButtonStyleButton under the IconButton');
}

/// Asserts two colours are the same **as drawn**, in ARGB32.
///
/// Not `expect(a, b)`, and the reason is a trap worth knowing at any boundary
/// with the framework. Flutter's disabled figures come from the deprecated
/// `Color.withOpacity`, which rounds to a byte: `onSurface.withOpacity(0.38)`
/// has alpha `97 / 255 = 0.380392…`. `ColorScheme3d` uses `withValues`, which
/// keeps the float, so its alpha is exactly `0.38`. The two are not `==` and
/// are the same colour everywhere it matters — the shader uniform, the frame
/// buffer, the render probe — so the comparison that means something is the
/// 32-bit one.
void expectSameColor(Color? ours, Color? flutter, {String? reason}) {
  expect(ours, isNotNull, reason: reason);
  expect(flutter, isNotNull, reason: reason);
  expect(ours!.toARGB32(), flutter!.toARGB32(), reason: reason);
}

Color? bg(ButtonStyle style, [Set<WidgetState> states = const {}]) =>
    style.backgroundColor?.resolve(states);

Color? fg(ButtonStyle style, [Set<WidgetState> states = const {}]) =>
    style.foregroundColor?.resolve(states);

void main() {
  const theme = Theme3dData.light;

  /// Pumps [child] inside a Material 3 app whose colour scheme is the one
  /// `ColorScheme3d.light` transcribes, and hands back nothing: the tests
  /// read the tree afterwards.
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(body: Center(child: child)),
    ),
  );

  group('the figures every variant shares', () {
    testWidgets('padding, minimum size, shape and type are Material\'s', (
      tester,
    ) async {
      await pump(
        tester,
        FilledButton(onPressed: () {}, child: const Text('x')),
      );
      final flutter = defaultStyleOf<FilledButton>(tester);
      final ours = ButtonStyle3d.of(theme, ButtonVariant3d.filled);

      final padding = flutter.padding!.resolve({}) as EdgeInsets;
      expect(ours.padding.left, padding.left);
      expect(ours.padding.right, padding.right);
      expect(ours.padding.top, padding.top);
      expect(ours.padding.bottom, padding.bottom);
      expect(
        ours.padding.front + ours.padding.back,
        0.0,
        reason: 'a depth inset would push the label inside the slab',
      );

      final minimum = flutter.minimumSize!.resolve({})!;
      expect(ours.minimumWidth, minimum.width);
      expect(ours.minimumHeight, minimum.height);
      expect(
        ours.minimumHeight,
        lessThan(48.0),
        reason: 'the 48dp target is reach, not extent — see the tap target',
      );

      expect(
        flutter.shape!.resolve({}),
        isA<StadiumBorder>(),
        reason: 'Material\'s `full` shape',
      );
      expect(ours.shape, theme.shape.full);

      final type = flutter.textStyle!.resolve({})!;
      final label = theme.typography.resolve(ours.labelStyle);
      expect(label.fontSize, type.fontSize);
      expect(label.fontWeight, type.fontWeight);
      expect(label.letterSpacing, type.letterSpacing);
      expect(ours.labelStyle, Typography3dToken.labelLarge);

      expect(ours.iconSize, flutter.iconSize!.resolve({}));
    });

    testWidgets('the surface tint is off, as Material turns it off', (
      tester,
    ) async {
      await pump(
        tester,
        FilledButton(onPressed: () {}, child: const Text('x')),
      );
      final flutter = defaultStyleOf<FilledButton>(tester);
      expect(
        flutter.surfaceTintColor!.resolve({})!.a,
        0.0,
        reason:
            'an elevated button\'s surfaceContainerLow is already the tinted '
            'colour, so tinting again double-counts — Button3d passes a '
            'transparent surfaceTint for this reason',
      );
    });
  });

  group('the container and content of each variant', () {
    testWidgets('filled is primary on onPrimary', (tester) async {
      await pump(
        tester,
        FilledButton(onPressed: () {}, child: const Text('x')),
      );
      final flutter = defaultStyleOf<FilledButton>(tester);
      final ours = ButtonStyle3d.of(theme, ButtonVariant3d.filled);
      expectSameColor(ours.container, bg(flutter));
      expectSameColor(ours.content, fg(flutter));
      expect(ours.container, theme.colorScheme.primary);
    });

    testWidgets('tonal is secondaryContainer on onSecondaryContainer', (
      tester,
    ) async {
      await pump(
        tester,
        FilledButton.tonal(onPressed: () {}, child: const Text('x')),
      );
      final flutter = defaultStyleOf<FilledButton>(tester);
      final ours = ButtonStyle3d.of(theme, ButtonVariant3d.filledTonal);
      expectSameColor(ours.container, bg(flutter));
      expectSameColor(ours.content, fg(flutter));
    });

    testWidgets('outlined is a transparent slab inside `outline`', (
      tester,
    ) async {
      await pump(
        tester,
        OutlinedButton(onPressed: () {}, child: const Text('x')),
      );
      final flutter = defaultStyleOf<OutlinedButton>(tester);
      final ours = ButtonStyle3d.of(theme, ButtonVariant3d.outlined);
      expect(ours.container.a, 0.0);
      expect(bg(flutter)!.a, 0.0);
      expectSameColor(ours.content, fg(flutter));
      expectSameColor(ours.outline, flutter.side!.resolve({})!.color);
      expect(ours.outlineWidth, flutter.side!.resolve({})!.width);
      expectSameColor(
        ours.focusedOutline,
        flutter.side!.resolve({WidgetState.focused})!.color,
        reason: 'the focus moves the border to primary, not only the wash',
      );
      expect(ours.focusedOutline, theme.colorScheme.primary);
    });

    testWidgets('text is a transparent slab and a tighter padding', (
      tester,
    ) async {
      await pump(tester, TextButton(onPressed: () {}, child: const Text('x')));
      final flutter = defaultStyleOf<TextButton>(tester);
      final ours = ButtonStyle3d.of(theme, ButtonVariant3d.text);
      expect(ours.container.a, 0.0);
      expectSameColor(ours.content, fg(flutter));
      expect(ours.outline, isNull);
      final padding = flutter.padding!.resolve({}) as EdgeInsets;
      expect(ours.padding.left, padding.left);
      expect(ours.padding.top, padding.top);
      expect(ours.padding.left, 12.0);
    });

    testWidgets('elevated rests at level 1 and rises to level 2', (
      tester,
    ) async {
      await pump(
        tester,
        ElevatedButton(onPressed: () {}, child: const Text('x')),
      );
      final flutter = defaultStyleOf<ElevatedButton>(tester);
      final ours = ButtonStyle3d.of(theme, ButtonVariant3d.elevated);
      expectSameColor(ours.container, bg(flutter));
      expectSameColor(ours.content, fg(flutter));
      expect(ours.elevation, flutter.elevation!.resolve({}));
      expect(
        ours.hoveredElevation,
        flutter.elevation!.resolve({WidgetState.hovered}),
      );
      expect(ours.elevation, theme.elevation.level1);
      expect(ours.hoveredElevation, theme.elevation.level2);
    });

    testWidgets('filled rises from level 0 to level 1 under a pointer', (
      tester,
    ) async {
      await pump(
        tester,
        FilledButton(onPressed: () {}, child: const Text('x')),
      );
      final flutter = defaultStyleOf<FilledButton>(tester);
      final ours = ButtonStyle3d.of(theme, ButtonVariant3d.filled);
      expect(ours.elevation, flutter.elevation!.resolve({}));
      expect(
        ours.hoveredElevation,
        flutter.elevation!.resolve({WidgetState.hovered}),
      );
      expect(
        flutter.elevation!.resolve({WidgetState.pressed}),
        ours.elevation,
        reason:
            'a press puts it back down, which is why resolve() asks for '
            '"hovered and not pressed"',
      );
    });

    testWidgets('the icon button is onSurfaceVariant on nothing, at 40dp', (
      tester,
    ) async {
      await pump(
        tester,
        IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
      );
      final flutter = iconButtonStyle(tester);
      final ours = ButtonStyle3d.of(theme, ButtonVariant3d.icon);
      expect(ours.container.a, 0.0);
      expectSameColor(ours.content, fg(flutter));
      expect(ours.content, theme.colorScheme.onSurfaceVariant);
      final minimum = flutter.minimumSize!.resolve({})!;
      expect(ours.minimumWidth, minimum.width);
      expect(ours.minimumHeight, minimum.height);
      final padding = flutter.padding!.resolve({}) as EdgeInsets;
      expect(ours.padding.left, padding.left);
      expect(ours.iconSize, flutter.iconSize!.resolve({}));
      expect(ours.iconSize, 24.0, reason: 'the icon *is* the button');
    });
  });

  group('the disabled table', () {
    testWidgets('every filled variant substitutes the same two colours', (
      tester,
    ) async {
      await pump(tester, const FilledButton(onPressed: null, child: Text('x')));
      final flutter = defaultStyleOf<FilledButton>(tester);
      const disabled = {WidgetState.disabled};
      final ours = ButtonStyle3d.of(
        theme,
        ButtonVariant3d.filled,
      ).resolve(const {}, enabled: false);

      expectSameColor(ours.container, bg(flutter, disabled));
      expectSameColor(ours.content, fg(flutter, disabled));
      expect(ours.container, theme.colorScheme.disabledContainer);
      expect(ours.content, theme.colorScheme.disabledContent);
      expect(
        ours.elevation,
        flutter.elevation!.resolve(disabled),
        reason: 'a disabled control does not float',
      );
      expect(ours.elevation, 0.0);
    });

    testWidgets('a disabled outlined button keeps a transparent slab', (
      tester,
    ) async {
      await pump(
        tester,
        const OutlinedButton(onPressed: null, child: Text('x')),
      );
      final flutter = defaultStyleOf<OutlinedButton>(tester);
      const disabled = {WidgetState.disabled};
      final ours = ButtonStyle3d.of(
        theme,
        ButtonVariant3d.outlined,
      ).resolve(const {}, enabled: false);

      expect(ours.container.a, 0.0);
      expect(bg(flutter, disabled)!.a, 0.0);
      expectSameColor(ours.content, fg(flutter, disabled));
      expectSameColor(
        ours.border.color,
        flutter.side!.resolve(disabled)!.color,
      );
      expect(
        ours.border.color,
        theme.colorScheme.disabledContainer,
        reason: 'the outline dims to the container figure, not the label one',
      );
    });

    test('the two disabled figures are Material\'s 12% and 38%', () {
      // Stated here in one place because they are the whole of the
      // substitution rule, and because a reader looking for "where is the 38%"
      // should find it beside the tests that check it against Flutter.
      expect(theme.colorScheme.disabledContent.a, closeTo(0.38, 0.005));
      expect(theme.colorScheme.disabledContainer.a, closeTo(0.12, 0.005));
      expect(
        theme.colorScheme.disabledContent.r,
        theme.colorScheme.onSurface.r,
      );
    });
  });

  group('the floating action button', () {
    // A transcription check, not a drift alarm — `_FABDefaultsM3` is private
    // and has no `defaultStyleOf`. What this can still do is read the
    // `Material` the framework builds and the size it renders at, which is
    // the framework's own output rather than a second copy of the spec.
    testWidgets('matches the Material a real FAB renders', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            floatingActionButton: FloatingActionButton(
              onPressed: () {},
              child: const Icon(Icons.add),
            ),
          ),
        ),
      );
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(FloatingActionButton),
              matching: find.byType(Material),
            )
            .first,
      );
      final ours = ButtonStyle3d.of(theme, ButtonVariant3d.floatingAction);

      expectSameColor(ours.container, material.color);
      expect(ours.container, theme.colorScheme.primaryContainer);
      expect(ours.content, theme.colorScheme.onPrimaryContainer);
      expect(ours.elevation, material.elevation);
      expect(
        ours.elevation,
        theme.elevation.level3,
        reason: 'M3 rests a FAB at level 3, which is 6dp — not "3"',
      );

      final shape = material.shape! as RoundedRectangleBorder;
      final radius = (shape.borderRadius.resolve(null)).topLeft.x;
      expect(ours.shape, BorderRadius3d.circular(radius));
      expect(ours.shape, theme.shape.large);

      final size = tester.getSize(find.byType(FloatingActionButton));
      expect(ours.minimumWidth, size.width);
      expect(ours.minimumHeight, size.height);
      expect(ours.padding.left * 2 + ours.iconSize, size.width);
    });

    test('it is a raised slab and it clears the theme\'s own depth step', () {
      final ours = ButtonStyle3d.of(theme, ButtonVariant3d.floatingAction);
      expect(ours.thickness, theme.thickness.raised);
      expect(
        ours.elevation + ours.thickness / 2.0,
        lessThan(theme.thickness.depthStep),
        reason:
            'a FAB reaches elevation + half its thickness in front of its own '
            'plane; past the step it would come through the layer above it',
      );
      expect(theme.thickness.separates(ours.thickness, ours.thickness), isTrue);
    });
  });
}
