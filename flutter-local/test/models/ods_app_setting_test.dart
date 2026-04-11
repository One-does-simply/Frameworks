import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/models/ods_app_setting.dart';

void main() {
  // =========================================================================
  // fromJson
  // =========================================================================

  group('OdsAppSetting.fromJson', () {
    test('full valid setting with options as list', () {
      final setting = OdsAppSetting.fromJson({
        'label': 'Language',
        'type': 'select',
        'default': 'en',
        'options': ['en', 'fr', 'de'],
      });
      expect(setting.label, 'Language');
      expect(setting.type, 'select');
      expect(setting.defaultValue, 'en');
      expect(setting.options, ['en', 'fr', 'de']);
    });

    test('default label is empty string when null', () {
      final setting = OdsAppSetting.fromJson({
        'type': 'text',
        'default': 'hello',
      });
      expect(setting.label, '');
    });

    test('default type is text when null', () {
      final setting = OdsAppSetting.fromJson({
        'label': 'Name',
        'default': 'World',
      });
      expect(setting.type, 'text');
    });

    test('default defaultValue is empty string when null', () {
      final setting = OdsAppSetting.fromJson({
        'label': 'Name',
        'type': 'text',
      });
      expect(setting.defaultValue, '');
    });

    test('options as comma-separated string are split and trimmed', () {
      final setting = OdsAppSetting.fromJson({
        'label': 'Size',
        'type': 'select',
        'default': 'M',
        'options': 'S, M , L, XL',
      });
      expect(setting.options, ['S', 'M', 'L', 'XL']);
    });

    test('options missing returns null', () {
      final setting = OdsAppSetting.fromJson({
        'label': 'Username',
        'type': 'text',
        'default': '',
      });
      expect(setting.options, isNull);
    });
  });
}
