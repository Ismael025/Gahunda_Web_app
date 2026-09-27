import 'habit_entities.dart';

abstract interface class HabitRepository {
  Stream<HabitDashboard> watchDashboard(DateTime localDay);

  Future<HabitDashboard> getDashboard(DateTime localDay);

  Future<Habit> createHabit(HabitDraft draft);

  Future<Habit> updateHabit(String habitId, HabitDraft draft);

  Future<HabitCheckIn> recordCheckIn(HabitCheckInDraft draft);

  Future<void> clearCheckIn(String habitId, DateTime localDay);

  Future<void> archiveHabit(String habitId);
}
