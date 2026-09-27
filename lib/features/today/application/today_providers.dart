import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../planner/application/planning_providers.dart';
import '../data/drift_today_repository.dart';
import '../domain/today_entities.dart';
import '../domain/today_repository.dart';

final Provider<TodayRepository> todayRepositoryProvider =
    Provider<TodayRepository>((Ref ref) {
  return DriftTodayRepository(ref.watch(planningDatabaseProvider));
});

final StreamProviderFamily<DailyClosure?, DateTime> dailyClosureProvider =
    StreamProvider.family<DailyClosure?, DateTime>(
  (Ref ref, DateTime localDay) {
    return ref.watch(todayRepositoryProvider).watchClosureForLocalDay(localDay);
  },
);
