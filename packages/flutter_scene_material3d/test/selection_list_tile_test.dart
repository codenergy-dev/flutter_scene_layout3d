// The labelled tiles: a checkbox, a switch and a radio button that are a
// whole row. What has to hold is that there is **one control** — one node for
// a screen reader, one focus, one target, one wash — because nothing here can
// merge two into one after the fact, and that the row does what the control
// in it would have done.

import 'package:flutter/widgets.dart' show TextDirection, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/testing.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'surfaces_support.dart';

const Theme3dData _theme = Theme3dData.light;

/// The middle of [box], in the surface's own frame, which is where
/// [rayAt] aims.
Offset3d _middleOf(Layout3d box) {
  final at = box.drawnOffsetInSurface;
  return Offset3d(at.x + box.size.width / 2, at.y + box.size.height / 2, 0);
}

/// The one label in [it], which is the tile's title.
Text3d _title(PumpedSurface it) => boxesOf<Text3d>(
  it.surface,
).firstWhere((label) => label.data == 'Remember me');

/// The control's own 40dp wash surface: the second panel, after the row's.
DecoratedBox3d _controlSurface(PumpedSurface it) => it.panels[1];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('one control, not two', () {
    final tiles = <String, Widget Function()>{
      'a checkbox tile': () => CheckboxListTile3d.text(
        title: 'Remember me',
        value: true,
        onChanged: (_) {},
      ),
      'a switch tile': () => SwitchListTile3d.text(
        title: 'Remember me',
        value: true,
        onChanged: (_) {},
      ),
      'a radio tile': () => RadioListTile3d<int>.text(
        title: 'Remember me',
        value: 1,
        groupValue: 1,
        onChanged: (_) {},
      ),
    };

    for (final MapEntry(key: name, value: build) in tiles.entries) {
      testWidgets('$name publishes one node for the whole row', (tester) async {
        final it = await pumpComponent(tester, build);
        final nodes = boxesOf<Semantics3d>(
          it.surface,
        ).where((box) => box.enabled).toList();
        expect(nodes, hasLength(1), reason: 'the control in it says nothing');
        expect(nodes.single.properties.label, 'Remember me');
        expect(nodes.single.properties.onTap, isNotNull);
        expect(
          nodes.single.properties.button,
          isNull,
          reason: 'it is the control it holds, not a button beside it',
        );
        expect(
          nodes.single.size.height,
          closeTo(ListTile3d.oneLineHeight / 100, 1e-9),
          reason: 'the reader\'s focus is the row, not the 40dp control',
        );
      });

      testWidgets('$name takes the focus once', (tester) async {
        final it = await pumpComponent(tester, build);
        // `focusIn` throws unless there is exactly one.
        expect(focusIn(it.surface), isNotNull);
      });

      testWidgets('$name has one target that reaches anywhere', (tester) async {
        final it = await pumpComponent(tester, build);
        final reaching = boxesOf<TapTarget3d>(
          it.surface,
        ).where((t) => t.effectiveMinimumSize.width > 0).toList();
        expect(reaching, hasLength(1));
        expect(identical(reaching.single, it.target), isTrue);
      });

      testWidgets('$name washes the row, and the control not at all', (
        tester,
      ) async {
        final it = await pumpComponent(tester, build);
        it.pointer.hover(rayAt(it.surface, _middleOf(_controlSurface(it))));
        expect(
          it.panel.stateLayer.opacity,
          _theme.stateLayer.hover,
          reason: 'a pointer over the control is a pointer over the row',
        );
        expect(_controlSurface(it).stateLayer, StateLayer3d.none);
      });
    }
  });

  group('a press anywhere on the row', () {
    testWidgets('ticks the box, on the words or on the box', (tester) async {
      var value = false;
      Widget build() => CheckboxListTile3d.text(
        title: 'Remember me',
        value: value,
        onChanged: (next) => value = next!,
      );
      var it = await pumpComponent(tester, build);
      it.pointer.down(rayAt(it.surface, _middleOf(_title(it))));
      it.pointer.up();
      expect(value, isTrue, reason: 'on the words');

      it = await pumpComponent(tester, build);
      it.pointer.down(rayAt(it.surface, _middleOf(_controlSurface(it))));
      it.pointer.up();
      expect(
        value,
        isFalse,
        reason: 'on the box, which answers no ray of its own',
      );
    });

    testWidgets('walks the three states when tristate', (tester) async {
      final seen = <bool?>[];
      bool? value = true;
      Widget build() => CheckboxListTile3d.text(
        title: 'Remember me',
        value: value,
        tristate: true,
        onChanged: (next) => seen.add(value = next),
      );
      var it = await pumpComponent(tester, build);
      it.pointer.down(rayAt(it.surface, _middleOf(_title(it))));
      it.pointer.up();
      it = await pumpComponent(tester, build);
      it.pointer.down(rayAt(it.surface, _middleOf(_title(it))));
      it.pointer.up();
      it = await pumpComponent(tester, build);
      it.pointer.down(rayAt(it.surface, _middleOf(_title(it))));
      it.pointer.up();
      expect(seen, <bool?>[null, false, true], reason: 'Flutter\'s order');
    });

    testWidgets('flips a switch', (tester) async {
      final seen = <bool>[];
      final it = await pumpComponent(
        tester,
        () => SwitchListTile3d.text(
          title: 'Remember me',
          value: false,
          onChanged: seen.add,
        ),
      );
      it.pointer.down(rayAt(it.surface, _middleOf(_title(it))));
      it.pointer.up();
      expect(seen, <bool>[true]);
    });

    testWidgets('chooses a radio, and leaves a chosen one alone', (
      tester,
    ) async {
      final seen = <int?>[];
      final unchosen = await pumpComponent(
        tester,
        () => RadioListTile3d<int>.text(
          title: 'Remember me',
          value: 1,
          groupValue: 2,
          onChanged: seen.add,
        ),
      );
      unchosen.pointer.down(
        rayAt(unchosen.surface, _middleOf(_title(unchosen))),
      );
      unchosen.pointer.up();
      expect(seen, <int?>[1]);

      final chosen = await pumpComponent(
        tester,
        () => RadioListTile3d<int>.text(
          title: 'Remember me',
          value: 1,
          groupValue: 1,
          onChanged: seen.add,
        ),
      );
      chosen.pointer.down(rayAt(chosen.surface, _middleOf(_title(chosen))));
      chosen.pointer.up();
      expect(seen, <int?>[1], reason: 'nothing, as Flutter\'s does');
      expect(
        chosen.semantics.properties.onTap,
        isNotNull,
        reason: 'and it is still a row that can be pressed',
      );

      final toggleable = await pumpComponent(
        tester,
        () => RadioListTile3d<int>.text(
          title: 'Remember me',
          value: 1,
          groupValue: 1,
          toggleable: true,
          onChanged: seen.add,
        ),
      );
      toggleable.pointer.down(
        rayAt(toggleable.surface, _middleOf(_title(toggleable))),
      );
      toggleable.pointer.up();
      expect(seen, <int?>[1, null]);
    });

    testWidgets('does nothing on a disabled row, which draws disabled', (
      tester,
    ) async {
      var taps = 0;
      final it = await pumpComponent(
        tester,
        () => CheckboxListTile3d.text(
          title: 'Remember me',
          value: false,
          enabled: false,
          onChanged: (_) => taps++,
        ),
      );
      it.pointer.down(rayAt(it.surface, _middleOf(_title(it))));
      it.pointer.up();
      expect(taps, 0);
      expect(it.semantics.properties.enabled, isFalse);
      expect(_title(it).style.color, _theme.colorScheme.disabledContent);
      final box = it.panels[2].decoration as BoxDecoration3d;
      expect(
        box.border.color,
        CheckboxStyle3d.of(_theme).disabledOutline,
        reason: 'the box it holds is disabled with it',
      );
    });
  });

  group('what the row says the control is', () {
    testWidgets('a checkbox row is checked, and mixed when tristate', (
      tester,
    ) async {
      final on = await pumpComponent(
        tester,
        () => CheckboxListTile3d.text(
          title: 'Remember me',
          value: true,
          onChanged: (_) {},
        ),
      );
      expect(on.semantics.properties.checked, isTrue);
      expect(on.semantics.properties.mixed, isNull);

      final mixed = await pumpComponent(
        tester,
        () => CheckboxListTile3d.text(
          title: 'Remember me',
          value: null,
          tristate: true,
          onChanged: (_) {},
        ),
      );
      expect(mixed.semantics.properties.checked, isFalse);
      expect(mixed.semantics.properties.mixed, isTrue);
    });

    testWidgets('a switch row is toggled', (tester) async {
      final it = await pumpComponent(
        tester,
        () => SwitchListTile3d.text(
          title: 'Remember me',
          value: true,
          onChanged: (_) {},
        ),
      );
      expect(it.semantics.properties.toggled, isTrue);
      expect(it.semantics.properties.checked, isNull);
    });

    testWidgets('a radio row is one of a set', (tester) async {
      final it = await pumpComponent(
        tester,
        () => RadioListTile3d<int>.text(
          title: 'Remember me',
          value: 1,
          groupValue: 1,
          onChanged: (_) {},
        ),
      );
      expect(it.semantics.properties.checked, isTrue);
      expect(it.semantics.properties.inMutuallyExclusiveGroup, isTrue);
    });

    testWidgets('.text composes the label from both lines', (tester) async {
      final it = await pumpComponent(
        tester,
        () => SwitchListTile3d.text(
          title: 'Notifications',
          subtitle: 'Only from people you follow',
          value: true,
          onChanged: (_) {},
        ),
      );
      expect(
        it.semantics.properties.label,
        'Notifications, Only from people you follow',
      );
    });
  });

  group('which end the control is at', () {
    /// Whether the control stands to the left of the title.
    bool controlIsLeft(PumpedSurface it) =>
        _controlSurface(it).drawnOffsetInSurface.x <
        _title(it).drawnOffsetInSurface.x;

    testWidgets('a checkbox and a switch trail, a radio leads', (tester) async {
      expect(
        controlIsLeft(
          await pumpComponent(
            tester,
            () => CheckboxListTile3d.text(
              title: 'Remember me',
              value: false,
              onChanged: (_) {},
            ),
          ),
        ),
        isFalse,
      );
      expect(
        controlIsLeft(
          await pumpComponent(
            tester,
            () => SwitchListTile3d.text(
              title: 'Remember me',
              value: false,
              onChanged: (_) {},
            ),
          ),
        ),
        isFalse,
      );
      expect(
        controlIsLeft(
          await pumpComponent(
            tester,
            () => RadioListTile3d<int>.text(
              title: 'Remember me',
              value: 1,
              groupValue: 2,
              onChanged: (_) {},
            ),
          ),
        ),
        isTrue,
      );
    });

    testWidgets('an affinity moves it, and the secondary goes opposite', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => CheckboxListTile3d.text(
          title: 'Remember me',
          value: false,
          controlAffinity: ListTileControlAffinity3d.leading,
          secondary: const SceneSizedBox3d(width: 0.24, height: 0.24),
          onChanged: (_) {},
        ),
      );
      expect(controlIsLeft(it), isTrue);
      final secondary = boxesOf<SizedBox3d>(
        it.surface,
      ).singleWhere((box) => box.width == 0.24);
      expect(
        secondary.drawnOffsetInSurface.x,
        greaterThan(_title(it).drawnOffsetInSurface.x),
      );
    });

    testWidgets('and trailing is the left in right to left', (tester) async {
      final it = await pumpComponent(
        tester,
        () => CheckboxListTile3d.text(
          title: 'Remember me',
          value: false,
          onChanged: (_) {},
        ),
        textDirection: TextDirection.rtl,
      );
      expect(controlIsLeft(it), isTrue);
    });
  });

  testWidgets('everything on a row stands on its face', (tester) async {
    await pumpComponent(
      tester,
      () => CheckboxListTile3d.text(
        title: 'Remember me',
        value: true,
        onChanged: (_) {},
      ),
    );
    expect(find3d.bySubtype<Text3d>(), standsOnItsPanel3d);
  });
}
