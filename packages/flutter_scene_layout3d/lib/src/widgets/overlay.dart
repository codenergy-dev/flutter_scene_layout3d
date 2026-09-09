import 'dart:ui' show Size;

import 'package:flutter/foundation.dart'
    show ValueListenable, VoidCallback, listEquals;
import 'package:flutter/rendering.dart' show RenderBox, RenderObject;
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        InheritedWidget,
        ObjectKey,
        State,
        StatefulWidget,
        StatelessWidget,
        Widget,
        WidgetsBinding;
import 'package:flutter_scene/scene.dart' show Camera, SceneScope;

import '../boxes/stack.dart';
import '../geometry/alignment3d.dart';
import '../layout3d.dart';
import '../overlay/modal_barrier.dart';
import '../overlay/navigator.dart';
import '../overlay/overlay.dart';
import 'framework.dart';

/// Imperative access to the [Overlay3d] a [SceneOverlay3d] owns.
///
/// Attach one where the overlay is described and entries can be inserted from
/// anywhere that has the controller, without a `BuildContext` in hand — a
/// component's own state object, a service, a test.
class Overlay3dController {
  Overlay3d? _overlay;

  /// The overlay, or null while the widget is unmounted.
  Overlay3d? get overlay => _overlay;
}

/// The declarative form of [Overlay3d]: a stack of things in front of
/// everything else.
///
/// Put one high in a layout — around a whole panel, usually — and every
/// descendant can put something in front of it with
/// `SceneOverlay3d.of(context).insertEntry(...)`. The base content is
/// [child]; the entries are inserted imperatively, because that is what
/// "from anywhere, at any time, outliving the widget that asked" means: a
/// dialog opened from a button's callback is not part of that button's
/// subtree.
///
/// ```dart
/// SceneOverlay3d(
///   camera: camera,
///   child: SceneColumn3d(children: [...]),
/// )
///
/// // ... from a button, deep inside:
/// final overlay = SceneOverlay3d.of(context);
/// late final Overlay3dEntry entry;
/// entry = Overlay3dEntry(
///   modal: true,
///   onDismiss: () => entry.remove(),
///   builder: (_) => dialogLayout,
/// );
/// overlay.insertEntry(entry);
/// ```
///
/// An entry's content is a [Layout3d] rather than a widget, which is the one
/// place this differs from Flutter's `Overlay`. The layout objects are the
/// same ones the widgets drive, so nothing is out of reach; what an entry
/// does not get is reconciliation, so a component that rebuilds its dialog
/// calls [Overlay3dEntry.markNeedsBuild].
class SceneOverlay3d extends StatefulWidget {
  /// Creates an overlay over [child].
  const SceneOverlay3d({
    super.key,
    this.alignment = Alignment3d.center,
    this.fit = StackFit3d.loose,
    this.depthStep = 0.0,
    this.camera,
    this.viewSize,
    this.controller,
    this.child,
  });

  /// Where entries and base children sit.
  final Alignment3d alignment;

  /// How non-positioned children are sized.
  final StackFit3d fit;

  /// How far toward the viewer each successive child's geometry is pulled.
  ///
  /// Independent of an entry's own lift, which is
  /// [OverlayLayer3d.inPlane]'s job.
  final double depthStep;

  /// The camera the detached entries' bindings read.
  ///
  /// With one, [Overlay3d.updateCameraBindings] runs off the enclosing
  /// scene's per-frame clock, so a billboarded dialog keeps facing the viewer
  /// without the application ticking anything. Entries without a binding cost
  /// nothing.
  final Camera? camera;

  /// The logical size of the view a screen-filling entry derives from.
  ///
  /// Leave it null in the common case: the size of the nearest laid-out
  /// ancestor box is used, which under a `SceneView` is the view itself.
  final Size? viewSize;

  /// Imperative access to the overlay this widget owns.
  final Overlay3dController? controller;

  /// The content the entries stand in front of.
  final Widget? child;

  /// The overlay above [context].
  ///
  /// Throws when there is none, which is a programming error: a component
  /// that opens a dialog needs somewhere to put it. Use [maybeOf] where the
  /// absence is a real case.
  static Overlay3d of(BuildContext context) {
    final overlay = maybeOf(context);
    assert(
      overlay != null,
      'SceneOverlay3d.of found no SceneOverlay3d above this context. Wrap the '
      'part of the layout that opens dialogs in one.',
    );
    return overlay!;
  }

  /// The overlay above [context], or null.
  static Overlay3d? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Overlay3dScope>()?.overlay;

  @override
  State<SceneOverlay3d> createState() => _SceneOverlay3dState();
}

class _SceneOverlay3dState extends State<SceneOverlay3d> {
  late final Overlay3d _overlay = Overlay3d(
    alignment: widget.alignment,
    fit: widget.fit,
    depthStep: widget.depthStep,
    name: 'SceneOverlay3d',
  );

  /// The enclosing view's per-frame clock, when there is one.
  ///
  /// A camera binding has to run every frame and the camera moves without
  /// anything in the widget tree changing, so a rebuild is the wrong signal —
  /// the same reasoning [SceneLayout3d] follows for its own binding.
  ValueListenable<Duration>? _frames;

  /// The widget-built entries, in the order they stand in.
  ///
  /// Kept rather than derived on every notification so that an entry with no
  /// widget in it — a `Draggable3d`'s feedback, say — costs no rebuild at
  /// all: a drag inserts and removes an entry per gesture and none of them
  /// changes this list.
  List<WidgetOverlay3dEntry> _widgetEntries = const <WidgetOverlay3dEntry>[];

  @override
  void initState() {
    super.initState();
    widget.controller?._overlay = _overlay;
    _overlay.entriesChanged.addListener(_handleEntriesChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyBindings());
  }

  /// The entry list changed, so the widget-built entries may have to be
  /// mounted or unmounted.
  ///
  /// Deferred to a post-frame callback when it arrives from inside the frame
  /// — a component that opens something from a layout callback rather than
  /// from a gesture — because `setState` is illegal there. Everything else
  /// happens in the same turn, so a dialog opened from a tap is in the tree
  /// on the very next frame.
  void _handleEntriesChanged() {
    if (!mounted) return;
    final next = <WidgetOverlay3dEntry>[
      for (final entry in _overlay.entries)
        if (entry is WidgetOverlay3dEntry) entry,
    ];
    if (listEquals(next, _widgetEntries)) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      _widgetEntries = next;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() => _widgetEntries = next);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final frames = SceneScope.maybeOf(context)?.elapsed;
    if (identical(frames, _frames)) return;
    _frames?.removeListener(_applyBindings);
    _frames = frames;
    frames?.addListener(_applyBindings);
  }

  @override
  void didUpdateWidget(SceneOverlay3d oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      if (identical(oldWidget.controller?._overlay, _overlay)) {
        oldWidget.controller?._overlay = null;
      }
      widget.controller?._overlay = _overlay;
    }
  }

  @override
  void dispose() {
    _frames?.removeListener(_applyBindings);
    // Before clearEntries, which notifies: a listener that called setState
    // from inside dispose would throw, and there is nothing left to rebuild.
    _overlay.entriesChanged.removeListener(_handleEntriesChanged);
    if (identical(widget.controller?._overlay, _overlay)) {
      widget.controller?._overlay = null;
    }
    // The entries are this widget's to release: each detached one holds a
    // surface of its own, which nothing else in the tree walks over. The
    // overlay layout itself follows the rule every layout widget keeps and is
    // disposed with the surface it hangs in.
    _overlay.clearEntries();
    super.dispose();
  }

  void _applyBindings() {
    if (!mounted) return;
    final camera = widget.camera;
    if (camera == null) return;
    _overlay.updateCameraBindings(camera: camera, viewSize: _resolveViewSize());
  }

  Size? _resolveViewSize() {
    final explicit = widget.viewSize;
    if (explicit != null) return explicit;
    RenderObject? node = context.findRenderObject();
    while (node != null) {
      if (node is RenderBox && node.hasSize && !node.size.isEmpty) {
        return node.size;
      }
      node = node.parent;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    return _Overlay3dScope(
      overlay: _overlay,
      child: _Overlay3dWidget(
        overlay: _overlay,
        alignment: widget.alignment,
        fit: widget.fit,
        depthStep: widget.depthStep,
        children: <Widget>[
          if (child != null) child,
          // One host per widget-built entry, keyed on the entry so that
          // reordering the stack moves the element rather than rebuilding it.
          // Each host contributes a zero-sized anchor to the overlay's base
          // children and hands the subtree it reconciled to the entry's slot
          // instead of adopting it, which is the whole trick.
          for (final entry in _widgetEntries)
            _Overlay3dEntryContent(key: ObjectKey(entry), entry: entry),
        ],
      ),
    );
  }
}

/// Carries the overlay down to the descendants that put things in it.
class _Overlay3dScope extends InheritedWidget {
  const _Overlay3dScope({required this.overlay, required super.child});

  final Overlay3d overlay;

  @override
  bool updateShouldNotify(_Overlay3dScope oldWidget) =>
      !identical(overlay, oldWidget.overlay);
}

/// Hosts the overlay the state owns.
///
/// The layout is made by the state rather than by [createLayout], because
/// [SceneOverlay3d.of] has to hand it to descendants that are built *inside*
/// this widget: the handle has to exist before the subtree it serves does.
class _Overlay3dWidget extends Layout3dWidget {
  const _Overlay3dWidget({
    required this.overlay,
    required this.alignment,
    required this.fit,
    required this.depthStep,
    required super.children,
  });

  final Overlay3d overlay;
  final Alignment3d alignment;
  final StackFit3d fit;
  final double depthStep;

  @override
  Overlay3d createLayout(BuildContext context) => overlay;

  @override
  void updateLayout(BuildContext context, Overlay3d layout) {
    assert(identical(layout, overlay));
    layout
      ..alignment = alignment
      ..fit = fit
      ..depthStep = depthStep;
  }
}

/// The declarative form of [ModalBarrier3d]: a slab that fills what it is
/// given, swallows every ray, and reports the tap that should dismiss what is
/// in front of it.
///
/// [Overlay3dEntry.modal] puts one in for you; this is for a barrier that is
/// part of a layout described in widgets.
class SceneModalBarrier3d extends SingleChildLayout3dWidget {
  /// Creates a barrier.
  const SceneModalBarrier3d({
    super.key,
    this.onDismiss,
    this.dismissible = true,
    this.thickness = 0.0,
    super.child,
  });

  /// Called when a tap lands on the barrier itself.
  final VoidCallback? onDismiss;

  /// Whether a tap calls [onDismiss].
  final bool dismissible;

  /// The barrier's extent along the depth axis, in world units.
  final double thickness;

  @override
  ModalBarrier3d createLayout(BuildContext context) => ModalBarrier3d(
    onDismiss: onDismiss,
    dismissible: dismissible,
    thickness: thickness,
  );

  @override
  void updateLayout(BuildContext context, ModalBarrier3d layout) {
    layout
      ..onDismiss = onDismiss
      ..dismissible = dismissible
      ..thickness = thickness;
  }
}

/// Where a widget-built [Overlay3dEntry]'s subtree hangs.
///
/// An entry's content is a [Layout3d] — [Overlay3dEntry.builder] returns one
/// — because giving entries widget subtrees would mean a second
/// reconciliation path through the element tree. A [WidgetOverlay3dEntry]
/// builds one of these instead: an empty proxy, inserted at once, that the
/// widget layer fills in on the frame after the entry goes in.
///
/// **It does not own what it holds.** Everything else in the declarative
/// layer follows the rule that a widget owns the layout it created, and a
/// slot that disposed its child would make the entry a second owner of a
/// subtree the element tree is still driving. So removing an entry releases
/// the content rather than disposing it, and the hosting box that built it
/// disposes it when it leaves the tree.
class Overlay3dContentSlot3d extends ProxyLayout3d {
  /// Creates an empty slot.
  Overlay3dContentSlot3d({super.name = 'Overlay3dEntry.slot'});

  @override
  void dispose() {
    // Released, not disposed: see the class documentation.
    child = null;
    super.dispose();
  }
}

/// Builds the content of a [WidgetOverlay3dEntry].
typedef WidgetOverlay3dBuilder =
    Widget Function(BuildContext context, WidgetOverlay3dEntry entry);

/// An [Overlay3dEntry] whose content is a widget subtree.
///
/// The entry a component written in widgets reaches for. Everything an
/// ordinary entry has — the layer and its lift, the barrier, the focus trap,
/// the ordering — is unchanged; what differs is that [contentBuilder] returns
/// a `Widget` and the subtree it describes is reconciled by the same element
/// machinery as the rest of the tree, so a `StatefulWidget` inside a dialog
/// keeps its state and an `InheritedWidget` above the overlay reaches it.
///
/// ```dart
/// late final WidgetOverlay3dEntry entry;
/// entry = WidgetOverlay3dEntry(
///   modal: true,
///   onDismiss: () => entry.remove(),
///   contentBuilder: (context, _) => const Dialog3d(child: SceneText3d('Hi')),
/// );
/// SceneOverlay3d.of(context).insertEntry(entry);
/// ```
///
/// **The content arrives one frame after the entry does**, and Flutter's own
/// `Overlay` behaves the same way: inserting an entry marks the widget that
/// owns the overlay as needing to build, and the subtree exists once that
/// build has run. Until then the entry is in the stack with an empty slot —
/// its barrier is already up, so a modal is modal from the moment it is
/// inserted. A test pumps once after inserting.
///
/// It only works under a [SceneOverlay3d]. An entry of this kind put into a
/// bare imperative [Overlay3d] shows nothing, because nothing is listening
/// for it; the assert in [Overlay3d.insertEntry]'s neighbourhood cannot catch
/// that, so this is where it is written down.
class WidgetOverlay3dEntry extends Overlay3dEntry {
  /// Creates an entry whose content is built from widgets.
  WidgetOverlay3dEntry({
    required this.contentBuilder,
    super.layer,
    super.modal,
    super.dismissible,
    super.onDismiss,
    super.scrimBuilder,
    super.scrimThickness,
    super.alignment,
    super.trapFocus,
    super.restoreFocus,
    super.debugLabel,
  }) : super(builder: _makeSlot);

  /// Builds this entry's content.
  ///
  /// Called from the widget layer, with a context inside the overlay, so
  /// everything inherited above the overlay is in scope.
  final WidgetOverlay3dBuilder contentBuilder;

  Overlay3dContentSlot3d? _slot;

  /// The slot this entry's widgets are attached to, or null before the entry
  /// is inserted.
  Overlay3dContentSlot3d? get contentSlot => _slot;

  static Layout3d _makeSlot(Overlay3dEntry entry) {
    final self = entry as WidgetOverlay3dEntry;
    return self._slot = Overlay3dContentSlot3d(
      name: self.debugLabel ?? 'Overlay3dEntry.slot',
    );
  }
}

/// Hosts one [WidgetOverlay3dEntry]'s subtree and hands it to the entry.
///
/// A [Layout3dWidget] that does not mirror its children onto its own layout.
/// Its layout is a zero-sized anchor, which the overlay adopts as an ordinary
/// base child and which occupies nothing and answers no ray; the subtree
/// underneath goes into the entry's [Overlay3dContentSlot3d] instead, which
/// is under the entry's host, behind its barrier and inside its focus scope.
class _Overlay3dEntryContent extends Layout3dWidget {
  _Overlay3dEntryContent({required super.key, required this.entry})
    : super(children: <Widget>[_Overlay3dEntryBuilder(entry: entry)]);

  final WidgetOverlay3dEntry entry;

  @override
  Layout3d createLayout(BuildContext context) => _Overlay3dContentAnchor();

  @override
  void updateLayout(BuildContext context, Layout3d layout) {}

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _Overlay3dContentRenderBox(entry, createLayout(context));
}

/// Calls the entry's builder, so that a rebuild of the content does not
/// rebuild the host that reparents it.
class _Overlay3dEntryBuilder extends StatelessWidget {
  const _Overlay3dEntryBuilder({required this.entry});

  final WidgetOverlay3dEntry entry;

  @override
  Widget build(BuildContext context) => entry.contentBuilder(context, entry);
}

/// The zero-sized box a widget-built entry leaves among the overlay's base
/// children.
///
/// It exists because every [Layout3dRenderBox] carries a layout and this one's
/// real output is somewhere else. It takes the smallest size it is offered,
/// which in a [Stack3d] is nothing, and a zero-extent box answers no ray.
class _Overlay3dContentAnchor extends Layout3d {
  _Overlay3dContentAnchor() : super(name: 'Overlay3dEntry.anchor');

  @override
  void performLayout() {
    size = constraints.smallest;
  }
}

/// Puts the subtree it reconciled into the entry's slot rather than into its
/// own layout.
///
/// The one place the declarative layer reparents: everywhere else
/// [Layout3dRenderBox.layoutChildBoxes] hands its children to its own layout,
/// and here they go to a layout in a different part of the tree — under the
/// entry's host, which is where "in front of everything" lives.
class _Overlay3dContentRenderBox extends Layout3dRenderBox {
  _Overlay3dContentRenderBox(this.entry, super.layout3d) {
    // The anchor is this box's own and nothing else holds it.
    disposeLayoutOnUnmount = true;
  }

  final WidgetOverlay3dEntry entry;

  Layout3d? _content;

  @override
  void layoutChildBoxes() {
    Layout3d? content;
    var child = firstChild;
    while (child != null) {
      child.layout(Layout3dRenderBox.hostConstraints);
      if (child is Layout3dRenderBox) {
        content ??= child.layout3d;
      } else {
        assert(debugCheckNoInterposedRenderObject(child));
      }
      child = childAfter(child);
    }
    _content = content;
    final slot = entry.contentSlot;
    // Null once the entry has been removed: the slot went with it, and the
    // subtree here is on its way out of the element tree on the next build.
    if (slot == null || identical(slot.child, content)) return;
    if (content != null) {
      final previous = content.parent;
      if (previous != null && !identical(previous, slot)) {
        detachLayout(content, previous);
      }
    }
    slot.child = content;
  }

  @override
  void dispose() {
    final content = _content;
    _content = null;
    if (content != null) {
      final parent = content.parent;
      if (parent != null) detachLayout(content, parent);
      content.dispose();
    }
    super.dispose();
  }
}

/// A [Route3d] whose content is a widget subtree.
///
/// [PageRoute3d] with a `Widget` where its `Layout3d` is, and the route a
/// declarative application actually pushes:
///
/// ```dart
/// final confirmed = await navigator.push(
///   WidgetPageRoute3d<bool>(
///     builder: (context, route) => ConfirmDialog(onYes: () => route.pop(true)),
///   ),
/// );
/// ```
///
/// As with [WidgetOverlay3dEntry], the content is in the tree from the frame
/// after the push; the barrier is up from the push itself.
class WidgetPageRoute3d<T> extends Route3d<T> {
  /// Creates a route over [builder].
  WidgetPageRoute3d({
    required this.builder,
    this.layer = const OverlayLayer3d.inPlane(),
    this.modal = true,
    this.barrierDismissible = true,
    this.scrimBuilder,
    this.scrimThickness = 0.0,
    this.alignment,
    this.trapFocus,
    this.restoreFocus = true,
    this.debugLabel,
  });

  /// Builds the route's content.
  final Widget Function(BuildContext context, WidgetPageRoute3d<T> route)
  builder;

  /// Which surface the route lives on, and how far in front.
  final OverlayLayer3d layer;

  /// Whether a [ModalBarrier3d] goes behind the content.
  final bool modal;

  /// Whether a tap on the barrier pops this route.
  final bool barrierDismissible;

  /// Builds the scrim geometry inside the barrier, if any.
  ///
  /// A [Layout3d], not a widget: it is the barrier's child, and the barrier
  /// is built by the entry rather than by the element tree. A component that
  /// wants a scrim described in widgets puts its own [SceneModalBarrier3d]
  /// inside [builder] and leaves [modal] false, which is also the only way to
  /// choose the depth step between the scrim and the content.
  final Layout3d Function(WidgetPageRoute3d<T> route)? scrimBuilder;

  /// How deep the barrier's slab is, in world units.
  final double scrimThickness;

  /// Where the content sits, or null for the overlay's own alignment.
  final Alignment3d? alignment;

  /// Whether the route's content gets a focus scope of its own, or null for
  /// the entry's default, which is [modal].
  final bool? trapFocus;

  /// Whether popping hands focus back to whatever held it before the push.
  final bool restoreFocus;

  /// A name for this route in diagnostics.
  final String? debugLabel;

  @override
  Overlay3dEntry createEntry() => WidgetOverlay3dEntry(
    contentBuilder: (context, _) => builder(context, this),
    layer: layer,
    modal: modal,
    dismissible: barrierDismissible,
    onDismiss: pop,
    scrimBuilder: scrimBuilder == null ? null : (_) => scrimBuilder!(this),
    scrimThickness: scrimThickness,
    alignment: alignment,
    trapFocus: trapFocus,
    restoreFocus: restoreFocus,
    debugLabel: debugLabel,
  );
}
