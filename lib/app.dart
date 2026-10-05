import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

class RecapApp extends StatelessWidget {
  const RecapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Recap Maker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Padauk',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6A1B9A)),
      ),
      home: const HomeScreen(),
    );
  }
}
