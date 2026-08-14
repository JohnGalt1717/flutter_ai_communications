import 'dart:io';

import 'wasapi_backend.dart';
import 'wasapi_unavailable.dart';
import 'wasapi_windows.dart';

/// Windows hosts get WASAPI; other `dart:io` hosts stay unavailable.
WasapiBackend createWasapiBackend() {
  if (Platform.isWindows) {
    return WasapiWindowsBackend();
  }
  return const UnavailableWasapiBackend();
}
