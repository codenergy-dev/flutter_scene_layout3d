// The README's worked examples, checked against the compiler.
//
// AGENTS.md's hard requirement for a README here is that it is faithful to
// what is actually implemented. Prose can be checked by reading; code cannot,
// and an example that no longer compiles is exactly the page that is worse
// than no page. So the examples live here too, verbatim, and the analyzer and
// the test runner keep them honest. Nothing below is called: compiling is the
// assertion.

import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------- Getting a
// theme in place.

/// A themed panel, which is roughly what `Material3d` will be.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    final thickness = theme.thickness.raised;
    return SceneDecoratedBox3d(
      decoration: BoxDecoration3d(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: theme.shape.medium,
        bevel: theme.shape.bevelFor(thickness),
        elevation: theme.elevation.level1,
        surfaceTint: theme.colorScheme.surfaceTint,
      ),
      child: child,
    );
  }
}

Widget screen(Node parent) => SceneLayout3d(
  parent: parent,
  size: const Size3d(4, 3, 0.5),
  child: SceneTheme3d(
    data: Theme3dData.dark,
    textRendererFactory: AtlasText3dRenderer.new,
    child: ScenePadding3d(
      // World units, not logical pixels: 0.16 units is 16dp at the default
      // rate. See "Two units, side by side" below — this is the one figure
      // in the example the theme does not convert for you.
      padding: const EdgeInsets3d.all(0.16),
      child: Panel(
        child: SceneText3d(
          'Continue',
          style: Theme3dData.dark.typography.labelLarge.copyWith(
            color: Theme3dData.dark.colorScheme.onSurface,
          ),
        ),
      ),
    ),
  ),
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
    expect(screen, isNotNull);
    expect(imperativelyThemed, isNotNull);
    expect(ThemedSlab.new, isNotNull);
    expect(thicknessRules, isNotNull);
    expect(const Panel(child: SizedBox.shrink()), isNotNull);
  });
}
