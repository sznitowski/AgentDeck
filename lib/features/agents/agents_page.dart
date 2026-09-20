import 'package:flutter/material.dart';

import '../../shared/page_frame.dart';

class AgentsPage extends StatelessWidget {
  const AgentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageFrame(
      title: 'Agents',
      subtitle: 'Coding agents run on your Linux servers',
      child: SummaryCard(
          title: 'Executions',
          value: 'No agents connected',
          icon: Icons.smart_toy_outlined),
    );
  }
}
