// The figures phase 4's styles carry, against the Flutter widgets they stand
// in for — and the dialog's and the menu's, which phase 1 found had been
// described as drift-checked by a test that never existed.
//
// Three grades, the ones `test/navigation_defaults_test.dart` names. Where a
// figure is a fact about a laid-out Flutter widget — a height, an offset, the
// colour on the `Material` it builds — it is read off one, so this is a drift
// alarm. Where it is only in Flutter's source, as a private constant, the test
// says *transcribed* and states the figure, which catches a change here and
// not one upstream.

import 'package:flutter/material.dart' as m;
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

const Theme3dData _theme = Theme3dData.light;

/// Flutter's own light scheme, which `test/color_scheme_test.dart` pins
/// `ColorScheme3d.light` against role by role, so "the same role" below is a
/// comparison of colours that are already known to be the same table.
final m.ColorScheme _flutter = m.ThemeData(
  brightness: m.Brightness.light,
).colorScheme;

int _argb(m.Color color) => color.toARGB32();

Future<void> _pump(WidgetTester tester, m.Widget home) => tester.pumpWidget(
  m.MaterialApp(
    theme: m.ThemeData(brightness: m.Brightness.light),
    home: home,
  ),
);

void main() {
  group('Badge', () {
    Finder stadium() => find.byWidgetPredicate(
      (widget) =>
          widget is m.Container && widget.decoration is m.ShapeDecoration,
    );

    testWidgets('a labelled badge: 16dp, error, at the top-end corner', (
      tester,
    ) async {
      await _pump(
        tester,
        const m.Center(
          child: m.Badge(
            label: m.Text('3'),
            child: m.SizedBox(width: 40, height: 40),
          ),
        ),
      );
      final child = tester.getRect(find.byType(m.SizedBox).last);
      final badge = tester.getRect(stadium());
      final style = BadgeStyle3d.of(_theme);
      expect(badge.height, style.largeSize);
      // The arithmetic `Badge3d` reproduces: the start edge 12dp in from the
      // child's end, and the top 4dp above it.
      expect(badge.left - child.left, 40 - style.largeSize + style.offset.x);
      expect(badge.top - child.top, style.offset.y + 8 - style.largeSize / 2);
      final decoration =
          tester.widget<m.Container>(stadium()).decoration!
              as m.ShapeDecoration;
      expect(_argb(decoration.color!), _argb(_flutter.error));
      expect(_argb(style.backgroundColor), _argb(_flutter.error));
      final label = tester.widget<m.DefaultTextStyle>(
        find
            .ancestor(
              of: find.text('3'),
              matching: find.byType(m.DefaultTextStyle),
            )
            .first,
      );
      expect(_argb(label.style.color!), _argb(_flutter.onError));
      // The catalogue's type scale, which `test/typography_test.dart` pins
      // against Flutter's: `ThemeData().textTheme` has no sizes in it until
      // `Theme.of` localizes it.
      expect(
        label.style.fontSize,
        _theme.textStyle(Typography3dToken.labelSmall).fontSize,
      );
    });

    testWidgets('a dot: 6dp, inside the corner', (tester) async {
      await _pump(
        tester,
        const m.Center(
          child: m.Badge(child: m.SizedBox(width: 40, height: 40)),
        ),
      );
      final child = tester.getRect(find.byType(m.SizedBox).last);
      final badge = tester.getRect(stadium());
      expect(badge.width, BadgeStyle3d.of(_theme).smallSize);
      expect(badge.right, child.right);
      expect(badge.top, child.top);
    });
  });

  group('MaterialBanner', () {
    Future<void> banner(WidgetTester tester, {double? elevation}) => _pump(
      tester,
      m.Scaffold(
        body: m.Column(
          children: <m.Widget>[
            m.MaterialBanner(
              elevation: elevation,
              content: const m.Text('Offline'),
              actions: <m.Widget>[
                m.TextButton(onPressed: () {}, child: const m.Text('Retry')),
              ],
            ),
          ],
        ),
      ),
    );

    m.Material material(WidgetTester tester) => tester.widget<m.Material>(
      find
          .descendant(
            of: find.byType(m.MaterialBanner),
            matching: find.byType(m.Material),
          )
          .first,
    );

    testWidgets('flat, though its token table says 1dp, with the content '
        '16dp in', (tester) async {
      await banner(tester);
      final style = MaterialBannerStyle3d.of(_theme);
      expect(
        _argb(material(tester).color!),
        _argb(_flutter.surfaceContainerLow),
      );
      expect(_argb(style.container), _argb(_flutter.surfaceContainerLow));
      // `_BannerDefaultsM3` passes 1.0 to its constructor, and
      // `MaterialBanner.build` falls back to 0.0 without ever reading it.
      expect(material(tester).elevation, 0.0);
      expect(style.elevation, 0.0);
      expect(find.byType(m.Divider), findsOneWidget);

      final strip = tester.getRect(
        find
            .descendant(
              of: find.byType(m.MaterialBanner),
              matching: find.byType(m.Material),
            )
            .first,
      );
      final content = tester.getRect(find.text('Offline'));
      expect(content.left - strip.left, style.singleRowPadding.start);
      // The 52dp actions bar beside the content, under 2dp of padding, and a
      // rule that takes no room. Ours takes 1dp; see `MaterialBanner3d`.
      expect(
        strip.height,
        style.actionsBarMinHeight + style.singleRowPadding.top,
      );
      final whole = tester.getRect(find.byType(m.MaterialBanner));
      expect(whole.height, strip.height, reason: 'no margin when flat');
    });

    testWidgets('raised, it has the 10dp margin under it', (tester) async {
      await banner(tester, elevation: 1);
      final strip = tester.getRect(
        find
            .descendant(
              of: find.byType(m.MaterialBanner),
              matching: find.byType(m.Material),
            )
            .first,
      );
      final whole = tester.getRect(find.byType(m.MaterialBanner));
      expect(
        whole.height - strip.height,
        MaterialBannerStyle3d.of(_theme).elevatedMargin,
      );
      expect(find.byType(m.Divider), findsNothing);
    });

    test('the rule is outlineVariant and the type stops at 1.5', () {
      // `_BannerDefaultsM3.dividerColor` and `_kMaxContentTextScaleFactor`,
      // both private. Transcribed.
      final style = MaterialBannerStyle3d.of(_theme);
      expect(_argb(style.dividerColor), _argb(_flutter.outlineVariant));
      expect(style.maxTextScaleFactor, 1.5);
    });
  });

  group('BottomAppBar', () {
    testWidgets('80dp of surfaceContainer, its child 16dp in and 12dp down', (
      tester,
    ) async {
      await _pump(
        tester,
        const m.Scaffold(
          bottomNavigationBar: m.BottomAppBar(child: m.SizedBox.expand()),
        ),
      );
      final style = BottomAppBarStyle3d.of(_theme);
      final bar = tester.getRect(find.byType(m.BottomAppBar));
      expect(bar.height, style.height);
      final child = tester.getRect(
        find
            .descendant(
              of: find.byType(m.BottomAppBar),
              matching: find.byType(m.SizedBox),
            )
            .last,
      );
      expect(child.left - bar.left, style.padding.left);
      expect(child.top - bar.top, style.padding.top);
      final shape = tester.widget<m.PhysicalShape>(
        find.descendant(
          of: find.byType(m.BottomAppBar),
          matching: find.byType(m.PhysicalShape),
        ),
      );
      expect(_argb(shape.color), _argb(_flutter.surfaceContainer));
      expect(_argb(style.container), _argb(_flutter.surfaceContainer));
      expect(shape.elevation, style.elevation);
    });
  });

  group('Drawer', () {
    testWidgets('304dp of surfaceContainerLow at 1dp', (tester) async {
      await _pump(tester, const m.Scaffold(body: m.Drawer()));
      final style = DrawerStyle3d.of(_theme);
      expect(tester.getSize(find.byType(m.Drawer)).width, style.width);
      final material = tester.widget<m.Material>(
        find.descendant(
          of: find.byType(m.Drawer),
          matching: find.byType(m.Material),
        ),
      );
      expect(_argb(material.color!), _argb(_flutter.surfaceContainerLow));
      expect(_argb(style.container), _argb(_flutter.surfaceContainerLow));
      expect(material.elevation, style.elevation);
      // The 16dp corner has no token, and Flutter says so in a comment.
      expect(
        material.shape,
        const m.RoundedRectangleBorder(
          borderRadius: m.BorderRadius.horizontal(right: m.Radius.circular(16)),
        ),
      );
      expect(style.cornerRadius, 16.0);
    });

    test('the scrim is Colors.black54', () {
      // `DrawerController`'s fallback, written inline in its build method.
      final scrim = DrawerStyle3d.of(_theme).scrimColor;
      expect(scrim.a, closeTo(m.Colors.black54.a, 1e-3));
      expect(_argb(scrim.withValues(alpha: 1)), 0xFF000000);
    });
  });

  group('NavigationDrawer', () {
    testWidgets('a 56dp destination, its icon 16dp in and its label 12dp '
        'after', (tester) async {
      await _pump(
        tester,
        const m.Scaffold(
          body: m.NavigationDrawer(
            children: <m.Widget>[
              m.NavigationDrawerDestination(
                icon: m.Icon(m.Icons.inbox),
                label: m.Text('Inbox'),
              ),
            ],
          ),
        ),
      );
      final style = NavigationDrawerStyle3d.of(_theme);
      final drawer = tester.getRect(find.byType(m.NavigationDrawer));
      final icon = tester.getRect(find.byType(m.Icon));
      final label = tester.getRect(find.text('Inbox'));
      expect(
        icon.left - drawer.left,
        style.tilePadding.start + style.iconInset,
      );
      expect(label.left - icon.right, style.labelGap);
      final tile = tester.getRect(
        find
            .ancestor(
              of: find.byType(m.InkWell),
              matching: find.byType(m.SizedBox),
            )
            .first,
      );
      expect(tile.height, style.tileHeight);
      // The label is labelLarge in onSecondaryContainer: index 0 is selected.
      final text = tester.widget<m.DefaultTextStyle>(
        find
            .ancestor(
              of: find.text('Inbox'),
              matching: find.byType(m.DefaultTextStyle),
            )
            .first,
      );
      expect(
        text.style.fontSize,
        _theme.textStyle(Typography3dToken.labelLarge).fontSize,
      );
      expect(_argb(text.style.color!), _argb(_flutter.onSecondaryContainer));
    });
  });

  group('ExpansionTile', () {
    testWidgets('the chevron is onSurfaceVariant closed and primary open, '
        'and the rules are the divider colour', (tester) async {
      await _pump(
        tester,
        const m.Scaffold(
          body: m.ExpansionTile(
            title: m.Text('Advanced'),
            children: <m.Widget>[m.Text('Sync')],
          ),
        ),
      );
      final style = ExpansionTileStyle3d.of(_theme);
      m.Color chevron() => tester
          .widget<m.RichText>(
            find.descendant(
              of: find.byIcon(m.Icons.expand_more),
              matching: find.byType(m.RichText),
            ),
          )
          .text
          .style!
          .color!;
      expect(_argb(chevron()), _argb(_flutter.onSurfaceVariant));
      expect(_argb(style.collapsedIconColor), _argb(_flutter.onSurfaceVariant));

      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      expect(_argb(chevron()), _argb(_flutter.primary));
      expect(_argb(style.iconColor), _argb(_flutter.primary));
      // The expanded border is `theme.dividerColor`, which in Material 3 is
      // `outline` — not the `outlineVariant` a `Divider` draws in, which is
      // what the plan assumed until this read it.
      expect(_argb(m.ThemeData().dividerColor), _argb(_flutter.outline));
      expect(_argb(style.dividerColor), _argb(_flutter.outline));
    });

    test('the clock is transcribed', () {
      // `_kExpand` and `Curves.easeIn` are private to the tile and to
      // `Expansible`.
      final style = ExpansionTileStyle3d.of(_theme);
      expect(style.duration, const Duration(milliseconds: 200));
      expect(style.curve, m.Curves.easeIn);
    });
  });

  group('SnackBar', () {
    testWidgets('the action is labelLarge, as a TextButton draws it', (
      tester,
    ) async {
      await _pump(
        tester,
        m.Scaffold(
          body: m.Builder(
            builder: (context) => m.TextButton(
              onPressed: () => m.ScaffoldMessenger.of(context).showSnackBar(
                m.SnackBar(
                  content: const m.Text('Deleted'),
                  action: m.SnackBarAction(label: 'Undo', onPressed: () {}),
                ),
              ),
              child: const m.Text('Go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      final undo = tester.widget<m.RichText>(
        find.descendant(
          of: find.text('Undo'),
          matching: find.byType(m.RichText),
        ),
      );
      final large = _theme.textStyle(Typography3dToken.labelLarge);
      expect(undo.text.style!.fontSize, large.fontSize);
      expect(undo.text.style!.fontWeight, large.fontWeight);
      expect(
        SnackBarStyle3d.of(_theme).actionTextStyle,
        Typography3dToken.labelLarge,
      );
    });

    test('the threshold is transcribed', () {
      // `_SnackbarDefaultsM3.actionOverflowThreshold`, private.
      expect(SnackBarStyle3d.of(_theme).actionOverflowThreshold, 0.25);
    });
  });

  group('Dialog, which phase 1 said had never been checked', () {
    testWidgets('surfaceContainerHigh at 6dp with a 28dp corner, 40 by 24 in '
        'from the edges', (tester) async {
      await _pump(
        tester,
        const m.Scaffold(
          body: m.Dialog(child: m.SizedBox(width: 10, height: 10)),
        ),
      );
      final style = DialogStyle3d.of(_theme);
      final material = tester.widget<m.Material>(
        find.descendant(
          of: find.byType(m.Dialog),
          matching: find.byType(m.Material),
        ),
      );
      expect(_argb(material.color!), _argb(_flutter.surfaceContainerHigh));
      expect(_argb(style.container), _argb(_flutter.surfaceContainerHigh));
      expect(material.elevation, style.elevation);
      expect(
        material.shape,
        const m.RoundedRectangleBorder(
          borderRadius: m.BorderRadius.all(m.Radius.circular(28)),
        ),
      );
      expect(style.shape.topLeft, 28.0);
      // The minimum width is what a narrow dialog is laid out at.
      expect(
        tester.getSize(find.byType(m.Material).last).width,
        style.minWidth,
      );
      final dialog = tester.widget<m.Dialog>(find.byType(m.Dialog));
      expect(dialog.insetPadding, isNull);
      // `_defaultInsetPadding`, private, and visible as where the dialog's
      // material stops short of a screen narrower than its minimum.
      expect(style.insetPadding.left, 40.0);
      expect(style.insetPadding.top, 24.0);
    });
  });

  group('Menu, which phase 1 said had never been checked', () {
    testWidgets('surfaceContainer at 3dp, a 4dp corner and 48dp items', (
      tester,
    ) async {
      await _pump(
        tester,
        m.Scaffold(
          body: m.Center(
            child: m.PopupMenuButton<String>(
              itemBuilder: (context) => const <m.PopupMenuEntry<String>>[
                m.PopupMenuItem<String>(value: 'a', child: m.Text('Rename')),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(m.PopupMenuButton<String>));
      await tester.pumpAndSettle();
      final style = MenuStyle3d.of(_theme);
      final material = tester.widget<m.Material>(
        find
            .ancestor(
              of: find.text('Rename'),
              matching: find.byType(m.Material),
            )
            .last,
      );
      expect(_argb(material.color!), _argb(_flutter.surfaceContainer));
      expect(_argb(style.container), _argb(_flutter.surfaceContainer));
      expect(material.elevation, style.elevation);
      expect(
        material.shape,
        const m.RoundedRectangleBorder(
          borderRadius: m.BorderRadius.all(m.Radius.circular(4)),
        ),
      );
      final item = tester.getSize(find.byType(m.PopupMenuItem<String>));
      expect(item.height, style.itemHeight);
      expect(item.width, style.minWidth);
    });
  });
}
