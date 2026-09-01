// Layout3dSlot: tree-wide state a component library puts on the owner,
// typed, without Material vocabulary reaching this package.

import 'package:flutter/widgets.dart' show BuildContext, Widget;
import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Stands in for the theme a catalogue will put here.
class Palette {
  const Palette(this.padding);

  final double padding;

  @override
  bool operator ==(Object other) =>
      other is Palette && other.padding == padding;

  @override
  int get hashCode => padding.hashCode;
}

class Density {
  const Density(this.scale);
  final double scale;
}

const paletteSlot = Layout3dSlot<Palette>('palette');
const densitySlot = Layout3dSlot<Density>('density');
final otherPaletteSlot = Layout3dSlot<Palette>('palette');
const differentTypeSlot = Layout3dSlot<Density>('palette');

/// A box that sizes itself from a slot, the way a themed component will.
class PaddedBySlot extends Layout3d {
  int layoutCount = 0;
  double? sawPadding;

  @override
  void performLayout() {
    layoutCount++;
    sawPadding = slot(paletteSlot)?.padding;
    final padding = sawPadding ?? 0.0;
    size = constraints.constrain(Size3d(padding, padding, 0));
  }
}

void main() {
  group('the owner', () {
    test('round-trips a typed value and reports whether it changed', () {
      final owner = Layout3dOwner();
      expect(owner.slot(paletteSlot), isNull);

      expect(owner.setSlot(paletteSlot, const Palette(8)), isTrue);
      expect(owner.slot(paletteSlot), const Palette(8));
      // The static type is the slot's, with no cast at the call site.
      final Palette? palette = owner.slot(paletteSlot);
      expect(palette?.padding, 8);

      expect(owner.setSlot(paletteSlot, const Palette(8)), isFalse);
      expect(owner.setSlot(paletteSlot, const Palette(12)), isTrue);
    });

    test('a slot is its type and its name, const or not', () {
      // Dart canonicalizes const instances, so an identity-keyed slot would
      // behave one way declared `const` and another declared `final`. Value
      // equality is the rule a reader can state without knowing which.
      final owner = Layout3dOwner();
      owner.setSlot(paletteSlot, const Palette(8));
      expect(otherPaletteSlot, paletteSlot);
      expect(owner.slot(otherPaletteSlot), const Palette(8));
      // A different type with the same name is a different slot.
      expect(differentTypeSlot, isNot(paletteSlot));
      expect(owner.slot(differentTypeSlot), isNull);
      expect(owner.slotKeys, contains(paletteSlot));
    });

    test('null removes the value', () {
      final owner = Layout3dOwner();
      owner.setSlot(densitySlot, const Density(1));
      expect(owner.setSlot(densitySlot, null), isTrue);
      expect(owner.slot(densitySlot), isNull);
      expect(owner.setSlot(densitySlot, null), isFalse);
      expect(owner.slotKeys, isEmpty);
    });

    test('dispose drops the slots and does not dispose the values', () {
      // The owner collects tree-wide state, it does not own it. A value that
      // holds resources is disposed by whoever put it there.
      final owner = Layout3dOwner();
      owner.setSlot(paletteSlot, const Palette(8));
      owner.dispose();
      expect(owner.slot(paletteSlot), isNull);
      expect(owner.slotKeys, isEmpty);
    });
  });

  group('a box', () {
    test('reads the slot its surface holds, and null while detached', () {
      final box = PaddedBySlot();
      expect(box.slot(paletteSlot), isNull);

      final surface = Layout3dSurface(child: box)
        ..setSlot(paletteSlot, const Palette(3))
        ..flush();
      expect(box.sawPadding, 3);
      expect(surface.slotValue(paletteSlot), const Palette(3));
    });

    test('is laid out again when the slot changes', () {
      // The reason setSlot relayouts by default: a slot is read inside
      // performLayout and never arrives as a constraint, so nothing else
      // would tell a box that the number it sized itself from moved.
      final box = PaddedBySlot();
      final surface = laidOut(box);
      expect(box.sawPadding, isNull);
      final layouts = box.layoutCount;

      surface.setSlot(paletteSlot, const Palette(5));
      surface.flush();
      expect(box.layoutCount, layouts + 1);
      expect(box.size, const Size3d(5, 5, 0));
    });

    test('is not laid out again when the write says so', () {
      final box = PaddedBySlot();
      final surface = laidOut(box);
      final layouts = box.layoutCount;

      surface.setSlot(paletteSlot, const Palette(5), relayout: false);
      expect(surface.needsFlush, isFalse);
      expect(box.layoutCount, layouts);
    });

    test('writing the same value again relayouts nothing', () {
      final box = PaddedBySlot();
      final surface = laidOut(box)..setSlot(paletteSlot, const Palette(5));
      surface.flush();
      final layouts = box.layoutCount;

      surface.setSlot(paletteSlot, const Palette(5));
      expect(surface.needsFlush, isFalse);
      expect(box.layoutCount, layouts);
    });
  });

  group('SlotProvider3d', () {
    test('writes while attached and clears when it detaches', () {
      final box = PaddedBySlot();
      final provider = SlotProvider3d<Palette>(
        slot: paletteSlot,
        value: const Palette(4),
        child: box,
      );
      final surface = laidOut(provider);
      expect(box.sawPadding, 4);

      provider.value = const Palette(9);
      surface.flush();
      expect(box.sawPadding, 9);

      surface.child = null;
      expect(surface.slotValue(paletteSlot), isNull);
    });
  });

  group('the widget layer', () {
    testWidgets('SceneLayout3d.slots writes and clears', (tester) async {
      late PaddedBySlot box;
      final controller = Layout3dController();

      Widget frame(Map<Layout3dSlot<Object>, Object> slots) => SceneLayout3d(
        parent: Node(),
        constraints: Constraints3d.loose(const Size3d(10, 10, 10)),
        controller: controller,
        slots: slots,
        child: _SceneSlotReader((made) => box = made),
      );

      await tester.pumpWidget(frame({paletteSlot: const Palette(6)}));
      expect(box.sawPadding, 6);

      await tester.pumpWidget(frame({paletteSlot: const Palette(2)}));
      expect(box.sawPadding, 2);

      // A key that disappears is cleared, not left behind.
      await tester.pumpWidget(frame(const {}));
      expect(controller.surface!.slotValue(paletteSlot), isNull);
      expect(box.sawPadding, isNull);
    });

    testWidgets('SceneSlotProvider3d writes from inside the tree', (
      tester,
    ) async {
      late PaddedBySlot box;
      final controller = Layout3dController();

      Widget frame(double padding) => SceneLayout3d(
        parent: Node(),
        constraints: Constraints3d.loose(const Size3d(10, 10, 10)),
        controller: controller,
        child: SceneSlotProvider3d<Palette>(
          slot: paletteSlot,
          value: Palette(padding),
          child: _SceneSlotReader((made) => box = made),
        ),
      );

      await tester.pumpWidget(frame(7));
      expect(box.sawPadding, 7);

      await tester.pumpWidget(frame(1));
      expect(box.sawPadding, 1);
    });

    testWidgets('a provider taken out of the tree clears its slot', (
      tester,
    ) async {
      final controller = Layout3dController();

      Widget frame({required bool themed}) => SceneLayout3d(
        parent: Node(),
        constraints: Constraints3d.loose(const Size3d(10, 10, 10)),
        controller: controller,
        child: themed
            ? const SceneSlotProvider3d<Palette>(
                slot: paletteSlot,
                value: Palette(7),
                child: SceneSizedBox3d.cube(1),
              )
            : const SceneSizedBox3d.cube(1),
      );

      await tester.pumpWidget(frame(themed: true));
      expect(controller.surface!.slotValue(paletteSlot), const Palette(7));

      await tester.pumpWidget(frame(themed: false));
      expect(controller.surface!.slotValue(paletteSlot), isNull);
    });
  });
}

/// Hosts a [PaddedBySlot] in the widget tree.
class _SceneSlotReader extends Layout3dWidget {
  const _SceneSlotReader(this.sink);

  final void Function(PaddedBySlot) sink;

  @override
  Layout3d createLayout(BuildContext context) {
    final box = PaddedBySlot();
    sink(box);
    return box;
  }

  @override
  void updateLayout(BuildContext context, PaddedBySlot layout) {}
}
