import 'dart:math';

import 'package:drift/drift.dart';

import '../../planner/data/planning_database.dart';
import '../domain/money_entities.dart';
import '../domain/money_repository.dart';

typedef MoneyUtcClock = DateTime Function();
typedef MoneyIdFactory = String Function(String prefix);

final class DriftMoneyRepository implements MoneyRepository {
  DriftMoneyRepository(
    this._database, {
    MoneyUtcClock? clock,
    MoneyIdFactory? idFactory,
  })  : _clock = clock ?? DateTime.now,
        _idFactory = idFactory;

  final PlanningDatabase _database;
  final MoneyUtcClock _clock;
  final MoneyIdFactory? _idFactory;
  final Random _random = Random.secure();
  int _idCounter = 0;

  @override
  Stream<MoneyDashboard> watchDashboard(DateTime monthContaining) {
    return _database.watchQuery(() => getDashboard(monthContaining));
  }

  @override
  Future<MoneyDashboard> getDashboard(DateTime monthContaining) async {
    final DateTime monthStart = startOfMoneyMonth(monthContaining);
    final DateTime monthEnd = nextMoneyMonth(monthStart);
    final List<MoneyAccount> accounts = (await _database.readRows('''
      SELECT * FROM money_accounts
      ORDER BY is_archived ASC, created_at_utc ASC
    ''')).map(_accountFromRow).toList(growable: false);
    final List<MoneyCategory> categories = (await _database.readRows('''
      SELECT * FROM money_categories
      ORDER BY kind ASC, is_archived ASC, name COLLATE NOCASE ASC
    ''')).map(_categoryFromRow).toList(growable: false);
    final List<MoneyTransaction> allTransactions = (await _database.readRows('''
      SELECT * FROM money_transactions
      WHERE deleted_at_utc IS NULL
      ORDER BY occurred_at_utc DESC, created_at_utc DESC
    ''')).map(_transactionFromRow).toList(growable: false);
    final List<MonthlyBudget> monthlyBudgets = (await _database.readRows('''
      SELECT * FROM money_budgets
      WHERE month_starts_on_local = ? AND deleted_at_utc IS NULL
      ORDER BY created_at_utc ASC
    ''', variables: _strings(<String>[_monthKey(monthStart)])))
        .map(_budgetFromRow)
        .toList(growable: false);
    final List<SavingsGoal> goals = (await _database.readRows('''
      SELECT * FROM savings_goals
      ORDER BY is_archived ASC, created_at_utc ASC
    ''')).map(_savingsGoalFromRow).toList(growable: false);
    final List<SavingsMovement> movements = (await _database.readRows('''
      SELECT * FROM savings_movements
      WHERE deleted_at_utc IS NULL
      ORDER BY occurred_at_utc DESC, created_at_utc DESC
    ''')).map(_savingsMovementFromRow).toList(growable: false);

    final Map<String, int> accountBalances = <String, int>{
      for (final MoneyAccount account in accounts)
        account.id: account.openingBalanceRwf,
    };
    for (final MoneyTransaction transaction in allTransactions) {
      switch (transaction.kind) {
        case MoneyTransactionKind.income:
          accountBalances[transaction.accountId] =
              (accountBalances[transaction.accountId] ?? 0) +
                  transaction.amountRwf;
          break;
        case MoneyTransactionKind.expense:
          accountBalances[transaction.accountId] =
              (accountBalances[transaction.accountId] ?? 0) -
                  transaction.amountRwf;
          break;
        case MoneyTransactionKind.transfer:
          accountBalances[transaction.accountId] =
              (accountBalances[transaction.accountId] ?? 0) -
                  transaction.amountRwf;
          final String destination = transaction.destinationAccountId!;
          accountBalances[destination] =
              (accountBalances[destination] ?? 0) + transaction.amountRwf;
          break;
      }
    }

    final Map<String, int> goalBalances = <String, int>{
      for (final SavingsGoal goal in goals) goal.id: 0,
    };
    for (final SavingsMovement movement in movements) {
      final int sign = movement.kind == SavingsMovementKind.deposit ? 1 : -1;
      goalBalances[movement.goalId] =
          (goalBalances[movement.goalId] ?? 0) + sign * movement.amountRwf;
      accountBalances[movement.accountId] =
          (accountBalances[movement.accountId] ?? 0) -
              sign * movement.amountRwf;
    }

    final List<MoneyTransaction> monthTransactions =
        allTransactions.where((MoneyTransaction transaction) {
      final DateTime local = transaction.occurredAtUtc.toLocal();
      return !local.isBefore(monthStart) && local.isBefore(monthEnd);
    }).toList(growable: false);
    final Map<String, MoneyCategory> categoryById = <String, MoneyCategory>{
      for (final MoneyCategory category in categories) category.id: category,
    };
    final List<BudgetProgress> budgetProgress = monthlyBudgets
        .map(
          (MonthlyBudget budget) => BudgetProgress(
            budget: budget,
            category: categoryById[budget.categoryId]!,
            spentRwf: monthTransactions
                .where(
                  (MoneyTransaction transaction) =>
                      transaction.kind == MoneyTransactionKind.expense &&
                      transaction.categoryId == budget.categoryId,
                )
                .fold<int>(
                  0,
                  (int total, MoneyTransaction transaction) =>
                      total + transaction.amountRwf,
                ),
          ),
        )
        .toList(growable: false);

    return MoneyDashboard(
      monthStartsOnLocal: monthStart,
      accounts: accounts
          .map(
            (MoneyAccount account) => MoneyAccountSummary(
              account: account,
              balanceRwf: accountBalances[account.id] ?? 0,
            ),
          )
          .toList(growable: false),
      categories: categories,
      transactions: monthTransactions,
      budgets: budgetProgress,
      savingsGoals: goals
          .map(
            (SavingsGoal goal) => SavingsGoalProgress(
              goal: goal,
              savedRwf: goalBalances[goal.id] ?? 0,
            ),
          )
          .toList(growable: false),
      savingsMovements: movements,
    );
  }

  @override
  Future<MoneyAccount> createAccount(MoneyAccountDraft draft) async {
    final String name = _requiredText(draft.name, 'Account name');
    if (draft.openingBalanceRwf < 0) {
      throw ArgumentError('Opening balance cannot be negative.');
    }
    _validateColor(draft.colorValue);
    final String id = _newId('account');
    final DateTime now = _clock().toUtc();
    await _database.insertRow('''
      INSERT INTO money_accounts (
        id, name, type, opening_balance_rwf, color_value, is_archived,
        created_at_utc, updated_at_utc, archived_at_utc
      ) VALUES (?, ?, ?, ?, ?, 0, ?, ?, NULL)
    ''', variables: <Variable<Object>>[
      Variable<String>(id),
      Variable<String>(name),
      Variable<String>(draft.type.name),
      Variable<int>(draft.openingBalanceRwf),
      Variable<int>(draft.colorValue),
      Variable<String>(_utc(now)),
      Variable<String>(_utc(now)),
    ]);
    _database.notifyChanged();
    return _readAccount(id);
  }

  @override
  Future<MoneyCategory> createCategory(MoneyCategoryDraft draft) async {
    final String name = _requiredText(draft.name, 'Category name');
    _validateColor(draft.colorValue);
    final String id = _newId('category');
    final DateTime now = _clock().toUtc();
    await _database.insertRow('''
      INSERT INTO money_categories (
        id, name, kind, color_value, is_system, is_archived,
        created_at_utc, updated_at_utc, archived_at_utc
      ) VALUES (?, ?, ?, ?, 0, 0, ?, ?, NULL)
    ''', variables: <Variable<Object>>[
      Variable<String>(id),
      Variable<String>(name),
      Variable<String>(draft.kind.name),
      Variable<int>(draft.colorValue),
      Variable<String>(_utc(now)),
      Variable<String>(_utc(now)),
    ]);
    _database.notifyChanged();
    return _readCategory(id);
  }

  @override
  Future<MoneyTransaction> recordTransaction(
    MoneyTransactionDraft draft,
  ) async {
    if (draft.amountRwf <= 0) {
      throw ArgumentError('Transaction amount must be greater than zero.');
    }
    _validateNotFuture(draft.occurredAtUtc, 'Transaction');
    final MoneyAccount source = await _readAccount(draft.accountId);
    _requireActive(source.isArchived, 'Account');
    switch (draft.kind) {
      case MoneyTransactionKind.income:
      case MoneyTransactionKind.expense:
        if (draft.destinationAccountId != null || draft.categoryId == null) {
          throw ArgumentError('Income and expenses need one category.');
        }
        final MoneyCategory category = await _readCategory(draft.categoryId!);
        _requireActive(category.isArchived, 'Category');
        final MoneyCategoryKind expected =
            draft.kind == MoneyTransactionKind.income
                ? MoneyCategoryKind.income
                : MoneyCategoryKind.expense;
        if (category.kind != expected) {
          throw ArgumentError('The selected category has the wrong type.');
        }
        if (draft.kind == MoneyTransactionKind.expense) {
          await _requireFunds(source.id, draft.amountRwf);
        }
        break;
      case MoneyTransactionKind.transfer:
        if (draft.categoryId != null || draft.destinationAccountId == null) {
          throw ArgumentError('A transfer needs a destination account.');
        }
        if (draft.destinationAccountId == source.id) {
          throw ArgumentError('Transfer accounts must be different.');
        }
        final MoneyAccount destination = await _readAccount(
          draft.destinationAccountId!,
        );
        _requireActive(destination.isArchived, 'Destination account');
        await _requireFunds(source.id, draft.amountRwf);
        break;
    }

    final String id = _newId('transaction');
    final DateTime now = _clock().toUtc();
    await _database.insertRow('''
      INSERT INTO money_transactions (
        id, kind, account_id, destination_account_id, category_id, title,
        amount_rwf, occurred_at_utc, notes, created_at_utc, updated_at_utc,
        deleted_at_utc
      ) VALUES (
        ?, ?, ?, NULLIF(?, ''), NULLIF(?, ''), ?, ?, ?, NULLIF(?, ''),
        ?, ?, NULL
      )
    ''', variables: <Variable<Object>>[
      Variable<String>(id),
      Variable<String>(draft.kind.name),
      Variable<String>(source.id),
      Variable<String>(draft.destinationAccountId ?? ''),
      Variable<String>(draft.categoryId ?? ''),
      Variable<String>(_requiredText(draft.title, 'Transaction title')),
      Variable<int>(draft.amountRwf),
      Variable<String>(_utc(draft.occurredAtUtc)),
      Variable<String>(_optionalText(draft.notes)),
      Variable<String>(_utc(now)),
      Variable<String>(_utc(now)),
    ]);
    _database.notifyChanged();
    return _readTransaction(id);
  }

  @override
  Future<void> voidTransaction(String transactionId) async {
    final MoneyTransaction transaction = await _readTransaction(transactionId);
    if (transaction.deletedAtUtc != null) {
      throw StateError('Transaction is already voided.');
    }
    final MoneyAccount source = await _readAccount(transaction.accountId);
    _requireActive(source.isArchived, 'Account');
    if (transaction.destinationAccountId != null) {
      final MoneyAccount destination =
          await _readAccount(transaction.destinationAccountId!);
      _requireActive(destination.isArchived, 'Destination account');
    }
    if (transaction.kind == MoneyTransactionKind.income) {
      await _requireFunds(transaction.accountId, transaction.amountRwf);
    } else if (transaction.kind == MoneyTransactionKind.transfer) {
      await _requireFunds(
        transaction.destinationAccountId!,
        transaction.amountRwf,
      );
    }
    final DateTime now = _clock().toUtc();
    await _requireUpdated(
      _database.updateRows('''
        UPDATE money_transactions
        SET deleted_at_utc = ?, updated_at_utc = ?
        WHERE id = ? AND deleted_at_utc IS NULL
      ''',
          variables: _strings(<String>[
            _utc(now),
            _utc(now),
            transactionId,
          ])),
      'Transaction',
    );
    _database.notifyChanged();
  }

  @override
  Future<MonthlyBudget> setBudget(MonthlyBudgetDraft draft) async {
    if (draft.limitRwf <= 0) {
      throw ArgumentError('Budget limit must be greater than zero.');
    }
    final MoneyCategory category = await _readCategory(draft.categoryId);
    _requireActive(category.isArchived, 'Category');
    if (category.kind != MoneyCategoryKind.expense) {
      throw ArgumentError('Only expense categories can have budgets.');
    }
    final DateTime month = startOfMoneyMonth(draft.monthStartsOnLocal);
    final DateTime now = _clock().toUtc();
    await _database.insertRow('''
      INSERT INTO money_budgets (
        id, category_id, month_starts_on_local, limit_rwf,
        created_at_utc, updated_at_utc, deleted_at_utc
      ) VALUES (?, ?, ?, ?, ?, ?, NULL)
      ON CONFLICT(category_id, month_starts_on_local) DO UPDATE SET
        limit_rwf = excluded.limit_rwf,
        updated_at_utc = excluded.updated_at_utc,
        deleted_at_utc = NULL
    ''', variables: <Variable<Object>>[
      Variable<String>(_newId('budget')),
      Variable<String>(category.id),
      Variable<String>(_monthKey(month)),
      Variable<int>(draft.limitRwf),
      Variable<String>(_utc(now)),
      Variable<String>(_utc(now)),
    ]);
    _database.notifyChanged();
    return _readBudget(category.id, _monthKey(month));
  }

  @override
  Future<void> removeBudget(String budgetId) async {
    final DateTime now = _clock().toUtc();
    await _requireUpdated(
      _database.updateRows('''
        UPDATE money_budgets
        SET deleted_at_utc = ?, updated_at_utc = ?
        WHERE id = ? AND deleted_at_utc IS NULL
      ''',
          variables: _strings(<String>[
            _utc(now),
            _utc(now),
            budgetId,
          ])),
      'Budget',
    );
    _database.notifyChanged();
  }

  @override
  Future<SavingsGoal> createSavingsGoal(SavingsGoalDraft draft) async {
    if (draft.targetRwf <= 0) {
      throw ArgumentError('Savings target must be greater than zero.');
    }
    _validateColor(draft.colorValue);
    final DateTime? due = draft.dueOnLocal;
    final String id = _newId('savings-goal');
    final DateTime now = _clock().toUtc();
    await _database.insertRow('''
      INSERT INTO savings_goals (
        id, name, target_rwf, due_on_local, color_value, is_archived,
        created_at_utc, updated_at_utc, archived_at_utc
      ) VALUES (?, ?, ?, NULLIF(?, ''), ?, 0, ?, ?, NULL)
    ''', variables: <Variable<Object>>[
      Variable<String>(id),
      Variable<String>(_requiredText(draft.name, 'Savings goal name')),
      Variable<int>(draft.targetRwf),
      Variable<String>(due == null ? '' : _dayKey(due)),
      Variable<int>(draft.colorValue),
      Variable<String>(_utc(now)),
      Variable<String>(_utc(now)),
    ]);
    _database.notifyChanged();
    return _readSavingsGoal(id);
  }

  @override
  Future<SavingsMovement> recordSavingsMovement(
    SavingsMovementDraft draft,
  ) async {
    if (draft.amountRwf <= 0) {
      throw ArgumentError('Savings amount must be greater than zero.');
    }
    _validateNotFuture(draft.occurredAtUtc, 'Savings movement');
    final MoneyAccount account = await _readAccount(draft.accountId);
    final SavingsGoal goal = await _readSavingsGoal(draft.goalId);
    _requireActive(account.isArchived, 'Account');
    _requireActive(goal.isArchived, 'Savings goal');
    if (draft.kind == SavingsMovementKind.deposit) {
      await _requireFunds(account.id, draft.amountRwf);
    } else {
      final int saved = await _savingsBalance(goal.id);
      if (saved < draft.amountRwf) {
        throw StateError('The savings goal does not contain enough money.');
      }
    }
    final String id = _newId('savings-movement');
    final DateTime now = _clock().toUtc();
    await _database.insertRow('''
      INSERT INTO savings_movements (
        id, goal_id, account_id, kind, amount_rwf, occurred_at_utc, notes,
        created_at_utc, updated_at_utc, deleted_at_utc
      ) VALUES (?, ?, ?, ?, ?, ?, NULLIF(?, ''), ?, ?, NULL)
    ''', variables: <Variable<Object>>[
      Variable<String>(id),
      Variable<String>(goal.id),
      Variable<String>(account.id),
      Variable<String>(draft.kind.name),
      Variable<int>(draft.amountRwf),
      Variable<String>(_utc(draft.occurredAtUtc)),
      Variable<String>(_optionalText(draft.notes)),
      Variable<String>(_utc(now)),
      Variable<String>(_utc(now)),
    ]);
    _database.notifyChanged();
    return _readSavingsMovement(id);
  }

  @override
  Future<void> archiveAccount(String accountId) async {
    final MoneyAccount account = await _readAccount(accountId);
    _requireActive(account.isArchived, 'Account');
    final int balance = await _accountBalance(account.id);
    if (balance != 0) {
      throw StateError('Move or spend the remaining RWF before archiving.');
    }
    await _archiveRecord('money_accounts', account.id, 'Account');
  }

  @override
  Future<void> archiveCategory(String categoryId) async {
    final MoneyCategory category = await _readCategory(categoryId);
    _requireActive(category.isArchived, 'Category');
    if (category.isSystem) {
      throw StateError('Built-in categories cannot be archived.');
    }
    await _archiveRecord('money_categories', category.id, 'Category');
  }

  @override
  Future<void> archiveSavingsGoal(String goalId) async {
    final SavingsGoal goal = await _readSavingsGoal(goalId);
    _requireActive(goal.isArchived, 'Savings goal');
    if (await _savingsBalance(goal.id) != 0) {
      throw StateError('Withdraw the saved money before archiving this goal.');
    }
    await _archiveRecord('savings_goals', goal.id, 'Savings goal');
  }

  Future<int> _accountBalance(String accountId) async {
    final List<QueryRow> rows = await _database.readRows('''
      SELECT
        a.opening_balance_rwf
        + COALESCE((
          SELECT SUM(CASE
            WHEN t.kind = 'income' THEN t.amount_rwf
            WHEN t.kind IN ('expense', 'transfer') THEN -t.amount_rwf
            ELSE 0 END)
          FROM money_transactions t
          WHERE t.account_id = a.id AND t.deleted_at_utc IS NULL
        ), 0)
        + COALESCE((
          SELECT SUM(t.amount_rwf)
          FROM money_transactions t
          WHERE t.kind = 'transfer' AND t.destination_account_id = a.id
            AND t.deleted_at_utc IS NULL
        ), 0)
        + COALESCE((
          SELECT SUM(CASE
            WHEN s.kind = 'deposit' THEN -s.amount_rwf
            WHEN s.kind = 'withdrawal' THEN s.amount_rwf
            ELSE 0 END)
          FROM savings_movements s
          WHERE s.account_id = a.id AND s.deleted_at_utc IS NULL
        ), 0) AS balance_rwf
      FROM money_accounts a
      WHERE a.id = ?
    ''', variables: _strings(<String>[accountId]));
    if (rows.isEmpty) throw StateError('Account was not found.');
    return rows.single.read<int>('balance_rwf');
  }

  Future<int> _savingsBalance(String goalId) async {
    final List<QueryRow> rows = await _database.readRows('''
      SELECT COALESCE(SUM(CASE
        WHEN kind = 'deposit' THEN amount_rwf
        WHEN kind = 'withdrawal' THEN -amount_rwf
        ELSE 0 END), 0) AS balance_rwf
      FROM savings_movements
      WHERE goal_id = ? AND deleted_at_utc IS NULL
    ''', variables: _strings(<String>[goalId]));
    return rows.single.read<int>('balance_rwf');
  }

  Future<void> _requireFunds(String accountId, int amountRwf) async {
    if (await _accountBalance(accountId) < amountRwf) {
      throw StateError('The selected account does not contain enough RWF.');
    }
  }

  Future<void> _archiveRecord(
    String table,
    String id,
    String recordName,
  ) async {
    const Set<String> allowed = <String>{
      'money_accounts',
      'money_categories',
      'savings_goals',
    };
    if (!allowed.contains(table)) throw ArgumentError('Invalid archive table.');
    final DateTime now = _clock().toUtc();
    await _requireUpdated(
      _database.updateRows('''
        UPDATE $table
        SET is_archived = 1, archived_at_utc = ?, updated_at_utc = ?
        WHERE id = ? AND is_archived = 0
      ''',
          variables: _strings(<String>[
            _utc(now),
            _utc(now),
            id,
          ])),
      recordName,
    );
    _database.notifyChanged();
  }

  Future<MoneyAccount> _readAccount(String id) async {
    final List<QueryRow> rows = await _database.readRows(
      'SELECT * FROM money_accounts WHERE id = ?',
      variables: _strings(<String>[id]),
    );
    if (rows.isEmpty) throw StateError('Account was not found.');
    return _accountFromRow(rows.single);
  }

  Future<MoneyCategory> _readCategory(String id) async {
    final List<QueryRow> rows = await _database.readRows(
      'SELECT * FROM money_categories WHERE id = ?',
      variables: _strings(<String>[id]),
    );
    if (rows.isEmpty) throw StateError('Category was not found.');
    return _categoryFromRow(rows.single);
  }

  Future<MoneyTransaction> _readTransaction(String id) async {
    final List<QueryRow> rows = await _database.readRows(
      'SELECT * FROM money_transactions WHERE id = ?',
      variables: _strings(<String>[id]),
    );
    if (rows.isEmpty) throw StateError('Transaction was not found.');
    return _transactionFromRow(rows.single);
  }

  Future<MonthlyBudget> _readBudget(String categoryId, String month) async {
    final List<QueryRow> rows = await _database.readRows('''
      SELECT * FROM money_budgets
      WHERE category_id = ? AND month_starts_on_local = ?
        AND deleted_at_utc IS NULL
    ''', variables: _strings(<String>[categoryId, month]));
    if (rows.isEmpty) throw StateError('Budget was not found.');
    return _budgetFromRow(rows.single);
  }

  Future<SavingsGoal> _readSavingsGoal(String id) async {
    final List<QueryRow> rows = await _database.readRows(
      'SELECT * FROM savings_goals WHERE id = ?',
      variables: _strings(<String>[id]),
    );
    if (rows.isEmpty) throw StateError('Savings goal was not found.');
    return _savingsGoalFromRow(rows.single);
  }

  Future<SavingsMovement> _readSavingsMovement(String id) async {
    final List<QueryRow> rows = await _database.readRows(
      'SELECT * FROM savings_movements WHERE id = ?',
      variables: _strings(<String>[id]),
    );
    if (rows.isEmpty) throw StateError('Savings movement was not found.');
    return _savingsMovementFromRow(rows.single);
  }

  MoneyAccount _accountFromRow(QueryRow row) {
    return MoneyAccount(
      id: row.read<String>('id'),
      name: row.read<String>('name'),
      type: MoneyAccountType.values.byName(row.read<String>('type')),
      openingBalanceRwf: row.read<int>('opening_balance_rwf'),
      colorValue: row.read<int>('color_value'),
      isArchived: row.read<int>('is_archived') == 1,
      createdAtUtc: _date(row, 'created_at_utc'),
      updatedAtUtc: _date(row, 'updated_at_utc'),
      archivedAtUtc: _nullableDate(row, 'archived_at_utc'),
    );
  }

  MoneyCategory _categoryFromRow(QueryRow row) {
    return MoneyCategory(
      id: row.read<String>('id'),
      name: row.read<String>('name'),
      kind: MoneyCategoryKind.values.byName(row.read<String>('kind')),
      colorValue: row.read<int>('color_value'),
      isSystem: row.read<int>('is_system') == 1,
      isArchived: row.read<int>('is_archived') == 1,
      createdAtUtc: _date(row, 'created_at_utc'),
      updatedAtUtc: _date(row, 'updated_at_utc'),
      archivedAtUtc: _nullableDate(row, 'archived_at_utc'),
    );
  }

  MoneyTransaction _transactionFromRow(QueryRow row) {
    return MoneyTransaction(
      id: row.read<String>('id'),
      kind: MoneyTransactionKind.values.byName(row.read<String>('kind')),
      accountId: row.read<String>('account_id'),
      destinationAccountId: row.readNullable<String>('destination_account_id'),
      categoryId: row.readNullable<String>('category_id'),
      title: row.read<String>('title'),
      amountRwf: row.read<int>('amount_rwf'),
      occurredAtUtc: _date(row, 'occurred_at_utc'),
      notes: row.readNullable<String>('notes'),
      createdAtUtc: _date(row, 'created_at_utc'),
      updatedAtUtc: _date(row, 'updated_at_utc'),
      deletedAtUtc: _nullableDate(row, 'deleted_at_utc'),
    );
  }

  MonthlyBudget _budgetFromRow(QueryRow row) {
    return MonthlyBudget(
      id: row.read<String>('id'),
      categoryId: row.read<String>('category_id'),
      monthStartsOnLocal: _localDay(row.read<String>('month_starts_on_local')),
      limitRwf: row.read<int>('limit_rwf'),
      createdAtUtc: _date(row, 'created_at_utc'),
      updatedAtUtc: _date(row, 'updated_at_utc'),
    );
  }

  SavingsGoal _savingsGoalFromRow(QueryRow row) {
    final String? due = row.readNullable<String>('due_on_local');
    return SavingsGoal(
      id: row.read<String>('id'),
      name: row.read<String>('name'),
      targetRwf: row.read<int>('target_rwf'),
      dueOnLocal: due == null ? null : _localDay(due),
      colorValue: row.read<int>('color_value'),
      isArchived: row.read<int>('is_archived') == 1,
      createdAtUtc: _date(row, 'created_at_utc'),
      updatedAtUtc: _date(row, 'updated_at_utc'),
      archivedAtUtc: _nullableDate(row, 'archived_at_utc'),
    );
  }

  SavingsMovement _savingsMovementFromRow(QueryRow row) {
    return SavingsMovement(
      id: row.read<String>('id'),
      goalId: row.read<String>('goal_id'),
      accountId: row.read<String>('account_id'),
      kind: SavingsMovementKind.values.byName(row.read<String>('kind')),
      amountRwf: row.read<int>('amount_rwf'),
      occurredAtUtc: _date(row, 'occurred_at_utc'),
      notes: row.readNullable<String>('notes'),
      createdAtUtc: _date(row, 'created_at_utc'),
      updatedAtUtc: _date(row, 'updated_at_utc'),
      deletedAtUtc: _nullableDate(row, 'deleted_at_utc'),
    );
  }

  String _newId(String prefix) {
    final MoneyIdFactory? factory = _idFactory;
    if (factory != null) return factory(prefix);
    _idCounter += 1;
    final String time =
        _clock().toUtc().microsecondsSinceEpoch.toRadixString(36);
    final String random = _random.nextInt(0x7fffffff).toRadixString(36);
    return '$prefix-$time-$random-$_idCounter';
  }

  void _validateNotFuture(DateTime value, String field) {
    if (value.toUtc().isAfter(_clock().toUtc())) {
      throw ArgumentError('$field date cannot be in the future.');
    }
  }
}

void _requireActive(bool isArchived, String recordName) {
  if (isArchived) throw StateError('$recordName is archived.');
}

String _requiredText(String value, String field) {
  final String text = value.trim();
  if (text.isEmpty) {
    throw ArgumentError.value(value, field, '$field cannot be empty.');
  }
  return text;
}

String _optionalText(String? value) => value?.trim() ?? '';

void _validateColor(int value) {
  if (value < 0 || value > 0xFFFFFFFF) {
    throw ArgumentError('Color must be a 32-bit ARGB value.');
  }
}

String _monthKey(DateTime value) {
  final DateTime month = startOfMoneyMonth(value);
  final String number = month.month.toString().padLeft(2, '0');
  return '${month.year}-$number-01';
}

String _dayKey(DateTime value) {
  final DateTime local = value.toLocal();
  final String month = local.month.toString().padLeft(2, '0');
  final String day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

DateTime _localDay(String value) {
  final List<int> parts = value.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

String _utc(DateTime value) => value.toUtc().toIso8601String();

DateTime _date(QueryRow row, String column) {
  return DateTime.parse(row.read<String>(column)).toUtc();
}

DateTime? _nullableDate(QueryRow row, String column) {
  final String? value = row.readNullable<String>(column);
  return value == null ? null : DateTime.parse(value).toUtc();
}

Future<void> _requireUpdated(Future<int> operation, String recordName) async {
  final int count = await operation;
  if (count == 0) throw StateError('$recordName was not found.');
}

List<Variable<Object>> _strings(List<String> values) {
  return values
      .map<Variable<Object>>((String value) => Variable<String>(value))
      .toList(growable: false);
}
