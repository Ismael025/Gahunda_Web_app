import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../planner/application/planning_providers.dart';
import '../data/drift_habit_repository.dart';
import '../domain/habit_entities.dart';
import '../domain/habit_repository.dart';

final Provider<HabitRepository> habitRepositoryProvider =
    Provider<HabitRepository>((Ref ref) {
  return DriftHabitRepository(ref.watch(planningDatabaseProvider));
});

final StreamProviderFamily<HabitDashboard, DateTime> habitDashboardProvider =
    StreamProvider.family<HabitDashboard, DateTime>(
  (Ref ref, DateTime localDay) {
    return ref.watch(habitRepositoryProvider).watchDashboard(localDay);
  },
);

/// A small UI intent used by the global Quick add sheet.
///
/// Keeping the actual dialog inside Track means the shell does not need to
/// know how a habit is edited or validated.
final NotifierProvider<HabitCreateRequests, int> habitCreateRequestProvider =
    NotifierProvider<HabitCreateRequests, int>(HabitCreateRequests.new);

class HabitCreateRequests extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state += 1;
}
