import 'package:flutter/material.dart';

import '../../shared/page_frame.dart';

class ProjectsPage extends StatelessWidget {
  const ProjectsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageFrame(
      title: 'Projects',
      subtitle: 'A project joins a server, workspace, agent, and policy',
      child: SummaryCard(
          title: 'Project profiles',
          value: 'No projects configured',
          icon: Icons.folder_open),
    );
  }
}
