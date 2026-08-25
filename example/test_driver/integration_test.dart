import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Host-side driver. Writes suite receipts and logs under
/// `/tmp/flutter_ai_communications_receipts/` so web-server Chrome
/// console is not the only place they exist.
Future<void> main() async {
  await integrationDriver(
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      await writeResponseData(data);
      final dir = Directory(
        Platform.isWindows
            ? '${Directory.systemTemp.path}${Platform.pathSeparator}flutter_ai_communications_receipts'
            : '/tmp/flutter_ai_communications_receipts',
      );
      await dir.create(recursive: true);
      if (data == null) {
        return;
      }
      final logs = data['logs'];
      if (logs is List) {
        final file = File('${dir.path}/suite.log');
        await file.writeAsString(logs.map((e) => '$e').join('\n'));
        stdout.writeln('SUITE_LOG ${file.path}');
      }
      final receipts = data['receipts'];
      if (receipts is List) {
        for (final receipt in receipts) {
          if (receipt is! Map) {
            continue;
          }
          final encoded = const JsonEncoder.withIndent('  ').convert(receipt);
          final commit = '${receipt['commit'] ?? 'unknown'}';
          final platform = '${receipt['platform'] ?? 'unknown'}';
          final hardware = _safe('${receipt['hardware'] ?? 'device'}');
          final name = '$commit-$platform-$hardware.json';
          await File('${dir.path}/$name').writeAsString('$encoded\n');
          stdout.writeln('NATIVE_MARIONETTE_RECEIPT $encoded');
        }
      }
    },
  );
}

String _safe(String value) =>
    value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
