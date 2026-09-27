import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../planner/application/planning_providers.dart';
import '../data/drift_school_repository.dart';
import '../domain/school_entities.dart';
import '../domain/school_repository.dart';

final Provider<SchoolRepository> schoolRepositoryProvider =
    Provider<SchoolRepository>((Ref ref) {
  return DriftSchoolRepository(ref.watch(planningDatabaseProvider));
});

final StreamProviderFamily<SchoolWeekData, DateTime> schoolWeekProvider =
    StreamProvider.family<SchoolWeekData, DateTime>(
  (Ref ref, DateTime weekContaining) {
    return ref.watch(schoolRepositoryProvider).watchSchoolWeek(weekContaining);
  },
);
