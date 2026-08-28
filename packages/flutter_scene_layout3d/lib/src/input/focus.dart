import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, FlagProperty, StringProperty;
import 'package:flutter/gestures.dart' show PointerDownEvent;
import 'package:flutter/widgets.dart'
    show
        FocusAttachment,
        FocusNode,
        FocusOnKeyEventCallback,
        FocusScopeNode,
        TraversalDirection,
        ValueChanged;
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3;

import '../geometry/size3d.dart';
import '../hit_test.dart';
import '../layout3d.dart';
import 'events.dart';

/// Ties a Flutter [FocusNode] to a box, so a layout can be focused.
///
/// The node graph is Flutter's, unchanged. [FocusNode] already knows how to
/// hold primary focus, how to notify, how to hand a key event to its
/// ancestors, and how to be disposed; none of that is worth reimplementing on
/// a plane. What this adds is the other half: *which box* the focus belongs
/// to, so a highlight can be drawn on it, a scroll can bring it into view,
/// and traversal can reason about where it is in space.
///
/// ```dart
/// final focus = Focus3d(
///   onFocusChange: (has) => panel.stateLayer = has ? focused : StateLayer3d.none,
///   child: GestureDetector3d(onTap: submit, child: panel),
/// );
/// ```
///
/// A press inside a [Focus3d] focuses it, which is what
/// [focusOnPointerDown] is for: on a plane there is no browser and no
/// platform view to do it, and a control that cannot be reached with the
/// pointer cannot be reached at all. A component that only wants a focus
/// ring for keyboard use should consult `FocusManager.instance.highlightMode`
/// before drawing one, exactly as Material does.
///
/// ## What it needs, and where its nodes hang
///
/// Flutter's focus manager, so the binding has to exist:
/// `WidgetsFlutterBinding.ensureInitialized()`, or
/// `TestWidgetsFlutterBinding.ensureInitialized()` in a test.
///
/// The nodes hang under a [FocusScopeNode] of the surface's own —
/// [Layout3dOwner.focusScope] — which is parented under the application's
/// root scope the first time something on the surface asks for focus. That
/// scope skips Flutter's traversal deliberately: a `Tab` in the surrounding
/// widget tree should not walk into a scene, because Flutter's traversal
/// policies reason about a `Rect` from a `RenderObject`, and a box on a plane
/// has neither. Traversal inside the surface is [Focus3dTraversal]'s job.
class Focus3d extends ProxyLayout3d implements HitTestTarget3d {
  /// Creates a focusable box.
  ///
  /// [focusNode] is optional: without one this box makes a node and owns it,
  /// disposing it with itself. With one, the caller keeps ownership — which
  /// is what a component that outlives its layout, or a `Focus`-driven
  /// widget layer above, wants.
  Focus3d({
    FocusNode? focusNode,
    this.onFocusChange,
    this.focusOnPointerDown = true,
    bool autofocus = false,
    bool canRequestFocus = true,
    bool skipTraversal = true,
    FocusOnKeyEventCallback? onKeyEvent,
    super.child,
    super.name,
  }) : _autofocus = autofocus,
       _canRequestFocus = canRequestFocus,
       _skipTraversal = skipTraversal,
       _onKeyEvent = onKeyEvent,
       _ownsNode = focusNode == null {
    _node = focusNode ?? _makeNode();
    _attachment = _node.attach(null, onKeyEvent: _onKeyEvent);
    _node.addListener(_handleFocusChanged);
    _hadFocus = _node.hasFocus;
  }

  late FocusNode _node;
  late FocusAttachment _attachment;
  bool _ownsNode;
  bool _hadFocus = false;
  bool _autofocus;
  final bool _canRequestFocus;
  final bool _skipTraversal;
  final FocusOnKeyEventCallback? _onKeyEvent;

  FocusNode _makeNode() => FocusNode(
    debugLabel: node.name,
    canRequestFocus: _canRequestFocus,
    skipTraversal: _skipTraversal,
  );

  /// Called when this box gains or loses focus.
  ValueChanged<bool>? onFocusChange;

  /// Whether a press inside this box focuses it.
  bool focusOnPointerDown;

  /// The node holding this box's place in Flutter's focus tree.
  ///
  /// Everything a `FocusNode` can do it can do here: listen to it, hand it to
  /// a `Shortcuts` or `Actions` widget, ask it for `hasPrimaryFocus`.
  FocusNode get focusNode => _node;

  /// Swaps the node, or hands ownership back with null.
  ///
  /// The rule is the one [Scroll3dHolderMixin] keeps for scroll positions,
  /// because it is the same rule: **null means the default**, and the default
  /// is a node this box owns. So a declarative caller that stops passing a
  /// node gets a working box with a fresh one rather than one still tied to
  /// the node it passed two rebuilds ago. Focus follows the box: if this one
  /// had it, the new node takes it.
  set focusNode(FocusNode? value) {
    if (identical(_node, value)) return;
    final hadFocus = _node.hasPrimaryFocus;
    _node.removeListener(_handleFocusChanged);
    _attachment.detach();
    if (_ownsNode) _node.dispose();
    _ownsNode = value == null;
    _node = value ?? _makeNode();
    _attachment = _node.attach(null, onKeyEvent: _onKeyEvent);
    _node.addListener(_handleFocusChanged);
    _hadFocus = _node.hasFocus;
    if (hadFocus) requestFocus();
  }

  /// Whether this box, or something inside it, has focus.
  bool get hasFocus => _node.hasFocus;

  /// Whether this box itself has focus.
  bool get hasPrimaryFocus => _node.hasPrimaryFocus;

  /// Whether this box can take focus at all.
  bool get canRequestFocus => _node.canRequestFocus;

  set canRequestFocus(bool value) {
    _node.canRequestFocus = value;
  }

  /// Whether this box takes focus as soon as it is part of a laid-out tree.
  bool get autofocus => _autofocus;

  set autofocus(bool value) {
    if (_autofocus == value) return;
    _autofocus = value;
    if (value && attached) requestFocus();
  }

  /// Takes focus.
  ///
  /// The first call on a surface parents its scope under the application's
  /// root scope, which is the moment the scene starts taking part in the
  /// application's focus at all. Nothing happens before that, deliberately: a
  /// scene that is only looked at should not be able to take the keyboard
  /// away from the widgets around it.
  void requestFocus() {
    if (owner == null) return;
    enclosingScope.requestFocus(_node);
  }

  /// The scope this box's focus belongs to.
  ///
  /// The nearest [FocusScope3d] above it, and the surface's own scope
  /// ([Layout3dOwner.focusScope]) when there is none. That walk is the whole
  /// of what focus trapping is: a modal wraps its content in a scope, so
  /// everything inside it asks that scope for focus instead of the
  /// surface's, and focus cannot leak out of the dialog by a control simply
  /// asking for it.
  ///
  /// Only meaningful once this box is attached; reading it before that throws
  /// on the null owner.
  FocusScopeNode get enclosingScope {
    Layout3d? node = parent;
    while (node != null) {
      if (node is FocusScope3d) return node.scopeNode;
      node = node.parent;
    }
    return owner!.focusScope;
  }

  /// Gives up focus, handing it back to the enclosing scope.
  void unfocus() => _node.unfocus();

  /// The nearest [Focus3d] at or above [layout], or null.
  ///
  /// The walk a control uses to focus itself without being handed a node: a
  /// gesture detector deep inside a component can find the box that stands
  /// for the whole of it.
  static Focus3d? of(Layout3d layout) {
    Layout3d? node = layout;
    while (node != null) {
      if (node is Focus3d) return node;
      node = node.parent;
    }
    return null;
  }

  @override
  void handleEvent(PointerEvent3d event, HitTestEntry3d entry) {
    if (!focusOnPointerDown) return;
    if (event.event is! PointerDownEvent) return;
    if (!_node.canRequestFocus) return;
    requestFocus();
  }

  void _handleFocusChanged() {
    final has = _node.hasFocus;
    if (has == _hadFocus) return;
    _hadFocus = has;
    onFocusChange?.call(has);
  }

  @override
  void attach(Layout3dOwner owner) {
    super.attach(owner);
    if (_autofocus) requestFocus();
  }

  @override
  void dispose() {
    _node.removeListener(_handleFocusChanged);
    // Detaching is what takes the node back out of the focus tree; a node
    // that is only disposed would be left parented under the scope.
    _attachment.detach();
    if (_ownsNode) _node.dispose();
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      FlagProperty('hasFocus', value: hasFocus, ifTrue: 'FOCUSED'),
    );
    properties.add(
      FlagProperty(
        'hasPrimaryFocus',
        value: hasPrimaryFocus,
        ifTrue: 'PRIMARY',
      ),
    );
    properties.add(
      FlagProperty(
        'canRequestFocus',
        value: canRequestFocus,
        ifFalse: 'cannot request focus',
      ),
    );
    properties.add(
      FlagProperty(
        'focusOnPointerDown',
        value: focusOnPointerDown,
        ifFalse: 'not focusable by pointer',
      ),
    );
  }
}

/// A [FocusScopeNode] tied to a subtree, so focus can be trapped inside it.
///
/// The 3D analogue of Flutter's `FocusScope`, and it exists for the reason a
/// modal needs it: [Focus3d.requestFocus] asks the nearest scope above it,
/// and [Focus3dTraversal.traversalRootFor] stops the walk at the same place.
/// Wrap a dialog's content in one and the dialog's focus is its own — nothing
/// inside it can hand focus to the page behind, and tabbing inside it cycles
/// the dialog rather than walking out of it. [Overlay3dEntry] does exactly
/// this for a modal entry.
///
/// Scopes nest the way Flutter's do: this one parents under the nearest
/// enclosing [FocusScope3d], or under the surface's own scope
/// ([Layout3dOwner.focusScope]) when there is none, at the moment the box
/// joins an attached tree.
class FocusScope3d extends ProxyLayout3d {
  /// Creates a scope around [child].
  ///
  /// [node] is optional and follows the rule [Focus3d] keeps for its node:
  /// without one this box makes a scope and disposes it with itself; with
  /// one, the caller keeps ownership.
  FocusScope3d({
    FocusScopeNode? node,
    String? debugLabel,
    super.child,
    super.name,
  }) : _ownsNode = node == null {
    _scope =
        node ??
        FocusScopeNode(
          debugLabel: debugLabel ?? this.node.name,
          skipTraversal: true,
        );
    // Attached with a null context for the same reason the owner's scope is:
    // the attachment is what a later detach unparents through, and nothing
    // ever reparents through the context.
    _attachment = _scope.attach(null);
  }

  late final FocusScopeNode _scope;
  late final FocusAttachment _attachment;
  final bool _ownsNode;

  /// The node this box holds focus through.
  ///
  /// Everything a `FocusScopeNode` can do it can do here: ask it for
  /// `hasFocus`, hand it to a `FocusTraversalGroup`, call `unfocus` on it.
  FocusScopeNode get scopeNode => _scope;

  /// Whether focus is anywhere inside this scope.
  bool get hasFocus => _scope.hasFocus;

  @override
  void attach(Layout3dOwner owner) {
    super.attach(owner);
    _parentUnderEnclosingScope(owner);
  }

  /// Hangs this scope under the one above it.
  ///
  /// `setFirstFocus` is Flutter's way of parenting a scope: it reparents the
  /// child scope and names it the one focus goes to when the parent is asked.
  /// That second half is what a dialog wants — the scope that just appeared
  /// is where focus should land.
  void _parentUnderEnclosingScope(Layout3dOwner owner) {
    Layout3d? node = parent;
    while (node != null) {
      if (node is FocusScope3d) {
        node.scopeNode.setFirstFocus(_scope);
        return;
      }
      node = node.parent;
    }
    owner.focusScope.setFirstFocus(_scope);
  }

  @override
  void dispose() {
    // Detaching is what takes the scope back out of the focus tree; a scope
    // that is only disposed would be left parented under its ancestor.
    _attachment.detach();
    if (_ownsNode) _scope.dispose();
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      FlagProperty('hasFocus', value: hasFocus, ifTrue: 'FOCUSED'),
    );
    properties.add(
      StringProperty('debugLabel', scopeNode.debugLabel, quoted: true),
    );
  }
}

/// Moving focus from box to box on a surface.
///
/// Flutter's `DirectionalFocusTraversalPolicy` cannot be reused as it stands:
/// it reads a candidate's `Rect` off the `RenderObject` behind its
/// `BuildContext`, and a box here has neither — it has a [Size3d] and a
/// position in a frame that may be turned any way at all. So this reuses the
/// *idea* rather than the class: every candidate is projected onto the
/// surface's plane, giving the flat rectangles the policy was written for,
/// and the choice is made among those.
///
/// That is a first cut and is named as one. It is right for the case the
/// catalogue actually has — a screen of controls arranged on one plane — and
/// it is wrong for content that faces different ways, where "left" stops
/// being a property of the plane and becomes a property of the viewer.
/// Traversal *between* surfaces is not answered here at all; it belongs with
/// whoever builds overlays, since the question only arises once a second
/// surface is in front of the first.
class Focus3dTraversal {
  /// Creates a traversal policy. Subclass it to change the order.
  const Focus3dTraversal();

  /// The root traversal should search from, for something at [layout].
  ///
  /// The nearest [FocusScope3d] at or above it, and the root of the tree when
  /// there is none. This is the hook that makes a modal trap traversal:
  /// every method here takes the root to search from, so a `Tab` handler that
  /// resolves the root through this instead of reaching for the surface walks
  /// the dialog when a dialog is up and the whole page when it is not.
  ///
  /// ```dart
  /// final current = Focus3d.of(focusedBox);
  /// final root = Focus3dTraversal.traversalRootFor(current ?? surface);
  /// const Focus3dTraversal().next(root, current)?.requestFocus();
  /// ```
  static Layout3d traversalRootFor(Layout3d layout) {
    Layout3d? node = layout;
    var root = layout;
    while (node != null) {
      if (node is FocusScope3d) return node;
      root = node;
      node = node.parent;
    }
    return root;
  }

  /// Every focusable box under [root], in tree order.
  ///
  /// Skips what cannot be focused and what cannot be seen: a box whose node
  /// is hidden, or that has not been laid out, is not a candidate, so what a
  /// list has culled out of its window is not somewhere focus can land.
  List<Focus3d> focusableDescendants(Layout3d root) {
    final found = <Focus3d>[];
    void visit(Layout3d layout) {
      layout.visitChildren((child) {
        if (!child.node.visible) return;
        if (child is Focus3d && child.canRequestFocus && child.hasSize) {
          found.add(child);
        }
        visit(child);
      });
    }

    visit(root);
    return found;
  }

  /// The box focus should start on.
  Focus3d? firstFocus(Layout3d root) {
    final candidates = focusableDescendants(root);
    return candidates.isEmpty ? null : candidates.first;
  }

  /// The box after [current] in tree order, wrapping around at the end.
  Focus3d? next(Layout3d root, Focus3d? current) =>
      _step(root, current, forward: true);

  /// The box before [current] in tree order, wrapping around at the start.
  Focus3d? previous(Layout3d root, Focus3d? current) =>
      _step(root, current, forward: false);

  Focus3d? _step(Layout3d root, Focus3d? current, {required bool forward}) {
    final candidates = focusableDescendants(root);
    if (candidates.isEmpty) return null;
    if (current == null) {
      return forward ? candidates.first : candidates.last;
    }
    final index = candidates.indexOf(current);
    if (index < 0) return forward ? candidates.first : candidates.last;
    final next = forward ? index + 1 : index - 1;
    return candidates[(next + candidates.length) % candidates.length];
  }

  /// The box [direction] of [from], or null when there is nothing that way.
  ///
  /// Candidates are ranked the way Flutter ranks them on a screen: a box
  /// whose projection overlaps [from]'s band on the perpendicular axis wins
  /// over one that does not, because that is what "directly below" means to a
  /// reader, and among equals the nearest one wins.
  Focus3d? inDirection(
    Layout3d root,
    Focus3d from,
    TraversalDirection direction,
  ) {
    final source = projectedRect(from);
    if (source == null) return null;
    Focus3d? best;
    var bestScore = double.infinity;
    var bestInBand = false;
    for (final candidate in focusableDescendants(root)) {
      if (identical(candidate, from)) continue;
      final rect = projectedRect(candidate);
      if (rect == null) continue;
      final along = _distanceAlong(source, rect, direction);
      if (along <= _epsilon) continue;
      final inBand = _overlapsBand(source, rect, direction);
      final across = _distanceAcross(source, rect, direction);
      final score = along + across;
      if (inBand && !bestInBand) {
        best = candidate;
        bestScore = score;
        bestInBand = true;
        continue;
      }
      if (inBand != bestInBand) continue;
      if (score < bestScore) {
        best = candidate;
        bestScore = score;
        bestInBand = inBand;
      }
    }
    return best;
  }

  /// Moves focus [direction] from whatever holds it now, and reports whether
  /// anything moved.
  bool moveInDirection(
    Layout3d root,
    Focus3d from,
    TraversalDirection direction,
  ) {
    final target = inDirection(root, from, direction);
    if (target == null) return false;
    target.requestFocus();
    return true;
  }

  /// [box]'s extent projected onto the surface's plane, in world units, or
  /// null before the tree has been laid out.
  ///
  /// The eight corners are carried through whatever transforms stand between
  /// the box and the root and the bounding rectangle of what comes out is
  /// taken, so a box inside a `Transform3d` is judged by where it *appears*
  /// on the plane rather than by where it was measured.
  static Rect? projectedRect(Layout3d box) {
    if (!box.hasSize) return null;
    var root = box;
    while (root.parent != null) {
      root = root.parent!;
    }
    if (!root.hasSize) return null;
    final toRoot = Matrix4.zero();
    if (toRoot.copyInverse(root.worldTransform) == 0.0) return null;
    final matrix = toRoot.multiplied(box.worldTransform);
    final size = box.size;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (var corner = 0; corner < 8; corner++) {
      final point = matrix.transformed3(
        Vector3(
          corner & 1 == 0 ? 0.0 : size.width,
          corner & 2 == 0 ? 0.0 : size.height,
          corner & 4 == 0 ? 0.0 : size.depth,
        ),
      );
      minX = math.min(minX, point.x);
      minY = math.min(minY, point.y);
      maxX = math.max(maxX, point.x);
      maxY = math.max(maxY, point.y);
    }
    if (!minX.isFinite || !minY.isFinite) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// How far [candidate] lies in [direction] of [source], centre to centre.
  ///
  /// Centres rather than facing edges, because two boxes side by side in a
  /// row touch: the gap between them is zero, and a rule written on gaps
  /// would find nothing to the right of anything.
  static double _distanceAlong(
    Rect source,
    Rect candidate,
    TraversalDirection direction,
  ) => switch (direction) {
    TraversalDirection.up => source.center.dy - candidate.center.dy,
    TraversalDirection.down => candidate.center.dy - source.center.dy,
    TraversalDirection.left => source.center.dx - candidate.center.dx,
    TraversalDirection.right => candidate.center.dx - source.center.dx,
  };

  /// Slack for the comparison above, so two boxes whose centres agree to
  /// within a rounding error are not each other's neighbour.
  static const double _epsilon = 1e-9;

  /// How far [candidate] is off [source]'s axis, in the perpendicular
  /// direction. Zero when the two overlap.
  static double _distanceAcross(
    Rect source,
    Rect candidate,
    TraversalDirection direction,
  ) {
    final vertical =
        direction == TraversalDirection.up ||
        direction == TraversalDirection.down;
    final sourceStart = vertical ? source.left : source.top;
    final sourceEnd = vertical ? source.right : source.bottom;
    final start = vertical ? candidate.left : candidate.top;
    final end = vertical ? candidate.right : candidate.bottom;
    if (end < sourceStart) return sourceStart - end;
    if (start > sourceEnd) return start - sourceEnd;
    return 0.0;
  }

  /// Whether [candidate] shares any of [source]'s band on the perpendicular
  /// axis.
  ///
  /// Sharing an *edge* is not sharing a band: the box below and the box
  /// diagonally below both touch the source's column at a corner, and only
  /// one of them is what a reader means by "down".
  static bool _overlapsBand(
    Rect source,
    Rect candidate,
    TraversalDirection direction,
  ) {
    final vertical =
        direction == TraversalDirection.up ||
        direction == TraversalDirection.down;
    final sourceStart = vertical ? source.left : source.top;
    final sourceEnd = vertical ? source.right : source.bottom;
    final start = vertical ? candidate.left : candidate.top;
    final end = vertical ? candidate.right : candidate.bottom;
    return math.min(end, sourceEnd) - math.max(start, sourceStart) > _epsilon;
  }
}
