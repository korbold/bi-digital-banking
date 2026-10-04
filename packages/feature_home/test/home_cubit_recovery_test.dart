import 'dart:async';

import 'package:core/core.dart';
import 'package:feature_home/feature_home.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sdui/sdui.dart';

class _MockHomeRepository extends Mock implements HomeRepository {}

void main() {
  test('reloads home automatically when connectivity comes back', () async {
    final repository = _MockHomeRepository();
    final online = StreamController<bool>();
    final screen = SduiScreen.fromJson(const {
      'schemaVersion': 1,
      'screen': 'home',
      'sections': <Object>[],
    });
    var calls = 0;
    when(repository.watchHome).thenAnswer((_) {
      calls++;
      return Stream.value(
        Result.success(
          Fetched(
            screen,
            source: DataSource.network,
            fetchedAt: DateTime(2026),
          ),
        ),
      );
    });

    final cubit = HomeCubit(repository, connectivityChanges: online.stream);
    await cubit.load();
    expect(calls, 1);

    online
      ..add(false)
      ..add(true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2);

    await cubit.close();
    await online.close();
  });
}
