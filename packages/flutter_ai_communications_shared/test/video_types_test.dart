import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:test/test.dart';

void main() {
  group('VideoFormat', () {
    test('default is 1280x720 at 30 fps', () {
      expect(VideoFormat.defaultFormat.width, 1280);
      expect(VideoFormat.defaultFormat.height, 720);
      expect(VideoFormat.defaultFormat.frameRate, 30);
    });
  });

  group('VideoFormatNegotiator', () {
    const negotiator = VideoFormatNegotiator();
    const requested = VideoFormat.defaultFormat;

    test('picks exact match when present', () {
      const modes = [
        VideoFormat(width: 640, height: 480, frameRate: 30),
        VideoFormat.defaultFormat,
        VideoFormat(width: 1920, height: 1080, frameRate: 30),
      ];
      expect(negotiator.nearest(requested, modes), VideoFormat.defaultFormat);
    });

    test('prefers next higher resolution over lower', () {
      const modes = [
        VideoFormat(width: 640, height: 480, frameRate: 30),
        VideoFormat(width: 1920, height: 1080, frameRate: 30),
      ];
      expect(
        negotiator.nearest(requested, modes),
        const VideoFormat(width: 1920, height: 1080, frameRate: 30),
      );
    });

    test('falls to next lower when nothing is higher', () {
      const modes = [
        VideoFormat(width: 640, height: 480, frameRate: 30),
        VideoFormat(width: 320, height: 240, frameRate: 30),
      ];
      expect(
        negotiator.nearest(requested, modes),
        const VideoFormat(width: 640, height: 480, frameRate: 30),
      );
    });

    test('prefers fps at least the request when distance ties', () {
      const modes = [
        VideoFormat(width: 1280, height: 720, frameRate: 24),
        VideoFormat(width: 1280, height: 720, frameRate: 36),
      ];
      expect(
        negotiator.nearest(requested, modes),
        const VideoFormat(width: 1280, height: 720, frameRate: 36),
      );
    });

    test('empty modes is null, not a failure object', () {
      expect(negotiator.nearest(requested, const []), isNull);
    });
  });

  group('CameraPreference', () {
    const front = CameraEndpoint(
      id: 'front',
      name: 'Front',
      facing: CameraFacing.user,
    );
    const back = CameraEndpoint(
      id: 'back',
      name: 'Back',
      facing: CameraFacing.environment,
    );
    const usb = CameraEndpoint(
      id: 'usb',
      name: 'USB',
      facing: CameraFacing.external,
    );

    test('empty list prefers user-facing', () {
      expect(
        const CameraPreference().resolve(const [back, front, usb])?.id,
        'front',
      );
    });

    test('empty list with no facing uses first catalog entry', () {
      expect(const CameraPreference().resolve(const [usb])?.id, 'usb');
    });

    test('ordered list wins over facing', () {
      const preference = CameraPreference(
        entries: [CameraPreferenceEntry(id: 'usb')],
      );
      expect(preference.resolve(const [front, back, usb])?.id, 'usb');
    });

    test('empty catalog is null', () {
      expect(const CameraPreference().resolve(const []), isNull);
    });
  });

  group('VideoProcessor', () {
    test('none equals none', () {
      expect(const NoneVideoProcessor(), const NoneVideoProcessor());
    });

    test('blur intensity 0-100 is valid; 101 is not', () {
      expect(const BlurVideoProcessor(intensity: 0).isValid, isTrue);
      expect(const BlurVideoProcessor(intensity: 100).isValid, isTrue);
      expect(const BlurVideoProcessor(intensity: 101).isValid, isFalse);
    });

    test('replace with empty still is invalid', () {
      expect(const ReplaceVideoProcessor().isValid, isFalse);
      expect(const ReplaceVideoProcessor(bytes: []).isValid, isFalse);
      expect(const ReplaceVideoProcessor(asset: 'bg.png').isValid, isTrue);
    });
  });
}
