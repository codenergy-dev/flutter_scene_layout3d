// The safe area, spent by the catalogue: an app bar that runs up under the
// status bar, a navigation bar that grows over the home indicator, a rail
// that clears the notch, and a scaffold that takes from the body what its
// bars already took.
//
// Every test states its own insets through `MediaQuery3d`, which is how a
// panel set in a bezel states them too. On a surface that does not stand in
// for the view they are zero, and the rest of this suite is the proof that
// nothing moves then.

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart' show Builder, TextDirection, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/testing.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'surfaces_support.dart';

const double _dp = 0.01;
const double _tol = 1e-3;

/// A phone in portrait: a status bar, a home indicator, and nothing at the
/// sides.
const EdgeInsets3d _phone = EdgeInsets3d.only(top: 44, bottom: 34);

/// A phone on its side: the notch on the left, the indicator at the bottom.
const EdgeInsets3d _landscape = EdgeInsets3d.only(left: 48, bottom: 21);

const List<NavigationDestination3d> _destinations = <NavigationDestination3d>[
  NavigationDestination3d(icon: Icon3d(Icons.inbox), label: 'Inbox'),
  NavigationDestination3d(icon: Icon3d(Icons.tune), label: 'Settings'),
];

/// [child], told the surface has spent [padding].
Widget _spent(EdgeInsets3d padding, Widget child) => Builder(
  builder: (context) => MediaQuery3d(
    data: MediaQuery3d.of(context).copyWith(padding: padding),
    child: child,
  ),
);

Widget _atTop(Widget bar) => SceneColumn3d(
  crossAxisAlignment: CrossAxisAlignment3d.stretch,
  children: <Widget>[
    bar,
    const SceneExpanded3d(child: SceneSizedBox3d()),
  ],
);

Widget _atBottom(Widget bar) => SceneColumn3d(
  crossAxisAlignment: CrossAxisAlignment3d.stretch,
  children: <Widget>[
    const SceneExpanded3d(child: SceneSizedBox3d()),
    bar,
  ],
);

/// Where [box] starts and how big it is, in logical pixels from the surface.
({double left, double top, double right, double bottom}) _edges(
  PumpedSurface it,
  Layout3d box,
) {
  final at = box.drawnOffsetInSurface;
  final surface = it.surface.size;
  return (
    left: at.x / _dp,
    top: at.y / _dp,
    right: (surface.width - at.x - box.size.width) / _dp,
    bottom: (surface.height - at.y - box.size.height) / _dp,
  );
}

/// The label reading [text].
Text3d _label(PumpedSurface it, String text) =>
    boxesOf<Text3d>(it.surface).singleWhere((label) => label.data == text);

void main() {
  group('an app bar', () {
    testWidgets('runs up under the status bar, and its toolbar does not', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => _spent(_phone, _atTop(AppBar3d.text(title: 'Inbox'))),
        centred: false,
      );
      final bar = it.panels.first;
      expect(
        bar.size.height / _dp,
        closeTo(64 + 44, _tol),
        reason: 'the container is drawn behind the status bar',
      );
      expect(_edges(it, bar).top, closeTo(0, _tol));
      final title = _label(it, 'Inbox');
      // Centred in the 64dp toolbar below the inset.
      expect(
        _edges(it, title).top + title.size.height / _dp / 2,
        closeTo(44 + 32, _tol),
      );
    });

    testWidgets('a bar that is not primary ignores it', (tester) async {
      final it = await pumpComponent(
        tester,
        () => _spent(
          _phone,
          _atTop(AppBar3d.text(title: 'Inbox', primary: false)),
        ),
        centred: false,
      );
      expect(it.panels.first.size.height / _dp, closeTo(64, _tol));
    });

    testWidgets('a sliver bar grows both its heights by the inset', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => _spent(
          _phone,
          SceneCustomScrollView3d(
            slivers: <Widget>[
              SliverAppBar3d.text(
                title: 'Inbox',
                variant: AppBarVariant3d.medium,
                pinned: true,
              ),
            ],
          ),
        ),
        centred: false,
      );
      final header = oneOf<SliverPersistentHeader3d>(it.surface);
      expect(header.delegate.maxExtent / _dp, closeTo(112 + 44, _tol));
      expect(header.delegate.minExtent / _dp, closeTo(64 + 44, _tol));
    });
  });

  group('a navigation bar', () {
    NavigationBar3d bar() => NavigationBar3d(
      destinations: _destinations,
      selectedIndex: 0,
      onDestinationSelected: (_) {},
    );

    testWidgets('grows over the home indicator, and its pills do not move', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => _spent(_phone.copyWith(top: 0), _atBottom(bar())),
        centred: false,
      );
      final panel = it.panels.first;
      expect(panel.size.height / _dp, closeTo(80 + 34, _tol));
      expect(_edges(it, panel).bottom, closeTo(0, _tol));
      final pill = it.panels.firstWhere(
        (box) =>
            (box.decoration as BoxDecoration3d).color ==
            Theme3dData.light.colorScheme.secondaryContainer,
      );
      expect(
        _edges(it, pill).top - _edges(it, panel).top,
        closeTo(14, _tol),
        reason: 'the destinations keep their place in the top 80dp',
      );
    });
  });

  group('a navigation rail', () {
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

    testWidgets('clears the notch on its leading side', (tester) async {
      final it = await pumpComponent(
        tester,
        () => _spent(_landscape, rail()),
        centred: false,
      );
      final panel = it.panels.first;
      expect(panel.size.width / _dp, closeTo(80 + 48, _tol));
      final label = _label(it, 'Inbox');
      final middle = _edges(it, label).left + label.size.width / _dp / 2;
      expect(middle, closeTo(48 + 40, _tol), reason: 'centred in the 80dp');
    });

    testWidgets('and ignores one on the side it does not touch', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => _spent(_landscape, rail()),
        centred: false,
        textDirection: TextDirection.rtl,
      );
      expect(it.panels.first.size.width / _dp, closeTo(80, _tol));
    });
  });

  group('a scaffold', () {
    /// A screen whose body reports what it was told.
    Widget screen(
      List<EdgeInsets3d> told, {
      bool appBar = true,
      bool navigationBar = true,
      bool fab = true,
    }) => _spent(
      const EdgeInsets3d.only(top: 44, bottom: 34, left: 12, right: 20),
      Scaffold3d(
        appBar: appBar ? AppBar3d.text(title: 'Inbox') : null,
        body: Builder(
          builder: (context) {
            told.add(MediaQuery3d.of(context).padding);
            return const SceneSizedBox3d();
          },
        ),
        bottomNavigationBar: navigationBar
            ? NavigationBar3d(
                destinations: _destinations,
                selectedIndex: 0,
                onDestinationSelected: (_) {},
              )
            : null,
        floatingActionButton: fab
            ? FloatingActionButton3d(
                semanticLabel: 'Compose',
                onPressed: () {},
                child: const Icon3d(Icons.edit),
              )
            : null,
      ),
    );

    testWidgets('tells the body only what neither bar took', (tester) async {
      final told = <EdgeInsets3d>[];
      await pumpComponent(tester, () => screen(told), centred: false);
      expect(
        told.last,
        const EdgeInsets3d.only(left: 12, right: 20),
        reason: 'the bars took the top and the bottom; the sides are nobody\'s',
      );
    });

    testWidgets('and all of it when there are no bars', (tester) async {
      final told = <EdgeInsets3d>[];
      await pumpComponent(
        tester,
        () => screen(told, appBar: false, navigationBar: false),
        centred: false,
      );
      expect(
        told.last,
        const EdgeInsets3d.only(top: 44, bottom: 34, left: 12, right: 20),
      );
    });

    testWidgets('puts the body between the grown bars', (tester) async {
      final it = await pumpComponent(
        tester,
        () => screen(<EdgeInsets3d>[]),
        centred: false,
      );
      final clip = oneOf<ClipBox3d>(it.surface);
      expect(_edges(it, clip).top, closeTo(64 + 44, _tol));
      expect(_edges(it, clip).bottom, closeTo(80 + 34, _tol));
    });

    testWidgets('keeps the button 16dp above the bar and clear of the side', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => screen(<EdgeInsets3d>[]),
        centred: false,
      );
      final fab = boxesOf<DecoratedBox3d>(it.surface).last;
      expect(_edges(it, fab).bottom, closeTo(80 + 34 + 16, _tol));
      expect(_edges(it, fab).right, closeTo(20 + 16, _tol));
    });

    testWidgets('and 16dp above the home indicator with no bar', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => screen(<EdgeInsets3d>[], navigationBar: false),
        centred: false,
      );
      final fab = boxesOf<DecoratedBox3d>(it.surface).last;
      expect(_edges(it, fab).bottom, closeTo(34 + 16, _tol));
    });

    testWidgets('and at the left, in right to left', (tester) async {
      final it = await pumpComponent(
        tester,
        () => screen(<EdgeInsets3d>[]),
        centred: false,
        textDirection: TextDirection.rtl,
      );
      final fab = boxesOf<DecoratedBox3d>(it.surface).last;
      expect(
        _edges(it, fab).left,
        closeTo(12 + 16, _tol),
        reason: 'the trailing corner, clear of the inset on that side',
      );
    });

    testWidgets('with no insets, nothing moves', (tester) async {
      final it = await pumpComponent(
        tester,
        () => Scaffold3d(
          appBar: AppBar3d.text(title: 'Inbox'),
          body: const SceneSizedBox3d(),
          floatingActionButton: FloatingActionButton3d(
            semanticLabel: 'Compose',
            onPressed: () {},
            child: const Icon3d(Icons.edit),
          ),
        ),
        centred: false,
      );
      final fab = boxesOf<DecoratedBox3d>(it.surface).last;
      expect(_edges(it, fab).bottom, closeTo(16, _tol));
      expect(_edges(it, fab).right, closeTo(16, _tol));
      expect(_edges(it, oneOf<ClipBox3d>(it.surface)).top, closeTo(64, _tol));
    });
  });
}
