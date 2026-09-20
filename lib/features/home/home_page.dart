import 'package:flutter/material.dart';

import '../../shared/page_frame.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageFrame(
      title: 'AgentDeck',
      subtitle: 'Your remote workspace, one project at a time',
      child: Column(children: [
        SummaryCard(
            title: 'Servers',
            value: 'No servers yet',
            icon: Icons.dns_outlined),
        SummaryCard(
            title: 'Projects',
            value: 'No projects yet',
            icon: Icons.folder_outlined),
        SummaryCard(
            title: 'Agents',
            value: 'No active agents',
            icon: Icons.smart_toy_outlined),
        SummaryCard(
            title: 'Recent activity',
            value: 'Nothing to show',
            icon: Icons.history),
      ]),
    );
  }
}
