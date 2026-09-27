import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

/// The single local SQLite database used by Gahunda's offline-first features.
///
/// The schema stays explicit and migration-controlled. Domain objects are
/// mapped by repositories, so widgets and application providers never depend
/// on SQL rows.
final class PlanningDatabase extends GeneratedDatabase {
  PlanningDatabase(QueryExecutor executor) : super(executor);

  PlanningDatabase.defaults()
      : super(
          driftDatabase(
            name: 'gahunda',
            native: const DriftNativeOptions(shareAcrossIsolates: true),
            web: DriftWebOptions(
              sqlite3Wasm: Uri.parse('sqlite3.wasm'),
              driftWorker: Uri.parse('drift_worker.dart.js'),
            ),
          ),
        );

  final StreamController<void> _changes = StreamController<void>.broadcast(
    sync: true,
  );

  Stream<void> get changes => _changes.stream;

  void notifyChanged() {
    if (!_changes.isClosed) _changes.add(null);
  }

  /// Runs [load] immediately and again after every repository write.
  ///
  /// The change subscription is installed before the first query, so a write
  /// that happens while that query is running cannot be missed.
  Stream<T> watchQuery<T>(Future<T> Function() load) {
    late final StreamController<T> controller;
    StreamSubscription<void>? subscription;
    bool loading = false;
    bool reloadRequested = false;

    Future<void> emitLatest() async {
      if (loading) {
        reloadRequested = true;
        return;
      }
      loading = true;
      try {
        do {
          reloadRequested = false;
          try {
            final T value = await load();
            if (!controller.isClosed) controller.add(value);
          } on Object catch (error, stackTrace) {
            if (!controller.isClosed) controller.addError(error, stackTrace);
          }
        } while (reloadRequested && !controller.isClosed);
      } finally {
        loading = false;
      }
    }

    controller = StreamController<T>(
      onListen: () {
        subscription = _changes.stream.listen(
          (_) => emitLatest(),
          onDone: controller.close,
        );
        emitLatest();
      },
      onCancel: () async {
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  int get schemaVersion => 8;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      const <TableInfo<Table, Object?>>[];

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      const <DatabaseSchemaEntity>[];

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator _) async {
          await _createVersionOne();
          await _createVersionTwo();
          await _createVersionThree();
          await _createVersionFour();
          await _createVersionFive();
          await _createVersionSix();
          await _createVersionSeven();
          await _createVersionEight();
        },
        onUpgrade: (Migrator _, int from, int to) async {
          if (from < 2) await _createVersionTwo();
          if (from < 3) await _createVersionThree();
          if (from < 4) await _createVersionFour();
          if (from < 5) await _createVersionFive();
          if (from < 6) await _createVersionSix();
          if (from < 7) await _createVersionSeven();
          if (from < 8) await _createVersionEight();
        },
        beforeOpen: (OpeningDetails _) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _createVersionOne() async {
    await customStatement('''
      CREATE TABLE goals (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT NOT NULL CHECK (length(trim(title)) > 0),
        description TEXT,
        scope TEXT NOT NULL CHECK (scope IN ('annual', 'monthly', 'weekly', 'daily')),
        parent_goal_id TEXT REFERENCES goals(id) ON DELETE SET NULL,
        starts_at_utc TEXT,
        due_at_utc TEXT,
        status TEXT NOT NULL CHECK (status IN ('active', 'completed', 'archived')),
        created_at_utc TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL,
        archived_at_utc TEXT
      )
    ''');

    await customStatement('''
      CREATE TABLE plan_periods (
        id TEXT NOT NULL PRIMARY KEY,
        goal_id TEXT REFERENCES goals(id) ON DELETE SET NULL,
        parent_period_id TEXT REFERENCES plan_periods(id) ON DELETE SET NULL,
        label TEXT NOT NULL CHECK (length(trim(label)) > 0),
        scope TEXT NOT NULL CHECK (scope IN ('annual', 'monthly', 'weekly', 'daily')),
        starts_at_utc TEXT NOT NULL,
        ends_at_utc TEXT NOT NULL,
        CHECK (starts_at_utc < ends_at_utc)
      )
    ''');

    await customStatement('''
      CREATE TABLE milestones (
        id TEXT NOT NULL PRIMARY KEY,
        goal_id TEXT REFERENCES goals(id) ON DELETE SET NULL,
        parent_milestone_id TEXT REFERENCES milestones(id) ON DELETE SET NULL,
        plan_period_id TEXT REFERENCES plan_periods(id) ON DELETE SET NULL,
        title TEXT NOT NULL CHECK (length(trim(title)) > 0),
        description TEXT,
        scope TEXT NOT NULL CHECK (scope IN ('annual', 'monthly', 'weekly', 'daily')),
        due_at_utc TEXT,
        status TEXT NOT NULL CHECK (status IN ('pending', 'inProgress', 'completed', 'skipped', 'cancelled')),
        created_at_utc TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL
      )
    ''');

    await customStatement('''
      CREATE TABLE planning_tasks (
        id TEXT NOT NULL PRIMARY KEY,
        goal_id TEXT REFERENCES goals(id) ON DELETE SET NULL,
        milestone_id TEXT REFERENCES milestones(id) ON DELETE SET NULL,
        subject_id TEXT,
        title TEXT NOT NULL CHECK (length(trim(title)) > 0),
        notes TEXT,
        kind TEXT NOT NULL CHECK (kind IN ('general', 'assignment')),
        status TEXT NOT NULL CHECK (status IN ('pending', 'inProgress', 'completed', 'skipped', 'cancelled')),
        scheduled_at_utc TEXT,
        due_at_utc TEXT,
        completed_at_utc TEXT,
        created_at_utc TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL,
        deleted_at_utc TEXT,
        CHECK (kind != 'assignment' OR subject_id IS NOT NULL)
      )
    ''');

    await customStatement('''
      CREATE TABLE time_blocks (
        id TEXT NOT NULL PRIMARY KEY,
        task_id TEXT UNIQUE REFERENCES planning_tasks(id) ON DELETE SET NULL,
        title TEXT NOT NULL CHECK (length(trim(title)) > 0),
        notes TEXT,
        starts_at_utc TEXT NOT NULL,
        ends_at_utc TEXT NOT NULL,
        created_at_utc TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL,
        CHECK (starts_at_utc < ends_at_utc)
      )
    ''');

    await customStatement(
      'CREATE INDEX goals_status_idx ON goals(status)',
    );
    await customStatement(
      'CREATE INDEX periods_goal_idx ON plan_periods(goal_id)',
    );
    await customStatement(
      'CREATE INDEX milestones_goal_idx ON milestones(goal_id)',
    );
    await customStatement(
      'CREATE INDEX tasks_goal_idx ON planning_tasks(goal_id)',
    );
    await customStatement(
      'CREATE INDEX tasks_milestone_idx ON planning_tasks(milestone_id)',
    );
    await customStatement(
      'CREATE INDEX blocks_start_idx ON time_blocks(starts_at_utc)',
    );
  }

  Future<void> _createVersionTwo() async {
    await customStatement('''
      CREATE TABLE daily_closures (
        id TEXT NOT NULL PRIMARY KEY,
        local_day TEXT NOT NULL UNIQUE,
        mood INTEGER NOT NULL CHECK (mood BETWEEN 1 AND 5),
        win TEXT,
        lesson TEXT,
        tomorrow_focus TEXT,
        scheduled_task_count INTEGER NOT NULL CHECK (scheduled_task_count >= 0),
        completed_task_count INTEGER NOT NULL CHECK (completed_task_count >= 0),
        planned_minutes INTEGER NOT NULL CHECK (planned_minutes >= 0),
        completed_minutes INTEGER NOT NULL CHECK (completed_minutes >= 0),
        closed_at_utc TEXT NOT NULL,
        created_at_utc TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL
      )
    ''');
    await customStatement(
      'CREATE INDEX closures_day_idx ON daily_closures(local_day)',
    );
  }

  Future<void> _createVersionThree() async {
    await customStatement('''
      CREATE TABLE academic_terms (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL CHECK (length(trim(name)) > 0),
        starts_on_local TEXT NOT NULL,
        ends_on_local TEXT NOT NULL,
        is_active INTEGER NOT NULL CHECK (is_active IN (0, 1)),
        created_at_utc TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL,
        CHECK (starts_on_local <= ends_on_local)
      )
    ''');

    await customStatement('''
      CREATE TABLE subjects (
        id TEXT NOT NULL PRIMARY KEY,
        term_id TEXT NOT NULL REFERENCES academic_terms(id) ON DELETE RESTRICT,
        name TEXT NOT NULL CHECK (length(trim(name)) > 0),
        code TEXT,
        teacher TEXT,
        default_room TEXT,
        color_value INTEGER NOT NULL CHECK (color_value BETWEEN 0 AND 4294967295),
        created_at_utc TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL,
        UNIQUE (term_id, name COLLATE NOCASE)
      )
    ''');

    await customStatement('''
      CREATE TABLE class_sessions (
        id TEXT NOT NULL PRIMARY KEY,
        subject_id TEXT NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
        weekday INTEGER NOT NULL CHECK (weekday BETWEEN 1 AND 7),
        starts_at_minute INTEGER NOT NULL CHECK (starts_at_minute BETWEEN 0 AND 1439),
        ends_at_minute INTEGER NOT NULL CHECK (ends_at_minute BETWEEN 1 AND 1440),
        room TEXT,
        notes TEXT,
        created_at_utc TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL,
        CHECK (starts_at_minute < ends_at_minute)
      )
    ''');

    await customStatement('''
      CREATE TABLE school_assignments (
        id TEXT NOT NULL PRIMARY KEY,
        subject_id TEXT NOT NULL REFERENCES subjects(id) ON DELETE RESTRICT,
        task_id TEXT NOT NULL UNIQUE REFERENCES planning_tasks(id) ON DELETE RESTRICT,
        due_at_utc TEXT NOT NULL,
        created_at_utc TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL
      )
    ''');

    await customStatement('''
      CREATE TABLE exams (
        id TEXT NOT NULL PRIMARY KEY,
        subject_id TEXT NOT NULL REFERENCES subjects(id) ON DELETE RESTRICT,
        title TEXT NOT NULL CHECK (length(trim(title)) > 0),
        starts_at_utc TEXT NOT NULL,
        ends_at_utc TEXT NOT NULL,
        room TEXT,
        notes TEXT,
        created_at_utc TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL,
        CHECK (starts_at_utc < ends_at_utc)
      )
    ''');

    await customStatement(
      'CREATE UNIQUE INDEX one_active_term_idx '
      'ON academic_terms(is_active) WHERE is_active = 1',
    );
    await customStatement(
      'CREATE INDEX subjects_term_idx ON subjects(term_id)',
    );
    await customStatement(
      'CREATE INDEX sessions_day_idx '
      'ON class_sessions(weekday, starts_at_minute)',
    );
    await customStatement(
      'CREATE INDEX assignments_due_idx ON school_assignments(due_at_utc)',
    );
    await customStatement(
      'CREATE INDEX exams_start_idx ON exams(starts_at_utc)',
    );
  }

  Future<void> _createVersionFour() async {
    await customStatement('''
      CREATE TABLE habits (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL CHECK (length(trim(name)) > 0),
        description TEXT,
        direction TEXT NOT NULL CHECK (direction IN ('build', 'reduce')),
        measurement TEXT NOT NULL CHECK (measurement IN ('binary', 'count', 'minutes')),
        target_value INTEGER NOT NULL CHECK (target_value >= 0),
        unit TEXT NOT NULL CHECK (length(trim(unit)) > 0),
        weekdays_mask INTEGER NOT NULL CHECK (weekdays_mask BETWEEN 1 AND 127),
        preferred_time_minute INTEGER CHECK (
          preferred_time_minute IS NULL OR
          preferred_time_minute BETWEEN 0 AND 1439
        ),
        starts_on_local TEXT NOT NULL,
        ends_on_local TEXT,
        color_value INTEGER NOT NULL CHECK (color_value BETWEEN 0 AND 4294967295),
        is_archived INTEGER NOT NULL CHECK (is_archived IN (0, 1)),
        created_at_utc TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL,
        archived_at_utc TEXT,
        CHECK (ends_on_local IS NULL OR starts_on_local <= ends_on_local),
        CHECK (measurement != 'binary' OR (direction = 'build' AND target_value = 1)),
        CHECK (direction != 'build' OR target_value > 0)
      )
    ''');

    await customStatement('''
      CREATE TABLE habit_check_ins (
        id TEXT NOT NULL PRIMARY KEY,
        habit_id TEXT NOT NULL REFERENCES habits(id) ON DELETE RESTRICT,
        local_day TEXT NOT NULL,
        value INTEGER NOT NULL CHECK (value >= 0),
        note TEXT,
        recorded_at_utc TEXT NOT NULL,
        created_at_utc TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL,
        UNIQUE (habit_id, local_day)
      )
    ''');

    await customStatement(
      'CREATE INDEX habits_active_idx ON habits(is_archived, starts_on_local)',
    );
    await customStatement(
      'CREATE INDEX habit_check_ins_day_idx ON habit_check_ins(local_day)',
    );
    await customStatement(
      'CREATE INDEX habit_check_ins_habit_idx ON habit_check_ins(habit_id)',
    );
  }

  Future<void> _createVersionFive() async {
    await customStatement('''
      CREATE TABLE money_accounts (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE CHECK (length(trim(name)) > 0),
        type TEXT NOT NULL CHECK (type IN ('cash', 'mobileMoney', 'bank', 'savings')),
        opening_balance_rwf INTEGER NOT NULL CHECK (opening_balance_rwf >= 0),
        color_value INTEGER NOT NULL CHECK (color_value BETWEEN 0 AND 4294967295),
        is_archived INTEGER NOT NULL CHECK (is_archived IN (0, 1)),
        created_at_utc TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL,
        archived_at_utc TEXT
      )
    ''');

    await customStatement('''
      CREATE TABLE money_categories (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL CHECK (length(trim(name)) > 0),
        kind TEXT NOT NULL CHECK (kind IN ('expense', 'income')),
        color_value INTEGER NOT NULL CHECK (color_value BETWEEN 0 AND 4294967295),
        is_system INTEGER NOT NULL CHECK (is_system IN (0, 1)),
        is_archived INTEGER NOT NULL CHECK (is_archived IN (0, 1)),
        created_at_utc TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL,
        archived_at_utc TEXT,
        UNIQUE (kind, name COLLATE NOCASE)
      )
    ''');

    await customStatement('''
      CREATE TABLE money_transactions (
        id TEXT NOT NULL PRIMARY KEY,
        kind TEXT NOT NULL CHECK (kind IN ('income', 'expense', 'transfer')),
        account_id TEXT NOT NULL REFERENCES money_accounts(id) ON DELETE RESTRICT,
        destination_account_id TEXT REFERENCES money_accounts(id) ON DELETE RESTRICT,
        category_id TEXT REFERENCES money_categories(id) ON DELETE RESTRICT,
        title TEXT NOT NULL CHECK (length(trim(title)) > 0),
        amount_rwf INTEGER NOT NULL CHECK (amount_rwf > 0),
        occurred_at_utc TEXT NOT NULL,
        notes TEXT,
        created_at_utc TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL,
        deleted_at_utc TEXT,
        CHECK (
          (kind = 'transfer' AND destination_account_id IS NOT NULL AND
           category_id IS NULL AND account_id != destination_account_id) OR
          (kind IN ('income', 'expense') AND destination_account_id IS NULL AND
           category_id IS NOT NULL)
        )
      )
    ''');

    await customStatement('''
      CREATE TABLE money_budgets (
        id TEXT NOT NULL PRIMARY KEY,
        category_id TEXT NOT NULL REFERENCES money_categories(id) ON DELETE RESTRICT,
        month_starts_on_local TEXT NOT NULL,
        limit_rwf INTEGER NOT NULL CHECK (limit_rwf > 0),
        created_at_utc TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL,
        deleted_at_utc TEXT,
        UNIQUE (category_id, month_starts_on_local)
      )
    ''');

    await customStatement('''
      CREATE TABLE savings_goals (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL CHECK (length(trim(name)) > 0),
        target_rwf INTEGER NOT NULL CHECK (target_rwf > 0),
        due_on_local TEXT,
        color_value INTEGER NOT NULL CHECK (color_value BETWEEN 0 AND 4294967295),
        is_archived INTEGER NOT NULL CHECK (is_archived IN (0, 1)),
        created_at_utc TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL,
        archived_at_utc TEXT
      )
    ''');

    await customStatement('''
      CREATE TABLE savings_movements (
        id TEXT NOT NULL PRIMARY KEY,
        goal_id TEXT NOT NULL REFERENCES savings_goals(id) ON DELETE RESTRICT,
        account_id TEXT NOT NULL REFERENCES money_accounts(id) ON DELETE RESTRICT,
        kind TEXT NOT NULL CHECK (kind IN ('deposit', 'withdrawal')),
        amount_rwf INTEGER NOT NULL CHECK (amount_rwf > 0),
        occurred_at_utc TEXT NOT NULL,
        notes TEXT,
        created_at_utc TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL,
        deleted_at_utc TEXT
      )
    ''');

    await customStatement('''
      INSERT INTO money_categories (
        id, name, kind, color_value, is_system, is_archived,
        created_at_utc, updated_at_utc, archived_at_utc
      ) VALUES
        ('money-category-food', 'Food', 'expense', 4294937099, 1, 0, '1970-01-01T00:00:00Z', '1970-01-01T00:00:00Z', NULL),
        ('money-category-transport', 'Transport', 'expense', 4283389905, 1, 0, '1970-01-01T00:00:00Z', '1970-01-01T00:00:00Z', NULL),
        ('money-category-school', 'School', 'expense', 4287906558, 1, 0, '1970-01-01T00:00:00Z', '1970-01-01T00:00:00Z', NULL),
        ('money-category-housing', 'Housing', 'expense', 4282927376, 1, 0, '1970-01-01T00:00:00Z', '1970-01-01T00:00:00Z', NULL),
        ('money-category-health', 'Health', 'expense', 4293854276, 1, 0, '1970-01-01T00:00:00Z', '1970-01-01T00:00:00Z', NULL),
        ('money-category-airtime', 'Airtime & data', 'expense', 4283215696, 1, 0, '1970-01-01T00:00:00Z', '1970-01-01T00:00:00Z', NULL),
        ('money-category-entertainment', 'Entertainment', 'expense', 4287696361, 1, 0, '1970-01-01T00:00:00Z', '1970-01-01T00:00:00Z', NULL),
        ('money-category-giving', 'Giving', 'expense', 4288423856, 1, 0, '1970-01-01T00:00:00Z', '1970-01-01T00:00:00Z', NULL),
        ('money-category-other-expense', 'Other expense', 'expense', 4288585374, 1, 0, '1970-01-01T00:00:00Z', '1970-01-01T00:00:00Z', NULL),
        ('money-category-salary', 'Salary', 'income', 4279217546, 1, 0, '1970-01-01T00:00:00Z', '1970-01-01T00:00:00Z', NULL),
        ('money-category-freelance', 'Freelance', 'income', 4283389905, 1, 0, '1970-01-01T00:00:00Z', '1970-01-01T00:00:00Z', NULL),
        ('money-category-allowance', 'Allowance', 'income', 4288423856, 1, 0, '1970-01-01T00:00:00Z', '1970-01-01T00:00:00Z', NULL),
        ('money-category-gift', 'Gift', 'income', 4287906558, 1, 0, '1970-01-01T00:00:00Z', '1970-01-01T00:00:00Z', NULL),
        ('money-category-other-income', 'Other income', 'income', 4288585374, 1, 0, '1970-01-01T00:00:00Z', '1970-01-01T00:00:00Z', NULL)
    ''');

    await customStatement(
      'CREATE INDEX money_transactions_date_idx '
      'ON money_transactions(occurred_at_utc, deleted_at_utc)',
    );
    await customStatement(
      'CREATE INDEX money_transactions_account_idx '
      'ON money_transactions(account_id, destination_account_id)',
    );
    await customStatement(
      'CREATE INDEX money_budgets_month_idx '
      'ON money_budgets(month_starts_on_local, deleted_at_utc)',
    );
    await customStatement(
      'CREATE INDEX savings_movements_goal_idx '
      'ON savings_movements(goal_id, deleted_at_utc)',
    );
  }

  Future<void> _createVersionSix() async {
    await customStatement('''
      CREATE TABLE period_reviews (
        id TEXT NOT NULL PRIMARY KEY,
        cadence TEXT NOT NULL CHECK (cadence IN ('weekly', 'monthly', 'annual')),
        period_starts_on_local TEXT NOT NULL,
        overall_rating INTEGER NOT NULL CHECK (overall_rating BETWEEN 1 AND 5),
        wins TEXT NOT NULL CHECK (length(trim(wins)) > 0),
        challenges TEXT,
        lessons TEXT,
        next_focus TEXT NOT NULL CHECK (length(trim(next_focus)) > 0),
        created_at_utc TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL,
        UNIQUE (cadence, period_starts_on_local)
      )
    ''');
    await customStatement(
      'CREATE INDEX period_reviews_period_idx '
      'ON period_reviews(cadence, period_starts_on_local)',
    );
  }

  Future<void> _createVersionSeven() async {
    await customStatement('''
      CREATE TABLE sync_metadata (
        singleton_id INTEGER NOT NULL PRIMARY KEY CHECK (singleton_id = 1),
        owner_user_id TEXT,
        device_id TEXT NOT NULL CHECK (length(trim(device_id)) > 0),
        remote_revision INTEGER NOT NULL CHECK (remote_revision >= 0),
        base_fingerprint TEXT,
        last_synced_at_utc TEXT,
        last_error TEXT,
        updated_at_utc TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createVersionEight() async {
    await customStatement('''
      CREATE TABLE notification_preferences (
        singleton_id INTEGER NOT NULL PRIMARY KEY CHECK (singleton_id = 1),
        enabled INTEGER NOT NULL CHECK (enabled IN (0, 1)),
        task_enabled INTEGER NOT NULL CHECK (task_enabled IN (0, 1)),
        class_enabled INTEGER NOT NULL CHECK (class_enabled IN (0, 1)),
        assignment_enabled INTEGER NOT NULL CHECK (assignment_enabled IN (0, 1)),
        exam_enabled INTEGER NOT NULL CHECK (exam_enabled IN (0, 1)),
        habit_enabled INTEGER NOT NULL CHECK (habit_enabled IN (0, 1)),
        daily_closure_enabled INTEGER NOT NULL CHECK (daily_closure_enabled IN (0, 1)),
        class_lead_minutes INTEGER NOT NULL CHECK (class_lead_minutes >= 0),
        assignment_lead_minutes INTEGER NOT NULL CHECK (assignment_lead_minutes >= 0),
        exam_lead_minutes INTEGER NOT NULL CHECK (exam_lead_minutes >= 0),
        daily_closure_minute INTEGER NOT NULL CHECK (daily_closure_minute BETWEEN 0 AND 1439),
        updated_at_utc TEXT NOT NULL
      )
    ''');
    await customStatement('''
      INSERT INTO notification_preferences (
        singleton_id, enabled, task_enabled, class_enabled,
        assignment_enabled, exam_enabled, habit_enabled,
        daily_closure_enabled, class_lead_minutes,
        assignment_lead_minutes, exam_lead_minutes,
        daily_closure_minute, updated_at_utc
      ) VALUES (1, 0, 1, 1, 1, 1, 1, 0, 10, 1440, 60, 1230,
        '1970-01-01T00:00:00Z')
    ''');
  }

  Future<List<QueryRow>> readRows(
    String sql, {
    List<Variable<Object>> variables = const <Variable<Object>>[],
  }) {
    return customSelect(sql, variables: variables).get();
  }

  Future<int> insertRow(
    String sql, {
    List<Variable<Object>> variables = const <Variable<Object>>[],
  }) {
    return customInsert(sql, variables: variables);
  }

  Future<int> updateRows(
    String sql, {
    List<Variable<Object>> variables = const <Variable<Object>>[],
  }) {
    return customUpdate(sql, variables: variables);
  }

  Future<void> executeStatement(
    String sql, [
    List<Object?> parameters = const <Object?>[],
  ]) {
    return customStatement(sql, parameters);
  }

  @override
  Future<void> close() async {
    await _changes.close();
    await super.close();
  }
}
