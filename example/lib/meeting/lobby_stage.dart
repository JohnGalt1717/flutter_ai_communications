import 'package:flutter/material.dart';

import 'chrome.dart';

/// Teams / Zoom-style pre-join lobby: large self-view, device splits, Join.
final class LobbyStage extends StatelessWidget {
  /// Creates the lobby stage.
  const LobbyStage({
    super.key,
    required this.selfView,
    required this.audioButton,
    required this.cameraButton,
    required this.onEnter,
    required this.onJoin,
    required this.onLeave,
    this.audioPanel,
    this.cameraPanel,
    this.canEnter = false,
    this.canJoin = false,
    this.canLeave = false,
    this.status,
    this.onDismissFlyouts,
  });

  /// Camera self-view. Must not live inside a [ListView].
  final Widget selfView;

  /// Mic split control.
  final Widget audioButton;

  /// Camera split control.
  final Widget cameraButton;

  /// Device panel opened from the mic chevron.
  final Widget? audioPanel;

  /// Device panel opened from the camera chevron.
  final Widget? cameraPanel;

  /// Idle → lobby Session.
  final VoidCallback onEnter;

  /// Lobby → meeting Session.
  final VoidCallback onJoin;

  /// Leave lobby.
  final VoidCallback onLeave;

  /// Enter lobby is enabled.
  final bool canEnter;

  /// Join is enabled.
  final bool canJoin;

  /// Leave is enabled.
  final bool canLeave;

  /// Optional status line under the preview.
  final String? status;

  /// Closes the audio or camera picker. Join stays outside this stack.
  final VoidCallback? onDismissFlyouts;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('lobby'),
      color: MeetingChrome.background,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: const Color(0xFF111118),
                      child: KeyedSubtree(
                        key: const Key('self-view'),
                        child: selfView,
                      ),
                    ),
                    const Positioned(
                      left: 16,
                      bottom: 14,
                      child: Text(
                        'You',
                        style: TextStyle(
                          color: MeetingChrome.foreground,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (audioPanel != null || cameraPanel != null)
                      Positioned.fill(
                        child: GestureDetector(
                          key: const Key('flyout-dismiss'),
                          behavior: HitTestBehavior.opaque,
                          onTap: onDismissFlyouts,
                        ),
                      ),
                    if (audioPanel != null)
                      MeetingChrome.overlaySheet(audioPanel!),
                    if (cameraPanel != null)
                      MeetingChrome.overlaySheet(cameraPanel!),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                audioButton,
                cameraButton,
                FilledButton(
                  key: const Key('lobby-enter'),
                  onPressed: canEnter ? onEnter : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: MeetingChrome.join,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 16,
                    ),
                  ),
                  child: const Text('Enter lobby'),
                ),
                FilledButton(
                  key: const Key('lobby-join'),
                  onPressed: canJoin ? onJoin : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: MeetingChrome.join,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 16,
                    ),
                  ),
                  child: const Text('Join'),
                ),
                OutlinedButton(
                  key: const Key('lobby-leave'),
                  onPressed: canLeave ? onLeave : null,
                  child: const Text('Leave'),
                ),
              ],
            ),
          ),
          if (status != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                status!,
                style: const TextStyle(color: MeetingChrome.dim, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
