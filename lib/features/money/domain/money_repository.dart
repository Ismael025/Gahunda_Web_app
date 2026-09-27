import 'money_entities.dart';

abstract interface class MoneyRepository {
  Stream<MoneyDashboard> watchDashboard(DateTime monthContaining);

  Future<MoneyDashboard> getDashboard(DateTime monthContaining);

  Future<MoneyAccount> createAccount(MoneyAccountDraft draft);

  Future<MoneyCategory> createCategory(MoneyCategoryDraft draft);

  Future<MoneyTransaction> recordTransaction(MoneyTransactionDraft draft);

  Future<void> voidTransaction(String transactionId);

  Future<MonthlyBudget> setBudget(MonthlyBudgetDraft draft);

  Future<void> removeBudget(String budgetId);

  Future<SavingsGoal> createSavingsGoal(SavingsGoalDraft draft);

  Future<SavingsMovement> recordSavingsMovement(SavingsMovementDraft draft);

  Future<void> archiveAccount(String accountId);

  Future<void> archiveCategory(String categoryId);

  Future<void> archiveSavingsGoal(String goalId);
}
