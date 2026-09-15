/// This build's number, compared against a pack's `min_app_build`.
///
/// Release builds set it with `--dart-define=APP_BUILD=<n>`.
const int appBuild = int.fromEnvironment('APP_BUILD', defaultValue: 1);
