// The app bar's figures, against Flutter's own.
//
// The standard phase 3 set and phase 4 refined: check a figure against
// Flutter where Flutter can be asked, and where it cannot, transcribe it and
// say in the test that it is a transcription. This component hit a third
// case nobody had met yet — Flutter has **two** answers and they disagree —
// and the test's job there is to pin both so the next reader meets the
// discrepancy here rather than against a ruler.

import 'package:flutter/material.dart' as m;
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

const Theme3dData _theme = Theme3dData.light;

void main() {
  group('the toolbar height, where Flutter contradicts itself', () {
    testWidgets('a real M3 AppBar lays out at kToolbarHeight, which is 56', (
      tester,
    ) async {
      // Flutter's build method resolves
      //   widget.toolbarHeight ?? appBarTheme.toolbarHeight ?? kToolbarHeight
      // and `AppBarTheme.of(context)` is the *application's* overrides, empty
      // by default — so the 64 in `_AppBarDefaultsM3` is never reached by a
      // plain AppBar and a real one is 56 tall.
      await tester.pumpWidget(
        m.MaterialApp(
          theme: m.ThemeData(useMaterial3: true),
          home: m.Scaffold(appBar: m.AppBar(title: const m.Text('Inbox'))),
        ),
      );
      expect(m.kToolbarHeight, 56.0);
      expect(tester.getSize(find.byType(m.AppBar)).height, m.kToolbarHeight);
    });

    test('and this package takes 64, which is the M3 token', () {
      // `_AppBarDefaultsM3.toolbarHeight` is 64, and it is the height
      // `AppBar.medium` and `AppBar.large` collapse to
      // (`_MediumScrollUnderFlexibleConfig.collapsedHeight`), so 64 is the
      // figure Material 3 actually specifies. A transcription, and this test
      // is where it is written down as one.
      expect(AppBarStyle3d.defaultToolbarHeight, 64.0);
      expect(
        AppBarStyle3d.of(_theme, AppBarVariant3d.small).toolbarHeight,
        64.0,
      );
      expect(
        AppBarStyle3d.of(_theme, AppBarVariant3d.large).toolbarHeight,
        64.0,
      );
    });
  });

  group('the figures that are transcriptions, stated as such', () {
    test('the medium and large expanded heights', () {
      // `_MediumScrollUnderFlexibleConfig.expandedHeight` and its large
      // sibling, both private. Transcribed.
      expect(AppBarStyle3d.mediumExpandedHeight, 112.0);
      expect(AppBarStyle3d.largeExpandedHeight, 152.0);
    });

    test('the scrolled-under elevation', () {
      // `_AppBarDefaultsM3.scrolledUnderElevation`, private. Transcribed.
      expect(AppBarStyle3d.defaultScrolledUnderElevation, 3.0);
    });
  });

  group('the figures Flutter publishes', () {
    test('the title spacing is NavigationToolbar.kMiddleSpacing', () {
      // Public, and read rather than transcribed: the one figure in this
      // component that is a genuine drift alarm.
      expect(
        AppBarStyle3d.defaultTitleSpacing,
        m.NavigationToolbar.kMiddleSpacing,
      );
    });
  });

  group('the colours, which are roles rather than figures', () {
    test('a bar is surface on onSurface, untinted', () {
      // `_AppBarDefaultsM3` resolves backgroundColor to `surface`,
      // foregroundColor to `onSurface` and surfaceTintColor to transparent.
      // The first two are asserted against this package's own scheme, which
      // is the same M3 role table; the third is the phase-4 finding applied
      // — a container token that already encodes the elevation does not want
      // a tint on top of it.
      final style = AppBarStyle3d.of(_theme, AppBarVariant3d.small);
      expect(style.container, _theme.colorScheme.surface);
      expect(style.contentColor, _theme.colorScheme.onSurface);
      expect(style.elevation, 0.0);
    });

    test('and the title is titleLarge, growing with the bar', () {
      // `_AppBarDefaultsM3.titleTextStyle` is `titleLarge`; the two
      // expanding bars take `headlineSmall` and `headlineMedium` from their
      // flexible-space configs.
      expect(
        AppBarStyle3d.of(_theme, AppBarVariant3d.small).titleStyle,
        Typography3dToken.titleLarge,
      );
      expect(
        AppBarStyle3d.of(_theme, AppBarVariant3d.medium).expandedTitleStyle,
        Typography3dToken.headlineSmall,
      );
      expect(
        AppBarStyle3d.of(_theme, AppBarVariant3d.large).expandedTitleStyle,
        Typography3dToken.headlineMedium,
      );
    });
  });
}
