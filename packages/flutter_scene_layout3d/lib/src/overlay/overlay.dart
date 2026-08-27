import 'dart:ui' show Size;

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter/widgets.dart' show FocusManager, FocusNode;
import 'package:flutter_scene/scene.dart' show Camera, Node;
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3;

import '../boxes/stack.dart';
import '../camera_binding.dart';
import '../geometry/alignment3d.dart';
import '../geometry/basis3d.dart';
import '../geometry/constraints3d.dart';
import '../geometry/offset3d.dart';
import '../input/focus.dart';
import '../layout3d.dart';
import '../metrics.dart';
import '../surface.dart';
import 'modal_barrier.dart';

/// Builds the content of an [Overlay3dEntry].
///
/// Called once when the entry is inserted, and again for each
/// [Overlay3dEntry.markNeedsBuild]; the layout it returns belongs to the
/// entry, which disposes it when it is removed.
typedef Overlay3dBuilder = Layout3d Function(Overlay3dEntry entry);

/// Which surface an [Overlay3dEntry] lives on, and how far in front it sits.
///
/// Two answers, both honest, and the caller picks per entry. See the class
/// documentation on [Overlay3d] for which to reach for.
sealed class OverlayLayer3d {
  const OverlayLayer3d._();

  /// The entry is a child of the overlay itself, lifted toward the viewer.
  ///
  /// One surface, one layout pass, one plane node; hit ordering is the
  /// stack's, which is already right. The entry is bounded by the overlay's
  /// box, so it cannot overhang the panel, and the lift eats into whatever
  /// depth the panel has.
  ///
  /// [lift] is the distance toward the viewer, in world units. Null means the
  /// default, which is [Overlay3d.defaultLift] logical pixels taken through
  /// the tree's [Layout3dMetrics] — a lift is a depth-buffer separation, and
  /// a separation stated in world units is wrong at a different density.
  const factory OverlayLayer3d.inPlane({double? lift}) = InPlaneOverlayLayer3d;

  /// The entry gets a [Layout3dSurface] of its own, in front of the host.
  ///
  /// Unbounded by the host panel — a menu may overhang it — and bindable to
  /// the camera independently, so a dialog can face the viewer while the
  /// panel behind it stays angled. The cost is that hit testing has to be
  /// routed across surfaces, which is [Layout3dPointerGroup]'s job.
  const factory OverlayLayer3d.detached({
    double? lift,
    Offset3d offset,
    Constraints3d? constraints,
    Alignment3d origin,
    LayoutBasis3d? basis,
    Layout3dCameraBinding? binding,
  }) = DetachedOverlayLayer3d;

  /// How far toward the viewer this entry sits, in world units, at [metrics].
  double liftIn(Layout3dMetrics metrics);
}

/// An entry laid out on the host surface, lifted toward the viewer.
///
/// See [OverlayLayer3d.inPlane].
class InPlaneOverlayLayer3d extends OverlayLayer3d {
  /// Creates an in-plane layer.
  const InPlaneOverlayLayer3d({this.lift}) : super._();

  /// The distance toward the viewer, in world units, or null for the default.
  final double? lift;

  @override
  double liftIn(Layout3dMetrics metrics) =>
      lift ?? metrics.dp(Overlay3d.defaultLift);

  @override
  bool operator ==(Object other) =>
      other is InPlaneOverlayLayer3d && other.lift == lift;

  @override
  int get hashCode => Object.hash(InPlaneOverlayLayer3d, lift);

  @override
  String toString() => 'OverlayLayer3d.inPlane(lift: ${lift ?? 'default'})';
}

/// An entry on a surface of its own, parented to the host.
///
/// See [OverlayLayer3d.detached].
class DetachedOverlayLayer3d extends OverlayLayer3d {
  /// Creates a detached layer.
  const DetachedOverlayLayer3d({
    this.lift,
    this.offset = Offset3d.zero,
    this.constraints,
    this.origin = Alignment3d.center,
    this.basis,
    this.binding,
  }) : super._();

  /// The distance toward the viewer, in world units, or null for the default.
  final double? lift;

  /// Where the entry's plane sits relative to the anchor the overlay gives
  /// it, in the host's layout space.
  ///
  /// The anchor itself is a zero-extent box placed by the overlay's own
  /// [Stack3d.alignment], so the default of zero puts a centred overlay's
  /// entry at the centre of the panel.
  final Offset3d offset;

  /// What the entry's own surface is laid out against.
  ///
  /// Null derives them from the host: as wide and as tall as the overlay,
  /// and unbounded in depth. Unbounded in depth because escaping the panel's
  /// depth budget is half the reason to detach at all — a menu that has to
  /// stand out of the plane cannot be capped by the plane's thickness.
  final Constraints3d? constraints;

  /// Which point of the entry sits at its plane's origin.
  final Alignment3d origin;

  /// How the entry's layout space maps into its plane's scene space.
  ///
  /// Null means the right thing for the [binding], and the right thing is not
  /// the same in the two cases. Unbound, the entry's plane hangs in the
  /// host's *layout* space — the surface's basis has already been applied
  /// once, above it — so the entry adds no basis of its own and uses
  /// [hostBasis]. Bound, the binding writes a world-space plane transform
  /// built for [LayoutBasis3d.xy], so that is what the entry uses.
  final LayoutBasis3d? basis;

  /// Ties the entry's surface to a camera, independently of the host.
  ///
  /// The reason to reach for a detached entry at all in many cases: a
  /// [Layout3dCameraBinding.billboard] here keeps a dialog facing the viewer
  /// while the panel it belongs to stays angled. Drive it by calling
  /// [Overlay3d.updateCameraBindings] once a frame.
  final Layout3dCameraBinding? binding;

  /// The identity basis: the entry's layout space is the host's.
  ///
  /// The default for an unbound entry, and the only correct choice there,
  /// since the plane already hangs below a node that carries the host
  /// surface's basis.
  static final LayoutBasis3d hostBasis = LayoutBasis3d.fromMatrix(
    Matrix4.identity(),
    debugLabel: 'host',
  );

  /// The basis this layer's surface is built with.
  LayoutBasis3d get effectiveBasis =>
      basis ?? (binding == null ? hostBasis : LayoutBasis3d.xy);

  @override
  double liftIn(Layout3dMetrics metrics) =>
      lift ?? metrics.dp(Overlay3d.defaultLift);

  @override
  String toString() =>
      'OverlayLayer3d.detached(${binding == null ? 'unbound' : '$binding'})';
}

/// One thing put in front of everything else: a dialog, a menu, a snack bar.
///
/// An entry is inert until an [Overlay3d] takes it, and it is finished once
/// it is removed — an entry is not reinserted, which is the same contract
/// Flutter's `OverlayEntry` keeps. [builder] is called when the entry is
/// inserted and the layout it returns belongs to the entry: removing it
/// disposes that subtree, and, for a detached entry, the surface it was on.
///
/// ```dart
/// final entry = Overlay3dEntry(
///   modal: true,
///   onDismiss: () => entry.remove(),
///   builder: (_) => Container3d(
///     size: const Size3d(1.2, 0.8, 0.05),
///     decoration: panelDecoration,
///     child: Text3d('Delete this?', renderer: renderer),
///   ),
/// );
/// overlay.insertEntry(entry);
/// ```
class Overlay3dEntry {
  /// Creates an overlay entry.
  Overlay3dEntry({
    required this.builder,
    this.layer = const OverlayLayer3d.inPlane(),
    this.modal = false,
    this.dismissible = true,
    this.onDismiss,
    this.scrimBuilder,
    this.scrimThickness = 0.0,
    this.alignment,
    bool? trapFocus,
    this.restoreFocus = true,
    this.debugLabel,
  }) : trapFocus = trapFocus ?? modal;

  /// Builds this entry's content.
  final Overlay3dBuilder builder;

  /// Which surface this entry lives on, and how far in front.
  final OverlayLayer3d layer;

  /// Whether a [ModalBarrier3d] is put behind the content.
  ///
  /// The barrier fills the overlay, absorbs every ray aimed at what is
  /// behind it, and reports a tap on itself through [onDismiss]. It is the
  /// whole of what "modal" means here; trapping focus is [trapFocus], which
  /// defaults to this.
  final bool modal;

  /// Whether a tap on the barrier calls [onDismiss].
  final bool dismissible;

  /// Called when a tap lands outside the content, on the barrier.
  ///
  /// Nothing is removed for you: an entry that should close on an outside
  /// tap passes `onDismiss: entry.remove`, and a route lets [Navigator3d] pop
  /// it.
  final VoidCallback? onDismiss;

  /// Builds the scrim geometry inside the barrier, if any.
  ///
  /// A scrim in a scene is a slab, not an alpha wash; see [ModalBarrier3d].
  final Overlay3dBuilder? scrimBuilder;

  /// How deep the barrier's slab is, in world units.
  final double scrimThickness;

  /// Where the content sits inside a modal entry.
  ///
  /// Null means the overlay's own [Stack3d.alignment]. Ignored when [modal]
  /// is false, where the content is a plain child of the overlay and the
  /// overlay's alignment applies directly.
  final Alignment3d? alignment;

  /// Whether the entry's content gets a [FocusScope3d] of its own.
  ///
  /// A trapped entry's focus does not leak: [Focus3d.requestFocus] inside it
  /// asks the entry's scope rather than the surface's, and
  /// [Focus3dTraversal.traversalRootFor] stops the walk at the same place, so
  /// tabbing inside a dialog cycles the dialog. Defaults to [modal].
  final bool trapFocus;

  /// Whether removing the entry hands focus back to whatever had it.
  final bool restoreFocus;

  /// A name for this entry in diagnostics.
  final String? debugLabel;

  Overlay3d? _overlay;
  _Overlay3dEntryHost? _host;
  Layout3d? _content;
  FocusScope3d? _scope;
  FocusNode? _restoreTo;
  FocusNode? _pendingRestore;

  Layout3dSurface? _surface;
  Node? _frame;

  /// The overlay holding this entry, or null before it is inserted and after
  /// it is removed.
  Overlay3d? get overlay => _overlay;

  /// Whether this entry is in an overlay.
  bool get isInserted => _overlay != null;

  /// The entry's own surface, for a [OverlayLayer3d.detached] entry.
  ///
  /// Null for an in-plane entry, which has no surface of its own, and before
  /// insertion. What a [Layout3dPointerGroup] is handed so the entry can be
  /// pointed at.
  Layout3dSurface? get surface => _surface;

  /// The root of the layout this entry built, including the barrier and the
  /// focus scope wrapped around it.
  ///
  /// Null before insertion. For a detached entry this is the child of
  /// [surface], not a descendant of the overlay.
  Layout3d? get content => _content;

  /// The focus scope this entry traps focus in, when [trapFocus] is set.
  FocusScope3d? get focusScope => _scope;

  /// Takes this entry out of its overlay, disposing what it built.
  ///
  /// Safe to call twice; the second call does nothing. Idiomatic as a
  /// callback: `onDismiss: entry.remove`.
  void remove() => _overlay?.removeEntry(this);

  /// Rebuilds this entry's content in place.
  ///
  /// Disposes the old subtree and calls [builder] again, keeping the entry's
  /// position in the stack, its surface (for a detached entry), and its
  /// focus scope's node. The cheap thing a component does when its state
  /// changed and it is not driven by the widget layer.
  void markNeedsBuild() {
    final overlay = _overlay;
    if (overlay == null) return;
    assert(
      !(overlay.owner?.debugDoingLayout ?? false),
      'Overlay3dEntry.markNeedsBuild was called during layout. Rebuilding an '
      'entry edits the tree that is being laid out; do it before the flush, '
      'or from a callback the flush schedules.',
    );
    final surface = _surface;
    final old = _content;
    _build(overlay);
    if (surface != null) {
      surface.child = _content;
    } else {
      _host?.child = _content;
    }
    old?.dispose();
  }

  // ------------------------------------------------------------- internals

  /// Builds the content, wrapping it in the barrier and the focus scope.
  void _build(Overlay3d overlay) {
    var root = builder(this);
    if (modal) {
      root = Stack3d(
        alignment: alignment ?? overlay.alignment,
        name: 'Overlay3dEntry.modal',
        children: <Layout3d>[
          ModalBarrier3d(
            dismissible: dismissible,
            onDismiss: onDismiss,
            thickness: scrimThickness,
            child: scrimBuilder?.call(this),
          ),
          root,
        ],
      );
    }
    if (trapFocus) {
      // A fresh scope node on every build. Reusing the old one would mean
      // attaching it under the new scope before the old scope, disposed with
      // the old subtree, detached it — and the node would end up parented
      // nowhere. A rebuilt entry starts with focus wherever its content asks.
      root = _scope = FocusScope3d(
        debugLabel: debugLabel ?? 'Overlay3dEntry',
        child: root,
      );
    }
    _content = root;
  }

  void _insertInto(Overlay3d overlay) {
    assert(_overlay == null, 'An Overlay3dEntry is inserted once.');
    _overlay = overlay;
    _restoreTo = restoreFocus ? FocusManager.instance.primaryFocus : null;
    _build(overlay);
    final host = _host = _Overlay3dEntryHost(this);
    final layer = this.layer;
    if (layer is DetachedOverlayLayer3d) {
      _attachSurface(overlay, layer, host);
    } else {
      host.child = _content;
    }
  }

  /// Gives a detached entry its own surface, hung under the anchor the
  /// overlay places for it.
  ///
  /// Two nodes rather than one. [_frame] is the change of frame between the
  /// host and the entry: identity while the entry follows the panel, and the
  /// inverse of the anchor's world transform once a binding is driving the
  /// plane, since a binding writes a *world* transform and has no way to know
  /// what it is hanging under. The plane below it is the surface's own, and
  /// is the thing the binding writes.
  void _attachSurface(
    Overlay3d overlay,
    DetachedOverlayLayer3d layer,
    _Overlay3dEntryHost host,
  ) {
    final frame = _frame = Node()..name = 'Overlay3dEntry.frame';
    final surface = _surface = Layout3dSurface(
      constraints: layer.constraints ?? const Constraints3d(),
      basis: layer.effectiveBasis,
      metrics: overlay.metrics,
      origin: layer.origin,
      onNeedVisualUpdate: overlay._handleDetachedNeedsFlush,
      child: _content,
      name: debugLabel ?? 'Overlay3dEntry',
    );
    Overlay3d._detachedOwners[surface] = overlay;
    frame.add(surface.plane);
    host.node.add(frame);
  }

  void _removedFrom(Overlay3d overlay) {
    assert(identical(_overlay, overlay));
    _pendingRestore = (_scope?.scopeNode.hasFocus ?? false) ? _restoreTo : null;
    _overlay = null;
    _restoreTo = null;
    final surface = _surface;
    if (surface != null) {
      Overlay3d._detachedOwners[surface] = null;
      _host?.node.remove(_frame!);
      _frame = null;
      _surface = null;
      // The surface owns the content it was given, so this disposes the
      // subtree the builder made along with the plane it was on.
      surface.dispose();
    }
    _host = null;
    _content = null;
    _scope = null;
  }

  /// Hands focus back to whatever held it before this entry took it.
  ///
  /// Deliberately after the entry's subtree has been disposed rather than
  /// before. Disposing a focus node that still holds primary focus makes
  /// Flutter's manager pick a successor of its own — the nearest enclosing
  /// scope — and whichever request comes last is the one applied. So the
  /// restore has to be the last word, not the first.
  void _restoreFocusIfNeeded() {
    final restoreTo = _pendingRestore;
    _pendingRestore = null;
    if (restoreTo == null) return;
    if (!restoreTo.canRequestFocus) return;
    restoreTo.requestFocus();
  }

  /// How far toward the viewer this entry's *geometry* is pulled, in the
  /// host's layout space.
  Offset3d _sceneLift(Layout3dMetrics metrics) =>
      layer is DetachedOverlayLayer3d
      ? Offset3d.zero
      : Offset3d(0, 0, -layer.liftIn(metrics));

  @override
  String toString() {
    final where = layer is DetachedOverlayLayer3d ? 'detached' : 'in plane';
    return 'Overlay3dEntry(${debugLabel ?? ''}$where'
        '${modal ? ', modal' : ''})';
  }
}

/// Where an entry sits in the overlay's own stack.
///
/// A plain box for an in-plane entry, holding the content; an empty one for a
/// detached entry, whose content is on a surface hung below this box's node —
/// which is exactly what makes a detached entry follow the panel when the
/// panel turns.
///
/// The lift is applied here rather than by the overlay's [performLayout],
/// through [Layout3d.sceneOffset], so it moves the geometry and nothing else:
/// the box stays where the stack put it, a [Positioned3d] inside the entry
/// still pins to the face it named, and a ray still finds the entry by its
/// place in the stack rather than by how far it was lifted.
class _Overlay3dEntryHost extends ProxyLayout3d {
  _Overlay3dEntryHost(this.entry) : super(name: 'Overlay3dEntry');

  final Overlay3dEntry entry;

  @override
  Offset3d get sceneOffset => super.sceneOffset + entry._sceneLift(metrics);
}

/// A stack of things in front of everything else, the 3D analogue of
/// [Overlay].
///
/// The overlay is where a dialog, a menu, a snack bar or a tooltip is put:
/// content inserted from anywhere, above everything, outside the bounds of
/// whatever asked for it. Its children come in two kinds. The ones given as
/// [children] are the base — the application's own content, laid out as an
/// ordinary [Stack3d] would — and the [entries] are what has been put in
/// front, in order, the last one nearest the viewer.
///
/// ```dart
/// final overlay = Overlay3d(children: [page]);
/// surface.child = overlay;
///
/// final entry = Overlay3dEntry(modal: true, builder: (_) => dialog);
/// entry.onDismiss = entry.remove;
/// overlay.insertEntry(entry);
/// ```
///
/// ## What "in front" means, and why there are two answers
///
/// An entry is either **in plane** or **detached**, per entry, through
/// [Overlay3dEntry.layer].
///
/// In plane is the default and the cheap one: the entry is a child of the
/// overlay, laid out against the overlay's own constraints, and its geometry
/// is pulled toward the viewer by a lift so that it does not fight the panel
/// for the depth buffer. One surface, one layout pass, hit ordering already
/// correct. The limits are the honest ones: the entry cannot escape the
/// overlay's box, so a menu cannot overhang the panel's edge, and the lift
/// spends whatever depth the panel has.
///
/// Detached gives the entry a [Layout3dSurface] of its own, hung under the
/// overlay's node so it follows the panel, and bindable to a camera on its
/// own account so that a dialog can face the viewer while the panel behind it
/// stays angled. Flutter has no analogue of that second half. The cost is
/// that the entry is on another surface, so a ray has to be routed across
/// surfaces: use [Layout3dPointerGroup], which tests front to back and stops
/// at the first surface that answers.
///
/// ## Focus
///
/// A modal entry traps focus by default: its content is wrapped in a
/// [FocusScope3d], [Focus3d.requestFocus] inside it asks that scope, and
/// [Focus3dTraversal.traversalRootFor] stops the walk there. Removing the
/// entry hands focus back to whatever held it before, when the entry still
/// had it.
class Overlay3d extends Stack3d {
  /// Creates an overlay over [children].
  Overlay3d({
    super.alignment = Alignment3d.center,
    super.fit,
    super.depthStep,
    List<Overlay3dEntry>? initialEntries,
    super.children,
    super.name,
  }) {
    if (initialEntries != null) {
      insertAllEntries(initialEntries);
    }
  }

  /// The default lift of an entry, in logical pixels.
  ///
  /// Small on purpose: it is a depth-buffer separation, not a layout, and
  /// every logical pixel it spends is a logical pixel of the panel's own
  /// thickness that content can no longer stand in. Eight of them is far
  /// above the depth precision of any sane near/far pair and far below what
  /// a viewer reads as distance.
  static const double defaultLift = 8.0;

  /// The overlay a detached entry's surface belongs to.
  ///
  /// Keyed weakly on the surface, so a disposed one is not held alive. This
  /// is what lets [of] answer from inside a detached entry, where the layout
  /// tree ends at the entry's own surface instead of continuing up to the
  /// overlay.
  static final Expando<Overlay3d> _detachedOwners = Expando<Overlay3d>(
    'Overlay3d',
  );

  final List<Overlay3dEntry> _entries = <Overlay3dEntry>[];

  bool _flushingDetached = false;

  /// The entries in this overlay, back to front.
  List<Overlay3dEntry> get entries =>
      List<Overlay3dEntry>.unmodifiable(_entries);

  /// The surfaces of the detached entries, back to front.
  ///
  /// What a [Layout3dPointerGroup] routes rays through, in the order they
  /// stand in.
  List<Layout3dSurface> get detachedSurfaces => <Layout3dSurface>[
    for (final entry in _entries)
      if (entry._surface case final surface?) surface,
  ];

  /// The nearest overlay at or above [layout], or null.
  ///
  /// The walk a descendant uses to put something in front without being
  /// handed a handle. It crosses out of a detached entry: a box inside one
  /// finds the overlay that entry belongs to, not nothing, even though the
  /// layout tree it is in ends at the entry's own surface.
  static Overlay3d? of(Layout3d layout) {
    Layout3d? node = layout;
    while (node != null) {
      if (node is Overlay3d) return node;
      if (node is Layout3dSurface) {
        final owner = _detachedOwners[node];
        if (owner == null) return null;
        node = owner;
        continue;
      }
      node = node.parent;
    }
    return null;
  }

  /// Whether [entry] is in this overlay.
  bool holdsEntry(Overlay3dEntry entry) => _entries.contains(entry);

  /// Puts [entry] in front of everything, or next to another entry.
  ///
  /// [above] and [below] name an entry already here; giving neither puts this
  /// one on top. An entry belongs to one overlay and is inserted once.
  void insertEntry(
    Overlay3dEntry entry, {
    Overlay3dEntry? above,
    Overlay3dEntry? below,
  }) {
    assert(
      above == null || below == null,
      'Give insertEntry an entry to go above or one to go below, not both.',
    );
    assert(above == null || holdsEntry(above));
    assert(below == null || holdsEntry(below));
    assert(!holdsEntry(entry), 'This entry is already in this overlay.');
    entry._insertInto(this);
    _entries.insert(_indexFor(above: above, below: below), entry);
    _syncEntryOrder();
  }

  /// Inserts several entries in one go, keeping their order.
  void insertAllEntries(
    Iterable<Overlay3dEntry> entries, {
    Overlay3dEntry? above,
    Overlay3dEntry? below,
  }) {
    var at = _indexFor(above: above, below: below);
    for (final entry in entries) {
      assert(!holdsEntry(entry), 'This entry is already in this overlay.');
      entry._insertInto(this);
      _entries.insert(at++, entry);
    }
    _syncEntryOrder();
  }

  /// Takes [entry] out and disposes what it built.
  ///
  /// A no-op for an entry that is not here, so a double removal (a dismiss
  /// racing a pop) is harmless.
  void removeEntry(Overlay3dEntry entry) {
    if (!_entries.remove(entry)) return;
    final host = entry._host;
    entry._removedFrom(this);
    _syncEntryOrder();
    host?.dispose();
    entry._restoreFocusIfNeeded();
  }

  /// Takes every entry out, front to back.
  void clearEntries() {
    for (final entry in _entries.reversed.toList()) {
      removeEntry(entry);
    }
  }

  /// Reorders the entries, which must be the ones already here.
  void rearrangeEntries(List<Overlay3dEntry> order) {
    assert(
      order.length == _entries.length && order.every(holdsEntry),
      'rearrangeEntries takes the entries this overlay already holds.',
    );
    _entries
      ..clear()
      ..addAll(order);
    _syncEntryOrder();
  }

  int _indexFor({Overlay3dEntry? above, Overlay3dEntry? below}) {
    if (above != null) return _entries.indexOf(above) + 1;
    if (below != null) return _entries.indexOf(below);
    return _entries.length;
  }

  /// Keeps the entry hosts at the end of the child list, in entry order.
  ///
  /// The base children come first and the entries after them, so the stack's
  /// own back-to-front order *is* the overlay's: the last entry is nearest
  /// the viewer and is the first thing a ray reaches.
  void _syncEntryOrder() => syncChildren(_baseChildren());

  List<Layout3d> _baseChildren() => <Layout3d>[
    for (final child in heldChildren)
      if (child is! _Overlay3dEntryHost) child,
  ];

  /// The base children, with the entry hosts appended.
  ///
  /// The widget layer mirrors a reconciled child list onto a layout by
  /// calling this, and the list it mirrors is the base alone — it knows
  /// nothing about entries, which are inserted imperatively from wherever
  /// asked. Appending them here is what keeps the two sources of children
  /// from fighting.
  @override
  void syncChildren(List<Layout3d> children) {
    super.syncChildren(<Layout3d>[
      for (final child in children)
        if (child is! _Overlay3dEntryHost) child,
      for (final entry in _entries)
        if (entry._host case final host?) host,
    ]);
  }

  @override
  void performLayout() {
    super.performLayout();
    _layoutDetachedEntries();
  }

  /// Lays the detached entries' surfaces out, after this one has a size.
  ///
  /// They are separate trees with owners of their own, so this is a nested
  /// flush rather than a recursion into this pass: nothing here can dirty the
  /// tree being laid out. What is shared is the unit contract, which is
  /// pushed down every pass because a detached surface has no other way to
  /// learn that the host's metrics changed.
  void _layoutDetachedEntries() {
    if (_entries.isEmpty) return;
    _flushingDetached = true;
    try {
      for (final entry in _entries) {
        final surface = entry._surface;
        if (surface == null) continue;
        final layer = entry.layer as DetachedOverlayLayer3d;
        surface.metrics = metrics;
        if (layer.constraints case final constraints?) {
          surface.configuration = constraints;
        } else if (!(layer.binding?.derivesConstraints ?? false)) {
          surface.configuration = Constraints3d(
            maxWidth: size.width,
            maxHeight: size.height,
          );
        }
        if (layer.binding == null) {
          _placePlane(entry, layer);
        }
        surface.flush();
      }
    } finally {
      _flushingDetached = false;
    }
  }

  /// Puts an unbound entry's plane where the host anchored it, lifted.
  void _placePlane(Overlay3dEntry entry, DetachedOverlayLayer3d layer) {
    final offset = layer.offset;
    final transform = Matrix4.translationValues(
      offset.x,
      offset.y,
      offset.z - layer.liftIn(metrics),
    );
    final plane = entry._surface!.plane;
    if (plane.localTransform == transform) return;
    plane.localTransform = transform;
  }

  /// Runs the camera bindings of the detached entries that have one.
  ///
  /// Call it once a frame, before flushing, the way a bound surface's own
  /// binding is driven — the declarative layer does it off the enclosing
  /// scene's clock. Entries without a binding cost nothing here.
  ///
  /// A binding writes a *world* transform onto a plane, because that is what
  /// "in front of the camera" means, and an entry's plane hangs under the
  /// host panel. So the frame node above it is set to the inverse of the
  /// anchor's world transform first, which cancels the panel out, and the
  /// plane's translation is set to where the panel anchored the entry, in
  /// world terms, so a [Layout3dCameraBinding.billboard] keeps the position
  /// the panel gave it and takes only its facing from the camera.
  void updateCameraBindings({Camera? camera, Size? viewSize}) {
    for (final entry in _entries) {
      final surface = entry._surface;
      final host = entry._host;
      final frame = entry._frame;
      if (surface == null || host == null || frame == null) continue;
      final layer = entry.layer as DetachedOverlayLayer3d;
      final binding = layer.binding;
      if (binding == null) continue;
      if (binding.needsCamera && camera == null) continue;
      if (binding.needsViewSize && viewSize == null) continue;
      final anchor = host.node.globalTransform;
      final inverse = Matrix4.zero();
      if (inverse.copyInverse(anchor) == 0.0) continue;
      if (frame.localTransform != inverse) frame.localTransform = inverse;
      final offset = layer.offset;
      final origin = anchor.transformed3(
        Vector3(offset.x, offset.y, offset.z - layer.liftIn(metrics)),
      );
      final placed = surface.plane.localTransform.clone()
        ..setTranslation(origin);
      if (surface.plane.localTransform != placed) {
        surface.plane.localTransform = placed;
      }
      binding.update(surface, camera: camera, viewSize: viewSize);
      surface.flush();
    }
  }

  /// A detached entry's tree went dirty, which the host's own flush would
  /// never hear about.
  ///
  /// Reported as a relayout of the overlay rather than as a flush of the
  /// entry alone: the flush has to stay whole-surface and root-driven, so
  /// that a lazy view inside an entry builds its children in the window the
  /// root opened for it and not in some path of the overlay's own.
  void _handleDetachedNeedsFlush() {
    if (_flushingDetached) return;
    markNeedsLayout();
    owner?.requestVisualUpdate();
  }

  @override
  void dispose() {
    // The detached surfaces are not children, so nothing else walks over
    // them, and each owns the content its entry built. The hosts *are*
    // children and are disposed by the walk below, along with the in-plane
    // content hanging off them.
    for (final entry in _entries.toList()) {
      entry._removedFrom(this);
    }
    _entries.clear();
    super.dispose();
  }

  @override
  String toString() => 'Overlay3d(${_entries.length} entries)';
}
