import 'package:core/core.dart';
import 'package:equatable/equatable.dart';
import 'package:feature_home/src/fx/fx_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class FxState extends Equatable {
  const FxState();

  @override
  List<Object?> get props => [];
}

final class FxLoading extends FxState {
  const FxLoading();
}

final class FxLoaded extends FxState {
  const FxLoaded(this.rates, {required this.isStale, required this.fetchedAt});

  final FxRates rates;

  /// Served from the local cache because the fx service did not answer.
  final bool isStale;
  final DateTime fetchedAt;

  @override
  List<Object?> get props => [rates, isStale, fetchedAt];
}

final class FxUnavailable extends FxState {
  const FxUnavailable(this.failure);

  final AppFailure failure;

  @override
  List<Object?> get props => [failure];
}

class FxCubit extends Cubit<FxState> {
  FxCubit(this._repository, {required this.base, required this.symbols})
    : super(const FxLoading());

  final FxRepository _repository;
  final String base;
  final List<String> symbols;

  /// [silent] keeps the current rates on screen while refreshing (used when
  /// the whole home is refreshed) instead of flashing a skeleton.
  Future<void> load({bool silent = false}) async {
    if (!silent || state is! FxLoaded) emit(const FxLoading());
    final result = await _repository.fetch(base: base, symbols: symbols);
    if (isClosed) return;
    emit(
      switch (result) {
        Success(:final value) => FxLoaded(
          value.data,
          isStale: value.isFromCache,
          fetchedAt: value.fetchedAt,
        ),
        Failure(:final failure) => FxUnavailable(failure),
      },
    );
  }
}
