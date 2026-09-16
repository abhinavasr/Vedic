import 'package:flutter_test/flutter_test.dart';
import 'package:vedic/ai/model_host.dart';
import 'package:vedic/core/model_catalog.dart';

void main() {
  test('a served file is reachable, whole or partial', () {
    expect(hostStatusForCode(200), ModelHostStatus.reachable);
    expect(hostStatusForCode(206), ModelHostStatus.reachable);
  });

  test('a file behind a gate counts as gone', () {
    // From the app's side, a model that used to be public and now needs a
    // token is a file that is no longer there.
    for (final code in [401, 403, 404, 410]) {
      expect(
        hostStatusForCode(code),
        ModelHostStatus.missing,
        reason: 'HTTP $code',
      );
    }
  });

  test(
    'anything else is the host being unhelpful, not the file being gone',
    () {
      expect(hostStatusForCode(500), ModelHostStatus.unavailable);
      expect(hostStatusForCode(429), ModelHostStatus.unavailable);
      expect(hostStatusForCode(null), ModelHostStatus.unavailable);
    },
  );

  test('every failure says something the reader can act on', () {
    for (final status in ModelHostStatus.values) {
      if (status == ModelHostStatus.reachable) continue;
      final message = messageForHostStatus(status);
      expect(message, isNotEmpty, reason: '$status');
      expect(message, endsWith('.'), reason: '$status');
    }
    expect(messageForHostStatus(ModelHostStatus.offline), contains('Wi-Fi'));
    expect(
      messageForHostStatus(ModelHostStatus.missing),
      contains('our end rather than yours'),
    );
  });

  test('Hugging Face is not resumable, and the mirror is', () {
    // Weak ETags there: a resumed transfer can produce a corrupt file that
    // only the engine notices, an hour later.
    expect(ModelHost.huggingFace.resumable, isFalse);
    expect(ModelHost.mirror.resumable, isTrue);
  });

  test('both hosts point at the same file name', () {
    // The installed model's identity is its file name, so switching hosts
    // must not look like a different model.
    String file(ModelHost host) =>
        Uri.parse(host.urlFor(gemma4E2b)).pathSegments.last;
    expect(file(ModelHost.mirror), file(ModelHost.huggingFace));
    expect(file(ModelHost.huggingFace), 'gemma-4-E2B-it.litertlm');
  });
}
