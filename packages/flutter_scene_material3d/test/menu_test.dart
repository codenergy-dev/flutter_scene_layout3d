import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart'
    show BuildContext, StatefulBuilder, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/testing.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'overlays_support.dart';

/// A popup button in the top-left corner of the panel, which is as far from
/// the overlay's own centre as the surface allows — so an anchored menu that
/// is *not* anchored is unmistakable.
Widget cornerButton(
  List<MenuItem3dEntry<String>> Function(BuildContext) items, {
  void Function(String)? onSelected,
  void Function()? onCanceled,
}) => ScenePositioned3d(
  left: 0,
  top: 0,
  front: 0,
  child: PopupMenuButton3d<String>(
    semanticLabel: 'More',
    itemBuilder: items,
    onSelected: onSelected,
    onCanceled: onCanceled,
    child: const SceneSizedBox3d(width: 0.4, height: 0.4, depth: 0.02),
  ),
);

List<MenuItem3dEntry<String>> twoItems(BuildContext context) =>
    const <MenuItem3dEntry<String>>[
      MenuItem3dEntry(value: 'rename', label: 'Rename'),
      MenuItem3dEntry(value: 'delete', label: 'Delete'),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the tokens', () {
    test('a menu is the extra-small shape on surfaceContainer', () {
      const theme = Theme3dData.light;
      final style = MenuStyle3d.of(theme);
      expect(style.container, theme.colorScheme.surfaceContainer);
      expect(style.shape, theme.shape.extraSmall);
      expect(style.elevation, theme.elevation.level2);
      expect(style.thickness, theme.thickness.raised);
      // Flutter's `_kMenuMinWidth`, `_kMenuMaxWidth` and `_kMenuItemHeight`.
      expect(style.minWidth, 112.0);
      expect(style.maxWidth, 280.0);
      expect(style.itemHeight, 48.0);
    });

    test('an item stands clear of the menu it is drawn on', () {
      const theme = Theme3dData.light;
      final style = MenuStyle3d.of(theme);
      // Not zero — a slab resting on the menu's front face is coplanar with
      // it — and not the item's own depth either, which would put the *back*
      // face there instead.
      expect(style.itemDepthStep, greaterThan(style.itemThickness));
      expect(style.itemThickness, theme.thickness.thin);
    });

    test('a style with an item that cannot clear the menu is refused', () {
      const theme = Theme3dData.light;
      expect(
        () => MenuStyle3d(
          container: theme.colorScheme.surface,
          contentColor: theme.colorScheme.onSurface,
          shape: theme.shape.extraSmall,
          elevation: 3,
          thickness: 4,
          padding: const EdgeInsets3d.symmetric(vertical: 8),
          minWidth: 112,
          maxWidth: 280,
          itemHeight: 48,
          itemPadding: const EdgeInsets3d.symmetric(horizontal: 12),
          itemThickness: 1,
          itemDepthStep: 1,
          itemTextStyle: Typography3dToken.labelLarge,
          arrival: Arrival3d.none,
        ),
        throwsAssertionError,
      );
    });
  });

  group('Menu3d', () {
    testWidgets('is a surface holding its items', (tester) async {
      final pumped = await pumpOverlay(
        tester,
        child: const Menu3d(
          semanticLabel: 'Actions',
          children: <Widget>[
            MenuItem3d(label: 'Rename'),
            MenuItem3d(label: 'Delete'),
          ],
        ),
      );
      final style = MenuStyle3d.of(Theme3dData.light);
      final panel = pumped.panels.first;
      final decoration = panel.decoration as BoxDecoration3d;
      expect(decoration.color, style.container);
      expect(decoration.borderRadius, style.shape);
      expect(decoration.elevation, style.elevation);
      // The menu's panel plus one per item.
      expect(pumped.panels, hasLength(3));
    });

    testWidgets('an item is 48dp tall and announces its own label', (
      tester,
    ) async {
      final pumped = await pumpOverlay(
        tester,
        child: const Menu3d(children: <Widget>[MenuItem3d(label: 'Rename')]),
      );
      final item = boxesOf<SizedBox3d>(pumped.surface).first;
      expect(item.size.height, closeTo(0.48, 1e-9));
      final labels = boxesOf<Semantics3d>(
        pumped.surface,
      ).map((box) => box.properties.label).toList();
      expect(labels, contains('Rename'));
    });

    testWidgets('an item lifts its own slab off the menu', (tester) async {
      final pumped = await pumpOverlay(
        tester,
        child: const Menu3d(children: <Widget>[MenuItem3d(label: 'Rename')]),
      );
      final style = MenuStyle3d.of(Theme3dData.light);
      final itemPanel = pumped.panels.last;
      final decoration = itemPanel.decoration as BoxDecoration3d;
      expect(decoration.elevation, style.itemDepthStep);
      expect(decoration.color.a, 0);
    });

    testWidgets('it takes the width of its widest item, within the bounds', (
      tester,
    ) async {
      final pumped = await pumpOverlay(
        tester,
        child: const Menu3d(children: <Widget>[MenuItem3d(label: 'Rename')]),
      );
      final panel = pumped.panels.first;
      // At least the 112dp minimum, and nowhere near the 280dp maximum: a
      // menu that filled its bound would be as wide as its longest possible
      // label rather than its actual one.
      expect(panel.size.width, greaterThanOrEqualTo(1.12));
      expect(panel.size.width, lessThan(2.8));
    });
  });

  group('PopupMenuButton3d', () {
    testWidgets('opens a menu and closes it with the item pressed where it '
        'is drawn', (tester) async {
      // Pressed through the camera, the way a person presses it. This test
      // used to aim a ray at where the overlay had *laid the menu out* — the
      // middle of the panel, where nothing is drawn — and the press landed,
      // because a follower answered hit tests there and not at its button.
      // Aimed where the item is drawn, the press reached the barrier and the
      // menu closed with nothing chosen.
      final chosen = <String>[];
      await tester.pumpSurface3d(
        SceneTheme3d(
          data: Theme3dData.light,
          child: SceneOverlay3d(
            child: SceneStack3d(
              children: <Widget>[
                cornerButton(twoItems, onSelected: chosen.add),
              ],
            ),
          ),
        ),
      );
      expect(find3d.bySubtype<Follower3d>(), findsNothing);

      await tester.tap3d(find3d.bySemanticsLabel('More'));
      // Settled, not pumped once: a menu grows over three hundred
      // milliseconds, and **an arriving box is pressable where layout put it
      // rather than where it is drawn** — the node tier's contract. A press
      // aimed at the drawn centre of a menu still at 80% lands on the item
      // above. A person waits for the menu; so does the test.
      await tester.pumpAndSettle();

      final follower = tester.layout3d<Follower3d>(
        find3d.bySubtype<Follower3d>(),
      );
      expect(follower.nodeOffset, isNot(Offset3d.zero));
      expect(find3d.bySemanticsLabel('Delete'), isReachable3d);

      await tester.tap3d(find3d.bySemanticsLabel('Delete'));
      await tester.pumpAndSettle();

      expect(chosen, <String>['delete']);
      expect(find3d.bySemanticsLabel('Delete'), findsNothing);
    });

    testWidgets('the menu is at the button, not at the middle of the panel', (
      tester,
    ) async {
      final pumped = await pumpOverlay(tester, child: cornerButton(twoItems));
      pumped.pointer.down(rayAt(pumped.surface, const Offset3d(0.2, 0.2, 0)));
      pumped.pointer.up();
      await tester.pump();

      final anchor = oneOf<Anchor3d>(pumped.surface);
      final follower = oneOf<Follower3d>(pumped.surface);

      // The overlay would have centred it: the entry's content fills the
      // panel and the menu inside it is centred, four units from the button.
      // Anchoring is the whole of what puts it back.
      final placed = follower.nodeOffset;
      expect(placed, isNot(Offset3d.zero));

      // Its top-left corner sits on the button's bottom-left one, which is
      // the claim rather than any particular number.
      final delta = follower.anchorOffsetTo(
        anchor,
        self: Alignment3d.topLeft,
        target: Alignment3d.bottomLeft,
      )!;
      expect(delta.x, closeTo(placed.x, 1e-9));
      expect(delta.y, closeTo(placed.y, 1e-9));
    });

    testWidgets('it follows the button when the button moves', (tester) async {
      // A button whose position a rebuild changes, which is what a scroll or
      // a resize does to a real one.
      var left = 0.0;
      late void Function(void Function()) rebuild;
      final pumped = await pumpOverlay(
        tester,
        child: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return ScenePositioned3d(
              left: left,
              top: 0,
              front: 0,
              child: PopupMenuButton3d<String>(
                semanticLabel: 'More',
                itemBuilder: twoItems,
                child: const SceneSizedBox3d(
                  width: 0.4,
                  height: 0.4,
                  depth: 0.02,
                ),
              ),
            );
          },
        ),
      );

      pumped.pointer.down(rayAt(pumped.surface, const Offset3d(0.2, 0.2, 0)));
      pumped.pointer.up();
      await tester.pump();

      final follower = oneOf<Follower3d>(pumped.surface);
      final before = follower.nodeOffset;

      rebuild(() => left = 2.0);
      await tester.pump();

      // The menu went with it, by exactly what the button moved.
      expect(follower.nodeOffset.x - before.x, closeTo(2.0, 1e-6));
    });

    testWidgets('a tap outside closes it with nothing', (tester) async {
      final cancels = <int>[0];
      final pumped = await pumpOverlay(
        tester,
        child: cornerButton(twoItems, onCanceled: () => cancels[0]++),
      );
      pumped.pointer.down(rayAt(pumped.surface, const Offset3d(0.2, 0.2, 0)));
      pumped.pointer.up();
      await tester.pump();
      expect(pumped.overlay.entries, hasLength(1));

      final outside = Layout3dPointer(pumped.surface);
      outside.down(rayAt(pumped.surface, const Offset3d(7.5, 5.5, 0)));
      outside.up();
      await tester.pump();

      expect(pumped.overlay.entries, isEmpty);
      expect(cancels.single, 1);
    });

    testWidgets('the menu closes when its button leaves the tree', (
      tester,
    ) async {
      var show = true;
      late void Function(void Function()) rebuild;
      final pumped = await pumpOverlay(
        tester,
        child: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return show
                ? cornerButton(twoItems)
                : const SceneSizedBox3d.cube(0.1);
          },
        ),
      );
      pumped.pointer.down(rayAt(pumped.surface, const Offset3d(0.2, 0.2, 0)));
      pumped.pointer.up();
      await tester.pump();
      expect(pumped.overlay.entries, hasLength(1));

      rebuild(() => show = false);
      await tester.pump();

      // An anchor that no longer exists cannot be followed, so the menu goes
      // with the button rather than hanging where it used to be.
      expect(pumped.overlay.entries, isEmpty);
    });

    testWidgets('it announces itself as a button', (tester) async {
      final pumped = await pumpOverlay(tester, child: cornerButton(twoItems));
      final semantics = boxesOf<Semantics3d>(pumped.surface).first;
      expect(semantics.properties.button, isTrue);
      expect(semantics.properties.label, 'More');
    });
  });
  group('the button a menu hangs from', () {
    // Everything here is about the trigger rather than the menu, and both
    // cases are regressions: an overflow button in an app bar laid out, drew,
    // announced itself to a screen reader and could not be pressed.

    Future<Layout3dSurface> pumpButton(
      WidgetTester tester, {
      bool trailing = false,
    }) => tester.pumpSurface3d(
      SceneTheme3d(
        data: Theme3dData.light,
        child: SceneOverlay3d(
          child: SceneStack3d(
            children: <Widget>[
              ScenePositioned3d(
                left: trailing ? null : 0,
                right: trailing ? 0 : null,
                top: 0,
                front: 0,
                child: PopupMenuButton3d<String>(
                  semanticLabel: 'More',
                  menuCorner: trailing
                      ? AlignmentDirectional3d.topEnd
                      : AlignmentDirectional3d.topStart,
                  anchorCorner: trailing
                      ? AlignmentDirectional3d.bottomEnd
                      : AlignmentDirectional3d.bottomStart,
                  itemBuilder: twoItems,
                  child: const Icon3d(Icons.more_vert),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    testWidgets('an icon trigger has depth, and Material\'s reach', (
      tester,
    ) async {
      final surface = await pumpButton(tester);

      for (final target in boxesOf<TapTarget3d>(surface)) {
        expect(
          target.size.depth,
          greaterThan(0.0),
          reason:
              'a target with no thickness is a slab no ray intersects, and an '
              'Icon3d is a glyph with no depth of its own — so the align that '
              'shrink-wraps it has to sit inside the ink well, not above it',
        );
      }
      expect(
        boxesOf<TapTarget3d>(surface),
        isNotEmpty,
        reason:
            'the outermost box of the button is a target, as Button3d\'s '
            'is: there was none at all, so the whole reach was the 24dp icon',
      );
      expect(find3d.bySemanticsLabel('More'), isReachable3d);
    });

    testWidgets('it can be hung by its trailing corner instead', (
      tester,
    ) async {
      // The answer for a button against the trailing edge of a panel, where a
      // menu opening the usual way runs off the surface and a ray finds
      // nothing at all. Nothing chooses it: the caller does.
      final surface = await pumpButton(tester, trailing: true);

      await tester.tap3d(find3d.bySemanticsLabel('More'));
      await tester.pumpAndSettle();

      final menu = tester.layout3d<Follower3d>(find3d.bySubtype<Follower3d>());
      // Hung by its own trailing edge, so it stays on the panel: its trailing
      // edge is the button's, not a menu's width further out.
      final right = menu.drawnOffsetInSurface.x + menu.size.width;
      expect(right, lessThanOrEqualTo(surface.child!.size.width + 1e-6));
      expect(find3d.bySemanticsLabel('Rename'), findsOne);

      // **Not `isReachable3d`**, and the omission is the honest half of this
      // test. A menu is drawn in front of the panel by its overlay's lift and
      // is hit-tested where it was laid out, because the lift is on the node
      // tier and a surface clamps a ray to its own box — so an overlay drawn
      // in front of the panel can only ever be found behind it. The two
      // points coincide in the middle of the view and drift apart toward the
      // edges, and this menu is hung in the far corner of the panel, which is
      // the worst case there is. The gallery's own overflow menu, at the end
      // of an app bar, is pressed by `examples/layout3d_gallery`'s suite and
      // works. See *An overlay is pressed where it was laid out* in
      // `docs/traps.md`, which owns the general defect.
    });
  });
}
