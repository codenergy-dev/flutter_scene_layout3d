// InkWell3d, and the one claim the whole interaction design rests on: a
// hover, a focus and a press reach the panel without rebuilding anything and
// without laying anything out.
//
// This is the same promise `test/animation_test.dart` makes about text in the
// layout package, asserted the same way — by counting the work rather than by
// trusting the code path.

import 'package:flutter/gestures.dart' show kPressTimeout;
import 'package:flutter/widgets.dart'
    show Builder, BuildContext, FocusManager, Widget;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show DecoratedBox3d;
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Everything a test needs to poke one control and see what it cost.
class Control {
  Control(this.controller, this.child, this.builds);

  final Layout3dController controller;
  final TestBox child;
  final List<int> builds;

  Layout3dSurface get surface => controller.surface!;
  DecoratedBox3d get panel => decoratedBoxIn(surface);
  StateLayer3d get layer => panel.stateLayer;
  Layout3dPointer get pointer => Layout3dPointer(surface);
}

/// A `Material3d` filling the surface with an `InkWell3d` in it.
///
/// The surface is small in world units so the whole of it is one control and
/// a ray at its centre cannot miss.
Future<Control> pumpControl(
  WidgetTester tester, {
  bool enabled = true,
  bool focusOnPointerDown = false,
  void Function()? onTap,
}) async {
  final controller = Layout3dController();
  late TestBox child;
  final builds = <int>[0];

  await tester.pumpWidget(
    SceneLayout3d(
      parent: Node(),
      size: const Size3d(2, 2, 0.1),
      controller: controller,
      child: SceneTheme3d(
        data: Theme3dData.light,
        child: Material3d(
          child: Builder(
            builder: (BuildContext context) {
              builds[0]++;
              return InkWell3d(
                enabled: enabled,
                // Off by default here so that a press measures the press and
                // nothing else: the focus wash is the same 10% as the press
                // one, and a control that focuses itself on every press makes
                // the two indistinguishable. One test below turns it back on
                // and states that behaviour on purpose.
                focusOnPointerDown: focusOnPointerDown,
                onTap: onTap,
                child: SceneTestBox(const Size3d(2, 2, 0), (b) => child = b),
              );
            },
          ),
        ),
      ),
    ),
  );

  return Control(controller, child, builds);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The focus manager is global and outlives a pumped tree, so a test that
  // leaves a node focused hands the next one a focus change to apply against
  // a manager that has moved on. The layout package's own focus tests do the
  // same thing for the same reason.
  tearDown(() {
    FocusManager.instance.primaryFocus?.unfocus();
    FocusManager.instance.applyFocusChangesIfNeeded();
  });

  const theme = Theme3dData.light;

  group('the tier it must not leave', () {
    testWidgets('a hover lights the panel and rebuilds nothing', (
      tester,
    ) async {
      final control = await pumpControl(tester);
      expect(control.layer, StateLayer3d.none);

      final laidOut = control.child.layoutCount;
      final built = control.builds[0];
      final pointer = control.pointer;

      pointer.hover(rayAt(control.surface, const Offset3d(1, 1, 0)));

      expect(
        control.layer.opacity,
        theme.stateLayer.hover,
        reason: 'the wash is Material\'s 8%',
      );
      expect(
        control.layer.color,
        theme.colorScheme.onSurface,
        reason: 'and its colour is the surface\'s own content colour',
      );
      expect(control.child.layoutCount, laidOut, reason: 'nothing laid out');
      expect(control.builds[0], built, reason: 'nothing rebuilt');
      expect(control.surface.needsFlush, isFalse);

      pointer.exit();
      expect(control.layer, StateLayer3d.none);
      expect(control.child.layoutCount, laidOut);
      expect(control.builds[0], built);
    });

    testWidgets('a hover that stays inside the box writes once', (
      tester,
    ) async {
      // A pointer moving over a control produces a hover event per frame, and
      // a controller that re-resolved the wash on each of them would be
      // asking for a repaint sixty times a second for nothing.
      final control = await pumpControl(tester);
      final pointer = control.pointer;

      pointer.hover(rayAt(control.surface, const Offset3d(0.5, 0.5, 0)));
      final first = control.layer;
      pointer.hover(rayAt(control.surface, const Offset3d(1.5, 1.5, 0)));

      expect(identical(control.layer, first), isTrue);
    });

    testWidgets('a press lights it harder and lets go', (tester) async {
      var taps = 0;
      final control = await pumpControl(tester, onTap: () => taps++);
      final laidOut = control.child.layoutCount;
      final built = control.builds[0];
      final pointer = control.pointer;

      pointer.down(rayAt(control.surface, const Offset3d(1, 1, 0)));
      // Flutter's tap recognizer does not report a press the instant a
      // pointer lands: it holds the report until it wins the arena or its
      // own deadline expires, so that a press which turns into a scroll
      // never flashes a highlight. `kPressTimeout` is that deadline, and a
      // test that presses and lets go in the same instant sees the wash
      // appear and vanish between two statements.
      await tester.pump(kPressTimeout);
      expect(control.layer.opacity, theme.stateLayer.press);

      pointer.up();
      expect(taps, 1);
      expect(control.layer, StateLayer3d.none);
      expect(control.child.layoutCount, laidOut);
      expect(control.builds[0], built);
      expect(control.surface.needsFlush, isFalse);
    });

    testWidgets('a focus lights it, through the focus tree', (tester) async {
      final control = await pumpControl(tester);
      final laidOut = control.child.layoutCount;
      final built = control.builds[0];
      final focus = focusIn(control.surface);

      focus.requestFocus();
      FocusManager.instance.applyFocusChangesIfNeeded();

      expect(focus.hasPrimaryFocus, isTrue);
      expect(control.layer.opacity, theme.stateLayer.focus);
      expect(control.child.layoutCount, laidOut);
      expect(control.builds[0], built);

      focus.unfocus();
      FocusManager.instance.applyFocusChangesIfNeeded();
      expect(control.layer, StateLayer3d.none);
    });

    testWidgets('a press focuses the control, and the wash says so', (
      tester,
    ) async {
      // The protocol's own default, kept: a press focuses what it landed on.
      // The consequence is that the wash outlives the press, because nothing
      // here reads Flutter's highlight mode to tell a pointer focus from a
      // keyboard one. A control that should not glow after a click passes
      // `focusOnPointerDown: false`.
      final control = await pumpControl(tester, focusOnPointerDown: true);
      final pointer = control.pointer;

      pointer.down(rayAt(control.surface, const Offset3d(1, 1, 0)));
      pointer.up();
      FocusManager.instance.applyFocusChangesIfNeeded();

      expect(focusIn(control.surface).hasPrimaryFocus, isTrue);
      expect(control.layer.opacity, theme.stateLayer.focus);
    });

    testWidgets('a press over a hover is one wash, the stronger one', (
      tester,
    ) async {
      // Material resolves one state layer, not a sum: a hovered control that
      // is then pressed is 10% and never 18%.
      final control = await pumpControl(tester);
      final pointer = control.pointer;

      pointer.hover(rayAt(control.surface, const Offset3d(1, 1, 0)));
      pointer.down(rayAt(control.surface, const Offset3d(1, 1, 0)));
      await tester.pump(kPressTimeout);

      expect(control.layer.opacity, theme.stateLayer.press);
      expect(
        control.layer.opacity,
        lessThan(theme.stateLayer.hover + theme.stateLayer.press),
      );

      pointer.up();
      expect(control.layer.opacity, theme.stateLayer.hover);
    });
  });

  group('disabled', () {
    testWidgets('lights up for nothing and fires nothing', (tester) async {
      var taps = 0;
      final control = await pumpControl(
        tester,
        enabled: false,
        onTap: () => taps++,
      );
      final pointer = control.pointer;

      pointer.hover(rayAt(control.surface, const Offset3d(1, 1, 0)));
      expect(control.layer, StateLayer3d.none);

      pointer.down(rayAt(control.surface, const Offset3d(1, 1, 0)));
      await tester.pump(kPressTimeout);
      expect(control.layer, StateLayer3d.none);
      pointer.up();
      expect(taps, 0);
      expect(control.layer, StateLayer3d.none);
    });

    testWidgets('drops the wash it was already wearing', (tester) async {
      // The case that leaves a stuck highlight if nothing handles it: the
      // pointer is over a button when the button goes disabled, and there is
      // no exit event coming.
      final controller = Layout3dController();
      Widget frame({required bool enabled}) => SceneLayout3d(
        parent: Node(),
        size: const Size3d(2, 2, 0.1),
        controller: controller,
        child: SceneTheme3d(
          data: Theme3dData.light,
          child: Material3d(
            child: InkWell3d(
              enabled: enabled,
              onTap: () {},
              child: const SceneSizedBox3d(width: 2, height: 2, depth: 0),
            ),
          ),
        ),
      );

      await tester.pumpWidget(frame(enabled: true));
      final surface = controller.surface!;
      Layout3dPointer(surface).hover(rayAt(surface, const Offset3d(1, 1, 0)));
      expect(
        decoratedBoxIn(surface).stateLayer.opacity,
        theme.stateLayer.hover,
      );

      await tester.pumpWidget(frame(enabled: false));
      expect(decoratedBoxIn(surface).stateLayer, StateLayer3d.none);
    });
  });

  group('the target', () {
    testWidgets('grows no box, and does not reach past its own parent', (
      tester,
    ) async {
      // Two claims, and the second one is the rule a component author has to
      // know rather than a defect.
      //
      // The first is the protocol's design: `TapTarget3d` grows the ray
      // region and not the extent, so the control keeps the size layout
      // measured and its neighbours do not move apart to make room for it.
      //
      // The second is where a target has to sit. `TapTarget3d` now delivers a
      // press in its margin — it re-tests its children at the centre of the
      // control, the way Flutter's `_InputPadding` does — but it cannot reach
      // past its own *parent*, because every box gates its children on its
      // own extent. An `InkWell3d` puts its target inside the `Material3d`
      // that draws the panel, and the panel is the smaller box, so the ray is
      // rejected a level above and the reach buys nothing here. That is why
      // `Button3d` wraps its whole surface in a `SceneTapTarget3d` and asks
      // the ink well inside for `minimumSize: Size3d.zero`; the last
      // expectation below is the same press landing when the target is in the
      // right place.
      final controller = Layout3dController();
      late TestBox child;
      var taps = 0;
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(2, 2, 0.5),
          controller: controller,
          child: SceneTheme3d(
            data: Theme3dData.light,
            child: SceneCenter3d(
              child: Material3d(
                alignment: null,
                child: InkWell3d(
                  onTap: () => taps++,
                  // 20dp across: well under Material's 48dp minimum.
                  child: SceneTestBox(
                    const Size3d(0.2, 0.2, 0),
                    (b) => child = b,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(child.size.width, 0.2, reason: 'the box did not grow');
      expect(decoratedBoxIn(controller.surface!).size.width, 0.2);

      // The control spans 0.9 to 1.1 in a 2-unit surface, and the target's
      // reach would be 0.14 units beyond each edge.
      final surface = controller.surface!;
      final pointer = Layout3dPointer(surface);
      pointer.down(rayAt(surface, const Offset3d(0.8, 1.0, 0)));
      pointer.up();
      expect(
        taps,
        0,
        reason: 'the panel gated the ray out a level above the target',
      );

      pointer.down(rayAt(surface, const Offset3d(1.0, 1.0, 0)));
      pointer.up();
      expect(taps, 1, reason: 'inside the box it taps');
    });

    testWidgets('a target outside the surface does deliver the press', (
      tester,
    ) async {
      // The same control, with the target where a component should put it.
      // This is the composition `Button3d` uses, reduced to its bones.
      final controller = Layout3dController();
      var taps = 0;
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(2, 2, 0.5),
          controller: controller,
          child: SceneTheme3d(
            data: Theme3dData.light,
            child: SceneCenter3d(
              child: SceneTapTarget3d(
                child: Material3d(
                  alignment: null,
                  child: InkWell3d(
                    minimumSize: Size3d.zero,
                    onTap: () => taps++,
                    child: const SceneSizedBox3d(
                      width: 0.2,
                      height: 0.2,
                      depth: 0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final surface = controller.surface!;
      final pointer = Layout3dPointer(surface);
      pointer.down(rayAt(surface, const Offset3d(0.8, 1.0, 0)));
      pointer.up();
      expect(taps, 1, reason: '14dp out in the margin, and the press landed');

      pointer.down(rayAt(surface, const Offset3d(0.7, 1.0, 0)));
      pointer.up();
      expect(taps, 1, reason: 'and the reach still stops at 48dp');
    });
  });
}
