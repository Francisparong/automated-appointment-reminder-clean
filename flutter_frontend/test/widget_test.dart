
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:automated_appointment_reminder/main.dart';

void main() {
  testWidgets(
    'New Appointment form opens successfully',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog<AppointmentData>(
                      context: context,
                      builder: (_) => const AppointmentForm(),
                    );
                  },
                  child: const Text('Open Form'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Form'));
      await tester.pumpAndSettle();

      expect(
        find.text('New Appointment'),
        findsOneWidget,
      );

      expect(
        find.text('Full Name'),
        findsOneWidget,
      );

      expect(
        find.text('Email Address'),
        findsOneWidget,
      );

      expect(
        find.text('Appointment Purpose'),
        findsOneWidget,
      );

      expect(
        find.text('Create Appointment'),
        findsOneWidget,
      );
    },
  );
}
