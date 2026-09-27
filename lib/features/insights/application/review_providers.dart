import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../planner/application/planning_providers.dart';
import '../data/drift_review_repository.dart';
import '../domain/review_entities.dart';
import '../domain/review_repository.dart';

final Provider<ReviewRepository> reviewRepositoryProvider =
    Provider<ReviewRepository>((Ref ref) {
  return DriftReviewRepository(ref.watch(planningDatabaseProvider));
});

final StreamProviderFamily<ReviewSummary, ReviewPeriod> reviewSummaryProvider =
    StreamProvider.family<ReviewSummary, ReviewPeriod>(
  (Ref ref, ReviewPeriod period) {
    return ref.watch(reviewRepositoryProvider).watchSummary(period);
  },
);
