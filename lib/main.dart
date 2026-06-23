import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HappyBusApp());
}

class HappyBusApp extends StatelessWidget {
  const HappyBusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Happy Bus — Laporan Crew',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1E88E5),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          foregroundColor: Colors.white,
          backgroundColor: Color(0xFF1E88E5),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
