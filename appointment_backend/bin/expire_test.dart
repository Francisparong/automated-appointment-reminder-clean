
import 'package:sqlite3/sqlite3.dart';

void main() {
  final db = sqlite3.open('appointments.db');

  try {
    // Hanapin ang test appointment.
    final rows = db.select(
      '''
      SELECT id, status, scheduled_at
      FROM appointments
      WHERE purpose = ?
      ''',
      ['TEST_EXPIRATION'],
    );

    if (rows.length != 1) {
      print(
        'Expected exactly one TEST_EXPIRATION appointment, '
        'but found ${rows.length}. No changes made.',
      );
      return;
    }

    final appointment = rows.first;
    final id = appointment['id'] as int;
    final status = appointment['status'] as String;

    if (status != 'pending') {
      print(
        'Appointment $id is not pending. '
        'No changes made.',
      );
      return;
    }

    // I-set ang schedule sa dalawang oras na nakalipas.
    final pastTime = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 2))
        .toIso8601String();

    db.execute(
      '''
      UPDATE appointments
      SET scheduled_at = ?
      WHERE id = ? AND status = 'pending'
      ''',
      [pastTime, id],
    );

    print('Expiration test prepared successfully.');
    print('Appointment ID: $id');
    print('Simulated past schedule: $pastTime');
    print('Status remains pending until automation runs.');
  } finally {
  db.close();
}
}
