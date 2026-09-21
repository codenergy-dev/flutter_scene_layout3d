// The alert dialog: the one arrangement of a title, a body and a row of
// actions that is right, and the two obvious ones it exists to spare a caller.
//
// Pumped as a component rather than through `showDialog3d`: what is being
// measured here is the arrangement, and the route, the scrim and the depth an
// overlay sits at are `dialog_test.dart`'s, unchanged — this is a `Dialog3d`.

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart' show TextDirection, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/testing.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'surfaces_support.dart';

/// One world unit is a hundred logical pixels at the standard metrics.
const double _dp = 0.01;

/// How close two figures in logical pixels have to be. Positions come back
/// through the scene graph's single-precision transforms, which is a few
/// hundred-thousandths of a logical pixel at these sizes.
const double _tol = 1e-3;

/// A 64 by 20 stand-in for a button, so an action has a known width.
Widget _action() => const SceneSizedBox3d(width: 0.64, height: 0.2);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const theme = Theme3dData.light;
  final alert = AlertDialogStyle3d.of(theme);

  group('the tokens', () {
    test('are Flutter\'s AlertDialog figures and M3\'s roles', () {
      expect(alert.titleStyle, Typography3dToken.headlineSmall);
      expect(alert.titleColor, theme.colorScheme.onSurface);
      expect(alert.contentStyle, Typography3dToken.bodyMedium);
      expect(alert.contentColor, theme.colorScheme.onSurfaceVariant);
      expect(alert.iconColor, theme.colorScheme.secondary);
      expect(alert.iconGap, 16.0);
      expect(alert.titleGap, 16.0);
      expect(alert.actionsGap, 24.0);
      expect(alert.actionsSpacing, 8.0);
    });

    test('copyWith replaces what it is given and nothing else', () {
      final wider = alert.copyWith(actionsSpacing: 12.0);
      expect(wider.actionsSpacing, 12.0);
      expect(wider.titleGap, alert.titleGap);
      expect(wider.contentColor, alert.contentColor);
    });
  });

  group('the roles', () {
    testWidgets('the title is headlineSmall and the body bodyMedium', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => AlertDialog3d.text(
          title: 'Delete this file?',
          content: 'It will be gone from every device.',
        ),
      );
      final labels = boxesOf<Text3d>(it.surface);
      expect(labels.map((label) => label.data), <String>[
        'Delete this file?',
        'It will be gone from every device.',
      ]);
      expect(labels[0].style.color, theme.colorScheme.onSurface);
      expect(labels[0].style.fontSize, theme.typography.headlineSmall.fontSize);
      expect(
        labels[1].style.color,
        theme.colorScheme.onSurfaceVariant,
        reason: 'the role a hand-written dialog most often leaves out',
      );
      expect(labels[1].style.fontSize, theme.typography.bodyMedium.fontSize);
    });

    testWidgets('an icon is secondary and Material\'s 24dp', (tester) async {
      final it = await pumpComponent(
        tester,
        () => AlertDialog3d.text(
          icon: const Icon3d(Icons.delete),
          title: 'Delete this file?',
        ),
      );
      final glyph = boxesOf<Text3d>(it.surface).first;
      expect(glyph.style.color, theme.colorScheme.secondary);
      expect(glyph.style.fontSize, Icon3d.defaultSize);
    });

    testWidgets('it is a Dialog3d, so the surface is the dialog\'s', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => AlertDialog3d.text(title: 'Delete this file?'),
      );
      expect(boxesOf<DecoratedBox3d>(it.surface), hasLength(1));
      expect(
        (it.decoration).color,
        DialogStyle3d.of(theme).container,
        reason: 'no second surface, and no token repeated',
      );
    });
  });

  group('the arrangement', () {
    /// Where [box] starts, in logical pixels from the dialog's own panel.
    Offset3d offsetInPanel(PumpedSurface it, Layout3d box) {
      final panel = it.panel.drawnOffsetInSurface;
      final at = box.drawnOffsetInSurface;
      return Offset3d(
        (at.x - panel.x) / _dp,
        (at.y - panel.y) / _dp,
        (at.z - panel.z) / _dp,
      );
    }

    testWidgets('the gaps are 16dp to the body and 24dp to the actions', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => AlertDialog3d.text(
          icon: const Icon3d(Icons.delete),
          title: 'Delete?',
          content: 'Gone.',
          actions: <Widget>[_action()],
        ),
      );
      final labels = boxesOf<Text3d>(it.surface);
      final (glyph, title, body) = (labels[0], labels[1], labels[2]);
      final action = boxesOf<SizedBox3d>(it.surface).last;

      double top(Layout3d box) => offsetInPanel(it, box).y;
      double bottom(Layout3d box) => top(box) + box.size.height / _dp;

      expect(top(title) - bottom(glyph), closeTo(alert.iconGap, _tol));
      expect(top(body) - bottom(title), closeTo(alert.titleGap, _tol));
      expect(top(action) - bottom(body), closeTo(alert.actionsGap, _tol));
      expect(
        top(glyph),
        closeTo(DialogStyle3d.of(theme).padding.top, _tol),
        reason: 'the 24dp round the edge is the dialog\'s own padding',
      );
    });

    testWidgets('a title alone keeps the 24dp before its actions', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () =>
            AlertDialog3d.text(title: 'Delete?', actions: <Widget>[_action()]),
      );
      final title = oneOf<Text3d>(it.surface);
      final action = boxesOf<SizedBox3d>(it.surface).last;
      final gap =
          offsetInPanel(it, action).y -
          offsetInPanel(it, title).y -
          title.size.height / _dp;
      expect(gap, closeTo(alert.actionsGap, _tol));
    });

    testWidgets('the actions sit at the trailing edge, 8dp apart', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => AlertDialog3d(
          title: const SceneSizedBox3d(width: 3.0, height: 0.3),
          actions: <Widget>[_action(), _action()],
        ),
        size: const Size3d(8, 6, 0.5),
      );
      final boxes = boxesOf<SizedBox3d>(it.surface);
      final (first, second) = (boxes[boxes.length - 2], boxes.last);
      final padding = DialogStyle3d.of(theme).padding;

      final secondRight = offsetInPanel(it, second).x + second.size.width / _dp;
      expect(
        secondRight,
        closeTo(it.panel.size.width / _dp - padding.right, _tol),
        reason: 'the last action ends at the trailing padding',
      );
      final between =
          offsetInPanel(it, second).x -
          offsetInPanel(it, first).x -
          first.size.width / _dp;
      expect(between, closeTo(alert.actionsSpacing, _tol));
    });

    testWidgets('and at the left, in right to left', (tester) async {
      final it = await pumpComponent(
        tester,
        () => AlertDialog3d(
          title: const SceneSizedBox3d(width: 3.0, height: 0.3),
          actions: <Widget>[_action(), _action()],
        ),
        size: const Size3d(8, 6, 0.5),
        textDirection: TextDirection.rtl,
      );
      final boxes = boxesOf<SizedBox3d>(it.surface);
      final (first, second) = (boxes[boxes.length - 2], boxes.last);
      expect(
        offsetInPanel(it, first).x,
        greaterThan(offsetInPanel(it, second).x),
        reason: 'the first action is the one nearest the trailing edge',
      );
      expect(
        offsetInPanel(it, second).x,
        closeTo(DialogStyle3d.of(theme).padding.left, _tol),
      );
    });

    testWidgets('it is as wide as its widest line, not as the screen', (
      tester,
    ) async {
      // The reason this is a component: a stretched column without an
      // intrinsic width fills whatever it is given, and a dialog in a
      // full-screen frame would be the width of the screen.
      final it = await pumpComponent(
        tester,
        () => AlertDialog3d(
          title: const SceneSizedBox3d(width: 3.2, height: 0.3),
          actions: <Widget>[_action()],
        ),
        size: const Size3d(8, 6, 0.5),
      );
      final padding = DialogStyle3d.of(theme).padding;
      expect(
        it.panel.size.width / _dp,
        closeTo(320 + padding.left + padding.right, _tol),
      );
    });

    testWidgets('and never narrower than Material\'s 280dp', (tester) async {
      final it = await pumpComponent(
        tester,
        () => AlertDialog3d(
          title: const SceneSizedBox3d(width: 0.5, height: 0.3),
          actions: <Widget>[_action()],
        ),
        size: const Size3d(8, 6, 0.5),
      );
      final dialog = DialogStyle3d.of(theme);
      expect(it.panel.size.width / _dp, closeTo(dialog.minWidth, _tol));

      // And the arrangement fills that width rather than floating in it.
      // `Dialog3d` centres what it holds in a loose box, so a column that
      // took only its own 64dp would put the action in the middle of the
      // dialog — which the first version of this component did.
      final action = boxesOf<SizedBox3d>(it.surface).last;
      expect(
        offsetInPanel(it, action).x + action.size.width / _dp,
        closeTo(dialog.minWidth - dialog.padding.right, _tol),
      );
    });

    testWidgets('an icon centres the title with it; the body stays put', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => AlertDialog3d(
          icon: const SceneSizedBox3d(width: 0.24, height: 0.24),
          title: const SceneSizedBox3d(width: 1.0, height: 0.3),
          content: const SceneSizedBox3d(width: 2.0, height: 0.4),
        ),
        size: const Size3d(8, 6, 0.5),
      );
      // By height: the 16dp gaps between the sections are sized boxes too.
      SizedBox3d tall(double height) => boxesOf<SizedBox3d>(
        it.surface,
      ).singleWhere((box) => box.height == height);
      final (icon, title, body) = (tall(0.24), tall(0.3), tall(0.4));
      double centre(Layout3d box) =>
          offsetInPanel(it, box).x + box.size.width / _dp / 2.0;

      final middle = it.panel.size.width / _dp / 2.0;
      expect(centre(icon), closeTo(middle, _tol));
      expect(centre(title), closeTo(middle, _tol));
      expect(
        offsetInPanel(it, body).x,
        closeTo(DialogStyle3d.of(theme).padding.left, _tol),
        reason: 'the body is the widest line here, so it starts at the edge',
      );
    });

    testWidgets('without an icon the title starts at the leading edge', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => const AlertDialog3d(
          title: SceneSizedBox3d(width: 1.0, height: 0.3),
          content: SceneSizedBox3d(width: 3.0, height: 0.4),
        ),
        size: const Size3d(8, 6, 0.5),
      );
      final title = boxesOf<SizedBox3d>(it.surface).first;
      expect(
        offsetInPanel(it, title).x,
        closeTo(DialogStyle3d.of(theme).padding.left, _tol),
      );
    });

    testWidgets('everything on it stands on its face', (tester) async {
      await pumpComponent(
        tester,
        () => AlertDialog3d.text(
          icon: const Icon3d(Icons.delete),
          title: 'Delete this file?',
          content: 'It will be gone from every device.',
          actions: <Widget>[
            TextButton3d(onPressed: () {}, child: const SceneText3d('Delete')),
          ],
        ),
        size: const Size3d(8, 6, 0.5),
      );
      expect(find3d.bySubtype<Text3d>(), standsOnItsPanel3d);
    });
  });

  group('what it announces', () {
    testWidgets('.text names the route after its title', (tester) async {
      final it = await pumpComponent(
        tester,
        () => AlertDialog3d.text(title: 'Delete this file?', content: 'Gone.'),
      );
      expect(it.semantics.properties.label, 'Delete this file?');
      expect(it.semantics.properties.namesRoute, isTrue);
      expect(it.semantics.properties.scopesRoute, isTrue);
    });

    testWidgets('an explicit label wins over the title', (tester) async {
      final it = await pumpComponent(
        tester,
        () => AlertDialog3d.text(
          title: 'Delete?',
          semanticLabel: 'Delete this file?',
        ),
      );
      expect(it.semantics.properties.label, 'Delete this file?');
    });

    testWidgets('built from widgets, it announces what it was told', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => const AlertDialog3d(title: SceneText3d('Delete?')),
      );
      expect(it.semantics.properties.label, isNull);
      expect(it.semantics.properties.namesRoute, isFalse);
    });
  });
}
