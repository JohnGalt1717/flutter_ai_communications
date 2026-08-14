import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_ai_communications/flutter_ai_communications.dart';

/// Host Transport that echoes Session capture back through [Session.play].
///
/// The library does not own Transport. This is the Marionette / e2e
/// stand-in: fixture or live capture in, the same bytes out on play.
final class EchoTransport {
  /// Creates an echo Transport on [session].
  ///
  /// [replay] plays capture back. Leave it on for digital identity.
  /// Turn it off on a live device so the mic does not hear itself.
  EchoTransport(this.session, {this.replay = true});

  /// Live Session this Transport is attached to.
  final Session session;

  /// Whether received frames are sent to [Session.play].
  final bool replay;

  final BytesBuilder _received = BytesBuilder();
  StreamSubscription<Uint8List>? _sub;

  /// Capture bytes received on the current leg.
  Uint8List get received => _received.toBytes();

  /// Subscribes to [Session.capture] and plays each frame back.
  Future<void> attach() async {
    await _sub?.cancel();
    _sub = session.capture.listen((bytes) {
      _received.add(bytes);
      if (replay) {
        unawaited(session.play(bytes));
      }
    });
  }

  /// Starts a new identity leg after an Endpoint pick.
  void beginLeg() {
    _received.clear();
  }

  /// Detaches from the Session. Does not stop the Session.
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
