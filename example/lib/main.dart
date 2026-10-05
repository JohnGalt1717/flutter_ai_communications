import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_ai_communications_webrtc/flutter_ai_communications_webrtc.dart';
import 'package:flutter_ai_communications_example/echo/echo_transport.dart';
import 'package:flutter_ai_communications_example/host_preference_store.dart';
import 'package:flutter_ai_communications_example/meeting/flutter_webrtc_loopback.dart';
import 'package:flutter_ai_communications_example/meeting/host_webrtc_loopback.dart';
import 'package:flutter_ai_communications_example/preference_editor.dart';
import 'package:flutter_ai_communications_example/echo/loopback_platform.dart';
import 'package:flutter_ai_communications_example/echo/loopback_probe.dart';
import 'package:flutter_ai_communications_example/meeting/audio_device_panel.dart';
import 'package:flutter_ai_communications_example/meeting/camera_device_panel.dart';
import 'package:flutter_ai_communications_example/meeting/chrome.dart';
import 'package:flutter_ai_communications_example/meeting/lobby_stage.dart';
import 'package:flutter_ai_communications_example/meeting/loopback_meeting.dart';
import 'package:flutter_ai_communications_example/meeting/share_picker.dart';
import 'package:flutter_ai_communications_example/meeting/video_surface_view.dart';
import 'package:flutter_skill/flutter_skill.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  // FlutterSkillBinding is not a WidgetsBinding; initialize ServicesBinding
  // before any platform EventChannel listen (loopback wrap).
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (details) {
    return ColoredBox(
      color: const Color(0xFF5B0000),
      child: Text(
        '${details.exception}',
        key: const Key('error'),
        style: const TextStyle(color: Color(0xFFFFFFFF)),
      ),
    );
  };
  _installAgentBindings();
  LoopbackCommunicationsPlatform.wrapRegistered();
  runApp(
    ExampleApp(
      manager: CommunicationsManager(),
      preferenceStore: await _loadPreferenceStore(),
      webRtcLoopback: FlutterWebRtcLoopback(),
    ),
  );
}

Future<HostPreferenceStore> _loadPreferenceStore() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return HostPreferenceStore(
      storage: {
        for (final key in [
          HostPreferenceStore.endpointsKey,
          HostPreferenceStore.camerasKey,
        ])
          key: ?prefs.getString(key),
      },
      persist: (key, value) async {
        await prefs.setString(key, value);
      },
    );
  } on Object {
    return HostPreferenceStore();
  }
}

/// Registers flutter-skill UI automation in debug `flutter run` only.
///
/// Use flutter_agent_lens for attach/logs/breakpoints; flutter-skill for taps.
/// Tests should not call this `main()` if they need a different binding.
void _installAgentBindings() {
  if (!kDebugMode) {
    return;
  }
  hierarchicalLoggingEnabled = true;
  Logger.root.level = Level.INFO;
  Logger(PipelineLog.loggerName).level = Level.INFO;
  // Web HtmlElementView + the skill overlay both use Overlay entries.
  // Auto-indicators on web trip InheritedElement.deactivate during Session start.
  FlutterSkillBinding.ensureInitialized(autoEnableIndicators: !kIsWeb);
}

enum _HarnessPhase { idle, lobby, meeting }

/// AI-voice harness that looks like a communications client.
///
/// Owns one application-scoped [CommunicationsManager]. Tests may inject a
/// manager; `main()` constructs one for the process lifetime.
final class ExampleApp extends StatefulWidget {
  /// Creates the example app.
  const ExampleApp({
    super.key,
    this.manager,
    this.preferenceStore,
    this.webRtcLoopback,
  });

  /// Optional injected Communications manager (tests / agent harness).
  final CommunicationsManager? manager;

  /// Optional injected host preference store (tests).
  final HostPreferenceStore? preferenceStore;

  /// Optional injected host WebRTC loopback (tests).
  final HostWebRtcLoopback? webRtcLoopback;

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

final class _ExampleAppState extends State<ExampleApp> {
  late final CommunicationsManager _manager =
      widget.manager ?? CommunicationsManager();
  late final HostPreferenceStore _store =
      widget.preferenceStore ?? HostPreferenceStore();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Communications',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B4BFF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: SessionPage(
        manager: _manager,
        preferenceStore: _store,
        webRtcLoopback: widget.webRtcLoopback,
      ),
    );
  }
}

/// Live Session controls and capture visualizer.
final class SessionPage extends StatefulWidget {
  /// Creates the Session page.
  const SessionPage({
    super.key,
    required this.manager,
    this.preferenceStore,
    this.webRtcLoopback,
  });

  /// Communications manager driving the Session.
  final CommunicationsManager manager;

  /// Host-persisted Endpoint preference and Camera preference.
  final HostPreferenceStore? preferenceStore;

  /// Host-owned WebRTC loopback. Tests inject a fake.
  final HostWebRtcLoopback? webRtcLoopback;

  @override
  State<SessionPage> createState() => _SessionPageState();
}

final class _SessionPageState extends State<SessionPage> {
  late final HostPreferenceStore _store =
      widget.preferenceStore ?? HostPreferenceStore();
  late final HostWebRtcLoopback _webRtcLoopback =
      widget.webRtcLoopback ?? FakeHostWebRtcLoopback();
  var _phase = _HarnessPhase.idle;
  Session? _session;
  EchoTransport? _echo;
  WebrtcVideoSink? _webrtc;
  StreamSubscription<WebrtcSendTrack?>? _webrtcSub;
  EchoProof? _proof;
  String? _status;
  IsolationEvent? _isolation;
  Coverage _coverage = const Coverage.ok();
  double _level = 0;
  final _levels = <double>[];
  final _wave = ValueNotifier<int>(0);
  var _waveScheduled = false;
  List<Endpoint> _endpoints = const [];
  List<CameraEndpoint> _cameras = const [];
  List<ScreenSource> _screenSources = const [];
  String? _indicatedScreenId;
  var _includeSound = false;
  var _screenMotion = false;
  var _screenCursor = true;
  String? _screenStatus;
  SessionDiagnostics? _diagnostics;
  final _pipeline = <String>[];
  StreamSubscription<LogRecord>? _logSub;
  StreamSubscription<List<Endpoint>>? _catalogSub;
  StreamSubscription<List<CameraEndpoint>>? _cameraCatalogSub;
  Uint8List? _replaceStill;
  var _catalogEpoch = 0;
  EndpointPreference _draft = const EndpointPreference();
  var _audioOpen = false;
  var _cameraOpen = false;
  static const _pcm16le16k = AudioFormat.pcm16le(sampleRate: 16000);
  AudioFormat _edgeFormat = AudioFormat.pcm16le24k;
  var _formatSwitching = false;
  var _starting = false;
  var _lastCaptureFrameBytes = 0;
  var _captureBytesPerSecond = 0;
  var _captureByteWindow = 0;
  DateTime? _captureWindowStart;

  CommunicationsManager get _manager => widget.manager;

  @override
  void initState() {
    super.initState();
    hierarchicalLoggingEnabled = true;
    Logger(PipelineLog.loggerName).level = Level.INFO;
    _logSub = Logger(PipelineLog.loggerName).onRecord.listen((record) {
      _pipeline.add(record.message);
      if (_pipeline.length > 64) {
        _pipeline.removeAt(0);
      }
    });
    _catalogSub = _manager.endpointCatalog.listen((endpoints) {
      _catalogEpoch++;
      _endpoints = endpoints;
      if (!mounted) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
    });
    _cameraCatalogSub = _manager.cameraCatalog.listen((cameras) {
      _cameras = cameras;
      if (!mounted) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
    });
    _draft = _store.endpoints;
    _bindStoredPreference();
    _loadEndpoints();
    unawaited(_loadReplaceStill());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _phase == _HarnessPhase.idle && !_starting) {
        unawaited(_enterLobby());
      }
    });
  }

  Future<void> _loadReplaceStill() async {
    final data = await rootBundle.load('assets/replace_still.jpg');
    if (!mounted) {
      return;
    }
    setState(() {
      _replaceStill = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
    });
  }

  void _bindStoredPreference() {
    _manager.bindCameraPreference(_store.cameras);
    unawaited(_manager.bindPreference(_store.endpoints));
  }

  bool _idlePreferredEndpoint(Endpoint endpoint) {
    String? preferredCapture;
    String? preferredRender;
    for (final entry in _store.endpoints.entries) {
      if (!entry.enabled) {
        continue;
      }
      if (preferredRender == null &&
          _endpoints.any((item) => item.id == entry.renderId)) {
        preferredRender = entry.renderId;
      }
      for (final slot in entry.captures) {
        if (!slot.enabled) {
          continue;
        }
        if (preferredCapture == null &&
            _endpoints.any((item) => item.id == slot.id)) {
          preferredCapture = slot.id;
        }
      }
      if (preferredCapture != null && preferredRender != null) {
        break;
      }
    }
    return endpoint.id == preferredCapture || endpoint.id == preferredRender;
  }

  @override
  void dispose() {
    unawaited(_logSub?.cancel());
    unawaited(_catalogSub?.cancel());
    unawaited(_cameraCatalogSub?.cancel());
    unawaited(_webrtcSub?.cancel());
    _webrtc?.detach();
    unawaited(_webRtcLoopback.dispose());
    unawaited(_manager.cameraPreview?.stop());
    unawaited(_session?.stop());
    unawaited(_releaseCatalogObservation());
    _wave.dispose();
    super.dispose();
  }

  /// Page-lifetime catalog observation — begin once, end on dispose (#88).
  bool _catalogObserving = false;
  Future<void>? _catalogBeginInFlight;

  Future<void> _ensureCatalogObservation() async {
    if (_catalogObserving) {
      return;
    }
    final existing = _catalogBeginInFlight;
    if (existing != null) {
      await existing;
      return;
    }
    late final Future<void> started;
    started = () async {
      await _manager.beginCatalogObservation();
      _catalogObserving = true;
    }();
    _catalogBeginInFlight = started;
    try {
      await started;
    } finally {
      if (identical(_catalogBeginInFlight, started)) {
        _catalogBeginInFlight = null;
      }
    }
  }

  Future<void> _releaseCatalogObservation() async {
    final pending = _catalogBeginInFlight;
    if (pending != null) {
      await pending;
    }
    if (!_catalogObserving) {
      return;
    }
    _catalogObserving = false;
    await _manager.endCatalogObservation();
  }

  Future<void> _loadEndpoints() async {
    final epoch = _catalogEpoch;
    await _ensureCatalogObservation();
    final endpoints = await _manager.endpoints();
    List<ScreenSource> screens = const [];
    try {
      screens = await _manager.screenSources();
    } on Object {
      screens = const [];
    }
    if (mounted) {
      setState(() {
        if (_catalogEpoch == epoch) {
          _endpoints = endpoints;
        }
        _screenSources = screens;
      });
    }
  }

  Future<void> _applyPreference() async {
    _store.saveEndpoints(_draft);
    await _stop();
    await _manager.bindPreference(_store.endpoints);
    if (!mounted) {
      return;
    }
    setState(() => _status = 'preference-bound');
    await _enterLobby();
  }

  Future<void> _useCurrent() async {
    final session = _session;
    if (session == null) {
      return;
    }
    await session.select(
      captureId: session.selectedCaptureId,
      renderId: session.selectedRenderId,
    );
    if (mounted) {
      setState(() => _diagnostics = session.diagnostics);
    }
  }

  Future<StartResult> _startForPhase({required bool meeting}) {
    return _manager.start(
      purpose: meeting ? 'meeting' : 'lobby',
      cameraSend: true,
      captureFormat: _edgeFormat,
      playbackFormat: _edgeFormat,
    );
  }

  void _resetCaptureMeter() {
    _lastCaptureFrameBytes = 0;
    _captureBytesPerSecond = 0;
    _captureByteWindow = 0;
    _captureWindowStart = null;
  }

  Future<void> _applyEdgeFormat(AudioFormat format) async {
    debugPrint(
      '[fac-edge] apply requested=$format current=$_edgeFormat '
      'switching=$_formatSwitching session=${_session != null}',
    );
    if (_formatSwitching) {
      return;
    }
    if (_edgeFormat == format && _session != null) {
      return;
    }
    final meeting = _phase == _HarnessPhase.meeting;
    final muted = _session?.isMuted ?? false;
    _formatSwitching = true;
    _edgeFormat = format;
    _resetCaptureMeter();
    if (mounted) {
      setState(() => _status = 'edge-format');
    }
    try {
      await _echo?.dispose();
      _echo = null;
      await _manager.cameraPreview?.stop();
      await _session?.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _session = null;
        _phase = _HarnessPhase.idle;
      });
      await _applyStart(
        await _startForPhase(meeting: meeting),
        meeting: meeting,
      );
      if (muted) {
        _session?.mute();
      }
    } finally {
      _formatSwitching = false;
    }
  }

  Future<void> _enterLobby() async {
    if (_phase != _HarnessPhase.idle || _starting) {
      return;
    }
    _starting = true;
    if (mounted) {
      setState(() {});
    }
    try {
      await _applyStart(await _startForPhase(meeting: false), meeting: false);
    } finally {
      _starting = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _joinMeeting() async {
    final lobby = _session;
    if (lobby == null) {
      return;
    }
    final settings = lobby.settings;
    final muted = lobby.isMuted;
    setState(() => _status = 'joining');
    await _echo?.dispose();
    await _manager.cameraPreview?.stop();
    await lobby.stop();
    if (!mounted) {
      return;
    }
    try {
      await _applyStart(
        await _manager.start(
          settings: settings,
          purpose: 'meeting',
          captureFormat: _edgeFormat,
          playbackFormat: _edgeFormat,
        ),
        meeting: true,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _session = null;
          _echo = null;
          _status = 'join-failed';
          _phase = _HarnessPhase.idle;
        });
      }
      return;
    }
    final meeting = _session;
    if (muted && meeting != null) {
      meeting.mute();
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _applyStart(StartResult result, {required bool meeting}) async {
    if (!mounted) {
      return;
    }
    switch (result) {
      case StartReady(:final session):
        _bind(session, meeting: meeting);
      case StartDenied():
        setState(() {
          _status = 'denied';
          _phase = _HarnessPhase.idle;
        });
      case StartRestricted():
        setState(() {
          _status = 'restricted';
          _phase = _HarnessPhase.idle;
        });
      case StartUnavailable():
        setState(() {
          _status = 'unavailable';
          _phase = _HarnessPhase.idle;
        });
      case StartAlreadyActive():
        setState(() => _status = 'alreadyActive');
      case StartFailed():
        setState(() {
          _status = 'failed';
          _phase = _HarnessPhase.idle;
        });
    }
  }

  void _bind(Session session, {required bool meeting}) {
    _session = session;
    _phase = meeting ? _HarnessPhase.meeting : _HarnessPhase.lobby;
    _audioOpen = false;
    _cameraOpen = false;
    _status = session.status.code.name;
    _isolation = session.lastIsolation;
    _diagnostics = session.diagnostics;
    if (meeting) {
      final echo = EchoTransport(session, replay: false);
      _echo = echo;
      unawaited(echo.attach());
      final webrtc = WebrtcVideoSink();
      _webrtc = webrtc;
      webrtc.attach(session);
      _webRtcLoopback.inboundChanged = () {
        if (mounted) {
          setState(() {});
        }
      };
      _webrtcSub = webrtc.localVideos.listen((track) {
        unawaited(_webRtcLoopback.applySendTrack(track));
        if (mounted) {
          setState(() {});
        }
      });
    }
    session.isolation.listen((event) {
      if (mounted) {
        setState(() => _isolation = event);
      }
    });
    session.coverage.listen((event) {
      if (mounted) {
        setState(() => _coverage = event);
      }
    });
    session.statuses.listen((status) {
      if (mounted) {
        setState(() {
          _status = status.code.name;
          _diagnostics = session.diagnostics;
        });
      }
    });
    session.screenSourceCatalog.listen((sources) {
      if (mounted) {
        setState(() => _screenSources = sources);
      }
    }, onError: (_) {});
    session.videoSurfaces.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
    session.capture.listen((bytes) {
      if (!mounted) {
        return;
      }
      _level = _rms(bytes);
      _levels.add(_level);
      if (_levels.length > 48) {
        _levels.removeAt(0);
      }
      _diagnostics = session.diagnostics;
      _lastCaptureFrameBytes = bytes.length;
      final now = DateTime.now();
      _captureWindowStart ??= now;
      _captureByteWindow += bytes.length;
      final elapsed = now.difference(_captureWindowStart!).inMilliseconds;
      if (elapsed >= 1000) {
        _captureBytesPerSecond = (_captureByteWindow * 1000 / elapsed).round();
        debugPrint(
          '[fac-edge] bps=$_captureBytesPerSecond last=${bytes.length} '
          'edge=${session.captureFormat} '
          'native=${session.diagnostics.nativeCaptureFormat} '
          'path=${session.diagnostics.captureConversionPath.name}',
        );
        _captureByteWindow = 0;
        _captureWindowStart = now;
      }
      if (_waveScheduled) {
        return;
      }
      _waveScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _waveScheduled = false;
        if (mounted) {
          _wave.value++;
          setState(() {});
        }
      });
    });
    setState(() {});
    unawaited(_loadEndpoints());
  }

  Future<void> _stop() async {
    final sub = _webrtcSub;
    _webrtcSub = null;
    unawaited(sub?.cancel());
    _webrtc?.detach();
    await _webRtcLoopback.dispose();
    await _echo?.dispose();
    await _manager.cameraPreview?.stop();
    await _session?.stop();
    // Keep catalog observation while the settings page stays mounted (#88).
    if (mounted) {
      setState(() {
        _session = null;
        _echo = null;
        _webrtc = null;
        _proof = null;
        _status = null;
        _diagnostics = null;
        _phase = _HarnessPhase.idle;
        _pipeline.clear();
        _levels.clear();
        _level = 0;
        _wave.value++;
        _indicatedScreenId = null;
        _screenStatus = null;
        _audioOpen = false;
        _cameraOpen = false;
      });
      _resetCaptureMeter();
    }
  }

  bool get _osPickerCatalog =>
      _screenSources.length == 1 &&
      _screenSources.first.kind == ScreenSourceKind.systemPicker;

  Future<void> _startScreenSession() async {
    if (_phase != _HarnessPhase.idle) {
      return;
    }
    await _applyStart(await _startForPhase(meeting: true), meeting: true);
  }

  Future<void> _openSharePicker(Session session) async {
    if (_osPickerCatalog) {
      await _shareScreen(session);
      return;
    }
    await session.beginScreenPick();
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Share'),
              content: SharePicker(
                sources: [
                  for (final source in _screenSources)
                    if (source.kind != ScreenSourceKind.systemPicker) source,
                ],
                includeSound: _includeSound,
                motion: _screenMotion,
                cursor: _screenCursor,
                indicatedId: _indicatedScreenId,
                onIncludeSound: (value) {
                  setState(() => _includeSound = value);
                  setDialogState(() {});
                },
                onMotion: (value) {
                  setState(() => _screenMotion = value);
                  setDialogState(() {});
                },
                onCursor: (value) {
                  setState(() => _screenCursor = value);
                  setDialogState(() {});
                },
                previewBuilder: (source) => screenPreviewThumb(session, source),
                onPick: (id) {
                  Navigator.of(dialogContext).pop();
                  unawaited(_shareScreen(session, sourceId: id));
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _shareScreen(Session session, {String? sourceId}) async {
    if (_phase != _HarnessPhase.meeting) {
      setState(() => _screenStatus = 'blocked');
      return;
    }
    if (sourceId != null) {
      _indicatedScreenId = sourceId;
    }
    final resolvedId =
        _indicatedScreenId ??
        (_osPickerCatalog
            ? _screenSources.first.id
            : _screenSources
                  .where(
                    (source) => source.kind != ScreenSourceKind.systemPicker,
                  )
                  .firstOrNull
                  ?.id);
    if (resolvedId == null) {
      setState(() => _screenStatus = 'none');
      return;
    }
    if (!_osPickerCatalog) {
      await session.beginScreenPick();
      await session.indicateScreenSource(resolvedId);
    }
    final result = await session.startScreenShare(
      resolvedId,
      includeSystemAudio: _includeSound,
      cursor: _screenCursor,
      motion: _screenMotion,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _screenStatus = switch (result) {
        ScreenShareReady() => 'sharing',
        ScreenShareDenied() => 'denied',
        ScreenShareRestricted() => 'restricted',
        ScreenShareBlocked() => 'blocked',
        ScreenShareUnavailable() => 'unavailable',
        ScreenShareFailed() => 'failed',
      };
    });
  }

  Future<void> _stopScreenShare(Session session) async {
    await session.stopScreenShare();
    if (mounted) {
      setState(() => _screenStatus = 'stopped');
    }
  }

  Future<void> _setProcessor(VideoProcessor processor) async {
    debugPrint('[fac-processor] set $processor');
    final session = _session;
    final preview = _manager.cameraPreview;
    ProcessorSetResult? result;
    if (session != null) {
      result = await session.setVideoProcessor(processor);
    }
    if (preview != null) {
      final previewResult = await preview.setVideoProcessor(processor);
      result ??= previewResult;
    }
    debugPrint(
      '[fac-processor] result=$result session=${session != null} '
      'preview=${preview != null} processor=$processor',
    );
    if (mounted) {
      setState(() {});
    }
  }

  void _toggleAudio() {
    setState(() {
      _audioOpen = !_audioOpen;
      if (_audioOpen) {
        _cameraOpen = false;
      }
    });
  }

  void _toggleCamera() {
    setState(() {
      _cameraOpen = !_cameraOpen;
      if (_cameraOpen) {
        _audioOpen = false;
      }
    });
  }

  void _closeFlyouts() {
    if (!_audioOpen && !_cameraOpen) {
      return;
    }
    setState(() {
      _audioOpen = false;
      _cameraOpen = false;
    });
  }

  void _toggleMute() {
    final session = _session;
    if (session == null) {
      return;
    }
    if (session.isMuted) {
      session.unmute();
    } else {
      session.mute();
    }
    setState(() {});
  }

  Future<void> _toggleCameraEnabled() async {
    final session = _session;
    if (session == null) {
      return;
    }
    final enable = !session.isCameraEnabled;
    if (enable) {
      final previewId = _manager.cameraPreview?.selectedCameraId;
      await _manager.cameraPreview?.stop();
      await session.setCameraEnabled(true);
      if (previewId != null && previewId != session.selectedCameraId) {
        await session.selectCamera(previewId);
      }
    } else {
      await session.setCameraEnabled(false);
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _toggleMuteVideo() async {
    final session = _session;
    if (session == null) {
      return;
    }
    if (session.isVideoMuted) {
      await session.unmuteVideo();
    } else {
      await session.muteVideo();
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _selectEndpoint(Endpoint endpoint) async {
    final session = _session;
    if (session == null) {
      _store.preferEndpoint(endpoint, _endpoints);
      _draft = _store.endpoints;
      await _manager.bindPreference(_store.endpoints);
      if (mounted) {
        setState(() {});
      }
      return;
    }
    try {
      await session.select(
        captureId: endpoint.isCapture ? endpoint.id : null,
        renderId: endpoint.isCapture ? null : endpoint.id,
      );
    } on Object {
      // Platform select can fail; keep the live diagnostics.
    }
    if (mounted) {
      setState(() => _diagnostics = session.diagnostics);
    }
  }

  Future<void> _pickCamera(String? id) async {
    final session = _session;
    if (id == null) {
      if (session != null) {
        await session.setCameraEnabled(false);
      }
      if (mounted) {
        setState(() {});
      }
      return;
    }
    if (session == null) {
      _store.preferCamera(id);
      _manager.bindCameraPreference(_store.cameras);
      if (mounted) {
        setState(() {});
      }
      return;
    }
    final preview = _manager.cameraPreview;
    if (preview != null) {
      await preview.selectCamera(id);
      if (mounted) {
        setState(() {});
      }
      return;
    }
    if (!session.isCameraEnabled) {
      await session.setCameraEnabled(true);
    }
    await session.selectCamera(id);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _startCameraPreview() async {
    _manager.bindCameraPreference(_store.cameras);
    final cameras = await _manager.cameras();
    await _manager.startCameraPreview(
      cameraId: _store.cameras.resolve(cameras)?.id,
    );
    if (mounted) {
      setState(() {});
    }
  }

  String? _idleSelectedId({required bool capture}) {
    for (final endpoint in _endpoints) {
      if (endpoint.isCapture == capture && _idlePreferredEndpoint(endpoint)) {
        return endpoint.id;
      }
    }
    return null;
  }

  String? get _selectedCameraId {
    final session = _session;
    if (session == null) {
      return _store.cameras.resolve(_cameras)?.id;
    }
    return _manager.cameraPreview?.selectedCameraId ?? session.selectedCameraId;
  }

  bool get _cameraEnabled {
    final session = _session;
    if (_manager.cameraPreview != null) {
      return true;
    }
    return session != null && session.isCameraEnabled;
  }

  Widget _audioPanel() {
    final session = _session;
    return AudioDevicePanel(
      catalog: _endpoints,
      preference: _store.endpoints,
      selectedCaptureId:
          session?.selectedCaptureId ?? _idleSelectedId(capture: true),
      selectedRenderId:
          session?.selectedRenderId ?? _idleSelectedId(capture: false),
      onSelectEndpoint: _selectEndpoint,
    );
  }

  Widget _cameraPanel() {
    final session = _session;
    final processor =
        session?.videoProcessor ?? _manager.cameraPreview?.videoProcessor;
    return CameraDevicePanel(
      cameras: _cameras,
      selectedCameraId: _selectedCameraId,
      cameraEnabled: _cameraEnabled,
      videoMuted: session?.isVideoMuted ?? false,
      onSelectCamera: _pickCamera,
      processor: processor,
      onProcessor: session != null || _manager.cameraPreview != null
          ? _setProcessor
          : null,
      replaceStill: _replaceStill ?? const [],
      onMuteVideo: _phase == _HarnessPhase.meeting ? _toggleMuteVideo : null,
      onCameraPreview: session != null && !session.isCameraEnabled
          ? _startCameraPreview
          : null,
    );
  }

  Widget _audioSplit() {
    final session = _session;
    return SplitCallButton(
      actionKey: const Key('mute'),
      menuKey: const Key('audio-pick'),
      icon: session?.isMuted == true ? Icons.mic_off : Icons.mic,
      tooltip: session?.isMuted == true ? 'Unmute' : 'Mute',
      menuTooltip: 'Choose microphone and speaker',
      active: session?.isMuted == true,
      menuOpen: _audioOpen,
      enabled: session != null,
      onAction: session == null ? null : _toggleMute,
      onMenu: _toggleAudio,
    );
  }

  Widget _cameraSplit() {
    final enabled = _cameraEnabled;
    return SplitCallButton(
      actionKey: const Key('camera-off'),
      menuKey: const Key('camera-pick'),
      icon: enabled ? Icons.videocam : Icons.videocam_off,
      tooltip: enabled ? 'Camera off' : 'Camera on',
      menuTooltip: 'Choose camera and background',
      active: !enabled,
      menuOpen: _cameraOpen,
      enabled: _session != null,
      onAction: _session == null ? null : _toggleCameraEnabled,
      onMenu: _toggleCamera,
    );
  }

  Future<void> _prove() async {
    final session = _session;
    if (session == null) {
      return;
    }
    final proof = await const LoopbackProbe().live(session: session);
    if (mounted) {
      setState(() => _proof = proof);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final isolation = _isolation ?? session?.lastIsolation;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Communications'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(_coverage.level.name, key: const Key('coverage')),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (isolation != null)
            IsolationBanner(
              event: isolation,
              onOpen: () => session?.openIsolationSettings(),
            ),
          if (_phase == _HarnessPhase.meeting && session != null) ...[
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: LoopbackMeetingStage(
                      key: const Key('meeting'),
                      session: session,
                      webrtcTrackId: _webrtc?.localVideo?.id ?? 'none',
                      inbound: _webRtcLoopback.inboundView(),
                    ),
                  ),
                  if (_audioOpen || _cameraOpen)
                    Positioned.fill(
                      child: GestureDetector(
                        key: const Key('flyout-dismiss'),
                        behavior: HitTestBehavior.opaque,
                        onTap: _closeFlyouts,
                      ),
                    ),
                  if (_audioOpen) MeetingChrome.overlaySheet(_audioPanel()),
                  if (_cameraOpen) MeetingChrome.overlaySheet(_cameraPanel()),
                ],
              ),
            ),
            MeetingBar(
              session: session,
              audioOpen: _audioOpen,
              cameraOpen: _cameraOpen,
              onMute: _toggleMute,
              onCamera: _toggleCameraEnabled,
              onAudioMenu: _toggleAudio,
              onCameraMenu: _toggleCamera,
              onShare: () => _openSharePicker(session),
              onStopShare: () => _stopScreenShare(session),
              onPause: () async {
                if (session.isPaused) {
                  await session.resume();
                } else {
                  await session.pause();
                }
                setState(() {});
              },
              onLeave: _stop,
              onProve: _prove,
            ),
          ] else
            Expanded(
              flex: 3,
              child: LobbyStage(
                selfView: _selfView(session),
                audioButton: _audioSplit(),
                cameraButton: _cameraSplit(),
                audioPanel: _audioOpen ? _audioPanel() : null,
                cameraPanel: _cameraOpen ? _cameraPanel() : null,
                onDismissFlyouts: _closeFlyouts,
                onEnter: _enterLobby,
                onJoin: _joinMeeting,
                onLeave: _stop,
                canEnter: _phase == _HarnessPhase.idle && !_starting,
                canJoin: _phase == _HarnessPhase.lobby,
                canLeave: _phase == _HarnessPhase.lobby,
              ),
            ),
          if (session != null) ...[
            _waveStrip(height: 40),
            if (_proof != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'echo ${_proof!.bytes} B'
                  '${_proof!.identical ? ' identical' : ' mismatch'}'
                  '${_proof!.clipped ? ' clipped' : ''}'
                  '${_proof!.sameCaptureStream ? '' : ' stream-replaced'}',
                  key: const Key('echo-proof'),
                ),
              ),
          ],
          Expanded(
            child: ListView(
              key: const Key('diagnostics'),
              scrollCacheExtent: ScrollCacheExtent.pixels(4000),
              padding: const EdgeInsets.all(20),
              children: _harnessChildren(context, session, isolation),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _harnessChildren(
    BuildContext context,
    Session? session,
    IsolationEvent? isolation,
  ) {
    final failure = startFailureCopy(_status);
    final isolationRequired = isolation?.state == IsolationState.required;
    final theme = Theme.of(context).textTheme;
    final diagnostics = _diagnostics ?? session?.diagnostics;
    return [
      Text('Diagnostics', style: theme.titleMedium),
      if (session != null) ...[
        ListTile(
          key: const Key('edge-format-24k'),
          title: const Text('PCM16 24 kHz'),
          subtitle: Text(
            _edgeFormat == AudioFormat.pcm16le24k
                ? '${diagnostics?.captureConversionPath.name ?? ''} '
                      '${diagnostics?.edgeCaptureFormat ?? ''}'
                : 'OpenAI Realtime',
          ),
          selected: _edgeFormat == AudioFormat.pcm16le24k,
          onTap: () => unawaited(_applyEdgeFormat(AudioFormat.pcm16le24k)),
        ),
        ListTile(
          key: const Key('edge-format-16k'),
          title: const Text('PCM16 16 kHz'),
          subtitle: Text(
            _edgeFormat == _pcm16le16k
                ? '${diagnostics?.captureConversionPath.name ?? ''} '
                      '${diagnostics?.edgeCaptureFormat ?? ''}'
                : 'Grok Speech-to-Speech',
          ),
          selected: _edgeFormat == _pcm16le16k,
          onTap: () => unawaited(_applyEdgeFormat(_pcm16le16k)),
        ),
        Text('$_lastCaptureFrameBytes', key: const Key('capture-bytes')),
        Text('$_captureBytesPerSecond', key: const Key('capture-bps')),
      ],
      const SizedBox(height: 8),
      Text(
        _status ?? 'idle',
        key: const Key('status'),
        style: theme.labelLarge,
      ),
      if (failure != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(failure, key: const Key('permission-copy')),
        ),
      if (session != null)
        Text(
          'Isolation ${(session.lastIsolation.state.name)}',
          key: const Key('isolation'),
        ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _pipelineKeys(session),
      ),
      if (_screenStatus != null)
        Text(
          _screenStatus!,
          key: const Key('screen-status'),
          style: theme.labelLarge,
        ),
      if (_phase == _HarnessPhase.idle)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: FilledButton.tonal(
            key: const Key('screen-session'),
            onPressed: _startScreenSession,
            child: const Text('Start session'),
          ),
        ),
      if (session != null) ...[
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            title: const Text('Isolation settings'),
            subtitle: Text((_isolation ?? session.lastIsolation).state.name),
            trailing: TextButton(
              key: isolationRequired ? null : const Key('open-isolation'),
              onPressed: () => session.openIsolationSettings(),
              child: const Text('Open'),
            ),
          ),
        ),
      ],
      const SizedBox(height: 16),
      Text('Host preference', style: theme.titleMedium),
      PreferenceEditor(
        catalog: _endpoints,
        draft: _draft,
        onChanged: (preference) => setState(() => _draft = preference),
        onApply: _applyPreference,
        onReset: () {
          _draft = const EndpointPreference();
          unawaited(_applyPreference());
        },
        onUseCurrent: session == null ? null : _useCurrent,
      ),
    ];
  }

  Widget _waveStrip({required double height}) {
    return SizedBox(
      key: const Key('visualizer'),
      height: height,
      child: ValueListenableBuilder<int>(
        valueListenable: _wave,
        builder: (context, _, _) {
          return CustomPaint(
            painter: _WavePainter(List<double>.of(_levels), _level),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }

  Widget _selfView(Session? session) {
    final preview = _manager.cameraPreview;
    if (preview != null) {
      return VideoSurfaceView(
        surface: preview.surface,
        viewTypePrefix: 'fac-camera',
        followUiOrientation: true,
      );
    }
    final surface = session?.videoSurface;
    if (session == null ||
        !session.cameraSend ||
        !session.isCameraEnabled ||
        session.isVideoMuted ||
        surface == null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: const Color(0xFF111118),
          child: Center(
            child: Text(
              session?.videoUnavailableReason ?? 'Camera off',
              style: const TextStyle(color: Color(0xFFB0B0C0)),
            ),
          ),
        ),
      );
    }
    return VideoSurfaceView(
      surface: surface,
      viewTypePrefix: 'fac-camera',
      followUiOrientation: true,
    );
  }

  List<Widget> _pipelineKeys(Session? session) {
    final diagnostics = _diagnostics ?? session?.diagnostics;
    if (session == null || diagnostics == null) {
      return const [];
    }
    return [
      const SizedBox(height: 8),
      Text(
        '${session.direction.name} ${session.purpose ?? ''}'.trim(),
        key: const Key('direction'),
      ),
      Text(session.status.code.name, key: const Key('status-code')),
      Text(session.status.severity.name, key: const Key('status-severity')),
      Text(
        session.status.recoverability.name,
        key: const Key('status-recoverability'),
      ),
      Text(session.status.usability.name, key: const Key('status-usability')),
      Text(session.status.action.name, key: const Key('status-action')),
      Text('${session.status.attempt}', key: const Key('status-attempt')),
      Text(
        '${session.status.maxAttempts}',
        key: const Key('status-max-attempts'),
      ),
      Text('${diagnostics.selectionGeneration}', key: const Key('generation')),
      Text(
        diagnostics.desired.captureId ?? '',
        key: const Key('desired-capture'),
      ),
      Text(
        diagnostics.desired.renderId ?? '',
        key: const Key('desired-render'),
      ),
      Text(
        diagnostics.applied.captureId ?? '',
        key: const Key('applied-capture'),
      ),
      Text(
        diagnostics.applied.renderId ?? '',
        key: const Key('applied-render'),
      ),
      Text(
        diagnostics.observed.captureId ?? '',
        key: const Key('observed-capture'),
      ),
      Text(
        diagnostics.observed.renderId ?? '',
        key: const Key('observed-render'),
      ),
      Text(
        '${diagnostics.preferenceControlled}',
        key: const Key('preference-controlled'),
      ),
      Text(
        '${diagnostics.desired.captureOverride}',
        key: const Key('desired-capture-override'),
      ),
      Text(
        '${diagnostics.desired.renderOverride}',
        key: const Key('desired-render-override'),
      ),
      Text(
        '${diagnostics.captureFrameCount}',
        key: const Key('capture-frames'),
      ),
      Text('${diagnostics.recentRms ?? 0}', key: const Key('capture-rms')),
      Text(
        '${diagnostics.playbackAccepted}/${diagnostics.playbackQueued}/'
        '${diagnostics.playbackRendered}/${diagnostics.playbackFlushed}',
        key: const Key('playback-progress'),
      ),
      Text(
        diagnostics.edgeCaptureFormat?.toString() ?? '',
        key: const Key('edge-capture-format'),
      ),
      Text(
        diagnostics.nativeCaptureFormat?.toString() ?? '',
        key: const Key('native-capture-format'),
      ),
      Text(
        diagnostics.captureConversionPath.name,
        key: const Key('capture-conversion-path'),
      ),
      Text(
        diagnostics.edgePlaybackFormat?.toString() ?? '',
        key: const Key('edge-playback-format'),
      ),
      Text(
        diagnostics.nativePlaybackFormat?.toString() ?? '',
        key: const Key('native-playback-format'),
      ),
      Text(
        diagnostics.playbackConversionPath.name,
        key: const Key('playback-conversion-path'),
      ),
      Text(
        diagnostics.acousticProfile?.family.name ?? '',
        key: const Key('acoustic-profile'),
      ),
      Text(
        '${diagnostics.baselineStep ?? ''}',
        key: const Key('baseline-step'),
      ),
      Text(
        diagnostics.captureProcessor?.toString() ?? '',
        key: const Key('capture-processor'),
      ),
      Text('${diagnostics.activeFloor ?? ''}', key: const Key('active-floor')),
      Text(
        diagnostics.profileConfidence?.name ?? '',
        key: const Key('profile-confidence'),
      ),
      Text(_pipeline.join('\n'), key: const Key('pipeline-log')),
    ];
  }
}

double _rms(Uint8List bytes) {
  if (bytes.length < 2) {
    return 0;
  }
  final data = ByteData.sublistView(bytes);
  var sum = 0.0;
  final n = bytes.length ~/ 2;
  for (var i = 0; i < n; i++) {
    final s = data.getInt16(i * 2, Endian.little) / 32768.0;
    sum += s * s;
  }
  return math.sqrt(sum / n);
}

final class _WavePainter extends CustomPainter {
  _WavePainter(this.levels, this.level);

  final List<double> levels;
  final double level;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF8B7CFF)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    if (levels.isEmpty) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint..color = paint.color.withValues(alpha: 0.3),
      );
      return;
    }
    final dx = size.width / math.max(levels.length - 1, 1);
    final path = Path();
    for (var i = 0; i < levels.length; i++) {
      final x = i * dx;
      final y = size.height / 2 - levels[i] * size.height * 2;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint..style = PaintingStyle.stroke);
    canvas.drawCircle(
      Offset(size.width - 8, size.height / 2 - level * size.height * 2),
      4,
      Paint()..color = const Color(0xFF5B4BFF),
    );
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) =>
      oldDelegate.level != level || oldDelegate.levels.length != levels.length;
}
