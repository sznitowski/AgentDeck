import 'package:flutter/material.dart';

import 'app_services.dart';
import 'navigation_shell.dart';

class AgentDeckApp extends StatefulWidget {
  const AgentDeckApp({super.key, this.services});
  final AgentDeckServices? services;

  @override
  State<AgentDeckApp> createState() => _AgentDeckAppState();
}

class _AgentDeckAppState extends State<AgentDeckApp> {
  @override
  void dispose() {
    widget.services?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgentDeck',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF536CFF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B1020),
      ),
      home: NavigationShell(services: widget.services),
    );
  }
}
