import 'package:feature_home/src/fx/fx_rates_section.dart';
import 'package:feature_home/src/fx/fx_repository.dart';
import 'package:sdui/sdui.dart';

/// Registers the native sections owned by the home domain.
void registerHomeSections(
  SduiRegistry registry, {
  required FxRepository fxRepository,
}) {
  registry.register(
    'fx_rates',
    (context, section, _) =>
        FxRatesSection(section: section, repository: fxRepository),
  );
}
