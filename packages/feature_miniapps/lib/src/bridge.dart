import 'dart:convert';

/// Capabilities the native host exposes to a micro-app. Implemented by the
/// page (UI-bound ones) with data supplied by the app shell.
abstract interface class MiniAppHost {
  Future<Map<String, Object?>> getContext();
  Future<String?> getAuthToken();
  void track(String event, Map<String, Object?> params);
  void notifyHost(String title, String body);
  void close(Object? result);
}

/// Result of handling one bridge message. [script] is the JavaScript to run
/// in the WebView to resolve/reject the caller's promise (null when the
/// message was too malformed to answer).
class BridgeResponse {
  const BridgeResponse._(this.id, this.ok, this.payload);

  factory BridgeResponse.resolve(String id, Object? payload) =>
      BridgeResponse._(id, true, payload);
  factory BridgeResponse.reject(String? id, String code, String message) =>
      BridgeResponse._(id, false, {'code': code, 'message': message});

  final String? id;
  final bool ok;
  final Object? payload;

  String? get script {
    if (id == null) return null;
    final fn = ok ? 'biBridgeResolve' : 'biBridgeReject';
    // jsonEncode yields valid JS literals and escapes quotes -> no injection.
    return 'window.$fn && window.$fn(${jsonEncode(id)}, ${jsonEncode(payload)});';
  }
}

/// Protocol: the micro-app calls
/// `BiBridge.postMessage(JSON.stringify({id, method, params}))`
/// and receives `window.biBridgeResolve(id, result)` or
/// `window.biBridgeReject(id, {code, message})`.
///
/// Kept free of WebView types so it is fully unit-testable.
class MiniAppBridge {
  MiniAppBridge(this._host);

  final MiniAppHost _host;

  /// Explicit allowlist: a micro-app can never call anything else.
  static const allowedMethods = {
    'getContext',
    'getAuthToken',
    'track',
    'close',
    'notifyHost',
  };

  Future<BridgeResponse> handle(String raw) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return BridgeResponse.reject(
        null,
        'malformed',
        'Message is not valid JSON',
      );
    }
    if (decoded is! Map) {
      return BridgeResponse.reject(
        null,
        'malformed',
        'Message must be an object',
      );
    }

    final id = decoded['id'];
    if (id is! String || id.isEmpty) {
      return BridgeResponse.reject(null, 'malformed', 'Missing id');
    }
    final method = decoded['method'];
    if (method is! String || !allowedMethods.contains(method)) {
      return BridgeResponse.reject(
        id,
        'method_not_allowed',
        'Method "$method" is not allowed',
      );
    }
    final rawParams = decoded['params'];
    final params = rawParams is Map
        ? rawParams.map((k, v) => MapEntry('$k', v))
        : <String, Object?>{};

    try {
      switch (method) {
        case 'getContext':
          return BridgeResponse.resolve(id, await _host.getContext());
        case 'getAuthToken':
          final token = await _host.getAuthToken();
          if (token == null) {
            return BridgeResponse.reject(
              id,
              'unauthenticated',
              'No active session',
            );
          }
          return BridgeResponse.resolve(id, {'token': token});
        case 'track':
          final event = params['event'];
          if (event is! String) {
            return BridgeResponse.reject(
              id,
              'invalid_params',
              'event is required',
            );
          }
          final eventParams = params['params'];
          _host.track(
            event,
            eventParams is Map
                ? eventParams.map((k, v) => MapEntry('$k', v))
                : const {},
          );
          return BridgeResponse.resolve(id, null);
        case 'notifyHost':
          _host.notifyHost(
            '${params['title'] ?? ''}',
            '${params['body'] ?? ''}',
          );
          return BridgeResponse.resolve(id, null);
        case 'close':
          _host.close(params['result']);
          return BridgeResponse.resolve(id, null);
      }
    } on Object catch (e) {
      return BridgeResponse.reject(id, 'host_error', '$e');
    }
    return BridgeResponse.reject(id, 'method_not_allowed', 'Unhandled method');
  }
}
