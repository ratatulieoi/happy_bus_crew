import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/home_screen.dart';
import 'services/platform_setup.dart';
import 'ui/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupDesktopPlatform();
  await initializeDateFormatting('id_ID', null);
  runApp(const HappyBusApp());
}

class HappyBusApp extends StatelessWidget {
  const HappyBusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Happy Group — Laporan Crew',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('id', 'ID'),
        Locale('en', 'US'),
      ],
      locale: const Locale('id', 'ID'),
      theme: buildAppTheme(),
      home: const HomeScreen(),
    );
  }
}
