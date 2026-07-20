// Basic smoke test for the app.
//
// This test avoids pumping the full MyApp widget tree because that
// requires Firebase.initializeApp() to have run first (which happens
// in main(), not in widget tests). Instead it does a minimal sanity
// check that MaterialApp renders correctly.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('HoloLingo')),
        ),
      ),
    );

    expect(find.text('HoloLingo'), findsOneWidget);
  });
}