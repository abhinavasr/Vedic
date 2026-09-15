enum DownloadAction {
  /// Write the body as the whole file.
  writeFromStart,

  /// The server honoured `Range`; append the body to the partial file.
  append,

  /// The server ignored `Range` and sent the whole file. Discard the partial
  /// file and write from the start; appending would corrupt it.
  discardPartialAndWrite,

  /// Nothing left to fetch at this offset. Verify the SHA-256; if it fails,
  /// delete the file and start again.
  verifyExisting,

  /// Transient. Try again later with backoff.
  retry,

  /// Permanent. Stop and tell the user.
  fail,
}

class DownloadDecision {
  const DownloadDecision(this.action, [this.message]);

  final DownloadAction action;

  /// User-facing explanation, set for [DownloadAction.fail].
  final String? message;
}

/// Maps a download response's HTTP status to what the downloader does next.
///
/// [resuming] is whether the request carried a `Range` header for a partial
/// file.
DownloadDecision decideDownload(int status, {required bool resuming}) =>
    switch (status) {
      200 when resuming => const DownloadDecision(
        DownloadAction.discardPartialAndWrite,
      ),
      200 => const DownloadDecision(DownloadAction.writeFromStart),
      206 when resuming => const DownloadDecision(DownloadAction.append),
      206 => const DownloadDecision(
        DownloadAction.fail,
        'The server sent only part of the file.',
      ),
      416 when resuming => const DownloadDecision(
        DownloadAction.verifyExisting,
      ),
      401 || 403 => const DownloadDecision(
        DownloadAction.fail,
        'The download server refused access. Try again later, or switch to '
        'the mirror in Settings.',
      ),
      404 || 410 => const DownloadDecision(
        DownloadAction.fail,
        'The file is no longer available at this address.',
      ),
      408 || 425 || 429 => const DownloadDecision(DownloadAction.retry),
      >= 500 && < 600 => const DownloadDecision(DownloadAction.retry),
      _ => DownloadDecision(
        DownloadAction.fail,
        'The download failed (HTTP $status).',
      ),
    };
