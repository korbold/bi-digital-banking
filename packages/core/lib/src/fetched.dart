import 'package:equatable/equatable.dart';

enum DataSource { network, cache }

/// Data plus provenance, so the UI can show "showing saved data from 10:42"
/// when it is serving a cached copy during an outage.
class Fetched<T> extends Equatable {
  const Fetched(this.data, {required this.source, required this.fetchedAt});

  final T data;
  final DataSource source;
  final DateTime fetchedAt;

  bool get isFromCache => source == DataSource.cache;

  Fetched<R> map<R>(R Function(T data) transform) =>
      Fetched(transform(data), source: source, fetchedAt: fetchedAt);

  @override
  List<Object?> get props => [data, source, fetchedAt];
}
