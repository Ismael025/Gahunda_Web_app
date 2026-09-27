import 'package:drift/drift.dart';

import '../../planner/data/planning_database.dart';
import '../domain/notification_entities.dart';

final class NotificationPreferencesRepository {
  const NotificationPreferencesRepository(this._database);

  final PlanningDatabase _database;

  Future<NotificationPreferences> load() async {
    final List<QueryRow> rows = await _database.readRows(
      'SELECT * FROM notification_preferences WHERE singleton_id = 1',
    );
    if (rows.isEmpty) return const NotificationPreferences.defaults();
    final QueryRow row = rows.single;
    return NotificationPreferences(
      enabled: row.read<int>('enabled') == 1,
      taskEnabled: row.read<int>('task_enabled') == 1,
      classEnabled: row.read<int>('class_enabled') == 1,
      assignmentEnabled: row.read<int>('assignment_enabled') == 1,
      examEnabled: row.read<int>('exam_enabled') == 1,
      habitEnabled: row.read<int>('habit_enabled') == 1,
      dailyClosureEnabled: row.read<int>('daily_closure_enabled') == 1,
      classLeadMinutes: row.read<int>('class_lead_minutes'),
      assignmentLeadMinutes: row.read<int>('assignment_lead_minutes'),
      examLeadMinutes: row.read<int>('exam_lead_minutes'),
      dailyClosureMinute: row.read<int>('daily_closure_minute'),
    );
  }

  Future<void> save(NotificationPreferences preferences) {
    return _database.executeStatement(
      '''
        UPDATE notification_preferences SET
          enabled = ?, task_enabled = ?, class_enabled = ?,
          assignment_enabled = ?, exam_enabled = ?, habit_enabled = ?,
          daily_closure_enabled = ?, class_lead_minutes = ?,
          assignment_lead_minutes = ?, exam_lead_minutes = ?,
          daily_closure_minute = ?, updated_at_utc = ?
        WHERE singleton_id = 1
      ''',
      <Object?>[
        preferences.enabled ? 1 : 0,
        preferences.taskEnabled ? 1 : 0,
        preferences.classEnabled ? 1 : 0,
        preferences.assignmentEnabled ? 1 : 0,
        preferences.examEnabled ? 1 : 0,
        preferences.habitEnabled ? 1 : 0,
        preferences.dailyClosureEnabled ? 1 : 0,
        preferences.classLeadMinutes,
        preferences.assignmentLeadMinutes,
        preferences.examLeadMinutes,
        preferences.dailyClosureMinute,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }
}
