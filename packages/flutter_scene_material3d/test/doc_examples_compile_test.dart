// The README's worked examples, checked against the compiler.
//
// AGENTS.md's hard requirement for a README here is that it is faithful to
// what is actually implemented. Prose can be checked by reading; code cannot,
// and an example that no longer compiles is exactly the page that is worse
// than no page. So the examples live here too, verbatim, and the analyzer and
// the test runner keep them honest. Nothing below is called: compiling is the
// assertion.

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

// ------------------------------------------------------ The one call that
// makes anything draw.

Future<void> setUpApplication() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeMaterial3d();
}

// ------------------------------------------------------------- Material3d,
// and everything that is one.

Widget filledButton(Theme3dData theme, VoidCallback submit) => Material3d(
  color: theme.colorScheme.primary,
  contentColor: theme.colorScheme.onPrimary,
  shape: theme.shape.full,
  elevation: theme.elevation.level1,
  thickness: theme.thickness.standard,
  padding: const EdgeInsets3d.symmetric(horizontal: 24, vertical: 10),
  child: InkWell3d(onTap: submit, child: const SceneText3d('Continue')),
);

// -------------------------------------------------------------- Icons, and
// naming a type style instead of building one.

Widget icons(Theme3dData theme) => SceneTextStyle3d(
  style: Typography3dToken.titleMedium,
  color: theme.colorScheme.onSurfaceVariant,
  child: SceneColumn3d(
    children: <Widget>[
      const Icon3d(Icons.favorite, size: 24),
      SceneText3d(
        'Inbox',
        style: theme.textStyle(
          Typography3dToken.labelLarge,
          color: theme.colorScheme.onPrimary,
        ),
      ),
    ],
  ),
);

// ---------------------------------------------------------------- Getting a
// theme in place.

Widget screen(Node parent) => SceneLayout3d(
  parent: parent,
  size: const Size3d(4, 3, 0.5),
  child: SceneTheme3d(
    data: Theme3dData.dark,
    textRendererFactory: AtlasText3dRenderer.new,
    child: SceneCenter3d(
      child: Builder(
        builder: (context) {
          final theme = Theme3d.of(context);
          return Material3d(
            color: theme.colorScheme.primary,
            contentColor: theme.colorScheme.onPrimary,
            shape: theme.shape.full,
            elevation: theme.elevation.level1,
            padding: const EdgeInsets3d.symmetric(horizontal: 24, vertical: 10),
            textStyle: theme.textStyle(
              Typography3dToken.labelLarge,
              color: theme.colorScheme.onPrimary,
            ),
            child: InkWell3d(
              onTap: () => debugPrint('tapped'),
              child: const SceneText3d('Continue'),
            ),
          );
        },
      ),
    ),
  ),
);

// ------------------------------------------------------ A unit conversion in
// a build method.

Widget padded(Layout3dMetrics metrics, Widget child) => ScenePadding3d(
  padding: metrics.dpInsets(const EdgeInsets3d.all(16)),
  child: child,
);

// ------------------------------------------------------- The imperative-only
// spelling, and a box reading the theme.

Widget imperativelyThemed(Node parent, Widget screen) => SceneLayout3d(
  parent: parent,
  slots: {Theme3dData.slot: Theme3dData.dark}, // not a const map, see below
  child: screen,
);

class ThemedSlab extends Layout3d {
  @override
  void performLayout() {
    // The theme names a figure in logical pixels; the metrics says what a
    // logical pixel is worth here. Never the other way round.
    final depth = metrics.dp(theme3d.thickness.raised);
    size = constraints.constrain(
      Size3d(metrics.dp(120), metrics.dp(40), depth),
    );
  }
}

// --------------------------------------------------------- The two rules a
// thickness comes with.

void thicknessRules() {
  const thickness = Thickness3d.baseline; // 1, 2, 4, 8 on a 12dp step
  assert(thickness.separates(thickness.structural, thickness.raised));

  final theme = Theme3dData.light;
  BoxDecoration3d(
    borderRadius: theme.shape.medium, // 12dp face radius
    bevel: theme.shape.bevelFor(theme.thickness.raised), // 1dp rim
  );
}

void main() {
  test('the README examples compile', () {
    // They do, or this file would not have been compiled to run.
    expect(setUpApplication, isNotNull);
    expect(filledButton, isNotNull);
    expect(icons, isNotNull);
    expect(padded, isNotNull);
    expect(screen, isNotNull);
    expect(imperativelyThemed, isNotNull);
    expect(ThemedSlab.new, isNotNull);
    expect(thicknessRules, isNotNull);
  });
}
