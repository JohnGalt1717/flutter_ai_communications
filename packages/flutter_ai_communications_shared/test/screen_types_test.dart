import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:test/test.dart';

void main() {
  group('ScreenSource', () {
    test('equality uses id, name, kind, bounds, and canPreview', () {
      const a = ScreenSource(
        id: 'display-0',
        name: 'Display 1',
        kind: ScreenSourceKind.display,
        width: 1920,
        height: 1080,
        canPreview: true,
      );
      const b = ScreenSource(
        id: 'display-0',
        name: 'Display 1',
        kind: ScreenSourceKind.display,
        width: 1920,
        height: 1080,
        canPreview: true,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('All-displays is a kind, not an application kind', () {
      const source = ScreenSource(
        id: 'all',
        name: 'All displays',
        kind: ScreenSourceKind.allDisplays,
      );
      expect(source.kind, ScreenSourceKind.allDisplays);
      expect(ScreenSourceKind.values, isNot(contains(null)));
      expect(
        ScreenSourceKind.values,
        containsAll([
          ScreenSourceKind.display,
          ScreenSourceKind.window,
          ScreenSourceKind.allDisplays,
          ScreenSourceKind.systemPicker,
        ]),
      );
    });
  });

  group('ScreenVideoFormat', () {
    test('under the cap keeps physical size and uses 5 fps', () {
      expect(
        ScreenVideoFormat.request(width: 1280, height: 720, motion: false),
        const VideoFormat(width: 1280, height: 720, frameRate: 5),
      );
    });

    test('4K is capped at 1920x1080 keeping aspect', () {
      expect(
        ScreenVideoFormat.request(width: 3840, height: 2160, motion: false),
        const VideoFormat(width: 1920, height: 1080, frameRate: 5),
      );
    });

    test('ultrawide cap keeps aspect under 1920x1080', () {
      final format = ScreenVideoFormat.request(
        width: 3440,
        height: 1440,
        motion: true,
      );
      expect(format.width, lessThanOrEqualTo(1920));
      expect(format.height, lessThanOrEqualTo(1080));
      expect(format.width / format.height, closeTo(3440 / 1440, 0.02));
      expect(format.frameRate, 30);
    });
  });
}
