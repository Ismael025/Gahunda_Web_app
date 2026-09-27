import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/drift_planning_repository.dart';
import '../data/planning_database.dart';
import '../domain/planning_entities.dart';
import '../domain/planning_repository.dart';

final Provider<PlanningDatabase> planningDatabaseProvider =
    Provider<PlanningDatabase>((Ref ref) {
  final PlanningDatabase database = PlanningDatabase.defaults();
  ref.onDispose(database.close);
  return database;
});

final Provider<PlanningRepository> planningRepositoryProvider =
    Provider<PlanningRepository>((Ref ref) {
  final DriftPlanningRepository repository = DriftPlanningRepository(
    ref.watch(planningDatabaseProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

final StreamProvider<List<PlanningPath>> planningPathsProvider =
    StreamProvider<List<PlanningPath>>(
  (Ref ref) {
    return ref.watch(planningRepositoryProvider).watchPlanningPaths();
  },
);

final StreamProviderFamily<List<ScheduledPlanningTask>, DateTime>
    tasksForLocalDayProvider =
    StreamProvider.family<List<ScheduledPlanningTask>, DateTime>(
  (
    Ref ref,
    DateTime localDay,
  ) {
    return ref
        .watch(planningRepositoryProvider)
        .watchTasksForLocalDay(localDay);
  },
);

final StreamProvider<List<PlanningTask>> unscheduledTasksProvider =
    StreamProvider<List<PlanningTask>>(
  (Ref ref) {
    return ref.watch(planningRepositoryProvider).watchUnscheduledTasks();
  },
);
