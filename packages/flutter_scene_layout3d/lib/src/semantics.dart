import 'package:flutter/foundation.dart'
    show
        DiagnosticPropertiesBuilder,
        DoubleProperty,
        FlagProperty,
        StringProperty;
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter_scene/scene.dart' show SemanticsComponent;
import 'package:vector_math/vector_math.dart' show Aabb3, Vector3;

import 'geometry/size3d.dart';
import 'input/focus.dart';
import 'layout3d.dart';

/// A box that publishes itself to assistive technology, the 3D analogue of
/// `Semantics`.
///
/// A catalogue that claims to implement Material claims accessibility with
/// it, and scene content is opaque to a screen reader by default: a button
/// built out of geometry is, to the platform, a picture. This box is the way
/// out. It attaches a [SemanticsComponent] to its own scene node, which
/// `SceneView` turns into a real Flutter semantics node whose focus rectangle
/// is the node's bounds projected through the camera — so the reader's focus
/// ring lands on the control, tracks it as the plane turns, and disappears
/// when the control is culled or hidden.
///
/// What a component author writes is Flutter's own [SemanticsProperties],
/// unchanged:
///
/// ```dart
/// Semantics3d(
///   properties: SemanticsProperties(
///     label: 'Continue',
///     button: true,
///     enabled: true,
///     onTap: submit,
///     textDirection: TextDirection.ltr,
///   ),
///   child: DecoratedBox3d(decoration: buttonSurface, child: label),
/// )
/// ```
///
/// That is deliberate: a `Button3d` in the catalogue declares the same
/// `button: true, label: ...` it would declare in a 2D Flutter widget, and
/// the platform sees the same thing. There is no second vocabulary to learn
/// and nothing to translate.
///
/// **The bounds come from layout, not from the geometry.** A
/// [SemanticsComponent] with no override projects the node's combined mesh
/// bounds, which for a control is whatever meshes happen to hang under it —
/// an icon and a label, not the touch target they sit in. This box overrides
/// them with its own [Layout3d.size] instead, so the semantics rectangle is
/// the box the layout protocol produced: the 48dp target, including the empty
/// room around the glyph. That agreement between what a ray can hit and what
/// a screen reader can focus is the whole point of putting semantics in the
/// layout tree rather than on the meshes.
///
/// **Traversal order is layout order**, without anything being said. Reading
/// order follows the scene graph, and in this package the scene graph *is*
/// the layout tree: a child's node is its parent's node's child, added in
/// layout order, by [Layout3d.adoptChild]. So a `Column3d` of controls reads
/// top to bottom, and a `Row3d` reads leading to trailing, for the same
/// reason they lay out that way. Set [sortOrder] only where that is wrong.
class Semantics3d extends ProxyLayout3d {
  /// Creates a box publishing [properties] for its subtree.
  Semantics3d({
    required SemanticsProperties properties,
    double? sortOrder,
    bool enabled = true,
    bool occlusionHiding = false,
    super.child,
    super.name,
  }) : _properties = properties,
       _enabled = enabled {
    _component = SemanticsComponent(
      properties: properties,
      sortOrder: sortOrder,
      occlusionHiding: occlusionHiding,
    );
    if (enabled) node.addComponent(_component);
  }

  late final SemanticsComponent _component;

  /// The component this box attaches to its node.
  ///
  /// Exposed because a control may want to reach past the properties for
  /// something only the component has — [SemanticsComponent.occlusionHiding],
  /// say — without this box growing a passthrough for every field.
  SemanticsComponent get component => _component;

  SemanticsProperties _properties;

  /// What this box tells the platform it is.
  ///
  /// Setting it never relayouts. Semantics have no say in any extent, so a
  /// button that changes its label from "Play" to "Pause" writes one field
  /// and asks for a frame; nothing above or below it is measured again.
  SemanticsProperties get properties => _properties;

  set properties(SemanticsProperties value) {
    if (identical(_properties, value)) return;
    _properties = value;
    _component.properties = value;
    owner?.requestVisualUpdate();
  }

  /// Where this box reads in traversal order, or null to follow the scene
  /// graph, which is layout order.
  double? get sortOrder => _component.sortOrder;

  set sortOrder(double? value) {
    if (_component.sortOrder == value) return;
    _component.sortOrder = value;
    owner?.requestVisualUpdate();
  }

  bool _enabled;

  /// Whether this box is published at all.
  ///
  /// Clearing it takes the component off the node, which is how a control
  /// that is temporarily not a control (a disabled item in a list that is
  /// being rebuilt, a route that has been pushed under another) leaves the
  /// semantics tree without being rebuilt.
  bool get enabled => _enabled;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (value) {
      node.addComponent(_component);
      _updateBounds();
    } else {
      node.removeComponent(_component);
    }
    owner?.requestVisualUpdate();
  }

  /// The nearest [Semantics3d] at or above [layout], or null.
  static Semantics3d? of(Layout3d layout) {
    Layout3d? node = layout;
    while (node != null) {
      if (node is Semantics3d) return node;
      node = node.parent;
    }
    return null;
  }

  @override
  void performLayout() {
    super.performLayout();
    _updateBounds();
  }

  void _updateBounds() {
    if (!_enabled) return;
    final Size3d(:width, :height, :depth) = size;
    // Measured in the box's own frame, where the origin corner is the
    // origin: exactly the frame the node's transform maps into the scene, so
    // the platform's rectangle is the layout box and nothing else.
    _component.boundsOverride = Aabb3.minMax(
      Vector3.zero(),
      Vector3(width, height, depth),
    );
  }

  @override
  void dispose() {
    if (_enabled) node.removeComponent(_component);
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      StringProperty('label', this.properties.label, quoted: true),
    );
    properties.add(DoubleProperty('sortOrder', sortOrder, defaultValue: null));
    properties.add(
      FlagProperty('enabled', value: enabled, ifFalse: 'not published'),
    );
  }
}

/// Every focusable box under [root] that no [Semantics3d] speaks for.
///
/// The agreement this checks is not a style rule: a box that can take focus
/// is, by definition, a control, and a control a screen reader cannot see is
/// a control half the users cannot reach. Focus and semantics have to be
/// declared on the same boxes or the two trees disagree — keyboard traversal
/// visits five things and the reader announces three.
///
/// A [Focus3d] counts as covered when a [Semantics3d] sits above it (the
/// usual shape: semantics wrap the whole control, focus sits inside it) or
/// anywhere below it. Call it in a test over a catalogue's page, or from a
/// debug menu:
///
/// ```dart
/// expect(debugFocusableBoxesWithoutSemantics(surface), isEmpty);
/// ```
List<Focus3d> debugFocusableBoxesWithoutSemantics(Layout3d root) {
  final missing = <Focus3d>[];
  for (final focus in const Focus3dTraversal().focusableDescendants(root)) {
    if (_hasSemanticsAbove(focus, root) || _hasSemanticsBelow(focus)) continue;
    missing.add(focus);
  }
  return missing;
}

bool _hasSemanticsAbove(Layout3d box, Layout3d root) {
  Layout3d? node = box;
  while (node != null) {
    if (node is Semantics3d) return true;
    if (identical(node, root)) return false;
    node = node.parent;
  }
  return false;
}

bool _hasSemanticsBelow(Layout3d box) {
  var found = false;
  void visit(Layout3d child) {
    if (found) return;
    if (child is Semantics3d) {
      found = true;
      return;
    }
    child.visitChildren(visit);
  }

  box.visitChildren(visit);
  return found;
}
