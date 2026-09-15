import 'dart:ui' show Offset, Size;

import 'package:flutter/rendering.dart' show RenderBox, RenderPointerListener;
import 'package:flutter/widgets.dart'
    show Element, RenderObjectElement, WidgetsBinding;
import 'package:flutter_scene/scene.dart' show Camera;
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3;

import '../debug/screen_projection.dart';
import '../geometry/offset3d.dart';
import '../hit_test.dart';
import '../layout3d.dart';
import '../overlay/overlay.dart';
import '../semantics.dart';
import '../surface.dart';
import '../text/rich_text3d.dart';
import '../text/text3d.dart';
import '../widgets/framework.dart' show Layout3dRootRenderBox;
import '../widgets/input.dart';

/// A surface found in the widget tree, and the input host it is under.
class SceneSurface3d {
  SceneSurface3d(this.surface, this.host);

  /// The surface.
  final Layout3dSurface surface;

  /// The host a press on [surface] goes through, or null when the surface is
  /// not under a [SceneInput3d].
  final SceneHost3d? host;
}

/// A [SceneInput3d] found in the widget tree, with what it takes to turn a
/// point of the view into a point of the screen.
class SceneHost3d {
  SceneHost3d(this.host, this.box, this.viewSize);

  /// The host.
  final Input3dHost host;

  /// The box pointer events are delivered in, whose coordinates are the ones
  /// [Input3dHost.hitTestAt] takes.
  final RenderBox box;

  /// The size stated on the widget, when the view is a sub-rectangle of
  /// [box].
  final Size? viewSize;

  /// The camera rays are cast from.
  Camera? get camera => host.camera;

  /// The size of the view the camera projects into.
  Size get size => viewSize ?? box.size;

  /// [local], a point of the view, in global coordinates.
  Offset toGlobal(Offset local) => box.localToGlobal(local);

  /// [global] in the view's coordinates.
  Offset toLocal(Offset global) => box.globalToLocal(global);

  /// Whether [global] falls inside the view.
  bool contains(Offset global) =>
      box.hasSize && box.size.contains(box.globalToLocal(global));
}

/// Every surface mounted in the widget tree, in tree order, with each
/// overlay's detached entries straight after the surface that holds the
/// overlay.
///
/// Found through the render tree — every `SceneLayout3d` mounts a
/// [Layout3dRootRenderBox] — so nothing private to the widget is needed, and
/// a surface registered with a host by hand is added after the ones the tree
/// holds.
List<SceneSurface3d> sceneSurfaces3d() {
  final found = <Layout3dSurface, SceneSurface3d>{};
  final hosts = <SceneHost3d>[];

  void addSurface(Layout3dSurface surface, SceneHost3d? host) {
    if (found.containsKey(surface)) return;
    found[surface] = SceneSurface3d(surface, host);
    for (final overlay in _overlaysIn(surface)) {
      for (final entry in overlay.detachedSurfaces) {
        addSurface(entry, host);
      }
    }
  }

  void visit(Element element, SceneHost3d? host) {
    var current = host;
    final widget = element.widget;
    if (widget is Input3dScope) {
      final box = element
          .findAncestorRenderObjectOfType<RenderPointerListener>();
      final input = element.findAncestorWidgetOfExactType<SceneInput3d>();
      if (box != null) {
        current = SceneHost3d(widget.host, box, input?.viewSize);
        hosts.add(current);
      }
    }
    if (element is RenderObjectElement) {
      final renderObject = element.renderObject;
      if (renderObject is Layout3dRootRenderBox) {
        addSurface(renderObject.surface, current);
      }
    }
    element.visitChildren((child) => visit(child, current));
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) visit(root, null);
  for (final host in hosts) {
    for (final surface in host.host.pointers.surfaces) {
      addSurface(surface, host);
    }
  }
  return found.values.toList();
}

/// Every [Overlay3d] in [surface]'s own tree, outermost first.
List<Overlay3d> _overlaysIn(Layout3dSurface surface) {
  final overlays = <Overlay3d>[];
  void walk(Layout3d box) {
    if (box is Overlay3d) overlays.add(box);
    box.visitChildren(walk);
  }

  walk(surface);
  return overlays;
}

/// The surface at the root of [box]'s tree.
Layout3dSurface? rootSurfaceOf(Layout3d box) {
  Layout3d? node = box;
  while (node != null) {
    if (node is Layout3dSurface && node.parent == null) return node;
    node = node.parent;
  }
  return null;
}

/// [box] in a few words for a failure message: its type and identity, and
/// the label or the text that says which one it is.
String describeBox3d(Layout3d box) {
  final short = box.toStringShort();
  final said = switch (box) {
    Semantics3d() => box.properties.label,
    Text3d() => box.data,
    RichText3d() => box.text.toPlainText(),
    _ => null,
  };
  return said == null ? short : '$short "$said"';
}

/// Whether [box] is [ancestor] or somewhere below it in the layout tree.
bool isAtOrBelow(Layout3d box, Layout3d ancestor) {
  Layout3d? node = box;
  while (node != null) {
    if (identical(node, ancestor)) return true;
    node = node.parent;
  }
  return false;
}

/// Where a press aimed at [box] lands, and what it would reach.
class Reach3d {
  Reach3d._(this.box, this.host, this.local, this.paths, this.problem);

  /// The box aimed at.
  final Layout3d box;

  /// The host the press goes through, or null when there is none.
  final SceneHost3d? host;

  /// The box's projected centre, in the view's coordinates, or null when it
  /// has none.
  final Offset? local;

  /// Every path a press at [local] would be dispatched to, front to back.
  final List<HitTestResult3d> paths;

  /// Why the box cannot be aimed at at all, or null when it can.
  final String? problem;

  /// The box's projected centre, in global coordinates.
  Offset? get global => local == null ? null : host!.toGlobal(local!);

  /// Whether a press at [global] reaches [box].
  bool get reaches =>
      problem == null &&
      paths.any(
        (path) => path.path.any((entry) => isAtOrBelow(entry.layout, box)),
      );

  /// What a press at [global] reaches instead, for a failure message.
  String describeMiss() {
    if (problem != null) return problem!;
    final at = 'a press at ${_describeOffset(global!)}';
    if (paths.isEmpty) {
      return '$at reaches nothing: no surface answers a ray through that '
          'point, so nothing under it is on a hit-testable path — a '
          'TapTarget3d, a Listener3d, a scrolling view, a NodeBox3d.';
    }
    final front = paths.first;
    final target = front.target!;
    final sameSurface = identical(rootSurfaceOf(target), rootSurfaceOf(box));
    // The deepest box hit is rarely one a person would recognize — a gesture
    // detector, a sized box — so the nearest label on the path says which
    // control it belongs to.
    String? label;
    for (final entry in front.path) {
      final layout = entry.layout;
      if (layout is Semantics3d && layout.properties.label != null) {
        label = layout.properties.label;
        break;
      }
    }
    final named = label == null || describeBox3d(target).endsWith('"$label"')
        ? describeBox3d(target)
        : '${describeBox3d(target)} under "$label"';
    return '$at reaches $named first, '
        '${sameSurface ? 'on the same surface' : 'on a surface in front of it'}, '
        'and the press never gets to the box.';
  }

  /// Aims at [box] through [surfaces].
  static Reach3d of(Layout3d box, List<SceneSurface3d> surfaces) {
    if (!box.attached || !box.hasSize) {
      return Reach3d._(
        box,
        null,
        null,
        const [],
        '${describeBox3d(box)} is not laid out.',
      );
    }
    final root = rootSurfaceOf(box);
    SceneSurface3d? record;
    for (final candidate in surfaces) {
      if (identical(candidate.surface, root)) record = candidate;
    }
    final host = record?.host;
    if (host == null) {
      return Reach3d._(
        box,
        null,
        null,
        const [],
        '${describeBox3d(box)} is not under a SceneInput3d, so there is no '
        'camera to aim a press with. '
        'Pump the screen with tester.pumpSurface3d or '
        'tester.pumpScene3d, or put a SceneInput3d around it.',
      );
    }
    final camera = host.camera;
    if (camera == null) {
      return Reach3d._(
        box,
        host,
        null,
        const [],
        'the SceneInput3d above ${describeBox3d(box)} has no camera.',
      );
    }
    final local = box.screenCenter(camera, host.size);
    if (local == null) {
      return Reach3d._(
        box,
        host,
        null,
        const [],
        '${describeBox3d(box)} is behind the camera, so it has no point on '
        'the screen.',
      );
    }
    final size = host.size;
    if (local.dx < 0 ||
        local.dy < 0 ||
        local.dx > size.width ||
        local.dy > size.height) {
      return Reach3d._(
        box,
        host,
        null,
        const [],
        '${describeBox3d(box)} projects to ${_describeOffset(local)}, outside '
        'the '
        '${size.width.toStringAsFixed(0)}×${size.height.toStringAsFixed(0)} '
        'view.',
      );
    }
    return Reach3d._(box, host, local, host.host.hitTestAt(local), null);
  }
}

String _describeOffset(Offset offset) =>
    '(${offset.dx.toStringAsFixed(1)}, ${offset.dy.toStringAsFixed(1)})';

/// Where [box]'s front, top, left corner is drawn, in [surface]'s layout
/// frame.
///
/// The box's own nudges — the depth step a `Stack3d` wrote, a node offset, a
/// node transform — are *kept*: this is where the geometry is, not where
/// layout put the slot. [Layout3d.worldTransform] undoes all three, so they
/// are put back on top of it; what stays undone is the box's own local
/// transform, which is the frame its children sit in rather than the frame it
/// measures itself in.
Offset3d drawnCornerIn(Layout3dSurface surface, Layout3d box) {
  final nudge = box.sceneOffset + box.nodeOffset;
  var drawn = box.worldTransform.multiplied(
    Matrix4.translationValues(nudge.x, nudge.y, nudge.z),
  );
  final animated = box.nodeTransform;
  if (animated != null) drawn = drawn.multiplied(animated);
  final toSurface = Matrix4.zero()..copyInverse(surface.node.globalTransform);
  final point = toSurface.transformed3(drawn.transformed3(Vector3.zero()));
  return Offset3d(point.x, point.y, point.z);
}
