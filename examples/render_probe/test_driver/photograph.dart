import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Writes each photograph the test hands back to `build/photographs/`.
///
/// On the host, and that is the point: the application runs in the macOS app
/// sandbox, where a file written to its own temporary directory lands in a
/// container nobody looks in.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final file = File('build/photographs/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    stdout.writeln('photographed ${file.absolute.path}');
    return true;
  },
);
