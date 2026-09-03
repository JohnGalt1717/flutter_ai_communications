import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_ai_communications_example/echo/echo_transport.dart';
import 'package:flutter_ai_communications_example/echo/fixture_pcm.dart';
import 'package:flutter_ai_communications_example/echo/loopback_platform.dart';
import 'package:flutter_ai_communications_example/echo/loopback_probe.dart';
import 'package:flutter_skill/flutter_skill.dart';
import 'package:logging/logging.dart';

void main() {
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
  runApp(ExampleApp(manager: CommunicationsManager()));
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
  FlutterSkillBinding.ensureInitialized();
}

enum _HarnessPhase { idle, lobby, meeting }

/// AI-voice harness that looks like a communications client.
///
/// Owns one application-scoped [CommunicationsManager]. Tests may inject a
/// manager; `main()` constructs one for the process lifetime.
final class ExampleApp extends StatefulWidget {
  /// Creates the example app.
  const ExampleApp({super.key, this.manager});

  /// Optional injected Communications manager (tests / agent harness).
  final CommunicationsManager? manager;

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

final class _ExampleAppState extends State<ExampleApp> {
  late final CommunicationsManager _manager =
      widget.manager ?? CommunicationsManager();

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
      home: SessionPage(manager: _manager),
    );
  }
}

/// Live Session controls and capture visualizer.
final class SessionPage extends StatefulWidget {
  /// Creates the Session page.
  const SessionPage({super.key, required this.manager});

  /// Communications manager driving the Session.
  final CommunicationsManager manager;

  @override
  State<SessionPage> createState() => _SessionPageState();
}

final class _SessionPageState extends State<SessionPage> {
  var _phase = _HarnessPhase.idle;
  Session? _session;
  EchoTransport? _echo;
  EchoProof? _proof;
  String? _status;
  IsolationEvent? _isolation;
  Coverage _coverage = const Coverage.ok();
  double _level = 0;
  final _levels = <double>[];
  List<Endpoint> _endpoints = const [];
  List<CameraEndpoint> _cameras = const [];
  SessionDiagnostics? _diagnostics;
  final _pipeline = <String>[];
  StreamSubscription<LogRecord>? _logSub;

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
    _loadEndpoints();
  }

  @override
  void dispose() {
    unawaited(_logSub?.cancel());
    unawaited(_session?.stop());
    super.dispose();
  }

  Future<void> _loadEndpoints() async {
    final endpoints = await _manager.endpoints();
    List<CameraEndpoint> cameras = const [];
    try {
      cameras = await _manager.cameras();
    } on Object {
      cameras = const [];
    }
    if (mounted) {
      setState(() {
        _endpoints = endpoints;
        _cameras = cameras;
      });
    }
  }

  Future<void> _enterLobby() async {
    await _applyStart(
      await _manager.start(purpose: 'lobby', cameraSend: true),
      meeting: false,
    );
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
    await lobby.stop();
    if (!mounted) {
      return;
    }
    try {
      await _applyStart(
        await _manager.start(settings: settings, purpose: 'meeting'),
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
    _status = session.status.code.name;
    _isolation = session.lastIsolation;
    _diagnostics = session.diagnostics;
    if (meeting) {
      final echo = EchoTransport(session, replay: false);
      _echo = echo;
      unawaited(echo.attach());
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
    session.capture.listen((bytes) {
      if (!mounted) {
        return;
      }
      setState(() {
        _level = _rms(bytes);
        _levels.add(_level);
        if (_levels.length > 48) {
          _levels.removeAt(0);
        }
        _diagnostics = session.diagnostics;
      });
    });
    setState(() {});
    unawaited(_loadEndpoints());
  }

  Future<void> _stop() async {
    await _echo?.dispose();
    await _session?.stop();
    if (mounted) {
      setState(() {
        _session = null;
        _echo = null;
        _proof = null;
        _status = null;
        _diagnostics = null;
        _phase = _HarnessPhase.idle;
        _pipeline.clear();
        _levels.clear();
        _level = 0;
      });
    }
  }

  Future<void> _prove() async {
    final session = _session;
    if (session == null) {
      return;
    }
    final fixture = FixturePcm.voiceBand24k();
    final proof = await const LoopbackProbe().echo(
      session: session,
      fixture: fixture,
    );
    if (mounted) {
      setState(() => _proof = proof);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
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
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            switch (_phase) {
              _HarnessPhase.idle => 'Lobby',
              _HarnessPhase.lobby => 'Lobby',
              _HarnessPhase.meeting => 'Live Session',
            },
            key: Key(_phase == _HarnessPhase.meeting ? 'meeting' : 'lobby'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            _phase == _HarnessPhase.meeting ? 'Meeting' : 'Pick devices, then Join. Permission is requested on Enter lobby.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            _status ?? 'idle',
            key: const Key('status'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          if (session != null)
            Text(
              'Isolation ${(session.lastIsolation.state.name)}',
              key: const Key('isolation'),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (_phase != _HarnessPhase.meeting) ...[
                FilledButton(
                  key: const Key('lobby-enter'),
                  onPressed: _phase == _HarnessPhase.idle ? _enterLobby : null,
                  child: const Text('Enter lobby'),
                ),
                FilledButton(
                  key: const Key('lobby-join'),
                  onPressed: _phase == _HarnessPhase.lobby
                      ? _joinMeeting
                      : null,
                  child: const Text('Join'),
                ),
                OutlinedButton(
                  key: const Key('lobby-leave'),
                  onPressed: _phase == _HarnessPhase.lobby ? _stop : null,
                  child: const Text('Leave'),
                ),
              ],
              FilledButton.tonal(
                key: const Key('mute'),
                onPressed: session == null
                    ? null
                    : () {
                        if (session.isMuted) {
                          session.unmute();
                        } else {
                          session.mute();
                        }
                        setState(() {});
                      },
                child: Text(session?.isMuted == true ? 'Unmute' : 'Mute'),
              ),
              if (_phase == _HarnessPhase.meeting) ...[
                FilledButton.tonal(
                  key: const Key('pause'),
                  onPressed: () async {
                    if (session!.isPaused) {
                      await session.resume();
                    } else {
                      await session.pause();
                    }
                    setState(() {});
                  },
                  child: Text(session?.isPaused == true ? 'Resume' : 'Pause'),
                ),
                OutlinedButton(
                  key: const Key('stop'),
                  onPressed: _stop,
                  child: const Text('End'),
                ),
                FilledButton.tonal(
                  key: const Key('prove'),
                  onPressed: _prove,
                  child: const Text('Prove'),
                ),
              ],
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _pipelineKeys(session),
          ),
          const SizedBox(height: 16),
          SizedBox(height: 220, child: _selfView(session)),
          const SizedBox(height: 12),
          SizedBox(
            height: 72,
            child: CustomPaint(
              painter: _WavePainter(_levels, _level),
              child: const SizedBox.expand(),
            ),
          ),
          if (_proof != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'echo ${_proof!.bytes} B'
                '${_proof!.identical ? ' identical' : ' mismatch'}'
                '${_proof!.clipped ? ' clipped' : ''}'
                '${_proof!.sameCaptureStream ? '' : ' stream-replaced'}',
                key: const Key('echo-proof'),
              ),
            ),
          const SizedBox(height: 24),
          if (_phase != _HarnessPhase.idle && session != null)
            Wrap(
              spacing: 12,
              children: [
                FilledButton.tonal(
                  key: const Key('camera-off'),
                  onPressed: () async {
                    await session.setCameraEnabled(!session.isCameraEnabled);
                    setState(() {});
                  },
                  child: Text(
                    session.isCameraEnabled ? 'Camera off' : 'Camera on',
                  ),
                ),
                if (_phase == _HarnessPhase.meeting)
                  FilledButton.tonal(
                    key: const Key('mute-video'),
                    onPressed: () async {
                      if (session.isVideoMuted) {
                        await session.unmuteVideo();
                      } else {
                        await session.muteVideo();
                      }
                      setState(() {});
                    },
                    child: Text(
                      session.isVideoMuted ? 'Unmute video' : 'Mute video',
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 16),
          Text('Cameras', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final camera in _cameras)
            ListTile(
              key: Key('camera-${camera.id}'),
              title: Text(camera.name),
              subtitle: Text(camera.facing.name),
              selected: camera.id == session?.selectedCameraId,
              onTap: session == null
                  ? null
                  : () async {
                      await session.selectCamera(camera.id);
                      setState(() {});
                    },
            ),
          Text('Endpoints', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final endpoint in _endpoints)
            ListTile(
              key: Key('endpoint-${endpoint.id}'),
              title: Text(endpoint.name),
              subtitle: Text(
                '${endpoint.routeClass.name} · ${endpoint.isCapture ? 'capture' : 'render'}',
              ),
              selected:
                  endpoint.id == session?.selectedCaptureId ||
                  endpoint.id == session?.selectedRenderId,
              onTap: session == null
                  ? null
                  : () => session.select(
                      captureId: endpoint.isCapture ? endpoint.id : null,
                      renderId: endpoint.isCapture ? null : endpoint.id,
                    ),
            ),
          if (session != null) ...[
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                title: const Text('Isolation settings'),
                subtitle: Text(
                  (_isolation ?? session.lastIsolation).state.name,
                ),
                trailing: TextButton(
                  key: const Key('open-isolation'),
                  onPressed: () => session.openIsolationSettings(),
                  child: const Text('Open'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _selfView(Session? session) {
    final surface = session?.videoSurface;
    if (session == null ||
        !session.cameraSend ||
        !session.isCameraEnabled ||
        session.isVideoMuted ||
        surface == null) {
      return ColoredBox(
        color: const Color(0xFF111118),
        child: Center(
          child: Text(
            session?.videoUnavailableReason ?? 'Camera off',
            key: const Key('self-view'),
            style: const TextStyle(color: Color(0xFFB0B0C0)),
          ),
        ),
      );
    }
    if (surface.kind == VideoSurfaceKind.htmlElement) {
      // Flutter web platform views overlay the glass pane if they are unmounted
      // or given percentage sizing. Keep a tight pixel box and clip it.
      return SizedBox(
        width: 320,
        height: 220,
        child: ClipRect(
          child: HtmlElementView(
            key: const Key('self-view'),
            viewType: 'fac-camera-${surface.handle}',
          ),
        ),
      );
    }
    return Texture(key: const Key('self-view'), textureId: surface.handle);
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
      Text(session.status.severity.name, key: const Key('status-severity')),
      Text(session.status.action.name, key: const Key('status-action')),
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
