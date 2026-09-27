import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/account/presentation/account_access.dart';
import 'features/shell/presentation/app_shell.dart';

class GahundaApp extends StatelessWidget {
  const GahundaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gahunda',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const AccountGate(child: AppShell()),
    );
  }
}
