import 'package:core/core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

/// Feature flags and kill switches served by Firebase Remote Config.
///
/// They complement SDUI: the BFF decides *what content* a customer sees;
/// flags decide *which capabilities* are enabled for a rollout percentage,
/// so a faulty feature can be turned off without a release.
class RemoteFlags {
  RemoteFlags(this._rc, {AppLogger logger = const ConsoleLogger()})
    : _logger = logger;

  final FirebaseRemoteConfig _rc;
  final AppLogger _logger;

  static const _defaults = <String, Object>{
    'transfers_enabled': true,
    'miniapps_enabled': true,
    'home_refresh_seconds': 60,
    'maintenance_message': '',
  };

  Future<void> init() async {
    await _rc.setDefaults(_defaults);
    await _rc.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 5),
        minimumFetchInterval: const Duration(minutes: 5),
      ),
    );
    try {
      // Never block startup on Remote Config: defaults/last activated values
      // are used if the fetch is slow or fails.
      await _rc.fetchAndActivate().timeout(const Duration(seconds: 3));
    } on Object catch (e) {
      _logger.warning(
        'Remote Config fetch failed, using cached/defaults',
        context: {'error': '$e'},
      );
    }
  }

  bool get transfersEnabled => _rc.getBool('transfers_enabled');
  bool get miniAppsEnabled => _rc.getBool('miniapps_enabled');
  String get maintenanceMessage => _rc.getString('maintenance_message');

  Stream<void> get onUpdated =>
      _rc.onConfigUpdated.asyncMap((_) => _rc.activate());
}
