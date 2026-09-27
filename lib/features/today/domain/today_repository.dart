import 'today_entities.dart';

abstract interface class TodayRepository {
  Stream<DailyClosure?> watchClosureForLocalDay(DateTime localDay);

  Future<DailyClosure?> getClosureForLocalDay(DateTime localDay);

  Future<DailyClosure> closeDay(DailyClosureDraft draft);
}
