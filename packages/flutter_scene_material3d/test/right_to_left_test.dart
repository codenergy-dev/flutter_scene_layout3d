// The catalogue in a right-to-left application: every row mirrors on its own
// once the layout reads the ambient Directionality, so what is tested here is
// the part that would not — the asymmetric paddings, the toolbar's slots, the
// two controls whose position is arithmetic rather than a row, and the corner
// a menu hangs from.

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart' show FocusManager, TextDirection, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/testing.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'overlays_support.dart' as overlays;
import 'support.dart';
import 'surfaces_support.dart';

const double _dp = 0.01;
const Theme3dData _theme = Theme3dData.light;
const _rtl = TextDirection.rtl;

/// A bar at the top of a screen-shaped column, as `app_bar_test.dart` pumps
/// one.
Widget _screenWith(Widget bar) => SceneColumn3d(
  crossAxisAlignment: CrossAxisAlignment3d.stretch,
  children: <Widget>[
    bar,
    const SceneExpanded3d(child: SceneSizedBox3d()),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a list tile keeps 16dp before its leading edge, on the right', (
    tester,
  ) async {
    final it = await pumpComponent(
      tester,
      () => ListTile3d.text(title: 'x'),
      textDirection: _rtl,
    );
    final container = oneOf<Container3d>(it.surface);
    final padding = container.padding.resolve(container.textDirection);
    expect(padding.right, closeTo(0.16, 1e-9));
    expect(padding.left, closeTo(0.24, 1e-9));
  });

  testWidgets('a divider indents from its leading edge, on the right', (
    tester,
  ) async {
    final it = await pumpComponent(
      tester,
      () => const Divider3d(indent: 8, endIndent: 16),
      textDirection: _rtl,
    );
    final padding = oneOf<Padding3d>(it.surface);
    final resolved = padding.padding.resolve(padding.textDirection);
    expect(resolved.right, closeTo(0.08, 1e-9));
    expect(resolved.left, closeTo(0.16, 1e-9));
  });

  group('an app bar', () {
    /// How far the title stands off each edge of the bar, in logical pixels.
    ({double fromLeft, double fromRight}) titleInsets(PumpedSurface pumped) {
      final bar = outermostOf<DecoratedBox3d>(pumped.surface);
      final title = oneOf<Text3d>(pumped.surface);
      final left =
          (title.drawnOffsetInSurface.x - bar.drawnOffsetInSurface.x) / _dp;
      return (
        fromLeft: left,
        fromRight: bar.size.width / _dp - left - title.size.width / _dp,
      );
    }

    testWidgets('is the mirror image of its left-to-right self', (
      tester,
    ) async {
      Widget bar() => _screenWith(
        AppBar3d.text(
          title: 'Inbox',
          leading: const SceneSizedBox3d(width: 48 * _dp),
          actions: const <Widget>[SceneSizedBox3d(width: 48 * _dp)],
        ),
      );
      final ltr = titleInsets(await pumpComponent(tester, bar, centred: false));
      final rtl = titleInsets(
        await pumpComponent(tester, bar, centred: false, textDirection: _rtl),
      );
      expect(ltr.fromLeft, closeTo(72, 1e-4));
      expect(rtl.fromRight, closeTo(ltr.fromLeft, 1e-4));
      expect(rtl.fromLeft, closeTo(ltr.fromRight, 1e-4));
    });

    testWidgets('keeps the title off the empty edge, which is the right', (
      tester,
    ) async {
      final at = titleInsets(
        await pumpComponent(
          tester,
          () => _screenWith(AppBar3d.text(title: 'Inbox')),
          centred: false,
          textDirection: _rtl,
        ),
      );
      expect(at.fromRight, closeTo(AppBarStyle3d.defaultTitleSpacing, 1e-4));
    });

    testWidgets('a centred bar puts its leading widget at the right edge', (
      tester,
    ) async {
      final pumped = await pumpComponent(
        tester,
        () => _screenWith(
          AppBar3d.text(
            title: 'Inbox',
            centerTitle: true,
            leading: const SceneSizedBox3d(width: 48 * _dp),
            actions: const <Widget>[SceneSizedBox3d(width: 40 * _dp)],
          ),
        ),
        centred: false,
        textDirection: _rtl,
      );
      final bar = outermostOf<DecoratedBox3d>(pumped.surface);
      double edgeOf(double width, {required bool right}) {
        final box = boxesOf<SizedBox3d>(
          pumped.surface,
        ).firstWhere((box) => (box.size.width / _dp - width).abs() < 1e-4);
        final left =
            (box.drawnOffsetInSurface.x - bar.drawnOffsetInSurface.x) / _dp;
        return right ? bar.size.width / _dp - left - width : left;
      }

      final style = AppBarStyle3d.of(_theme, AppBarVariant3d.centerAligned);
      // The 48dp leading widget centred in its 56dp slot, from the right.
      expect(
        edgeOf(48, right: true),
        closeTo((style.leadingWidth - 48) / 2, 1e-4),
      );
      // The action against the left edge.
      expect(edgeOf(40, right: false), closeTo(0, 1e-4));
    });
  });

  group('a slider', () {
    final style = SliderStyle3d.of(_theme);
    final travel = (style.minimumTrackWidth - style.thumbSize) * _dp;

    testWidgets('fills its track from the right end', (tester) async {
      for (final value in <double>[0.0, 0.25, 1.0]) {
        final it = await pumpComponent(
          tester,
          () => Slider3d(value: value, onChanged: (_) {}),
          textDirection: _rtl,
        );
        final fill = componentShifts(it.surface)[0];
        expect(fill.scaleX, closeTo(value, 1e-9));
        // Scaled about its left end and moved by the part it does not cover,
        // which leaves its right end where layout put it.
        expect(fill.shift.x, closeTo(travel * (1 - value), 1e-9));
        expect(fill.shift.x + travel * fill.scaleX, closeTo(travel, 1e-9));
      }
    });

    testWidgets('puts the minimum at the right', (tester) async {
      for (final entry in <double, double>{
        0.0: 0.5,
        0.5: 0.0,
        1.0: -0.5,
      }.entries) {
        final it = await pumpComponent(
          tester,
          () => Slider3d(value: entry.key, onChanged: (_) {}),
          textDirection: _rtl,
        );
        expect(
          componentShifts(it.surface)[1].shift.x,
          closeTo(entry.value * travel, 1e-9),
          reason: 'the thumb at ${entry.key}',
        );
      }
    });

    testWidgets('reads a press from the right', (tester) async {
      final it = await pumpComponent(
        tester,
        () => Slider3d(value: 0.5, onChanged: (_) {}),
        textDirection: _rtl,
      );
      final gesture = oneOf<SliderGesture3d>(it.surface);
      final y = gesture.size.height / 2;
      expect(
        gesture.fractionAt(Offset3d(gesture.padding, y, 0)),
        closeTo(1.0, 1e-9),
      );
      expect(
        gesture.fractionAt(
          Offset3d(gesture.size.width - gesture.padding, y, 0),
        ),
        closeTo(0.0, 1e-9),
      );
    });

    testWidgets('moves toward the arrow, whichever way the numbers run', (
      tester,
    ) async {
      addTearDown(() {
        FocusManager.instance.primaryFocus?.unfocus();
        FocusManager.instance.applyFocusChangesIfNeeded();
      });
      final reported = <double>[];
      final it = await pumpComponent(
        tester,
        () => Slider3d(value: 0.5, divisions: 10, onChanged: reported.add),
        textDirection: _rtl,
      );
      focusIn(it.surface).requestFocus();
      FocusManager.instance.applyFocusChangesIfNeeded();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);

      // Right is toward the minimum here; up and down name the value.
      expect(reported, <Matcher>[
        closeTo(0.4, 1e-9),
        closeTo(0.6, 1e-9),
        closeTo(0.6, 1e-9),
        closeTo(0.4, 1e-9),
      ]);
    });
  });

  testWidgets('a switch that is on has its thumb at the left', (tester) async {
    final travel = SwitchStyle3d.of(_theme).travel * _dp;
    final on = await pumpComponent(
      tester,
      () => Switch3d(value: true, onChanged: (_) {}),
      textDirection: _rtl,
    );
    expect(oneComponentShift(on.surface).shift.x, closeTo(-travel / 2, 1e-9));
    final off = await pumpComponent(
      tester,
      () => Switch3d(value: false, onChanged: (_) {}),
      textDirection: _rtl,
    );
    expect(oneComponentShift(off.surface).shift.x, closeTo(travel / 2, 1e-9));
  });

  testWidgets('a menu hangs from its button\'s leading corner, on the right', (
    tester,
  ) async {
    final pumped = await overlays.pumpOverlay(
      tester,
      textDirection: _rtl,
      child: ScenePositioned3d(
        right: 0,
        top: 0,
        front: 0,
        child: PopupMenuButton3d<String>(
          semanticLabel: 'More',
          itemBuilder: (context) => const <MenuItem3dEntry<String>>[
            MenuItem3dEntry(value: 'rename', label: 'Rename'),
          ],
          child: const SceneSizedBox3d(width: 0.4, height: 0.4, depth: 0.02),
        ),
      ),
    );
    final button = Offset3d(pumped.surface.size.width - 0.2, 0.2, 0);
    pumped.pointer.down(overlays.rayAt(pumped.surface, button));
    pumped.pointer.up();
    await tester.pump();

    final anchor = overlays.oneOf<Anchor3d>(pumped.surface);
    final follower = overlays.oneOf<Follower3d>(pumped.surface);
    expect(follower.self, Alignment3d.topRight);
    expect(follower.target, Alignment3d.bottomRight);
    final delta = follower.anchorOffsetTo(
      anchor,
      self: Alignment3d.topRight,
      target: Alignment3d.bottomRight,
    )!;
    expect(delta.x, closeTo(follower.nodeOffset.x, 1e-9));
  });
}
