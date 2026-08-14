import 'wasapi_backend.dart';
import 'wasapi_unavailable.dart';

/// Fallback when `dart:io` is unavailable.
WasapiBackend createWasapiBackend() => const UnavailableWasapiBackend();
