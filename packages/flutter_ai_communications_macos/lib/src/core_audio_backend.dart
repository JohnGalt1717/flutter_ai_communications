import 'dart:async';
import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';

import 'audio_backend.dart';
import 'core_audio_ffi.dart';
import 'macos_format_plan.dart';
import 'macos_pcm_convert.dart';
import 'macos_queue_bind.dart';
import 'route_class.dart';

const _silenceBytes = 480;
const _bufferCount = 3;

/// Core Audio AudioQueue capture and render.
final class CoreAudioBackend implements AudioBackend {
  /// Opens Core Audio in-process.
  CoreAudioBackend() : _audio = CoreAudio();

  final CoreAudio _audio;
  final MacPcmConvert _convert = const MacPcmConvert();
  AudioQueueRef _capture = nullptr;
  AudioQueueRef _render = nullptr;
  NativeCallable<AudioQueueInputNative>? _inputCallable;
  NativeCallable<AudioQueueOutputNative>? _outputCallable;
  final List<Uint8List> _playback = [];
  var _running = false;
  var _paused = false;
  String? _captureId;
  String? _renderId;
  AudioFormat _captureNative = AudioFormat.pcm16le24k;
  AudioFormat _renderNative = AudioFormat.pcm16le24k;
  var _captureBufferBytes = _silenceBytes;
  var _renderBufferBytes = _silenceBytes;

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
    _playback.add(_convert.fromEdge(bytes, native: _renderNative));
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
    _startGraph();
  }

  @override
  PairingSnapshot get observed => PairingSnapshot(
    captureId: observedQueueUid(boundUid: _boundUid(_capture)),
    renderId: observedQueueUid(boundUid: _boundUid(_render)),
  );

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
    _captureNative = _planFor(_captureId, capture: true).native;
    _renderNative = _planFor(_renderId, capture: false).native;
    _captureBufferBytes = _bufferBytesFor(_captureNative);
    _renderBufferBytes = _bufferBytesFor(_renderNative);
    try {
      if (!_openCapture() || !_openRender()) {
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
    } on Object {
      _stopGraph();
      return false;
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

  bool _openCapture() {
    final callable = NativeCallable<AudioQueueInputNative>.isolateLocal(
      _onInput,
    );
    _inputCallable = callable;
    final format = calloc<AudioStreamBasicDescription>();
    _audio.writePcm16(
      format,
      sampleRate: _captureNative.sampleRate.toDouble(),
      channels: _captureNative.channels,
    );
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
    calloc.free(format);
    if (status != noErr) {
      calloc.free(queue);
      return false;
    }
    _capture = queue.value;
    calloc.free(queue);
    if (!_bindDevice(_capture, _captureId, capture: true)) {
      return false;
    }
    return _prime(_capture, _captureBufferBytes, fillSilence: false);
  }

  bool _openRender() {
    final callable = NativeCallable<AudioQueueOutputNative>.isolateLocal(
      _onOutput,
    );
    _outputCallable = callable;
    final format = calloc<AudioStreamBasicDescription>();
    _audio.writePcm16(
      format,
      sampleRate: _renderNative.sampleRate.toDouble(),
      channels: _renderNative.channels,
    );
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
    calloc.free(format);
    if (status != noErr) {
      calloc.free(queue);
      return false;
    }
    _render = queue.value;
    calloc.free(queue);
    if (!_bindDevice(_render, _renderId, capture: false)) {
      return false;
    }
    return _prime(_render, _renderBufferBytes, fillSilence: true);
  }

  bool _prime(
    AudioQueueRef queue,
    int bufferBytes, {
    required bool fillSilence,
  }) {
    for (var i = 0; i < _bufferCount; i++) {
      final buffer = calloc<AudioQueueBufferRef>();
      final status = _audio.queueAllocateBuffer(queue, bufferBytes, buffer);
      if (status != noErr) {
        calloc.free(buffer);
        return false;
      }
      final ref = buffer.value;
      calloc.free(buffer);
      ref.ref.audioDataByteSize = bufferBytes;
      if (fillSilence) {
        ref.ref.audioData
            .cast<Uint8>()
            .asTypedList(bufferBytes)
            .fillRange(0, bufferBytes, 0);
      }
      if (_audio.queueEnqueueBuffer(queue, ref, 0, nullptr) != noErr) {
        return false;
      }
    }
    return true;
  }

  bool _bindDevice(AudioQueueRef queue, String? id, {required bool capture}) {
    final uid = id ?? _defaultUid(capture: capture);
    if (uid == null || uid.isEmpty) {
      return true;
    }
    final cf = _cfString(uid);
    if (cf == nullptr) {
      return false;
    }
    final value = calloc<Pointer<Void>>()..value = cf;
    final status = _audio.queueSetProperty(
      queue,
      fourCC('aqcd'),
      value.cast(),
      sizeOf<Pointer>(),
    );
    calloc.free(value);
    _cfRelease(cf);
    // Set must succeed. GetProperty is Observed only — a null get after
    // a successful set is not a license to claim the requested UID.
    return status == noErr;
  }

  String? _boundUid(AudioQueueRef queue) {
    if (queue == nullptr) {
      return null;
    }
    return _audio.queueCurrentDeviceUid(queue);
  }

  void _onInput(
    Pointer<Void> _,
    AudioQueueRef queue,
    AudioQueueBufferRef buffer,
    Pointer<Void> _,
    int _,
    Pointer<Void> _,
  ) {
    if (!_running || _paused) {
      if (queue != nullptr && buffer != nullptr) {
        _audio.queueEnqueueBuffer(queue, buffer, 0, nullptr);
      }
      return;
    }
    final size = buffer.ref.audioDataByteSize;
    if (size > 0 && buffer.ref.audioData != nullptr) {
      final native = Uint8List.fromList(
        buffer.ref.audioData.cast<Uint8>().asTypedList(size),
      );
      _captureOut.add(_convert.toEdge(native, native: _captureNative));
    }
    _audio.queueEnqueueBuffer(queue, buffer, 0, nullptr);
  }

  void _onOutput(
    Pointer<Void> _,
    AudioQueueRef queue,
    AudioQueueBufferRef buffer,
  ) {
    final dest = buffer.ref.audioData.cast<Uint8>().asTypedList(
      _renderBufferBytes,
    );
    dest.fillRange(0, _renderBufferBytes, 0);
    if (_running && !_paused && _playback.isNotEmpty) {
      final next = _playback.removeAt(0);
      final count = min(next.length, _renderBufferBytes);
      dest.setRange(0, count, next);
    }
    buffer.ref.audioDataByteSize = _renderBufferBytes;
    if (queue != nullptr) {
      _audio.queueEnqueueBuffer(queue, buffer, 0, nullptr);
    }
  }

  void _emitSilence() {
    _captureOut.add(Uint8List(_silenceBytes));
  }

  MacNativeFormatPlan _planFor(String? uid, {required bool capture}) {
    final deviceId = switch (uid) {
      null || '' => _defaultDeviceId(capture: capture),
      final value => _audio.deviceIdForUid(value),
    };
    if (deviceId == null) {
      return planMacNativeFormat(channels: 1);
    }
    final channels = _audio.channelCount(deviceId, capture: capture);
    final rates = macosDiscreteRates(
      _audio.availableSampleRateRanges(deviceId),
    );
    return planMacNativeFormat(
      channels: channels < 1 ? 1 : channels,
      availableRates: rates,
    );
  }

  int _bufferBytesFor(AudioFormat format) {
    final frames = max(format.sampleRate ~/ 100, 1);
    return frames * format.channels * 2;
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

  int? _defaultDeviceId({required bool capture}) {
    return _audio.uint32Property(
      audioObjectSystemObject,
      capture ? fourCC('dIn ') : fourCC('dOut'),
    );
  }

  String? _defaultUid({required bool capture}) {
    final defaultId = _defaultDeviceId(capture: capture);
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
