// Every announcement carries a reading direction.
//
// `SemanticsData` asserts that a non-empty label, value or hint has a
// `textDirection`, and the assert fires inside
// `PipelineOwner.flushSemantics` — which a headless `flutter test` never runs,
// and a screen reader or an integration test runs on every frame. So a
// catalogue that left the direction null looked correct in 488 tests and could
// not draw a single frame of the gallery with a `Checkbox3d` on it.
//
// These are the tests that stop it coming back. They ask the published
// properties directly, which is the only place the answer exists headlessly.

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart'
    show Directionality, TextDirection, Widget;
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'surfaces_support.dart';

/// Every direction published by a box that also publishes a label.
List<TextDirection?> directionsIn(Layout3dSurface surface) => <TextDirection?>[
  for (final box in boxesOf<Semantics3d>(surface))
    if (box.properties.label?.isNotEmpty ?? false) box.properties.textDirection,
];

void main() {
  final components = <String, Widget Function()>{
    'Checkbox3d': () =>
        Checkbox3d(value: true, semanticLabel: 'Star', onChanged: (_) {}),
    'Switch3d': () =>
        Switch3d(value: true, semanticLabel: 'Notify', onChanged: (_) {}),
    'Slider3d': () =>
        Slider3d(value: 0.5, semanticLabel: 'Volume', onChanged: (_) {}),
    'Radio3d': () => Radio3d<int>(
      value: 1,
      groupValue: 1,
      semanticLabel: 'One',
      onChanged: (_) {},
    ),
    'FilledButton3d': () => FilledButton3d(
      semanticLabel: 'Save',
      onPressed: () {},
      child: const SceneText3d('Save'),
    ),
    'IconButton3d': () => IconButton3d(
      icon: Icons.search,
      semanticLabel: 'Search',
      onPressed: () {},
    ),
    'Icon3d': () => const Icon3d(Icons.edit, semanticLabel: 'Compose'),
    'Card3d': () => const Card3d(semanticLabel: 'A card'),
    'ListTile3d': () =>
        const ListTile3d(title: SceneText3d('Row'), semanticLabel: 'Row'),
    'Chip3d': () =>
        const Chip3d(label: SceneText3d('All'), semanticLabel: 'All'),
    'Divider3d': () => const Divider3d(semanticLabel: 'Section break'),
    'AppBar3d': () => AppBar3d.text(title: 'Inbox'),
    'NavigationBar3d': () => const NavigationBar3d(
      selectedIndex: 0,
      destinations: <NavigationDestination3d>[
        NavigationDestination3d(icon: Icon3d(Icons.inbox), label: 'Inbox'),
        NavigationDestination3d(icon: Icon3d(Icons.send), label: 'Sent'),
      ],
    ),
  };

  group('a label is never published without a direction', () {
    components.forEach((name, build) {
      testWidgets(name, (tester) async {
        final pumped = await pumpComponent(tester, build, centred: false);
        final directions = directionsIn(pumped.surface);
        expect(directions, isNotEmpty, reason: '$name announces nothing');
        expect(
          directions,
          everyElement(isNotNull),
          reason:
              '$name published a label with a null textDirection, which '
              'asserts in flushSemantics the moment semantics are on',
        );
      });
    });
  });

  testWidgets('and the direction comes from the enclosing Directionality', (
    tester,
  ) async {
    final pumped = await pumpComponent(
      tester,
      () => Directionality(
        textDirection: TextDirection.rtl,
        child: Checkbox3d(
          value: true,
          semanticLabel: 'Star',
          onChanged: (_) {},
        ),
      ),
      centred: false,
    );
    expect(directionsIn(pumped.surface), <TextDirection>[TextDirection.rtl]);
  });

  testWidgets('with an explicit direction winning over both', (tester) async {
    final pumped = await pumpComponent(
      tester,
      () => Directionality(
        textDirection: TextDirection.rtl,
        child: Checkbox3d(
          value: true,
          semanticLabel: 'Star',
          textDirection: TextDirection.ltr,
          onChanged: (_) {},
        ),
      ),
      centred: false,
    );
    expect(directionsIn(pumped.surface), <TextDirection>[TextDirection.ltr]);
  });
}
