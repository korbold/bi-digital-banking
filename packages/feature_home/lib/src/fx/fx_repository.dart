import 'package:core/core.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';

class FxRates extends Equatable {
  const FxRates({
    required this.base,
    required this.rates,
    this.updatedAt,
    this.provider,
  });

  factory FxRates.fromJson(Object? json) {
    final map = json! as Map;
    final raw = map['rates']! as Map;
    return FxRates(
      base: map['base']! as String,
      rates: raw.map((k, v) => MapEntry('$k', (v! as num).toDouble())),
      updatedAt: DateTime.tryParse('${map['updatedAt']}'),
      provider: map['provider'] as String?,
    );
  }

  final String base;
  final Map<String, double> rates;
  final DateTime? updatedAt;
  final String? provider;

  @override
  List<Object?> get props => [base, rates, updatedAt, provider];
}

/// Exchange rates proxied by the BFF from a public third-party API. It is a
/// separate "service" (`fx`) for circuit breaking, so its outage is isolated.
class FxRepository {
  FxRepository(this._api);

  final ApiClient _api;

  Future<Result<Fetched<FxRates>>> fetch({
    required String base,
    required List<String> symbols,
  }) => _api.get(
    '/api/fx',
    query: {'base': base, if (symbols.isNotEmpty) 'symbols': symbols.join(',')},
    decode: FxRates.fromJson,
  );
}
