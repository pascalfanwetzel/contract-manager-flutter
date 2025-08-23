import 'package:flutter/material.dart';
import '../features/contracts/data/app_state.dart';
import 'shell.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppState(); // single source of truth (in-memory for now)

    return MaterialApp(
      title: 'Contract Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color.fromARGB(255, 255, 255, 255).fromARGB(255, 213, 222, 221),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      home: HomeShell(state: state),
    );
  }
}
