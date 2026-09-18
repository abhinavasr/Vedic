/// Something to sit with, played under the timer.
///
/// The clips are short — half a minute for all but the waves — so they are
/// looped rather than played once. A loop is why they were chosen: a track
/// that ends in the middle of a sitting is worse than no track at all, and
/// there is nothing to wait for at the end of one.
enum MeditationMusic {
  none('Silence', null),
  bell('Temple Bell', 'sounds/meditation_bell.mp3'),
  ambient('Ambient', 'sounds/meditation_ambient.mp3'),
  birdsong('Birdsong', 'sounds/meditation_birdsong.mp3'),
  waves('Waves', 'sounds/meditation_waves.mp3');

  const MeditationMusic(this.label, this.asset);

  /// What the chip says.
  final String label;

  /// Where the audio lives, relative to the asset bundle. Null is silence,
  /// which is a choice rather than the absence of one.
  final String? asset;

  /// Whether choosing this means playing something.
  bool get sounds => asset != null;
}
