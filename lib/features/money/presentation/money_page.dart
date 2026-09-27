import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_components.dart';
import '../application/money_providers.dart';
import '../domain/money_entities.dart';

class MoneyPage extends ConsumerStatefulWidget {
  const MoneyPage({super.key});

  @override
  ConsumerState<MoneyPage> createState() => _MoneyPageState();
}

class _MoneyPageState extends ConsumerState<MoneyPage> {
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    _selectedMonth = startOfMoneyMonth(DateTime.now());
  }

  Future<void> _run(
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    try {
      await action();
      if (mounted && successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(error))),
        );
      }
    }
  }

  Future<void> _createAccount() async {
    final MoneyAccountDraft? draft = await showDialog<MoneyAccountDraft>(
      context: context,
      builder: (BuildContext context) => const _AccountDialog(),
    );
    if (draft == null || !mounted) return;
    await _run(
      () async {
        await ref.read(moneyRepositoryProvider).createAccount(draft);
      },
      successMessage: 'Account saved locally.',
    );
  }

  Future<void> _createCategory() async {
    final MoneyCategoryDraft? draft = await showDialog<MoneyCategoryDraft>(
      context: context,
      builder: (BuildContext context) => const _CategoryDialog(),
    );
    if (draft == null || !mounted) return;
    await _run(
      () async {
        await ref.read(moneyRepositoryProvider).createCategory(draft);
      },
      successMessage: 'Category saved locally.',
    );
  }

  Future<void> _recordTransaction(
    MoneyDashboard dashboard,
    MoneyTransactionKind kind,
  ) async {
    if (dashboard.activeAccounts.isEmpty) {
      _showMessage('Create an account before recording money.');
      return;
    }
    if (kind == MoneyTransactionKind.transfer &&
        dashboard.activeAccounts.length < 2) {
      _showMessage('A transfer needs two active accounts.');
      return;
    }
    final MoneyCategoryKind? categoryKind = switch (kind) {
      MoneyTransactionKind.expense => MoneyCategoryKind.expense,
      MoneyTransactionKind.income => MoneyCategoryKind.income,
      MoneyTransactionKind.transfer => null,
    };
    if (categoryKind != null && dashboard.categoriesFor(categoryKind).isEmpty) {
      _showMessage('Create an active ${categoryKind.name} category first.');
      return;
    }

    final MoneyTransactionDraft? draft =
        await showDialog<MoneyTransactionDraft>(
      context: context,
      builder: (BuildContext context) => _TransactionDialog(
        kind: kind,
        dashboard: dashboard,
      ),
    );
    if (draft == null || !mounted) return;
    await _run(
      () async {
        await ref.read(moneyRepositoryProvider).recordTransaction(draft);
        final DateTime entryMonth =
            startOfMoneyMonth(draft.occurredAtUtc.toLocal());
        if (mounted && !_sameMonth(_selectedMonth, entryMonth)) {
          setState(() => _selectedMonth = entryMonth);
        }
      },
      successMessage: '${_transactionKindLabel(kind)} recorded.',
    );
  }

  Future<void> _setBudget(
    MoneyDashboard dashboard, {
    BudgetProgress? existing,
  }) async {
    final List<MoneyCategory> expenseCategories =
        dashboard.categoriesFor(MoneyCategoryKind.expense);
    final Set<String> used = dashboard.budgets
        .map((BudgetProgress item) => item.category.id)
        .toSet();
    final List<MoneyCategory> available = existing == null
        ? expenseCategories
            .where((MoneyCategory category) => !used.contains(category.id))
            .toList(growable: false)
        : expenseCategories;
    if (available.isEmpty) {
      _showMessage(
        expenseCategories.isEmpty
            ? 'Create an expense category before setting a budget.'
            : 'Every expense category already has a budget this month.',
      );
      return;
    }
    final MonthlyBudgetDraft? draft = await showDialog<MonthlyBudgetDraft>(
      context: context,
      builder: (BuildContext context) => _BudgetDialog(
        month: dashboard.monthStartsOnLocal,
        categories: available,
        existing: existing,
      ),
    );
    if (draft == null || !mounted) return;
    await _run(
      () async {
        await ref.read(moneyRepositoryProvider).setBudget(draft);
      },
      successMessage: 'Monthly budget saved.',
    );
  }

  Future<void> _createSavingsGoal() async {
    final SavingsGoalDraft? draft = await showDialog<SavingsGoalDraft>(
      context: context,
      builder: (BuildContext context) => const _SavingsGoalDialog(),
    );
    if (draft == null || !mounted) return;
    await _run(
      () async {
        await ref.read(moneyRepositoryProvider).createSavingsGoal(draft);
      },
      successMessage: 'Savings goal saved locally.',
    );
  }

  Future<void> _moveSavings(
    MoneyDashboard dashboard,
    SavingsGoalProgress goal,
    SavingsMovementKind kind,
  ) async {
    if (dashboard.activeAccounts.isEmpty) {
      _showMessage('Create an active account before moving savings.');
      return;
    }
    if (kind == SavingsMovementKind.withdrawal && goal.savedRwf == 0) {
      _showMessage('This goal has no money to withdraw.');
      return;
    }
    final SavingsMovementDraft? draft = await showDialog<SavingsMovementDraft>(
      context: context,
      builder: (BuildContext context) => _SavingsMovementDialog(
        goal: goal,
        accounts: dashboard.activeAccounts,
        kind: kind,
      ),
    );
    if (draft == null || !mounted) return;
    await _run(
      () async {
        await ref.read(moneyRepositoryProvider).recordSavingsMovement(draft);
      },
      successMessage: kind == SavingsMovementKind.deposit
          ? 'Savings deposit recorded.'
          : 'Savings withdrawal recorded.',
    );
  }

  Future<void> _removeBudget(BudgetProgress item) async {
    if (!await _confirm(
      title: 'Remove budget?',
      message:
          'Transactions stay in your ledger. Only this monthly limit is removed.',
      actionLabel: 'Remove',
    )) {
      return;
    }
    await _run(
      () => ref.read(moneyRepositoryProvider).removeBudget(item.budget.id),
      successMessage: 'Budget removed.',
    );
  }

  Future<void> _voidTransaction(MoneyTransaction transaction) async {
    if (!await _confirm(
      title: 'Void this transaction?',
      message:
          'The entry remains in local history, but its effect on balances is reversed.',
      actionLabel: 'Void',
    )) {
      return;
    }
    await _run(
      () => ref.read(moneyRepositoryProvider).voidTransaction(transaction.id),
      successMessage: 'Transaction voided.',
    );
  }

  Future<void> _archiveAccount(MoneyAccountSummary account) async {
    if (!await _confirm(
      title: 'Archive ${account.account.name}?',
      message: account.balanceRwf == 0
          ? 'The account disappears from new entries; its history remains.'
          : 'This account still has ${_formatRwf(account.balanceRwf)}. Move or spend it before archiving.',
      actionLabel: 'Archive',
    )) {
      return;
    }
    await _run(
      () =>
          ref.read(moneyRepositoryProvider).archiveAccount(account.account.id),
      successMessage: 'Account archived.',
    );
  }

  Future<void> _archiveCategory(MoneyCategory category) async {
    if (!await _confirm(
      title: 'Archive ${category.name}?',
      message:
          'Past transactions keep this category, but it cannot be selected again.',
      actionLabel: 'Archive',
    )) {
      return;
    }
    await _run(
      () => ref.read(moneyRepositoryProvider).archiveCategory(category.id),
      successMessage: 'Category archived.',
    );
  }

  Future<void> _archiveGoal(SavingsGoalProgress goal) async {
    if (!await _confirm(
      title: 'Archive ${goal.goal.name}?',
      message: goal.savedRwf == 0
          ? 'The goal disappears from active savings; its history remains.'
          : 'Withdraw ${_formatRwf(goal.savedRwf)} before archiving this goal.',
      actionLabel: 'Archive',
    )) {
      return;
    }
    await _run(
      () => ref.read(moneyRepositoryProvider).archiveSavingsGoal(goal.goal.id),
      successMessage: 'Savings goal archived.',
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String actionLabel,
  }) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _moveMonth(int offset) {
    final DateTime candidate =
        DateTime(_selectedMonth.year, _selectedMonth.month + offset);
    final DateTime current = startOfMoneyMonth(DateTime.now());
    if (candidate.isAfter(current)) return;
    setState(() => _selectedMonth = candidate);
  }

  Future<void> _openQuickExpense() async {
    final DateTime current = startOfMoneyMonth(DateTime.now());
    if (!_sameMonth(_selectedMonth, current)) {
      setState(() => _selectedMonth = current);
    }
    try {
      final MoneyDashboard dashboard =
          await ref.read(moneyRepositoryProvider).getDashboard(current);
      if (mounted) {
        await _recordTransaction(dashboard, MoneyTransactionKind.expense);
      }
    } on Object catch (error) {
      if (mounted) _showMessage(_friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(expenseCreateRequestProvider, (int? previous, int next) {
      if (previous != null && next > previous) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openQuickExpense();
        });
      }
    });
    final AsyncValue<MoneyDashboard> dashboard =
        ref.watch(moneyDashboardProvider(_selectedMonth));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const PageIntro(
                eyebrow: 'Money',
                title: 'Know where every RWF goes',
                subtitle:
                    'Accounts, spending, monthly budgets, and savings stay on this device.',
              ),
              const SizedBox(height: 18),
              dashboard.when(
                loading: () => const SurfaceCard(
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (Object error, StackTrace _) => SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Money data could not be loaded.',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(_friendlyError(error)),
                    ],
                  ),
                ),
                data: (MoneyDashboard data) => _buildDashboard(data),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard(MoneyDashboard dashboard) {
    final bool currentMonth = _sameMonth(
      dashboard.monthStartsOnLocal,
      startOfMoneyMonth(DateTime.now()),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _MoneyToolbar(
          hasAccounts: dashboard.activeAccounts.isNotEmpty,
          canTransfer: dashboard.activeAccounts.length >= 2,
          onAccount: _createAccount,
          onIncome: () =>
              _recordTransaction(dashboard, MoneyTransactionKind.income),
          onExpense: () =>
              _recordTransaction(dashboard, MoneyTransactionKind.expense),
          onTransfer: () =>
              _recordTransaction(dashboard, MoneyTransactionKind.transfer),
          onCategory: _createCategory,
          onGoal: _createSavingsGoal,
        ),
        const SizedBox(height: 22),
        _MonthNavigator(
          month: dashboard.monthStartsOnLocal,
          isCurrentMonth: currentMonth,
          onPrevious: () => _moveMonth(-1),
          onNext: currentMonth ? null : () => _moveMonth(1),
          onCurrent: currentMonth
              ? null
              : () => setState(
                    () => _selectedMonth = startOfMoneyMonth(DateTime.now()),
                  ),
        ),
        const SizedBox(height: 14),
        ResponsiveCardGrid(
          children: <Widget>[
            MetricCard(
              label: 'Spendable',
              value: _formatRwf(dashboard.totalSpendableRwf),
              caption:
                  '${dashboard.activeAccounts.length} active account${dashboard.activeAccounts.length == 1 ? '' : 's'}',
              icon: Icons.account_balance_wallet_outlined,
              color: AppColors.primary,
            ),
            MetricCard(
              label: 'Spent in ${_shortMonth(dashboard.monthStartsOnLocal)}',
              value: _formatRwf(dashboard.monthlySpentRwf),
              caption:
                  '${dashboard.transactions.where((MoneyTransaction item) => item.kind == MoneyTransactionKind.expense).length} expense entries',
              icon: Icons.south_east_rounded,
              color: AppColors.danger,
            ),
            MetricCard(
              label: 'Income in ${_shortMonth(dashboard.monthStartsOnLocal)}',
              value: _formatRwf(dashboard.monthlyIncomeRwf),
              caption:
                  '${dashboard.transactions.where((MoneyTransaction item) => item.kind == MoneyTransactionKind.income).length} income entries',
              icon: Icons.north_east_rounded,
              color: AppColors.secondary,
            ),
            MetricCard(
              label: 'Saved',
              value: _formatRwf(dashboard.totalSavedRwf),
              caption: 'Net worth ${_formatRwf(dashboard.netWorthRwf)}',
              icon: Icons.savings_outlined,
              color: AppColors.warning,
            ),
          ],
        ),
        const SizedBox(height: 28),
        SectionHeading(
          title: 'Accounts',
          actionLabel: 'Add account',
          onAction: _createAccount,
        ),
        const SizedBox(height: 10),
        _AccountsCard(
          accounts: dashboard.activeAccounts,
          onArchive: _archiveAccount,
          onCreate: _createAccount,
        ),
        const SizedBox(height: 28),
        SectionHeading(
          title: '${_monthTitle(dashboard.monthStartsOnLocal)} budgets',
          actionLabel: 'Set budget',
          onAction: () => _setBudget(dashboard),
        ),
        const SizedBox(height: 10),
        _BudgetsCard(
          budgets: dashboard.budgets,
          onCreate: () => _setBudget(dashboard),
          onEdit: (BudgetProgress item) =>
              _setBudget(dashboard, existing: item),
          onRemove: _removeBudget,
        ),
        const SizedBox(height: 28),
        SectionHeading(
          title: 'Savings goals',
          actionLabel: 'Add goal',
          onAction: _createSavingsGoal,
        ),
        const SizedBox(height: 10),
        _SavingsCard(
          goals: dashboard.activeSavingsGoals,
          onCreate: _createSavingsGoal,
          onDeposit: (SavingsGoalProgress goal) => _moveSavings(
            dashboard,
            goal,
            SavingsMovementKind.deposit,
          ),
          onWithdraw: (SavingsGoalProgress goal) => _moveSavings(
            dashboard,
            goal,
            SavingsMovementKind.withdrawal,
          ),
          onArchive: _archiveGoal,
        ),
        const SizedBox(height: 28),
        const SectionHeading(title: 'Transactions'),
        const SizedBox(height: 10),
        _TransactionsCard(
          month: dashboard.monthStartsOnLocal,
          transactions: dashboard.transactions,
          dashboard: dashboard,
          onVoid: _voidTransaction,
        ),
        const SizedBox(height: 28),
        SectionHeading(
          title: 'Categories',
          actionLabel: 'Add category',
          onAction: _createCategory,
        ),
        const SizedBox(height: 10),
        _CategoriesCard(
          categories: dashboard.categories
              .where((MoneyCategory item) => !item.isArchived)
              .toList(growable: false),
          onArchive: _archiveCategory,
        ),
      ],
    );
  }
}

class _MoneyToolbar extends StatelessWidget {
  const _MoneyToolbar({
    required this.hasAccounts,
    required this.canTransfer,
    required this.onAccount,
    required this.onIncome,
    required this.onExpense,
    required this.onTransfer,
    required this.onCategory,
    required this.onGoal,
  });

  final bool hasAccounts;
  final bool canTransfer;
  final VoidCallback onAccount;
  final VoidCallback onIncome;
  final VoidCallback onExpense;
  final VoidCallback onTransfer;
  final VoidCallback onCategory;
  final VoidCallback onGoal;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        FilledButton.icon(
          onPressed: onExpense,
          icon: const Icon(Icons.remove_rounded),
          label: const Text('Expense'),
        ),
        FilledButton.tonalIcon(
          onPressed: onIncome,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Income'),
        ),
        OutlinedButton.icon(
          onPressed: canTransfer ? onTransfer : null,
          icon: const Icon(Icons.swap_horiz_rounded),
          label: const Text('Transfer'),
        ),
        OutlinedButton.icon(
          onPressed: onAccount,
          icon: const Icon(Icons.account_balance_wallet_outlined),
          label: Text(hasAccounts ? 'Account' : 'First account'),
        ),
        PopupMenuButton<_MoneySetupAction>(
          tooltip: 'More money setup',
          onSelected: (_MoneySetupAction action) {
            switch (action) {
              case _MoneySetupAction.category:
                onCategory();
                break;
              case _MoneySetupAction.goal:
                onGoal();
                break;
            }
          },
          itemBuilder: (BuildContext context) =>
              const <PopupMenuEntry<_MoneySetupAction>>[
            PopupMenuItem<_MoneySetupAction>(
              value: _MoneySetupAction.category,
              child: Text('Add category'),
            ),
            PopupMenuItem<_MoneySetupAction>(
              value: _MoneySetupAction.goal,
              child: Text('Add savings goal'),
            ),
          ],
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.more_horiz_rounded),
                SizedBox(width: 8),
                Text('More'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _MoneySetupAction { category, goal }

class _MonthNavigator extends StatelessWidget {
  const _MonthNavigator({
    required this.month,
    required this.isCurrentMonth,
    required this.onPrevious,
    required this.onNext,
    required this.onCurrent,
  });

  final DateTime month;
  final bool isCurrentMonth;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onCurrent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        IconButton(
          tooltip: 'Previous month',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text(
          _monthTitle(month),
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        IconButton(
          tooltip: 'Next month',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        const Spacer(),
        if (!isCurrentMonth)
          TextButton(onPressed: onCurrent, child: const Text('This month')),
      ],
    );
  }
}

class _AccountsCard extends StatelessWidget {
  const _AccountsCard({
    required this.accounts,
    required this.onArchive,
    required this.onCreate,
  });

  final List<MoneyAccountSummary> accounts;
  final ValueChanged<MoneyAccountSummary> onArchive;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) {
      return SurfaceCard(
        child: _EmptyState(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Create your first money account',
          message:
              'Use the real balance currently in your cash, mobile money, or bank account as its opening balance.',
          actionLabel: 'Add account',
          onAction: onCreate,
        ),
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth >= 720
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: accounts
              .map(
                (MoneyAccountSummary item) => SizedBox(
                  width: width,
                  child: SurfaceCard(
                    child: Row(
                      children: <Widget>[
                        CircleAvatar(
                          backgroundColor: Color(item.account.colorValue)
                              .withValues(alpha: 0.14),
                          foregroundColor: Color(item.account.colorValue),
                          child: Icon(_accountTypeIcon(item.account.type)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                item.account.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _accountTypeLabel(item.account.type),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _formatRwf(item.balanceRwf),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Account actions',
                          onSelected: (_) => onArchive(item),
                          itemBuilder: (BuildContext context) =>
                              const <PopupMenuEntry<String>>[
                            PopupMenuItem<String>(
                              value: 'archive',
                              child: Text('Archive account'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _BudgetsCard extends StatelessWidget {
  const _BudgetsCard({
    required this.budgets,
    required this.onCreate,
    required this.onEdit,
    required this.onRemove,
  });

  final List<BudgetProgress> budgets;
  final VoidCallback onCreate;
  final ValueChanged<BudgetProgress> onEdit;
  final ValueChanged<BudgetProgress> onRemove;

  @override
  Widget build(BuildContext context) {
    if (budgets.isEmpty) {
      return SurfaceCard(
        child: _EmptyState(
          icon: Icons.pie_chart_outline_rounded,
          title: 'No limits set for this month',
          message:
              'Give an expense category a monthly RWF limit. Recorded expenses update it automatically.',
          actionLabel: 'Set budget',
          onAction: onCreate,
        ),
      );
    }
    final List<Widget> rows = <Widget>[];
    for (final BudgetProgress item in budgets) {
      if (rows.isNotEmpty) rows.add(const Divider(height: 26));
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: ProgressLine(
                label: item.category.name,
                valueLabel:
                    '${_formatRwf(item.spentRwf)} / ${_formatRwf(item.budget.limitRwf)}',
                progress: item.progress,
                color: item.isOverBudget
                    ? AppColors.danger
                    : Color(item.category.colorValue),
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: 'Budget actions',
              onSelected: (String value) {
                if (value == 'edit') {
                  onEdit(item);
                } else {
                  onRemove(item);
                }
              },
              itemBuilder: (BuildContext context) =>
                  const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(value: 'edit', child: Text('Edit limit')),
                PopupMenuItem<String>(
                  value: 'remove',
                  child: Text('Remove budget'),
                ),
              ],
            ),
          ],
        ),
      );
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Text(
            item.isOverBudget
                ? '${_formatRwf(-item.remainingRwf)} over budget'
                : '${_formatRwf(item.remainingRwf)} remaining',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: item.isOverBudget ? AppColors.danger : null,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      );
    }
    return SurfaceCard(child: Column(children: rows));
  }
}

class _SavingsCard extends StatelessWidget {
  const _SavingsCard({
    required this.goals,
    required this.onCreate,
    required this.onDeposit,
    required this.onWithdraw,
    required this.onArchive,
  });

  final List<SavingsGoalProgress> goals;
  final VoidCallback onCreate;
  final ValueChanged<SavingsGoalProgress> onDeposit;
  final ValueChanged<SavingsGoalProgress> onWithdraw;
  final ValueChanged<SavingsGoalProgress> onArchive;

  @override
  Widget build(BuildContext context) {
    if (goals.isEmpty) {
      return SurfaceCard(
        child: _EmptyState(
          icon: Icons.savings_outlined,
          title: 'Start a savings goal',
          message:
              'Deposits move RWF out of spendable accounts into a goal without changing your total net worth.',
          actionLabel: 'Add goal',
          onAction: onCreate,
        ),
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth >= 720
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: goals
              .map(
                (SavingsGoalProgress item) => SizedBox(
                  width: width,
                  child: SurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            CircleAvatar(
                              backgroundColor: Color(item.goal.colorValue)
                                  .withValues(alpha: 0.14),
                              foregroundColor: Color(item.goal.colorValue),
                              child: const Icon(Icons.savings_outlined),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    item.goal.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (item.goal.dueOnLocal != null)
                                    Text(
                                      'Target date ${_dayLabel(item.goal.dueOnLocal!)}',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: 'Savings goal actions',
                              onSelected: (_) => onArchive(item),
                              itemBuilder: (BuildContext context) =>
                                  const <PopupMenuEntry<String>>[
                                PopupMenuItem<String>(
                                  value: 'archive',
                                  child: Text('Archive goal'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ProgressLine(
                          label: item.isReached ? 'Goal reached' : 'Progress',
                          valueLabel:
                              '${_formatRwf(item.savedRwf)} / ${_formatRwf(item.goal.targetRwf)}',
                          progress: item.progress,
                          color: Color(item.goal.colorValue),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            FilledButton.tonalIcon(
                              onPressed: () => onDeposit(item),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Deposit'),
                            ),
                            TextButton.icon(
                              onPressed: item.savedRwf == 0
                                  ? null
                                  : () => onWithdraw(item),
                              icon: const Icon(Icons.undo_rounded),
                              label: const Text('Withdraw'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _TransactionsCard extends StatelessWidget {
  const _TransactionsCard({
    required this.month,
    required this.transactions,
    required this.dashboard,
    required this.onVoid,
  });

  final DateTime month;
  final List<MoneyTransaction> transactions;
  final MoneyDashboard dashboard;
  final ValueChanged<MoneyTransaction> onVoid;

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return SurfaceCard(
        child: Row(
          children: <Widget>[
            const Icon(Icons.receipt_long_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Text('No transactions recorded in ${_monthTitle(month)}.'),
            ),
          ],
        ),
      );
    }
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: transactions
            .map(
              (MoneyTransaction item) => _TransactionRow(
                transaction: item,
                dashboard: dashboard,
                onVoid: () => onVoid(item),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    required this.transaction,
    required this.dashboard,
    required this.onVoid,
  });

  final MoneyTransaction transaction;
  final MoneyDashboard dashboard;
  final VoidCallback onVoid;

  @override
  Widget build(BuildContext context) {
    final MoneyCategory? category =
        dashboard.categoryById(transaction.categoryId);
    final MoneyAccountSummary? account =
        dashboard.accountById(transaction.accountId);
    final MoneyAccountSummary? destination =
        transaction.destinationAccountId == null
            ? null
            : dashboard.accountById(transaction.destinationAccountId!);
    final Color color = switch (transaction.kind) {
      MoneyTransactionKind.income => AppColors.secondary,
      MoneyTransactionKind.expense => AppColors.danger,
      MoneyTransactionKind.transfer => AppColors.primary,
    };
    final String sign = switch (transaction.kind) {
      MoneyTransactionKind.income => '+',
      MoneyTransactionKind.expense => '−',
      MoneyTransactionKind.transfer => '',
    };
    final String source = account?.account.name ?? 'Archived account';
    final String detail = transaction.kind == MoneyTransactionKind.transfer
        ? '$source → ${destination?.account.name ?? 'Archived account'}'
        : '${category?.name ?? 'Archived category'} • $source';
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.14),
                foregroundColor: color,
                child: Icon(_transactionKindIcon(transaction.kind), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      transaction.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$detail • ${_dateTimeLabel(transaction.occurredAtUtc.toLocal())}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$sign${_formatRwf(transaction.amountRwf)}',
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
              PopupMenuButton<String>(
                tooltip: 'Transaction actions',
                onSelected: (_) => onVoid(),
                itemBuilder: (BuildContext context) =>
                    const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'void',
                    child: Text('Void transaction'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _CategoriesCard extends StatelessWidget {
  const _CategoriesCard({
    required this.categories,
    required this.onArchive,
  });

  final List<MoneyCategory> categories;
  final ValueChanged<MoneyCategory> onArchive;

  @override
  Widget build(BuildContext context) {
    final List<MoneyCategory> expenses = categories
        .where((MoneyCategory item) => item.kind == MoneyCategoryKind.expense)
        .toList(growable: false);
    final List<MoneyCategory> income = categories
        .where((MoneyCategory item) => item.kind == MoneyCategoryKind.income)
        .toList(growable: false);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('Expense', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          _CategoryWrap(categories: expenses, onArchive: onArchive),
          const SizedBox(height: 18),
          const Text('Income', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          _CategoryWrap(categories: income, onArchive: onArchive),
        ],
      ),
    );
  }
}

class _CategoryWrap extends StatelessWidget {
  const _CategoryWrap({required this.categories, required this.onArchive});

  final List<MoneyCategory> categories;
  final ValueChanged<MoneyCategory> onArchive;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: categories
          .map(
            (MoneyCategory item) => InputChip(
              avatar: CircleAvatar(backgroundColor: Color(item.colorValue)),
              label: Text(item.name),
              deleteIcon: item.isSystem
                  ? null
                  : const Icon(Icons.archive_outlined, size: 18),
              deleteButtonTooltipMessage: 'Archive custom category',
              onDeleted: item.isSystem ? null : () => onArchive(item),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Icon(icon, size: 38, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: onAction,
          icon: const Icon(Icons.add_rounded),
          label: Text(actionLabel),
        ),
      ],
    );
  }
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog();

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _opening = TextEditingController(text: '0');
  MoneyAccountType _type = MoneyAccountType.mobileMoney;
  int _color = _moneyColors.first;

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      MoneyAccountDraft(
        name: _name.text,
        type: _type,
        openingBalanceRwf: _parseRwf(_opening.text)!,
        colorValue: _color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add money account'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Account name',
                    hintText: 'MTN MoMo, cash, bank…',
                  ),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<MoneyAccountType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Account type'),
                  items: MoneyAccountType.values
                      .map(
                        (MoneyAccountType type) =>
                            DropdownMenuItem<MoneyAccountType>(
                          value: type,
                          child: Text(_accountTypeLabel(type)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (MoneyAccountType? value) {
                    if (value != null) setState(() => _type = value);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _opening,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Current opening balance (RWF)',
                    helperText:
                        'Enter what is in this account now. Future balances are calculated.',
                  ),
                  validator: (String? value) =>
                      _rwfValidator(value, allowZero: true),
                ),
                const SizedBox(height: 16),
                const Text('Color',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _ColorPicker(
                  selected: _color,
                  onSelected: (int value) => setState(() => _color = value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save account')),
      ],
    );
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog();

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  MoneyCategoryKind _kind = MoneyCategoryKind.expense;
  int _color = _moneyColors[1];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      MoneyCategoryDraft(
        name: _name.text,
        kind: _kind,
        colorValue: _color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add category'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Category name'),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              SegmentedButton<MoneyCategoryKind>(
                segments: const <ButtonSegment<MoneyCategoryKind>>[
                  ButtonSegment<MoneyCategoryKind>(
                    value: MoneyCategoryKind.expense,
                    label: Text('Expense'),
                    icon: Icon(Icons.south_east_rounded),
                  ),
                  ButtonSegment<MoneyCategoryKind>(
                    value: MoneyCategoryKind.income,
                    label: Text('Income'),
                    icon: Icon(Icons.north_east_rounded),
                  ),
                ],
                selected: <MoneyCategoryKind>{_kind},
                onSelectionChanged: (Set<MoneyCategoryKind> values) {
                  setState(() => _kind = values.single);
                },
              ),
              const SizedBox(height: 16),
              const Text('Color',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _ColorPicker(
                selected: _color,
                onSelected: (int value) => setState(() => _color = value),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save category')),
      ],
    );
  }
}

class _TransactionDialog extends StatefulWidget {
  const _TransactionDialog({required this.kind, required this.dashboard});

  final MoneyTransactionKind kind;
  final MoneyDashboard dashboard;

  @override
  State<_TransactionDialog> createState() => _TransactionDialogState();
}

class _TransactionDialogState extends State<_TransactionDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  late String _accountId;
  String? _destinationId;
  String? _categoryId;
  late DateTime _occurredLocal;

  List<MoneyCategory> get _categories {
    if (widget.kind == MoneyTransactionKind.transfer) {
      return const <MoneyCategory>[];
    }
    return widget.dashboard.categoriesFor(
      widget.kind == MoneyTransactionKind.expense
          ? MoneyCategoryKind.expense
          : MoneyCategoryKind.income,
    );
  }

  @override
  void initState() {
    super.initState();
    _accountId = widget.dashboard.activeAccounts.first.account.id;
    if (widget.kind == MoneyTransactionKind.transfer) {
      _destinationId = widget.dashboard.activeAccounts
          .firstWhere(
            (MoneyAccountSummary item) => item.account.id != _accountId,
          )
          .account
          .id;
    } else {
      _categoryId = _categories.first.id;
    }
    _occurredLocal = DateTime.now();
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: _occurredLocal,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _occurredLocal = DateTime(
        selected.year,
        selected.month,
        selected.day,
        _occurredLocal.hour,
        _occurredLocal.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final TimeOfDay? selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredLocal),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _occurredLocal = DateTime(
        _occurredLocal.year,
        _occurredLocal.month,
        _occurredLocal.day,
        selected.hour,
        selected.minute,
      );
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_occurredLocal.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A transaction cannot be in the future.')),
      );
      return;
    }
    Navigator.of(context).pop(
      MoneyTransactionDraft(
        kind: widget.kind,
        accountId: _accountId,
        destinationAccountId: _destinationId,
        categoryId: _categoryId,
        title: _title.text,
        amountRwf: _parseRwf(_amount.text)!,
        occurredAtUtc: _occurredLocal.toUtc(),
        notes: _notes.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<MoneyAccountSummary> accounts = widget.dashboard.activeAccounts;
    final List<MoneyAccountSummary> destinations = accounts
        .where((MoneyAccountSummary item) => item.account.id != _accountId)
        .toList(growable: false);
    if (widget.kind == MoneyTransactionKind.transfer &&
        !destinations.any(
          (MoneyAccountSummary item) => item.account.id == _destinationId,
        )) {
      _destinationId = destinations.first.account.id;
    }
    return AlertDialog(
      title: Text('Record ${_transactionKindLabel(widget.kind).toLowerCase()}'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                DropdownButtonFormField<String>(
                  initialValue: _accountId,
                  decoration: InputDecoration(
                    labelText: widget.kind == MoneyTransactionKind.transfer
                        ? 'From account'
                        : 'Account',
                  ),
                  items: accounts
                      .map(
                        (MoneyAccountSummary item) => DropdownMenuItem<String>(
                          value: item.account.id,
                          child: Text(
                            '${item.account.name} • ${_formatRwf(item.balanceRwf)}',
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (String? value) {
                    if (value != null) setState(() => _accountId = value);
                  },
                ),
                const SizedBox(height: 12),
                if (widget.kind == MoneyTransactionKind.transfer)
                  DropdownButtonFormField<String>(
                    key: ValueKey<String>(_accountId),
                    initialValue: _destinationId,
                    decoration: const InputDecoration(labelText: 'To account'),
                    items: destinations
                        .map(
                          (MoneyAccountSummary item) =>
                              DropdownMenuItem<String>(
                            value: item.account.id,
                            child: Text(item.account.name),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (String? value) {
                      if (value != null) {
                        setState(() => _destinationId = value);
                      }
                    },
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _categoryId,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: _categories
                        .map(
                          (MoneyCategory item) => DropdownMenuItem<String>(
                            value: item.id,
                            child: Text(item.name),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (String? value) {
                      if (value != null) setState(() => _categoryId = value);
                    },
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Title',
                    hintText: widget.kind == MoneyTransactionKind.transfer
                        ? 'Move to bank'
                        : widget.kind == MoneyTransactionKind.expense
                            ? 'Lunch'
                            : 'Allowance',
                  ),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amount,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount (RWF)'),
                  validator: _rwfValidator,
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.calendar_today_outlined),
                        title: const Text('Date'),
                        subtitle: Text(_dayLabel(_occurredLocal)),
                        onTap: _pickDate,
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.schedule_rounded),
                        title: const Text('Time'),
                        subtitle: Text(_clockLabel(_occurredLocal)),
                        onTap: _pickTime,
                      ),
                    ),
                  ],
                ),
                TextFormField(
                  controller: _notes,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                  decoration:
                      const InputDecoration(labelText: 'Note (optional)'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child:
              Text('Save ${_transactionKindLabel(widget.kind).toLowerCase()}'),
        ),
      ],
    );
  }
}

class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({
    required this.month,
    required this.categories,
    required this.existing,
  });

  final DateTime month;
  final List<MoneyCategory> categories;
  final BudgetProgress? existing;

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _limit;
  late String _categoryId;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.existing?.category.id ?? widget.categories.first.id;
    _limit = TextEditingController(
      text: widget.existing?.budget.limitRwf.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      MonthlyBudgetDraft(
        categoryId: _categoryId,
        monthStartsOnLocal: widget.month,
        limitRwf: _parseRwf(_limit.text)!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Budget for ${_monthTitle(widget.month)}'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DropdownButtonFormField<String>(
                initialValue: _categoryId,
                decoration:
                    const InputDecoration(labelText: 'Expense category'),
                items: widget.categories
                    .map(
                      (MoneyCategory item) => DropdownMenuItem<String>(
                        value: item.id,
                        child: Text(item.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: widget.existing == null
                    ? (String? value) {
                        if (value != null) setState(() => _categoryId = value);
                      }
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _limit,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Monthly limit (RWF)',
                ),
                validator: _rwfValidator,
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save budget')),
      ],
    );
  }
}

class _SavingsGoalDialog extends StatefulWidget {
  const _SavingsGoalDialog();

  @override
  State<_SavingsGoalDialog> createState() => _SavingsGoalDialogState();
}

class _SavingsGoalDialogState extends State<_SavingsGoalDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _target = TextEditingController();
  DateTime? _due;
  int _color = _moneyColors[2];

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final DateTime now = DateTime.now();
    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: _due ?? DateTime(now.year, now.month + 1, now.day),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 20),
    );
    if (selected != null && mounted) setState(() => _due = selected);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      SavingsGoalDraft(
        name: _name.text,
        targetRwf: _parseRwf(_target.text)!,
        dueOnLocal: _due,
        colorValue: _color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add savings goal'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Goal name',
                  hintText: 'Laptop, emergency fund…',
                ),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _target,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Target (RWF)'),
                validator: _rwfValidator,
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Target date (optional)'),
                subtitle:
                    Text(_due == null ? 'No target date' : _dayLabel(_due!)),
                trailing: _due == null
                    ? null
                    : IconButton(
                        tooltip: 'Clear target date',
                        onPressed: () => setState(() => _due = null),
                        icon: const Icon(Icons.close_rounded),
                      ),
                onTap: _pickDueDate,
              ),
              const SizedBox(height: 8),
              const Text('Color',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _ColorPicker(
                selected: _color,
                onSelected: (int value) => setState(() => _color = value),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save goal')),
      ],
    );
  }
}

class _SavingsMovementDialog extends StatefulWidget {
  const _SavingsMovementDialog({
    required this.goal,
    required this.accounts,
    required this.kind,
  });

  final SavingsGoalProgress goal;
  final List<MoneyAccountSummary> accounts;
  final SavingsMovementKind kind;

  @override
  State<_SavingsMovementDialog> createState() => _SavingsMovementDialogState();
}

class _SavingsMovementDialogState extends State<_SavingsMovementDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  late String _accountId;

  @override
  void initState() {
    super.initState();
    _accountId = widget.accounts.first.account.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      SavingsMovementDraft(
        goalId: widget.goal.goal.id,
        accountId: _accountId,
        kind: widget.kind,
        amountRwf: _parseRwf(_amount.text)!,
        occurredAtUtc: DateTime.now().toUtc(),
        notes: _notes.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool deposit = widget.kind == SavingsMovementKind.deposit;
    return AlertDialog(
      title: Text(
          '${deposit ? 'Deposit to' : 'Withdraw from'} ${widget.goal.goal.name}'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DropdownButtonFormField<String>(
                initialValue: _accountId,
                decoration: InputDecoration(
                  labelText: deposit ? 'From account' : 'Return to account',
                ),
                items: widget.accounts
                    .map(
                      (MoneyAccountSummary item) => DropdownMenuItem<String>(
                        value: item.account.id,
                        child: Text(
                          '${item.account.name} • ${_formatRwf(item.balanceRwf)}',
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (String? value) {
                  if (value != null) setState(() => _accountId = value);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Amount (RWF)',
                  helperText: deposit
                      ? 'This leaves the selected spendable account.'
                      : '${_formatRwf(widget.goal.savedRwf)} is currently saved.',
                ),
                validator: _rwfValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(deposit ? 'Save deposit' : 'Save withdrawal'),
        ),
      ],
    );
  }
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: _moneyColors
          .map(
            (int value) => InkWell(
              onTap: () => onSelected(value),
              borderRadius: BorderRadius.circular(99),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(value),
                  border: selected == value
                      ? Border.all(
                          color: Theme.of(context).colorScheme.onSurface,
                          width: 3,
                        )
                      : null,
                ),
                child: selected == value
                    ? const Icon(Icons.check_rounded,
                        size: 18, color: Colors.white)
                    : null,
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

const List<int> _moneyColors = <int>[
  0xFF4F46E5,
  0xFF0F9D8A,
  0xFFF59E0B,
  0xFFEF4444,
  0xFF8B5CF6,
  0xFF0284C7,
  0xFFDB2777,
  0xFF64748B,
];

String? _requiredValidator(String? value) {
  return value == null || value.trim().isEmpty
      ? 'This field is required.'
      : null;
}

String? _rwfValidator(String? value, {bool allowZero = false}) {
  final int? amount = _parseRwf(value ?? '');
  if (amount == null) return 'Enter a whole RWF amount.';
  if (allowZero ? amount < 0 : amount <= 0) {
    return allowZero
        ? 'Amount cannot be negative.'
        : 'Amount must be above zero.';
  }
  return null;
}

int? _parseRwf(String value) {
  final String normalized = value.replaceAll(RegExp(r'[\s,]'), '');
  return int.tryParse(normalized);
}

String _formatRwf(int value) {
  final bool negative = value < 0;
  final String digits = value.abs().toString();
  final StringBuffer grouped = StringBuffer();
  for (int index = 0; index < digits.length; index += 1) {
    if (index > 0 && (digits.length - index) % 3 == 0) grouped.write(',');
    grouped.write(digits[index]);
  }
  return '${negative ? '−' : ''}RWF $grouped';
}

String _friendlyError(Object error) {
  final String message = error.toString();
  return message
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Invalid argument(s): ', '')
      .replaceFirst(RegExp(r'^Invalid argument \([^)]*\): '), '');
}

String _transactionKindLabel(MoneyTransactionKind kind) {
  return switch (kind) {
    MoneyTransactionKind.income => 'Income',
    MoneyTransactionKind.expense => 'Expense',
    MoneyTransactionKind.transfer => 'Transfer',
  };
}

IconData _transactionKindIcon(MoneyTransactionKind kind) {
  return switch (kind) {
    MoneyTransactionKind.income => Icons.north_east_rounded,
    MoneyTransactionKind.expense => Icons.south_east_rounded,
    MoneyTransactionKind.transfer => Icons.swap_horiz_rounded,
  };
}

String _accountTypeLabel(MoneyAccountType type) {
  return switch (type) {
    MoneyAccountType.cash => 'Cash',
    MoneyAccountType.mobileMoney => 'Mobile money',
    MoneyAccountType.bank => 'Bank',
    MoneyAccountType.savings => 'Savings account',
  };
}

IconData _accountTypeIcon(MoneyAccountType type) {
  return switch (type) {
    MoneyAccountType.cash => Icons.payments_outlined,
    MoneyAccountType.mobileMoney => Icons.phone_android_rounded,
    MoneyAccountType.bank => Icons.account_balance_outlined,
    MoneyAccountType.savings => Icons.savings_outlined,
  };
}

const List<String> _months = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _monthTitle(DateTime month) =>
    '${_months[month.month - 1]} ${month.year}';

String _shortMonth(DateTime month) => _months[month.month - 1].substring(0, 3);

String _dayLabel(DateTime day) {
  final String month = day.month.toString().padLeft(2, '0');
  final String date = day.day.toString().padLeft(2, '0');
  return '${day.year}-$month-$date';
}

String _clockLabel(DateTime value) {
  final int hour =
      value.hour == 0 ? 12 : (value.hour > 12 ? value.hour - 12 : value.hour);
  final String minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
}

String _dateTimeLabel(DateTime value) =>
    '${_dayLabel(value)} • ${_clockLabel(value)}';

bool _sameMonth(DateTime first, DateTime second) {
  return first.year == second.year && first.month == second.month;
}
