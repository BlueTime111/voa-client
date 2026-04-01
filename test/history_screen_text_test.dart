import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:nova_voice_assistant/providers/app_provider.dart';
import 'package:nova_voice_assistant/screens/history_screen.dart';

void main() {
  testWidgets('history screen copy uses natural Chinese strings',
      (tester) async {
    final appProvider = AppProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: appProvider,
        child: const MaterialApp(home: HistoryScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('历史记录'), findsOneWidget);
    expect(find.text('还没有历史记录'), findsOneWidget);
    expect(find.text('先去首页发一条任务试试吧。'), findsOneWidget);
  });
}
