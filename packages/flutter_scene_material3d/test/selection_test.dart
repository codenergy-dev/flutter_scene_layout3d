// The three selection controls that are shape and state: the token table
// across selection and enablement, the geometry at each state, the 48dp
// target a 40dp control has to reach with, what each one announces, and the
// tier a toggle is allowed to touch.
//
// `Slider3d` is next door in `slider_test.dart`: it is a drag rather than a
// press, and what it has to prove is about the gesture arena.

import 'package:flutter/widgets.dart'
    show BuildContext, State, StatefulWidget, Widget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'surfaces_support.dart';

/// One world unit is a hundred logical pixels at the standard metrics, which
/// is what `pumpComponent` gives every test here.
double dp(double logical) => logical / 100.0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const theme = Theme3dData.light;
  final checkboxStyle = CheckboxStyle3d.of(theme);
  final radioStyle = RadioStyle3d.of(theme);
  final switchStyle = SwitchStyle3d.of(theme);

  group('the checkbox token table', () {
    testWidgets('an empty box is transparent inside a 2dp outline', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => Checkbox3d(value: false, onChanged: (_) {}),
      );
      // Two panels: the wash surface, and the box on it.
      expect(it.panels.length, 2);
      final box = it.panels[1].decoration as BoxDecoration3d;
      expect(box.color.a, 0.0, reason: 'an empty box has no fill');
      expect(box.border.color, theme.colorScheme.onSurfaceVariant);
      expect(box.border.width, checkboxStyle.outlineWidth);
      expect(box.borderRadius, const BorderRadius3d.circular(2.0));
      expect(
        boxesOf<Text3d>(it.surface),
        isEmpty,
        reason: 'no mark, so no glyph at all rather than a transparent one',
      );
    });

    testWidgets('a full box is primary with a mark on it and no outline', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => Checkbox3d(value: true, onChanged: (_) {}),
      );
      final box = it.panels[1].decoration as BoxDecoration3d;
      expect(box.color, theme.colorScheme.primary);
      expect(
        box.border.isNone,
        isTrue,
        reason: 'the fill is the edge; an outline round it would compete',
      );
      final mark = boxesOf<Text3d>(it.surface).single;
      expect(mark.style.color, theme.colorScheme.onPrimary);
      expect(mark.style.fontSize, checkboxStyle.markSize);
    });

    testWidgets('a disabled empty box dims its outline and keeps its fill', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => const Checkbox3d(value: false),
      );
      final box = it.panels[1].decoration as BoxDecoration3d;
      expect(box.color.a, 0.0);
      expect(box.border.color, theme.colorScheme.disabledContent);
    });

    testWidgets(
      'a disabled full box stays full, which is the one thing disabled '
      'does not win',
      (tester) async {
        // The precedence every table in this package shares: disabled beats
        // everything *except* the fact of the selection, because that is
        // information the reader still needs.
        final it = await pumpComponent(
          tester,
          () => const Checkbox3d(value: true),
        );
        final box = it.panels[1].decoration as BoxDecoration3d;
        expect(box.color, theme.colorScheme.disabledContent);
        expect(
          boxesOf<Text3d>(it.surface).single.style.color,
          theme.colorScheme.surface,
        );
      },
    );

    test('the resolver states the four states as a table', () {
      final table = <(bool, bool), (bool, bool)>{
        // (selected, enabled) -> (has a fill, has a mark)
        (false, true): (false, false),
        (true, true): (true, true),
        (false, false): (false, false),
        (true, false): (true, true),
      };
      for (final entry in table.entries) {
        final resolved = checkboxStyle.resolve(
          const {},
          selected: entry.key.$1,
          enabled: entry.key.$2,
        );
        expect(
          resolved.container.a > 0.0,
          entry.value.$1,
          reason: 'fill for ${entry.key}',
        );
        expect(
          resolved.hasMark,
          entry.value.$2,
          reason: 'mark for ${entry.key}',
        );
      }
    });
  });

  group('the checkbox geometry', () {
    testWidgets('is 18dp of ink centred in a 40dp wash', (tester) async {
      final it = await pumpComponent(
        tester,
        () => Checkbox3d(value: true, onChanged: (_) {}),
      );
      final wash = it.panels[0];
      final box = it.panels[1];
      expect(wash.size.width, closeTo(dp(40), 1e-9));
      expect(wash.size.height, closeTo(dp(40), 1e-9));
      expect(
        (wash.decoration as BoxDecoration3d).color.a,
        0.0,
        reason: 'the wash surface shows nothing but its own state layer',
      );
      expect(box.size.width, closeTo(dp(18), 1e-9));
      expect(box.size.height, closeTo(dp(18), 1e-9));
      final inkAt = offsetInSurface(box) + box.size.center;
      final washAt = offsetInSurface(wash) + wash.size.center;
      expect(inkAt.x, closeTo(washAt.x, 1e-9), reason: 'centred in the wash');
      expect(inkAt.y, closeTo(washAt.y, 1e-9), reason: 'centred in the wash');
    });

    testWidgets('and the mark stands clear of the box it is drawn on', (
      tester,
    ) async {
      // The rule this catalogue keeps rediscovering: a surface resting
      // exactly on another surface's front face is coplanar with it and
      // z-fights. The step comes from `Thickness3d.stepOver`, and the stack
      // is where it is applied.
      final it = await pumpComponent(
        tester,
        () => Checkbox3d(value: true, onChanged: (_) {}),
      );
      final steps = oneOf<Stack3d>(
        it.surface,
      ).children.map((child) => child.sceneOffset.z).toList();
      expect(steps.length, 3, reason: 'the wash, the box, and the mark');
      expect(steps[0], 0.0);
      expect(steps[1], closeTo(-dp(checkboxStyle.depthStep), 1e-9));
      expect(steps[2], closeTo(-2 * dp(checkboxStyle.depthStep), 1e-9));
      expect(
        theme.thickness.separates(
          checkboxStyle.thickness,
          checkboxStyle.thickness,
          step: checkboxStyle.depthStep,
        ),
        isTrue,
      );
    });
  });

  group('the radio token table and geometry', () {
    testWidgets('an unchosen option is a ring and nothing inside it', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => Radio3d<int>(value: 1, groupValue: 2, onChanged: (_) {}),
      );
      expect(it.panels.length, 2, reason: 'the wash and the ring');
      final ring = it.panels[1];
      final decoration = ring.decoration as BoxDecoration3d;
      expect(decoration.color.a, 0.0);
      expect(decoration.border.color, theme.colorScheme.onSurfaceVariant);
      expect(decoration.borderRadius, theme.shape.full);
      expect(ring.size.width, closeTo(dp(radioStyle.outerSize), 1e-9));
    });

    testWidgets('the chosen one is a primary ring with a dot in it', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => Radio3d<int>(value: 1, groupValue: 1, onChanged: (_) {}),
      );
      expect(it.panels.length, 3, reason: 'the wash, the ring and the dot');
      expect(
        (it.panels[1].decoration as BoxDecoration3d).border.color,
        theme.colorScheme.primary,
      );
      final dot = it.panels[2];
      expect(
        (dot.decoration as BoxDecoration3d).color,
        theme.colorScheme.primary,
      );
      expect(dot.size.width, closeTo(dp(radioStyle.innerSize), 1e-9));
      expect(
        (dot.decoration as BoxDecoration3d).borderRadius,
        theme.shape.full,
        reason: 'a stadium on a square box is a circle, and needed nothing new',
      );
    });

    testWidgets('a disabled group dims the ring and the dot together', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => const Radio3d<int>(value: 1, groupValue: 1),
      );
      expect(
        (it.panels[1].decoration as BoxDecoration3d).border.color,
        theme.colorScheme.disabledContent,
      );
      expect(
        (it.panels[2].decoration as BoxDecoration3d).color,
        theme.colorScheme.disabledContent,
      );
    });

    testWidgets('pressing an unchosen option reports its value', (
      tester,
    ) async {
      final reported = <int?>[];
      final it = await pumpComponent(
        tester,
        () => Radio3d<int>(value: 7, groupValue: 2, onChanged: reported.add),
      );
      it.pointer.down(rayAt(it.surface, const Offset3d(2, 1.5, 0)));
      it.pointer.up();
      expect(reported, <int?>[7]);
    });

    testWidgets('pressing the chosen one does nothing unless it toggles', (
      tester,
    ) async {
      final reported = <int?>[];
      final fixed = await pumpComponent(
        tester,
        () => Radio3d<int>(value: 7, groupValue: 7, onChanged: reported.add),
      );
      fixed.pointer.down(rayAt(fixed.surface, const Offset3d(2, 1.5, 0)));
      fixed.pointer.up();
      expect(
        reported,
        isEmpty,
        reason: 'a radio group has no way back to none',
      );

      final toggleable = await pumpComponent(
        tester,
        () => Radio3d<int>(
          value: 7,
          groupValue: 7,
          toggleable: true,
          onChanged: reported.add,
        ),
      );
      toggleable.pointer.down(
        rayAt(toggleable.surface, const Offset3d(2, 1.5, 0)),
      );
      toggleable.pointer.up();
      expect(reported, <int?>[null], reason: "Flutter's own contract");
    });
  });

  group('the switch', () {
    testWidgets('is a 52 by 32 track with a 24dp thumb on it', (tester) async {
      final it = await pumpComponent(
        tester,
        () => Switch3d(value: false, onChanged: (_) {}),
      );
      final track = it.panels[0];
      final thumb = it.panels[1];
      expect(track.size.width, closeTo(dp(52), 1e-9));
      expect(track.size.height, closeTo(dp(32), 1e-9));
      expect(track.size.depth, closeTo(dp(theme.thickness.thin), 1e-9));
      expect(thumb.size.width, closeTo(dp(24), 1e-9));
      expect(
        thumb.size.depth,
        closeTo(dp(theme.thickness.standard), 1e-9),
        reason:
            'the thumb is its own slab, not a decal on the track — which is '
            'only possible because it is a sibling of the track rather than '
            "a child of it, where the track's tight depth would clamp it",
      );
    });

    testWidgets('and the thumb stands proud of the track it slides on', (
      tester,
    ) async {
      final it = await pumpComponent(
        tester,
        () => Switch3d(value: false, onChanged: (_) {}),
      );
      final steps = oneOf<Stack3d>(
        it.surface,
      ).children.map((child) => child.sceneOffset.z).toList();
      expect(steps, hasLength(2));
      expect(steps[1], closeTo(-dp(switchStyle.depthStep), 1e-9));
      expect(
        theme.thickness.separates(
          switchStyle.trackThickness,
          switchStyle.thumbThickness,
          step: switchStyle.depthStep,
        ),
        isTrue,
        reason:
            'a thumb resting on the track is coplanar with it, and one '
            "lifted by exactly its own depth puts its back face there "
            'instead',
      );
    });

    testWidgets('slides its thumb on the node tier, half the travel each way', (
      tester,
    ) async {
      final off = await pumpComponent(
        tester,
        () => Switch3d(value: false, onChanged: (_) {}),
      );
      final shiftOff = oneComponentShift(off.surface).shift;
      expect(shiftOff.x, closeTo(-dp(switchStyle.travel) / 2, 1e-9));

      final on = await pumpComponent(
        tester,
        () => Switch3d(value: true, onChanged: (_) {}),
      );
      final shiftOn = oneComponentShift(on.surface).shift;
      expect(shiftOn.x, closeTo(dp(switchStyle.travel) / 2, 1e-9));
      expect(
        switchStyle.travel,
        closeTo(20.0, 1e-9),
        reason: '52 less a 24dp thumb and 4dp of margin at each end',
      );
    });

    testWidgets('and layout never hears about it', (tester) async {
      // The claim the node tier exists for. A toggle rebuilds the widget —
      // its tokens really do change — and writes one matrix; no box under it
      // is laid out again.
      var value = false;
      late void Function(void Function()) rebuild;
      final it = await pumpComponent(tester, () {
        return _Toggling(
          builder: (context, setState) {
            rebuild = setState;
            return Switch3d(
              value: value,
              onChanged: (next) => setState(() => value = next),
            );
          },
        );
      });
      final track = it.panels[0];
      final laidOut = layoutCountOf(it.surface);
      expect(oneComponentShift(it.surface).shift.x, lessThan(0.0));

      it.pointer.down(rayAt(it.surface, const Offset3d(2, 1.5, 0)));
      it.pointer.up();
      await tester.pump();

      expect(value, isTrue);
      expect(oneComponentShift(it.surface).shift.x, greaterThan(0.0));
      expect(it.surface.needsFlush, isFalse, reason: 'nothing was laid out');
      expect(layoutCountOf(it.surface), laidOut);
      expect(identical(it.panels[0], track), isTrue, reason: 'the same boxes');
      rebuild(() {});
      await tester.pump();
      expect(it.surface.needsFlush, isFalse);
    });

    testWidgets('a disabled switch keeps its position and loses its colour', (
      tester,
    ) async {
      final it = await pumpComponent(tester, () => const Switch3d(value: true));
      expect(
        (it.panels[0].decoration as BoxDecoration3d).color,
        theme.colorScheme.disabledContainer,
      );
      expect(
        (it.panels[1].decoration as BoxDecoration3d).color,
        theme.colorScheme.surface,
      );
      expect(
        oneComponentShift(it.surface).shift.x,
        greaterThan(0.0),
        reason: 'a disabled switch still says which way it is set',
      );
    });

    testWidgets('an off switch has an outline and an on one does not', (
      tester,
    ) async {
      final off = await pumpComponent(
        tester,
        () => Switch3d(value: false, onChanged: (_) {}),
      );
      expect(
        (off.panels[0].decoration as BoxDecoration3d).border.color,
        theme.colorScheme.outline,
      );
      final on = await pumpComponent(
        tester,
        () => Switch3d(value: true, onChanged: (_) {}),
      );
      expect(
        (on.panels[0].decoration as BoxDecoration3d).border.isNone,
        isTrue,
        reason: 'a filled track is the signal; an edge round it competes',
      );
    });
  });

  group('the 48dp target, at its most extreme', () {
    testWidgets('a checkbox answers a press 4dp past its own corner', (
      tester,
    ) async {
      // The reach at its thinnest. A checkbox is 40dp against Material's
      // 48dp minimum, so there is four logical pixels of margin on each
      // side — and at a corner that margin is all a press has.
      var taps = 0;
      final it = await pumpComponent(
        tester,
        () => Checkbox3d(value: false, onChanged: (_) => taps++),
      );
      expect(it.target.size.width, closeTo(dp(40), 1e-9));
      expect(it.target.effectiveMinimumSize.width, closeTo(dp(48), 1e-9));

      it.pointer.down(rayAt(it.surface, const Offset3d(2, 1.5, 0)));
      it.pointer.up();
      expect(taps, 1, reason: 'the middle');

      // The corner of the 48dp square: 24dp out on both axes from the centre.
      it.pointer.down(rayAt(it.surface, const Offset3d(2.235, 1.735, 0)));
      it.pointer.up();
      expect(taps, 2, reason: 'inside the corner of the reach');

      it.pointer.down(rayAt(it.surface, const Offset3d(2.245, 1.745, 0)));
      it.pointer.up();
      expect(taps, 2, reason: 'past it, and it stops');
    });

    testWidgets('and the reach grows no box', (tester) async {
      final it = await pumpComponent(
        tester,
        () => Checkbox3d(value: false, onChanged: (_) {}),
      );
      expect(it.target.size.width, closeTo(dp(40), 1e-9));
      expect(
        it.target.effectiveMinimumSize.width,
        greaterThan(it.target.size.width),
      );
      // Exactly one box in the whole control reaches past itself: the ink
      // well's own target sits inside at `Size3d.zero`, which is the
      // arrangement every component here uses.
      final reaching = boxesOf<TapTarget3d>(
        it.surface,
      ).where((t) => t.effectiveMinimumSize.width > t.size.width).toList();
      expect(reaching.length, 1);
      expect(identical(reaching.single, it.target), isTrue);
    });

    testWidgets('a switch is 32dp tall and reaches 8dp above itself', (
      tester,
    ) async {
      var taps = 0;
      final it = await pumpComponent(
        tester,
        () => Switch3d(value: false, onChanged: (_) => taps++),
      );
      expect(it.target.size.height, closeTo(dp(32), 1e-9));

      it.pointer.down(rayAt(it.surface, const Offset3d(2, 1.28, 0)));
      it.pointer.up();
      expect(taps, 1, reason: '6dp above the track, inside the reach');

      it.pointer.down(rayAt(it.surface, const Offset3d(2, 1.20, 0)));
      it.pointer.up();
      expect(taps, 1, reason: '14dp above: past it');
    });
  });

  group('what each one announces', () {
    testWidgets('a checkbox is checked or not, and states its own name', (
      tester,
    ) async {
      final on = await pumpComponent(
        tester,
        () => Checkbox3d(
          value: true,
          onChanged: (_) {},
          semanticLabel: 'Subscribe',
        ),
      );
      expect(on.semantics.properties.checked, isTrue);
      expect(on.semantics.properties.label, 'Subscribe');
      expect(on.semantics.properties.enabled, isTrue);
      expect(on.semantics.properties.onTap, isNotNull);

      final off = await pumpComponent(
        tester,
        () => const Checkbox3d(value: false),
      );
      expect(off.semantics.properties.checked, isFalse);
      expect(off.semantics.properties.enabled, isFalse);
      expect(off.semantics.properties.onTap, isNull);
    });

    testWidgets('a radio says it is one of a set', (tester) async {
      final it = await pumpComponent(
        tester,
        () => Radio3d<int>(
          value: 1,
          groupValue: 1,
          onChanged: (_) {},
          semanticLabel: 'Standard delivery',
        ),
      );
      expect(it.semantics.properties.checked, isTrue);
      expect(it.semantics.properties.inMutuallyExclusiveGroup, isTrue);
      expect(it.semantics.properties.label, 'Standard delivery');
    });

    testWidgets('a switch is toggled rather than checked', (tester) async {
      // Flutter's own distinction, and worth keeping: a reader says "on" and
      // "off" for a switch and "ticked" for a checkbox.
      final it = await pumpComponent(
        tester,
        () => Switch3d(value: true, onChanged: (_) {}, semanticLabel: 'Wi-Fi'),
      );
      expect(it.semantics.properties.toggled, isTrue);
      expect(it.semantics.properties.checked, isNull);
      expect(it.semantics.properties.label, 'Wi-Fi');
    });

    testWidgets('and nothing gathers a label from the row it sits in', (
      tester,
    ) async {
      // The phase-3 rule, restated where it bites hardest: a selection
      // control has no text of its own at all, so a caller who says nothing
      // publishes a checkbox with no name.
      final it = await pumpComponent(
        tester,
        () => SceneRow3d(
          mainAxisSize: MainAxisSize3d.min,
          children: <Widget>[
            Checkbox3d(value: false, onChanged: (_) {}),
            const SceneText3d('Subscribe'),
          ],
        ),
      );
      expect(it.semantics.properties.label, isNull);
    });
  });

  group('what a state costs', () {
    for (final entry in <String, Widget Function()>{
      'a checkbox': () => Checkbox3d(value: false, onChanged: (_) {}),
      'a radio': () => Radio3d<int>(value: 1, groupValue: 2, onChanged: (_) {}),
      'a switch': () => Switch3d(value: false, onChanged: (_) {}),
    }.entries) {
      testWidgets(
        '${entry.key} hovered rebuilds nothing and lays nothing out',
        (tester) async {
          final it = await pumpComponent(tester, entry.value);
          final built = it.builds[0];

          it.pointer.hover(rayAt(it.surface, const Offset3d(2, 1.5, 0)));

          expect(it.panel.stateLayer.opacity, theme.stateLayer.hover);
          expect(it.builds[0], built, reason: 'nothing rebuilt');
          expect(it.surface.needsFlush, isFalse, reason: 'nothing laid out');
        },
      );
    }

    testWidgets('and the wash lands on the control, not on what holds it', (
      tester,
    ) async {
      // An `InkWell3d` finds the *enclosing* `Material3d`. A checkbox with
      // no surface of its own would therefore light up whatever card or row
      // it was dropped into — the trap `docs/traps.md` records for a chip's
      // delete icon, in a control that is meant to live inside other
      // components.
      final it = await pumpComponent(
        tester,
        () => Card3d(child: Checkbox3d(value: false, onChanged: (_) {})),
      );
      final panels = it.panels;
      expect(panels.length, 3, reason: 'the card, the wash and the box');
      it.pointer.hover(rayAt(it.surface, const Offset3d(2, 1.5, 0)));
      expect(panels[0].stateLayer, StateLayer3d.none, reason: 'the card');
      expect(
        panels[1].stateLayer.opacity,
        theme.stateLayer.hover,
        reason: "the checkbox's own 40dp surface",
      );
    });

    testWidgets('the selected wash is primary and the empty one is onSurface', (
      tester,
    ) async {
      final on = await pumpComponent(
        tester,
        () => Checkbox3d(value: true, onChanged: (_) {}),
      );
      on.pointer.hover(rayAt(on.surface, const Offset3d(2, 1.5, 0)));
      expect(on.panel.stateLayer.color, theme.colorScheme.primary);

      final off = await pumpComponent(
        tester,
        () => Checkbox3d(value: false, onChanged: (_) {}),
      );
      off.pointer.hover(rayAt(off.surface, const Offset3d(2, 1.5, 0)));
      expect(off.panel.stateLayer.color, theme.colorScheme.onSurface);
    });
  });

  group('a restyled control', () {
    testWidgets('takes the tokens it is handed', (tester) async {
      final it = await pumpComponent(
        tester,
        () => Checkbox3d(
          value: false,
          onChanged: (_) {},
          style: checkboxStyle.copyWith(size: 24.0, outlineWidth: 4.0),
        ),
      );
      expect(it.panels[1].size.width, closeTo(dp(24), 1e-9));
      expect((it.panels[1].decoration as BoxDecoration3d).border.width, 4.0);
    });
  });
}

/// How many times every box in [surface] has been laid out, added up.
///
/// A blunt instrument on purpose: the claim is that a toggle lays out
/// *nothing*, so any box moving is a failure and which one hardly matters.
int layoutCountOf(Layout3dSurface surface) {
  var total = 0;
  void walk(Layout3d box) {
    if (box is TestBox) total += box.layoutCount;
    box.visitChildren(walk);
  }

  walk(surface.child!);
  return total;
}

/// A minimal stateful host, so a test can toggle a control the way an
/// application does — through `setState` — rather than by re-pumping.
class _Toggling extends StatefulWidget {
  const _Toggling({required this.builder});

  final Widget Function(BuildContext, void Function(void Function())) builder;

  @override
  State<_Toggling> createState() => _TogglingState();
}

class _TogglingState extends State<_Toggling> {
  @override
  Widget build(BuildContext context) => widget.builder(context, setState);
}
