import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gahunda/features/money/data/drift_money_repository.dart';
import 'package:gahunda/features/money/domain/money_entities.dart';
import 'package:gahunda/features/planner/data/planning_database.dart';

void main() {
  final DateTime fixedNow = DateTime(2026, 9, 9, 12);
  int id = 0;

  DriftMoneyRepository repository(PlanningDatabase database) {
    return DriftMoneyRepository(
      database,
      clock: () => fixedNow,
      idFactory: (String prefix) => '$prefix-${id++}',
    );
  }

  Future<MoneyAccount> createAccount(
    DriftMoneyRepository money, {
    String name = 'MTN MoMo',
    int openingBalance = 100000,
    MoneyAccountType type = MoneyAccountType.mobileMoney,
  }) {
    return money.createAccount(
      MoneyAccountDraft(
        name: name,
        type: type,
        openingBalanceRwf: openingBalance,
        colorValue: 0xFFFFCC00,
      ),
    );
  }

  Future<MoneyCategory> category(
    DriftMoneyRepository money,
    String name,
  ) async {
    return (await money.getDashboard(fixedNow))
        .categories
        .singleWhere((MoneyCategory item) => item.name == name);
  }

  Future<MoneyTransaction> record(
    DriftMoneyRepository money, {
    required MoneyTransactionKind kind,
    required MoneyAccount account,
    required int amount,
    required String title,
    MoneyCategory? category,
    MoneyAccount? destination,
    DateTime? occurredAt,
  }) {
    return money.recordTransaction(
      MoneyTransactionDraft(
        kind: kind,
        accountId: account.id,
        destinationAccountId: destination?.id,
        categoryId: category?.id,
        title: title,
        amountRwf: amount,
        occurredAtUtc: (occurredAt ?? fixedNow).toUtc(),
      ),
    );
  }

  setUp(() => id = 0);

  test('starts with useful categories and creates an RWF account', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftMoneyRepository money = repository(database);
    addTearDown(database.close);

    MoneyDashboard dashboard = await money.getDashboard(fixedNow);
    expect(dashboard.categoriesFor(MoneyCategoryKind.expense), hasLength(9));
    expect(dashboard.categoriesFor(MoneyCategoryKind.income), hasLength(5));

    await createAccount(money, openingBalance: 125000);
    dashboard = await money.getDashboard(fixedNow);
    expect(dashboard.activeAccounts.single.account.name, 'MTN MoMo');
    expect(dashboard.totalSpendableRwf, 125000);
    expect(dashboard.netWorthRwf, 125000);
  });

  test('income and expenses reconcile the account and monthly totals',
      () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftMoneyRepository money = repository(database);
    addTearDown(database.close);
    final MoneyAccount account = await createAccount(money);
    final MoneyCategory salary = await category(money, 'Salary');
    final MoneyCategory food = await category(money, 'Food');

    await record(
      money,
      kind: MoneyTransactionKind.income,
      account: account,
      category: salary,
      amount: 50000,
      title: 'Project payment',
    );
    await record(
      money,
      kind: MoneyTransactionKind.expense,
      account: account,
      category: food,
      amount: 20000,
      title: 'Groceries',
    );

    final MoneyDashboard dashboard = await money.getDashboard(fixedNow);
    expect(dashboard.activeAccounts.single.balanceRwf, 130000);
    expect(dashboard.monthlyIncomeRwf, 50000);
    expect(dashboard.monthlySpentRwf, 20000);
    expect(dashboard.spentOnLocalDay(fixedNow), 20000);
  });

  test('a transfer changes account balances but conserves total money',
      () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftMoneyRepository money = repository(database);
    addTearDown(database.close);
    final MoneyAccount cash = await createAccount(
      money,
      name: 'Cash',
      openingBalance: 100000,
      type: MoneyAccountType.cash,
    );
    final MoneyAccount bank = await createAccount(
      money,
      name: 'Bank',
      openingBalance: 10000,
      type: MoneyAccountType.bank,
    );

    final MoneyTransaction transfer = await record(
      money,
      kind: MoneyTransactionKind.transfer,
      account: cash,
      destination: bank,
      amount: 30000,
      title: 'Deposit cash',
    );

    final MoneyDashboard dashboard = await money.getDashboard(fixedNow);
    expect(dashboard.accountById(cash.id)?.balanceRwf, 70000);
    expect(dashboard.accountById(bank.id)?.balanceRwf, 40000);
    expect(dashboard.totalSpendableRwf, 110000);
    expect(dashboard.monthlyIncomeRwf, 0);
    expect(dashboard.monthlySpentRwf, 0);

    await money.voidTransaction(transfer.id);
    final MoneyDashboard reversed = await money.getDashboard(fixedNow);
    expect(reversed.accountById(cash.id)?.balanceRwf, 100000);
    expect(reversed.accountById(bank.id)?.balanceRwf, 10000);
    expect(reversed.totalSpendableRwf, 110000);
  });

  test('wrong category types and overspending are rejected', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftMoneyRepository money = repository(database);
    addTearDown(database.close);
    final MoneyAccount account = await createAccount(
      money,
      openingBalance: 10000,
    );
    final MoneyCategory food = await category(money, 'Food');

    await expectLater(
      record(
        money,
        kind: MoneyTransactionKind.income,
        account: account,
        category: food,
        amount: 5000,
        title: 'Wrong income category',
      ),
      throwsArgumentError,
    );
    await expectLater(
      record(
        money,
        kind: MoneyTransactionKind.expense,
        account: account,
        category: food,
        amount: 10001,
        title: 'Too much',
      ),
      throwsStateError,
    );
    expect((await money.getDashboard(fixedNow)).totalSpendableRwf, 10000);
  });

  test('category budgets use expenses only and report overspending', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftMoneyRepository money = repository(database);
    addTearDown(database.close);
    final MoneyAccount account = await createAccount(
      money,
      openingBalance: 200000,
    );
    final MoneyCategory food = await category(money, 'Food');
    final MoneyCategory transport = await category(money, 'Transport');
    await money.setBudget(
      MonthlyBudgetDraft(
        categoryId: food.id,
        monthStartsOnLocal: fixedNow,
        limitRwf: 50000,
      ),
    );
    for (final int amount in <int>[30000, 25000]) {
      await record(
        money,
        kind: MoneyTransactionKind.expense,
        account: account,
        category: food,
        amount: amount,
        title: 'Food expense',
      );
    }
    await record(
      money,
      kind: MoneyTransactionKind.expense,
      account: account,
      category: transport,
      amount: 10000,
      title: 'Bus fare',
    );

    final BudgetProgress budget =
        (await money.getDashboard(fixedNow)).budgets.single;
    expect(budget.spentRwf, 55000);
    expect(budget.remainingRwf, -5000);
    expect(budget.isOverBudget, isTrue);
    expect(budget.progress, 1);
  });

  test('savings deposits and withdrawals conserve net worth', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftMoneyRepository money = repository(database);
    addTearDown(database.close);
    final MoneyAccount account = await createAccount(money);
    final SavingsGoal goal = await money.createSavingsGoal(
      const SavingsGoalDraft(
        name: 'Laptop',
        targetRwf: 500000,
        colorValue: 0xFF0F9D8A,
      ),
    );

    await money.recordSavingsMovement(
      SavingsMovementDraft(
        goalId: goal.id,
        accountId: account.id,
        kind: SavingsMovementKind.deposit,
        amountRwf: 40000,
        occurredAtUtc: fixedNow.toUtc(),
      ),
    );
    MoneyDashboard dashboard = await money.getDashboard(fixedNow);
    expect(dashboard.totalSpendableRwf, 60000);
    expect(dashboard.totalSavedRwf, 40000);
    expect(dashboard.netWorthRwf, 100000);

    await money.recordSavingsMovement(
      SavingsMovementDraft(
        goalId: goal.id,
        accountId: account.id,
        kind: SavingsMovementKind.withdrawal,
        amountRwf: 15000,
        occurredAtUtc: fixedNow.toUtc(),
      ),
    );
    dashboard = await money.getDashboard(fixedNow);
    expect(dashboard.totalSpendableRwf, 75000);
    expect(dashboard.totalSavedRwf, 25000);
    expect(dashboard.netWorthRwf, 100000);
    await expectLater(
      money.recordSavingsMovement(
        SavingsMovementDraft(
          goalId: goal.id,
          accountId: account.id,
          kind: SavingsMovementKind.withdrawal,
          amountRwf: 25001,
          occurredAtUtc: fixedNow.toUtc(),
        ),
      ),
      throwsStateError,
    );
  });

  test('archive rules protect balances and built-in categories', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftMoneyRepository money = repository(database);
    addTearDown(database.close);
    final MoneyAccount account = await createAccount(
      money,
      openingBalance: 10000,
    );
    final MoneyAccount empty = await createAccount(
      money,
      name: 'Empty cash',
      openingBalance: 0,
      type: MoneyAccountType.cash,
    );
    final SavingsGoal goal = await money.createSavingsGoal(
      const SavingsGoalDraft(
        name: 'Emergency fund',
        targetRwf: 100000,
        colorValue: 0xFF4F46E5,
      ),
    );
    final MoneyCategory food = await category(money, 'Food');
    final MoneyCategory custom = await money.createCategory(
      const MoneyCategoryDraft(
        name: 'Books',
        kind: MoneyCategoryKind.expense,
        colorValue: 0xFF4F46E5,
      ),
    );

    await expectLater(money.archiveAccount(account.id), throwsStateError);
    await money.archiveAccount(empty.id);
    await expectLater(money.archiveCategory(food.id), throwsStateError);
    await money.archiveCategory(custom.id);
    await money.archiveSavingsGoal(goal.id);
    expect(
      (await money.getDashboard(fixedNow)).activeSavingsGoals,
      isEmpty,
    );
    expect(
      (await money.getDashboard(fixedNow))
          .activeAccounts
          .any((MoneyAccountSummary item) => item.account.id == empty.id),
      isFalse,
    );
    expect(
      (await money.getDashboard(fixedNow))
          .categoriesFor(MoneyCategoryKind.expense)
          .any((MoneyCategory item) => item.id == custom.id),
      isFalse,
    );
  });

  test('voiding an entry reverses its effect without deleting history',
      () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftMoneyRepository money = repository(database);
    addTearDown(database.close);
    final MoneyAccount account = await createAccount(money, openingBalance: 0);
    final MoneyCategory salary = await category(money, 'Salary');
    final MoneyTransaction transaction = await record(
      money,
      kind: MoneyTransactionKind.income,
      account: account,
      category: salary,
      amount: 20000,
      title: 'Allowance',
    );

    await money.voidTransaction(transaction.id);
    final MoneyDashboard dashboard = await money.getDashboard(fixedNow);
    expect(dashboard.totalSpendableRwf, 0);
    expect(dashboard.transactions, isEmpty);
    expect(
      await database.readRows(
        'SELECT * FROM money_transactions WHERE deleted_at_utc IS NOT NULL',
      ),
      hasLength(1),
    );
  });

  test('month and day totals use occurrence time while balances use history',
      () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftMoneyRepository money = repository(database);
    addTearDown(database.close);
    final MoneyAccount account = await createAccount(
      money,
      openingBalance: 100000,
    );
    final MoneyCategory food = await category(money, 'Food');
    await record(
      money,
      kind: MoneyTransactionKind.expense,
      account: account,
      category: food,
      amount: 10000,
      title: 'August food',
      occurredAt: DateTime(2026, 8, 31, 18),
    );
    await record(
      money,
      kind: MoneyTransactionKind.expense,
      account: account,
      category: food,
      amount: 5000,
      title: 'September food',
    );

    final MoneyDashboard september = await money.getDashboard(fixedNow);
    expect(september.monthlySpentRwf, 5000);
    expect(september.spentOnLocalDay(fixedNow), 5000);
    expect(september.totalSpendableRwf, 85000);
    final MoneyDashboard august = await money.getDashboard(DateTime(2026, 8));
    expect(august.monthlySpentRwf, 10000);
  });

  test('money dashboard stream refreshes after ledger writes', () async {
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    final DriftMoneyRepository money = repository(database);
    addTearDown(database.close);
    final StreamIterator<MoneyDashboard> iterator =
        StreamIterator<MoneyDashboard>(money.watchDashboard(fixedNow));
    addTearDown(iterator.cancel);

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.activeAccounts, isEmpty);
    await createAccount(money, openingBalance: 75000);
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.totalSpendableRwf, 75000);
  });

  test('accounts, budgets, savings, and entries persist after reopening',
      () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'gahunda-money-',
    );
    final File file = File('${directory.path}/money.sqlite');
    addTearDown(() => directory.delete(recursive: true));

    PlanningDatabase database = PlanningDatabase(NativeDatabase(file));
    DriftMoneyRepository money = repository(database);
    final MoneyAccount account = await createAccount(money);
    final MoneyCategory food = await category(money, 'Food');
    final SavingsGoal goal = await money.createSavingsGoal(
      const SavingsGoalDraft(
        name: 'New laptop',
        targetRwf: 600000,
        colorValue: 0xFF4F46E5,
      ),
    );
    await record(
      money,
      kind: MoneyTransactionKind.expense,
      account: account,
      category: food,
      amount: 10000,
      title: 'Lunch',
    );
    await money.setBudget(
      MonthlyBudgetDraft(
        categoryId: food.id,
        monthStartsOnLocal: fixedNow,
        limitRwf: 30000,
      ),
    );
    await money.recordSavingsMovement(
      SavingsMovementDraft(
        goalId: goal.id,
        accountId: account.id,
        kind: SavingsMovementKind.deposit,
        amountRwf: 20000,
        occurredAtUtc: fixedNow.toUtc(),
      ),
    );
    await database.close();

    database = PlanningDatabase(NativeDatabase(file));
    money = repository(database);
    addTearDown(database.close);
    final MoneyDashboard dashboard = await money.getDashboard(fixedNow);
    expect(dashboard.totalSpendableRwf, 70000);
    expect(dashboard.totalSavedRwf, 20000);
    expect(dashboard.netWorthRwf, 90000);
    expect(dashboard.monthlySpentRwf, 10000);
    expect(dashboard.budgets.single.spentRwf, 10000);
  });

  test('schema version 4 upgrades without losing existing habit data',
      () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'gahunda-money-migration-',
    );
    final File file = File('${directory.path}/migration.sqlite');
    addTearDown(() => directory.delete(recursive: true));

    final PlanningDatabase setup = PlanningDatabase(NativeDatabase(file));
    await setup.customStatement('''
      INSERT INTO habits (
        id, name, description, direction, measurement, target_value, unit,
        weekdays_mask, preferred_time_minute, starts_on_local, ends_on_local,
        color_value, is_archived, created_at_utc, updated_at_utc,
        archived_at_utc
      ) VALUES (
        'existing-habit', 'Keep reading', NULL, 'build', 'binary', 1, 'done',
        127, NULL, '2026-09-01', NULL, 4279217546, 0,
        '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z', NULL
      )
    ''');
    for (final String table in <String>[
      'notification_preferences',
      'sync_metadata',
      'period_reviews',
      'money_budgets',
      'money_transactions',
      'savings_movements',
      'savings_goals',
      'money_categories',
      'money_accounts',
    ]) {
      await setup.customStatement('DROP TABLE $table');
    }
    await setup.customStatement('PRAGMA user_version = 4');
    await setup.close();

    final PlanningDatabase upgraded = PlanningDatabase(NativeDatabase(file));
    addTearDown(upgraded.close);
    expect(
      (await upgraded.readRows(
        "SELECT name FROM habits WHERE id = 'existing-habit'",
      ))
          .single
          .read<String>('name'),
      'Keep reading',
    );
    expect(
      await upgraded.readRows('SELECT * FROM money_categories'),
      hasLength(14),
    );
  });
}
