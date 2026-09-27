import 'review_entities.dart';

abstract interface class ReviewRepository {
  Stream<ReviewSummary> watchSummary(ReviewPeriod period);

  Future<ReviewSummary> getSummary(ReviewPeriod period);

  Future<PeriodReview> saveReview(PeriodReviewDraft draft);
}
