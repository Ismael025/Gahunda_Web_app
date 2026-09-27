import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gahunda/features/notifications/application/notification_providers.dart';
import 'package:gahunda/features/notifications/data/drift_reminder_source.dart';
import 'package:gahunda/features/notifications/data/notification_gateway.dart';
import 'package:gahunda/features/notifications/data/notification_preferences_repository.dart';
import 'package:gahunda/features/notifications/domain/notification_entities.dart';
import 'package:gahunda/features/planner/data/planning_database.dart';

void main() {
  test('notification preferences default off and persist per database',
      () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final NotificationPreferencesRepository repository =
        NotificationPreferencesRepository(database);

    final NotificationPreferences initial = await repository.load();
    expect(initial.enabled, isFalse);
    expect(initial.taskEnabled, isTrue);
    expect(NotificationPreferences.taskLeadMinutes, 5);

    final NotificationPreferences changed = initial.copyWith(
      enabled: true,
      classLeadMinutes: 30,
      dailyClosureEnabled: true,
      dailyClosureMinute: 21 * 60,
    );
    await repository.save(changed);
    final NotificationPreferences restored = await repository.load();
    expect(restored.enabled, isTrue);
    expect(restored.classLeadMinutes, 30);
    expect(restored.dailyClosureEnabled, isTrue);
    expect(restored.dailyClosureMinute, 1260);
  });

  test('task reminder stays exactly five minutes before its current start',
      () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final DriftReminderSource source = DriftReminderSource(database);
    final DateTime now = DateTime(2026, 9, 9, 9);
    DateTime startsAt = DateTime(2026, 9, 9, 10);
    await _insertTask(database, startsAt: startsAt);

    List<ReminderRequest> requests = await source.buildRequests(
      preferences: _onlyTasks,
      now: now,
    );
    expect(requests, hasLength(1));
    expect(requests.single.kind, ReminderKind.task);
    expect(
      startsAt.difference(requests.single.scheduledAtUtc.toLocal()),
      const Duration(minutes: 5),
    );
    final int stableId = requests.single.id;

    startsAt = startsAt.add(const Duration(hours: 2));
    await database.executeStatement(
      'UPDATE planning_tasks SET scheduled_at_utc = ? WHERE id = ?',
      <Object?>[startsAt.toUtc().toIso8601String(), 'task-1'],
    );
    requests = await source.buildRequests(
      preferences: _onlyTasks,
      now: now,
    );
    expect(requests.single.id, stableId);
    expect(
      startsAt.difference(requests.single.scheduledAtUtc.toLocal()),
      const Duration(minutes: 5),
    );
  });

  test('completed, cancelled, deleted, and past tasks do not remind', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final DriftReminderSource source = DriftReminderSource(database);
    final DateTime now = DateTime(2026, 9, 9, 9);
    await _insertTask(
      database,
      id: 'completed',
      status: 'completed',
      startsAt: DateTime(2026, 9, 9, 10),
    );
    await _insertTask(
      database,
      id: 'cancelled',
      status: 'cancelled',
      startsAt: DateTime(2026, 9, 9, 11),
    );
    await _insertTask(
      database,
      id: 'deleted',
      startsAt: DateTime(2026, 9, 9, 12),
      deleted: true,
    );
    await _insertTask(
      database,
      id: 'past',
      startsAt: DateTime(2026, 9, 9, 8),
    );

    expect(
      await source.buildRequests(preferences: _onlyTasks, now: now),
      isEmpty,
    );
  });

  test('class reminders repeat weekly only inside active term boundaries',
      () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await _insertSchoolFoundation(database);
    await database.executeStatement('''
      INSERT INTO class_sessions (
        id, subject_id, weekday, starts_at_minute, ends_at_minute,
        room, notes, created_at_utc, updated_at_utc
      ) VALUES (
        'class-1', 'subject-1', 3, 600, 660, 'Room A', NULL,
        '2026-09-09T00:00:00Z', '2026-09-09T00:00:00Z'
      )
    ''');
    final List<ReminderRequest> requests =
        await DriftReminderSource(database).buildRequests(
      preferences: _onlyClasses,
      now: DateTime(2026, 9, 9, 8),
    );

    expect(requests, hasLength(2));
    expect(requests.every((ReminderRequest item) {
      final DateTime local = item.scheduledAtUtc.toLocal();
      return local.weekday == DateTime.wednesday &&
          local.hour == 9 &&
          local.minute == 50;
    }), isTrue);
    expect(requests.first.sourceKey, contains('2026-09-09'));
    expect(requests.last.sourceKey, contains('2026-09-16'));
  });

  test('assignment and exam reminders use their configured lead times',
      () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await _insertSchoolFoundation(database);
    final DateTime dueAt = DateTime(2026, 9, 10, 12);
    await _insertTask(
      database,
      id: 'assignment-task',
      title: 'Submit database report',
      kind: 'assignment',
      subjectId: 'subject-1',
      dueAt: dueAt,
    );
    await database.executeStatement(
      '''
        INSERT INTO school_assignments (
          id, subject_id, task_id, due_at_utc, created_at_utc, updated_at_utc
        ) VALUES ('assignment-1', 'subject-1', 'assignment-task', ?,
          '2026-09-09T00:00:00Z', '2026-09-09T00:00:00Z')
      ''',
      <Object?>[dueAt.toUtc().toIso8601String()],
    );
    final DateTime examAt = DateTime(2026, 9, 10, 15);
    await database.executeStatement(
      '''
        INSERT INTO exams (
          id, subject_id, title, starts_at_utc, ends_at_utc, room, notes,
          created_at_utc, updated_at_utc
        ) VALUES ('exam-1', 'subject-1', 'Database exam', ?, ?, 'Hall', NULL,
          '2026-09-09T00:00:00Z', '2026-09-09T00:00:00Z')
      ''',
      <Object?>[
        examAt.toUtc().toIso8601String(),
        examAt.add(const Duration(hours: 2)).toUtc().toIso8601String(),
      ],
    );

    final List<ReminderRequest> requests =
        await DriftReminderSource(database).buildRequests(
      preferences: _assignmentsAndExams,
      now: DateTime(2026, 9, 9, 8),
    );
    final ReminderRequest assignment = requests.singleWhere(
      (ReminderRequest item) => item.kind == ReminderKind.assignment,
    );
    final ReminderRequest exam = requests.singleWhere(
      (ReminderRequest item) => item.kind == ReminderKind.exam,
    );
    expect(
      dueAt.difference(assignment.scheduledAtUtc.toLocal()),
      const Duration(days: 1),
    );
    expect(
      examAt.difference(exam.scheduledAtUtc.toLocal()),
      const Duration(hours: 1),
    );
  });

  test('timed habits and an unfinished day produce local reminders', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.executeStatement('''
      INSERT INTO habits (
        id, name, description, direction, measurement, target_value, unit,
        weekdays_mask, preferred_time_minute, starts_on_local, ends_on_local,
        color_value, is_archived, created_at_utc, updated_at_utc,
        archived_at_utc
      ) VALUES (
        'habit-1', 'Read', NULL, 'build', 'binary', 1, 'done', 4, 540,
        '2026-09-09', '2026-09-09', 4279217546, 0,
        '2026-09-09T00:00:00Z', '2026-09-09T00:00:00Z', NULL
      )
    ''');
    final DriftReminderSource source = DriftReminderSource(database);
    List<ReminderRequest> requests = await source.buildRequests(
      preferences: _habitsAndClosure,
      now: DateTime(2026, 9, 9, 8),
    );
    expect(
      requests.where((ReminderRequest item) => item.kind == ReminderKind.habit),
      hasLength(1),
    );
    expect(
      requests.where(
        (ReminderRequest item) => item.kind == ReminderKind.dailyClosure,
      ),
      hasLength(7),
    );

    await database.executeStatement('''
      INSERT INTO daily_closures (
        id, local_day, mood, win, lesson, tomorrow_focus,
        scheduled_task_count, completed_task_count, planned_minutes,
        completed_minutes, closed_at_utc, created_at_utc, updated_at_utc
      ) VALUES (
        'closure-1', '2026-09-09', 4, NULL, NULL, NULL, 0, 0, 0, 0,
        '2026-09-09T18:00:00Z', '2026-09-09T18:00:00Z',
        '2026-09-09T18:00:00Z'
      )
    ''');
    await database.executeStatement('''
      INSERT INTO habit_check_ins (
        id, habit_id, local_day, value, note, recorded_at_utc,
        created_at_utc, updated_at_utc
      ) VALUES (
        'check-in-1', 'habit-1', '2026-09-09', 1, NULL,
        '2026-09-09T08:10:00Z', '2026-09-09T08:10:00Z',
        '2026-09-09T08:10:00Z'
      )
    ''');
    requests = await source.buildRequests(
      preferences: _habitsAndClosure,
      now: DateTime(2026, 9, 9, 8),
    );
    expect(
      requests.where(
        (ReminderRequest item) => item.kind == ReminderKind.dailyClosure,
      ),
      hasLength(6),
    );
    expect(
      requests.where((ReminderRequest item) => item.kind == ReminderKind.habit),
      isEmpty,
    );
  });

  test('notification identifiers are deterministic and source-specific', () {
    expect(stableNotificationId('task:one'), stableNotificationId('task:one'));
    expect(
      stableNotificationId('task:one'),
      isNot(stableNotificationId('task:two')),
    );
    expect(stableNotificationId('task:one'), greaterThan(0));
  });

  test('database changes replace reminders and remove completed tasks',
      () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final NotificationPreferencesRepository repository =
        NotificationPreferencesRepository(database);
    final _FakeNotificationGateway gateway = _FakeNotificationGateway();
    final DateTime startsAt = DateTime.now().add(const Duration(hours: 1));
    await _insertTask(database, startsAt: startsAt);
    await repository.save(_onlyTasks);
    final NotificationController controller = NotificationController(
      database: database,
      preferencesRepository: repository,
      reminderSource: DriftReminderSource(database),
      gateway: gateway,
      rebuildDelay: Duration.zero,
    );
    addTearDown(() async {
      controller.dispose();
      await database.close();
    });

    await controller.initialize();
    expect(gateway.requests, hasLength(1));

    await database.executeStatement(
      "UPDATE planning_tasks SET status = 'completed' WHERE id = 'task-1'",
    );
    database.notifyChanged();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(gateway.requests, isEmpty);
  });

  test('schema version 7 adds device preferences without losing synced data',
      () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'gahunda-notification-migration-',
    );
    final File file = File('${directory.path}/migration.sqlite');
    addTearDown(() => directory.delete(recursive: true));
    final PlanningDatabase setup = PlanningDatabase(NativeDatabase(file));
    await setup.executeStatement('''
      INSERT INTO goals (
        id, title, description, scope, parent_goal_id, starts_at_utc,
        due_at_utc, status, created_at_utc, updated_at_utc, archived_at_utc
      ) VALUES (
        'goal-1', 'Protected goal', NULL, 'annual', NULL, NULL, NULL,
        'active', '2026-09-09T00:00:00Z', '2026-09-09T00:00:00Z', NULL
      )
    ''');
    await setup.executeStatement('DROP TABLE notification_preferences');
    await setup.executeStatement('PRAGMA user_version = 7');
    await setup.close();

    final PlanningDatabase upgraded = PlanningDatabase(NativeDatabase(file));
    addTearDown(upgraded.close);
    final NotificationPreferences preferences =
        await NotificationPreferencesRepository(upgraded).load();
    expect(preferences.enabled, isFalse);
    expect(
      (await upgraded.readRows("SELECT title FROM goals WHERE id = 'goal-1'"))
          .single
          .read<String>('title'),
      'Protected goal',
    );
  });
}

const NotificationPreferences _onlyTasks = NotificationPreferences(
  enabled: true,
  taskEnabled: true,
  classEnabled: false,
  assignmentEnabled: false,
  examEnabled: false,
  habitEnabled: false,
  dailyClosureEnabled: false,
  classLeadMinutes: 10,
  assignmentLeadMinutes: 1440,
  examLeadMinutes: 60,
  dailyClosureMinute: 1230,
);

const NotificationPreferences _onlyClasses = NotificationPreferences(
  enabled: true,
  taskEnabled: false,
  classEnabled: true,
  assignmentEnabled: false,
  examEnabled: false,
  habitEnabled: false,
  dailyClosureEnabled: false,
  classLeadMinutes: 10,
  assignmentLeadMinutes: 1440,
  examLeadMinutes: 60,
  dailyClosureMinute: 1230,
);

const NotificationPreferences _assignmentsAndExams = NotificationPreferences(
  enabled: true,
  taskEnabled: false,
  classEnabled: false,
  assignmentEnabled: true,
  examEnabled: true,
  habitEnabled: false,
  dailyClosureEnabled: false,
  classLeadMinutes: 10,
  assignmentLeadMinutes: 1440,
  examLeadMinutes: 60,
  dailyClosureMinute: 1230,
);

const NotificationPreferences _habitsAndClosure = NotificationPreferences(
  enabled: true,
  taskEnabled: false,
  classEnabled: false,
  assignmentEnabled: false,
  examEnabled: false,
  habitEnabled: true,
  dailyClosureEnabled: true,
  classLeadMinutes: 10,
  assignmentLeadMinutes: 1440,
  examLeadMinutes: 60,
  dailyClosureMinute: 1230,
);

Future<void> _insertTask(
  PlanningDatabase database, {
  String id = 'task-1',
  String title = 'Prepare presentation',
  String kind = 'general',
  String status = 'pending',
  String? subjectId,
  DateTime? startsAt,
  DateTime? dueAt,
  bool deleted = false,
}) {
  return database.executeStatement(
    '''
      INSERT INTO planning_tasks (
        id, goal_id, milestone_id, subject_id, title, notes, kind, status,
        scheduled_at_utc, due_at_utc, completed_at_utc, created_at_utc,
        updated_at_utc, deleted_at_utc
      ) VALUES (?, NULL, NULL, ?, ?, NULL, ?, ?, ?, ?, NULL,
        '2026-09-09T00:00:00Z', '2026-09-09T00:00:00Z', ?)
    ''',
    <Object?>[
      id,
      subjectId,
      title,
      kind,
      status,
      startsAt?.toUtc().toIso8601String(),
      dueAt?.toUtc().toIso8601String(),
      deleted ? '2026-09-09T00:00:00Z' : null,
    ],
  );
}

Future<void> _insertSchoolFoundation(PlanningDatabase database) async {
  await database.executeStatement('''
    INSERT INTO academic_terms (
      id, name, starts_on_local, ends_on_local, is_active,
      created_at_utc, updated_at_utc
    ) VALUES (
      'term-1', 'Term one', '2026-09-09', '2026-09-16', 1,
      '2026-09-09T00:00:00Z', '2026-09-09T00:00:00Z'
    )
  ''');
  await database.executeStatement('''
    INSERT INTO subjects (
      id, term_id, name, code, teacher, default_room, color_value,
      created_at_utc, updated_at_utc
    ) VALUES (
      'subject-1', 'term-1', 'Databases', 'DB', NULL, 'Room A',
      4279217546, '2026-09-09T00:00:00Z', '2026-09-09T00:00:00Z'
    )
  ''');
}

final class _FakeNotificationGateway implements NotificationGateway {
  List<ReminderRequest> requests = <ReminderRequest>[];

  @override
  bool get supportsBackgroundScheduling => true;

  @override
  Future<String> initialize() async => 'Africa/Kigali';

  @override
  Future<int> pendingCount() async => requests.length;

  @override
  Future<ReminderPermissionResult> requestPermissions() async {
    return const ReminderPermissionResult(
      notificationsAllowed: true,
      exactTimingAllowed: true,
    );
  }

  @override
  Future<void> replaceAll(
    List<ReminderRequest> requests, {
    required bool exactTiming,
  }) async {
    this.requests = List<ReminderRequest>.from(requests);
  }

  @override
  Future<void> showTestNotification() async {}
}
