import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_scene_layout3d/widgets.dart';
import 'package:flutter_scene_material3d/flutter_scene_material3d.dart';

/// The two Material screens the gallery draws, and the state behind them.
///
/// Both are ordinary widget subtrees: a `Scaffold3d` and the components on it,
/// with no idea what plane they are laid out on. That is the claim the gallery
/// exists to make visible — [MaterialScreen] is mounted upright on a turning
/// panel and [TableScreen] flat on the ground, and neither one says a word
/// about geometry.
///
/// Everything here is sized in **logical pixels**. The surfaces that host
/// these screens carry the unit contract (`Layout3dMetrics`), so a 48dp touch
/// target is 48dp whether the panel is a metre wide or a hand's breadth.

/// An upright screen: a bar, a body that changes with the navigation bar, a
/// floating action button, and a snack bar when it is pressed.
///
/// It is a `Scaffold3d` and nothing else — the same widget an application
/// would write, with the same two tabs an application would write.
class MaterialScreen extends StatefulWidget {
  const MaterialScreen({super.key});

  @override
  State<MaterialScreen> createState() => _MaterialScreenState();
}

class _MaterialScreenState extends State<MaterialScreen> {
  int _tab = 0;

  // The inbox.
  final Set<int> _starred = <int>{1};
  int _filter = 0;

  // The settings.
  bool _notify = true;
  bool _compact = false;
  double _volume = 0.65;

  static const List<(String, String)> _messages = <(String, String)>[
    ('Ada Lovelace', 'The engine weaves algebraic patterns'),
    ('Grace Hopper', 'A ship in port is safe, but that is not'),
    ('Alan Kay', 'The best way to predict the future'),
    ('Barbara Liskov', 'A subtype must not surprise its caller'),
    ('Edsger Dijkstra', 'Simplicity is a prerequisite'),
  ];

  static const List<String> _filters = <String>['All', 'Unread', 'Starred'];

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger3d(
      child: Builder(
        builder: (context) => Scaffold3d(
          appBar: AppBar3d.text(
            title: _tab == 0 ? 'Inbox' : 'Settings',
            variant: AppBarVariant3d.small,
            actions: <Widget>[
              // A tooltip, because a hover is the only arrival in the
              // catalogue that needs no press at all: rest a pointer here and
              // the label fades up under it.
              Tooltip3d(
                message: 'Search the inbox',
                child: IconButton3d(
                  icon: Icons.search,
                  semanticLabel: 'Search',
                  onPressed: () => _say(context, 'Nothing to search yet'),
                ),
              ),
              // The overflow menu is how a person sees the other three
              // arrivals. There is no probe for whether a dialog *reads* as
              // arriving; looking at one is the lane, and this is what there
              // is to look at.
              PopupMenuButton3d<String>(
                semanticLabel: 'More',
                // Hung by its trailing corner: this button is against the
                // trailing edge of the panel, and a menu opening the usual way
                // would run off the surface, where there is nothing for a ray
                // to hit. See the note on `menuCorner`.
                menuCorner: AlignmentDirectional3d.topEnd,
                anchorCorner: AlignmentDirectional3d.bottomEnd,
                child: const Icon3d(Icons.more_vert),
                itemBuilder: (context) => const <MenuItem3dEntry<String>>[
                  MenuItem3dEntry<String>(value: 'about', label: 'About'),
                  MenuItem3dEntry<String>(value: 'sort', label: 'Sort by'),
                ],
                onSelected: (value) =>
                    value == 'about' ? _about(context) : _sort(context),
              ),
            ],
          ),
          body: _tab == 0 ? _inbox(context) : _settings(context),
          bottomNavigationBar: NavigationBar3d(
            selectedIndex: _tab,
            onDestinationSelected: (index) => setState(() => _tab = index),
            destinations: const <NavigationDestination3d>[
              NavigationDestination3d(
                icon: Icon3d(Icons.inbox),
                label: 'Inbox',
              ),
              NavigationDestination3d(
                icon: Icon3d(Icons.tune),
                label: 'Settings',
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton3d(
            semanticLabel: 'Compose',
            onPressed: () => _say(context, 'Composing a message'),
            child: const Icon3d(Icons.edit),
          ),
        ),
      ),
    );
  }

  /// A dialog, which grows and fades in over its own scrim.
  Future<void> _about(BuildContext context) async {
    final theme = Theme3d.of(context);
    await showDialog3d<void>(
      context: context,
      builder: (context) => Dialog3d(
        semanticLabel: 'About this gallery',
        child: SceneColumn3d(
          mainAxisSize: MainAxisSize3d.min,
          crossAxisAlignment: CrossAxisAlignment3d.start,
          children: <Widget>[
            SceneText3d(
              'Material, as geometry',
              style: theme.textStyle(
                Typography3dToken.headlineSmall,
                color: theme.colorScheme.onSurface,
              ),
            ),
            SceneSizedBox3d(height: _dp(context, 12)),
            SceneText3d(
              'Every panel here is a slab with a thickness, and every '
              'arrival is one duration and one curve out of the theme.',
              style: theme.textStyle(
                Typography3dToken.bodyMedium,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A bottom sheet, which rises one whole height from off the edge.
  Future<void> _sort(BuildContext context) async {
    final picked = await showModalBottomSheet3d<String>(
      context: context,
      builder: (context) => BottomSheet3d(
        semanticLabel: 'Sort by',
        child: SceneColumn3d(
          mainAxisSize: MainAxisSize3d.min,
          children: <Widget>[
            for (final by in const <String>['Newest', 'Oldest', 'Sender'])
              ListTile3d.text(
                title: by,
                onTap: () =>
                    Navigator3d.of(SceneOverlay3d.of(context))?.pop(by),
              ),
          ],
        ),
      ),
    );
    if (picked != null && context.mounted) _say(context, 'Sorted by $picked');
  }

  void _say(BuildContext context, String message) {
    ScaffoldMessenger3d.of(context).show(
      SnackBar3d(
        message: message,
        actionLabel: 'Undo',
        onAction: () {},
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// A row of filter chips over a scrolling list of cards.
  ///
  /// The list is where the clip earns its keep: it is taller than the room the
  /// scaffold gave it, and the body's window is what stops a row drawing over
  /// the bar above it. A card in it stays `raised` all the same — the window
  /// cuts the face and leaves the depth alone.
  Widget _inbox(BuildContext context) {
    final theme = Theme3d.of(context);
    return SceneColumn3d(
      crossAxisAlignment: CrossAxisAlignment3d.stretch,
      children: <Widget>[
        // A gradient, because a brand has one and `BoxDecoration3d` now draws
        // one: it is evaluated by the panel shader against the box's own face,
        // so it is exact at this size and would be exact at any other.
        ScenePadding3d(
          padding: _insets(
            context,
            const EdgeInsets3d.symmetric(horizontal: 12, vertical: 8),
          ),
          child: SceneSizedBox3d(
            height: _dp(context, 56),
            depth: _dp(context, theme.thickness.raised),
            child: SceneDecoratedBox3d(
              decoration: BoxDecoration3d(
                borderRadius: const BorderRadius3d.circular(16),
                gradient: LinearGradient(
                  begin: AlignmentDirectional.centerStart,
                  end: AlignmentDirectional.centerEnd,
                  colors: <Color>[
                    theme.colorScheme.primaryContainer,
                    theme.colorScheme.tertiaryContainer,
                  ],
                ),
              ),
              child: SceneAlign3d(
                alignment: Alignment3d.frontCenter,
                child: SceneText3d(
                  '${_messages.length} messages',
                  style: theme.textStyle(
                    Typography3dToken.titleMedium,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
        ),
        ScenePadding3d(
          padding: _insets(context, const EdgeInsets3d.all(8)),
          child: SceneRow3d(
            mainAxisAlignment: MainAxisAlignment3d.spaceEvenly,
            children: <Widget>[
              for (var index = 0; index < _filters.length; index++)
                FilterChip3d(
                  label: SceneText3d(_filters[index]),
                  semanticLabel: _filters[index],
                  selected: _filter == index,
                  onSelected: (_) => setState(() => _filter = index),
                ),
            ],
          ),
        ),
        SceneExpanded3d(
          child: SceneListView3d(
            spacing: _dp(context, 8),
            children: <Widget>[
              for (var index = 0; index < _messages.length; index++)
                ScenePadding3d(
                  key: ValueKey<int>(index),
                  padding: _insets(
                    context,
                    const EdgeInsets3d.symmetric(horizontal: 12),
                  ),
                  child: ElevatedCard3d(
                    onTap: () => _say(context, 'Opened ${_messages[index].$1}'),
                    semanticLabel: _messages[index].$1,
                    child: ListTile3d(
                      // A photograph, cut to a circle by the panel that draws
                      // it. There is no rounded clip in this package — a clip
                      // region is an intersection of planes, and so convex —
                      // so the only thing that can round a picture is the
                      // signed distance field it is sampled inside, which is
                      // why a picture is a decoration here.
                      leading: SceneSizedBox3d(
                        width: _dp(context, 40),
                        height: _dp(context, 40),
                        child: SceneImage3d(
                          image: GalleryAvatar(index),
                          fit: BoxFit.cover,
                          borderRadius: const BorderRadius3d.circular(20),
                        ),
                      ),
                      title: SceneText3d(_messages[index].$1),
                      subtitle: SceneText3d(_messages[index].$2),
                      trailing: Checkbox3d(
                        value: _starred.contains(index),
                        semanticLabel: 'Star',
                        onChanged: (value) => setState(() {
                          if (value) {
                            _starred.add(index);
                          } else {
                            _starred.remove(index);
                          }
                        }),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// The controls, each one a real state that a press actually changes.
  Widget _settings(BuildContext context) {
    return ScenePadding3d(
      padding: _insets(context, const EdgeInsets3d.all(12)),
      child: SceneColumn3d(
        crossAxisAlignment: CrossAxisAlignment3d.stretch,
        mainAxisSize: MainAxisSize3d.min,
        spacing: _dp(context, 8),
        children: <Widget>[
          FilledCard3d(
            child: SceneColumn3d(
              crossAxisAlignment: CrossAxisAlignment3d.stretch,
              // Everything in a card sits on the card's **front face**, and
              // this is the line that puts it there. A flex centres its
              // children on the depth axis by default, in the depth of its
              // deepest child — so a 1dp divider beside a 2dp tile ends up
              // half a millimetre *inside* the card, where the card's own
              // face is drawn in front of it and it simply is not there. See
              // `docs/traps.md`, *Depth ordering*.
              depthAxisAlignment: CrossAxisAlignment3d.start,
              mainAxisSize: MainAxisSize3d.min,
              children: <Widget>[
                ListTile3d(
                  title: const SceneText3d('Notifications'),
                  trailing: Switch3d(
                    value: _notify,
                    semanticLabel: 'Notifications',
                    onChanged: (value) => setState(() => _notify = value),
                  ),
                ),
                const Divider3d(),
                ListTile3d(
                  title: const SceneText3d('Compact rows'),
                  trailing: Switch3d(
                    value: _compact,
                    semanticLabel: 'Compact rows',
                    onChanged: (value) => setState(() => _compact = value),
                  ),
                ),
              ],
            ),
          ),
          OutlinedCard3d(
            child: ScenePadding3d(
              // The four edges and not the six faces. `EdgeInsets3d.all` insets
              // the front as well, and a card's depth is only its thickness,
              // so a front inset of 12dp put the label and the slider 12dp
              // *behind* the card's face, where the face hid them both. See
              // `docs/traps.md`, *A padded box has six faces*.
              padding: _insets(
                context,
                const EdgeInsets3d.symmetric(horizontal: 12, vertical: 12),
              ),
              child: SceneColumn3d(
                crossAxisAlignment: CrossAxisAlignment3d.stretch,
                depthAxisAlignment: CrossAxisAlignment3d.start,
                mainAxisSize: MainAxisSize3d.min,
                spacing: _dp(context, 4),
                children: <Widget>[
                  const SceneText3d('Volume'),
                  SceneAlign3d(
                    alignment: Alignment3d.frontCenter,
                    child: Slider3d(
                      value: _volume,
                      width: 200,
                      semanticLabel: 'Volume',
                      onChanged: (value) => setState(() => _volume = value),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SceneRow3d(
            mainAxisAlignment: MainAxisAlignment3d.spaceEvenly,
            children: <Widget>[
              TextButton3d(
                onPressed: () => setState(() {
                  _notify = true;
                  _compact = false;
                  _volume = 0.65;
                }),
                child: const SceneText3d('Reset'),
              ),
              FilledButton3d(
                onPressed: () => _say(context, 'Saved'),
                child: const SceneText3d('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The same catalogue lying on a table.
///
/// This is the screen that could not exist in a 2D toolkit. The surface it is
/// laid out on uses [LayoutBasis3d.xz], so layout's "down" runs away from the
/// camera and the whole scaffold is flat on the ground — and every elevation
/// on it becomes a **height** you can see from the side, because an elevation
/// here is a distance rather than a painted shadow.
///
/// One of the three cards standing at `level5` while the other two rest at
/// `level1` is therefore not an ornament: it is the claim, drawn. Tap a card,
/// or the floating action button, and the raised one moves. That button stands
/// furthest off the table of anything on the screen, which is what
/// `Scaffold3d`'s depth ordering says it should do.
class TableScreen extends StatefulWidget {
  const TableScreen({super.key});

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  int _lifted = 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme3d.of(context);
    return Scaffold3d(
      // A shorter step than the theme's twelve. The depth vocabulary was
      // designed to keep two slabs out of each other's depth test, not to
      // decide how a screen *looks*, and four steps of it is 48dp — a seventh
      // of a phone's width, and on a table it is 48dp of **height**, which
      // leaves the title bar hanging in the air above the thing it belongs
      // to. Eight still clears the six a `thickness.structural` bar over a
      // `thickness.raised` card needs, and `Scaffold3d` asserts as much.
      depthStep: 8,
      appBar: AppBar3d.text(title: 'On the table', centerTitle: true),
      floatingActionButton: FloatingActionButton3d(
        semanticLabel: 'Lift the next card',
        onPressed: () => setState(() => _lifted = (_lifted + 1) % 3),
        child: const Icon3d(Icons.layers),
      ),
      body: ScenePadding3d(
        padding: _insets(context, const EdgeInsets3d.all(8)),
        child: SceneRow3d(
          crossAxisAlignment: CrossAxisAlignment3d.stretch,
          spacing: _dp(context, 8),
          children: <Widget>[
            for (var index = 0; index < 3; index++)
              SceneExpanded3d(
                child: ElevatedCard3d(
                  semanticLabel: 'Card ${index + 1}',
                  onTap: () => setState(() => _lifted = index),
                  style: CardStyle3d.of(theme, CardVariant3d.elevated).copyWith(
                    elevation: _lifted == index
                        ? theme.elevation.level5
                        : theme.elevation.level1,
                  ),
                  child: SceneAlign3d(
                    alignment: Alignment3d.frontCenter,
                    child: SceneColumn3d(
                      mainAxisSize: MainAxisSize3d.min,
                      depthAxisAlignment: CrossAxisAlignment3d.start,
                      spacing: _dp(context, 6),
                      children: <Widget>[
                        Icon3d(_tableIcons[index]),
                        SceneText3d(_tableLabels[index]),
                        // The elevation, written out. It is the whole point of
                        // this screen: on the ground plane an elevation is a
                        // height, so the lifted card visibly stands off the
                        // table rather than merely being tinted.
                        SceneText3d(
                          _lifted == index ? 'level 5' : 'level 1',
                          style: theme.textStyle(
                            Typography3dToken.labelMedium,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static const List<IconData> _tableIcons = <IconData>[
    Icons.map,
    Icons.local_cafe,
    Icons.calendar_today,
  ];

  static const List<String> _tableLabels = <String>['Route', 'Break', 'Agenda'];
}

/// One sender's avatar, drawn in code rather than loaded from an asset.
///
/// The gallery commits no assets — it is generated with `flutter create` — so
/// its pictures are painted into a `ui.Image` at startup, which is also the
/// honest demonstration: an `ImageProvider` is an `ImageProvider`, and
/// `SceneImage3d` neither knows nor cares where its pixels came from.
class GalleryAvatar extends ImageProvider<GalleryAvatar> {
  const GalleryAvatar(this.seed);

  /// Which of the five avatars this is.
  final int seed;

  static const List<(Color, Color)> _palette = <(Color, Color)>[
    (Color(0xFF6D8CFF), Color(0xFF3C1E7A)),
    (Color(0xFF4FD1C5), Color(0xFF134E4A)),
    (Color(0xFFF6A94A), Color(0xFF7A3B0F)),
    (Color(0xFFE879A6), Color(0xFF6B1440)),
    (Color(0xFF9CE37D), Color(0xFF1F5130)),
  ];

  @override
  Future<GalleryAvatar> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<GalleryAvatar>(this);

  @override
  ImageStreamCompleter loadImage(
    GalleryAvatar key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(_paint());

  Future<ImageInfo> _paint() async {
    const edge = 96.0;
    final (from, to) = _palette[seed % _palette.length];
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const bounds = Rect.fromLTWH(0, 0, edge, edge);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.linear(
          bounds.topLeft,
          bounds.bottomRight,
          <Color>[from, to],
        ),
    );
    canvas.drawCircle(
      const Offset(edge * 0.5, edge * 0.38),
      edge * 0.17,
      Paint()..color = const Color(0x66FFFFFF),
    );
    canvas.drawOval(
      const Rect.fromLTWH(edge * 0.2, edge * 0.6, edge * 0.6, edge * 0.5),
      Paint()..color = const Color(0x66FFFFFF),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(edge.round(), edge.round());
    picture.dispose();
    return ImageInfo(image: image);
  }

  @override
  bool operator ==(Object other) =>
      other is GalleryAvatar && other.seed == seed;

  @override
  int get hashCode => seed;
}

/// A dp figure as world units, read from the surface's unit contract.
///
/// A `build` method reaches the contract through [Layout3dMetricsScope]; a
/// `performLayout` reaches the same thing as `Layout3d.metrics`. Everything
/// Material states is in logical pixels and has to cross that boundary
/// exactly once — never the other way round.
double _dp(BuildContext context, double logicalPixels) =>
    Layout3dMetricsScope.of(context).dp(logicalPixels);

EdgeInsets3d _insets(BuildContext context, EdgeInsets3d insets) =>
    Layout3dMetricsScope.of(context).dpInsets(insets);
