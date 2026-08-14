import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

/// Web adapter: `getUserMedia` then `enumerateDevices` + `groupId` pairing.
///
/// No Isolation, no handset. Blank labels before permission are not a catalog
/// the host should see after [startNative].
final class FlutterAiCommunicationsWeb extends FlutterAiCommunicationsPlatform {
  /// Creates the web adapter.
  FlutterAiCommunicationsWeb();

  /// Registers this class as the default instance.
  static void registerWith(Registrar registrar) {
    FlutterAiCommunicationsPlatform.instance = FlutterAiCommunicationsWeb();
  }

  final StreamController<Uint8List> _capture =
      StreamController<Uint8List>.broadcast();
  final StreamController<List<Endpoint>> _catalog =
      StreamController<List<Endpoint>>.broadcast();
  final StreamController<IsolationEvent> _isolation =
      StreamController<IsolationEvent>.broadcast();

  web.MediaStream? _stream;
  web.AudioContext? _context;
  web.ScriptProcessorNode? _processor;
  web.MediaStreamAudioSourceNode? _source;
  web.AudioBufferSourceNode? _player;
  List<Endpoint> _endpoints = const [];
  var _paused = false;
  var _running = false;
  String? _captureId;
  IsolationEvent _lastIsolation = const IsolationEvent(
    IsolationState.unavailable,
  );

  @override
  IsolationEvent get lastIsolation => _lastIsolation;

  @override
  String get platformName => 'web';

  /// Browser user agent, used for capability probes.
  String get userAgent => web.window.navigator.userAgent;

  @override
  Future<List<Endpoint>> enumerateEndpoints() async =>
      List<Endpoint>.of(_endpoints);

  @override
  Stream<List<Endpoint>> get endpointCatalog => _catalog.stream;

  @override
  Future<MicrophonePermission> requestMicrophonePermission() async {
    try {
      _stream = await web.window.navigator.mediaDevices
          .getUserMedia(
            web.MediaStreamConstraints(audio: true.toJS),
          )
          .toDart;
      return MicrophonePermission.granted;
    } on Object {
      return MicrophonePermission.denied;
    }
  }

  @override
  Future<NativeGraphStart> startNative({
    String? captureId,
    String? renderId,
  }) async {
    final stream = _stream;
    if (stream == null) {
      return NativeGraphStart.unavailable;
    }
    _captureId = captureId;
    await _refreshCatalog();
    if (_endpoints.where((e) => e.isCapture).isEmpty) {
      return NativeGraphStart.unavailable;
    }
    _lastIsolation = const IsolationEvent(IsolationState.unavailable);
    _isolation.add(_lastIsolation);
    try {
      await _startGraph(stream);
    } on Object {
      return NativeGraphStart.failed;
    }
    return NativeGraphStart.started;
  }

  @override
  Future<void> stopNative() async {
    _running = false;
    _processor?.disconnect();
    _source?.disconnect();
    _player?.stop();
    await _context?.close().toDart;
    _processor = null;
    _source = null;
    _player = null;
    _context = null;
    final tracks = _stream?.getTracks().toDart;
    if (tracks != null) {
      for (final track in tracks) {
        track.stop();
      }
    }
    _stream = null;
  }

  @override
  Future<void> pauseNative() async {
    _paused = true;
    await _context?.suspend().toDart;
  }

  @override
  Future<void> resumeNative() async {
    _paused = false;
    await _context?.resume().toDart;
  }

  @override
  Stream<Uint8List> get nativeCapture => _capture.stream;

  @override
  Future<void> play(Uint8List bytes) async {
    final context = _context;
    if (context == null || _paused || !_running) {
      return;
    }
    final samples = bytes.length ~/ 2;
    if (samples == 0) {
      return;
    }
    final buffer = context.createBuffer(1, samples, context.sampleRate);
    final channel = buffer.getChannelData(0).toDart;
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < samples; i++) {
      channel[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    final source = context.createBufferSource();
    source.buffer = buffer;
    source.connect(context.destination);
    source.start();
    _player = source;
  }

  @override
  Future<void> selectEndpoints({String? captureId, String? renderId}) async {
    if (captureId == null || captureId == _captureId) {
      return;
    }
    _captureId = captureId;
    final granted = await requestMicrophonePermission();
    if (granted != MicrophonePermission.granted) {
      return;
    }
    final stream = _stream;
    if (stream == null) {
      return;
    }
    await _startGraph(stream);
  }

  @override
  Stream<IsolationEvent> get isolation => _isolation.stream;

  @override
  Future<void> openIsolationSettings() async {}

  @override
  Future<void> flushPlayback() async {
    _player?.stop();
    _player = null;
  }

  Future<void> _refreshCatalog() async {
    final devices = (await web.window.navigator.mediaDevices
            .enumerateDevices()
            .toDart)
        .toDart;
    _endpoints = [
      for (final device in devices)
        if (device.kind == 'audioinput' || device.kind == 'audiooutput')
          Endpoint(
            id: device.deviceId,
            name: device.label.isEmpty ? device.deviceId : device.label,
            routeClass: device.kind == 'audiooutput'
                ? RouteClass.speakerphone
                : RouteClass.wired,
            isCapture: device.kind == 'audioinput',
            pairId: device.groupId.isEmpty ? device.deviceId : device.groupId,
          ),
    ];
    _catalog.add(List<Endpoint>.of(_endpoints));
  }

  Future<void> _startGraph(web.MediaStream stream) async {
    _processor?.disconnect();
    _source?.disconnect();
    await _context?.close().toDart;
    final context = web.AudioContext();
    _context = context;
    final source = context.createMediaStreamSource(stream);
    _source = source;
    final processor = context.createScriptProcessor(2048, 1, 1);
    _processor = processor;
    processor.onaudioprocess = ((web.AudioProcessingEvent event) {
      if (_paused || !_running) {
        return;
      }
      final input = event.inputBuffer.getChannelData(0).toDart;
      final out = Uint8List(input.length * 2);
      final data = ByteData.sublistView(out);
      for (var i = 0; i < input.length; i++) {
        final sample = (input[i] * 32767).round().clamp(-32767, 32767);
        data.setInt16(i * 2, sample, Endian.little);
      }
      _capture.add(out);
    }).toJS;
    source.connect(processor);
    processor.connect(context.destination);
    _running = true;
    _paused = false;
  }
}
