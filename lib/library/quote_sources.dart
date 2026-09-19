import '../packs/pack_store.dart';
import 'scripture_repository.dart';

/// Which books the verse of the day may be drawn from.
///
/// Everything installed is the wrong default. The Ṛgveda is ten times the
/// Gītā, so drawing from all of it makes the morning verse almost always a
/// hymn to Agni for cattle — true to the text, and not what somebody opening
/// the app at five in the morning is looking for. So the Gītā is where the
/// day's verse comes from until the reader says otherwise, and anything else
/// is added on purpose.
class QuoteSources {
  const QuoteSources(this.store);

  final PackStore store;

  /// The setting holds the chosen books. Absent means nobody has chosen, and
  /// the default applies; present and empty means every book was turned off,
  /// which is a choice and is respected rather than quietly overridden.
  static const _key = 'quote_sources';

  /// Whether a book is one of the defaults.
  ///
  /// The Gītā, recognised by name rather than by an exact id. Packs have
  /// called it "gita" and "bhagavad-gita" and sat in a pack called
  /// "bhagavad-gita.sa", and a default that silently matched none of them
  /// would leave the reader with no verse of the day and nothing to explain
  /// it. Loose matching is the right trade here: being wrong means offering
  /// a book somebody can turn off in one tap.
  static bool isDefault(WorkSummary work) =>
      work.slug.toLowerCase().contains('gita') ||
      work.pack.packId.toLowerCase().contains('gita');

  /// Whether the reader has ever chosen.
  bool get chosen => store.setting(_key) != null;

  Set<String> get selected {
    final stored = store.setting(_key);
    if (stored == null) return const {};
    return stored.isEmpty ? const {} : stored.split('\n').toSet();
  }

  static String keyFor(WorkSummary work) => '${work.pack.packId}/${work.slug}';

  /// Whether this book feeds the verse of the day.
  bool includes(WorkSummary work) =>
      chosen ? selected.contains(keyFor(work)) : isDefault(work);

  /// Turns a book on or off as a source.
  ///
  /// The first change writes out the default alongside it, so that turning
  /// one book on never silently turns the Gītā off.
  void set(WorkSummary work, {required bool on, required List<WorkSummary> all}) {
    final current = chosen
        ? selected
        : {
            for (final candidate in all)
              if (isDefault(candidate)) keyFor(candidate),
          };
    final next = {...current};
    if (on) {
      next.add(keyFor(work));
    } else {
      next.remove(keyFor(work));
    }
    store.saveSetting(_key, next.join('\n'));
  }

  /// The books a verse may come from, in the order they are installed.
  List<WorkSummary> among(List<WorkSummary> all) =>
      [for (final work in all) if (includes(work)) work];
}
