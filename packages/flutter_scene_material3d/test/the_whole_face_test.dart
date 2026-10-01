// A control is pressable across its whole face, not only where its content is.
//
// Every interactive component here used to answer a press on its label and
// swallow one on its padding: the ink well sat *inside* the padding, so a ray
// through the rim of a button reached the button's panel — which answers a
// hit on its own account — and went no further. A floating action button
// answered only at its middle, a list tile not in its 16dp leading margin, a
// navigation destination not beside its pill. Nothing caught it, because
// every press in every suite was aimed at a control's centre; phase 4 of
// `the_components_a_screen_still_needs` found it pressing a bottom app bar's
// corner button through the camera, where a press lands on the rim.
//
// So these press each control a few logical pixels inside each edge of its
// own face — the panel it draws — and expect the press to count.

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'surfaces_support.dart';

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

/// A control, built around a callback that counts presses, and how to find
/// the face it is pressed on.
typedef _Case = ({
  Widget Function(void Function() pressed) build,
  bool centred,
  Layout3d Function(Layout3dSurface surface)? face,
});

Layout3d _labelled(Layout3dSurface surface, String label) =>
    boxesOf<Semantics3d>(
      surface,
    ).firstWhere((box) => box.properties.label == label);

void main() {
  final cases = <String, _Case>{
    'a filled button': (
      build: (pressed) => FilledButton3d(
        semanticLabel: 'Save',
        onPressed: pressed,
        child: const SceneText3d('Save'),
      ),
      centred: true,
      face: null,
    ),
    'an outlined button': (
      build: (pressed) => OutlinedButton3d(
        semanticLabel: 'Save',
        onPressed: pressed,
        child: const SceneText3d('Save'),
      ),
      centred: true,
      face: null,
    ),
    'an icon button': (
      build: (pressed) => IconButton3d(
        icon: Icons.search,
        semanticLabel: 'Search',
        onPressed: pressed,
      ),
      centred: true,
      face: null,
    ),
    'a floating action button': (
      build: (pressed) => FloatingActionButton3d(
        semanticLabel: 'Compose',
        onPressed: pressed,
        child: const Icon3d(Icons.edit),
      ),
      centred: true,
      face: null,
    ),
    'a filter chip': (
      build: (pressed) => FilterChip3d(
        label: const SceneText3d('Unread'),
        semanticLabel: 'Unread',
        selected: false,
        onSelected: (_) => pressed(),
      ),
      centred: true,
      face: null,
    ),
    'a list tile': (
      build: (pressed) => SceneSizedBox3d(
        width: 3,
        child: ListTile3d.text(title: 'Inbox', onTap: pressed),
      ),
      centred: true,
      face: null,
    ),
    'a switch tile': (
      build: (pressed) => SceneSizedBox3d(
        width: 3,
        child: SwitchListTile3d.text(
          title: 'Notifications',
          value: false,
          onChanged: (_) => pressed(),
        ),
      ),
      centred: true,
      face: null,
    ),
    'a navigation destination': (
      build: (pressed) => SceneColumn3d(
        crossAxisAlignment: CrossAxisAlignment3d.stretch,
        children: <Widget>[
          const SceneExpanded3d(child: SceneSizedBox3d()),
          NavigationBar3d(
            selectedIndex: 1,
            onDestinationSelected: (index) {
              if (index == 0) pressed();
            },
            destinations: const <NavigationDestination3d>[
              NavigationDestination3d(
                icon: Icon3d(Icons.inbox),
                label: 'Inbox',
              ),
              NavigationDestination3d(icon: Icon3d(Icons.send), label: 'Sent'),
            ],
          ),
        ],
      ),
      centred: false,
      face: (surface) => _labelled(surface, 'Inbox'),
    ),
    'a navigation drawer destination': (
      build: (pressed) => SceneRow3d(
        crossAxisAlignment: CrossAxisAlignment3d.stretch,
        children: <Widget>[
          NavigationDrawer3d(
            selectedIndex: 1,
            onDestinationSelected: (index) {
              if (index == 0) pressed();
            },
            children: const <Widget>[
              NavigationDrawerDestination3d(
                icon: Icon3d(Icons.inbox),
                label: 'Inbox',
              ),
              NavigationDrawerDestination3d(
                icon: Icon3d(Icons.send),
                label: 'Sent',
              ),
            ],
          ),
          const SceneExpanded3d(child: SceneSizedBox3d()),
        ],
      ),
      centred: false,
      face: (surface) => _labelled(surface, 'Inbox'),
    ),
    'an expansion tile': (
      build: (pressed) => SceneSizedBox3d(
        width: 3,
        child: ExpansionTile3d.text(
          title: 'Advanced',
          onExpansionChanged: (_) => pressed(),
        ),
      ),
      centred: true,
      face: (surface) => _labelled(surface, 'Advanced'),
    ),
  };

  for (final MapEntry(key: name, value: control) in cases.entries) {
    testWidgets('$name answers a press at every edge of its face', (
      tester,
    ) async {
      var presses = 0;
      final pumped = await pumpComponent(
        tester,
        () => control.build(() => presses++),
        centred: control.centred,
      );
      final face = control.face?.call(pumped.surface) ?? pumped.panels.first;
      final at = _origin(face);
      final size = face.size;
      // Three logical pixels in from each edge, along the middle of the
      // other axis: on the rim, which is where the padding is.
      const inset = 0.03;
      final aims = <String, Offset3d>{
        'leading': Offset3d(at.x + inset, at.y + size.height / 2, 0),
        'trailing': Offset3d(
          at.x + size.width - inset,
          at.y + size.height / 2,
          0,
        ),
        'top': Offset3d(at.x + size.width / 2, at.y + inset, 0),
        'bottom': Offset3d(
          at.x + size.width / 2,
          at.y + size.height - inset,
          0,
        ),
      };
      for (final MapEntry(key: edge, value: aim) in aims.entries) {
        final before = presses;
        pumped.pointer.down(rayAt(pumped.surface, aim));
        pumped.pointer.up();
        await tester.pumpAndSettle();
        expect(presses, before + 1, reason: 'a press at its $edge edge');
      }
    });
  }
}
