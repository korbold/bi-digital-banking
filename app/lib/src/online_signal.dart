import 'dart:async';

import 'package:core_network/core_network.dart';

/// "We are back online" events from two sources: the real network
/// (connectivity_plus) and the chaos panel (forced-offline switched off or
/// a service restored). Features refresh on `true`, which is how recovery is
/// demonstrated without touching the app.
class OnlineSignal {
  OnlineSignal(ConnectivityMonitor connectivity, ChaosController chaos) {
    _sub = connectivity.onStatusChange.listen(_controller.add);
    var previous = chaos.value;
    chaos.addListener(() {
      final next = chaos.value;
      final restored =
          (previous.forceOffline && !next.forceOffline) ||
          next.downServices.length < previous.downServices.length;
      if (restored) _controller.add(true);
      previous = next;
    });
  }

  final _controller = StreamController<bool>.broadcast();
  late final StreamSubscription<bool> _sub;

  Stream<bool> get changes => _controller.stream;

  Future<void> dispose() async {
    await _sub.cancel();
    await _controller.close();
  }
}
