import 'package:flutter_ai_communications_shared/flutter_ai_communications_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web catalog kind is system-picker, not a window list', () {
    const source = ScreenSource(
      id: 'system-picker',
      name: 'System picker',
      kind: ScreenSourceKind.systemPicker,
    );
    expect(source.kind, ScreenSourceKind.systemPicker);
    expect(source.canPreview, isFalse);
  });
}
