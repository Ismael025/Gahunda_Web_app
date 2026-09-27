import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../planner/application/planning_providers.dart';
import '../data/drift_money_repository.dart';
import '../domain/money_entities.dart';
import '../domain/money_repository.dart';

final Provider<MoneyRepository> moneyRepositoryProvider =
    Provider<MoneyRepository>((Ref ref) {
  return DriftMoneyRepository(ref.watch(planningDatabaseProvider));
});

final StreamProviderFamily<MoneyDashboard, DateTime> moneyDashboardProvider =
    StreamProvider.family<MoneyDashboard, DateTime>(
  (Ref ref, DateTime monthContaining) {
    return ref.watch(moneyRepositoryProvider).watchDashboard(monthContaining);
  },
);

final NotifierProvider<ExpenseCreateRequests, int>
    expenseCreateRequestProvider =
    NotifierProvider<ExpenseCreateRequests, int>(ExpenseCreateRequests.new);

class ExpenseCreateRequests extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state += 1;
}
