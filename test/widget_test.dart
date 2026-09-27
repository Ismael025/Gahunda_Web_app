import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gahunda/app.dart';
import 'package:gahunda/features/planner/application/planning_providers.dart';
import 'package:gahunda/features/planner/data/planning_database.dart';

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int attempts = 40,
}) async {
  for (int attempt = 0; attempt < attempts; attempt += 1) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 25));
  }
}

void main() {
  testWidgets('opens Today and navigates to Plan and School',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await database.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          planningDatabaseProvider.overrideWithValue(database),
        ],
        child: const GahundaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gahunda'), findsOneWidget);
    expect(find.text('Good morning, Ismael'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Turn direction into action'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.school_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Own your school week'), findsOneWidget);
  });

  testWidgets('account panel explains local-only mode when cloud is not set',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await database.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          planningDatabaseProvider.overrideWithValue(database),
        ],
        child: const GahundaApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Account and sync'));
    await tester.pumpAndSettle();

    expect(find.text('Account and sync'), findsOneWidget);
    expect(find.text('Local-only mode'), findsOneWidget);
    expect(
      find.textContaining('Everything continues to save on this device'),
      findsOneWidget,
    );
  });

  testWidgets('notification bell explains the fixed task reminder',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await database.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          planningDatabaseProvider.overrideWithValue(database),
        ],
        child: const GahundaApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Reminders and notifications'));
    await tester.pumpAndSettle();

    expect(find.text('Reminders and notifications'), findsOneWidget);
    expect(find.text('Enable reminders'), findsOneWidget);
    expect(
      find.textContaining('continue to work without an internet connection'),
      findsOneWidget,
    );
  });

  testWidgets('Quick add creates a habit and opens Track',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await database.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          planningDatabaseProvider.overrideWithValue(database),
        ],
        child: const GahundaApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quick add'));
    await tester.pumpAndSettle();

    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('Reflection'), findsOneWidget);
    await tester.tap(find.text('Habit'));
    await tester.pumpAndSettle();

    expect(find.text('Create habit'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Habit name'),
      'Morning stretch',
    );
    await tester.tap(find.text('Save locally'));
    await tester.pumpAndSettle();

    expect(find.text('Build a rhythm that works'), findsOneWidget);
    expect(find.text('Morning stretch'), findsOneWidget);
    await tester.tap(find.byTooltip('Mark complete'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 1'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pumpAndSettle();
    expect(find.text("Today's habits"), findsOneWidget);
    expect(find.text('Morning stretch'), findsOneWidget);
  });

  testWidgets('scheduled Quick Add appears on Today without restarting',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await database.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          planningDatabaseProvider.overrideWithValue(database),
        ],
        child: const GahundaApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Quick add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Task title'),
      'Task added immediately',
    );
    await tester.tap(find.text('Save locally'));
    await tester.pumpAndSettle();

    expect(find.text('Task added immediately'), findsOneWidget);
    expect(find.text('0 of 1'), findsOneWidget);
  });

  testWidgets('Quick add records an expense and refreshes Today',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await database.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          planningDatabaseProvider.overrideWithValue(database),
        ],
        child: const GahundaApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.account_balance_wallet_outlined),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Know where every RWF goes'), findsOneWidget);

    await tester.tap(find.text('First account'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Account name'),
      'MTN MoMo',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Current opening balance (RWF)'),
      '10000',
    );
    await tester.tap(find.text('Save account'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.home_outlined),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quick add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Bus fare',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount (RWF)'),
      '2000',
    );
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();

    expect(find.text('Bus fare'), findsOneWidget);
    expect(find.text('RWF 8,000'), findsWidgets);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.home_outlined),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Today's money"), findsOneWidget);
    expect(find.text('RWF 2,000'), findsWidgets);
  });

  testWidgets('Insights switches cadence and saves a weekly review',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await database.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          planningDatabaseProvider.overrideWithValue(database),
        ],
        child: const GahundaApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.insights_outlined),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Learn from what actually happened'), findsOneWidget);
    expect(find.text('Weekly'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('Annual'), findsOneWidget);
    expect(find.text('Plan completion'), findsOneWidget);

    final Finder startReview = find.text('Start weekly review');
    await tester.ensureVisible(startReview);
    await tester.pumpAndSettle();
    await tester.tap(startReview);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Wins'),
      'Kept the week focused',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Next week focus'),
      'Prepare the next priority',
    );
    await tester.tap(find.text('Save review'));
    await tester.pumpAndSettle();

    expect(find.text('Review saved • 3/5'), findsOneWidget);
    expect(find.text('Kept the week focused'), findsOneWidget);
  });

  testWidgets('Quick add reflection is included in Insights',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final PlanningDatabase database = PlanningDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await database.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          planningDatabaseProvider.overrideWithValue(database),
        ],
        child: const GahundaApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quick add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reflection'));
    await _pumpUntilFound(tester, find.text('Close today'));

    expect(find.text('Close today'), findsOneWidget);
    await _pumpUntilFound(
      tester,
      find.widgetWithText(TextField, 'Today’s win'),
    );
    expect(
      find.widgetWithText(TextField, 'Today’s win'),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Today’s win'),
      'Closed the day from Quick add',
    );
    await tester.tap(find.text('Save closure'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.insights_outlined),
      ),
    );
    await tester.pumpAndSettle();
    await _pumpUntilFound(
      tester,
      find.text('Win: Closed the day from Quick add'),
    );
    expect(find.text('Win: Closed the day from Quick add'), findsOneWidget);
  });
}
