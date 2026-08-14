import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';

void main() {
  runApp(const ExampleApp());
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
  String? _status;
  IsolationEvent? _isolation;
  Coverage _coverage = const Coverage.ok();
  double _level = 0;
  final _levels = <double>[];
  List<Endpoint> _endpoints = const [];

  AudioManager get _manager => widget.manager;

  @override
  void initState() {
    super.initState();
    _loadEndpoints();
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
    _status = 'ready';
    _isolation = session.lastIsolation;
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
      });
    });
    setState(() {});
  }

  Future<void> _stop() async {
    await _session?.stop();
    if (mounted) {
      setState(() {
        _session = null;
        _status = null;
        _levels.clear();
        _level = 0;
      });
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
            ],
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
