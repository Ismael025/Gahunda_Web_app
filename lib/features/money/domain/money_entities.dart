enum MoneyAccountType { cash, mobileMoney, bank, savings }

enum MoneyCategoryKind { expense, income }

enum MoneyTransactionKind { income, expense, transfer }

enum SavingsMovementKind { deposit, withdrawal }

class MoneyAccount {
  const MoneyAccount({
    required this.id,
    required this.name,
    required this.type,
    required this.openingBalanceRwf,
    required this.colorValue,
    required this.isArchived,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.archivedAtUtc,
  });

  final String id;
  final String name;
  final MoneyAccountType type;
  final int openingBalanceRwf;
  final int colorValue;
  final bool isArchived;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final DateTime? archivedAtUtc;
}

class MoneyAccountSummary {
  const MoneyAccountSummary({required this.account, required this.balanceRwf});

  final MoneyAccount account;
  final int balanceRwf;
}

class MoneyCategory {
  const MoneyCategory({
    required this.id,
    required this.name,
    required this.kind,
    required this.colorValue,
    required this.isSystem,
    required this.isArchived,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.archivedAtUtc,
  });

  final String id;
  final String name;
  final MoneyCategoryKind kind;
  final int colorValue;
  final bool isSystem;
  final bool isArchived;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final DateTime? archivedAtUtc;
}

class MoneyTransaction {
  const MoneyTransaction({
    required this.id,
    required this.kind,
    required this.accountId,
    required this.title,
    required this.amountRwf,
    required this.occurredAtUtc,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.destinationAccountId,
    this.categoryId,
    this.notes,
    this.deletedAtUtc,
  });

  final String id;
  final MoneyTransactionKind kind;
  final String accountId;
  final String? destinationAccountId;
  final String? categoryId;
  final String title;
  final int amountRwf;
  final DateTime occurredAtUtc;
  final String? notes;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final DateTime? deletedAtUtc;
}

class MonthlyBudget {
  const MonthlyBudget({
    required this.id,
    required this.categoryId,
    required this.monthStartsOnLocal,
    required this.limitRwf,
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });

  final String id;
  final String categoryId;
  final DateTime monthStartsOnLocal;
  final int limitRwf;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
}

class BudgetProgress {
  const BudgetProgress({
    required this.budget,
    required this.category,
    required this.spentRwf,
  });

  final MonthlyBudget budget;
  final MoneyCategory category;
  final int spentRwf;

  int get remainingRwf => budget.limitRwf - spentRwf;

  bool get isOverBudget => remainingRwf < 0;

  double get progress => budget.limitRwf == 0
      ? 0
      : (spentRwf / budget.limitRwf).clamp(0.0, 1.0).toDouble();
}

class SavingsGoal {
  const SavingsGoal({
    required this.id,
    required this.name,
    required this.targetRwf,
    required this.colorValue,
    required this.isArchived,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.dueOnLocal,
    this.archivedAtUtc,
  });

  final String id;
  final String name;
  final int targetRwf;
  final DateTime? dueOnLocal;
  final int colorValue;
  final bool isArchived;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final DateTime? archivedAtUtc;
}

class SavingsGoalProgress {
  const SavingsGoalProgress({required this.goal, required this.savedRwf});

  final SavingsGoal goal;
  final int savedRwf;

  int get remainingRwf => goal.targetRwf - savedRwf;

  bool get isReached => savedRwf >= goal.targetRwf;

  double get progress => goal.targetRwf == 0
      ? 0
      : (savedRwf / goal.targetRwf).clamp(0.0, 1.0).toDouble();
}

class SavingsMovement {
  const SavingsMovement({
    required this.id,
    required this.goalId,
    required this.accountId,
    required this.kind,
    required this.amountRwf,
    required this.occurredAtUtc,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.notes,
    this.deletedAtUtc,
  });

  final String id;
  final String goalId;
  final String accountId;
  final SavingsMovementKind kind;
  final int amountRwf;
  final DateTime occurredAtUtc;
  final String? notes;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final DateTime? deletedAtUtc;
}

class MoneyDashboard {
  const MoneyDashboard({
    required this.monthStartsOnLocal,
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.budgets,
    required this.savingsGoals,
    required this.savingsMovements,
  });

  final DateTime monthStartsOnLocal;
  final List<MoneyAccountSummary> accounts;
  final List<MoneyCategory> categories;
  final List<MoneyTransaction> transactions;
  final List<BudgetProgress> budgets;
  final List<SavingsGoalProgress> savingsGoals;
  final List<SavingsMovement> savingsMovements;

  List<MoneyAccountSummary> get activeAccounts => accounts
      .where((MoneyAccountSummary item) => !item.account.isArchived)
      .toList(growable: false);

  List<MoneyCategory> categoriesFor(MoneyCategoryKind kind) => categories
      .where(
        (MoneyCategory category) =>
            !category.isArchived && category.kind == kind,
      )
      .toList(growable: false);

  List<SavingsGoalProgress> get activeSavingsGoals => savingsGoals
      .where((SavingsGoalProgress item) => !item.goal.isArchived)
      .toList(growable: false);

  int get totalSpendableRwf => activeAccounts.fold<int>(
        0,
        (int total, MoneyAccountSummary item) => total + item.balanceRwf,
      );

  int get totalSavedRwf => activeSavingsGoals.fold<int>(
        0,
        (int total, SavingsGoalProgress item) => total + item.savedRwf,
      );

  int get netWorthRwf => totalSpendableRwf + totalSavedRwf;

  int get monthlySpentRwf => transactions
      .where(
          (MoneyTransaction item) => item.kind == MoneyTransactionKind.expense)
      .fold<int>(
          0, (int total, MoneyTransaction item) => total + item.amountRwf);

  int get monthlyIncomeRwf => transactions
      .where(
          (MoneyTransaction item) => item.kind == MoneyTransactionKind.income)
      .fold<int>(
          0, (int total, MoneyTransaction item) => total + item.amountRwf);

  int spentOnLocalDay(DateTime localDay) => transactions
      .where(
        (MoneyTransaction item) =>
            item.kind == MoneyTransactionKind.expense &&
            _sameLocalDay(item.occurredAtUtc.toLocal(), localDay),
      )
      .fold<int>(
          0, (int total, MoneyTransaction item) => total + item.amountRwf);

  int incomeOnLocalDay(DateTime localDay) => transactions
      .where(
        (MoneyTransaction item) =>
            item.kind == MoneyTransactionKind.income &&
            _sameLocalDay(item.occurredAtUtc.toLocal(), localDay),
      )
      .fold<int>(
          0, (int total, MoneyTransaction item) => total + item.amountRwf);

  MoneyAccountSummary? accountById(String id) {
    for (final MoneyAccountSummary item in accounts) {
      if (item.account.id == id) return item;
    }
    return null;
  }

  MoneyCategory? categoryById(String? id) {
    if (id == null) return null;
    for (final MoneyCategory item in categories) {
      if (item.id == id) return item;
    }
    return null;
  }
}

class MoneyAccountDraft {
  const MoneyAccountDraft({
    required this.name,
    required this.type,
    required this.openingBalanceRwf,
    required this.colorValue,
  });

  final String name;
  final MoneyAccountType type;
  final int openingBalanceRwf;
  final int colorValue;
}

class MoneyCategoryDraft {
  const MoneyCategoryDraft({
    required this.name,
    required this.kind,
    required this.colorValue,
  });

  final String name;
  final MoneyCategoryKind kind;
  final int colorValue;
}

class MoneyTransactionDraft {
  const MoneyTransactionDraft({
    required this.kind,
    required this.accountId,
    required this.title,
    required this.amountRwf,
    required this.occurredAtUtc,
    this.destinationAccountId,
    this.categoryId,
    this.notes,
  });

  final MoneyTransactionKind kind;
  final String accountId;
  final String? destinationAccountId;
  final String? categoryId;
  final String title;
  final int amountRwf;
  final DateTime occurredAtUtc;
  final String? notes;
}

class MonthlyBudgetDraft {
  const MonthlyBudgetDraft({
    required this.categoryId,
    required this.monthStartsOnLocal,
    required this.limitRwf,
  });

  final String categoryId;
  final DateTime monthStartsOnLocal;
  final int limitRwf;
}

class SavingsGoalDraft {
  const SavingsGoalDraft({
    required this.name,
    required this.targetRwf,
    required this.colorValue,
    this.dueOnLocal,
  });

  final String name;
  final int targetRwf;
  final DateTime? dueOnLocal;
  final int colorValue;
}

class SavingsMovementDraft {
  const SavingsMovementDraft({
    required this.goalId,
    required this.accountId,
    required this.kind,
    required this.amountRwf,
    required this.occurredAtUtc,
    this.notes,
  });

  final String goalId;
  final String accountId;
  final SavingsMovementKind kind;
  final int amountRwf;
  final DateTime occurredAtUtc;
  final String? notes;
}

DateTime startOfMoneyMonth(DateTime value) {
  final DateTime local = value.toLocal();
  return DateTime(local.year, local.month);
}

DateTime nextMoneyMonth(DateTime monthStart) {
  return DateTime(monthStart.year, monthStart.month + 1);
}

bool _sameLocalDay(DateTime first, DateTime second) {
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}
