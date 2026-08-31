/// The declarative layer of `flutter_scene_layout3d`: 3D layout described
/// from a Flutter `build` method.
///
/// Each widget owns one of the layout objects from the imperative library and
/// applies property changes to it on rebuild, so an unchanged rebuild writes
/// nothing. The widgets live in the element tree (as zero-sized boxes that
/// paint nothing), which is what reconciles the layout tree: added, removed,
/// moved, and reordered children are handled by the same machinery every
/// other Flutter widget uses.
///
/// Start with [SceneLayout3d], the surface, among a `SceneView`'s children.
/// The value types ([Size3d], [Constraints3d], [EdgeInsets3d],
/// [Alignment3d], the alignment enums) are re-exported here, so this import
/// is usually all a declarative app needs.
///
/// ```dart
/// SceneView.declarative(
///   children: [
///     SceneLayout3d(
///       size: const Size3d(4, 3, 0.5),
///       child: SceneRow3d(
///         mainAxisAlignment: MainAxisAlignment3d.spaceEvenly,
///         children: [
///           SceneNodeBox3d(content: cube),
///           SceneExpanded3d(child: SceneNodeBox3d(content: banner)),
///         ],
///       ),
///     ),
///   ],
/// )
/// ```
library;

export 'src/animation/implicit.dart'
    show
        AnimatedLayout3dWidgetBaseState,
        ImplicitlyAnimatedLayout3dWidget,
        ImplicitlyAnimatedLayout3dWidgetState,
        Layout3dTweenConstructor,
        Layout3dTweenVisitor,
        SceneAnimatedAlign3d,
        SceneAnimatedContainer3d,
        SceneAnimatedPositioned3d,
        SceneAnimatedSizedBox3d;
export 'src/animation/node_transform.dart' show NodeTransform3d;
export 'src/animation/node_widgets.dart'
    show SceneAnimatedSlide3d, SceneNodeTransform3d;
export 'src/animation/tweens.dart'
    show
        Alignment3dTween,
        BorderRadius3dTween,
        BoxDecoration3dTween,
        Constraints3dTween,
        EdgeInsets3dTween,
        Offset3dTween,
        Size3dTween,
        StateLayer3dTween;
export 'src/boxes/flex.dart'
    show CrossAxisAlignment3d, FlexFit3d, MainAxisAlignment3d, MainAxisSize3d;
export 'src/boxes/custom_layout.dart' show MultiChildLayout3dDelegate;
export 'src/boxes/flow.dart' show Flow3dDelegate, Flow3dPaintingContext;
export 'src/boxes/node_box.dart' show BoxFit3d;
export 'src/boxes/stack.dart' show StackFit3d;
export 'src/boxes/table.dart'
    show
        FixedColumnWidth3d,
        FlexColumnWidth3d,
        FractionColumnWidth3d,
        IntrinsicColumnWidth3d,
        TableCellAlignment3d,
        TableColumnWidth3d;
export 'src/boxes/wrap.dart' show WrapAlignment3d, WrapCrossAlignment3d;
export 'src/camera_binding.dart' show Layout3dCameraBinding;
export 'src/debug/diagnostics.dart'
    show debugDescribeLayout3dTree, debugDumpLayout3dTree;
export 'src/debug/overflow.dart'
    show Layout3dOverflow, debugLayout3dOverflowReporter;
export 'src/debug/wireframe.dart'
    show
        Layout3dWireframe,
        debugLayout3dWireframeFactory,
        debugPaintLayout3dBaselines,
        debugPaintLayout3dSize;
export 'src/geometry/alignment3d.dart' show Alignment3d;
export 'src/geometry/basis3d.dart' show LayoutBasis3d;
export 'src/geometry/constraints3d.dart' show Constraints3d;
export 'src/geometry/edge_insets3d.dart' show EdgeInsets3d;
export 'src/geometry/offset3d.dart' show Axis3d, Offset3d;
export 'src/geometry/size3d.dart' show Size3d;
export 'src/hit_test.dart' show HitTestEntry3d, HitTestResult3d, Ray3d;
export 'src/input/drag.dart'
    show
        Drag3dAnchor,
        Drag3dDetails,
        Drag3dEvent,
        Drag3dEventKind,
        Drag3dSession,
        Drag3dTarget;
export 'src/input/draggable.dart'
    show
        Drag3dFeedbackBuilder,
        Drag3dStartMode,
        Drag3dTargetCallback,
        Drag3dWillAccept,
        DragTarget3d,
        Draggable3d;
export 'src/input/events.dart'
    show HitTestBehavior3d, HitTestTarget3d, PointerEvent3d;
export 'src/input/focus.dart' show Focus3d, Focus3dTraversal, FocusScope3d;
export 'src/input/listener.dart' show PointerEvent3dCallback;
export 'src/input/pointer.dart' show Layout3dPointer;
export 'src/input/pointer_group.dart' show Layout3dPointerGroup;
export 'src/overlay/modal_barrier.dart' show ModalBarrier3d;
export 'src/overlay/navigator.dart'
    show Navigator3d, PageRoute3d, Route3d, Route3dTransition;
export 'src/overlay/overlay.dart'
    show
        DetachedOverlayLayer3d,
        InPlaneOverlayLayer3d,
        Overlay3d,
        Overlay3dBuilder,
        Overlay3dEntry,
        OverlayLayer3d;
export 'src/widgets/overlay.dart'
    show Overlay3dController, SceneModalBarrier3d, SceneOverlay3d;
export 'src/layout3d.dart' show Layout3d;
export 'src/metrics.dart' show Layout3dMetrics, VisualDensity3d;
export 'src/semantics.dart'
    show Semantics3d, debugFocusableBoxesWithoutSemantics;
export 'src/scroll/grid_delegate.dart'
    show
        Grid3dDelegate,
        Grid3dDelegateWithFixedCrossAxisCount,
        Grid3dDelegateWithMaxCrossAxisExtent,
        Grid3dLayout;
export 'src/scroll/scroll_controller.dart'
    show ScrollDirection3d, Scroll3dController;
export 'src/scroll/scroll_physics.dart'
    show
        BouncingScroll3dPhysics,
        ClampingScroll3dPhysics,
        PageScroll3dPhysics,
        Scroll3dPhysics;
export 'src/scroll/scrollable.dart'
    show Scrollable3d, ensureVisible3d, offsetToReveal3d;
export 'src/sliver/sliver.dart' show Sliver3d;
export 'src/sliver/sliver_constraints.dart'
    show SliverConstraints3d, SliverGeometry3d;
export 'src/surface.dart' show Layout3dSurface;
export 'src/text/break_rules.dart'
    show OverflowWrap3d, TextBreakRules3d, TextWhitespace3d, WordBreak3d;
export 'src/text/text3d.dart' show Text3d;
export 'src/text/text_layout.dart' show TextLayout3d, TextLine3d, TextRun3d;
export 'src/text/text_measurement.dart'
    show
        ParagraphTextMeasurement3d,
        SegmentedTextMeasurement3d,
        TextMeasurement3d;
export 'src/text/text_renderer.dart' show Text3dRenderRequest, Text3dRenderer;
export 'src/widgets/drag.dart' show SceneDragTarget3d, SceneDraggable3d;
export 'src/widgets/framework.dart'
    show
        LazyLayout3dWidget,
        Layout3dWidget,
        SingleChildLayout3dWidget,
        debugCheckNoInterposedRenderObject;
export 'src/widgets/layouts.dart'
    show
        Layout3dWidgetBuilder,
        SceneAbsorbPointer3d,
        SceneAlign3d,
        SceneAspectRatio3d,
        SceneBaseline3d,
        SceneCenter3d,
        SceneColumn3d,
        SceneConstrainedBox3d,
        SceneCustomMultiChildLayout3d,
        SceneCustomScrollView3d,
        SceneContainer3d,
        SceneDepth3d,
        SceneExpanded3d,
        SceneFittedBox3d,
        SceneFlow3d,
        SceneFractionallySizedBox3d,
        SceneFlex3d,
        SceneFocus3d,
        SceneFlexible3d,
        SceneGestureDetector3d,
        SceneGridView3d,
        SceneHitTestArea3d,
        SceneIgnorePointer3d,
        SceneIndexedStack3d,
        SceneIntrinsicDepth3d,
        SceneIntrinsicHeight3d,
        SceneIntrinsicWidth3d,
        SceneLayoutBuilder3d,
        SceneLayoutId3d,
        SceneLimitedBox3d,
        SceneListener3d,
        SceneListView3d,
        SceneNodeBox3d,
        SceneOverflowBox3d,
        ScenePageView3d,
        ScenePadding3d,
        ScenePositioned3d,
        SceneRow3d,
        SceneSemantics3d,
        SceneSizedBox3d,
        SceneSliverGrid3d,
        SceneSliverList3d,
        SceneSliverPadding3d,
        SceneSliverToBoxAdapter3d,
        SceneSpacer3d,
        SceneStack3d,
        SceneTable3d,
        SceneTapTarget3d,
        SceneText3d,
        SceneTransform3d,
        SceneUnconstrainedBox3d,
        SceneViewport3d,
        SceneWrap3d;
export 'src/widgets/surface.dart' show Layout3dController, SceneLayout3d;
