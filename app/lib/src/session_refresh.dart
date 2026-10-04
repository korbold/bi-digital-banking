import 'dart:async';

import 'package:flutter/foundation.dart';

/// Adapts a stream to a [Listenable] so go_router re-evaluates redirects
/// whenever the session state changes.
class StreamRefresh extends ChangeNotifier {
  StreamRefresh(Stream<Object?> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
