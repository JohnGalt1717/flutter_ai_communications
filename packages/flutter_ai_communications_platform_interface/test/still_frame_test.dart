import 'dart:typed_data';

import 'package:flutter_ai_communications_platform_interface/flutter_ai_communications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromChannel reads JPEG bytes and dimensions', () {
    final frame = StillFrame.fromChannel({
      'bytes': Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9]),
      'width': 640,
      'height': 360,
      'mime': 'image/jpeg',
    });
    expect(frame, isNotNull);
    expect(frame!.width, 640);
    expect(frame.height, 360);
    expect(frame.mime, 'image/jpeg');
    expect(frame.bytes, [0xFF, 0xD8, 0xFF, 0xD9]);
  });

  test('fromChannel is null for empty or missing bytes', () {
    expect(StillFrame.fromChannel(null), isNull);
    expect(StillFrame.fromChannel({'width': 1, 'height': 1}), isNull);
    expect(
      StillFrame.fromChannel({'bytes': Uint8List(0), 'width': 1, 'height': 1}),
      isNull,
    );
  });
}
