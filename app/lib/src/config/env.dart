/// Build-time configuration injected with `--dart-define`.
///
/// One binary per environment is promoted through dev -> staging -> prod,
/// so nothing environment-specific is hard-coded in source.
abstract final class Env {
  static const bffBaseUrl = String.fromEnvironment(
    'BFF_BASE_URL',
    defaultValue: 'https://bi-digital-banking.vercel.app',
  );

  /// Shows the fault-injection panel. On for the evaluation build, off in
  /// production flavors.
  static const enableChaosPanel = bool.fromEnvironment(
    'ENABLE_CHAOS_PANEL',
    defaultValue: true,
  );

  static const environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );
}
