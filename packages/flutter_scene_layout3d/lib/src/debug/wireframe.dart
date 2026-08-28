import 'dart:typed_data' show Float32List;
import 'dart:ui' show Color;

import 'package:flutter_scene/scene.dart'
    show
        LineSegmentData,
        LineSegmentsGeometry,
        Mesh,
        Node,
        Scene,
        UnlitMaterial;
import 'package:vector_math/vector_math.dart' show Matrix4, Vector4;

import '../geometry/offset3d.dart';
import '../geometry/size3d.dart';
import '../layout3d.dart';

/// Whether every laid-out box hangs a wireframe of its own extent under its
/// scene node.
///
/// [debugPaintSize] with real lines, and the single most useful tool in this
/// file. A layout on a plane paints nothing of its own: a box that came out
/// the wrong size, a padding that went the wrong way, a child standing out
/// through the front of a panel are all invisible until something draws the
/// boxes, and a `Size3d` in a test failure does not say *where* the box is.
///
/// Set it, then flush the surface — [Layout3dSurface.flush] syncs the
/// overlay, so the next frame carries it. Clearing it and flushing again
/// takes every line back out of the scene.
///
/// Debug-only: the sync is inside an `assert`, so nothing here costs a
/// release build anything.
bool debugPaintLayout3dSize = false;

/// Whether the wireframe also draws each box's baselines and the offset its
/// parent placed it at.
///
/// Rides on [debugPaintLayout3dSize] rather than replacing it, because both
/// answers are about the same box. A baseline is otherwise entirely
/// invisible — [Baseline3d] and `CrossAxisAlignment3d.baseline` move content
/// by a number nothing draws — and the offset line, running from the
/// parent's origin corner to this box's, is what tells a misplaced child from
/// a mis-sized one.
bool debugPaintLayout3dBaselines = false;

/// One line of a debug overlay, in the box's own layout frame.
class Layout3dWireframeLine {
  /// Creates a line from [start] to [end], drawn in [color].
  const Layout3dWireframeLine(this.start, this.end, this.color);

  /// Where the line starts, relative to the box's origin corner.
  final Offset3d start;

  /// Where the line ends, relative to the box's origin corner.
  final Offset3d end;

  /// What colour to draw it in.
  final Color color;

  @override
  String toString() => 'Layout3dWireframeLine($start -> $end)';
}

/// Everything the overlay needs to draw one box.
class Layout3dWireframeRequest {
  /// Describes one box's overlay.
  const Layout3dWireframeRequest({
    required this.node,
    required this.size,
    required this.color,
    this.lines = const <Layout3dWireframeLine>[],
  });

  /// The box's scene node, which the lines hang under.
  ///
  /// The identity a wireframe keys its per-box state on, exactly as
  /// [Decoration3dPaintRequest.node] is: one child node per box, taken back
  /// out by [Layout3dWireframe.hide].
  final Node node;

  /// The box's extent, whose twelve edges are the wireframe proper.
  final Size3d size;

  /// What colour to draw the box's own edges in.
  final Color color;

  /// Extra lines to draw beside the edges: baselines, the offset from the
  /// parent's origin.
  final List<Layout3dWireframeLine> lines;
}

/// Draws the debug overlay for a tree of boxes.
///
/// The seam is here for the same reason [BoxDecoration3d.painterFactory] is:
/// building line geometry allocates a device buffer, so it cannot happen
/// before the engine is ready and must not happen at all in a headless test.
/// [LineSegments3dWireframe] is the real one; a test installs a recording
/// implementation through [debugLayout3dWireframeFactory] and asserts on what
/// the layout asked for rather than on pixels.
abstract class Layout3dWireframe {
  /// Draws (or redraws) the overlay for one box.
  ///
  /// Called after every layout of the box while the flags are set, so an
  /// implementation must treat a repeat call for the same node as an update.
  void show(Layout3dWireframeRequest request);

  /// Takes the overlay for [node] back out of the scene.
  void hide(Node node);

  /// Releases whatever this wireframe built.
  void dispose();
}

/// Builds the object that draws debug wireframes for one surface.
///
/// Replace it to draw the overlay some other way, or to record what would
/// have been drawn. Returning null means no overlay, which is what the
/// default does before [Scene.initializeStaticResources] has completed.
Layout3dWireframe? Function() debugLayout3dWireframeFactory =
    defaultLayout3dWireframeFactory;

/// The default [debugLayout3dWireframeFactory]: real line geometry once the
/// engine can build it, and nothing before that.
Layout3dWireframe? defaultLayout3dWireframeFactory() =>
    Scene.isReadyToRender ? LineSegments3dWireframe() : null;

/// The colour a box's own edges are drawn in, mirroring Flutter's
/// `debugPaintSizeColor`.
const Color debugPaintLayout3dSizeColor = Color(0xFF00FFFF);

/// The colour a baseline is drawn in.
const Color debugPaintLayout3dBaselineColor = Color(0xFF00FF00);

/// The colour the line from the parent's origin corner to this box's is
/// drawn in.
const Color debugPaintLayout3dOffsetColor = Color(0xFFFF00FF);

/// Syncs the debug overlay for the whole tree under [root].
///
/// Called by [Layout3dSurface.flush]; call it yourself for a tree you drive
/// by hand. Cheap when the flags have never been set — it does nothing at all
/// until the first time one of them is — and a walk of the tree afterwards,
/// which is the price of a debug flag that can be turned on at any moment.
///
/// Returns whether anything is currently drawn, so a caller can tell an
/// overlay that is off from one the engine could not build yet.
bool debugSyncLayout3dWireframes(Layout3d root) {
  final owner = root.owner;
  if (owner == null) return false;
  final wanted = debugPaintLayout3dSize;
  if (!wanted && !owner.debugHasWireframe) return false;
  final wireframe = wanted
      ? owner.debugAcquireWireframe(debugLayout3dWireframeFactory)
      : null;
  if (wanted && wireframe == null) return false;
  void visit(Layout3d box, {required bool visible}) {
    // Hidden means hidden all the way down: what a ListView3d has culled out
    // of its window, or an Offstage3d has taken out of the scene, has no
    // lines either. A box whose own node is visible inside a hidden subtree
    // is still not on screen.
    final showing = visible && box.node.visible;
    if (wireframe == null) {
      // Turning the flag off: every box gives its lines back with the
      // wireframe, so nothing is left holding a device buffer once the
      // overlay is not wanted.
      box.visitChildren((child) => visit(child, visible: showing));
      return;
    }
    if (showing && box.hasSize) {
      wireframe.show(
        Layout3dWireframeRequest(
          node: box.node,
          size: box.size,
          color: debugPaintLayout3dSizeColor,
          lines: debugPaintLayout3dBaselines
              ? _annotationsFor(box)
              : const <Layout3dWireframeLine>[],
        ),
      );
    } else {
      wireframe.hide(box.node);
    }
    box.visitChildren((child) => visit(child, visible: showing));
  }

  visit(root, visible: true);
  if (wireframe == null) {
    owner.debugReleaseWireframe();
    return false;
  }
  return true;
}

/// The baseline and offset lines for one box.
List<Layout3dWireframeLine> _annotationsFor(Layout3d box) {
  final lines = <Layout3dWireframeLine>[];
  final size = box.size;
  for (final axis in Axis3d.values) {
    final distance = box.getDistanceToBaseline(axis, onlyReal: true);
    if (distance == null) continue;
    // A baseline on one axis is a line drawn across the *other* two, at the
    // declared distance. Drawing both of them is what makes it read as a
    // plane through the box rather than as a stray segment.
    final at = Offset3d.zero.withAxis(axis, distance);
    for (final across in Axis3d.values) {
      if (across == axis) continue;
      lines.add(
        Layout3dWireframeLine(
          at,
          at + Offset3d.zero.withAxis(across, size.alongAxis(across)),
          debugPaintLayout3dBaselineColor,
        ),
      );
    }
  }
  final offset = box.offset;
  if (offset != Offset3d.zero) {
    // Drawn in this box's frame, so it runs backwards from the origin corner
    // to where the parent's corner is: the line a misplaced child is off by.
    lines.add(
      Layout3dWireframeLine(
        Offset3d.zero,
        -offset,
        debugPaintLayout3dOffsetColor,
      ),
    );
  }
  return lines;
}

/// The real overlay: thick line segments, one shared geometry, scaled per
/// box.
///
/// The economy is the decoration painter's, for the same reason. Every box's
/// edges are the *same twelve unit-cube edges* under a different scale, and
/// every extra line is the same unit segment under a different transform, so
/// a screen of boxes is two geometries and a matrix write per box. A box that
/// animates its size therefore rebuilds nothing; it writes sixteen floats.
class LineSegments3dWireframe implements Layout3dWireframe {
  /// Creates a wireframe. Needs the engine to be ready
  /// ([Scene.isReadyToRender]), since building line geometry allocates a
  /// device buffer.
  LineSegments3dWireframe({this.width = 0.004});

  /// The world-space width of a drawn line.
  final double width;

  LineSegmentsGeometry? _cube;
  LineSegmentsGeometry? _segment;
  final Map<Node, _WireframeEntry> _entries = <Node, _WireframeEntry>{};

  /// How many boxes this wireframe is currently drawing.
  int get boxCount => _entries.length;

  @override
  void show(Layout3dWireframeRequest request) {
    final entry = _entries.putIfAbsent(request.node, () {
      final holder = Node()..name = 'Layout3dWireframe';
      request.node.add(holder);
      return _WireframeEntry(holder);
    });
    final size = request.size;
    entry
        .edges(_cubeGeometry(), request.color)
        .localTransform = Matrix4.diagonal3Values(
      _nonZero(size.width),
      _nonZero(size.height),
      _nonZero(size.depth),
    );
    entry.setLines(_segmentGeometry(), request.lines, width);
  }

  @override
  void hide(Node node) {
    final entry = _entries.remove(node);
    if (entry == null) return;
    node.remove(entry.holder);
    entry.holder.removeAll();
  }

  @override
  void dispose() {
    for (final entry in _entries.values) {
      entry.holder.parent?.remove(entry.holder);
      entry.holder.removeAll();
    }
    _entries.clear();
    _cube = null;
    _segment = null;
  }

  // A zero extent would make the scale singular, and a box with no depth is
  // the common case rather than a mistake, so it is drawn as a flat frame.
  static double _nonZero(double extent) => extent == 0.0 ? 1e-6 : extent;

  LineSegmentsGeometry _cubeGeometry() =>
      _cube ??= LineSegmentsGeometry(_unitCubeEdges(), width: width);

  LineSegmentsGeometry _segmentGeometry() =>
      _segment ??= LineSegmentsGeometry(_unitSegment(), width: width);

  static LineSegmentData _unitSegment() => LineSegmentData(
    positions: Float32List.fromList(<double>[0, 0, 0, 1, 0, 0]),
  );

  static LineSegmentData _unitCubeEdges() {
    // The twelve edges of the unit cube with a corner at the origin, so
    // scaling by the box's extent lands them exactly on the box.
    const corners = <List<double>>[
      <double>[0, 0, 0],
      <double>[1, 0, 0],
      <double>[1, 1, 0],
      <double>[0, 1, 0],
      <double>[0, 0, 1],
      <double>[1, 0, 1],
      <double>[1, 1, 1],
      <double>[0, 1, 1],
    ];
    const edges = <List<int>>[
      <int>[0, 1], <int>[1, 2], <int>[2, 3], <int>[3, 0], //
      <int>[4, 5], <int>[5, 6], <int>[6, 7], <int>[7, 4], //
      <int>[0, 4], <int>[1, 5], <int>[2, 6], <int>[3, 7], //
    ];
    final positions = Float32List(edges.length * 6);
    var i = 0;
    for (final edge in edges) {
      for (final index in edge) {
        positions[i++] = corners[index][0];
        positions[i++] = corners[index][1];
        positions[i++] = corners[index][2];
      }
    }
    return LineSegmentData(positions: positions);
  }
}

/// One box's overlay: the node the lines hang under, and the meshes in it.
class _WireframeEntry {
  _WireframeEntry(this.holder);

  final Node holder;
  Node? _edges;
  final List<Node> _lines = <Node>[];

  Node edges(LineSegmentsGeometry geometry, Color color) {
    final existing = _edges;
    if (existing != null) return existing;
    final node = Node(mesh: Mesh(geometry, _materialFor(color)))
      ..name = 'Layout3dWireframe.edges';
    holder.add(node);
    return _edges = node;
  }

  void setLines(
    LineSegmentsGeometry geometry,
    List<Layout3dWireframeLine> lines,
    double width,
  ) {
    while (_lines.length > lines.length) {
      final node = _lines.removeLast();
      holder.remove(node);
    }
    for (var i = 0; i < lines.length; i += 1) {
      final line = lines[i];
      if (i == _lines.length) {
        final node = Node(mesh: Mesh(geometry, _materialFor(line.color)))
          ..name = 'Layout3dWireframe.line';
        holder.add(node);
        _lines.add(node);
      }
      // The unit segment runs along `x`, so the matrix that carries it onto
      // this line puts the line's own direction in the first column and
      // leaves the other two axes alone: the geometry has no extent there,
      // and the shader expands the ribbon itself.
      final delta = line.end - line.start;
      _lines[i].localTransform = Matrix4.columns(
        Vector4(delta.x, delta.y, delta.z, 0.0),
        Vector4(0.0, 1.0, 0.0, 0.0),
        Vector4(0.0, 0.0, 1.0, 0.0),
        Vector4(line.start.x, line.start.y, line.start.z, 1.0),
      );
    }
  }

  static UnlitMaterial _materialFor(Color color) =>
      UnlitMaterial()
        ..baseColorFactor = Vector4(color.r, color.g, color.b, color.a);
}
