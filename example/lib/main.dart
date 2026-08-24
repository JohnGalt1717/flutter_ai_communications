import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_ai_communications_example/echo/echo_transport.dart';
import 'package:flutter_ai_communications_example/echo/fixture_pcm.dart';
import 'package:flutter_ai_communications_example/echo/loopback_platform.dart';
import 'package:flutter_ai_communications_example/echo/loopback_probe.dart';
import 'package:logging/logging.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_logging/marionette_logging.dart';

void main() {
  _installMarionetteBinding();
  LoopbackCommunicationsPlatform.wrapRegistered();
  runApp(const ExampleApp());
}

/// Registers Marionette + `get_logs` in debug `flutter run` only.
///
/// Tests must not call this `main()`: [MarionetteBinding] is a
/// [WidgetsBinding] and cannot share a process with the test binding.
void _installMarionetteBinding() {
  if (kDebugMode) {
    hierarchicalLoggingEnabled = true;
    Logger.root.level = Level.INFO;
    Logger(PipelineLog.loggerName).level = Level.INFO;
    MarionetteBinding.ensureInitialized(
      MarionetteConfiguration(logCollector: LoggingLogCollector()),
    );
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();
}

/// Marionette harness that looks like an AI voice client.
final class ExampleApp extends StatelessWidget {
  /// Creates the example app.
  const ExampleApp({super.key, this.manager});

  /// Optional injected Audio manager (tests / Marionette).
  final AudioManager? manager;

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
      home: SessionPage(manager: manager ?? AudioManager()),
    );
  }
}

/// Live Session controls and capture visualizer.
final class SessionPage extends StatefulWidget {
  /// Creates the Session page.
  const SessionPage({super.key, required this.manager});

  /// Audio manager driving the Session.
  final AudioManager manager;

  @override
  State<SessionPage> createState() => _SessionPageState();
}

final class _SessionPageState extends State<SessionPage> {
  Session? _session;
  EchoTransport? _echo;
  EchoProof? _proof;
  String? _status;
  IsolationEvent? _isolation;
  Coverage _coverage = const Coverage.ok();
  double _level = 0;
  final _levels = <double>[];
  List<Endpoint> _endpoints = const [];
  SessionDiagnostics? _diagnostics;
  final _pipeline = <String>[];
  StreamSubscription<LogRecord>? _logSub;

  AudioManager get _manager => widget.manager;

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
    if (mounted) {
      setState(() => _endpoints = endpoints);
    }
  }

  Future<void> _start() async {
    final result = await _manager.start();
    if (!mounted) {
      return;
    }
    switch (result) {
      case StartReady(:final session):
        _bind(session);
      case StartDenied():
        setState(() => _status = 'denied');
      case StartRestricted():
        setState(() => _status = 'restricted');
      case StartUnavailable():
        setState(() => _status = 'unavailable');
      case StartAlreadyActive():
        setState(() => _status = 'alreadyActive');
      case StartFailed():
        setState(() => _status = 'failed');
    }
  }

  void _bind(Session session) {
    _session = session;
    _status = session.status.code.name;
    _isolation = session.lastIsolation;
    _diagnostics = session.diagnostics;
    final echo = EchoTransport(session, replay: false);
    _echo = echo;
    unawaited(echo.attach());
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
        title: const Text('Marionette'),
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
            session == null ? 'Ready when you are' : 'Live Session',
            style: Theme.of(context).textTheme.headlineSmall,
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _pipelineKeys(session),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 72,
            child: CustomPaint(
              painter: _WavePainter(_levels, _level),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                key: const Key('start'),
                onPressed: session == null ? _start : null,
                child: const Text('Start'),
              ),
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
              FilledButton.tonal(
                key: const Key('pause'),
                onPressed: session == null
                    ? null
                    : () async {
                        if (session.isPaused) {
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
                onPressed: session == null ? null : _stop,
                child: const Text('End'),
              ),
              FilledButton.tonal(
                key: const Key('prove'),
                onPressed: session == null ? null : _prove,
                child: const Text('Prove'),
              ),
            ],
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
