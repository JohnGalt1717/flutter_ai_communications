import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'src/web_endpoint_policy.dart';

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

  static const _policy = WebEndpointPolicy();

  final StreamController<Uint8List> _capture =
      StreamController<Uint8List>.broadcast();
  final StreamController<List<Endpoint>> _catalog =
      StreamController<List<Endpoint>>.broadcast();
  final StreamController<IsolationEvent> _isolation =
      StreamController<IsolationEvent>.broadcast();
  final StreamController<OsRouteChange> _routes =
      StreamController<OsRouteChange>.broadcast();

  web.MediaStream? _stream;
  web.AudioContext? _context;
  web.ScriptProcessorNode? _processor;
  web.MediaStreamAudioSourceNode? _source;
  web.AudioBufferSourceNode? _player;
  List<Endpoint> _endpoints = const [];
  var _paused = false;
  var _running = false;
  var _listeningDevices = false;
  var _generation = 0;
  var _nextTime = 0.0;
  bool? _sinkCapability;
  String? _captureId;
  String? _renderId;
  String? _appliedSinkId;
  PairingSnapshot _observed = const PairingSnapshot();
  NativeFormatReport _lastNativeFormats = const NativeFormatReport();
  IsolationEvent _lastIsolation = const IsolationEvent(
    IsolationState.unavailable,
  );

  @override
  IsolationEvent get lastIsolation => _lastIsolation;

  @override
  PairingSnapshot get lastObservedRoute => _observed;

  @override
  NativeFormatReport get lastNativeFormats => _lastNativeFormats;

  @override
  Stream<OsRouteChange> get osRouteChanges => _routes.stream;

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
    return _acquireCapture(_captureId);
  }

  @override
  Future<NativeGraphStart> startNative({
    String? captureId,
    String? renderId,
    AudioFormat? captureFormat,
    AudioFormat? playbackFormat,
    bool noiseCancelling = true,
  }) async {
    _captureId = captureId;
    _renderId = renderId;
    _listenForDeviceChanges();
    final granted = await _acquireCapture(captureId);
    if (granted != MicrophonePermission.granted) {
      return NativeGraphStart.unavailable;
    }
    await _refreshCatalog();
    if (_endpoints.where((e) => e.isCapture).isEmpty) {
      return NativeGraphStart.unavailable;
    }
    _lastIsolation = const IsolationEvent(IsolationState.unavailable);
    _isolation.add(_lastIsolation);
    try {
      await _startGraph();
    } on Object {
      return NativeGraphStart.failed;
    }
    _lastNativeFormats = NativeFormatReport(
      capture: captureFormat,
      playback: playbackFormat,
    );
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
    _nextTime = 0;
    _stopTracks();
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
    final context = _context;
    if (context != null && _nextTime < context.currentTime) {
      _nextTime = context.currentTime;
    }
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
    final startAt = _nextTime > context.currentTime
        ? _nextTime
        : context.currentTime;
    source.start(startAt);
    _nextTime = startAt + (samples / context.sampleRate);
    _player = source;
  }

  @override
  Future<void> selectEndpoints({String? captureId, String? renderId}) async {
    final captureChanged = captureId != null && captureId != _captureId;
    final renderChanged = renderId != null && renderId != _renderId;
    if (captureId != null) {
      _captureId = captureId;
    }
    if (renderId != null) {
      _renderId = renderId;
    }
    if (!_running && _stream == null) {
      return;
    }
    if (captureChanged || renderChanged || _stream == null) {
      if (captureChanged || _stream == null) {
        final granted = await _acquireCapture(_captureId);
        if (granted != MicrophonePermission.granted) {
          return;
        }
      }
      await _startGraph();
    }
  }

  @override
  Stream<IsolationEvent> get isolation => _isolation.stream;

  @override
  Future<void> openIsolationSettings() async {}

  @override
  Future<void> flushPlayback() async {
    _player?.stop();
    _player = null;
    final context = _context;
    _nextTime = context?.currentTime ?? 0;
  }

  Future<MicrophonePermission> _acquireCapture(String? captureId) async {
    try {
      final plan = _policy.capturePlan(captureId);
      final JSAny audio = plan.constrainDevice
          ? web.MediaTrackConstraints(
              deviceId: web.ConstrainDOMStringParameters(
                exact: plan.deviceId!.toJS,
              ),
            )
          : true.toJS;
      final next = await web.window.navigator.mediaDevices
          .getUserMedia(web.MediaStreamConstraints(audio: audio))
          .toDart;
      _stopTracks();
      _stream = next;
      return MicrophonePermission.granted;
    } on Object {
      return MicrophonePermission.denied;
    }
  }

  void _listenForDeviceChanges() {
    if (_listeningDevices) {
      return;
    }
    _listeningDevices = true;
    web.window.navigator.mediaDevices.ondevicechange = ((web.Event _) {
      unawaited(_onDeviceChange());
    }).toJS;
  }

  Future<void> _onDeviceChange() async {
    await _refreshCatalog();
    if (!_running) {
      return;
    }
    _emitObserved();
  }

  void _stopTracks() {
    final tracks = _stream?.getTracks().toDart;
    if (tracks != null) {
      for (final track in tracks) {
        track.stop();
      }
    }
    _stream = null;
  }

  Future<void> _refreshCatalog() async {
    final devices =
        (await web.window.navigator.mediaDevices.enumerateDevices().toDart)
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

  Future<void> _startGraph() async {
    final stream = _stream;
    if (stream == null) {
      throw StateError('capture stream missing');
    }
    _processor?.disconnect();
    _source?.disconnect();
    await _context?.close().toDart;
    final render = _policy.renderPlan(_renderId, sinkSupported: _sinkSupported);
    final context = _openContext(render);
    _context = context;
    _nextTime = context.currentTime;
    _generation++;
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
    _emitObserved(unsupported: render.unsupported);
  }

  web.AudioContext _openContext(WebRenderPlan render) {
    final sinkId = render.sinkId;
    if (sinkId == null) {
      _appliedSinkId = null;
      return web.AudioContext();
    }
    try {
      final context = web.AudioContext(
        web.AudioContextOptions(sinkId: sinkId.toJS),
      );
      _appliedSinkId = sinkId;
      return context;
    } on Object {
      _appliedSinkId = null;
      return web.AudioContext();
    }
  }

  bool get _sinkSupported {
    final cached = _sinkCapability;
    if (cached != null) {
      return cached;
    }
    try {
      final probe = web.AudioContext();
      final supported = probe.has('sinkId');
      unawaited(probe.close().toDart);
      return _sinkCapability = supported;
    } on Object {
      return _sinkCapability = false;
    }
  }

  void _emitObserved({WebSinkUnsupported? unsupported}) {
    final capture = _observedCaptureId();
    final render = unsupported == null ? _observedRenderId() : null;
    _observed = PairingSnapshot(captureId: capture, renderId: render);
    _routes.add(
      OsRouteChange(
        captureId: capture,
        renderId: render,
        generation: _generation,
      ),
    );
  }

  String? _observedCaptureId() {
    final track = _stream?.getAudioTracks().toDart.firstOrNull;
    final id = track?.getSettings().deviceId;
    if (id != null && id.isNotEmpty) {
      return id;
    }
    return _captureId;
  }

  String? _observedRenderId() {
    final applied = _appliedSinkId;
    if (applied != null && applied.isNotEmpty) {
      return applied;
    }
    return _renderId;
  }
}
