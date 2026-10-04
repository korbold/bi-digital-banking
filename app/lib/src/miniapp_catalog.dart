import 'package:bi_digital_banking/src/config/env.dart';
import 'package:feature_miniapps/feature_miniapps.dart';

/// Known micro-apps. SDUI references them by id so the server can promote a
/// micro-app without knowing (or being able to change) its URL; the URL
/// allowlist stays on the client.
abstract final class MiniAppCatalog {
  static final Map<String, MiniAppDescriptor> _items = {
    'insurance': MiniAppDescriptor(
      id: 'insurance',
      title: 'Seguros',
      url: Uri.parse('${Env.bffBaseUrl}/miniapps/insurance/'),
    ),
  };

  static MiniAppDescriptor? byId(String id) => _items[id];
}
