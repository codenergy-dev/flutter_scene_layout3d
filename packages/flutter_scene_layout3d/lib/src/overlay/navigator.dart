import 'dart:async' show Completer, Future, unawaited;

import 'package:flutter/foundation.dart' show SynchronousFuture, protected;

import '../geometry/alignment3d.dart';
import '../layout3d.dart';
import 'overlay.dart';

/// What happens while a route comes in or goes out.
///
/// The seam animation is filled in through. A transition is asked to run
/// before the route's entry is taken out of the overlay, and after it is put
/// in, so an implementation has a laid-out subtree to move: the entry's
/// [Overlay3dEntry.content] is in the tree for the whole of both calls.
///
/// Nothing here animates anything — this package has no clock of its own yet
/// (see the animation plan). [none] is the honest default: routes appear and
/// disappear at once.
abstract class Route3dTransition {
  /// Allows subclasses to be const.
  const Route3dTransition();

  /// Runs as [route] arrives, after its entry is inserted.
  ///
  /// The returned future is not awaited by [Navigator3d.push]: a push is not
  /// blocked on its own animation, exactly as Flutter's is not.
  Future<void> forward(Route3d<Object?> route);

  /// Runs as [route] leaves, *before* its entry is removed.
  ///
  /// [Navigator3d.pop] awaits this and then takes the entry out, so a
  /// reverse transition that outlives its route is not possible.
  Future<void> reverse(Route3d<Object?> route);

  /// No transition: routes appear and disappear at once.
  static const Route3dTransition none = _NoTransition();
}

class _NoTransition extends Route3dTransition {
  const _NoTransition();

  @override
  Future<void> forward(Route3d<Object?> route) => SynchronousFuture<void>(null);

  @override
  Future<void> reverse(Route3d<Object?> route) => SynchronousFuture<void>(null);

  @override
  String toString() => 'Route3dTransition.none';
}

/// One thing on a [Navigator3d]'s stack, and the future its result arrives
/// on.
///
/// A route is a description of something to put in front, plus what to do
/// with the answer. It is pushed once and finished when it is popped;
/// [popped] completes with the result the pop carried.
///
/// Subclass it to control how the entry is built, or use [PageRoute3d], which
/// is the common case: a builder, a barrier, and a pop on an outside tap.
abstract class Route3d<T> {
  /// Creates a route.
  Route3d();

  final Completer<T?> _completer = Completer<T?>();

  Navigator3d? _navigator;
  Overlay3dEntry? _entry;
  bool _popping = false;

  /// The navigator holding this route, or null before it is pushed and after
  /// it is finished.
  Navigator3d? get navigator => _navigator;

  /// The overlay entry this route put in front, or null before it is pushed.
  Overlay3dEntry? get entry => _entry;

  /// Completes when this route is popped, with the result the pop carried.
  Future<T?> get popped => _completer.future;

  /// Whether this route is on a navigator's stack.
  bool get isActive => _navigator?.routes.contains(this) ?? false;

  /// Whether this route is the top of its navigator's stack.
  bool get isCurrent => identical(_navigator?.currentRoute, this);

  /// Builds the entry that puts this route in front.
  ///
  /// Called once, by [Navigator3d.push]. The entry belongs to the navigator
  /// from then on: it is inserted on push and removed on pop.
  @protected
  Overlay3dEntry createEntry();

  /// Called after this route's entry has been inserted.
  @protected
  void didPush() {}

  /// Called after this route's entry has been removed.
  @protected
  void didPop(T? result) {}

  /// Pops this route from its navigator, whether or not it is on top.
  ///
  /// Returns false when it is not on a navigator at all.
  bool pop([T? result]) {
    final navigator = _navigator;
    if (navigator == null) return false;
    return navigator.removeRoute(this, result);
  }

  void _finish(Object? result) {
    final typed = result as T?;
    _navigator = null;
    _entry = null;
    didPop(typed);
    if (!_completer.isCompleted) _completer.complete(typed);
  }

  @override
  String toString() => '$runtimeType(${isActive ? 'active' : 'finished'})';
}

/// A route that puts one built layout in front, behind a modal barrier.
///
/// The route [Navigator3d] is usually pushed with, and the shape a dialog, a
/// menu, or a bottom sheet takes: a builder, whether there is a barrier, and
/// whether a tap on it pops.
///
/// ```dart
/// final choice = await navigator.push(
///   PageRoute3d<bool>(
///     builder: (route) => confirmDialog(onYes: () => route.pop(true)),
///   ),
/// );
/// ```
class PageRoute3d<T> extends Route3d<T> {
  /// Creates a route over [builder].
  PageRoute3d({
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
  final Layout3d Function(PageRoute3d<T> route) builder;

  /// Which surface the route lives on, and how far in front.
  final OverlayLayer3d layer;

  /// Whether a [ModalBarrier3d] goes behind the content.
  final bool modal;

  /// Whether a tap on the barrier pops this route.
  final bool barrierDismissible;

  /// Builds the scrim geometry inside the barrier, if any.
  final Layout3d Function(PageRoute3d<T> route)? scrimBuilder;

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
  Overlay3dEntry createEntry() => Overlay3dEntry(
    builder: (_) => builder(this),
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

/// A stack of routes over an [Overlay3d]: push, pop, and the result that
/// comes back.
///
/// Thin on purpose. The overlay already orders what is in front of what and
/// owns what an entry built; a navigator adds the two things a stack of
/// *routes* has that a stack of entries does not — a result future per route,
/// and a transition hook to run while one arrives or leaves.
///
/// ```dart
/// final navigator = Navigator3d(overlay);
/// final name = await navigator.push(
///   PageRoute3d<String>(builder: (route) => namePrompt(route.pop)),
/// );
/// ```
///
/// It is deliberately **not** wired into Flutter's own `Navigator`. Flutter's
/// overlay is a stack of `RenderBox`es and its routes build 2D widgets; there
/// is no honest mapping. A 3D dialog opened from a 2D route, and the system
/// back button popping this stack, are real questions and are not answered
/// here: an application that wants either wires it up itself, by pushing on
/// this navigator from wherever it likes and calling [pop] from its own
/// `PopScope`.
class Navigator3d {
  /// Creates a navigator over [overlay].
  Navigator3d(this.overlay, {this.transition = Route3dTransition.none}) {
    _navigators[overlay] = this;
  }

  /// The overlay this navigator pushes into.
  final Overlay3d overlay;

  /// What runs while a route arrives or leaves.
  Route3dTransition transition;

  static final Expando<Navigator3d> _navigators = Expando<Navigator3d>(
    'Navigator3d',
  );

  final List<Route3d<Object?>> _routes = <Route3d<Object?>>[];

  /// The routes on the stack, bottom first.
  List<Route3d<Object?>> get routes =>
      List<Route3d<Object?>>.unmodifiable(_routes);

  /// The route on top, or null when the stack is empty.
  Route3d<Object?>? get currentRoute => _routes.isEmpty ? null : _routes.last;

  /// Whether there is anything to pop.
  bool get canPop => _routes.isNotEmpty;

  /// The navigator over the overlay at or above [layout], or null.
  ///
  /// The walk a control deep inside a dialog uses to pop it without being
  /// handed a navigator. It crosses out of a detached entry, because
  /// [Overlay3d.of] does.
  static Navigator3d? of(Layout3d layout) {
    final overlay = Overlay3d.of(layout);
    return overlay == null ? null : _navigators[overlay];
  }

  /// Pushes [route] and returns the future its result arrives on.
  ///
  /// The entry goes in front of everything already in the overlay, including
  /// entries that are not routes: a snack bar inserted directly is behind a
  /// dialog pushed after it.
  Future<T?> push<T>(Route3d<T> route) {
    assert(route._navigator == null, 'A Route3d is pushed once.');
    route._navigator = this;
    final entry = route.createEntry();
    route._entry = entry;
    _routes.add(route);
    overlay.insertEntry(entry);
    route.didPush();
    unawaited(transition.forward(route));
    return route.popped;
  }

  /// Pops the top route, completing its [Route3d.popped] with [result].
  ///
  /// Returns false when there is nothing to pop. The entry is taken out after
  /// [transition]'s reverse completes, so a route with an animation is on
  /// screen for the whole of it; with the default transition that is the same
  /// turn.
  bool pop<T>([T? result]) {
    final route = currentRoute;
    if (route == null) return false;
    return removeRoute(route, result);
  }

  /// Pops [route] wherever it is on the stack.
  ///
  /// Returns false when it is not here, or is already leaving.
  bool removeRoute(Route3d<Object?> route, [Object? result]) {
    if (!identical(route._navigator, this)) return false;
    if (route._popping) return false;
    if (!_routes.remove(route)) return false;
    route._popping = true;
    final entry = route._entry;
    final reverse = transition.reverse(route);
    if (reverse is SynchronousFuture<void>) {
      _finish(route, entry, result);
    } else {
      unawaited(reverse.then((_) => _finish(route, entry, result)));
    }
    return true;
  }

  /// Pops routes off the top until [predicate] holds, or the stack is empty.
  void popUntil(bool Function(Route3d<Object?> route) predicate) {
    while (_routes.isNotEmpty && !predicate(_routes.last)) {
      pop();
    }
  }

  /// Pops every route, top first.
  void popAll([Object? result]) {
    while (_routes.isNotEmpty) {
      removeRoute(_routes.last, result);
    }
  }

  void _finish(Route3d<Object?> route, Overlay3dEntry? entry, Object? result) {
    entry?.remove();
    route._finish(result);
  }

  @override
  String toString() => 'Navigator3d(${_routes.length} routes)';
}
