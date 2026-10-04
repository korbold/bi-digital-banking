import 'package:equatable/equatable.dart';

/// A micro-app hosted outside the binary (own repo, own deploy cadence).
class MiniAppDescriptor extends Equatable {
  const MiniAppDescriptor({
    required this.id,
    required this.title,
    required this.url,
  });

  final String id;
  final String title;
  final Uri url;

  /// Entry URL with launch params appended as query string.
  Uri launchUri([Map<String, Object?> params = const {}]) {
    if (params.isEmpty) return url;
    return url.replace(
      queryParameters: {
        ...url.queryParameters,
        for (final e in params.entries)
          if (e.value != null) e.key: '${e.value}',
      },
    );
  }

  /// Only the micro-app's own origin (https + same host) may load inside the
  /// WebView; anything else is blocked to prevent phishing / token leakage.
  bool allowsNavigation(Uri target) =>
      target.toString() == 'about:blank' ||
      (target.scheme == 'https' &&
          target.host == url.host &&
          target.port == url.port);

  @override
  List<Object?> get props => [id, title, url];
}
