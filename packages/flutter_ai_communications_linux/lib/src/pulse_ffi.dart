import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// PCM16 LE.
const paSampleS16le = 3;

/// Playback stream.
const paStreamPlayback = 1;

/// Capture stream.
const paStreamRecord = 2;

/// Context is ready.
const paContextReady = 4;

/// Context failed.
const paContextFailed = 5;

/// Context terminated.
const paContextTerminated = 6;

/// Operation done.
const paOperationDone = 2;

/// Pulse sample spec used by `pa_simple_new`.
final class PaSampleSpec extends Struct {
  @Int()
  external int format;

  @Uint32()
  external int rate;

  @Uint8()
  external int channels;
}

/// Prefix of `pa_source_info` / `pa_sink_info` — name, index, description.
final class PaNamedDevice extends Struct {
  external Pointer<Char> name;

  @Uint32()
  external int index;

  external Pointer<Char> description;
}

/// Opaque Pulse objects.
final class PaSimple extends Opaque {}

/// Opaque Pulse mainloop.
final class PaMainloop extends Opaque {}

/// Opaque Pulse mainloop API.
final class PaMainloopApi extends Opaque {}

/// Opaque Pulse context.
final class PaContext extends Opaque {}

/// Opaque Pulse operation.
final class PaOperation extends Opaque {}

/// Opaque Pulse property list.
final class PaProplist extends Opaque {}

/// `offsetof(pa_source_info, proplist)` / `pa_sink_info`. Same layout.
const pulseProplistOffset = 344;

/// `offsetof(pa_source_info, card)` / `pa_sink_info`.
const pulseCardOffset = 372;

/// Reads `proplist` from a `pa_source_info` / `pa_sink_info` pointer.
Pointer<PaProplist> pulseProplist(Pointer<PaNamedDevice> info) {
  return Pointer<Pointer<PaProplist>>.fromAddress(
    info.address + pulseProplistOffset,
  ).value;
}

/// Reads `card` from a `pa_source_info` / `pa_sink_info` pointer.
int pulseCard(Pointer<PaNamedDevice> info) {
  return Pointer<Uint32>.fromAddress(info.address + pulseCardOffset).value;
}

/// libpulse-simple bindings.
final class PulseSimple {
  /// Opens `libpulse-simple.so.0`.
  PulseSimple(DynamicLibrary lib)
    : _new = lib
          .lookupFunction<
            Pointer<PaSimple> Function(
              Pointer<Char>,
              Pointer<Char>,
              Int32,
              Pointer<Char>,
              Pointer<Char>,
              Pointer<PaSampleSpec>,
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Int32>,
            ),
            Pointer<PaSimple> Function(
              Pointer<Char>,
              Pointer<Char>,
              int,
              Pointer<Char>,
              Pointer<Char>,
              Pointer<PaSampleSpec>,
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Int32>,
            )
          >('pa_simple_new'),
      _free = lib
          .lookupFunction<
            Void Function(Pointer<PaSimple>),
            void Function(Pointer<PaSimple>)
          >('pa_simple_free'),
      _read = lib
          .lookupFunction<
            Int32 Function(
              Pointer<PaSimple>,
              Pointer<Void>,
              Size,
              Pointer<Int32>,
            ),
            int Function(Pointer<PaSimple>, Pointer<Void>, int, Pointer<Int32>)
          >('pa_simple_read'),
      _write = lib
          .lookupFunction<
            Int32 Function(
              Pointer<PaSimple>,
              Pointer<Void>,
              Size,
              Pointer<Int32>,
            ),
            int Function(Pointer<PaSimple>, Pointer<Void>, int, Pointer<Int32>)
          >('pa_simple_write'),
      _flush = lib
          .lookupFunction<
            Int32 Function(Pointer<PaSimple>, Pointer<Int32>),
            int Function(Pointer<PaSimple>, Pointer<Int32>)
          >('pa_simple_flush');

  final Pointer<PaSimple> Function(
    Pointer<Char>,
    Pointer<Char>,
    int,
    Pointer<Char>,
    Pointer<Char>,
    Pointer<PaSampleSpec>,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Int32>,
  )
  _new;
  final void Function(Pointer<PaSimple>) _free;
  final int Function(Pointer<PaSimple>, Pointer<Void>, int, Pointer<Int32>)
  _read;
  final int Function(Pointer<PaSimple>, Pointer<Void>, int, Pointer<Int32>)
  _write;
  final int Function(Pointer<PaSimple>, Pointer<Int32>) _flush;

  /// Opens a simple stream.
  Pointer<PaSimple> open({
    required int direction,
    String? device,
    required Pointer<PaSampleSpec> spec,
  }) {
    final name = 'flutter_ai_communications'.toNativeUtf8();
    final stream = (direction == paStreamRecord ? 'capture' : 'render')
        .toNativeUtf8();
    final devicePtr = device?.toNativeUtf8();
    final error = calloc<Int32>();
    try {
      return _new(
        nullptr,
        name.cast(),
        direction,
        devicePtr?.cast() ?? nullptr,
        stream.cast(),
        spec,
        nullptr,
        nullptr,
        error,
      );
    } finally {
      malloc.free(name);
      malloc.free(stream);
      if (devicePtr != null) {
        malloc.free(devicePtr);
      }
      calloc.free(error);
    }
  }

  /// Closes [stream].
  void freeStream(Pointer<PaSimple> stream) => _free(stream);

  /// Blocking capture.
  int read(
    Pointer<PaSimple> stream,
    Pointer<Void> data,
    int bytes,
    Pointer<Int32> error,
  ) => _read(stream, data, bytes, error);

  /// Blocking playback.
  int write(
    Pointer<PaSimple> stream,
    Pointer<Void> data,
    int bytes,
    Pointer<Int32> error,
  ) => _write(stream, data, bytes, error);

  /// Drops queued playback.
  int flush(Pointer<PaSimple> stream, Pointer<Int32> error) =>
      _flush(stream, error);
}

/// libpulse catalog bindings.
final class PulseAsync {
  /// Opens `libpulse.so.0`.
  PulseAsync(DynamicLibrary lib)
    : mainloopNew = lib
          .lookupFunction<
            Pointer<PaMainloop> Function(),
            Pointer<PaMainloop> Function()
          >('pa_mainloop_new'),
      mainloopGetApi = lib
          .lookupFunction<
            Pointer<PaMainloopApi> Function(Pointer<PaMainloop>),
            Pointer<PaMainloopApi> Function(Pointer<PaMainloop>)
          >('pa_mainloop_get_api'),
      mainloopIterate = lib
          .lookupFunction<
            Int32 Function(Pointer<PaMainloop>, Int32, Pointer<Int32>),
            int Function(Pointer<PaMainloop>, int, Pointer<Int32>)
          >('pa_mainloop_iterate'),
      mainloopFree = lib
          .lookupFunction<
            Void Function(Pointer<PaMainloop>),
            void Function(Pointer<PaMainloop>)
          >('pa_mainloop_free'),
      contextNew = lib
          .lookupFunction<
            Pointer<PaContext> Function(Pointer<PaMainloopApi>, Pointer<Char>),
            Pointer<PaContext> Function(Pointer<PaMainloopApi>, Pointer<Char>)
          >('pa_context_new'),
      contextConnect = lib
          .lookupFunction<
            Int32 Function(
              Pointer<PaContext>,
              Pointer<Char>,
              Int32,
              Pointer<Void>,
            ),
            int Function(Pointer<PaContext>, Pointer<Char>, int, Pointer<Void>)
          >('pa_context_connect'),
      contextGetState = lib
          .lookupFunction<
            Int32 Function(Pointer<PaContext>),
            int Function(Pointer<PaContext>)
          >('pa_context_get_state'),
      contextDisconnect = lib
          .lookupFunction<
            Void Function(Pointer<PaContext>),
            void Function(Pointer<PaContext>)
          >('pa_context_disconnect'),
      contextUnref = lib
          .lookupFunction<
            Void Function(Pointer<PaContext>),
            void Function(Pointer<PaContext>)
          >('pa_context_unref'),
      getSourceInfoList = lib
          .lookupFunction<
            Pointer<PaOperation> Function(
              Pointer<PaContext>,
              Pointer<
                NativeFunction<
                  Void Function(
                    Pointer<PaContext>,
                    Pointer<PaNamedDevice>,
                    Int32,
                    Pointer<Void>,
                  )
                >
              >,
              Pointer<Void>,
            ),
            Pointer<PaOperation> Function(
              Pointer<PaContext>,
              Pointer<
                NativeFunction<
                  Void Function(
                    Pointer<PaContext>,
                    Pointer<PaNamedDevice>,
                    Int32,
                    Pointer<Void>,
                  )
                >
              >,
              Pointer<Void>,
            )
          >('pa_context_get_source_info_list'),
      getSinkInfoList = lib
          .lookupFunction<
            Pointer<PaOperation> Function(
              Pointer<PaContext>,
              Pointer<
                NativeFunction<
                  Void Function(
                    Pointer<PaContext>,
                    Pointer<PaNamedDevice>,
                    Int32,
                    Pointer<Void>,
                  )
                >
              >,
              Pointer<Void>,
            ),
            Pointer<PaOperation> Function(
              Pointer<PaContext>,
              Pointer<
                NativeFunction<
                  Void Function(
                    Pointer<PaContext>,
                    Pointer<PaNamedDevice>,
                    Int32,
                    Pointer<Void>,
                  )
                >
              >,
              Pointer<Void>,
            )
          >('pa_context_get_sink_info_list'),
      operationGetState = lib
          .lookupFunction<
            Int32 Function(Pointer<PaOperation>),
            int Function(Pointer<PaOperation>)
          >('pa_operation_get_state'),
      operationUnref = lib
          .lookupFunction<
            Void Function(Pointer<PaOperation>),
            void Function(Pointer<PaOperation>)
          >('pa_operation_unref'),
      _proplistGets = lib
          .lookupFunction<
            Pointer<Char> Function(Pointer<PaProplist>, Pointer<Char>),
            Pointer<Char> Function(Pointer<PaProplist>, Pointer<Char>)
          >('pa_proplist_gets');

  /// Creates a mainloop.
  final Pointer<PaMainloop> Function() mainloopNew;

  /// Mainloop API for a context.
  final Pointer<PaMainloopApi> Function(Pointer<PaMainloop>) mainloopGetApi;

  /// Iterates the mainloop.
  final int Function(Pointer<PaMainloop>, int, Pointer<Int32>) mainloopIterate;

  /// Frees a mainloop.
  final void Function(Pointer<PaMainloop>) mainloopFree;

  /// Creates a context.
  final Pointer<PaContext> Function(Pointer<PaMainloopApi>, Pointer<Char>)
  contextNew;

  /// Connects a context.
  final int Function(Pointer<PaContext>, Pointer<Char>, int, Pointer<Void>)
  contextConnect;

  /// Context state.
  final int Function(Pointer<PaContext>) contextGetState;

  /// Disconnects a context.
  final void Function(Pointer<PaContext>) contextDisconnect;

  /// Releases a context.
  final void Function(Pointer<PaContext>) contextUnref;

  /// Lists sources.
  final Pointer<PaOperation> Function(
    Pointer<PaContext>,
    Pointer<
      NativeFunction<
        Void Function(
          Pointer<PaContext>,
          Pointer<PaNamedDevice>,
          Int32,
          Pointer<Void>,
        )
      >
    >,
    Pointer<Void>,
  )
  getSourceInfoList;

  /// Lists sinks.
  final Pointer<PaOperation> Function(
    Pointer<PaContext>,
    Pointer<
      NativeFunction<
        Void Function(
          Pointer<PaContext>,
          Pointer<PaNamedDevice>,
          Int32,
          Pointer<Void>,
        )
      >
    >,
    Pointer<Void>,
  )
  getSinkInfoList;

  /// Operation state.
  final int Function(Pointer<PaOperation>) operationGetState;

  /// Releases an operation.
  final void Function(Pointer<PaOperation>) operationUnref;

  final Pointer<Char> Function(Pointer<PaProplist>, Pointer<Char>)
  _proplistGets;

  /// Reads a string property, or null when missing.
  String? proplistGets(Pointer<PaProplist> list, String key) {
    if (list == nullptr) {
      return null;
    }
    final keyPtr = key.toNativeUtf8();
    try {
      return pulseString(_proplistGets(list, keyPtr.cast()));
    } finally {
      malloc.free(keyPtr);
    }
  }
}

/// UTF-8 helper for Pulse `char*`.
String? pulseString(Pointer<Char> pointer) {
  if (pointer == nullptr) {
    return null;
  }
  return pointer.cast<Utf8>().toDartString();
}
