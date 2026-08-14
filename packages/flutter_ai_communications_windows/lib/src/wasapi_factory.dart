import 'wasapi_backend.dart';
import 'wasapi_factory_stub.dart'
    if (dart.library.io) 'wasapi_factory_io.dart'
    as impl;

/// Creates the WASAPI backend for this host.
WasapiBackend createWasapiBackend() => impl.createWasapiBackend();
