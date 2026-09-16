import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/library/scripture_repository.dart';

void main() {
  test('the day turns at five in the morning, not at midnight', () {
    // Still up at one: this is last night, and the verse being read should
    // not change underneath the reader.
    expect(scriptureDay(DateTime(2026, 9, 16, 1, 30)), DateTime(2026, 9, 15));
    expect(scriptureDay(DateTime(2026, 9, 16, 4, 59)), DateTime(2026, 9, 15));
    expect(scriptureDay(DateTime(2026, 9, 16, 5)), DateTime(2026, 9, 16));
    expect(scriptureDay(DateTime(2026, 9, 16, 23, 59)), DateTime(2026, 9, 16));
  });

  test('the next turnover is the next five in the morning', () {
    expect(
      nextScriptureDay(DateTime(2026, 9, 16, 1, 30)),
      DateTime(2026, 9, 16, 5),
    );
    expect(
      nextScriptureDay(DateTime(2026, 9, 16, 5)),
      DateTime(2026, 9, 17, 5),
      reason: 'the moment it turns, the next one is tomorrow',
    );
    expect(
      nextScriptureDay(DateTime(2026, 9, 16, 22)),
      DateTime(2026, 9, 17, 5),
    );
  });

  test('the turnover crosses a month and a year', () {
    expect(
      nextScriptureDay(DateTime(2026, 9, 30, 9)),
      DateTime(2026, 10, 1, 5),
    );
    expect(
      nextScriptureDay(DateTime(2026, 12, 31, 9)),
      DateTime(2027, 1, 1, 5),
    );
  });

  test('a device clock in UTC is read in local time', () {
    final utc = DateTime.utc(2026, 9, 16, 12);
    expect(scriptureDay(utc), scriptureDay(utc.toLocal()));
  });
}
