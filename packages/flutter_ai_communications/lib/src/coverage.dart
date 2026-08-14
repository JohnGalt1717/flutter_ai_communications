import 'dart:async';

/// Whether the Session can usefully continue.
enum CoverageLevel { ok, degraded, lost }

/// Why Coverage is not [CoverageLevel.ok].
enum CoverageReason { airplane, pathDead, hostReported, unknown }

/// Audio-path health plus host connectivity.
final class Coverage {
  /// Creates a Coverage snapshot.
  const Coverage({required this.level, this.reason, this.latency});

  /// Healthy path.
  const Coverage.ok() : level = CoverageLevel.ok, reason = null, latency = null;

  /// Path or host is degraded.
  const Coverage.degraded({this.reason = CoverageReason.unknown, this.latency})
    : level = CoverageLevel.degraded;

  /// Path or host is lost.
  const Coverage.lost({this.reason = CoverageReason.unknown, this.latency})
    : level = CoverageLevel.lost;

  /// Current level.
  final CoverageLevel level;

  /// Optional reason.
  final CoverageReason? reason;

  /// Optional latency sample.
  final Duration? latency;
}

/// Host-injected Coverage stream.
abstract interface class CoverageSource {
  /// Coverage updates.
  Stream<Coverage> get coverage;
}

/// Always reports [Coverage.ok].
final class AlwaysOkCoverageSource implements CoverageSource {
  /// Creates a source that never degrades.
  const AlwaysOkCoverageSource();

  @override
  Stream<Coverage> get coverage => Stream<Coverage>.value(const Coverage.ok());
}

/// Host-driven Coverage. Starts [Coverage.ok]; push airplane / hub loss here.
///
/// Does not measure RTT. Path death is merged in [Session] from the platform.
final class DefaultCoverageSource implements CoverageSource {
  /// Creates a host Coverage source.
  DefaultCoverageSource({Coverage initial = const Coverage.ok()})
    : _latest = initial;

  final StreamController<Coverage> _controller =
      StreamController<Coverage>.broadcast();
  Coverage _latest;

  /// Last value emitted.
  Coverage get latest => _latest;

  /// Reports a Coverage snapshot.
  void report(Coverage next) {
    _latest = next;
    _controller.add(next);
  }

  @override
  Stream<Coverage> get coverage async* {
    yield _latest;
    yield* _controller.stream;
  }

  /// Closes the source.
  Future<void> dispose() => _controller.close();
}
