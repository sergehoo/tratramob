// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/core/theme.dart';

void main() {
  testWidgets('renders the Tratra branded application shell',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: Center(child: Text(AppConstants.appName)),
        ),
      ),
    );

    expect(find.text('Tratra'), findsOneWidget);
  });
}
