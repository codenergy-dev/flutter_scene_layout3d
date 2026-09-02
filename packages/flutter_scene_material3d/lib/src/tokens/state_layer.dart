import 'dart:ui' show Color, lerpDouble;

import 'package:flutter_scene_layout3d/flutter_scene_layout3d.dart'
    show StateLayer3d;

/// One of the four things a pointer or the focus ring can be doing to a
/// component.
///
/// Material calls the result a *state layer*: a wash of the surface's "on"
/// colour laid over it at a published opacity. `StateLayer3d` in the layout
/// package is exactly that — one colour, one opacity, across the whole box —
/// and it is carried on `DecoratedBox3d` rather than on the decoration
/// precisely so that entering one of these states writes a shader uniform and
/// touches no layout at all.
///
/// Two states Flutter's `WidgetState` has are missing on purpose. There is no
/// `selected` because selection in Material is a token substitution (a
/// different container colour), not a wash; and there is no `disabled`
/// because a disabled control here is *also* a substitution —
/// `ColorScheme3d.disabledContainer` and `.disabledContent` — since there is
/// no opacity anywhere in this stack to fade a subtree with.
enum Material3dState {
  /// A pointer is over the component and not pressed.
  hovered,

  /// The component holds the focus.
  focused,

  /// A pointer is down on the component.
  pressed,

  /// The component is being dragged.
  dragged,
}

/// Material 3's published state-layer opacities, and the rule for a component
/// that is in more than one state at once.
///
/// The figures are the specification's: 8% for hover, 10% for focus and for
/// press, 16% for a drag. They are opacities rather than colours because the
/// *colour* comes from whatever the component is drawn on — `onSurface` over a
/// surface, `onPrimary` over a filled button — and a token that carried one
/// would have to be re-derived every time the scheme changed.
class StateLayerOpacity3d {
  /// Creates a set of state-layer opacities.
  const StateLayerOpacity3d({
    this.hover = 0.08,
    this.focus = 0.10,
    this.press = 0.10,
    this.drag = 0.16,
  }) : assert(hover >= 0.0 && hover <= 1.0),
       assert(focus >= 0.0 && focus <= 1.0),
       assert(press >= 0.0 && press <= 1.0),
       assert(drag >= 0.0 && drag <= 1.0);

  /// Material 3's published figures: 8%, 10%, 10% and 16%.
  static const StateLayerOpacity3d baseline = StateLayerOpacity3d();

  /// 8%. A pointer resting over the component.
  final double hover;

  /// 10%. The component holds the focus.
  final double focus;

  /// 10%. A pointer is down on the component.
  final double press;

  /// 16%. The component is in flight.
  final double drag;

  /// The opacity for [state].
  double of(Material3dState state) => switch (state) {
    Material3dState.hovered => hover,
    Material3dState.focused => focus,
    Material3dState.pressed => press,
    Material3dState.dragged => drag,
  };

  /// The opacity for a component in [states], which is the strongest of them
  /// and not their sum.
  ///
  /// A hovered control that is also focused and then pressed does not get
  /// 28% of a wash; Material resolves one state layer, and the precedence is
  /// the order the states are listed in [Material3dState] read backwards —
  /// a drag beats a press, a press beats the focus, the focus beats a hover.
  /// Taking the maximum is the same answer for the baseline figures and stays
  /// right for a theme that reorders them, which is why it is written this
  /// way rather than as a chain of ifs.
  double forStates(Set<Material3dState> states) {
    var opacity = 0.0;
    for (final state in states) {
      final value = of(state);
      if (value > opacity) opacity = value;
    }
    return opacity;
  }

  /// The layer a component in [states] draws over a surface whose content
  /// colour is [color].
  ///
  /// Returns [StateLayer3d.none] for a component in no state at all, which is
  /// the value that costs the shader nothing.
  StateLayer3d resolve(Set<Material3dState> states, Color color) {
    final opacity = forStates(states);
    return opacity == 0.0
        ? StateLayer3d.none
        : StateLayer3d(color: color, opacity: opacity);
  }

  /// A copy with the given opacities replaced.
  StateLayerOpacity3d copyWith({
    double? hover,
    double? focus,
    double? press,
    double? drag,
  }) => StateLayerOpacity3d(
    hover: hover ?? this.hover,
    focus: focus ?? this.focus,
    press: press ?? this.press,
    drag: drag ?? this.drag,
  );

  /// Linearly interpolates between two sets of opacities.
  ///
  /// Held inside `[0, 1]`, because `StateLayer3d` asserts on an opacity
  /// outside it and an overshooting curve produces one by construction — the
  /// same clamp, for the same reason, as `Elevation3d.lerp` and
  /// `Thickness3d.lerp`.
  static StateLayerOpacity3d lerp(
    StateLayerOpacity3d a,
    StateLayerOpacity3d b,
    double t,
  ) => StateLayerOpacity3d(
    hover: _lerp(a.hover, b.hover, t),
    focus: _lerp(a.focus, b.focus, t),
    press: _lerp(a.press, b.press, t),
    drag: _lerp(a.drag, b.drag, t),
  );

  static double _lerp(double a, double b, double t) =>
      lerpDouble(a, b, t)!.clamp(0.0, 1.0);

  @override
  bool operator ==(Object other) =>
      other is StateLayerOpacity3d &&
      other.hover == hover &&
      other.focus == focus &&
      other.press == press &&
      other.drag == drag;

  @override
  int get hashCode => Object.hash(hover, focus, press, drag);

  @override
  String toString() => 'StateLayerOpacity3d($hover, $focus, $press, $drag)';
}
