import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

import 'audio_backend.dart';
import 'pulse_ffi.dart';
import 'route_class.dart';

const _sampleRate = 24000;
const _silenceBytes = 480;
const _frameBytes = 480;

/// Pulse / PipeWire-Pulse capture and render.
final class PulseAudioBackend implements AudioBackend {
  /// Opens `libpulse` and `libpulse-simple`.
  PulseAudioBackend()
    : _simple = PulseSimple(DynamicLibrary.open('libpulse-simple.so.0')),
      _async = PulseAsync(DynamicLibrary.open('libpulse.so.0'));

  final PulseSimple _simple;
  final PulseAsync _async;

  Pointer<PaSimple> _render = nullptr;
  Isolate? _captureIsolate;
  ReceivePort? _capturePort;
  SendPort? _captureControl;
  var _running = false;
  var _paused = false;
  var _captureGeneration = 0;
  String? _captureId;
  String? _renderId;

  final StreamController<Uint8List> _captureOut =
      StreamController<Uint8List>.broadcast();

  @override
  Stream<Uint8List> get capture => _captureOut.stream;

  @override
  List<Endpoint> enumerate() => _enumerateSync();

  @override
  MicrophonePermission probePermission() {
    try {
      final started = start();
      stop();
      return started == NativeGraphStart.started
          ? MicrophonePermission.granted
          : MicrophonePermission.denied;
    } on Object {
      return MicrophonePermission.denied;
    }
  }

  @override
  NativeGraphStart start({String? captureId, String? renderId}) {
    _captureId = captureId;
    _renderId = renderId;
    return _startGraph() ? NativeGraphStart.started : NativeGraphStart.failed;
  }

  @override
  void stop() {
    _running = false;
    _stopGraph();
  }

  @override
  void pause() {
    _paused = true;
    _captureControl?.send(const _PauseCommand());
  }

  @override
  void resume() {
    _paused = false;
    _captureControl?.send(const _ResumeCommand());
  }

  @override
  void play(Uint8List bytes) {
    if (!_running || _paused || _render == nullptr || bytes.isEmpty) {
      return;
    }
    final error = calloc<Int32>();
    final data = calloc<Uint8>(bytes.length);
    try {
      data.asTypedList(bytes.length).setAll(0, bytes);
      _simple.write(_render, data.cast(), bytes.length, error);
    } finally {
      calloc.free(data);
      calloc.free(error);
    }
  }

  @override
  void select({String? captureId, String? renderId}) {
    if (captureId != null) {
      _captureId = captureId;
    }
    if (renderId != null) {
      _renderId = renderId;
    }
    if (_running) {
      _startGraph();
    }
  }

  @override
  PairingSnapshot get observed => PairingSnapshot(
    captureId: _wantCapture ? _presentId(_captureId) ?? _captureId : null,
    renderId: _wantRender ? _presentId(_renderId) ?? _renderId : null,
  );

  @override
  void flush() {
    if (_render == nullptr) {
      return;
    }
    final error = calloc<Int32>();
    try {
      _simple.flush(_render, error);
    } finally {
      calloc.free(error);
    }
  }

  @override
  void dispose() {
    stop();
    unawaited(_captureOut.close());
  }

  String? _presentId(String? id) => id == null || id.isEmpty ? null : id;

  bool get _wantCapture =>
      _presentId(_captureId) != null || _presentId(_renderId) == null;

  bool get _wantRender =>
      _presentId(_renderId) != null || _presentId(_captureId) == null;

  bool _startGraph() {
    if (_wantCapture) {
      _emitSilence();
    }
    _stopGraph();
    final spec = calloc<PaSampleSpec>();
    try {
      spec.ref
        ..format = paSampleS16le
        ..rate = _sampleRate
        ..channels = 1;
      if (_wantRender) {
        final render = _simple.open(
          direction: paStreamPlayback,
          device: _renderId,
          spec: spec,
        );
        if (render == nullptr) {
          return false;
        }
        _render = render;
      }
      _running = true;
      if (_wantCapture) {
        _startCaptureIsolate();
      }
      return true;
    } finally {
      calloc.free(spec);
    }
  }

  void _stopGraph() {
    _captureGeneration++;
    _running = false;
    final isolate = _captureIsolate;
    final port = _capturePort;
    final control = _captureControl;
    _captureIsolate = null;
    _capturePort = null;
    _captureControl = null;
    control?.send(const _StopCommand());
    isolate?.kill(priority: Isolate.immediate);
    port?.close();
    if (_render != nullptr) {
      _simple.freeStream(_render);
      _render = nullptr;
    }
  }

  void _startCaptureIsolate() {
    final generation = ++_captureGeneration;
    final port = ReceivePort();
    _capturePort = port;
    port.listen((message) {
      if (generation != _captureGeneration) {
        return;
      }
      if (message is SendPort) {
        _captureControl = message;
        if (_paused) {
          message.send(const _PauseCommand());
        }
        return;
      }
      if (message is Uint8List && _running && !_paused) {
        _captureOut.add(message);
      }
    });
    Isolate.spawn(
      _captureMain,
      _CaptureStart(sendPort: port.sendPort, device: _captureId),
    ).then((isolate) {
      if (generation != _captureGeneration || !_running) {
        isolate.kill(priority: Isolate.immediate);
        return;
      }
      _captureIsolate = isolate;
    });
  }

  void _emitSilence() {
    _captureOut.add(Uint8List(_silenceBytes));
  }

  List<Endpoint> _enumerateSync() {
    final items = <Endpoint>[];
    final loop = _async.mainloopNew();
    if (loop == nullptr) {
      return items;
    }
    final api = _async.mainloopGetApi(loop);
    final name = 'flutter_ai_communications'.toNativeUtf8();
    final context = _async.contextNew(api, name.cast());
    malloc.free(name);
    if (context == nullptr) {
      _async.mainloopFree(loop);
      return items;
    }
    if (_async.contextConnect(context, nullptr, 0, nullptr) < 0) {
      _async.contextUnref(context);
      _async.mainloopFree(loop);
      return items;
    }
    if (!_waitReady(loop, context)) {
      _async.contextDisconnect(context);
      _async.contextUnref(context);
      _async.mainloopFree(loop);
      return items;
    }

    items.addAll(_collect(loop, context, sources: true));
    items.addAll(_collect(loop, context, sources: false));

    _async.contextDisconnect(context);
    _async.contextUnref(context);
    _async.mainloopFree(loop);
    return items;
  }

  bool _waitReady(Pointer<PaMainloop> loop, Pointer<PaContext> context) {
    for (var i = 0; i < 2000; i++) {
      final state = _async.contextGetState(context);
      if (state == paContextReady) {
        return true;
      }
      if (state == paContextFailed || state == paContextTerminated) {
        return false;
      }
      _async.mainloopIterate(loop, 1, nullptr);
    }
    return false;
  }

  List<Endpoint> _collect(
    Pointer<PaMainloop> loop,
    Pointer<PaContext> context, {
    required bool sources,
  }) {
    final collected = <Endpoint>[];
    late final NativeCallable<
      Void Function(
        Pointer<PaContext>,
        Pointer<PaNamedDevice>,
        Int32,
        Pointer<Void>,
      )
    >
    callable;
    callable =
        NativeCallable<
          Void Function(
            Pointer<PaContext>,
            Pointer<PaNamedDevice>,
            Int32,
            Pointer<Void>,
          )
        >.isolateLocal((
          Pointer<PaContext> _,
          Pointer<PaNamedDevice> info,
          int eol,
          Pointer<Void> userdata,
        ) {
          if (eol != 0 || info == nullptr) {
            return;
          }
          final id = pulseString(info.ref.name) ?? '';
          if (id.isEmpty) {
            return;
          }
          if (sources &&
              (id.startsWith('auto_null.') || id.contains('.monitor'))) {
            return;
          }
          final name = pulseString(info.ref.description) ?? id;
          var bus = '';
          var formFactor = '';
          var card = 0xffffffff;
          try {
            final props = pulseProplist(info);
            bus =
                _async.proplistGets(props, 'device.bus') ??
                _async.proplistGets(props, 'device.api') ??
                '';
            formFactor = _async.proplistGets(props, 'device.form_factor') ?? '';
            card = pulseCard(info);
          } on Object {
            // Pulse layout drift must not drop the Endpoint.
          }
          collected.add(
            linuxEndpointFromPulse(
              id: id,
              name: name,
              isCapture: sources,
              bus: bus,
              formFactor: formFactor,
              card: card,
            ),
          );
        });
    final op = sources
        ? _async.getSourceInfoList(context, callable.nativeFunction, nullptr)
        : _async.getSinkInfoList(context, callable.nativeFunction, nullptr);
    if (op == nullptr) {
      callable.close();
      return collected;
    }
    for (var i = 0; i < 200; i++) {
      if (_async.operationGetState(op) == paOperationDone) {
        break;
      }
      _async.mainloopIterate(loop, 1, nullptr);
    }
    _async.operationUnref(op);
    callable.close();
    return collected;
  }
}

final class _CaptureStart {
  const _CaptureStart({required this.sendPort, this.device});

  final SendPort sendPort;
  final String? device;
}

sealed class _CaptureCommand {
  const _CaptureCommand();
}

final class _StopCommand extends _CaptureCommand {
  const _StopCommand();
}

final class _PauseCommand extends _CaptureCommand {
  const _PauseCommand();
}

final class _ResumeCommand extends _CaptureCommand {
  const _ResumeCommand();
}

void _captureMain(_CaptureStart start) {
  final control = ReceivePort();
  start.sendPort.send(control.sendPort);
  final simple = PulseSimple(DynamicLibrary.open('libpulse-simple.so.0'));
  final spec = calloc<PaSampleSpec>();
  spec.ref
    ..format = paSampleS16le
    ..rate = _sampleRate
    ..channels = 1;
  final stream = simple.open(
    direction: paStreamRecord,
    device: start.device,
    spec: spec,
  );
  calloc.free(spec);
  if (stream == nullptr) {
    control.close();
    return;
  }
  var running = true;
  var paused = false;
  control.listen((message) {
    switch (message) {
      case _StopCommand():
        running = false;
      case _PauseCommand():
        paused = true;
      case _ResumeCommand():
        paused = false;
    }
  });
  final error = calloc<Int32>();
  final buffer = calloc<Uint8>(_frameBytes);
  try {
    while (running) {
      if (paused) {
        sleep(const Duration(milliseconds: 10));
        continue;
      }
      final status = simple.read(stream, buffer.cast(), _frameBytes, error);
      if (status < 0) {
        break;
      }
      start.sendPort.send(Uint8List.fromList(buffer.asTypedList(_frameBytes)));
    }
  } finally {
    simple.freeStream(stream);
    calloc.free(buffer);
    calloc.free(error);
    control.close();
  }
}
