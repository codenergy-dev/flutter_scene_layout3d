// Drawer3d, NavigationDrawer3d and showDrawer3d: the surface, the numbered
// destinations, and the route that slides one in from the edge reading
// starts at.

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart' show TextDirection, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/testing.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'overlays_support.dart';

const Theme3dData _theme = Theme3dData.light;
const double _dp = 0.01;

/// Where [box]'s origin is on the surface.
Offset3d _origin(Layout3d box) {
  var at = Offset3d.zero;
  Layout3d? walk = box;
  while (walk != null) {
    at += walk.offset;
    walk = walk.parent;
  }
  return at;
}

/// The drawer's own panel: the one in its container colour.
DecoratedBox3d _drawerPanel(Layout3dSurface surface) =>
    boxesOf<DecoratedBox3d>(surface).firstWhere(
      (box) =>
          (box.decoration as BoxDecoration3d).color ==
          _theme.colorScheme.surfaceContainerLow,
    );

Semantics3d _labelled(Layout3dSurface surface, String label) =>
    boxesOf<Semantics3d>(
      surface,
    ).firstWhere((box) => box.properties.label == label);

/// The panel a destination draws: the one under its announcement.
DecoratedBox3d _destinationPanel(Layout3dSurface surface, String label) {
  final found = <DecoratedBox3d>[];
  void walk(Layout3d box) {
    if (box is DecoratedBox3d) found.add(box);
    box.visitChildren(walk);
  }

  _labelled(surface, label).visitChildren(walk);
  return found.first;
}

/// A drawer standing beside a body, as Material's standard drawer does.
Widget _beside(Widget drawer) => SceneRow3d(
  crossAxisAlignment: CrossAxisAlignment3d.stretch,
  children: <Widget>[
    drawer,
    const SceneExpanded3d(child: SceneSizedBox3d()),
  ],
);

List<Widget> _mail() => const <Widget>[
  SceneText3d('Mail'),
  NavigationDrawerDestination3d(icon: Icon3d(Icons.inbox), label: 'Inbox'),
  NavigationDrawerDestination3d(icon: Icon3d(Icons.send), label: 'Sent'),
  Divider3d(),
  NavigationDrawerDestination3d(icon: Icon3d(Icons.delete), label: 'Trash'),
];

void main() {
  group('the tokens', () {
    test('the surface is Flutter\'s drawer', () {
      final style = DrawerStyle3d.of(_theme);
      expect(style.container, _theme.colorScheme.surfaceContainerLow);
      expect(style.width, 304.0);
      expect(style.cornerRadius, 16.0);
      expect(style.elevation, _theme.elevation.level1);
      expect(style.thickness, _theme.thickness.structural);
      // `Colors.black54`, Flutter's drawer scrim, not Material's 32%.
      expect(style.scrimColor.a, closeTo(0x8A / 0xFF, 1e-6));
      expect(style.arrival.duration, _theme.motion.medium1);
    });

    test('the destinations are Flutter\'s navigation drawer', () {
      final style = NavigationDrawerStyle3d.of(_theme);
      expect(style.indicatorColor, _theme.colorScheme.secondaryContainer);
      expect(style.indicatorShape, _theme.shape.full);
      expect(style.contentColor, _theme.colorScheme.onSurfaceVariant);
      expect(
        style.selectedContentColor,
        _theme.colorScheme.onSecondaryContainer,
      );
      expect(style.labelStyle, Typography3dToken.labelLarge);
      expect(style.tileHeight, 56.0);
      expect(style.iconInset, 16.0);
      expect(style.labelGap, 12.0);
    });
  });

  group('Drawer3d', () {
    testWidgets('is 304dp wide and as tall as its room', (tester) async {
      final pumped = await pumpOverlay(
        tester,
        child: _beside(const Drawer3d(semanticLabel: 'Menu')),
      );
      final panel = _drawerPanel(pumped.surface);
      expect(panel.size.width, closeTo(304 * _dp, 1e-9));
      expect(panel.size.height, closeTo(6.0, 1e-9));
      expect(
        panel.size.depth,
        closeTo(_theme.thickness.structural * _dp, 1e-9),
      );
      final decoration = panel.decoration as BoxDecoration3d;
      expect(decoration.elevation, _theme.elevation.level1);
    });

    testWidgets('rounds its end side, which is the left in right to left', (
      tester,
    ) async {
      final ltr = await pumpOverlay(tester, child: _beside(const Drawer3d()));
      expect(
        (_drawerPanel(ltr.surface).decoration as BoxDecoration3d).borderRadius,
        const BorderRadius3d.horizontal(right: 16),
      );
      final rtl = await pumpOverlay(
        tester,
        child: _beside(const Drawer3d()),
        textDirection: TextDirection.rtl,
      );
      expect(
        (_drawerPanel(rtl.surface).decoration as BoxDecoration3d).borderRadius,
        const BorderRadius3d.horizontal(left: 16),
      );
    });

    testWidgets('names its route', (tester) async {
      final pumped = await pumpOverlay(
        tester,
        child: _beside(const Drawer3d(semanticLabel: 'Menu')),
      );
      final named = _labelled(pumped.surface, 'Menu');
      expect(named.properties.scopesRoute, isTrue);
      expect(named.properties.namesRoute, isTrue);
    });
  });

  group('NavigationDrawer3d', () {
    testWidgets('numbers its destinations past a heading and a divider', (
      tester,
    ) async {
      final chosen = <int>[];
      final pumped = await pumpOverlay(
        tester,
        child: _beside(
          NavigationDrawer3d(
            selectedIndex: 2,
            onDestinationSelected: chosen.add,
            children: _mail(),
          ),
        ),
      );
      // The third destination is the selected one, though it is the fifth
      // child: the heading and the divider are not counted.
      expect(_labelled(pumped.surface, 'Trash').properties.selected, isTrue);
      expect(_labelled(pumped.surface, 'Inbox').properties.selected, isFalse);
      expect(
        (_destinationPanel(pumped.surface, 'Trash').decoration
                as BoxDecoration3d)
            .color,
        _theme.colorScheme.secondaryContainer,
      );
      expect(
        (_destinationPanel(pumped.surface, 'Inbox').decoration
                as BoxDecoration3d)
            .color
            .a,
        0.0,
      );

      final sent = _labelled(pumped.surface, 'Sent');
      final at = _origin(sent);
      pumped.pointer.down(
        rayAt(
          pumped.surface,
          Offset3d(at.x + sent.size.width / 2, at.y + sent.size.height / 2, 0),
        ),
      );
      pumped.pointer.up();
      await tester.pump();
      expect(chosen, <int>[1]);
    });

    testWidgets('its destinations stand on the drawer\'s face, not in it', (
      tester,
    ) async {
      // A list centres its items in depth unless it is told otherwise, and a
      // drawer is an 8dp slab: centred, every destination sat 3.5dp behind
      // the face that hid it. Only the photograph said so — the drawer drew
      // its header and an inbox badge and nothing else.
      await tester.pumpSurface3d(
        SceneTheme3d(
          data: _theme,
          child: SceneOverlay3d(
            child: _beside(NavigationDrawer3d(children: _mail())),
          ),
        ),
      );
      for (final label in <String>['Inbox', 'Sent', 'Trash']) {
        expect(find3d.bySemanticsLabel(label), standsOnItsPanel3d);
        expect(find3d.bySemanticsLabel(label), isReachable3d);
      }
      expect(find3d.bySubtype<Text3d>(), standsOnItsPanel3d);
    });

    testWidgets('a destination is a 56dp stadium 12dp inside the drawer', (
      tester,
    ) async {
      final pumped = await pumpOverlay(
        tester,
        child: _beside(NavigationDrawer3d(children: _mail())),
      );
      final panel = _destinationPanel(pumped.surface, 'Inbox');
      expect(panel.size.height, closeTo(56 * _dp, 1e-9));
      expect(panel.size.width, closeTo(280 * _dp, 1e-9));
      expect(_origin(panel).x, closeTo(12 * _dp, 1e-9));
      expect(
        (panel.decoration as BoxDecoration3d).borderRadius,
        _theme.shape.full,
      );
      // And a slab of its own, so its wash is its own.
      expect(panel.size.depth, closeTo(_theme.thickness.thin * _dp, 1e-9));
    });

    testWidgets('the label is labelLarge, in the selected colour', (
      tester,
    ) async {
      final pumped = await pumpOverlay(
        tester,
        child: _beside(NavigationDrawer3d(children: _mail())),
      );
      final inbox = boxesOf<Text3d>(
        pumped.surface,
      ).singleWhere((box) => box.data == 'Inbox');
      final large = _theme.textStyle(Typography3dToken.labelLarge);
      expect(inbox.style.fontSize, large.fontSize);
      expect(inbox.style.color, _theme.colorScheme.onSecondaryContainer);
      final sent = boxesOf<Text3d>(
        pumped.surface,
      ).singleWhere((box) => box.data == 'Sent');
      expect(sent.style.color, _theme.colorScheme.onSurfaceVariant);
    });

    testWidgets('a disabled destination answers nothing', (tester) async {
      final chosen = <int>[];
      final pumped = await pumpOverlay(
        tester,
        child: _beside(
          NavigationDrawer3d(
            onDestinationSelected: chosen.add,
            children: const <Widget>[
              NavigationDrawerDestination3d(
                icon: Icon3d(Icons.inbox),
                label: 'Inbox',
              ),
              NavigationDrawerDestination3d(
                icon: Icon3d(Icons.send),
                label: 'Sent',
                enabled: false,
              ),
            ],
          ),
        ),
      );
      final sent = _labelled(pumped.surface, 'Sent');
      expect(sent.properties.enabled, isFalse);
      final at = _origin(sent);
      pumped.pointer.down(
        rayAt(
          pumped.surface,
          Offset3d(at.x + sent.size.width / 2, at.y + sent.size.height / 2, 0),
        ),
      );
      pumped.pointer.up();
      await tester.pump();
      expect(chosen, isEmpty);
    });

    testWidgets('a destination outside a drawer is refused', (tester) async {
      await pumpOverlay(
        tester,
        child: const NavigationDrawerDestination3d(
          icon: Icon3d(Icons.inbox),
          label: 'Inbox',
        ),
      );
      expect(tester.takeException(), isAssertionError);
    });
  });

  group('showDrawer3d', () {
    Future<Future<String?>> open(
      WidgetTester tester,
      PumpedOverlay pumped, {
      DrawerAlignment3d alignment = DrawerAlignment3d.start,
    }) async {
      final result = showDrawer3d<String>(
        context: pumped.context,
        alignment: alignment,
        builder: (context) =>
            NavigationDrawer3d(semanticLabel: 'Mail', children: _mail()),
      );
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('slides in at the left, over a scrim, and a tap outside '
        'closes it', (tester) async {
      final pumped = await pumpOverlay(tester);
      final result = await open(tester, pumped);

      final panel = _drawerPanel(pumped.surface);
      expect(_origin(panel).x, closeTo(0.0, 1e-9));
      expect(panel.size.height, closeTo(6.0, 1e-9));
      expect(scrimCoverageOf(pumped.surface), closeTo(0x8A / 0xFF, 1e-6));
      // The start drawer rounds its right side.
      expect(
        (panel.decoration as BoxDecoration3d).borderRadius,
        const BorderRadius3d.horizontal(right: 16),
      );

      // Past the drawer, on the scrim.
      pumped.pointer.down(rayAt(pumped.surface, const Offset3d(6, 3, 0)));
      pumped.pointer.up();
      await tester.pumpAndSettle();
      expect(await result, isNull);
      expect(pumped.overlay.entries, isEmpty);
    });

    testWidgets('arrives from off the left edge', (tester) async {
      final pumped = await pumpOverlay(tester);
      showDrawer3d<void>(
        context: pumped.context,
        builder: (context) => const Drawer3d(semanticLabel: 'Menu'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final motion = boxesOf<MotionTransition3d>(pumped.surface).single;
      expect(motion.nodeOffset.x, lessThan(0.0));
      await tester.pumpAndSettle();
      expect(motion.nodeOffset.x, 0.0);
    });

    testWidgets('comes from the right in right to left, and Escape closes '
        'it', (tester) async {
      final pumped = await pumpOverlay(
        tester,
        textDirection: TextDirection.rtl,
      );
      final result = await open(tester, pumped);
      final panel = _drawerPanel(pumped.surface);
      expect(
        _origin(panel).x + panel.size.width,
        closeTo(8.0, 1e-9),
        reason: 'against the right edge',
      );
      expect(
        (panel.decoration as BoxDecoration3d).borderRadius,
        const BorderRadius3d.horizontal(left: 16),
      );

      expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isTrue);
      await tester.pumpAndSettle();
      expect(await result, isNull);
      expect(pumped.overlay.entries, isEmpty);
    });

    testWidgets('an end drawer is on the right in left to right', (
      tester,
    ) async {
      final pumped = await pumpOverlay(tester);
      await open(tester, pumped, alignment: DrawerAlignment3d.end);
      final panel = _drawerPanel(pumped.surface);
      expect(_origin(panel).x + panel.size.width, closeTo(8.0, 1e-9));
      expect(
        (panel.decoration as BoxDecoration3d).borderRadius,
        const BorderRadius3d.horizontal(left: 16),
      );
    });

    testWidgets('returns what it is popped with', (tester) async {
      final pumped = await pumpOverlay(tester);
      final result = await open(tester, pumped);
      Navigator3d.of(pumped.overlay)!.pop('Sent');
      await tester.pumpAndSettle();
      expect(await result, 'Sent');
    });
  });
}
