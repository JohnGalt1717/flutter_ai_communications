import 'package:flutter_ai_communications_linux/flutter_ai_communications_linux.dart';
import 'package:flutter_ai_communications_linux/src/camera_backend.dart';
import 'package:flutter_ai_communications_linux/src/linux_camera_facing.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const usb = CameraEndpoint(
    id: '/dev/video0',
    name: 'Logitech BRIO',
    facing: CameraFacing.external,
    modes: [VideoFormat(width: 1920, height: 1080, frameRate: 30)],
  );
  const integrated = CameraEndpoint(
    id: '/dev/video2',
    name: 'Integrated Camera',
    facing: CameraFacing.user,
    modes: [VideoFormat.defaultFormat],
  );

  FlutterAiCommunicationsLinux adapterFor(_RecordingCamera camera) {
    final adapter = FlutterAiCommunicationsLinux(camera: camera);
    addTearDown(adapter.stopCameraNative);
    return adapter;
  }

  test('external cameras appear in the catalog', () async {
    final camera = _RecordingCamera()..cameras = [usb, integrated];
    final catalog = await adapterFor(camera).enumerateCameras();
    expect(
      catalog.map((endpoint) => endpoint.facing),
      contains(CameraFacing.external),
    );
    expect(catalog.map((endpoint) => endpoint.id), contains('/dev/video0'));
  });

  test('USB bus_info is an external Camera Endpoint', () {
    expect(
      linuxCameraFacing(name: 'HD Webcam', busInfo: 'usb-0000:00:14.0-1'),
      CameraFacing.external,
    );
  });

  test('integrated name wins over USB bus_info', () {
    expect(
      linuxCameraFacing(
        name: 'Integrated Camera',
        busInfo: 'usb-0000:00:14.0-7',
      ),
      CameraFacing.user,
    );
  });

  test('permission denial is a typed result without starting capture', () async {
    final camera = _RecordingCamera()
      ..cameras = [usb]
      ..permission = CameraPermission.denied;
    final adapter = adapterFor(camera);
    expect(
      await adapter.requestCameraPermission(),
      CameraPermission.denied,
    );
    expect(camera.startCalls, 0);
  });

  test('start yields a Video surface and nearest Native Video Format', () async {
    final camera = _RecordingCamera()..cameras = [usb, integrated];
    final adapter = adapterFor(camera);
    expect(
      await adapter.startCameraNative(
        cameraId: '/dev/video0',
        videoFormat: VideoFormat.defaultFormat,
      ),
      NativeGraphStart.started,
    );
    expect(adapter.lastVideoSurface?.handle, 1);
    expect(adapter.lastVideoSurface?.kind, VideoSurfaceKind.texture);
    expect(
      adapter.lastNativeVideoFormat,
      const VideoFormat(width: 1920, height: 1080, frameRate: 30),
    );
  });

  test('missing camera is unavailable, not a failed Session graph', () async {
    final camera = _RecordingCamera();
    final adapter = adapterFor(camera);
    expect(
      await adapter.startCameraNative(cameraId: '/dev/video9'),
      NativeGraphStart.unavailable,
    );
    expect(adapter.lastVideoSurface, isNull);
  });

  test('Mute-video keeps the surface; Camera-off stops hardware', () async {
    final camera = _RecordingCamera()..cameras = [usb];
    final adapter = adapterFor(camera);
    await adapter.startCameraNative(cameraId: '/dev/video0');
    await adapter.setMuteVideoNative(true);
    expect(camera.muted, isTrue);
    expect(adapter.lastVideoSurface, isNotNull);
    await adapter.setCameraEnabledNative(false);
    expect(camera.enabled, isFalse);
    expect(adapter.lastVideoSurface, isNotNull);
  });

  test('selectCamera is ephemeral and uses the requested id', () async {
    final camera = _RecordingCamera()..cameras = [usb, integrated];
    final adapter = adapterFor(camera);
    await adapter.startCameraNative(cameraId: '/dev/video2');
    await adapter.selectCameraNative('/dev/video0');
    expect(camera.selectedId, '/dev/video0');
  });
}

final class _RecordingCamera implements CameraBackend {
  List<CameraEndpoint> cameras = const [];
  CameraPermission permission = CameraPermission.granted;
  var startCalls = 0;
  var enabled = true;
  var muted = false;
  String? selectedId;
  @override
  VideoSurface? lastSurface;
  @override
  VideoFormat? lastFormat;
  @override
  int frameCount = 0;
  @override
  int liveFrames = 0;

  @override
  Future<List<CameraEndpoint>> enumerate() async => cameras;

  @override
  Future<CameraPermission> requestPermission() async => permission;

  @override
  Future<NativeGraphStart> start({
    String? cameraId,
    VideoFormat? videoFormat,
    bool enabled = true,
    bool muted = false,
  }) async {
    startCalls++;
    final resolved =
        cameras.where((camera) => camera.id == cameraId).firstOrNull ??
        cameras.firstOrNull;
    if (resolved == null) {
      lastSurface = null;
      lastFormat = null;
      return NativeGraphStart.unavailable;
    }
    selectedId = resolved.id;
    this.enabled = enabled;
    this.muted = muted;
    const negotiator = VideoFormatNegotiator();
    lastFormat = negotiator.nearest(
      videoFormat ?? VideoFormat.defaultFormat,
      resolved.modes.isEmpty
          ? const [VideoFormat.defaultFormat]
          : resolved.modes,
    );
    lastSurface = const VideoSurface(handle: 1);
    return NativeGraphStart.started;
  }

  @override
  Future<void> stop() async {
    lastSurface = null;
    lastFormat = null;
  }

  @override
  Future<void> select(String cameraId) async {
    selectedId = cameraId;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    this.enabled = enabled;
  }

  @override
  Future<void> setMuted(bool muted) async {
    this.muted = muted;
  }

  @override
  Future<void> pollStats() async {}
}
