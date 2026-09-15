const int kib = 1024;
const int mib = 1024 * kib;
const int gib = 1024 * mib;

/// Formats [bytes] with one decimal place, e.g. "2.4 GB".
///
/// Binary units labelled "GB", matching how the project docs quote model sizes
/// (2,588,147,712 bytes is "2.4 GB").
String formatBytes(int bytes) {
  if (bytes < kib) return '$bytes B';
  if (bytes < mib) return '${(bytes / kib).toStringAsFixed(1)} KB';
  if (bytes < gib) return '${(bytes / mib).toStringAsFixed(1)} MB';
  return '${(bytes / gib).toStringAsFixed(1)} GB';
}
