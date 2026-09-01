import 'package:flutter/foundation.dart'
    show DiagnosticPropertiesBuilder, DiagnosticsProperty;

import 'layout3d.dart';

/// A typed key for one piece of tree-wide state on a [Layout3dOwner].
///
/// [Layout3dOwner] already carries `basis`, `metrics`, `painters` and
/// `focusScope` for one stated reason: they are state both layers need and
/// the imperative one has no `BuildContext` to read an inherited widget with.
/// A theme has exactly that shape — and a *theme* must not be a field on this
/// package, because Material vocabulary does not belong here. So the owner
/// carries an open, typed map instead, and the library that has an opinion
/// declares the key:
///
/// ```dart
/// // In a component library, not here.
/// const themeSlot = Layout3dSlot<Theme3dData>('theme');
///
/// owner.setSlot(themeSlot, Theme3dData.light());
/// final Theme3dData? theme = owner.slot(themeSlot);   // typed, no cast
/// ```
///
/// **A slot is its type and its [name], and nothing else.** Two
/// `Layout3dSlot<Theme3dData>('theme')` are the same slot however they were
/// written, and a `Layout3dSlot<Density3d>('theme')` is a different one.
///
/// Identity keying was the first design and it is wrong here, because Dart
/// canonicalizes `const` instances: two `const Layout3dSlot<T>('theme')` in
/// different files are already *one object*, so an identity-keyed slot would
/// behave as a value key when declared `const` and as a unique key when
/// declared `final` — the same code, two behaviours, decided by a keyword
/// nobody would think to look at. Value equality makes the rule the one a
/// reader can state.
///
/// The cost is that two libraries choosing the same name for the same type
/// collide, so **name a slot after the library that owns it**
/// (`'material3d.theme'`), declare it once, and import it.
///
/// **The owner stores the value; it does not own it.** Nothing is disposed
/// when the surface goes away — the map is cleared and that is all — for the
/// same reason the owner does not dispose the layouts it collects. A value
/// that holds resources is disposed by whoever put it there. (The
/// alternative, an owner that disposes anything disposable, is the ownership
/// trap `Text3dRendererFactory` exists to avoid, one level up.)
class Layout3dSlot<T extends Object> {
  /// Declares a slot holding a [T], called [name].
  const Layout3dSlot(this.name);

  /// What this slot is called, and half of what identifies it.
  ///
  /// Prefix it with the library that owns the slot, so two packages that both
  /// want a `'theme'` of the same type do not silently share one.
  final String name;

  /// The type this slot holds, which is the other half of its identity.
  Type get _type => T;

  @override
  bool operator ==(Object other) =>
      other is Layout3dSlot && other.name == name && other._type == _type;

  @override
  int get hashCode => Object.hash(T, name);

  @override
  String toString() => 'Layout3dSlot<$T>($name)';
}

/// A pass-through box that writes one owner slot while it is in the tree.
///
/// The imperative half of putting a value where the whole surface can reach
/// it, for a caller that would rather not hold the [Layout3dSurface] itself.
/// It writes [value] into [slotKey] when it attaches, rewrites it when [value]
/// changes, and clears the slot when it detaches.
///
/// ```dart
/// Layout3dSurface(
///   child: SlotProvider3d(
///     slot: themeSlot,
///     value: Theme3dData.light(),
///     child: screen,
///   ),
/// );
/// ```
///
/// **The slot it writes is the owner's, not this box's subtree.** There is no
/// scoping: a second provider for the same slot anywhere on the surface
/// overwrites the first, and whichever detaches last leaves the slot empty.
/// Tree-wide state is what the owner is for, and a per-subtree value is a
/// constructor argument or an `InheritedWidget`, not this.
class SlotProvider3d<T extends Object> extends ProxyLayout3d {
  /// Creates a box that provides [value] under [slot].
  SlotProvider3d({
    required Layout3dSlot<T> slot,
    required T? value,
    super.child,
    super.name,
  }) : _slot = slot,
       _value = value;

  final Layout3dSlot<T> _slot;

  /// The slot this box writes.
  Layout3dSlot<T> get slotKey => _slot;

  T? _value;

  /// What the slot holds while this box is attached.
  ///
  /// Setting it relayouts the subtree, because a value nobody was handed as a
  /// constraint is one that boxes read inside `performLayout` — the same
  /// reason writing [Layout3dSurface.metrics] relayouts. Nothing on a
  /// per-frame path should write it.
  T? get value => _value;

  set value(T? newValue) {
    if (_value == newValue) return;
    _value = newValue;
    if (_write()) markSubtreeNeedsLayout();
  }

  bool _write() => owner?.setSlot(_slot, _value) ?? false;

  @override
  void attach(Layout3dOwner owner) {
    super.attach(owner);
    _write();
  }

  @override
  void detach() {
    owner?.setSlot(_slot, null);
    super.detach();
  }

  @override
  void performLayout() {
    // The write happens on attach, but a box that is laid out before its
    // owner arrived (or was re-parented onto another surface) has to catch
    // up, and layout is the one moment every box is guaranteed to reach.
    _write();
    super.performLayout();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Layout3dSlot<T>>('slot', slotKey));
    properties.add(DiagnosticsProperty<T>('value', value));
  }
}
