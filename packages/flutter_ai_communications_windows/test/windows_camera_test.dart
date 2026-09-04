import 'package:flutter/services.dart';
import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_ai_communications_windows/flutter_ai_communications_windows.dart';
import 'package:flutter_ai_communications_windows/src/camera_backend.dart';
import 'package:flutter_ai_communications_windows/src/camera_channel.dart';
import 'package:flutter_ai_communications_windows/src/windows_camera_consent.dart';
import 'package:flutter_ai_communications_windows/src/windows_camera_facing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const usb = CameraEndpoint(
    id: 'usb-cam',
    name: 'Logitech BRIO',
    facing: CameraFacing.external,
    modes: [VideoFormat(width: 1920, height: 1080, frameRate: 30)],
  );
  const integrated = CameraEndpoint(
    id: 'integrated',
    name: 'Integrated Camera',
    facing: CameraFacing.user,
    modes: [VideoFormat.defaultFormat],
  );

  FlutterAiCommunicationsWindows adapterFor(_RecordingCamera camera) {
    final adapter = FlutterAiCommunicationsWindows(
      camera: camera,
      cameraConsent: const GrantedWindowsCameraConsent(),
    );
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
    expect(catalog.map((endpoint) => endpoint.id), contains('usb-cam'));
  });

  test('USB symbolic link is an external Camera Endpoint', () {
    expect(
      windowsCameraFacing(
        name: 'HD Pro Webcam C920',
        symbolicLink: r'\\?\USB#VID_046D&PID_0892',
      ),
      CameraFacing.external,
    );
  });

  test('integrated name wins over USB in the symbolic link', () {
    expect(
      windowsCameraFacing(
        name: 'Integrated Camera',
        symbolicLink: r'\\?\USB#VID_13D3',
      ),
      CameraFacing.user,
    );
  });

  test(
    'permission denial is a typed result without starting capture',
    () async {
      final camera = _RecordingCamera()..cameras = [usb];
      final adapter = FlutterAiCommunicationsWindows(
        camera: camera,
        cameraConsent: _FixedCameraConsent(CameraPermission.denied),
      );
      addTearDown(adapter.stopCameraNative);
      expect(await adapter.requestCameraPermission(), CameraPermission.denied);
      expect(camera.permissionCalls, 0);
      expect(camera.startCalls, 0);
    },
  );

  test('restricted consent is restricted without starting capture', () async {
    final camera = _RecordingCamera()..cameras = [usb];
    final adapter = FlutterAiCommunicationsWindows(
      camera: camera,
      cameraConsent: _FixedCameraConsent(CameraPermission.restricted),
    );
    addTearDown(adapter.stopCameraNative);
    expect(
      await adapter.requestCameraPermission(),
      CameraPermission.restricted,
    );
    expect(camera.permissionCalls, 0);
  });

  test('packaged Store host requests camera consent', () async {
    final packaged = _RecordingCameraConsent()
      ..result = CameraPermission.denied;
    final adapter = FlutterAiCommunicationsWindows(
      camera: _RecordingCamera(),
      cameraConsent: GatedWindowsCameraConsent(
        isPackaged: () => true,
        packaged: packaged,
      ),
    );
    addTearDown(adapter.stopCameraNative);
    expect(await adapter.requestCameraPermission(), CameraPermission.denied);
    expect(packaged.calls, 1);
  });

  test('unpackaged Win32 skips Store camera consent', () async {
    final packaged = _RecordingCameraConsent()
      ..result = CameraPermission.denied;
    final adapter = FlutterAiCommunicationsWindows(
      camera: _RecordingCamera(),
      cameraConsent: GatedWindowsCameraConsent(
        isPackaged: () => false,
        packaged: packaged,
      ),
    );
    addTearDown(adapter.stopCameraNative);
    expect(await adapter.requestCameraPermission(), CameraPermission.granted);
    expect(packaged.calls, 0);
  });

  test(
    'start yields a Video surface and nearest Native Video Format',
    () async {
      final camera = _RecordingCamera()..cameras = [usb, integrated];
      final adapter = adapterFor(camera);
      expect(
        await adapter.startCameraNative(
          cameraId: 'usb-cam',
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
    },
  );

  test('missing camera is unavailable, not a failed Session graph', () async {
    final camera = _RecordingCamera();
    final adapter = adapterFor(camera);
    expect(
      await adapter.startCameraNative(cameraId: 'gone'),
      NativeGraphStart.unavailable,
    );
    expect(adapter.lastVideoSurface, isNull);
    expect(adapter.lastNativeVideoFormat, isNull);
  });

  test('native status failed is NativeGraphStart.failed', () async {
    const methods = MethodChannel('flutter_ai_communications/methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methods, (call) async {
      if (call.method == 'startCameraNative') {
        return {'status': 'failed'};
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(methods, null));
    final backend = MethodChannelCameraBackend(methods: methods);
    expect(await backend.start(cameraId: 'cam'), NativeGraphStart.failed);
    expect(backend.lastSurface, isNull);
  });

  test('Mute-video keeps the surface; Camera-off stops hardware', () async {
    final camera = _RecordingCamera()..cameras = [usb];
    final adapter = adapterFor(camera);
    await adapter.startCameraNative(cameraId: 'usb-cam');
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
    await adapter.startCameraNative(cameraId: 'integrated');
    await adapter.selectCameraNative('usb-cam');
    expect(camera.selectedId, 'usb-cam');
  });

  test('DeviceAccessStatus maps to CameraPermission', () {
    expect(cameraPermissionFromDeviceAccessStatus(1), CameraPermission.granted);
    expect(cameraPermissionFromDeviceAccessStatus(2), CameraPermission.denied);
    expect(
      cameraPermissionFromDeviceAccessStatus(3),
      CameraPermission.restricted,
    );
    expect(cameraPermissionFromDeviceAccessStatus(0), isNull);
  });
}

final class _FixedCameraConsent implements WindowsCameraConsent {
  _FixedCameraConsent(this.result);

  final CameraPermission result;

  @override
  Future<CameraPermission> request() async => result;
}

final class _RecordingCameraConsent implements WindowsCameraConsent {
  var calls = 0;
  CameraPermission result = CameraPermission.granted;

  @override
  Future<CameraPermission> request() async {
    calls++;
    return result;
  }
}

final class _RecordingCamera implements CameraBackend {
  List<CameraEndpoint> cameras = const [];
  CameraPermission permission = CameraPermission.granted;
  var permissionCalls = 0;
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
  Future<CameraPermission> requestPermission() async {
    permissionCalls++;
    return permission;
  }

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
