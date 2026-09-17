// Not a behavioural test: it is the compiler checking the dartdoc examples in
// `lib/src/widgets/drag.dart`, which named `SceneDecoratedBox3d` before that
// class existed, and the ones in `lib/src/boxes/visibility.dart` and
// `lib/src/widgets/layouts.dart` beside them. A code fence nothing compiles is
// how documentation drifts, and this file is the cheapest guard against it.
import 'dart:ui' show Color;

import 'package:flutter/widgets.dart'
    show
        Animation,
        BuildContext,
        Curves,
        FontWeight,
        InlineSpan,
        TextSpan,
        TextStyle,
        TickerProvider,
        Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class Photo {}

/// A question with a row of its own, standing in for the item a keep-alive
/// example wraps.
class Question {
  const Question(this.text);

  final String text;
}

class AnswerRow extends SceneText3d {
  AnswerRow({required Question question, super.key}) : super(question.text);
}

const BoxDecoration3d cardDecoration = BoxDecoration3d(
  color: Color(0xFF202124),
  borderRadius: BorderRadius3d.circular(12),
);
const BoxDecoration3d thumbnail = BoxDecoration3d(color: Color(0xFF1B6EF3));
const BoxDecoration3d deleteRed = BoxDecoration3d(color: Color(0xFFB3261E));

Widget draggableExample(Photo photo, Widget label) => SceneDraggable3d<Photo>(
  data: photo,
  startMode: const Drag3dStartMode.longPress(),
  feedbackBuilder: (_) => DecoratedBox3d(
    decoration: cardDecoration,
    child: SizedBox3d(width: 0.6, height: 0.4, depth: 0.02),
  ),
  child: SceneDecoratedBox3d(decoration: thumbnail, child: label),
);

Widget dismissibleExample(Widget row, void Function() removeItem) =>
    SceneDismissible3d(
      background: const SceneDecoratedBox3d(decoration: deleteRed),
      onDismissed: (_) => removeItem(),
      child: row,
    );

Widget keepAliveExample(List<Question> questions) => SceneListView3d.builder(
  itemCount: questions.length,
  itemExtent: 0.6,
  itemBuilder: (context, index) =>
      SceneKeepAlive3d(child: AnswerRow(question: questions[index])),
);

Widget richTextExample(BuildContext context, String name) => SceneRichText3d(
  text: TextSpan(
    style: const TextStyle(fontSize: 14),
    children: <InlineSpan>[
      const TextSpan(text: 'Signed, '),
      TextSpan(
        text: name,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    ],
  ),
);

/// The arrival examples: the widget one from `SceneMotionTransition3d`'s own
/// dartdoc, and the push from the README's *A route that arrives*.
Widget motionExample(Animation<double> animation, Widget dialog) =>
    SceneMotionTransition3d(
      animation: animation,
      motion: const Motion3d.grow(),
      child: dialog,
    );

Future<bool?> pushExample(Overlay3d overlay, TickerProvider vsync) {
  final navigator = Navigator3d(
    overlay,
    vsync: vsync,
    transition: const TimedRoute3dTransition(
      duration: Duration(milliseconds: 220),
    ),
  );
  return navigator.push(
    WidgetPageRoute3d<bool>(
      motion: const Motion3d.grow(),
      builder: (context, route) => SceneGestureDetector3d(
        onTap: () => route.pop(true),
        child: const SceneText3d('Yes'),
      ),
    ),
  );
}

/// The fade examples: the widget ones from `SceneOpacity3d`,
/// `SceneFadeTransition3d` and `SceneAnimatedOpacity3d`, and the README's
/// *Fading a subtree*.
Widget fadeExamples(
  bool enabled,
  bool selected,
  Animation<double> animation,
  Widget dialog,
  Widget badge,
  List<Widget> controls,
) => SceneColumn3d(
  children: <Widget>[
    SceneOpacity3d(
      opacity: enabled ? 1.0 : 0.38,
      child: const SceneContainer3d(width: 1, height: 0.3),
    ),
    SceneFadeTransition3d(opacity: animation, child: dialog),
    SceneAnimatedOpacity3d(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      opacity: selected ? 1.0 : 0.0,
      child: badge,
    ),
    SceneOpacity3d(
      opacity: enabled ? 1.0 : 0.38,
      child: SceneColumn3d(children: controls),
    ),
  ],
);

void main() {
  test('the fade dartdoc and README examples compile as written', () {
    expect(fadeExamples, isNotNull);
  });

  test('the arrival dartdoc and README examples compile as written', () {
    expect(motionExample, isNotNull);
    expect(pushExample, isNotNull);
  });

  test('the keep-alive and rich text dartdoc examples compile as written', () {
    expect(keepAliveExample(const <Question>[Question('why')]), isNotNull);
    expect(richTextExample, isNotNull);
  });

  test('the drag dartdoc examples compile as written', () {
    expect(draggableExample(Photo(), const SceneText3d('label')), isNotNull);
    expect(dismissibleExample(const SceneText3d('row'), () {}), isNotNull);
  });
}
