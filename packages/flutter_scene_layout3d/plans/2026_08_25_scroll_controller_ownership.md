---
status: completed
created_at: 2026-08-25T15:21:54Z
updated_at: 2026-08-25T18:04:00Z
commit: 88e98579925771720a40c21b3d5ad607f787fdf7
---

# Extract the scroll-controller ownership the four views share

The smallest of the three follow-ups from
[the review remediation](2026_08_25_layout3d_review_remediation.md), and the
one with no design questions in it. Do this first.

## What is duplicated

`Viewport3d`, `ListView3d`, `GridView3d` and `CustomScrollView3d` each carry
the same six things, character for character in most cases:

```dart
Scroll3dController _controller;
bool _ownsController;

@override
Scroll3dController get controller => _controller;

set controller(Scroll3dController? value) { ...nine lines... }

void _handleScrollChanged() => markNeedsLayout();

@override
void dispose() {
  _controller.removeListener(_handleScrollChanged);
  if (_ownsController) _controller.dispose();
  super.dispose();
}
```

plus, in the constructor, `_controller = controller ?? Scroll3dController()`,
`_ownsController = controller == null`, and an `addListener` in the body.

This is the fifth duplication cluster in the package and the last one left. The
other four became `Layout3dBuiltChildrenMixin` and
`Layout3dMeasuredChildrenMixin`; the reason this one was not folded in at the
same time is that `Viewport3d` holds a controller without holding built
children, so it does not mix those in.

It has already drifted once: the null-means-default rule landed in all four by
hand, and nothing but care kept them in step.

## Two mixins, not one

There is a second, smaller cluster tangled up with this one, and separating the
two is what makes both clean.

**`Layout3dLayoutPassMixin`** — the `_layingOut` flag, `runLayoutPass`, and the
`markNeedsLayout` override that ignores dirt raised during a view's own pass.
This currently lives inside `Layout3dBuiltChildrenMixin`, but
`CustomScrollView3d` needs it without built children (it has its own hand-rolled
copy), and `Viewport3d` has a half-copy: it guards `_handleScrollChanged` but
does *not* override `markNeedsLayout`, so dirt raised from anywhere else during
its layout still gets through. Pull it out into its own mixin on `Layout3d`:

```dart
mixin Layout3dLayoutPassMixin on Layout3d {
  bool _layingOut = false;

  @protected
  bool get layingOut => _layingOut;

  @protected
  void runLayoutPass(void Function() body) { ... }

  @override
  void markNeedsLayout() {
    if (_layingOut) return;
    super.markNeedsLayout();
  }
}
```

`Layout3dBuiltChildrenMixin` then declares `on Layout3dWithChildrenMixin,
Layout3dLayoutPassMixin` and loses those members.

**`Scroll3dHolderMixin`** — the controller half, on
`Layout3dLayoutPassMixin` so that `_handleScrollChanged` can be a plain
`markNeedsLayout` call:

```dart
mixin Scroll3dHolderMixin on Layout3dLayoutPassMixin implements Scrollable3d {
  Scroll3dController? _held;
  bool _ownsController = true;

  @override
  Scroll3dController get controller => _held!;

  set controller(Scroll3dController? value) { ...the rule below... }

  /// Installs the controller a constructor was handed. Constructor bodies only.
  @protected
  void initController(Scroll3dController? value) { ... }

  void _handleScrollChanged() => markNeedsLayout();

  @override
  void dispose() { ...detach, dispose if owned... }
}
```

The mixin leaves `Axis3d get scrollAxis` abstract; each view already has it.

## The constructor problem

A mixin has no constructor, so `_held` cannot be set in an initializer list.
Each view's constructor body calls `initController(controller)` instead, which
asserts it has not already run. The four constructors lose
`_controller = controller ?? Scroll3dController()`,
`_ownsController = controller == null` and
`_controller.addListener(_handleScrollChanged)`, and gain one line.

Lazy creation in the getter (`_held ??= Scroll3dController()`) is the
alternative and is worse: the listener has to be attached at the same moment,
and a view that is read before it is laid out would silently make a controller
nobody asked about. Prefer the explicit call.

## The rule to preserve

Landed in the last round and must survive unchanged: **null means the default**,
which for a controller is one the view owns.

- Constructor with null: the view makes one and owns it.
- `controller = someController`: the view detaches from the old one, disposes it
  only if it owned it, and does not own the new one.
- `controller = null`: the view makes a fresh one and owns it.
- `dispose()`: detach, and dispose only what the view owned.

## Steps

1. [x] Add `Layout3dLayoutPassMixin`, and make `Layout3dBuiltChildrenMixin`
   depend on it.
2. [x] Point `CustomScrollView3d` at it, deleting its hand-rolled copy.
3. [x] Add `Scroll3dHolderMixin`. Mix it into `Viewport3d`, `ListView3d`,
   `GridView3d`, `CustomScrollView3d`; delete the four copies; call
   `initController` from the four constructor bodies.
4. [x] Export both mixins, as the other two are.
5. [x] `CHANGELOG`: note that `Viewport3d` now ignores dirt raised during its
   own layout pass, which is the one behaviour change (its half-copy did not).

## Tests

The existing suite is the bar — 249 tests, no edits — because none of this is
new behaviour. Add two:

- [x] `dispose` disposes a controller the view made and leaves alone one it was
  given (currently untested in all four).
- [x] `controller = null` after a supplied one gives a fresh, working controller
  rather than the old one.

Both landed as one table-driven `controller ownership` group in
`test/scroll_test.dart`, run against all four views: content 10 long in a
window 4 long, and the first box slides by whatever the controller in force
says. Eight tests, 257 in the suite, the other 249 untouched. A `ChangeNotifier`
will not say whether it has been disposed, so `test/support.dart` gained
`isDisposed`, which asks it the only way there is — by using it again.

## Risk

Low. The one thing to watch is `initController` being missed in a constructor,
which the `_held!` getter turns into a null-check failure on first use rather
than something subtle. Make the assert message say which call is missing.

## What the work turned up

- **`Layout3dLayoutPassMixin` went in its own file**, `lib/src/layout_pass.dart`,
  rather than into `built_children.dart` as step 1 offered as its first
  option. `Viewport3d` and `CustomScrollView3d` need it without building
  children, and having them import a file whose dartdoc opens "A child list
  that may be built on demand" would say the wrong thing about why.
  `Scroll3dHolderMixin` went into `lib/src/scroll/scrollable.dart`, next to the
  `Scrollable3d` interface it satisfies, which all four views already import.
- **`SliverList3d` and `SliverGrid3d` had to be edited too**, which the plan
  did not mention. They mix in `Layout3dBuiltChildrenMixin`, so its new `on`
  clause obliges them to apply `Layout3dLayoutPassMixin` themselves; one line
  each, no behaviour change.
- **The four classes dropped `implements Scrollable3d`.** The mixin carries it,
  and stating it twice invites the two to disagree.
- The `_controller` field is gone, so the view bodies read the `controller`
  getter directly. It asserts a controller has been installed on every read,
  which is a handful of asserts per layout pass and only in debug.
- lib is 49 lines shorter (210 added, 259 removed) with the duplication gone.
  This was the fifth and last duplication cluster in the package.
