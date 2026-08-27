/// Web/stub host helpers for the native Orchestration suite.
String hostOperatingSystem() => 'web';

String hostOperatingSystemVersion() => 'web';

String hostHardwareLabel() => 'chrome';

String hostGitCommit() {
  const defined = String.fromEnvironment('GIT_COMMIT');
  return defined.isEmpty ? 'unknown' : defined;
}

Future<void> hostWriteReceiptFile(String name, String encoded) async {}
