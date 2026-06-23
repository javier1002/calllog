import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'presentation/main_shell.dart';

class RegistroLlamadasApp extends StatelessWidget {
  const RegistroLlamadasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Registro de llamadas salientes',
      theme: AppTheme.darkTheme,
      home: const MainShell(),
    );
  }
}
