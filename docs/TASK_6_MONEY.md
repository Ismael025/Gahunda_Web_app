# Task 6: Money

## Outcome

Money is no longer a mock screen. Gahunda stores accounts, a manual ledger,
monthly budgets, and savings goals in the same local SQLite database as the
rest of the app. Money and Today refresh reactively after a saved entry.

All values are whole Rwandan francs. No financial amount uses a floating-point
number.

## Reconciliation rules

- An account begins with the real balance entered when it is created.
- Income adds RWF to one account.
- An expense subtracts RWF from one account.
- A transfer subtracts and adds the same RWF amount between two different
  accounts, so total spendable money does not change.
- A savings deposit moves RWF from a spendable account to a goal. A withdrawal
  returns it. These movements change where the money sits but not net worth.
- Current balances are always calculated from the opening balance and saved
  ledger history; users do not overwrite a balance manually.
- Expenses and transfers cannot make an account negative.
- Voiding an entry reverses its calculated effect and keeps a soft-deleted
  history record.

## Monthly budgets

Each expense category can have one limit per calendar month. Only non-voided
expenses in that category and month count against the limit. Income, transfers,
savings movements, and expenses from other months do not consume it.

The Money screen can move backward through months. Account and savings balances
still reflect the complete ledger, while transaction and budget totals reflect
the selected month.

## Product workflow

1. Open **Money → First account** and enter an account name, type, current
   opening balance, and color.
2. Record income or expenses against one of the seeded categories.
3. Add a second account to transfer money without creating artificial income
   or spending.
4. Set a monthly limit for any active expense category.
5. Create a savings goal, then deposit from or withdraw to an active account.
6. Use **Quick add → Expense** from anywhere; Gahunda opens Money and saves the
   entry into the same ledger.
7. Review today’s spending and current spendable total on **Today**.

Custom categories may be archived. An account can be archived only at a zero
balance, and a savings goal only after all saved RWF is withdrawn. Existing
history remains readable through its related records.

## Local schema and migration

Database schema version 5 adds:

| Table | Purpose |
| --- | --- |
| `money_accounts` | Account definition and opening RWF balance |
| `money_categories` | Seeded and custom expense/income categories |
| `money_transactions` | Income, expense, and transfer ledger |
| `money_budgets` | One category limit per local calendar month |
| `savings_goals` | Target amount, optional target date, and archive state |
| `savings_movements` | Deposits to and withdrawals from goals |

The migration adds these tables and indexes without recreating earlier tables.
Existing planning, day-closure, school, and behavior records remain intact.

## Acceptance path

1. Create an account with RWF 100,000.
2. Record RWF 50,000 income and RWF 20,000 expense; confirm RWF 130,000 is
   spendable and the monthly cards show the two exact totals.
3. Create a second account, transfer RWF 30,000, and confirm total spendable
   money does not change.
4. Set a Food budget, record Food expenses, and confirm its used/remaining
   values update immediately and indicate overspending past the limit.
5. Create a goal and deposit RWF 40,000; confirm spendable decreases, saved
   increases, and net worth does not change. Withdraw part of it and recheck.
6. Use Quick add for another expense and confirm it appears on Today without a
   restart.
7. Void a safe transaction and confirm its balance effect is reversed.
8. Quit and reopen the app; all active records and reconciled totals remain.

## Verification

Run from the project root:

```bash
flutter create --platforms=android,windows .
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter run -d windows
```

The automated suite contains 43 tests after Task 6. Money repository tests
cover integer reconciliation, category rules, insufficient funds, transfers,
budgets, savings, archival, voiding, month/day boundaries, reactive updates,
file-backed persistence, and the schema 4-to-5 migration. A widget test covers
Quick add expense and the Today refresh.
