// Both halves of the theme channel: the owner slot a Layout3d reads inside
// performLayout, and the inherited widget the declarative layer reads.
//
// The slot half is the one that could not exist before phase 0 of the
// catalogue plan, and it is the half a component actually needs: a token
// decides a size, a size is decided in performLayout, and performLayout has
// no BuildContext.

import 'package:flutter/widgets.dart'
    show Builder, BuildContext, SizedBox, State, StatefulWidget, Widget;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A renderer that draws nothing, for asking whether a factory was installed.
class FakeRenderer3d implements Text3dRenderer {
  @override
  void dispose() {}

  @override
  void render(Text3dRenderRequest request) {}
}

FakeRenderer3d makeFakeRenderer() => FakeRenderer3d();

void main() {
  const deep = Theme3dData(
    thickness: Thickness3d(raised: 8.0),
    colorScheme: ColorScheme3d.dark,
  );

  group('a box reading the slot', () {
    test('sees the baseline when nothing published a theme', () {
      // Falling back rather than throwing, the way Layout3d.metrics does: a
      // component drawn in the wrong-but-valid baseline is visible and
      // diagnosable, and a layout pass that threw over a missing default is
      // neither.
      final box = ThemedBox();
      expect(box.theme3d, Theme3dData.light);
      expect(box.hasTheme3d, isFalse);

      laidOut(box, constraints: Constraints3d.loose(const Size3d(10, 10, 10)));
      expect(box.sawTheme, Theme3dData.light);
      expect(box.sawPublishedTheme, isFalse);
      expect(box.size.depth, closeTo(0.04, 1e-9));
    });

    test('sees the theme the surface holds, inside performLayout', () {
      final box = ThemedBox();
      final surface = Layout3dSurface(
        constraints: Constraints3d.loose(const Size3d(10, 10, 10)),
        child: box,
      )..setSlot(Theme3dData.slot, deep);
      surface.flush();

      expect(box.sawTheme, deep);
      expect(box.sawPublishedTheme, isTrue);
      // 8dp of thickness at the default rate of 0.01 units per logical pixel.
      expect(box.size.depth, closeTo(0.08, 1e-9));
    });

    test('turns a token into dp and lets the metrics reach world units', () {
      // The one-way arrow: the theme says 8dp, the metrics says what a dp is
      // worth here. Doubling the rate doubles the slab and changes no token.
      final box = ThemedBox();
      final surface = Layout3dSurface(
        constraints: Constraints3d.loose(const Size3d(10, 10, 10)),
        metrics: const Layout3dMetrics(unitsPerLogicalPixel: 0.02),
        child: box,
      )..setSlot(Theme3dData.slot, deep);
      surface.flush();
      expect(box.size.depth, closeTo(0.16, 1e-9));
      expect(box.sawTheme!.thickness.raised, 8.0);
    });

    test('is laid out again when the theme changes', () {
      // Writing a slot relayouts the subtree by default, and for a theme that
      // is exactly right: the tokens decide paddings, type sizes and
      // thicknesses, so a theme change changes sizes and nothing else would
      // tell the tree. It follows that nothing on a per-frame path may write
      // one.
      final box = ThemedBox();
      final surface = laidOut(
        box,
        constraints: Constraints3d.loose(const Size3d(10, 10, 10)),
      );
      final layouts = box.layoutCount;
      expect(box.size.depth, closeTo(0.04, 1e-9));

      surface.setSlot(Theme3dData.slot, deep);
      expect(surface.needsFlush, isTrue);
      surface.flush();

      expect(box.layoutCount, layouts + 1);
      expect(box.size.depth, closeTo(0.08, 1e-9));
    });

    test('writing the same theme again relayouts nothing', () {
      // Theme3dData has value equality, so a rebuild that produces an equal
      // theme is free. That is what makes it safe for a widget to hand the
      // same tokens down on every build.
      final box = ThemedBox();
      final surface = laidOut(
        box,
        constraints: Constraints3d.loose(const Size3d(10, 10, 10)),
      )..setSlot(Theme3dData.slot, deep);
      surface.flush();
      final layouts = box.layoutCount;

      surface.setSlot(
        Theme3dData.slot,
        const Theme3dData(
          thickness: Thickness3d(raised: 8.0),
          colorScheme: ColorScheme3d.dark,
        ),
      );
      expect(surface.needsFlush, isFalse);
      expect(box.layoutCount, layouts);
    });

    test('an imperative provider publishes it for a subtree', () {
      final box = ThemedBox();
      final provider = SlotProvider3d<Theme3dData>(
        slot: Theme3dData.slot,
        value: deep,
        child: box,
      );
      final surface = laidOut(
        provider,
        constraints: Constraints3d.loose(const Size3d(10, 10, 10)),
      );
      expect(box.sawTheme, deep);

      surface.child = null;
      expect(surface.slotValue(Theme3dData.slot), isNull);
    });
  });

  group('SceneTheme3d', () {
    testWidgets('writes both halves at once', (tester) async {
      late ThemedBox box;
      late Theme3dData seenByWidget;
      final controller = Layout3dController();

      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          constraints: Constraints3d.loose(const Size3d(10, 10, 10)),
          controller: controller,
          child: SceneTheme3d(
            data: deep,
            child: Builder(
              builder: (context) {
                seenByWidget = Theme3d.of(context);
                return _SceneThemedBox((made) => box = made);
              },
            ),
          ),
        ),
      );

      expect(seenByWidget, deep);
      expect(box.sawTheme, deep);
      expect(box.size.depth, closeTo(0.08, 1e-9));
      expect(controller.surface!.slotValue(Theme3dData.slot), deep);
    });

    testWidgets('a new theme reaches the box and relayouts it', (tester) async {
      late ThemedBox box;
      final controller = Layout3dController();

      Widget frame(Theme3dData data) => SceneLayout3d(
        parent: Node(),
        constraints: Constraints3d.loose(const Size3d(10, 10, 10)),
        controller: controller,
        child: SceneTheme3d(
          data: data,
          child: _SceneThemedBox((made) => box = made),
        ),
      );

      await tester.pumpWidget(frame(Theme3dData.light));
      expect(box.size.depth, closeTo(0.04, 1e-9));
      final layouts = box.layoutCount;

      await tester.pumpWidget(frame(deep));
      expect(box.layoutCount, greaterThan(layouts));
      expect(box.size.depth, closeTo(0.08, 1e-9));

      // And an unchanged theme costs no layout at all.
      final settled = box.layoutCount;
      await tester.pumpWidget(frame(deep));
      expect(box.layoutCount, settled);
    });

    testWidgets('taken out of the tree, it clears the slot', (tester) async {
      final controller = Layout3dController();

      Widget frame({required bool themed}) => SceneLayout3d(
        parent: Node(),
        constraints: Constraints3d.loose(const Size3d(10, 10, 10)),
        controller: controller,
        child: themed
            ? const SceneTheme3d(data: deep, child: SceneSizedBox3d.cube(1))
            : const SceneSizedBox3d.cube(1),
      );

      await tester.pumpWidget(frame(themed: true));
      expect(controller.surface!.slotValue(Theme3dData.slot), deep);

      await tester.pumpWidget(frame(themed: false));
      expect(controller.surface!.slotValue(Theme3dData.slot), isNull);
    });

    testWidgets('installs a text renderer only when asked', (tester) async {
      final controller = Layout3dController();
      Text3dRendererFactory? seen;

      Widget frame({Text3dRendererFactory? factory}) => SceneLayout3d(
        parent: Node(),
        constraints: Constraints3d.loose(const Size3d(10, 10, 10)),
        controller: controller,
        child: SceneTheme3d(
          data: Theme3dData.light,
          textRendererFactory: factory,
          child: Builder(
            builder: (context) {
              seen = DefaultTextRenderer3d.maybeOf(context);
              return const SceneSizedBox3d.cube(1);
            },
          ),
        ),
      );

      // A theme is tokens. Left alone it does not reach outside that
      // vocabulary, because a renderer is a resource with an ownership
      // contract rather than a token.
      await tester.pumpWidget(frame());
      expect(seen, isNull);

      // Offered, and then it is one call for "here is my theme, and here is
      // how labels are drawn".
      await tester.pumpWidget(frame(factory: makeFakeRenderer));
      expect(seen, same(makeFakeRenderer));
    });
  });

  group('Theme3d in the widget layer', () {
    testWidgets('falls back to the light baseline with no theme above', (
      tester,
    ) async {
      late Theme3dData seen;
      Theme3dData? maybe = Theme3dData.dark;

      await tester.pumpWidget(
        Builder(
          builder: (context) {
            seen = Theme3d.of(context);
            maybe = Theme3d.maybeOf(context);
            return const SizedBox.shrink();
          },
        ),
      );

      expect(seen, Theme3dData.light);
      expect(maybe, isNull);
    });

    testWidgets('can theme a subtree with no layout in it', (tester) async {
      late Theme3dData seen;
      await tester.pumpWidget(
        Theme3d(
          data: deep,
          child: Builder(
            builder: (context) {
              seen = Theme3d.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(seen, deep);
    });

    testWidgets('notifies its dependents only when the theme changed', (
      tester,
    ) async {
      // The child is `const`, so Flutter reuses its element without
      // rebuilding it, and every notification counted here came from the
      // inherited widget rather than from the parent rebuilding.
      _ThemeProbeState.notifications = 0;
      _ThemeProbeState.saw = null;

      Widget frame(Theme3dData data) =>
          Theme3d(data: data, child: const _ThemeProbe());

      await tester.pumpWidget(frame(Theme3dData.light));
      expect(_ThemeProbeState.notifications, 1);
      expect(_ThemeProbeState.saw, Theme3dData.light);

      await tester.pumpWidget(frame(deep));
      expect(_ThemeProbeState.notifications, 2);
      expect(_ThemeProbeState.saw, deep);

      // An equal theme notifies nobody, which is what value equality buys:
      // a widget can hand the same tokens down on every build for free.
      await tester.pumpWidget(
        frame(
          const Theme3dData(
            thickness: Thickness3d(raised: 8.0),
            colorScheme: ColorScheme3d.dark,
          ),
        ),
      );
      expect(_ThemeProbeState.notifications, 2);
    });
  });

  group('SceneLayout3d.slots', () {
    testWidgets('writes the slot and not the inherited widget', (tester) async {
      // The imperative-only spelling, for a surface whose components are
      // built by hand. Theme3d.of finds nothing below it, and that is stated
      // rather than accidental.
      late ThemedBox box;
      late Theme3dData? seenByWidget;
      final controller = Layout3dController();

      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          constraints: Constraints3d.loose(const Size3d(10, 10, 10)),
          controller: controller,
          // Not a const map: Layout3dSlot has value equality, and a const
          // map key must have primitive equality. Worth knowing before you
          // spend a compile error on it.
          slots: <Layout3dSlot<Object>, Object>{Theme3dData.slot: deep},
          child: Builder(
            builder: (context) {
              seenByWidget = Theme3d.maybeOf(context);
              return _SceneThemedBox((made) => box = made);
            },
          ),
        ),
      );

      expect(box.sawTheme, deep);
      expect(seenByWidget, isNull);
    });
  });
}

/// Hosts a [ThemedBox] in the widget tree.
class _SceneThemedBox extends Layout3dWidget {
  const _SceneThemedBox(this.sink);

  final void Function(ThemedBox) sink;

  @override
  Layout3d createLayout(BuildContext context) {
    final box = ThemedBox();
    sink(box);
    return box;
  }

  @override
  void updateLayout(BuildContext context, ThemedBox layout) {}
}

/// Counts how often the theme it depends on actually notified it.
class _ThemeProbe extends StatefulWidget {
  const _ThemeProbe();

  @override
  State<_ThemeProbe> createState() => _ThemeProbeState();
}

class _ThemeProbeState extends State<_ThemeProbe> {
  static int notifications = 0;
  static Theme3dData? saw;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    notifications++;
    saw = Theme3d.of(context);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
