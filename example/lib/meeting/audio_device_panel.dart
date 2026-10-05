import 'package:flutter/material.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';

import 'chrome.dart';

/// Teams-style microphone and speaker picker with Pair auto-selection.
final class AudioDevicePanel extends StatelessWidget {
  /// Creates the audio device panel.
  const AudioDevicePanel({
    super.key,
    required this.catalog,
    required this.onSelectEndpoint,
    this.preference = const EndpointPreference(),
    this.selectedCaptureId,
    this.selectedRenderId,
  });

  /// Live Endpoint catalog.
  final List<Endpoint> catalog;

  /// Host-persisted Endpoint preference. Empty uses OS default first.
  final EndpointPreference preference;

  /// Currently selected capture Endpoint id.
  final String? selectedCaptureId;

  /// Currently selected render Endpoint id.
  final String? selectedRenderId;

  /// Mic or speaker row. Capture-only keeps render; render-only re-pairs.
  final ValueChanged<Endpoint> onSelectEndpoint;

  @override
  Widget build(BuildContext context) {
    final captures = preference.orderedForDisplay(catalog, capture: true);
    final renders = preference.orderedForDisplay(catalog, capture: false);
    final textTheme = Theme.of(context).textTheme;
    return Material(
      key: const Key('audio-panel'),
      color: MeetingChrome.panel,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520, maxWidth: 420),
        child: SingleChildScrollView(
          key: const Key('audio-panel-scroll'),
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Text('Audio devices', style: textTheme.titleMedium),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Text('Microphone', style: textTheme.labelLarge),
              ),
              for (final endpoint in captures)
                _endpointTile(
                  endpoint,
                  selected: endpoint.id == selectedCaptureId,
                  icon: Icons.mic_none,
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Text('Speaker', style: textTheme.labelLarge),
              ),
              for (final endpoint in renders)
                _endpointTile(
                  endpoint,
                  selected: endpoint.id == selectedRenderId,
                  icon: Icons.volume_up_outlined,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _endpointTile(
    Endpoint endpoint, {
    required bool selected,
    required IconData icon,
  }) {
    return ListTile(
      key: Key('endpoint-${endpoint.id}'),
      leading: Icon(icon),
      title: Text(endpoint.name),
      subtitle: Text(endpoint.routeClass.name),
      trailing: endpoint.osDefault
          ? Text(
              'Default',
              key: Key('endpoint-default-${endpoint.id}'),
              style: const TextStyle(
                color: MeetingChrome.foreground,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
      selected: selected,
      onTap: () => onSelectEndpoint(endpoint),
    );
  }
}
