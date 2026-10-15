import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/time_utils.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  test('复用格式器保留当前语言和传入时间的墙上时间', () async {
    await initializeDateFormatting();
    final originalLocale = Intl.defaultLocale;
    addTearDown(() => Intl.defaultLocale = originalLocale);
    final formatters = <String, String Function(DateTime?)>{
      'yyyy-MM-dd HH:mm': TimeUtils.formatDetailTime,
      'MM-dd HH:mm': TimeUtils.formatCompactTime,
      'HH:mm': TimeUtils.formatClockTime,
    };
    for (final locale in ['en_US', 'ar', 'zh_CN', 'en_US']) {
      Intl.defaultLocale = locale;
      for (final time in [
        DateTime(2026, 10, 15, 8, 9),
        DateTime.utc(2026, 10, 15, 18, 29),
      ]) {
        for (final entry in formatters.entries) {
          expect(entry.value(time), DateFormat(entry.key).format(time));
          expect(entry.value(time), DateFormat(entry.key).format(time));
          expect(entry.value(null), '');
        }
      }
    }
  });
}
