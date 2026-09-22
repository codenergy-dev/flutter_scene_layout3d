// How far one label grows with the reader's font setting: an explicit
// `textScaler` on a text box, and `SceneTextScaling3d` for a subtree.
//
// The reader's setting lives on the surface and stays there. What is tested
// here is what a label does with it — an icon that must not grow, and a
// component's labels that grow and then stop.
//
// The test font makes every glyph exactly `fontSize` wide, so a five-letter
// word at 10pt is 50 logical pixels — 0.5 world units at the default rate.

import 'package:flutter/painting.dart' show TextScaler, TextSpan, TextStyle;
import 'package:flutter/widgets.dart'
    show MediaQuery, MediaQueryData, SizedBox, Widget;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/testing.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const TextStyle style = TextStyle(fontSize: 10);

/// [child] on a surface under a platform font setting of [scaler].
Widget atScale(TextScaler scaler, Widget child) => MediaQuery(
  data: MediaQueryData(textScaler: scaler),
  child: SizedBox.expand(
    child: SceneLayout3d(
      parent: Node(),
      size: const Size3d(4, 3, 0.5),
      child: SceneCenter3d(child: child),
    ),
  ),
);

/// How wide the one `Text3d` on screen came out, in world units.
double widthOf(WidgetTester tester, [int index = 0]) =>
    tester.layout3d<Text3d>(find3d.bySubtype<Text3d>().at(index)).size.width;

void main() {
  group('a text box\'s own scaler', () {
    test('replaces the surface\'s, and null follows it', () {
      final surface = Layout3dSurface(
        metrics: Layout3dMetrics(textScaler: TextScaler.linear(2)),
        child: Text3d('hello', style: style),
      )..flush();
      final label = surface.child! as Text3d;
      expect(label.size.width, closeTo(1.0, 1e-9), reason: 'the surface\'s');
      expect(label.effectiveTextScaler, TextScaler.linear(2));

      label.textScaler = TextScaler.noScaling;
      surface.flush();
      expect(label.size.width, closeTo(0.5, 1e-9), reason: 'its own');
      expect(label.effectiveTextScaler, TextScaler.noScaling);

      label.textScaler = null;
      surface.flush();
      expect(label.size.width, closeTo(1.0, 1e-9), reason: 'back again');
    });

    test('a paragraph measures with it too', () {
      final surface = Layout3dSurface(
        metrics: Layout3dMetrics(textScaler: TextScaler.linear(2)),
        child: RichText3d(
          const TextSpan(text: 'hello', style: style),
          textScaler: TextScaler.noScaling,
        ),
      )..flush();
      final paragraph = surface.child! as RichText3d;
      expect(paragraph.size.width, closeTo(0.5, 1e-9));
      expect(paragraph.painter.textScaler, TextScaler.noScaling);
    });
  });

  group('SceneText3d', () {
    testWidgets('an explicit scaler ignores the reader\'s setting', (
      tester,
    ) async {
      await tester.pumpWidget(
        atScale(
          TextScaler.linear(2),
          const SceneText3d(
            'hello',
            style: style,
            textScaler: TextScaler.noScaling,
          ),
        ),
      );
      expect(widthOf(tester), closeTo(0.5, 1e-9));
    });

    testWidgets('with none, it still follows the surface', (tester) async {
      await tester.pumpWidget(
        atScale(TextScaler.linear(2), const SceneText3d('hello', style: style)),
      );
      expect(widthOf(tester), closeTo(1.0, 1e-9));
      expect(
        tester.layout3d<Text3d>(find3d.bySubtype<Text3d>()).textScaler,
        isNull,
        reason: 'following, not holding a copy',
      );
    });
  });

  group('SceneTextScaling3d', () {
    testWidgets('clamped stops a label growing past its ceiling', (
      tester,
    ) async {
      await tester.pumpWidget(
        atScale(
          TextScaler.linear(2),
          SceneTextScaling3d.clamped(
            maxScaleFactor: 1.3,
            child: const SceneText3d('hello', style: style),
          ),
        ),
      );
      expect(widthOf(tester), closeTo(0.65, 1e-9));
    });

    testWidgets('and lets a smaller setting through unchanged', (tester) async {
      await tester.pumpWidget(
        atScale(
          TextScaler.linear(1.2),
          SceneTextScaling3d.clamped(
            maxScaleFactor: 1.3,
            child: const SceneText3d('hello', style: style),
          ),
        ),
      );
      expect(widthOf(tester), closeTo(0.6, 1e-9));
    });

    testWidgets('reaches every label below it, however deep', (tester) async {
      await tester.pumpWidget(
        atScale(
          TextScaler.linear(2),
          SceneTextScaling3d.clamped(
            maxScaleFactor: 1.5,
            child: const SceneColumn3d(
              mainAxisSize: MainAxisSize3d.min,
              children: <Widget>[
                ScenePadding3d(
                  padding: EdgeInsets3d.all(0.1),
                  child: SceneText3d('hello', style: style),
                ),
                SceneText3d('world', style: style),
              ],
            ),
          ),
        ),
      );
      expect(widthOf(tester, 0), closeTo(0.75, 1e-9));
      expect(widthOf(tester, 1), closeTo(0.75, 1e-9));
    });

    testWidgets('a clamp inside a clamp narrows it', (tester) async {
      await tester.pumpWidget(
        atScale(
          TextScaler.linear(3),
          SceneTextScaling3d.clamped(
            maxScaleFactor: 2,
            child: SceneTextScaling3d.clamped(
              maxScaleFactor: 1.5,
              child: const SceneText3d('hello', style: style),
            ),
          ),
        ),
      );
      expect(widthOf(tester), closeTo(0.75, 1e-9));
    });

    testWidgets('an explicit scaler on the label wins over the scope', (
      tester,
    ) async {
      await tester.pumpWidget(
        atScale(
          TextScaler.linear(2),
          SceneTextScaling3d.clamped(
            maxScaleFactor: 1.3,
            child: const SceneText3d(
              'hello',
              style: style,
              textScaler: TextScaler.noScaling,
            ),
          ),
        ),
      );
      expect(widthOf(tester), closeTo(0.5, 1e-9));
    });

    testWidgets('follows the reader\'s setting when it changes', (
      tester,
    ) async {
      Widget frame(TextScaler scaler) => atScale(
        scaler,
        SceneTextScaling3d.clamped(
          maxScaleFactor: 1.3,
          child: const SceneText3d('hello', style: style),
        ),
      );
      await tester.pumpWidget(frame(TextScaler.noScaling));
      expect(widthOf(tester), closeTo(0.5, 1e-9));
      await tester.pumpWidget(frame(TextScaler.linear(1.2)));
      expect(widthOf(tester), closeTo(0.6, 1e-9));
      await tester.pumpWidget(frame(TextScaler.linear(3)));
      expect(widthOf(tester), closeTo(0.65, 1e-9));
    });
  });
}
