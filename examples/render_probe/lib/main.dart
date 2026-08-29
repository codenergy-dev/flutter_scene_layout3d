import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' show Scene;

import 'probe_scene.dart';
import 'probe_scenes.dart';

/// A host for looking at the probe scenes by hand.
///
/// The render test pumps [ProbeSceneView] directly and never runs this; it is
/// here because a probe that fails is much easier to understand when you can
/// see what it drew.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Scene.initializeStaticResources();
  runApp(const ProbeApp());
}

class ProbeApp extends StatefulWidget {
  const ProbeApp({super.key});

  @override
  State<ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<ProbeApp> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final probe = kProbeScenes[index];
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: kProbeClear,
        appBar: AppBar(title: Text(probe.id)),
        body: ProbeSceneView(probe, key: ValueKey(probe.id)),
        floatingActionButton: FloatingActionButton(
          onPressed: () => setState(() {
            index = (index + 1) % kProbeScenes.length;
          }),
          child: const Icon(Icons.skip_next),
        ),
      ),
    );
  }
}
