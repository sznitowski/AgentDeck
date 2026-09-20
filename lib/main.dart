import 'package:flutter/material.dart';

import 'app/agentdeck_app.dart';
import 'app/app_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final services = await AgentDeckServices.bootstrap();
    runApp(AgentDeckApp(services: services));
  } catch (_) {
    runApp(const MaterialApp(
      home: Scaffold(
        body: Center(
            child: Text(
                'AgentDeck storage could not be opened. No SSH connection was started.')),
      ),
    ));
  }
}
