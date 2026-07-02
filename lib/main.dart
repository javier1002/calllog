import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/history_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await _saveApiKeyForWorker();
  runApp(const RegistroLlamadasApp());
}

Future<void> _saveApiKeyForWorker() async {
  const channel = MethodChannel('registro_llamadas/call_log');
  try {
    await channel.invokeMethod('saveApiKey', {
      'key': 'ujfj8+XVhZZHA7FHlFqK+Mplc0HO8mEbXHYp59C177FbXS9fIt70x40jYoLu/4Y+',
    });
  } catch (_) {}
}

class RegistroLlamadasApp extends StatelessWidget {
  const RegistroLlamadasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Registro de Llamadas Salientes',
      theme: AppTheme.darkTheme,
      home: const Scaffold(
        body: SafeArea(
          child: HistoryScreen(),
        ),
      ),
    );
  }
}