import 'dart:ui' show Color;

import 'package:flutter/widgets.dart' show BuildContext, InheritedWidget;
import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show DecoratedBox3d, StateLayer3d;

import '../tokens/state_layer.dart';

/// The seam a hover, a focus or a press reaches a [Material3d] through,
/// **without rebuilding anything**.
///
/// This is the load-bearing class of the interaction layer, and the reason it
/// exists is the animation tier. `DecoratedBox3d.stateLayer` is a setter that
/// writes one shader uniform and asks for a repaint; it never calls
/// `markNeedsLayout` and never marks a widget dirty. An `InkWell3d` that
/// answered a hover with `setState` would throw all of that away — a pointer
/// crossing a list of twenty tiles would rebuild twenty subtrees and relay
/// out each of them — so the ink does not travel through the widget tree at
/// all. The surface publishes a controller once, at build time; an interactive
/// widget looks it up once, in `didChangeDependencies`; and every state change
/// afterwards is a method call that ends in one field assignment on a box.
///
/// Flutter reaches the same arrangement from the other side, with
/// `MaterialInkController` and an ink feature that paints itself. The
/// constraint here is the tier, not the spelling.
///
/// A component reads [states] to resolve its own tokens — a filled button is a
/// different colour when pressed, not merely washed — but reading it does not
/// subscribe to it. Anything that has to *rebuild* on a state change is a
/// state a component must hold itself; this channel is for the wash.
abstract class InkController3d {
  /// The states in force, as a value that must not be mutated.
  Set<Material3dState> get states;

  /// Whether [state] is in force.
  bool isIn(Material3dState state) => states.contains(state);

  /// Adds or removes [state] and writes the resulting wash.
  ///
  /// Cheap and idempotent: a state that is already in the set writes nothing
  /// at all, which matters because a pointer moving inside a box produces a
  /// hover event per frame.
  void setInkState(Material3dState state, {required bool active});

  /// Drops every state, for a control that has just been disabled or has lost
  /// the pointer and the focus at once.
  void clearInkStates();

  /// The controller published by the nearest [Material3d] above [context], or
  /// null when there is none.
  ///
  /// The caller becomes a dependent, which costs nothing: a `Material3d`
  /// keeps one controller for its whole life, so the scope never notifies.
  static InkController3d? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<InkController3dScope>()
      ?.controller;

  /// The controller published by the nearest [Material3d] above [context].
  ///
  /// Asserts when there is none. An `InkWell3d` outside a `Material3d` is
  /// almost always a mistake — there is no surface for the wash to be drawn
  /// on — but it is a survivable one, so `InkWell3d` itself uses [maybeOf]
  /// and simply does not light anything up.
  static InkController3d of(BuildContext context) {
    final controller = maybeOf(context);
    assert(
      controller != null,
      'InkController3d.of() found no Material3d above this context. A wash '
      'is drawn by the panel underneath it, so an interactive component has '
      'to be built inside a Material3d; use maybeOf() when being outside is '
      'a legitimate state.',
    );
    return controller!;
  }
}

/// Publishes one [InkController3d] to the subtree a [Material3d] covers.
///
/// An ordinary inherited widget with a value that never changes, so
/// [updateShouldNotify] is all but always false and looking the controller up
/// subscribes a widget to nothing.
class InkController3dScope extends InheritedWidget {
  /// Publishes [controller] below.
  const InkController3dScope({
    super.key,
    required this.controller,
    required super.child,
  });

  /// The controller of the enclosing surface.
  final InkController3d controller;

  @override
  bool updateShouldNotify(InkController3dScope oldWidget) =>
      !identical(controller, oldWidget.controller);
}

/// The implementation a [Material3d] owns, and the only writer of a panel's
/// state layer.
///
/// Split out of the widget so the whole channel can be tested without a GPU,
/// a painter or a pointer: give it a box, set a state, read the box's layer.
class MutableInkController3d implements InkController3d {
  /// Creates a controller washing in [color] at [opacities].
  MutableInkController3d({
    required Color color,
    StateLayerOpacity3d opacities = StateLayerOpacity3d.baseline,
  }) : _color = color,
       _opacities = opacities;

  final Set<Material3dState> _states = <Material3dState>{};
  DecoratedBox3d? _box;
  Color _color;
  StateLayerOpacity3d _opacities;

  @override
  Set<Material3dState> get states => _states;

  @override
  bool isIn(Material3dState state) => _states.contains(state);

  /// The layer the current states resolve to.
  StateLayer3d get layer => _opacities.resolve(_states, _color);

  /// The box this controller washes, or null before the first build.
  DecoratedBox3d? get box => _box;

  /// Points this controller at the box a [Material3d] just created or
  /// updated, and writes the current wash onto it.
  ///
  /// Called from the layout widget's `createLayout` and `updateLayout`, which
  /// is what keeps the box and the controller in step across a rebuild that
  /// replaces neither.
  void attach(DecoratedBox3d box) {
    _box = box;
    box.stateLayer = layer;
  }

  /// Forgets the box, when the [Material3d] that owned it is disposed.
  void detach() {
    _box = null;
  }

  /// Re-resolves the wash against a new content colour or a new set of
  /// opacities, which is what a theme change looks like from here.
  ///
  /// Returns true when anything actually changed, so a caller can skip the
  /// write. A theme change also relayouts, so this is not on a hot path; it
  /// is here so that a rebuild with an equal theme writes nothing.
  bool restyle({required Color color, required StateLayerOpacity3d opacities}) {
    if (_color == color && _opacities == opacities) return false;
    _color = color;
    _opacities = opacities;
    _apply();
    return true;
  }

  @override
  void setInkState(Material3dState state, {required bool active}) {
    final changed = active ? _states.add(state) : _states.remove(state);
    if (!changed) return;
    _apply();
  }

  @override
  void clearInkStates() {
    if (_states.isEmpty) return;
    _states.clear();
    _apply();
  }

  /// The one line the whole design is arranged around: a field assignment on
  /// a box, on the repaint-only tier, with nothing marked dirty anywhere.
  void _apply() => _box?.stateLayer = layer;

  @override
  String toString() =>
      'MutableInkController3d(${_states.isEmpty ? 'idle' : _states.join(', ')})';
}
