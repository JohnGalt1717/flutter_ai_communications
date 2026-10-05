import 'package:flutter/material.dart';

/// Shared Teams-like chrome for the example lobby and meeting.
abstract final class MeetingChrome {
  static const background = Color(0xFF0B0B10);
  static const bar = Color(0xFF16161F);
  static const button = Color(0xFF2B2B38);
  static const buttonActive = Color(0xFFE8E8F0);
  static const foreground = Color(0xFFE8E8F0);
  static const foregroundActive = Color(0xFF1C1C28);
  static const hangup = Color(0xFFC4314B);
  static const muted = Color(0xFFC4314B);
  static const panel = Color(0xFF1C1C28);
  static const border = Color(0xFF3A3A48);
  static const dim = Color(0xFFB0B0C0);
  static const join = Color(0xFF5B5FC7);

  /// Pins a device sheet inside the preview. Tall catalogs scroll instead of
  /// clipping the first Microphone rows off the top of a phone-sized stage.
  static Widget overlaySheet(Widget child) {
    return Positioned(
      left: 16,
      right: 16,
      top: 16,
      bottom: 16,
      child: Align(alignment: Alignment.bottomCenter, child: child),
    );
  }
}

/// Mic or camera control: tap the icon, open devices from the chevron.
final class SplitCallButton extends StatelessWidget {
  /// Creates a split in-call control.
  const SplitCallButton({
    super.key,
    required this.actionKey,
    required this.menuKey,
    required this.icon,
    required this.tooltip,
    required this.menuTooltip,
    required this.onAction,
    required this.onMenu,
    this.active = false,
    this.menuOpen = false,
    this.enabled = true,
  });

  /// Key on the mute / camera-off action.
  final Key actionKey;

  /// Key on the device-menu chevron.
  final Key menuKey;

  /// Action icon.
  final IconData icon;

  /// Tooltip for the action half.
  final String tooltip;

  /// Tooltip for the chevron.
  final String menuTooltip;

  /// Mute or camera-off.
  final VoidCallback? onAction;

  /// Opens the device panel.
  final VoidCallback onMenu;

  /// Latched / off appearance (muted, camera-off).
  final bool active;

  /// Chevron is showing its panel.
  final bool menuOpen;

  /// Whether the action half is enabled.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final background = active ? MeetingChrome.muted : MeetingChrome.button;
    final foreground = active
        ? Colors.white
        : enabled
        ? MeetingChrome.foreground
        : const Color(0xFF6E6E7A);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 48,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: tooltip,
              child: InkWell(
                key: actionKey,
                onTap: enabled ? onAction : null,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(24),
                ),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(icon, color: foreground),
                ),
              ),
            ),
            ColoredBox(
              color: foreground.withValues(alpha: 0.24),
              child: const SizedBox(width: 1, height: 22),
            ),
            Tooltip(
              message: menuTooltip,
              child: InkWell(
                key: menuKey,
                onTap: onMenu,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(24),
                ),
                child: SizedBox(
                  width: 32,
                  height: 48,
                  child: Icon(
                    menuOpen
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                    color: foreground,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round in-call button used for share, pause, prove, and leave.
final class RoundCallButton extends StatelessWidget {
  /// Creates a round in-call button.
  const RoundCallButton({
    super.key,
    required this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.danger = false,
  });

  /// Widget key.
  final Key buttonKey;

  /// Tooltip.
  final String tooltip;

  /// Icon.
  final IconData icon;

  /// Press handler.
  final VoidCallback? onPressed;

  /// Latched appearance.
  final bool active;

  /// Hang-up styling.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final background = danger
        ? MeetingChrome.hangup
        : active
        ? MeetingChrome.buttonActive
        : MeetingChrome.button;
    final foreground = danger
        ? Colors.white
        : active
        ? MeetingChrome.foregroundActive
        : MeetingChrome.foreground;
    return Tooltip(
      message: tooltip,
      child: IconButton.filled(
        key: buttonKey,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: MeetingChrome.button,
          disabledForegroundColor: const Color(0xFF6E6E7A),
        ),
        icon: Icon(icon),
      ),
    );
  }
}
