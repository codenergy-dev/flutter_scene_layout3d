// The reader's font setting, met by the catalogue: which labels grow, which
// stop, and which do not grow at all — and a screen's worth of components
// that still fit at double-size type.
//
// The last group is the oracle this was written against. Before it, one
// component in the catalogue overflowed at a 1.3 setting, and the reason was
// two things at once: an icon that grew when Flutter's never does, and a bar
// whose padding left it four logical pixels to spare.

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/testing.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'surfaces_support.dart';

const double _dp = 0.01;

const List<NavigationDestination3d> _destinations = <NavigationDestination3d>[
  NavigationDestination3d(icon: Icon3d(Icons.inbox), label: 'Inbox'),
  NavigationDestination3d(icon: Icon3d(Icons.tune), label: 'Settings'),
];

/// [build] on an 8 by 6 surface under a platform font setting of [scale].
Future<Layout3dSurface> pumpAt(
  WidgetTester tester,
  double scale,
  Widget Function() build,
) async {
  final controller = Layout3dController();
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SceneLayout3d(
          parent: Node(),
          size: const Size3d(8, 6, 0.5),
          controller: controller,
          child: SceneTheme3d(data: Theme3dData.light, child: build()),
        ),
      ),
    ),
  );
  return controller.surface!;
}

Widget _atBottom(Widget bar) => SceneColumn3d(
  crossAxisAlignment: CrossAxisAlignment3d.stretch,
  children: <Widget>[
    const SceneExpanded3d(child: SceneSizedBox3d()),
    bar,
  ],
);

Widget _atTop(Widget bar) => SceneColumn3d(
  crossAxisAlignment: CrossAxisAlignment3d.stretch,
  children: <Widget>[
    bar,
    const SceneExpanded3d(child: SceneSizedBox3d()),
  ],
);

/// The label reading [text], wherever it is.
Text3d _label(Layout3dSurface surface, String text) =>
    boxesOf<Text3d>(surface).singleWhere((label) => label.data == text);

void main() {
  group('an icon', () {
    testWidgets('does not grow with type, as Flutter\'s does not', (
      tester,
    ) async {
      final plain = await pumpAt(
        tester,
        1.0,
        () => const SceneCenter3d(child: Icon3d(Icons.inbox)),
      );
      final height = oneOf<Text3d>(plain).size.height;
      final doubled = await pumpAt(
        tester,
        2.0,
        () => const SceneCenter3d(child: Icon3d(Icons.inbox)),
      );
      expect(oneOf<Text3d>(doubled).size.height, closeTo(height, 1e-9));
      expect(oneOf<Text3d>(doubled).textScaler, TextScaler.noScaling);
    });
  });

  group('a navigation bar', () {
    NavigationBar3d bar() => NavigationBar3d(
      destinations: _destinations,
      selectedIndex: 0,
      onDestinationSelected: (_) {},
    );

    testWidgets('grows its labels to 1.3 and no further', (tester) async {
      double labelHeight(Layout3dSurface s) => _label(s, 'Inbox').size.height;
      final plain = labelHeight(
        await pumpAt(tester, 1.0, () => _atBottom(bar())),
      );
      final grown = labelHeight(
        await pumpAt(tester, 1.2, () => _atBottom(bar())),
      );
      final capped = labelHeight(
        await pumpAt(tester, 3.0, () => _atBottom(bar())),
      );
      expect(grown / plain, closeTo(1.2, 1e-6), reason: 'under the ceiling');
      expect(
        capped / plain,
        closeTo(NavigationBar3d.maxLabelTextScaleFactor, 1e-6),
        reason: 'Flutter\'s _kMaxLabelTextScaleFactor',
      );
    });

    testWidgets('keeps its pill 14dp from the top, as padding used to', (
      tester,
    ) async {
      // The bar's vertical padding went, and the pill must not have moved:
      // 32 + 4 + 16 of content centred in 80 is 14dp down, which is what 12dp
      // of padding plus centring in the 56 left used to give.
      final surface = await pumpAt(tester, 1.0, () => _atBottom(bar()));
      final panel = boxesOf<DecoratedBox3d>(surface).first;
      final pill = boxesOf<DecoratedBox3d>(surface).firstWhere(
        (box) =>
            (box.decoration as BoxDecoration3d).color ==
            Theme3dData.light.colorScheme.secondaryContainer,
      );
      final down =
          (pill.drawnOffsetInSurface.y - panel.drawnOffsetInSurface.y) / _dp;
      expect(down, closeTo(14, 1e-3));
    });

    testWidgets('a rail\'s labels have no ceiling, as Flutter\'s have none', (
      tester,
    ) async {
      Widget rail() => SceneRow3d(
        crossAxisAlignment: CrossAxisAlignment3d.stretch,
        children: <Widget>[
          NavigationRail3d(
            destinations: _destinations,
            selectedIndex: 0,
            onDestinationSelected: (_) {},
          ),
          const SceneExpanded3d(child: SceneSizedBox3d()),
        ],
      );
      // Its scale rather than its height: at double size the test font's
      // square glyphs wrap 'Inbox' onto three lines of an 80dp rail.
      final plain = _label(
        await pumpAt(tester, 1.0, rail),
        'Inbox',
      ).logicalPixelScale;
      final doubled = _label(
        await pumpAt(tester, 2.0, rail),
        'Inbox',
      ).logicalPixelScale;
      expect(doubled / plain, closeTo(2.0, 1e-6));
    });
  });

  group('an app bar', () {
    testWidgets('grows its title to 1.34 and no further', (tester) async {
      Widget bar() => _atTop(AppBar3d.text(title: 'Inbox'));
      final plain = _label(await pumpAt(tester, 1.0, bar), 'Inbox').size.height;
      final capped = _label(
        await pumpAt(tester, 2.0, bar),
        'Inbox',
      ).size.height;
      expect(
        capped / plain,
        closeTo(AppBar3d.maxTitleTextScaleFactor, 1e-6),
        reason: 'Flutter\'s _kMaxTitleTextScaleFactor',
      );
    });
  });

  group('what still fits at a large setting', () {
    final cases = <String, Widget Function()>{
      'a filled button': () => SceneCenter3d(
        child: FilledButton3d(
          onPressed: () {},
          child: const SceneText3d('Save'),
        ),
      ),
      'a chip': () => SceneCenter3d(
        child: AssistChip3d(
          label: const SceneText3d('Track'),
          onPressed: () {},
        ),
      ),
      'a two-line tile': () => SceneCenter3d(
        child: ListTile3d.text(
          title: 'Inbox',
          subtitle: '12 unread',
          onTap: () {},
        ),
      ),
      'a checkbox tile': () => SceneCenter3d(
        child: CheckboxListTile3d.text(
          title: 'Remember me',
          value: true,
          onChanged: (_) {},
        ),
      ),
      'an app bar': () => _atTop(AppBar3d.text(title: 'Inbox')),
      'a navigation bar': () => _atBottom(
        NavigationBar3d(
          destinations: _destinations,
          selectedIndex: 0,
          onDestinationSelected: (_) {},
        ),
      ),
      'a menu': () => SceneCenter3d(
        child: Menu3d(
          children: <Widget>[MenuItem3d(label: 'Rename', onPressed: () {})],
        ),
      ),
      'an alert dialog': () => SceneCenter3d(
        child: AlertDialog3d.text(
          title: 'Delete?',
          content: 'Gone.',
          actions: <Widget>[
            TextButton3d(onPressed: () {}, child: const SceneText3d('OK')),
          ],
        ),
      ),
    };

    for (final scale in const <double>[1.3, 2.0]) {
      for (final MapEntry(key: name, value: build) in cases.entries) {
        testWidgets('$name at $scale', (tester) async {
          await pumpAt(tester, scale, build);
          expect(
            tester.takeException(),
            isNull,
            reason: 'an overflow is reported as an error here',
          );
        });
      }
    }
  });
}
