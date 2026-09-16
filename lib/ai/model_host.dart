import 'dart:async';
import 'dart:io';

import '../core/model_catalog.dart';

// Where the model comes from, and whether that host can actually serve it.
//
// Asking costs one round trip and saves the reader from a download that climbs
// for a while and then dies, which tells them nothing and invites them to
// retry something that cannot work.

enum ModelHost {
  huggingFace('Hugging Face'),
  mirror('Sadhana mirror');

  const ModelHost(this.label);

  final String label;

  String get url => switch (this) {
    ModelHost.huggingFace => gemmaModelUrl,
    ModelHost.mirror => gemmaModelFallbackUrl,
  };

  /// Whether a paused transfer can be picked up again.
  ///
  /// Hugging Face serves weak ETags, and a resumed transfer there can produce
  /// a file that is corrupt in a way only the engine notices, an hour later.
  bool get resumable => this != ModelHost.huggingFace;
}

enum ModelHostStatus { reachable, offline, missing, unavailable }

/// What an HTTP status means for a download that has not started yet.
///
/// 401 and 403 count as [ModelHostStatus.missing] on purpose: a model that
/// used to be public and now needs a token is, from the app's side, a file
/// that is no longer there.
ModelHostStatus hostStatusForCode(int? code) {
  if (code == null) return ModelHostStatus.unavailable;
  if (code == 200 || code == 206) return ModelHostStatus.reachable;
  if (code == 401 || code == 403 || code == 404 || code == 410) {
    return ModelHostStatus.missing;
  }
  return ModelHostStatus.unavailable;
}

String messageForHostStatus(ModelHostStatus status) => switch (status) {
  ModelHostStatus.reachable => '',
  ModelHostStatus.offline =>
    'No connection. The assistant needs a one-off download, so this needs '
        'Wi-Fi before it can start.',
  ModelHostStatus.missing =>
    'The model is no longer where the app expects it. This is a problem at '
        'our end rather than yours, and it does not affect anything else in '
        'the app.',
  ModelHostStatus.unavailable =>
    'The download host is not responding just now. Everything else keeps '
        'working; this is worth trying again later.',
};

/// The host chosen for a download, and why.
class ChosenHost {
  const ChosenHost(this.status, {this.host});

  final ModelHostStatus status;

  /// The host that answered, when [status] is reachable.
  final ModelHost? host;
}

/// Asks each host whether it can serve the file, in order.
class HostProbe {
  const HostProbe({this.timeout = const Duration(seconds: 12)});

  final Duration timeout;

  /// The first host that can serve the file.
  ///
  /// With [preferred] set, only that host is asked: a host the reader picked
  /// is not overruled by the automatic order. Otherwise the worst answer is
  /// reported, preferring [ModelHostStatus.offline] — being offline is worth
  /// saying even if a later host merely timed out.
  Future<ChosenHost> choose({ModelHost? preferred}) async {
    if (preferred != null) {
      final status = await check(preferred);
      return ChosenHost(
        status,
        host: status == ModelHostStatus.reachable ? preferred : null,
      );
    }

    var worst = ModelHostStatus.unavailable;
    for (final host in ModelHost.values) {
      final status = await check(host);
      if (status == ModelHostStatus.reachable) {
        return ChosenHost(status, host: host);
      }
      if (status == ModelHostStatus.offline) return ChosenHost(status);
      worst = status;
    }
    return ChosenHost(worst);
  }

  Future<ModelHostStatus> check(ModelHost host) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..userAgent = 'Sadhana';
    try {
      final request = await client.headUrl(Uri.parse(host.url));
      request.followRedirects = true;
      final response = await request.close().timeout(timeout);
      await response.drain<void>();
      return hostStatusForCode(response.statusCode);
    } on SocketException {
      return ModelHostStatus.offline;
    } on TimeoutException {
      return ModelHostStatus.unavailable;
    } on HttpException {
      return ModelHostStatus.unavailable;
    } finally {
      client.close(force: true);
    }
  }
}
