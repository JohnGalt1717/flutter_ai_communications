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

    test('window share labels always include the owning app', () {
      expect(
        windowShareLabel(title: 'GitHub', applicationName: 'Safari'),
        'Safari — GitHub',
      );
      expect(
        windowShareLabel(title: 'Window', applicationName: 'Finder'),
        'Finder',
      );
      expect(
        windowShareLabel(title: '', applicationName: 'TextEdit'),
        'TextEdit',
      );
      expect(
        windowShareLabel(title: 'TextEdit', applicationName: 'TextEdit'),
        'TextEdit',
      );
      expect(windowShareLabel(title: 'Window', applicationName: ''), isNull);
      expect(windowShareLabel(title: '', applicationName: ''), isNull);
    });

    test('fromChannel formats window rows with the owning app', () {
      final titled = ScreenSource.fromChannel({
        'id': 'window-1',
        'name': 'GitHub',
        'kind': 'window',
        'applicationName': 'Safari',
      });
      expect(titled.name, 'Safari — GitHub');
      expect(titled.applicationName, 'Safari');

      final generic = ScreenSource.fromChannel({
        'id': 'window-2',
        'name': 'Window',
        'kind': 'window',
        'applicationName': 'Finder',
      });
      expect(generic.name, 'Finder');

      final untitled = ScreenSource.fromChannel({
        'id': 'window-3',
        'name': '',
        'kind': 'window',
        'applicationName': 'Notepad',
      });
      expect(untitled.name, 'Notepad');

      final display = ScreenSource.fromChannel({
        'id': 'display-0',
        'name': 'DELL U3219Q',
        'kind': 'display',
      });
      expect(display.name, 'DELL U3219Q');
    });

    test('tryFromChannel omits generic Window rows with no owning app', () {
      expect(
        ScreenSource.tryFromChannel({
          'id': 'window-1',
          'name': 'Window',
          'kind': 'window',
        }),
        isNull,
      );
      expect(
        ScreenSource.tryFromChannel({
          'id': 'window-sidebar',
          'name': 'Window',
          'kind': 'window',
          'applicationName': 'Sidebar',
        }),
        isNull,
      );
      expect(
        ScreenSource.tryFromChannel({
          'id': 'window-2',
          'name': '',
          'kind': 'window',
        }),
        isNull,
      );
      expect(
        ScreenSource.listFromChannel([
          {
            'id': 'window-hidden',
            'name': 'Window',
            'kind': 'window',
          },
          {
            'id': 'window-1',
            'name': 'GitHub',
            'kind': 'window',
            'applicationName': 'Safari',
          },
          {
            'id': 'display-0',
            'name': 'DELL U3219Q',
            'kind': 'display',
          },
        ]).map((source) => source.id),
        ['window-1', 'display-0'],
      );
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
