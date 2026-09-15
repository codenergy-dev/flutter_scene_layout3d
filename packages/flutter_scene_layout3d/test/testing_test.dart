// The test library an application author uses: finding a box on a screen,
// pressing it through the camera the way a person would, and asking the
// layout the questions a picture would otherwise have to answer.
//
// These are tests *of* `package:flutter_scene_layout3d/testing.dart`, so a
// good share of them are about the library failing, and saying why.

import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart'
    show Alignment, FocusNode, SizedBox, Stack, Widget;
import 'package:flutter_scene/scene.dart' show Node, PerspectiveCamera;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/testing.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Quaternion, Vector3;

/// A labelled control that logs its taps.
Widget control(String label, List<String> log, {Size3d? size}) =>
    SceneSemantics3d(
      properties: SemanticsProperties(label: label),
      child: SceneGestureDetector3d(
        onTap: () => log.add(label),
        child: SceneSizedBox3d(
          width: (size ?? const Size3d(1, 0.5, 0.1)).width,
          height: (size ?? const Size3d(1, 0.5, 0.1)).height,
          depth: (size ?? const Size3d(1, 0.5, 0.1)).depth,
        ),
      ),
    );

/// A panel with a card on it and something on the card, padded by [padding].
Widget card({required EdgeInsets3d padding, Widget? content}) => SceneCenter3d(
  child: SceneDecoratedBox3d(
    decoration: const BoxDecoration3d(),
    child: SceneSizedBox3d(
      width: 3,
      height: 2,
      depth: 0.04,
      child: ScenePadding3d(
        padding: padding,
        child: content ?? const SceneText3d('Volume'),
      ),
    ),
  ),
);

/// Asserts that [body] fails the test with a message containing every one of
/// [phrases].
Future<void> expectFailure(
  Future<void> Function() body,
  List<String> phrases,
) async {
  try {
    await body();
  } on TestFailure catch (failure) {
    for (final phrase in phrases) {
      expect(failure.message, contains(phrase));
    }
    return;
  }
  fail('expected a TestFailure mentioning $phrases');
}

/// The mismatch [matcher] reports for [item], or null when it matches.
String? mismatchOf(Matcher matcher, Object? item) {
  final state = <Object?, Object?>{};
  if (matcher.matches(item, state)) return null;
  return matcher
      .describeMismatch(item, StringDescription(), state, false)
      .toString();
}

void main() {
  group('find3d', () {
    testWidgets('finds a box by what a person reads on it', (tester) async {
      await tester.pumpSurface3d(
        SceneColumn3d(
          children: <Widget>[
            control('Inbox', <String>[]),
            control('Settings', <String>[]),
            const SceneText3d('Two unread'),
          ],
        ),
      );

      expect(find3d.bySemanticsLabel('Inbox'), findsOne);
      expect(find3d.bySemanticsLabel('Inbox'), isNot(findsExactly(2)));
      expect(find3d.bySemanticsLabel(RegExp('^Set')), findsOne);
      expect(find3d.bySemanticsLabel('Compose'), findsNothing);
      expect(find3d.text('Two unread'), findsOne);
      expect(find3d.text('Two'), findsNothing);
      expect(find3d.textContaining('unread'), findsOne);
      expect(find3d.textContaining(RegExp(r'\d')), findsNothing);
    });

    testWidgets('finds by type, by subtype, by name and by the box itself', (
      tester,
    ) async {
      final surface = await tester.pumpSurface3d(
        SceneColumn3d(
          children: <Widget>[
            control('a', <String>[]),
            control('b', <String>[]),
          ],
        ),
      );

      expect(find3d.byType(Semantics3d), findsExactly(2));
      expect(find3d.bySubtype<ProxyLayout3d>(), findsAtLeast(2));
      expect(find3d.byType(Layout3dSurface), findsOne);
      expect(find3d.byLayout(surface), findsOne);
      // A SceneColumn3d builds a Flex3d, and a node is named after the box.
      expect(find3d.byName('Flex3d'), findsOne);
      expect(
        find3d.byPredicate((box) => box is SizedBox3d && box.size.width == 1),
        findsExactly(2),
      );
      expect(tester.surfaces3d, <Layout3dSurface>[surface]);
    });

    testWidgets('descendant and ancestor walk the layout tree', (tester) async {
      await tester.pumpSurface3d(
        SceneColumn3d(
          children: <Widget>[
            control('a', <String>[]),
            control('b', <String>[]),
          ],
        ),
      );

      final underA = find3d.descendant(
        of: find3d.bySemanticsLabel('a'),
        matching: find3d.bySubtype<SizedBox3d>(),
      );
      expect(underA, findsOne);
      expect(
        find3d.descendant(
          of: find3d.bySemanticsLabel('a'),
          matching: find3d.byType(Semantics3d),
        ),
        findsNothing,
        reason: 'the root is not its own descendant',
      );
      expect(
        find3d.descendant(
          of: find3d.bySemanticsLabel('a'),
          matching: find3d.byType(Semantics3d),
          matchRoot: true,
        ),
        findsOne,
      );

      final above = find3d.ancestor(
        of: underA,
        matching: find3d.bySubtype<Semantics3d>(),
      );
      expect(above, findsOne);
      expect(
        tester.layout3d<Semantics3d>(above).properties.label,
        'a',
        reason: 'the nearest one, not the other control',
      );
    });

    testWidgets('finds the box that holds the keyboard', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpSurface3d(
        SceneFocus3d(focusNode: node, child: control('focusable', <String>[])),
      );
      expect(find3d.focused(), findsNothing);

      await tester.tap3d(find3d.bySemanticsLabel('focusable'));
      await tester.pump();

      expect(find3d.focused(), findsOne);
      expect(tester.layout3d<Layout3d>(find3d.focused()), isA<Focus3d>());
    });

    testWidgets('finds a detached entry, on the surface of its own', (
      tester,
    ) async {
      final overlay = Overlay3dController();
      final surface = await tester.pumpSurface3d(
        SceneOverlay3d(controller: overlay, child: control('page', <String>[])),
      );
      expect(find3d.bySemanticsLabel('dialog'), findsNothing);

      overlay.overlay!.insertEntry(
        WidgetOverlay3dEntry(
          layer: const OverlayLayer3d.detached(),
          contentBuilder: (context, _) => control('dialog', <String>[]),
        ),
      );
      await tester.pump();

      expect(find3d.bySemanticsLabel('dialog'), findsOne);
      final surfaces = tester.surfaces3d;
      expect(surfaces, hasLength(2));
      expect(surfaces.first, same(surface));
      expect(
        find3d.descendant(
          of: find3d.byLayout(surface),
          matching: find3d.bySemanticsLabel('dialog'),
        ),
        findsNothing,
        reason: 'a detached entry is not below the surface that opened it',
      );
    });

    testWidgets('layout3d names what it expected when the count is wrong', (
      tester,
    ) async {
      await tester.pumpSurface3d(
        SceneColumn3d(
          children: <Widget>[
            control('twin', <String>[]),
            control('twin', <String>[]),
          ],
        ),
      );

      await expectFailure(
        () async => tester.layout3d<Layout3d>(find3d.bySemanticsLabel('twin')),
        <String>['box with semantics label "twin"', 'found 2'],
      );
      await expectFailure(
        () async =>
            tester.layout3d<Text3d>(find3d.bySemanticsLabel('twin').first),
        <String>['to be a Text3d', 'Semantics3d', '"twin"'],
      );
    });
  });

  group('pumping', () {
    testWidgets('frames the surface in the middle of the view', (tester) async {
      await tester.pumpSurface3d(const SceneSizedBox3d.cube(1));

      final middle = tester.getCenter3d(find3d.byType(Layout3dSurface));
      expect(middle.dx, closeTo(400, 1e-6));
      expect(middle.dy, closeTo(300, 1e-6));
    });

    testWidgets('puts layout up at the top and left at the left', (
      tester,
    ) async {
      await tester.pumpSurface3d(
        SceneStack3d(
          children: <Widget>[
            ScenePositioned3d(
              left: 0,
              top: 0,
              child: control('top left', <String>[]),
            ),
            ScenePositioned3d(
              right: 0,
              bottom: 0,
              child: control('bottom right', <String>[]),
            ),
          ],
        ),
      );

      final topLeft = tester.getCenter3d(find3d.bySemanticsLabel('top left'));
      final bottomRight = tester.getCenter3d(
        find3d.bySemanticsLabel('bottom right'),
      );
      // Worth pinning because the engine's camera basis puts +x on the
      // viewer's left: a harness that framed the plane from behind would
      // still find both boxes and swap them.
      expect(topLeft.dx, lessThan(400));
      expect(topLeft.dy, lessThan(300));
      expect(bottomRight.dx, greaterThan(400));
      expect(bottomRight.dy, greaterThan(300));
    });

    testWidgets('frames a surface on the ground from above', (tester) async {
      final log = <String>[];
      await tester.pumpSurface3d(
        SceneStack3d(
          children: <Widget>[
            ScenePositioned3d(left: 0, top: 0, child: control('far', log)),
          ],
        ),
        basis: LayoutBasis3d.xz,
      );

      final far = tester.getCenter3d(find3d.bySemanticsLabel('far'));
      expect(far.dx, lessThan(400));
      expect(far.dy, lessThan(300));
      await tester.tap3d(find3d.bySemanticsLabel('far'));
      expect(log, <String>['far']);
    });

    testWidgets('a scene with its own camera is asked the way it is framed', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpScene3d(<Widget>[
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 3, 0.2),
          rotation: Quaternion.axisAngle(Vector3(0, 1, 0), 0.7),
          child: SceneCenter3d(child: control('turned', log)),
        ),
      ], camera: PerspectiveCamera(position: Vector3(0, 0, 6)));

      expect(find3d.bySemanticsLabel('turned'), isReachable3d);
      await tester.tap3d(find3d.bySemanticsLabel('turned'));
      expect(log, <String>['turned']);
    });

    testWidgets('a screen with its own host is found under it', (tester) async {
      final log = <String>[];
      final camera = PerspectiveCamera(
        fovRadiansY: math.pi / 4,
        position: Vector3(0, 0, 5),
      );
      await tester.pumpWidget(
        SceneInput3d(
          camera: camera,
          child: SizedBox.expand(
            child: Stack(
              alignment: Alignment.topLeft,
              children: <Widget>[
                SceneLayout3d(
                  parent: Node(),
                  size: const Size3d(4, 4, 0.2),
                  child: SceneCenter3d(child: control('own', log)),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap3d(find3d.bySemanticsLabel('own'));
      expect(log, <String>['own']);
    });
  });

  group('pressing', () {
    testWidgets('tap3d delivers a tap through the host', (tester) async {
      final log = <String>[];
      await tester.pumpSurface3d(
        SceneRow3d(
          mainAxisAlignment: MainAxisAlignment3d.spaceEvenly,
          children: <Widget>[control('left', log), control('right', log)],
        ),
      );

      await tester.tap3d(find3d.bySemanticsLabel('right'));
      await tester.tap3d(find3d.bySemanticsLabel('left'));

      expect(log, <String>['right', 'left']);
    });

    testWidgets('tap3d refuses a box covered by a surface in front', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpScene3d(<Widget>[
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(8, 6, 0.2),
          child: SceneCenter3d(child: control('behind', log)),
        ),
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(8, 6, 0.2),
          position: Vector3(0, 0, 0.5),
          zOrder: 1,
          child: SceneCenter3d(child: control('in front', log)),
        ),
      ]);

      await expectFailure(
        () => tester.tap3d(find3d.bySemanticsLabel('behind')),
        <String>[
          'tap3d() cannot press the box with semantics label "behind"',
          'GestureDetector3d',
          'under "in front" first, on a surface in front of it',
          'checkReachable: false',
        ],
      );
      expect(log, isEmpty, reason: 'a refused tap presses nothing');
      expect(find3d.bySemanticsLabel('behind'), isNot(isReachable3d));

      await tester.tap3d(
        find3d.bySemanticsLabel('behind'),
        checkReachable: false,
      );
      expect(log, <String>['in front']);
    });

    testWidgets('tap3d refuses a box nothing on the path answers for', (
      tester,
    ) async {
      await tester.pumpSurface3d(
        const SceneCenter3d(
          child: SceneSemantics3d(
            properties: SemanticsProperties(label: 'decoration only'),
            child: SceneSizedBox3d.cube(1),
          ),
        ),
      );

      await expectFailure(
        () => tester.tap3d(find3d.bySemanticsLabel('decoration only')),
        <String>['reaches nothing'],
      );
    });

    testWidgets('tap3d refuses a box off the screen', (tester) async {
      await tester.pumpScene3d(<Widget>[
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(1, 1, 0.1),
          position: Vector3(40, 0, 0),
          child: control('elsewhere', <String>[]),
        ),
      ], camera: PerspectiveCamera(position: Vector3(0, 0, 5)));

      await expectFailure(
        () => tester.tap3d(find3d.bySemanticsLabel('elsewhere')),
        <String>['outside the 800×600 view'],
      );
    });

    testWidgets('tap3d refuses a box with no host above it', (tester) async {
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(2, 2, 0.1),
          child: control('unhosted', <String>[]),
        ),
      );

      expect(find3d.bySemanticsLabel('unhosted'), findsOne);
      await expectFailure(
        () => tester.tap3d(find3d.bySemanticsLabel('unhosted')),
        <String>['not under a SceneInput3d', 'pumpSurface3d'],
      );
    });

    testWidgets('a dialog in front takes the press, and the page under it '
        'is not reachable', (tester) async {
      final log = <String>[];
      final overlay = Overlay3dController();
      await tester.pumpSurface3d(
        SceneOverlay3d(
          controller: overlay,
          child: SceneCenter3d(child: control('page', log)),
        ),
      );
      overlay.overlay!.insertEntry(
        WidgetOverlay3dEntry(
          layer: const OverlayLayer3d.detached(),
          contentBuilder: (context, _) =>
              control('dialog', log, size: const Size3d(2, 1.5, 0.1)),
        ),
      );
      await tester.pump();

      expect(find3d.bySemanticsLabel('dialog'), isReachable3d);
      expect(find3d.bySemanticsLabel('page'), isNot(isReachable3d));
      await tester.tap3d(find3d.bySemanticsLabel('dialog'));
      expect(log, <String>['dialog']);
    });

    testWidgets('drag3d and scroll3d move a list under the finger and the '
        'wheel', (tester) async {
      final controller = Scroll3dController();
      addTearDown(controller.dispose);
      await tester.pumpSurface3d(
        SceneListView3d(
          controller: controller,
          children: List<Widget>.generate(
            12,
            (index) => control('row $index', <String>[]),
          ),
        ),
        size: const Size3d(4, 3, 0.2),
      );

      await tester.scroll3d(find3d.byType(ListView3d), const Offset(0, 50));
      // A notch is measured in logical pixels on the plane: 50dp at the
      // standard metrics.
      expect(controller.offset, closeTo(0.5, 1e-9));

      await tester.drag3d(
        find3d.bySemanticsLabel('row 2'),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0.5));
    });

    testWidgets('hitTest3d answers what a press would reach, and nothing '
        'outside the view', (tester) async {
      await tester.pumpSurface3d(
        SceneCenter3d(child: control('here', <String>[])),
      );

      final paths = tester.hitTest3d(const Offset(400, 300));
      expect(paths, hasLength(1));
      expect(paths.single.firstOf<Semantics3d>()!.properties.label, 'here');
      expect(tester.hitTest3d(const Offset(-10, -10)), isEmpty);
    });
  });

  group('the host answers without dispatching', () {
    testWidgets('every path a press would go to, front to back', (
      tester,
    ) async {
      final log = <String>[];
      final input = Input3dController();
      Widget panel(String label, {required double z, required bool absorbs}) =>
          SceneLayout3d(
            parent: Node(),
            size: const Size3d(8, 6, 0.2),
            position: Vector3(0, 0, z),
            zOrder: z,
            absorbsPointer: absorbs,
            child: SceneCenter3d(child: control(label, log)),
          );
      final camera = PerspectiveCamera(position: Vector3(0, 0, 8));
      await tester.pumpWidget(
        SceneInput3d(
          camera: camera,
          controller: input,
          child: SizedBox.expand(
            child: Stack(
              alignment: Alignment.topLeft,
              children: <Widget>[
                panel('back', z: 0, absorbs: true),
                panel('hud', z: 1, absorbs: false),
              ],
            ),
          ),
        ),
      );
      final host = input.host!;
      final before = host.pointers.lastHit;

      final paths = host.hitTestAt(const Offset(400, 300));

      expect(
        paths.map((path) => path.firstOf<Semantics3d>()!.properties.label),
        <String>['hud', 'back'],
      );
      expect(log, isEmpty, reason: 'nothing was dispatched');
      expect(host.pointers.lastHit, same(before));

      // The group's own `hitTest` is the first of those paths, which is why a
      // question about the box on the panel behind needed a walk of its own.
      final ray = camera.screenPointToRay(
        const Offset(400, 300),
        const Size(800, 600),
      );
      expect(
        host.pointers.hitTest(ray).firstOf<Semantics3d>()!.properties.label,
        'hud',
      );
    });

    testWidgets('an empty answer with no camera', (tester) async {
      final input = Input3dController();
      await tester.pumpWidget(
        SceneInput3d(controller: input, child: const SizedBox.expand()),
      );
      expect(input.host!.hitTestAt(const Offset(400, 300)), isEmpty);
    });
  });

  group('where a box is drawn', () {
    testWidgets('with nothing nudged, it is the sum of the layout offsets', (
      tester,
    ) async {
      await tester.pumpSurface3d(
        ScenePadding3d(
          padding: const EdgeInsets3d.only(left: 1, top: 0.5),
          child: SceneColumn3d(
            children: <Widget>[
              const SceneSizedBox3d(height: 0.25),
              control('below', <String>[]),
            ],
          ),
        ),
      );
      final box = tester.layout3d<Semantics3d>(
        find3d.bySemanticsLabel('below'),
      );

      var summed = Offset3d.zero;
      for (Layout3d? node = box; node != null; node = node.parent) {
        summed += node.offset;
      }
      expect(box.drawnOffsetInSurface.x, closeTo(summed.x, 1e-6));
      expect(box.drawnOffsetInSurface.y, closeTo(summed.y, 1e-6));
      expect(box.drawnOffsetInSurface.z, closeTo(summed.z, 1e-6));
    });

    testWidgets('a stack\'s depth step and a node offset above the box both '
        'count, because that is where the geometry is', (tester) async {
      await tester.pumpSurface3d(
        SceneStack3d(
          depthStep: 0.1,
          children: <Widget>[
            const SceneSizedBox3d.cube(1),
            SceneCenter3d(child: control('front', <String>[])),
          ],
        ),
      );
      final box = tester.layout3d<Semantics3d>(
        find3d.bySemanticsLabel('front'),
      );
      final before = box.drawnOffsetInSurface;
      final laidOut = box.parent!.offset.z + box.offset.z;
      // The second child is stepped a tenth of a unit toward the viewer, and
      // layout's z runs away from the viewer. The transforms are single
      // precision, so the tolerance is too.
      expect(before.z, closeTo(laidOut - 0.1, 1e-6));

      box.parent!.nodeOffset = const Offset3d(0.2, 0, 0);
      await tester.pump();
      expect(box.drawnOffsetInSurface.x, closeTo(before.x + 0.2, 1e-6));
    });

    testWidgets('a box that is not under a surface says so', (tester) async {
      expect(
        () => SizedBox3d(width: 1).drawnOffsetInSurface,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('not under a surface'),
          ),
        ),
      );
    });
  });

  group('matchers', () {
    testWidgets('hasSizeDp measures in logical pixels, hasSize3d in units', (
      tester,
    ) async {
      await tester.pumpSurface3d(
        SceneCenter3d(
          child: control('slab', <String>[], size: const Size3d(1, 0.48, 0.04)),
        ),
      );
      final slab = find3d.bySemanticsLabel('slab');

      expect(slab, hasSize3d(const Size3d(1, 0.48, 0.04)));
      expect(slab, hasSizeDp(width: 100, height: 48, depth: 4));
      expect(slab, hasSizeDp(depth: greaterThan(1)));

      expect(
        mismatchOf(hasSizeDp(width: 100, depth: 1), slab),
        allOf(
          contains('searched for boxes with semantics label "slab"'),
          contains('its depth is 4 dp'),
          isNot(contains('its width')),
        ),
      );
    });

    testWidgets('a matcher over nothing fails rather than passing vacuously', (
      tester,
    ) async {
      await tester.pumpSurface3d(const SceneSizedBox3d.cube(1));

      expect(
        mismatchOf(hasSizeDp(width: 1), find3d.bySemanticsLabel('absent')),
        contains('found no box at all'),
      );
      expect(
        mismatchOf(isReachable3d, 'a string'),
        contains('is not a Layout3d or a finder'),
      );
    });

    testWidgets('standsOnItsPanel3d catches content inset behind a face', (
      tester,
    ) async {
      await tester.pumpSurface3d(card(padding: const EdgeInsets3d.all(0.12)));
      final label = find3d.text('Volume');

      expect(label, isNot(standsOnItsPanel3d));
      expect(
        mismatchOf(standsOnItsPanel3d, label),
        allOf(
          contains('Text3d'),
          contains('"Volume"'),
          contains('12 dp behind the front face of DecoratedBox3d'),
          contains('EdgeInsets3d.all'),
        ),
      );

      await tester.pumpSurface3d(
        card(
          padding: const EdgeInsets3d.symmetric(
            horizontal: 0.12,
            vertical: 0.12,
          ),
        ),
      );
      expect(label, standsOnItsPanel3d);
    });

    testWidgets('standsOnItsPanel3d passes a box on no panel at all, and '
        'reports every box that fails', (tester) async {
      await tester.pumpSurface3d(
        SceneColumn3d(
          children: <Widget>[
            const SceneText3d('loose'),
            card(
              padding: const EdgeInsets3d.all(0.12),
              content: const SceneColumn3d(
                children: <Widget>[SceneText3d('one'), SceneText3d('two')],
              ),
            ),
          ],
        ),
      );

      expect(find3d.text('loose'), standsOnItsPanel3d);
      expect(
        mismatchOf(standsOnItsPanel3d, find3d.bySubtype<Text3d>()),
        allOf(
          contains('2 of them failed'),
          contains('"one"'),
          contains('"two"'),
        ),
      );
    });
  });
}
