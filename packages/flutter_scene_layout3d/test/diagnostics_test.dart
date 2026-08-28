// The debugging story: what a box says about itself, what it says when its
// content does not fit, what it draws when you ask to see it, and what it
// tells the platform's accessibility about itself.

import 'package:flutter/foundation.dart'
    show DiagnosticLevel, FlutterError, FlutterErrorDetails;
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart'
    show
        Builder,
        BuildContext,
        EdgeInsets,
        InheritedWidget,
        Padding,
        State,
        StatefulWidget,
        TextDirection,
        Widget;
import 'package:flutter_scene/scene.dart' show Node, SemanticsComponent;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A wireframe that draws nothing and remembers everything, standing in for
/// the real one: building line geometry needs a GPU context, and a headless
/// test has none.
class RecordingWireframe implements Layout3dWireframe {
  final Map<Node, Layout3dWireframeRequest> shown =
      <Node, Layout3dWireframeRequest>{};
  final List<Node> hidden = <Node>[];
  int disposeCount = 0;

  @override
  void show(Layout3dWireframeRequest request) {
    shown[request.node] = request;
  }

  @override
  void hide(Node node) {
    shown.remove(node);
    hidden.add(node);
  }

  @override
  void dispose() => disposeCount += 1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('toStringDeep', () {
    test('describes a small tree the way a render tree dump does', () {
      final surface = Layout3dSurface(
        constraints: Constraints3d.tight(const Size3d(4, 3, 1)),
        child: Column3d(
          mainAxisAlignment: MainAxisAlignment3d.center,
          children: <Layout3d>[
            Padding3d(
              padding: const EdgeInsets3d.all(0.5),
              child: SizedBox3d(width: 1, height: 1, depth: 1),
            ),
          ],
        ),
      );
      addTearDown(surface.dispose);
      surface.flush();

      expect(
        surface.child!.toStringDeep(),
        equalsIgnoringHashCodes(
          'Column3d#00000\n'
          ' │ constraints: Constraints3d(w: 4.0..4.0, h: 3.0..3.0, d: 1.0..1.0)\n'
          ' │ size: Size3d(4.000, 3.000, 1.000)\n'
          ' │ direction: vertical\n'
          ' │ mainAxisAlignment: center\n'
          ' │ mainAxisSize: max\n'
          ' │ crossAxisAlignment: center\n'
          ' │\n'
          ' └─child: Padding3d#00000\n'
          '   │ constraints: Constraints3d(w: 0.0..4.0, h: 0.0..Infinity, d:\n'
          '   │   0.0..1.0)\n'
          '   │ size: Size3d(2.000, 2.000, 1.000)\n'
          '   │ offset: Offset3d(1.000, 0.500, 0.000)\n'
          '   │ padding: EdgeInsets3d(0.5, 0.5, 0.5, 0.5, 0.5, 0.5)\n'
          '   │\n'
          '   └─child: SizedBox3d#00000\n'
          '       constraints: Constraints3d(w: 0.0..3.0, h: 0.0..Infinity, d:\n'
          '         0.0..0.0)\n'
          '       size: Size3d(1.000, 1.000, 0.000)\n'
          '       offset: Offset3d(0.500, 0.500, 0.500)\n'
          '       additionalConstraints: Constraints3d(w: 1.0..1.0, h: 1.0..1.0, d:\n'
          '         1.0..1.0)\n',
        ),
      );
    });

    test('says so when a box has never been laid out', () {
      final box = SizedBox3d(width: 1, height: 1);
      expect(box.toStringShallow(), contains('size: MISSING'));
      expect(box.toStringShallow(), contains('NEEDS-LAYOUT'));
      expect(box.toStringShallow(), contains('DETACHED'));
    });

    test('names the relayout boundary at the fine level', () {
      final inner = TestBox(const Size3d(1, 1, 0));
      final surface = laidOut(
        Padding3d(padding: const EdgeInsets3d.all(1), child: inner),
      );
      addTearDown(surface.dispose);
      // Nothing below the surface is tightly constrained here, so dirt from
      // either box travels all the way up: the surface is the boundary for
      // both, one and two steps away. That number is the answer to "why did
      // marking this box dirty lay the whole plane out again".
      expect(
        surface.toStringShallow(minLevel: DiagnosticLevel.fine),
        contains('relayoutBoundary: "this"'),
      );
      expect(
        surface.child!.toStringShallow(minLevel: DiagnosticLevel.fine),
        contains('relayoutBoundary: "up1"'),
      );
      expect(
        inner.toStringShallow(minLevel: DiagnosticLevel.fine),
        contains('relayoutBoundary: "up2"'),
      );
    });

    test('the ancestry of a box reads from the box up', () {
      final inner = TestBox(const Size3d(1, 1, 0));
      final surface = laidOut(
        Center3d(
          child: Padding3d(padding: EdgeInsets3d.all(1), child: inner),
        ),
      );
      addTearDown(surface.dispose);
      final chain = debugDescribeLayout3dAncestry(inner);
      expect(chain, contains('TestBox'));
      expect(chain, contains('Padding3d'));
      expect(chain, contains('Center3d'));
      expect(chain, contains('Layout3dSurface'));
    });

    test('debugDescribeLayout3dTree is what the dump prints', () {
      final surface = laidOut(TestBox(const Size3d(1, 1, 1)));
      addTearDown(surface.dispose);
      expect(debugDescribeLayout3dTree(surface), surface.toStringDeep());
    });
  });

  group('the interposed render object', () {
    testWidgets('a Padding between two 3D widgets is an error', (tester) async {
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 4, 4),
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: SceneSizedBox3d.cube(1),
          ),
        ),
      );
      FlutterError.onError = previous;

      expect(errors, isNotEmpty);
      final message = errors.first.exception.toString();
      expect(message, contains('was placed between two 3D layout widgets'));
      // The message has to name the widget the developer wrote, not only the
      // render object nobody typed, and it has to say what was lost.
      expect(message, contains('The Padding widget'));
      expect(message, contains('SizedBox3d'));
      expect(message, contains('ScenePadding3d'));
    });

    testWidgets('a Builder, a StatefulWidget and an InheritedWidget are not', (
      tester,
    ) async {
      final controller = Layout3dController();
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 4, 4),
          controller: controller,
          child: Builder(
            builder: (context) => const _Rebuilds(
              child: _Ambient(value: 1, child: SceneSizedBox3d.cube(1)),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(controller.surface!.child, isA<SizedBox3d>());
    });

    testWidgets('an interposed render object with nothing 3D below is fine', (
      tester,
    ) async {
      // The check is about lost layouts, not about render objects: a Flutter
      // widget beside the layout tree, holding no `Scene*3d` widget of its
      // own, is a legitimate thing to build.
      await tester.pumpWidget(
        SceneLayout3d(
          parent: Node(),
          size: const Size3d(4, 4, 4),
          child: const Padding(padding: EdgeInsets.all(8)),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('overflow', () {
    late List<Layout3dOverflow> reports;

    setUp(() {
      reports = <Layout3dOverflow>[];
      debugLayout3dOverflowReporter = reports.add;
    });

    tearDown(() {
      debugLayout3dOverflowReporter = defaultLayout3dOverflowReporter;
    });

    test('a row wider than its room reports once, with the amount', () {
      final row = Row3d(
        children: <Layout3d>[
          TestBox(const Size3d(3, 1, 0)),
          TestBox(const Size3d(3, 1, 0)),
        ],
      );
      final surface = laidOut(
        row,
        constraints: Constraints3d.tight(const Size3d(4, 2, 0)),
      );
      addTearDown(surface.dispose);

      expect(reports, hasLength(1));
      expect(reports.single.box, same(row));
      expect(reports.single.overflow.width, closeTo(2.0, 1e-9));
      expect(reports.single.axes, <Axis3d>[Axis3d.horizontal]);
      expect(reports.single.describe(), 'the right by 2.000');
      expect(row.debugOverflow.width, closeTo(2.0, 1e-9));

      // The same overflow again is not news: a list being flung past an
      // overflowing row would otherwise report on every frame.
      surface.markSubtreeNeedsLayout();
      surface.flush();
      expect(reports, hasLength(1));
    });

    test('the depth axis reports like the others, and matters more', () {
      // The one an eye does not catch. A stack of cards a third too deep for
      // the panel holding them is not a clipped edge, it is geometry standing
      // out of the front of the panel, and nothing about that reads as a
      // layout mistake until something says the word "overflow".
      final line = Depth3d(
        children: <Layout3d>[
          TestBox(const Size3d(1, 1, 2)),
          TestBox(const Size3d(1, 1, 2)),
        ],
      );
      final surface = laidOut(
        line,
        constraints: Constraints3d.tight(const Size3d(2, 2, 1)),
      );
      addTearDown(surface.dispose);

      expect(reports, hasLength(1));
      final overflow = reports.single.overflow;
      expect(overflow.width, 0.0);
      expect(overflow.height, 0.0);
      expect(overflow.depth, closeTo(3.0, 1e-9));
      expect(reports.single.describe(), 'the back by 3.000');
    });

    test('a row that fits reports nothing, and clears a previous report', () {
      final child = TestBox(const Size3d(6, 1, 0));
      final row = Row3d(children: <Layout3d>[child]);
      final surface = laidOut(
        row,
        constraints: Constraints3d.tight(const Size3d(4, 2, 0)),
      );
      addTearDown(surface.dispose);
      expect(reports, hasLength(1));

      child.preferred = const Size3d(1, 1, 0);
      surface.flush();
      expect(row.debugOverflow, Size3d.zero);
      expect(reports, hasLength(1));

      // Cleared, so the next one is news again.
      child.preferred = const Size3d(6, 1, 0);
      surface.flush();
      expect(reports, hasLength(2));
    });

    test('an unconstrained box reports the child it could not hold', () {
      final box = UnconstrainedBox3d(child: TestBox(const Size3d(6, 1, 0)));
      final surface = laidOut(
        box,
        constraints: Constraints3d.tight(const Size3d(2, 2, 0)),
      );
      addTearDown(surface.dispose);

      expect(reports, hasLength(1));
      expect(reports.single.box, same(box));
      expect(reports.single.overflow.width, closeTo(4.0, 1e-9));
      expect(reports.single.hint, contains('without constraints'));
    });

    test('the default reporter is a Flutter error naming the box', () {
      debugLayout3dOverflowReporter = defaultLayout3dOverflowReporter;
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      final surface = laidOut(
        Row3d(children: <Layout3d>[TestBox(const Size3d(9, 1, 0))]),
        constraints: Constraints3d.tight(const Size3d(1, 1, 0)),
      );
      FlutterError.onError = previous;
      addTearDown(surface.dispose);

      expect(errors, hasLength(1));
      final message = errors.single.exception.toString();
      expect(message, contains('Row3d overflowed the right by 8.000'));
      expect(message, contains('The overflowing box was'));
    });
  });

  group('the debug wireframe', () {
    late RecordingWireframe wireframe;

    setUp(() {
      wireframe = RecordingWireframe();
      debugLayout3dWireframeFactory = () => wireframe;
    });

    tearDown(() {
      debugPaintLayout3dSize = false;
      debugPaintLayout3dBaselines = false;
      debugLayout3dWireframeFactory = defaultLayout3dWireframeFactory;
    });

    test('draws every laid-out box at its own extent, and stops on demand', () {
      final inner = TestBox(const Size3d(1, 2, 0));
      final surface = laidOut(
        Padding3d(padding: const EdgeInsets3d.all(0.5), child: inner),
      );
      addTearDown(surface.dispose);
      expect(wireframe.shown, isEmpty);

      debugPaintLayout3dSize = true;
      surface.flush();
      expect(wireframe.shown, hasLength(3));
      expect(wireframe.shown[inner.node]!.size, const Size3d(1, 2, 0));
      expect(wireframe.shown[surface.node]!.size, const Size3d(2, 3, 1));
      expect(wireframe.shown[inner.node]!.color, debugPaintLayout3dSizeColor);
      // Nothing extra until the second flag says so.
      expect(wireframe.shown[inner.node]!.lines, isEmpty);

      debugPaintLayout3dSize = false;
      surface.flush();
      expect(wireframe.disposeCount, 1);
      expect(surface.owner!.debugHasWireframe, isFalse);
    });

    test('draws the offset a parent placed a box at', () {
      final inner = TestBox(const Size3d(1, 1, 0));
      final surface = laidOut(
        Padding3d(padding: const EdgeInsets3d.all(0.5), child: inner),
        constraints: Constraints3d.tight(const Size3d(4, 4, 0)),
      );
      addTearDown(surface.dispose);

      debugPaintLayout3dSize = true;
      debugPaintLayout3dBaselines = true;
      surface.flush();

      final lines = wireframe.shown[inner.node]!.lines;
      final offsets = lines
          .where((line) => line.color == debugPaintLayout3dOffsetColor)
          .toList();
      expect(offsets, hasLength(1));
      // Drawn in the box's own frame, so it runs back to the parent's corner.
      expect(offsets.single.start, Offset3d.zero);
      expect(offsets.single.end, const Offset3d(-0.5, -0.5, -0.5));
    });

    test('draws a baseline that is otherwise invisible', () {
      final baseline = Baseline3d(
        baseline: 1.5,
        axis: Axis3d.vertical,
        child: TestBox(const Size3d(2, 1, 0)),
      );
      final surface = laidOut(baseline);
      addTearDown(surface.dispose);

      debugPaintLayout3dSize = true;
      debugPaintLayout3dBaselines = true;
      surface.flush();

      final lines = wireframe.shown[baseline.node]!.lines
          .where((line) => line.color == debugPaintLayout3dBaselineColor)
          .toList();
      expect(lines, isNotEmpty);
      expect(lines.every((line) => line.start.y == 1.5), isTrue);
    });

    test('a hidden box gives its lines back', () {
      final hidden = TestBox(const Size3d(1, 1, 0));
      final surface = laidOut(
        Visibility3d(visible: true, child: hidden),
        constraints: Constraints3d.tight(const Size3d(2, 2, 0)),
      );
      addTearDown(surface.dispose);

      debugPaintLayout3dSize = true;
      surface.flush();
      expect(wireframe.shown.containsKey(hidden.node), isTrue);

      (surface.child! as Visibility3d).visible = false;
      surface.flush();
      expect(wireframe.shown.containsKey(hidden.node), isFalse);
      expect(wireframe.hidden, contains(hidden.node));
    });

    test('the default factory draws nothing while the engine is not ready', () {
      debugLayout3dWireframeFactory = defaultLayout3dWireframeFactory;
      final surface = laidOut(TestBox(const Size3d(1, 1, 0)));
      addTearDown(surface.dispose);
      debugPaintLayout3dSize = true;
      expect(debugSyncLayout3dWireframes(surface), isFalse);
      expect(surface.owner!.debugHasWireframe, isFalse);
    });
  });

  group('Semantics3d', () {
    test('publishes a node sized from the box, not from the geometry', () {
      final semantics = Semantics3d(
        properties: const SemanticsProperties(
          label: 'Continue',
          button: true,
          textDirection: TextDirection.ltr,
        ),
        child: TestBox(const Size3d(2, 1, 0.25)),
      );
      final surface = laidOut(semantics);
      addTearDown(surface.dispose);

      expect(semantics.node.getComponent<SemanticsComponent>(), isNotNull);
      expect(semantics.properties.label, 'Continue');
      final bounds = semantics.component.boundsOverride!;
      expect(bounds.min.x, 0.0);
      expect(bounds.max.x, 2.0);
      expect(bounds.max.y, 1.0);
      expect(bounds.max.z, 0.25);
    });

    test('the whole control is focused, not the glyph inside it', () {
      // The reason the bounds come from layout rather than from the meshes:
      // what hangs under the node is a small label, and what the reader has
      // to be able to focus is the padded control around it.
      final semantics = Semantics3d(
        properties: const SemanticsProperties(label: 'Play'),
        child: Padding3d(
          padding: const EdgeInsets3d.all(1),
          child: TestBox(const Size3d(0.5, 0.5, 0)),
        ),
      );
      final surface = laidOut(semantics);
      addTearDown(surface.dispose);
      expect(semantics.component.boundsOverride!.max.x, 2.5);
      expect(semantics.component.boundsOverride!.max.y, 2.5);
    });

    test('a new label writes one field and lays nothing out again', () {
      final child = TestBox(const Size3d(1, 1, 0));
      final semantics = Semantics3d(
        properties: const SemanticsProperties(label: 'Play'),
        child: child,
      );
      final surface = laidOut(semantics);
      addTearDown(surface.dispose);
      final before = child.layoutCount;

      semantics.properties = const SemanticsProperties(label: 'Pause');
      expect(surface.needsFlush, isFalse);
      surface.flush();
      expect(child.layoutCount, before);
      expect(semantics.component.properties!.label, 'Pause');
    });

    test('disabling takes the box out of the semantics tree', () {
      final semantics = Semantics3d(
        properties: const SemanticsProperties(label: 'Play'),
        child: TestBox(const Size3d(1, 1, 0)),
      );
      final surface = laidOut(semantics);
      addTearDown(surface.dispose);

      semantics.enabled = false;
      expect(semantics.node.getComponent<SemanticsComponent>(), isNull);
      semantics.enabled = true;
      expect(semantics.node.getComponent<SemanticsComponent>(), isNotNull);
    });

    test('traversal order is layout order, through the scene graph', () {
      final first = Semantics3d(
        properties: const SemanticsProperties(label: 'first'),
        child: TestBox(const Size3d(1, 1, 0)),
      );
      final second = Semantics3d(
        properties: const SemanticsProperties(label: 'second'),
        child: TestBox(const Size3d(1, 1, 0)),
      );
      final column = Column3d(children: <Layout3d>[first, second]);
      final surface = laidOut(column);
      addTearDown(surface.dispose);

      // Nothing sorts them: the nodes are children of the column's node in
      // the order the column lays them out, and the scene graph is what the
      // reader walks.
      expect(column.node.children, <Node>[first.node, second.node]);
      expect(first.sortOrder, isNull);
    });

    test('a focusable box with no semantics is reported', () {
      final bare = Focus3d(child: TestBox(const Size3d(1, 1, 0)));
      final spoken = Semantics3d(
        properties: const SemanticsProperties(label: 'Save'),
        child: Focus3d(child: TestBox(const Size3d(1, 1, 0))),
      );
      final surface = laidOut(
        Column3d(children: <Layout3d>[bare, spoken]),
        constraints: Constraints3d.tight(const Size3d(4, 4, 0)),
      );
      addTearDown(surface.dispose);

      expect(debugFocusableBoxesWithoutSemantics(surface), <Focus3d>[bare]);
    });
  });
}

/// A `StatefulWidget` that creates no render object, so its child is the
/// layout host's child.
class _Rebuilds extends StatefulWidget {
  const _Rebuilds({required this.child});

  final Widget child;

  @override
  State<_Rebuilds> createState() => _RebuildsState();
}

class _RebuildsState extends State<_Rebuilds> {
  @override
  Widget build(BuildContext context) => widget.child;
}

/// An `InheritedWidget`, likewise transparent to the layout tree.
class _Ambient extends InheritedWidget {
  const _Ambient({required this.value, required super.child});

  final int value;

  @override
  bool updateShouldNotify(_Ambient old) => old.value != value;
}
