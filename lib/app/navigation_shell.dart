import 'package:flutter/material.dart';

import '../features/agents/agents_page.dart';
import '../features/home/home_page.dart';
import '../features/projects/projects_page.dart';
import '../features/servers/servers_page.dart';
import '../features/settings/settings_page.dart';
import 'app_services.dart';

class NavigationShell extends StatefulWidget {
  const NavigationShell({super.key, this.services});
  final AgentDeckServices? services;

  @override
  State<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends State<NavigationShell> {
  int selectedIndex = 0;

  List<Widget> get pages => [
        const HomePage(),
        ServersPage(
          profiles: widget.services?.profiles,
          credentials: widget.services?.credentials,
          knownHosts: widget.services?.knownHosts,
          connection: widget.services?.connection,
          tmuxReferences: widget.services?.tmuxReferences,
        ),
        const ProjectsPage(),
        const AgentsPage(),
        const SettingsPage(),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body:
          SafeArea(child: IndexedStack(index: selectedIndex, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => setState(() => selectedIndex = index),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.space_dashboard_outlined),
              selectedIcon: Icon(Icons.space_dashboard),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.dns_outlined),
              selectedIcon: Icon(Icons.dns),
              label: 'Servers'),
          NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder),
              label: 'Projects'),
          NavigationDestination(
              icon: Icon(Icons.smart_toy_outlined),
              selectedIcon: Icon(Icons.smart_toy),
              label: 'Agents'),
          NavigationDestination(
              icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune),
              label: 'Settings'),
        ],
      ),
    );
  }
}
