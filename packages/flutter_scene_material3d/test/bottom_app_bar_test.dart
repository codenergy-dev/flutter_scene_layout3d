// BottomAppBar3d: its height and role, the safe area, and a screen whose bar
// can be pressed.

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart' show Builder, Widget;
import 'package:flutter_scene_layout3d/testing.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart' show SceneTestBox, TestBox;
import 'surfaces_support.dart';

const Theme3dData _theme = Theme3dData.light;
const double _dp = 0.01;

/// A bar at the foot of a screen-shaped column; see `app_bar_test.dart` for
/// why a bar cannot be pumped straight onto a surface.
Widget _atFoot(Widget bar) => SceneColumn3d(
  crossAxisAlignment: CrossAxisAlignment3d.stretch,
  children: <Widget>[
    const SceneExpanded3d(child: SceneSizedBox3d()),
    bar,
  ],
);

/// [child], told the surface has spent [padding].
Widget _spent(EdgeInsets3d padding, Widget child) => Builder(
  builder: (context) => MediaQuery3d(
    data: MediaQuery3d.of(context).copyWith(padding: padding),
    child: child,
  ),
);

/// Where [box]'s origin is in [ancestor]'s frame.
Offset3d _originIn(Layout3d box, Layout3d ancestor) {
  var at = Offset3d.zero;
  Layout3d? walk = box;
  while (walk != null && !identical(walk, ancestor)) {
    at += walk.offset;
    walk = walk.parent;
  }
  return at;
}

void main() {
  test('the tokens are Flutter\'s Material 3 bar', () {
    final style = BottomAppBarStyle3d.of(_theme);
    expect(style.container, _theme.colorScheme.surfaceContainer);
    expect(style.height, 80.0);
    expect(style.elevation, _theme.elevation.level2);
    expect(style.thickness, _theme.thickness.structural);
    expect(
      style.padding,
      const EdgeInsets3d.symmetric(vertical: 12, horizontal: 16),
    );
  });

  testWidgets('is 80dp of surfaceContainer, a structural slab at level 2', (
    tester,
  ) async {
    final pumped = await pumpComponent(
      tester,
      () => _atFoot(const BottomAppBar3d()),
      centred: false,
    );
    final bar = pumped.panel;
    expect(bar.size.height, closeTo(80 * _dp, 1e-9));
    expect(bar.size.width, closeTo(4.0, 1e-9));
    expect(bar.size.depth, closeTo(_theme.thickness.structural * _dp, 1e-9));
    final decoration = bar.decoration as BoxDecoration3d;
    expect(decoration.color, _theme.colorScheme.surfaceContainer);
    expect(decoration.elevation, _theme.elevation.level2);
  });

  testWidgets('holds its child 16dp in and 12dp down', (tester) async {
    late TestBox held;
    final pumped = await pumpComponent(
      tester,
      () => _atFoot(
        BottomAppBar3d(
          child: SceneTestBox(
            const Size3d(double.infinity, double.infinity, 0),
            (box) => held = box,
          ),
        ),
      ),
      centred: false,
    );
    final at = _originIn(held, pumped.panel);
    expect(at.x, closeTo(16 * _dp, 1e-9));
    expect(at.y, closeTo(12 * _dp, 1e-9));
    expect(held.size.height, closeTo(56 * _dp, 1e-9));
    expect(held.size.width, closeTo(4.0 - 32 * _dp, 1e-9));
  });

  testWidgets('grows by the home indicator and keeps its child clear of it', (
    tester,
  ) async {
    late TestBox held;
    final pumped = await pumpComponent(
      tester,
      () => _spent(
        const EdgeInsets3d.only(bottom: 34),
        _atFoot(
          BottomAppBar3d(
            child: SceneTestBox(
              const Size3d(double.infinity, double.infinity, 0),
              (box) => held = box,
            ),
          ),
        ),
      ),
      centred: false,
    );
    expect(pumped.panel.size.height, closeTo((80 + 34) * _dp, 1e-9));
    expect(held.size.height, closeTo(56 * _dp, 1e-9));
    expect(_originIn(held, pumped.panel).y, closeTo(12 * _dp, 1e-9));
  });

  testWidgets('in a scaffold, its buttons can be pressed', (tester) async {
    var searched = 0;
    await tester.pumpSurface3d(
      SceneTheme3d(
        data: _theme,
        child: Scaffold3d(
          body: const SceneSizedBox3d(),
          bottomNavigationBar: BottomAppBar3d(
            child: SceneRow3d(
              children: <Widget>[
                IconButton3d(
                  icon: Icons.search,
                  semanticLabel: 'Search',
                  onPressed: () => searched++,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find3d.bySemanticsLabel('Search'), isReachable3d);
    await tester.tap3d(find3d.bySemanticsLabel('Search'));
    await tester.pumpAndSettle();
    expect(searched, 1);
  });

  testWidgets('announces nothing of its own', (tester) async {
    final pumped = await pumpComponent(
      tester,
      () => _atFoot(const BottomAppBar3d()),
      centred: false,
    );
    expect(boxesOf<Semantics3d>(pumped.surface), isEmpty);
  });
}
