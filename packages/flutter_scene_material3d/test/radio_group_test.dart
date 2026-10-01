// RadioGroup3d: the radios and the rows below it take their value from it,
// and an arrow moves the choice and the focus together.

import 'dart:ui' show SemanticsRole;

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart'
    show FocusManager, StatefulBuilder, Widget;
import 'package:flutter_scene_layout3d/testing.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'surfaces_support.dart';

/// Three radios in a row, or three rows in a column, choosing an `int` held
/// here — so a test can read what the group was told and what it shows.
class _Choice {
  int? value = 1;
  final List<int?> reported = <int?>[];
}

Widget _radios(_Choice choice, {Set<int> disabled = const <int>{}}) =>
    StatefulBuilder(
      builder: (context, setState) => RadioGroup3d<int>(
        groupValue: choice.value,
        onChanged: (value) {
          choice.reported.add(value);
          setState(() => choice.value = value);
        },
        child: SceneRow3d(
          mainAxisSize: MainAxisSize3d.min,
          children: <Widget>[
            for (var i = 0; i < 3; i++)
              Radio3d<int>(
                value: i,
                enabled: disabled.contains(i) ? false : null,
                semanticLabel: 'Option $i',
              ),
          ],
        ),
      ),
    );

Widget _tiles(_Choice choice) => StatefulBuilder(
  builder: (context, setState) => SceneSizedBox3d(
    width: 3,
    child: RadioGroup3d<int>(
      groupValue: choice.value,
      onChanged: (value) {
        choice.reported.add(value);
        setState(() => choice.value = value);
      },
      child: SceneColumn3d(
        mainAxisSize: MainAxisSize3d.min,
        crossAxisAlignment: CrossAxisAlignment3d.stretch,
        depthAxisAlignment: CrossAxisAlignment3d.start,
        children: <Widget>[
          for (var i = 0; i < 3; i++)
            RadioListTile3d<int>.text(title: 'Option $i', value: i),
        ],
      ),
    ),
  ),
);

/// The semantics node announcing [label].
Semantics3d _announced(Layout3dSurface surface, String label) =>
    boxesOf<Semantics3d>(
      surface,
    ).firstWhere((box) => box.properties.label == label);

/// The focus box of the control announcing [label].
Focus3d _focusOf(Layout3dSurface surface, String label) {
  final found = <Focus3d>[];
  void walk(Layout3d box) {
    if (box is Focus3d) found.add(box);
    box.visitChildren(walk);
  }

  walk(_announced(surface, label));
  return found.single;
}

void _unfocus() {
  FocusManager.instance.primaryFocus?.unfocus();
  FocusManager.instance.applyFocusChangesIfNeeded();
}

void main() {
  testWidgets('a radio takes the group\'s value and reports through it', (
    tester,
  ) async {
    final choice = _Choice();
    final pumped = await pumpComponent(tester, () => _radios(choice));
    expect(
      <bool?>[
        for (var i = 0; i < 3; i++)
          _announced(pumped.surface, 'Option $i').properties.checked,
      ],
      <bool>[false, true, false],
    );

    final target = _announced(pumped.surface, 'Option 2');
    pumped.pointer.down(
      rayAt(pumped.surface, target.drawnOffsetInSurface + target.size.center),
    );
    pumped.pointer.up();
    await tester.pumpAndSettle();
    expect(choice.reported, <int>[2]);
    expect(_announced(pumped.surface, 'Option 2').properties.checked, isTrue);
    expect(_announced(pumped.surface, 'Option 1').properties.checked, isFalse);
  });

  testWidgets('the group publishes nothing of its own', (tester) async {
    // Flutter's wears `radioGroup` on a node whose children are its radios.
    // A `Semantics3d` has no children in that tree, so a group node here
    // would group nothing — and the same absence is what a tab bar's node
    // tripped over, in a frame with semantics on.
    final pumped = await pumpComponent(tester, () => _radios(_Choice()));
    expect(
      boxesOf<Semantics3d>(
        pumped.surface,
      ).where((box) => box.properties.role == SemanticsRole.radioGroup),
      isEmpty,
    );
    expect(boxesOf<Semantics3d>(pumped.surface), hasLength(3));
  });

  testWidgets('an arrow moves the choice and the focus together', (
    tester,
  ) async {
    addTearDown(_unfocus);
    final choice = _Choice();
    final pumped = await pumpComponent(tester, () => _radios(choice));
    _focusOf(pumped.surface, 'Option 1').requestFocus();
    FocusManager.instance.applyFocusChangesIfNeeded();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(choice.reported, <int>[2]);
    expect(_focusOf(pumped.surface, 'Option 2').focusNode.hasFocus, isTrue);

    // Round the end, as Flutter's group goes.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(choice.reported, <int>[2, 0]);
    expect(_focusOf(pumped.surface, 'Option 0').focusNode.hasFocus, isTrue);

    // Left and up are the previous one.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(choice.reported, <int>[2, 0, 2, 1]);
    expect(_focusOf(pumped.surface, 'Option 1').focusNode.hasFocus, isTrue);
  });

  testWidgets('and passes over a radio that is switched off', (tester) async {
    addTearDown(_unfocus);
    final choice = _Choice()..value = 0;
    final pumped = await pumpComponent(
      tester,
      () => _radios(choice, disabled: <int>{1}),
    );
    expect(_announced(pumped.surface, 'Option 1').properties.enabled, isFalse);
    _focusOf(pumped.surface, 'Option 0').requestFocus();
    FocusManager.instance.applyFocusChangesIfNeeded();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(choice.reported, <int>[2]);
  });

  testWidgets('an arrow on anything else in the group goes on up the walk', (
    tester,
  ) async {
    addTearDown(_unfocus);
    final choice = _Choice();
    var pressed = 0;
    final pumped = await pumpComponent(
      tester,
      () => RadioGroup3d<int>(
        groupValue: choice.value,
        onChanged: choice.reported.add,
        child: SceneRow3d(
          mainAxisSize: MainAxisSize3d.min,
          children: <Widget>[
            TextButton3d(
              semanticLabel: 'Clear',
              onPressed: () => pressed++,
              child: const SceneText3d('Clear'),
            ),
            const Radio3d<int>(value: 0, semanticLabel: 'Option 0'),
          ],
        ),
      ),
    );
    _focusOf(pumped.surface, 'Clear').requestFocus();
    FocusManager.instance.applyFocusChangesIfNeeded();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(choice.reported, isEmpty);
    // The default the walk ends at moved the focus instead.
    expect(_focusOf(pumped.surface, 'Option 0').focusNode.hasFocus, isTrue);
    expect(pressed, 0);
  });

  testWidgets('a row joins the group, and the radio in it does not', (
    tester,
  ) async {
    addTearDown(_unfocus);
    final choice = _Choice();
    final pumped = await pumpComponent(tester, () => _tiles(choice));
    // One node per row, as without a group: the radio in a row is only its
    // picture.
    final announced = boxesOf<Semantics3d>(
      pumped.surface,
    ).where((box) => box.properties.label != null).toList();
    expect(announced.map((box) => box.properties.label), <String>[
      'Option 0',
      'Option 1',
      'Option 2',
    ]);
    expect(announced.map((box) => box.properties.checked), <bool>[
      false,
      true,
      false,
    ]);

    _focusOf(pumped.surface, 'Option 1').requestFocus();
    FocusManager.instance.applyFocusChangesIfNeeded();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(choice.reported, <int>[2]);
    expect(_focusOf(pumped.surface, 'Option 2').focusNode.hasFocus, isTrue);
    expect(_announced(pumped.surface, 'Option 2').properties.checked, isTrue);
  });

  testWidgets('a radio of another type does not see the group', (tester) async {
    final pumped = await pumpComponent(
      tester,
      () => RadioGroup3d<int>(
        groupValue: 1,
        onChanged: (_) {},
        child: const Radio3d<String>(
          value: 'a',
          groupValue: 'a',
          semanticLabel: 'Letter',
        ),
      ),
    );
    final radio = _announced(pumped.surface, 'Letter');
    // Its own value, and no callback of its own, so it cannot be changed.
    expect(radio.properties.checked, isTrue);
    expect(radio.properties.enabled, isFalse);
  });

  testWidgets('a radio with no group reads its own value, as it always has', (
    tester,
  ) async {
    final reported = <int?>[];
    final pumped = await pumpComponent(
      tester,
      () => Radio3d<int>(
        value: 3,
        groupValue: 1,
        onChanged: reported.add,
        semanticLabel: 'Alone',
      ),
    );
    expect(_announced(pumped.surface, 'Alone').properties.checked, isFalse);
    expect(_announced(pumped.surface, 'Alone').properties.enabled, isTrue);
    final panel = pumped.panels.first;
    pumped.pointer.down(
      rayAt(pumped.surface, panel.drawnOffsetInSurface + panel.size.center),
    );
    pumped.pointer.up();
    await tester.pump();
    expect(reported, <int>[3]);
  });
}
