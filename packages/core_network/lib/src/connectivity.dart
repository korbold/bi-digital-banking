import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Thin wrapper over connectivity_plus so features can show an offline
/// banner and auto-refresh when the link comes back.
class ConnectivityMonitor {
  ConnectivityMonitor({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Future<bool> isOnline() async =>
      _hasLink(await _connectivity.checkConnectivity());

  /// Emits only on transitions (online <-> offline).
  Stream<bool> get onStatusChange =>
      _connectivity.onConnectivityChanged.map(_hasLink).distinct();

  static bool _hasLink(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);
}
