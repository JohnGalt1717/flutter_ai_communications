import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'src/web_endpoint_policy.dart';
import 'src/web_route_class.dart';

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
    final granted = await _acquireCapture(_captureId);
    if (granted == MicrophonePermission.granted) {
      await _refreshCatalog();
    }
    return granted;
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
    _lastNativeFormats = const NativeFormatReport();
    _listenForDeviceChanges();
    final wantCapture = _policy.wantsCapture(captureId, renderId);
    if (wantCapture) {
      final granted = await _acquireCapture(captureId);
      if (granted != MicrophonePermission.granted) {
        return NativeGraphStart.unavailable;
      }
      await _refreshCatalog();
      if (_endpoints.where((e) => e.isCapture).isEmpty) {
        return NativeGraphStart.unavailable;
      }
    } else {
      await _refreshCatalog();
    }
    _lastIsolation = const IsolationEvent(IsolationState.unavailable);
    _isolation.add(_lastIsolation);
    try {
      await _startGraph();
    } on Object {
      _lastNativeFormats = const NativeFormatReport();
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
    _processor = null;
    _source = null;
    _player = null;
    _stopTracks();
    await _closeContext();
    _lastNativeFormats = const NativeFormatReport();
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
    final wantCapture = _policy.wantsCapture(_captureId, _renderId);
    if (captureChanged || renderChanged || _stream == null) {
      if (wantCapture && (captureChanged || _stream == null)) {
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
            routeClass: webRouteClass(
              name: device.label.isEmpty ? device.deviceId : device.label,
              isCapture: device.kind == 'audioinput',
            ),
            isCapture: device.kind == 'audioinput',
            pairId: device.groupId.isEmpty ? device.deviceId : device.groupId,
          ),
    ];
    _catalog.add(List<Endpoint>.of(_endpoints));
  }

  Future<void> _startGraph() async {
    final wantCapture = _policy.wantsCapture(_captureId, _renderId);
    final wantPlayback = _policy.wantsPlayback(_captureId, _renderId);
    final stream = _stream;
    if (wantCapture && stream == null) {
      throw StateError('capture stream missing');
    }
    _processor?.disconnect();
    _source?.disconnect();
    final render = _policy.renderPlan(_renderId, sinkSupported: _sinkSupported);
    final bind = _policy.sinkBind(
      contextOpen: _context != null,
      appliedSinkId: _appliedSinkId,
      desiredSinkId: render.sinkId,
      stopping: false,
    );
    final web.AudioContext context;
    switch (bind) {
      case WebSinkBind.open:
        context = _openContext(render);
        _context = context;
      case WebSinkBind.replace:
        await _closeContext();
        context = _openContext(render);
        _context = context;
      case WebSinkBind.keep:
        context = _context!;
      case WebSinkBind.close:
        throw StateError('stop does not start a graph');
    }
    try {
      await context.resume().toDart.timeout(const Duration(seconds: 1));
    } on Object {
      // Already running, or the browser blocked resume.
    }
    _nextTime = context.currentTime;
    _generation++;
    if (wantCapture && stream != null) {
      final source = context.createMediaStreamSource(stream);
      _source = source;
      final processor = context.createScriptProcessor(2048, 2, 1);
      _processor = processor;
      processor.onaudioprocess = ((web.AudioProcessingEvent event) {
        if (_paused || !_running) {
          return;
        }
        final channels = event.inputBuffer.numberOfChannels;
        final left = event.inputBuffer.getChannelData(0).toDart;
        final right = channels > 1
            ? event.inputBuffer.getChannelData(1).toDart
            : left;
        final out = Uint8List(left.length * 2);
        final data = ByteData.sublistView(out);
        for (var i = 0; i < left.length; i++) {
          final mixed = channels > 1 ? (left[i] + right[i]) / 2 : left[i];
          final sample = (mixed * 32767).round().clamp(-32767, 32767);
          data.setInt16(i * 2, sample, Endian.little);
        }
        _capture.add(out);
      }).toJS;
      source.connect(processor);
      if (wantPlayback) {
        processor.connect(context.destination);
      } else {
        final mute = context.createGain();
        mute.gain.value = 0;
        processor.connect(mute);
        mute.connect(context.destination);
      }
    }
    _running = true;
    _paused = false;
    final native = _policy.nativeFormat(sampleRate: context.sampleRate);
    _lastNativeFormats = NativeFormatReport(
      capture: wantCapture ? native : null,
      playback: wantPlayback ? native : null,
    );
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

  Future<void> _closeContext() async {
    try {
      _player?.stop();
    } on Object {
      // Node may already be dead with the context.
    }
    _player = null;
    final context = _context;
    _context = null;
    _appliedSinkId = null;
    _nextTime = 0.0;
    if (context == null) {
      return;
    }
    try {
      await context.close().toDart;
    } on Object {
      // Already closed.
    }
  }

  void _emitObserved({WebSinkUnsupported? unsupported}) {
    final capture = _observedCaptureId();
    final render = _policy.observedRenderId(
      appliedSinkId: _appliedSinkId,
      unsupported: unsupported,
    );
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

  web.MediaStream? _videoStream;
  web.HTMLVideoElement? _videoEl;
  var _cameraViewId = 0;
  VideoSurface? _cameraSurface;
  VideoFormat? _cameraFormat;
  String? _selectedCameraId;

  @override
  VideoSurface? get lastVideoSurface => _cameraSurface;

  @override
  VideoFormat? get lastNativeVideoFormat => _cameraFormat;

  @override
  Future<List<CameraEndpoint>> enumerateCameras() async {
    final devices =
        (await web.window.navigator.mediaDevices.enumerateDevices().toDart)
            .toDart;
    return [
      for (final device in devices)
        if (device.kind == 'videoinput')
          CameraEndpoint(
            id: device.deviceId,
            name: device.label.isEmpty ? 'Camera' : device.label,
            facing: CameraFacing.unspecified,
            modes: const [VideoFormat.defaultFormat],
          ),
    ];
  }

  @override
  Future<CameraPermission> requestCameraPermission() async {
    try {
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(web.MediaStreamConstraints(video: true.toJS))
          .toDart
          .timeout(const Duration(seconds: 2));
      stream.getTracks().toDart.forEach((track) => track.stop());
      return CameraPermission.granted;
    } on Object {
      return CameraPermission.denied;
    }
  }

  @override
  Future<NativeGraphStart> startCameraNative({
    String? cameraId,
    VideoFormat? videoFormat,
    bool enabled = true,
    bool muted = false,
  }) async {
    await stopCameraNative();
    _selectedCameraId = cameraId;
    final requested = videoFormat ?? VideoFormat.defaultFormat;
    if (!enabled) {
      _cameraSurface = null;
      _cameraFormat = requested;
      return NativeGraphStart.started;
    }
    try {
      final JSAny videoConstraint = cameraId == null || cameraId.isEmpty
          ? true.toJS
          : web.MediaTrackConstraints(
              deviceId: web.ConstrainDOMStringParameters(exact: cameraId.toJS),
            );
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(web.MediaStreamConstraints(video: videoConstraint))
          .toDart
          .timeout(const Duration(seconds: 3));
      _videoStream = stream;
      _cameraViewId++;
      final viewType = 'fac-camera-$_cameraViewId';
      ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
        final video = web.HTMLVideoElement()
          ..autoplay = true
          ..muted = true
          ..srcObject = stream;
        video.setAttribute('playsinline', 'true');
        video.style
          ..setProperty('width', '320px')
          ..setProperty('height', '220px')
          ..setProperty('object-fit', 'cover')
          ..setProperty('display', 'block');
        final wrap = web.HTMLDivElement();
        wrap.style
          ..setProperty('width', '320px')
          ..setProperty('height', '220px')
          ..setProperty('overflow', 'hidden')
          ..setProperty('position', 'relative');
        wrap.append(video);
        _videoEl = video;
        return wrap;
      });
      _cameraSurface = VideoSurface(
        handle: _cameraViewId,
        kind: VideoSurfaceKind.htmlElement,
      );
      _cameraFormat = requested;
      if (muted) {
        stream.getVideoTracks().toDart.forEach((track) {
          track.enabled = false;
        });
      }
      return NativeGraphStart.started;
    } on Object {
      _cameraSurface = null;
      _cameraFormat = null;
      return NativeGraphStart.unavailable;
    }
  }

  @override
  Future<void> stopCameraNative() async {
    _videoStream?.getTracks().toDart.forEach((track) => track.stop());
    _videoStream = null;
    _videoEl = null;
    _cameraSurface = null;
    _cameraFormat = null;
  }

  @override
  Future<void> selectCameraNative(String cameraId) async {
    _selectedCameraId = cameraId;
    if (_videoStream != null) {
      await startCameraNative(
        cameraId: cameraId,
        videoFormat: _cameraFormat,
        enabled: true,
        muted: false,
      );
    }
  }

  @override
  Future<void> setCameraEnabledNative(bool enabled) async {
    if (!enabled) {
      _videoStream?.getTracks().toDart.forEach((track) => track.stop());
      _videoStream = null;
      _cameraSurface = null;
    } else {
      await startCameraNative(
        cameraId: _selectedCameraId,
        videoFormat: _cameraFormat,
        enabled: true,
      );
    }
  }

  @override
  Future<void> setMuteVideoNative(bool muted) async {
    _videoStream?.getVideoTracks().toDart.forEach((track) {
      track.enabled = !muted;
    });
  }
}
