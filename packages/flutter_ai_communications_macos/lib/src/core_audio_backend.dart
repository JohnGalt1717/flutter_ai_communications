import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

import 'audio_backend.dart';
import 'core_audio_ffi.dart';
import 'route_class.dart';

const _silenceBytes = 480;
const _bufferBytes = 480;
const _bufferCount = 3;

/// Core Audio AudioQueue capture and render.
final class CoreAudioBackend implements AudioBackend {
  /// Opens Core Audio in-process.
  CoreAudioBackend() : _audio = CoreAudio();

  final CoreAudio _audio;
  AudioQueueRef _capture = nullptr;
  AudioQueueRef _render = nullptr;
  NativeCallable<AudioQueueInputNative>? _inputCallable;
  NativeCallable<AudioQueueOutputNative>? _outputCallable;
  final List<Uint8List> _playback = [];
  var _running = false;
  var _paused = false;
  String? _captureId;
  String? _renderId;

  final StreamController<Uint8List> _captureOut =
      StreamController<Uint8List>.broadcast();

  @override
  Stream<Uint8List> get capture => _captureOut.stream;

  @override
  List<Endpoint> enumerate() => [
    ..._collect(capture: true),
    ..._collect(capture: false),
  ];

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
    if (_capture != nullptr) {
      _audio.queuePause(_capture);
    }
    if (_render != nullptr) {
      _audio.queuePause(_render);
    }
  }

  @override
  void resume() {
    _paused = false;
    if (_capture != nullptr) {
      _audio.queueStart(_capture, nullptr);
    }
    if (_render != nullptr) {
      _audio.queueStart(_render, nullptr);
    }
  }

  @override
  void play(Uint8List bytes) {
    if (!_running || _paused || bytes.isEmpty) {
      return;
    }
    _playback.add(Uint8List.fromList(bytes));
  }

  @override
  void select({String? captureId, String? renderId}) {
    if (captureId != null) {
      _captureId = captureId;
    }
    if (renderId != null) {
      _renderId = renderId;
    }
    if (!_running) {
      return;
    }
    _emitSilence();
    if (_capture != nullptr) {
      _bindDevice(_capture, _captureId, capture: true);
    }
    if (_render != nullptr) {
      _bindDevice(_render, _renderId, capture: false);
    }
  }

  @override
  void flush() {
    _playback.clear();
    if (_render != nullptr) {
      _audio.queueFlush(_render);
      _audio.queueReset(_render);
    }
  }

  @override
  void dispose() {
    stop();
    unawaited(_captureOut.close());
  }

  bool _startGraph() {
    _emitSilence();
    final keepPaused = _paused;
    _stopGraph();
    final format = calloc<AudioStreamBasicDescription>();
    _audio.writePcm16(format);
    try {
      if (!_openCapture(format) || !_openRender(format)) {
        _stopGraph();
        return false;
      }
      _running = true;
      _paused = keepPaused;
      if (!keepPaused) {
        _audio.queueStart(_capture, nullptr);
        _audio.queueStart(_render, nullptr);
      }
      return true;
    } finally {
      calloc.free(format);
    }
  }

  void _stopGraph() {
    _running = false;
    final capture = _capture;
    final render = _render;
    _capture = nullptr;
    _render = nullptr;
    if (capture != nullptr) {
      _audio.queueStop(capture, 1);
      _audio.queueDispose(capture, 1);
    }
    if (render != nullptr) {
      _audio.queueStop(render, 1);
      _audio.queueDispose(render, 1);
    }
    _inputCallable?.close();
    _outputCallable?.close();
    _inputCallable = null;
    _outputCallable = null;
    _playback.clear();
  }

  bool _openCapture(Pointer<AudioStreamBasicDescription> format) {
    final callable = NativeCallable<AudioQueueInputNative>.isolateLocal(
      _onInput,
    );
    _inputCallable = callable;
    final queue = calloc<AudioQueueRef>();
    final status = _audio.queueNewInput(
      format,
      callable.nativeFunction,
      nullptr,
      _audio.runLoopMain(),
      _audio.commonModes,
      0,
      queue,
    );
    if (status != noErr) {
      calloc.free(queue);
      return false;
    }
    _capture = queue.value;
    calloc.free(queue);
    _bindDevice(_capture, _captureId, capture: true);
    return _prime(_capture, fillSilence: false);
  }

  bool _openRender(Pointer<AudioStreamBasicDescription> format) {
    final callable = NativeCallable<AudioQueueOutputNative>.isolateLocal(
      _onOutput,
    );
    _outputCallable = callable;
    final queue = calloc<AudioQueueRef>();
    final status = _audio.queueNewOutput(
      format,
      callable.nativeFunction,
      nullptr,
      _audio.runLoopMain(),
      _audio.commonModes,
      0,
      queue,
    );
    if (status != noErr) {
      calloc.free(queue);
      return false;
    }
    _render = queue.value;
    calloc.free(queue);
    _bindDevice(_render, _renderId, capture: false);
    return _prime(_render, fillSilence: true);
  }

  bool _prime(AudioQueueRef queue, {required bool fillSilence}) {
    for (var i = 0; i < _bufferCount; i++) {
      final buffer = calloc<AudioQueueBufferRef>();
      final status = _audio.queueAllocateBuffer(queue, _bufferBytes, buffer);
      if (status != noErr) {
        calloc.free(buffer);
        return false;
      }
      final ref = buffer.value;
      calloc.free(buffer);
      ref.ref.audioDataByteSize = _bufferBytes;
      if (fillSilence) {
        ref.ref.audioData
            .cast<Uint8>()
            .asTypedList(_bufferBytes)
            .fillRange(0, _bufferBytes, 0);
      }
      if (_audio.queueEnqueueBuffer(queue, ref, 0, nullptr) != noErr) {
        return false;
      }
    }
    return true;
  }

  void _bindDevice(AudioQueueRef queue, String? id, {required bool capture}) {
    final uid = id ?? _defaultUid(capture: capture);
    if (uid == null || uid.isEmpty) {
      return;
    }
    final cf = _cfString(uid);
    if (cf == nullptr) {
      return;
    }
    final value = calloc<Pointer<Void>>()..value = cf;
    _audio.queueSetProperty(
      queue,
      fourCC('aqcd'),
      value.cast(),
      sizeOf<Pointer>(),
    );
    calloc.free(value);
    _cfRelease(cf);
  }

  void _onInput(
    Pointer<Void> _,
    AudioQueueRef queue,
    AudioQueueBufferRef buffer,
    Pointer<Void> __,
    int ___,
    Pointer<Void> ____,
  ) {
    if (!_running || _paused) {
      if (queue != nullptr && buffer != nullptr) {
        _audio.queueEnqueueBuffer(queue, buffer, 0, nullptr);
      }
      return;
    }
    final size = buffer.ref.audioDataByteSize;
    if (size > 0 && buffer.ref.audioData != nullptr) {
      _captureOut.add(
        Uint8List.fromList(
          buffer.ref.audioData.cast<Uint8>().asTypedList(size),
        ),
      );
    }
    _audio.queueEnqueueBuffer(queue, buffer, 0, nullptr);
  }

  void _onOutput(
    Pointer<Void> _,
    AudioQueueRef queue,
    AudioQueueBufferRef buffer,
  ) {
    final dest = buffer.ref.audioData.cast<Uint8>().asTypedList(_bufferBytes);
    dest.fillRange(0, _bufferBytes, 0);
    if (_running && !_paused && _playback.isNotEmpty) {
      final next = _playback.removeAt(0);
      final count = next.length < _bufferBytes ? next.length : _bufferBytes;
      dest.setRange(0, count, next);
    }
    buffer.ref.audioDataByteSize = _bufferBytes;
    if (queue != nullptr) {
      _audio.queueEnqueueBuffer(queue, buffer, 0, nullptr);
    }
  }

  void _emitSilence() {
    _captureOut.add(Uint8List(_silenceBytes));
  }

  List<Endpoint> _collect({required bool capture}) {
    final scope = capture ? fourCC('inpt') : fourCC('outp');
    final items = <Endpoint>[];
    for (final id in _audio.uint32Array(
      audioObjectSystemObject,
      fourCC('dev#'),
    )) {
      if (_audio.uint32Array(id, fourCC('stm#'), scope: scope).isEmpty) {
        continue;
      }
      final name =
          _audio.stringProperty(id, fourCC('lnam')) ??
          _audio.stringProperty(id, fourCC('lmak')) ??
          id.toString();
      final uid = _audio.stringProperty(id, fourCC('uid ')) ?? id.toString();
      final transportCode = _audio.uint32Property(id, fourCC('tran'));
      final transport = transportCode == null
          ? ''
          : String.fromCharCodes([
              (transportCode >> 24) & 0xff,
              (transportCode >> 16) & 0xff,
              (transportCode >> 8) & 0xff,
              transportCode & 0xff,
            ]);
      final route = macosRouteClass(name: name, transport: transport);
      items.add(
        Endpoint(
          id: uid,
          name: name,
          routeClass: route,
          isCapture: capture,
          pairId: macosPairId(routeClass: route, id: uid, name: name, uid: uid),
        ),
      );
    }
    return items;
  }

  String? _defaultUid({required bool capture}) {
    final defaultId = _audio.uint32Property(
      audioObjectSystemObject,
      capture ? fourCC('dIn ') : fourCC('dOut'),
    );
    if (defaultId != null) {
      return _audio.stringProperty(defaultId, fourCC('uid '));
    }
    final first = _collect(capture: capture).firstOrNull;
    return first?.id;
  }

  Pointer<Void> _cfString(String value) {
    final lib = DynamicLibrary.process();
    final create = lib
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>, Pointer<Char>, Uint32),
          Pointer<Void> Function(Pointer<Void>, Pointer<Char>, int)
        >('CFStringCreateWithCString');
    final utf8 = value.toNativeUtf8();
    final cf = create(nullptr, utf8.cast(), kCFStringEncodingUTF8);
    malloc.free(utf8);
    return cf;
  }

  void _cfRelease(Pointer<Void> value) {
    final lib = DynamicLibrary.process();
    final release = lib
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('CFRelease');
    release(value);
  }
}
