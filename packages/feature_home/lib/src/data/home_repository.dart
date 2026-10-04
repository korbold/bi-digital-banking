import 'dart:async';

import 'package:core/core.dart';
import 'package:core_network/core_network.dart';
import 'package:sdui/sdui.dart';

/// Personalized home layout from the BFF (`GET /api/home`).
class HomeRepository {
  HomeRepository(this._api);

  final ApiClient _api;

  /// Cached layout first (instant paint, works offline), then the fresh one.
  Stream<Result<Fetched<SduiScreen>>> watchHome() =>
      _api.watch('/api/home', decode: SduiScreen.fromJson);

  /// Behaviour signal that feeds server-side personalization (quick-action
  /// ordering). Fire-and-forget: losing one event is acceptable, blocking
  /// the UI on it is not.
  void trackEvent(String type, String target) {
    unawaited(
      _api.post<void>(
        '/api/events',
        body: {'type': type, 'target': target},
        decode: (_) {},
      ),
    );
  }
}
