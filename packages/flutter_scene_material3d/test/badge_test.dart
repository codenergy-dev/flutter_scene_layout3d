// Badge3d: the corner it sits at, the stadium it stays, and the distance it
// stands in front of what it decorates.

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart'
    show
        Directionality,
        MediaQuery,
        MediaQueryData,
        TextDirection,
        TextScaler,
        Widget;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'surfaces_support.dart';

const Theme3dData _theme = Theme3dData.light;
const double _dp = 0.01;

/// A 40dp square to decorate, so every position below is arithmetic.
Widget _square() => SceneSizedBox3d(width: 40 * _dp, height: 40 * _dp);

/// Where [box]'s origin is, in the frame of [ancestor].
Offset3d _originIn(Layout3d box, Layout3d ancestor) {
  var at = Offset3d.zero;
  Layout3d? walk = box;
  while (walk != null && !identical(walk, ancestor)) {
    at += walk.offset;
    walk = walk.parent;
  }
  return at;
}

/// The badge's own panel: the one in the error colour.
DecoratedBox3d _badgePanel(Layout3dSurface surface) =>
    boxesOf<DecoratedBox3d>(surface).singleWhere(
      (box) =>
          (box.decoration as BoxDecoration3d).color == _theme.colorScheme.error,
    );

/// The stack the badge and its child share.
Stack3d _stack(Layout3dSurface surface) => outermostOf<Stack3d>(surface);

void main() {
  group('the tokens', () {
    test('are Flutter\'s: error on onError, 6 and 16, labelSmall', () {
      final style = BadgeStyle3d.of(_theme);
      expect(style.backgroundColor, _theme.colorScheme.error);
      expect(style.textColor, _theme.colorScheme.onError);
      expect(style.smallSize, 6.0);
      expect(style.largeSize, 16.0);
      expect(style.padding, const EdgeInsets3d.symmetric(horizontal: 4));
      expect(style.alignment, AlignmentDirectional3d.topEnd);
      expect(style.textStyle, Typography3dToken.labelSmall);
    });

    test('the step clears a 24dp icon\'s wall, its lift and the badge', () {
      // The wall factor is the renderer's own default, so a change there is
      // a change here — and the badge would start losing to the icon's
      // corner without anything saying so.
      expect(BadgeStyle3d.iconWallFactor, AtlasText3dRenderer().depthFactor);
      final style = BadgeStyle3d.of(_theme);
      final wall = Icon3d.defaultSize * BadgeStyle3d.iconWallFactor;
      // The badge occupies [−step, −step + thickness] in front of the plane
      // the icon stands on; the icon's wall reaches to −(wall + lift).
      expect(
        -style.depthStep + style.thickness,
        lessThan(-(wall + Material3d.contentLift)),
      );
    });

    test('count writes the number, and caps it', () {
      String labelOf(Badge3d badge) => (badge.label! as SceneText3d).data;
      expect(labelOf(Badge3d.count(count: 3)), '3');
      expect(labelOf(Badge3d.count(count: 999)), '999');
      expect(labelOf(Badge3d.count(count: 1000)), '999+');
      expect(labelOf(Badge3d.count(count: 12, maxCount: 9)), '9+');
      expect(() => Badge3d.count(count: -1), throwsAssertionError);
    });
  });

  group('the corner', () {
    testWidgets('a dot sits inside the top-end corner', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => Badge3d(child: _square()),
      );
      final panel = _badgePanel(pumped.surface);
      expect(panel.size.width, closeTo(6 * _dp, 1e-9));
      expect(panel.size.height, closeTo(6 * _dp, 1e-9));
      final at = _originIn(panel, _stack(pumped.surface));
      expect(at.x, closeTo(34 * _dp, 1e-9));
      expect(at.y, closeTo(0.0, 1e-9));
    });

    testWidgets('a labelled badge overhangs the corner by 4dp each way', (
      tester,
    ) async {
      final pumped = await pumpComponent(
        tester,
        () => Badge3d(label: const SceneText3d('3'), child: _square()),
      );
      final panel = _badgePanel(pumped.surface);
      expect(panel.size.height, closeTo(16 * _dp, 1e-9));
      final at = _originIn(panel, _stack(pumped.surface));
      // Flutter's arithmetic: the start edge at the width less 16 plus 4,
      // and the top at 4 down plus 8 less half of 16.
      expect(at.x, closeTo(28 * _dp, 1e-9));
      expect(at.y, closeTo(-4 * _dp, 1e-9));
    });

    testWidgets('and mirrors in right to left', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => Badge3d(label: const SceneText3d('3'), child: _square()),
        textDirection: TextDirection.rtl,
      );
      final at = _originIn(_badgePanel(pumped.surface), _stack(pumped.surface));
      expect(at.x, closeTo(-4 * _dp, 1e-9));
      expect(at.y, closeTo(-4 * _dp, 1e-9));
    });

    testWidgets('a label wider than its child is as wide as the label', (
      tester,
    ) async {
      // The case a positioned child in a stack cannot express: the stack
      // would cap the badge at the 40dp it is decorating.
      final pumped = await pumpComponent(
        tester,
        () => Badge3d.count(count: 5000, child: _square()),
      );
      final panel = _badgePanel(pumped.surface);
      expect(panel.size.width, greaterThan(40 * _dp));
      // And the decorated box is not moved or grown by any of it.
      expect(_stack(pumped.surface).size.width, closeTo(40 * _dp, 1e-9));
    });

    testWidgets('a badge with no child is just the badge', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => const Badge3d(label: SceneText3d('New')),
      );
      expect(boxesOf<Stack3d>(pumped.surface), isEmpty);
      expect(_badgePanel(pumped.surface).size.height, closeTo(0.16, 1e-9));
    });

    testWidgets('isLabelVisible false leaves the child alone', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => Badge3d(isLabelVisible: false, child: _square()),
      );
      expect(boxesOf<DecoratedBox3d>(pumped.surface), isEmpty);
      expect(boxesOf<Stack3d>(pumped.surface), isEmpty);
    });
  });

  group('the stadium', () {
    testWidgets('is never narrower than it is tall, at any type setting', (
      tester,
    ) async {
      // At twice the type a single digit's line is taller than the digit and
      // its padding are wide, and Flutter widens the badge to a circle.
      final controller = Layout3dController();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SceneLayout3d(
              parent: Node(),
              size: const Size3d(4, 3, 0.5),
              controller: controller,
              child: SceneTheme3d(
                data: _theme,
                child: SceneCenter3d(
                  child: Badge3d(label: const SceneText3d('3')),
                ),
              ),
            ),
          ),
        ),
      );
      final panel = _badgePanel(controller.surface!);
      expect(panel.size.height, greaterThan(16 * _dp));
      expect(panel.size.width, closeTo(panel.size.height, 1e-9));
    });
  });

  group('the depth', () {
    testWidgets('the badge stands its step in front of the child', (
      tester,
    ) async {
      final pumped = await pumpComponent(
        tester,
        () => Badge3d(child: const Icon3d(Icons.inbox)),
      );
      final placement = boxesOf<Positioned3d>(pumped.surface).single;
      expect(
        placement.sceneOffset.z,
        closeTo(-BadgeStyle3d.of(_theme).depthStep * _dp, 1e-9),
      );
      // On the node tier: the box itself is where layout put it, inside the
      // stack, so nothing about the child's layout knows the badge is there.
      expect(placement.offset.z, 0.0);
    });

    testWidgets('a press on the badge is a press on what it decorates', (
      tester,
    ) async {
      var pressed = 0;
      final pumped = await pumpComponent(
        tester,
        () => Badge3d.count(
          count: 3,
          child: IconButton3d(
            icon: Icons.inbox,
            semanticLabel: 'Inbox',
            onPressed: () => pressed++,
          ),
        ),
      );
      final panel = _badgePanel(pumped.surface);
      // The badge's corner nearest the middle of the button, which is over
      // the button's disc: a round button answers only inside its circle.
      final stack = _stack(pumped.surface);
      final corner = _originIn(stack, pumped.surface);
      final badge = _originIn(panel, stack);
      final aim = Offset3d(
        corner.x + badge.x + 2 * _dp,
        corner.y + badge.y + panel.size.height - 2 * _dp,
        0,
      );
      pumped.pointer.down(rayAt(pumped.surface, aim));
      pumped.pointer.up();
      await tester.pump();
      expect(pressed, 1);
    });
  });

  group('what it announces', () {
    testWidgets('nothing, unless it is told', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => Badge3d.count(count: 3, child: _square()),
      );
      expect(boxesOf<Semantics3d>(pumped.surface), isEmpty);
    });

    testWidgets('what it is told', (tester) async {
      final pumped = await pumpComponent(
        tester,
        () => Badge3d.count(
          count: 3,
          semanticLabel: '3 unread',
          child: _square(),
        ),
      );
      expect(oneOf<Semantics3d>(pumped.surface).properties.label, '3 unread');
    });
  });
}
