import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/core/http_status.dart';

DownloadAction act(int status, {bool resuming = false}) =>
    decideDownload(status, resuming: resuming).action;

void main() {
  test('fresh download writes the body', () {
    expect(act(200), DownloadAction.writeFromStart);
  });

  test('resume appends only when the server honours Range', () {
    expect(act(206, resuming: true), DownloadAction.append);
    expect(act(200, resuming: true), DownloadAction.discardPartialAndWrite);
    expect(act(206), DownloadAction.fail);
  });

  test('416 while resuming means the file may already be complete', () {
    expect(act(416, resuming: true), DownloadAction.verifyExisting);
    expect(act(416), DownloadAction.fail);
  });

  test('transient failures retry', () {
    for (final s in [408, 425, 429, 500, 502, 503, 504]) {
      expect(act(s), DownloadAction.retry, reason: 'HTTP $s');
    }
  });

  test('permanent failures stop with a message', () {
    for (final s in [401, 403, 404, 410, 400, 302]) {
      final d = decideDownload(s, resuming: false);
      expect(d.action, DownloadAction.fail, reason: 'HTTP $s');
      expect(d.message, isNotEmpty);
    }
  });
}
