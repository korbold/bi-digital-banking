import 'package:equatable/equatable.dart';

/// Transport-agnostic push message (decoupled from FCM's RemoteMessage).
class PushMessage extends Equatable {
  const PushMessage({this.title, this.body, this.data = const {}});

  final String? title;
  final String? body;
  final Map<String, Object?> data;

  /// Deep link carried in `data.route`. Only in-app paths are accepted, so a
  /// crafted push cannot send the user to an arbitrary URL.
  String? get route => routeOf(data);

  static String? routeOf(Map<String, Object?> data) {
    final route = data['route'];
    if (route is! String || !route.startsWith('/') || route.startsWith('//')) {
      return null;
    }
    return route;
  }

  @override
  List<Object?> get props => [title, body, data];
}
