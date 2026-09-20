import 'package:flutter/material.dart';

import '../../shared/page_frame.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageFrame(
      title: 'Settings',
      subtitle: 'Security and connection preferences',
      child: SummaryCard(
          title: 'Build stage',
          value: 'M0 Bootstrap',
          icon: Icons.construction_outlined),
    );
  }
}
