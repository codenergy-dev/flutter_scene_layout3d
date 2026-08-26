// Text as a box: what a [Text3d] reports to the layout protocol, and what the
// unit contract does to it.
//
// The test font makes every glyph exactly `fontSize` wide, with a line
// `fontSize` tall and its baseline at 0.75 of that. At the default metrics a
// logical pixel is 0.01 world units, so a five-letter word at 10pt is 0.5
// units across and 0.1 units tall.

import 'package:flutter/widgets.dart'
    show
        DefaultTextStyle,
        Directionality,
        TextAlign,
        TextDirection,
        TextOverflow,
        TextStyle,
        Widget;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const TextStyle style = TextStyle(fontSize: 10);
const TextStyle bigger = TextStyle(fontSize: 20);

/// Records what it was asked to draw, and whether it was let go of.
class RecordingRenderer extends Text3dRenderer {
  final List<Text3dRenderRequest> requests = <Text3dRenderRequest>[];
  bool disposed = false;

  @override
  void render(Text3dRenderRequest request) => requests.add(request);

  @override
  void dispose() => disposed = true;
}

/// The label under the surface's root box.
Text3d childOf(Layout3dController controller) =>
    (controller.surface!.child! as Align3d).child! as Text3d;

Layout3dSurface panel(
  Layout3d child, {
  Size3d size = const Size3d(4, 3, 0.5),
  Layout3dMetrics metrics = Layout3dMetrics.standard,
}) => laidOut(child, constraints: Constraints3d.tight(size), metrics: metrics);

void main() {
  group('sizing', () {
    test('a label is as big as its text, in world units', () {
      final text = Text3d('hello', style: style);
      panel(Center3d(child: text));
      expect(text.size.width, closeTo(0.5, 1e-9));
      expect(text.size.height, closeTo(0.1, 1e-9));
      expect(text.size.depth, 0.0);
    });

    test('it wraps into the room it is given', () {
      final text = Text3d('hello world foo bar', style: style);
      panel(
        Center3d(
          child: ConstrainedBox3d(
            additionalConstraints: const Constraints3d(maxWidth: 1.0),
            child: text,
          ),
        ),
      );
      // 100 logical pixels: 'hello' / 'world foo' / 'bar'.
      expect(text.size.height, closeTo(0.3, 1e-9));
      expect(text.textLayout!.lineCount, 3);
    });

    test('softWrap off lays every paragraph on one line', () {
      final text = Text3d('hello world foo bar', style: style, softWrap: false);
      panel(
        Center3d(
          child: ConstrainedBox3d(
            additionalConstraints: const Constraints3d(maxWidth: 1.0),
            child: text,
          ),
        ),
      );
      expect(text.textLayout!.lineCount, 1);
      // The box still cannot be wider than the room it was given, so the
      // glyphs overflow it — which is exactly what Flutter does.
      expect(text.size.width, 1.0);
      expect(text.textLayout!.longestLine, 190);
    });

    test('depth is reserved room, and defaults to none', () {
      final text = Text3d('hi', style: style, depth: 0.2);
      panel(Center3d(child: text));
      expect(text.size.depth, 0.2);
      expect(text.getMaxIntrinsicExtent(Axis3d.depth), 0.2);
    });

    test('an empty label is still a line tall', () {
      final text = Text3d('', style: style);
      panel(Center3d(child: text));
      expect(text.size.width, 0.0);
      expect(text.size.height, closeTo(0.1, 1e-9));
    });
  });

  group('the unit contract', () {
    test('a denser surface makes the same string smaller', () {
      final text = Text3d('hello', style: style);
      final surface = panel(Center3d(child: text));
      expect(text.size.width, closeTo(0.5, 1e-9));

      surface.metrics = const Layout3dMetrics(unitsPerLogicalPixel: 0.02);
      surface.flush();
      expect(text.size.width, closeTo(1.0, 1e-9));
    });

    test('the text scale grows type and nothing else', () {
      final text = Text3d('hello', style: style);
      final surface = panel(Center3d(child: text));

      surface.metrics = const Layout3dMetrics(textScaleFactor: 1.5);
      surface.flush();
      expect(text.size.width, closeTo(0.75, 1e-9));
      expect(text.size.height, closeTo(0.15, 1e-9));
      // And it costs no re-measurement: the prepared handle is in logical
      // pixels at the style's own size, which the scale multiplies.
      expect(text.logicalPixelScale, closeTo(0.015, 1e-12));
    });

    test('a change to the metrics reaches a deep label', () {
      final text = Text3d('hello', style: style);
      final surface = panel(
        Center3d(
          child: Padding3d(
            padding: const EdgeInsets3d.all(0.1),
            child: Align3d(child: text),
          ),
        ),
      );
      final before = text.size.width;
      surface.metrics = const Layout3dMetrics(unitsPerLogicalPixel: 0.005);
      surface.flush();
      expect(text.size.width, isNot(before));
      expect(text.size.width, closeTo(0.25, 1e-9));
    });
  });

  group('intrinsics', () {
    test('the widest word and the whole string on one line', () {
      final text = Text3d('hello world foo bar', style: style);
      panel(Center3d(child: text));
      expect(text.getMinIntrinsicExtent(Axis3d.horizontal), closeTo(0.5, 1e-9));
      expect(text.getMaxIntrinsicExtent(Axis3d.horizontal), closeTo(1.9, 1e-9));
    });

    test('the height depends on the width it is asked about', () {
      final text = Text3d('hello world foo bar', style: style);
      panel(Center3d(child: text));
      expect(
        text.getMinIntrinsicExtent(Axis3d.vertical, const Size3d(1.9, 0, 0)),
        closeTo(0.1, 1e-9),
      );
      expect(
        text.getMinIntrinsicExtent(Axis3d.vertical, const Size3d(1.0, 0, 0)),
        closeTo(0.3, 1e-9),
      );
    });

    test('asking costs no shaping past the first prepare', () {
      final text = Text3d('hello world foo bar', style: style);
      panel(Center3d(child: text));
      final before = debugTextParagraphCount;
      for (var width = 0.5; width < 2.0; width += 0.05) {
        text.getMaxIntrinsicExtent(Axis3d.vertical, Size3d(width, 0, 0));
      }
      text.getMinIntrinsicExtent(Axis3d.horizontal);
      expect(debugTextParagraphCount, before);
    });

    test('a stretched column under IntrinsicWidth3d takes the widest', () {
      final short = Text3d('hi', style: style);
      final long = Text3d('a longer label', style: style);
      panel(
        Center3d(
          child: IntrinsicWidth3d(
            child: Column3d(
              crossAxisAlignment: CrossAxisAlignment3d.stretch,
              children: <Layout3d>[short, long],
            ),
          ),
        ),
      );
      expect(short.size.width, closeTo(1.4, 1e-9));
      expect(long.size.width, closeTo(1.4, 1e-9));
    });
  });

  group('baselines', () {
    test('a label states the first line\'s alphabetic baseline', () {
      final text = Text3d('hello', style: style);
      panel(Center3d(child: text));
      expect(
        text.getDistanceToBaseline(Axis3d.vertical, onlyReal: true),
        closeTo(0.075, 1e-9),
      );
      // One line of type has one baseline, and it runs across the text.
      expect(
        text.getDistanceToBaseline(Axis3d.horizontal, onlyReal: true),
        isNull,
      );
      expect(text.getDistanceToBaseline(Axis3d.depth, onlyReal: true), isNull);
    });

    test('two sizes in a baseline row sit on the same line', () {
      final small = Text3d('abc', style: style);
      final large = Text3d('abc', style: bigger);
      panel(
        Center3d(
          child: Row3d(
            crossAxisAlignment: CrossAxisAlignment3d.baseline,
            children: <Layout3d>[small, large],
          ),
        ),
      );
      // The larger baseline is 15 logical pixels down, the smaller 7.5, so
      // the small one is pushed down by the difference and the two land on
      // one line.
      expect(small.offset.y, closeTo(0.075, 1e-9));
      expect(large.offset.y, 0.0);
      expect(
        small.offset.y +
            small.getDistanceToBaseline(Axis3d.vertical, onlyReal: true)!,
        closeTo(
          large.offset.y +
              large.getDistanceToBaseline(Axis3d.vertical, onlyReal: true)!,
          1e-9,
        ),
      );
    });

    test('the wrapping case reports the first line, not the last', () {
      final text = Text3d('hello world foo bar', style: style);
      panel(
        Center3d(
          child: ConstrainedBox3d(
            additionalConstraints: const Constraints3d(maxWidth: 1.0),
            child: text,
          ),
        ),
      );
      expect(text.textLayout!.lineCount, 3);
      expect(
        text.getDistanceToBaseline(Axis3d.vertical, onlyReal: true),
        closeTo(0.075, 1e-9),
      );
    });
  });

  group('overflow', () {
    test('maxLines cuts the box down to the lines it keeps', () {
      final text = Text3d('hello world foo bar', style: style, maxLines: 2);
      panel(
        Center3d(
          child: ConstrainedBox3d(
            additionalConstraints: const Constraints3d(maxWidth: 0.6),
            child: text,
          ),
        ),
      );
      expect(text.size.height, closeTo(0.2, 1e-9));
      expect(text.textLayout!.didExceedMaxLines, isTrue);
    });

    test('ellipsis marks the last line kept', () {
      final text = Text3d(
        'hello world foo bar',
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
      panel(
        Center3d(
          child: ConstrainedBox3d(
            additionalConstraints: const Constraints3d(maxWidth: 0.6),
            child: text,
          ),
        ),
      );
      expect(text.textLayout!.lines.single.runs.last.text, '…');
      expect(text.size.width, closeTo(0.6, 1e-9));
    });

    test('an unwrapped line with an ellipsis is cut to the box', () {
      final text = Text3d(
        'hello world',
        style: style,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      );
      panel(
        Center3d(
          child: ConstrainedBox3d(
            additionalConstraints: const Constraints3d(maxWidth: 0.6),
            child: text,
          ),
        ),
      );
      expect(text.textLayout!.lineCount, 1);
      expect(text.textLayout!.lines.single.runs.last.text, '…');
      expect(text.size.width, closeTo(0.6, 1e-9));
    });
  });

  group('relayout', () {
    test('the same question a second time is not asked again', () {
      final text = Text3d('hello world', style: style);
      final surface = panel(Center3d(child: text));
      final first = text.textLayout;
      text.markNeedsLayout();
      surface.flush();
      expect(text.textLayout, same(first));
    });

    test('a new width relayouts, and consults no font', () {
      final box = ConstrainedBox3d(
        additionalConstraints: const Constraints3d(maxWidth: 2.0),
        child: Text3d('hello world foo bar', style: style),
      );
      final surface = panel(Center3d(child: box));
      final text = box.child! as Text3d;
      expect(text.textLayout!.lineCount, 1);

      final before = debugTextParagraphCount;
      box.additionalConstraints = const Constraints3d(maxWidth: 0.6);
      surface.flush();
      expect(text.textLayout!.lineCount, 4);
      expect(debugTextParagraphCount, before);
    });

    test('a new string is measured again; a new alignment is not', () {
      final text = Text3d('hello', style: style);
      final surface = panel(Center3d(child: text));

      var before = debugTextParagraphCount;
      text.textAlign = TextAlign.center;
      surface.flush();
      expect(debugTextParagraphCount, before);

      before = debugTextParagraphCount;
      text.data = 'goodbye';
      surface.flush();
      expect(debugTextParagraphCount, greaterThan(before));
      expect(text.size.width, closeTo(0.7, 1e-9));
    });

    test('a new style resizes the box', () {
      final text = Text3d('hello', style: style);
      final surface = panel(Center3d(child: text));
      expect(text.size.width, closeTo(0.5, 1e-9));
      text.style = bigger;
      surface.flush();
      expect(text.size.width, closeTo(1.0, 1e-9));
    });
  });

  group('the scene', () {
    test('a ray finds the label, not the gap between its letters', () {
      final text = Text3d('hello', style: style);
      final surface = panel(Center3d(child: text));
      // The panel is 4 by 3 and the 0.5 by 0.1 label is centred on it, so it
      // spans x 1.75..2.25 and y 1.45..1.55.
      expect(surface.hitTestAt(const Offset3d(2.0, 1.5, 0)).target, same(text));
      expect(surface.hitTestAt(const Offset3d(2.0, 1.0, 0)).isEmpty, isTrue);
    });

    test(
      'a renderer is asked after every layout, and let go of at the end',
      () {
        final renderer = RecordingRenderer();
        final text = Text3d('hello', style: style, renderer: renderer);
        final surface = panel(Center3d(child: text));
        expect(renderer.requests, hasLength(1));
        final request = renderer.requests.single;
        expect(request.node, same(text.node));
        expect(request.layout.lines.single.width, 50);
        expect(request.unitsPerLogicalPixel, closeTo(0.01, 1e-12));
        expect(request.logicalPixelsPerUnit, 100);
        expect(request.size, text.size);

        text.data = 'goodbye';
        surface.flush();
        expect(renderer.requests, hasLength(2));

        text.dispose();
        expect(renderer.disposed, isTrue);
      },
    );

    test('replacing a renderer disposes the one it replaced', () {
      final first = RecordingRenderer();
      final second = RecordingRenderer();
      final text = Text3d('hello', style: style, renderer: first);
      final surface = panel(Center3d(child: text));
      text.renderer = second;
      surface.flush();
      expect(first.disposed, isTrue);
      expect(second.requests, hasLength(1));
    });
  });

  group('the declarative layer', () {
    testWidgets('SceneText3d owns a Text3d and updates it in place', (
      tester,
    ) async {
      final parent = Node();
      final controller = Layout3dController();

      Widget frame(String data) => Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: style,
          child: SceneLayout3d(
            parent: parent,
            size: const Size3d(4, 3, 0.5),
            controller: controller,
            child: SceneCenter3d(child: SceneText3d(data)),
          ),
        ),
      );

      await tester.pumpWidget(frame('hello'));
      final text = childOf(controller);
      expect(text.data, 'hello');
      // The ambient DefaultTextStyle is what a label is drawn in.
      expect(text.style.fontSize, 10);
      expect(text.textDirection, TextDirection.ltr);
      expect(text.size.width, closeTo(0.5, 1e-9));

      await tester.pumpWidget(frame('goodbye'));
      expect(childOf(controller), same(text));
      expect(text.data, 'goodbye');
      expect(text.size.width, closeTo(0.7, 1e-9));
    });

    testWidgets('a style passed in is merged onto the inherited one', (
      tester,
    ) async {
      final parent = Node();
      final controller = Layout3dController();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: DefaultTextStyle(
            style: style,
            child: SceneLayout3d(
              parent: parent,
              size: const Size3d(4, 3, 0.5),
              controller: controller,
              child: const SceneCenter3d(
                child: SceneText3d('hello', style: TextStyle(fontSize: 20)),
              ),
            ),
          ),
        ),
      );
      final text = childOf(controller);
      expect(text.style.fontSize, 20);
      expect(text.textDirection, TextDirection.rtl);
      expect(text.size.width, closeTo(1.0, 1e-9));
    });
  });
}
