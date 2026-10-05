import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';
import 'package:flutter_ai_communications_example/camera_facing_caption.dart';

import 'chrome.dart';

/// Teams-style camera, blur, and background picker.
final class CameraDevicePanel extends StatelessWidget {
  /// Creates the camera device panel.
  const CameraDevicePanel({
    super.key,
    required this.cameras,
    required this.onSelectCamera,
    this.selectedCameraId,
    this.cameraEnabled = true,
    this.videoMuted = false,
    this.processor,
    this.onProcessor,
    this.replaceStill = const [],
    this.onMuteVideo,
    this.onCameraPreview,
  });

  /// Camera catalog.
  final List<CameraEndpoint> cameras;

  /// Selected Camera Endpoint id.
  final String? selectedCameraId;

  /// Whether the Session or preview is sending camera.
  final bool cameraEnabled;

  /// Mute-video latched.
  final bool videoMuted;

  /// None means Camera-off.
  final ValueChanged<String?> onSelectCamera;

  /// Current send-path Video processor.
  final VideoProcessor? processor;

  /// None / blur / replace.
  final ValueChanged<VideoProcessor>? onProcessor;

  /// Bundled still for replace.
  final List<int> replaceStill;

  /// Mute-video toggle. Null hides the control.
  final VoidCallback? onMuteVideo;

  /// Start Camera preview while Camera-off. Null hides the control.
  final VoidCallback? onCameraPreview;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final current = processor;
    return Material(
      key: const Key('camera-panel'),
      color: MeetingChrome.panel,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420, maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Text('Camera', style: textTheme.titleMedium),
              ),
              ListTile(
                key: const Key('camera-none'),
                leading: const Icon(Icons.videocam_off_outlined),
                title: const Text('None'),
                selected: !cameraEnabled,
                onTap: () => onSelectCamera(null),
              ),
              for (final camera in cameras)
                ListTile(
                  key: Key('camera-${camera.id}'),
                  leading: const Icon(Icons.videocam_outlined),
                  title: Text(camera.name),
                  subtitle: switch (cameraFacingCaption(camera.facing)) {
                    final caption? => Text(caption),
                    _ => null,
                  },
                  selected: cameraEnabled && camera.id == selectedCameraId,
                  onTap: () => onSelectCamera(camera.id),
                ),
              if (onMuteVideo != null)
                SwitchListTile(
                  key: const Key('mute-video'),
                  secondary: const Icon(Icons.video_camera_front_outlined),
                  title: const Text('Mute video'),
                  value: videoMuted,
                  onChanged: cameraEnabled ? (_) => onMuteVideo!() : null,
                ),
              if (onCameraPreview != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: OutlinedButton(
                    key: const Key('camera-preview'),
                    onPressed: cameraEnabled ? null : onCameraPreview,
                    child: const Text('Camera preview'),
                  ),
                ),
              if (onProcessor != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                  child: Text(
                    'Background',
                    key: const Key('processor-pick'),
                    style: textTheme.labelLarge,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _effectChip(
                        key: const Key('processor-none'),
                        label: 'None',
                        selected: current is NoneVideoProcessor,
                        icon: Icons.person_outline,
                        onTap: () => onProcessor!(const NoneVideoProcessor()),
                      ),
                      _effectChip(
                        key: const Key('processor-blur-50'),
                        label: 'Blur',
                        selected:
                            current == const BlurVideoProcessor(intensity: 50),
                        icon: Icons.blur_on,
                        onTap: () => onProcessor!(
                          const BlurVideoProcessor(intensity: 50),
                        ),
                      ),
                      _effectChip(
                        key: const Key('processor-blur-100'),
                        label: 'More blur',
                        selected:
                            current == const BlurVideoProcessor(intensity: 100),
                        icon: Icons.blur_circular,
                        onTap: () => onProcessor!(
                          const BlurVideoProcessor(intensity: 100),
                        ),
                      ),
                      _backgroundImageChip(current),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _backgroundImageChip(VideoProcessor? current) {
    final still = replaceStill;
    final selected = current is ReplaceVideoProcessor;
    return InkWell(
      key: const Key('processor-replace'),
      onTap: still.isEmpty
          ? null
          : () => onProcessor!(ReplaceVideoProcessor(bytes: still)),
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        width: 96,
        height: 72,
        decoration: BoxDecoration(
          color: MeetingChrome.button,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? MeetingChrome.buttonActive : MeetingChrome.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: still.isEmpty
            ? const Center(child: Icon(Icons.image_outlined))
            : ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(
                      Uint8List.fromList(still),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                    const Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 4),
                        child: Text(
                          'Image',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            shadows: [Shadow(blurRadius: 4)],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _effectChip({
    required Key key,
    required String label,
    required bool selected,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: FilterChip(
        label: Text(label),
        avatar: Icon(icon, size: 18),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}
