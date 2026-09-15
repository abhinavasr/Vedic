// A silent meditation session timed by the wall clock, so it stays correct
// across pauses and while the app is in the background.

class MeditationSettings {
  const MeditationSettings({
    required this.total,
    this.interval,
    this.endingBell = true,
  });

  final Duration total;

  /// Null for no interval chime.
  final Duration? interval;
  final bool endingBell;

  /// When the interval chime sounds, measured from the start. Never at the
  /// start, and never at the end, where the ending bell rings instead.
  List<Duration> get chimeTimes {
    final interval = this.interval;
    if (interval == null || interval <= Duration.zero) return const [];
    return [for (var t = interval; t < total; t += interval) t];
  }
}

enum MeditationPhase { ready, running, paused, finished }

enum MeditationSound { chime, endingBell }

class MeditationSession {
  MeditationSession(this.settings);

  final MeditationSettings settings;

  var _phase = MeditationPhase.ready;
  DateTime? _runningSince;
  var _elapsedBeforeRun = Duration.zero;
  var _chimesDone = 0;

  MeditationPhase get phase => _phase;

  Duration elapsed(DateTime now) {
    final since = _runningSince;
    final elapsed = _phase == MeditationPhase.running && since != null
        ? _elapsedBeforeRun + now.difference(since)
        : _elapsedBeforeRun;
    return elapsed > settings.total ? settings.total : elapsed;
  }

  Duration remaining(DateTime now) => settings.total - elapsed(now);

  void start(DateTime now) {
    if (_phase != MeditationPhase.ready) return;
    _phase = MeditationPhase.running;
    _runningSince = now;
  }

  void pause(DateTime now) {
    if (_phase != MeditationPhase.running) return;
    _elapsedBeforeRun = elapsed(now);
    _runningSince = null;
    _phase = MeditationPhase.paused;
  }

  void resume(DateTime now) {
    if (_phase != MeditationPhase.paused) return;
    _runningSince = now;
    _phase = MeditationPhase.running;
  }

  /// Advances the session to [now] and returns the sounds now due.
  ///
  /// Chimes missed while the app was suspended collapse into one, and no
  /// chime sounds on the tick that ends the session: only the bell.
  List<MeditationSound> tick(DateTime now) {
    if (_phase != MeditationPhase.running) return const [];
    final elapsed = this.elapsed(now);
    final chimes = settings.chimeTimes;
    var due = 0;
    while (_chimesDone < chimes.length && chimes[_chimesDone] <= elapsed) {
      _chimesDone++;
      due++;
    }

    if (elapsed >= settings.total) {
      _elapsedBeforeRun = settings.total;
      _runningSince = null;
      _phase = MeditationPhase.finished;
      return [if (settings.endingBell) MeditationSound.endingBell];
    }
    return [if (due > 0) MeditationSound.chime];
  }
}
