import 'package:core/core.dart';
import 'package:equatable/equatable.dart';
import 'package:feature_auth/src/domain/customer.dart';
import 'package:feature_auth/src/domain/customer_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum ProfileStatus { idle, saving, saved, failure }

class ProfileState extends Equatable {
  const ProfileState({
    required this.customer,
    required this.interests,
    this.status = ProfileStatus.idle,
    this.failure,
  });

  final Customer customer;
  final Set<String> interests;
  final ProfileStatus status;
  final AppFailure? failure;

  bool get isDirty => !_sameSet(interests, customer.interests.toSet());

  ProfileState copyWith({
    Customer? customer,
    Set<String>? interests,
    ProfileStatus? status,
    AppFailure? failure,
  }) => ProfileState(
    customer: customer ?? this.customer,
    interests: interests ?? this.interests,
    status: status ?? this.status,
    failure: failure,
  );

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  List<Object?> get props => [customer, interests, status, failure];
}

/// Edits the declared interests. Saving them changes what the BFF puts on
/// the personalized home (campaigns are filtered by interest).
class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit(
    this._repository, {
    required Customer customer,
    AnalyticsTracker analytics = const NoopAnalytics(),
  }) : _analytics = analytics,
       super(
         ProfileState(
           customer: customer,
           interests: customer.interests.toSet(),
         ),
       );

  final CustomerRepository _repository;
  final AnalyticsTracker _analytics;

  void toggleInterest(String id) {
    final next = {...state.interests};
    if (!next.remove(id)) next.add(id);
    emit(state.copyWith(interests: next, status: ProfileStatus.idle));
  }

  Future<Customer?> save() async {
    if (state.status == ProfileStatus.saving) return null;
    emit(state.copyWith(status: ProfileStatus.saving));
    final result = await _repository.updateInterests(
      state.interests.toList()..sort(),
    );
    if (isClosed) return null;
    switch (result) {
      case Success(:final value):
        _analytics.track('interests_updated', {
          'count': value.interests.length,
        }).ignore();
        emit(
          ProfileState(
            customer: value,
            interests: value.interests.toSet(),
            status: ProfileStatus.saved,
          ),
        );
        return value;
      case Failure(:final failure):
        emit(state.copyWith(status: ProfileStatus.failure, failure: failure));
        return null;
    }
  }
}
