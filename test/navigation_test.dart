import 'package:agentdeck/app/agentdeck_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('all five destinations navigate to their pages', (tester) async {
    await tester.pumpWidget(const AgentDeckApp());
    expect(find.text('No servers yet'), findsOneWidget);

    for (final label in ['Servers', 'Projects', 'Agents', 'Settings']) {
      await tester.tap(find.widgetWithText(NavigationDestination, label));
      await tester.pumpAndSettle();
      expect(find.text(label, skipOffstage: false), findsWidgets);
    }
    expect(find.text('M0 Bootstrap'), findsOneWidget);
  });
}
