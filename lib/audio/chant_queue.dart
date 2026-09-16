// What a listening session plays, and in what order.
//
// Pure data: a queue is built from the pack before anything is played, so the
// order, the labels and the "3 of 47" can be tested without a speaker.

/// One passage in a listening queue.
class ChantItem {
  const ChantItem({
    required this.ref,
    required this.label,
    required this.work,
    required this.chapter,
    required this.url,
    required this.sha256,
    required this.bytes,
    required this.durationMs,
    required this.text,
  });

  final String ref;

  /// As printed, e.g. "2.47".
  final String label;

  /// The book, for the lock screen.
  final String work;

  /// Where in it, e.g. "Chapter 2".
  final String? chapter;

  final String url;
  final String sha256;
  final int bytes;
  final int durationMs;

  /// The Sanskrit. Part of the cache key, so a verse corrected in a later
  /// revision never replays the recording made from the old wording.
  final String text;

  /// What the lock screen shows as the title.
  String get title => '$work $label';

  /// And underneath it.
  String get subtitle => chapter ?? work;
}

/// A queue, and where it has got to.
///
/// Immutable: advancing gives a new one, which keeps the player's state and
/// the UI's state from drifting apart.
class ChantQueue {
  const ChantQueue({required this.items, this.index = 0});

  static const empty = ChantQueue(items: []);

  final List<ChantItem> items;
  final int index;

  bool get isEmpty => items.isEmpty;
  bool get hasNext => index + 1 < items.length;
  bool get hasPrevious => index > 0;

  ChantItem? get current =>
      index >= 0 && index < items.length ? items[index] : null;

  /// The next few, for fetching before they are wanted. A listener walking
  /// down the road should not wait for each verse to download as it arrives.
  List<ChantItem> ahead({int count = 2}) => [
    for (var i = index + 1; i <= index + count && i < items.length; i++)
      items[i],
  ];

  ChantQueue at(int position) => ChantQueue(
    items: items,
    // An empty queue has no position to be at, and clamping into an empty
    // range throws rather than saying so.
    index: items.isEmpty ? 0 : position.clamp(0, items.length - 1),
  );

  ChantQueue get next => hasNext ? at(index + 1) : this;

  ChantQueue get previous => hasPrevious ? at(index - 1) : this;

  /// Starts at [ref], or at the beginning when the queue does not hold it.
  ChantQueue startingAt(String? ref) {
    if (ref == null) return at(0);
    final position = items.indexWhere((item) => item.ref == ref);
    return at(position < 0 ? 0 : position);
  }

  /// How long what is left will take.
  Duration get remaining => Duration(
    milliseconds: [
      for (var i = index; i < items.length; i++) items[i].durationMs,
    ].fold(0, (sum, ms) => sum + ms),
  );

  Duration get total => Duration(
    milliseconds: items.fold(0, (sum, item) => sum + item.durationMs),
  );
}

/// How long something runs, said the way a listener would say it.
String spokenDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  if (hours > 0) {
    return minutes == 0 ? '$hours hr' : '$hours hr $minutes min';
  }
  if (d.inMinutes > 0) return '${d.inMinutes} min';
  return '${d.inSeconds} sec';
}
