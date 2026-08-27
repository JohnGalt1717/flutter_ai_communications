import 'dart:io';

String hostOperatingSystem() => Platform.operatingSystem;

String hostOperatingSystemVersion() => Platform.operatingSystemVersion;

String hostHardwareLabel() {
  if (Platform.isAndroid) {
    return Platform.environment['ANDROID_DEVICE'] ?? 'android';
  }
  if (Platform.isIOS) {
    return Platform.environment['SIMULATOR_DEVICE_NAME'] ?? 'ios';
  }
  return Platform.localHostname;
}

String hostGitCommit() {
  try {
    final result = Process.runSync('git', ['rev-parse', 'HEAD']);
    if (result.exitCode == 0) {
      final commit = (result.stdout as String).trim();
      if (commit.isNotEmpty) {
        return commit;
      }
    }
  } on Object {
    // Host Process is unavailable on some device runners.
  }
  const defined = String.fromEnvironment('GIT_COMMIT');
  return defined.isEmpty ? 'unknown' : defined;
}

Future<void> hostWriteReceiptFile(String name, String encoded) async {
  final dir = Directory(
    '${Directory.systemTemp.path}/flutter_ai_communications_receipts',
  );
  await dir.create(recursive: true);
  await File('${dir.path}/$name').writeAsString(encoded);
}
