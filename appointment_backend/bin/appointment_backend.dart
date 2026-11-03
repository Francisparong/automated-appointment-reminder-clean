import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:sqlite3/sqlite3.dart';

void main() async {
  // =====================================================
  // DATABASE CONNECTION
  // =====================================================

  final db = sqlite3.open('appointments.db');

  // Create tables without deleting existing records.
  db.execute('''
    CREATE TABLE IF NOT EXISTS appointments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      email TEXT NOT NULL,
      purpose TEXT NOT NULL,
      scheduled_at TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      created_at TEXT NOT NULL
    )
  ''');

  db.execute('''
    CREATE TABLE IF NOT EXISTS reminders (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      appointment_id INTEGER NOT NULL,
      scheduled_at TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      attempt_count INTEGER NOT NULL DEFAULT 0,
      max_attempts INTEGER NOT NULL DEFAULT 3,
      next_attempt_at TEXT,
      last_error TEXT,
      delivered_at TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY (appointment_id)
        REFERENCES appointments(id)
    )
  ''');

  db.execute('''
    CREATE TABLE IF NOT EXISTS automation_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      reminder_id INTEGER,
      event TEXT NOT NULL,
      details TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');

  // =====================================================
  // HELPER FUNCTIONS
  // =====================================================

  String nowUtc() {
    return DateTime.now().toUtc().toIso8601String();
  }

  Response jsonResponse(int status, Object data) {
    return Response(
      status,
      body: jsonEncode(data),
      headers: {'content-type': 'application/json'},
    );
  }

  void logEvent(int? reminderId, String event, String details) {
    final timestamp = nowUtc();

    db.execute(
      '''
      INSERT INTO automation_logs
      (reminder_id, event, details, created_at)
      VALUES (?, ?, ?, ?)
    ''',
      [reminderId, event, details, timestamp],
    );

    print(
      jsonEncode({
        'timestamp': timestamp,
        'reminder_id': reminderId,
        'event': event,
        'details': details,
      }),
    );
  }

  List<Map<String, dynamic>> convertRows(ResultSet rows) {
    return rows.map((row) {
      return Map<String, dynamic>.from(row);
    }).toList();
  }

  // =====================================================
  // REMINDER SCHEDULING
  // =====================================================

  void scheduleReminder(int appointmentId, DateTime appointmentTime) {
    final now = DateTime.now().toUtc();

    var reminderTime = appointmentTime.toUtc().subtract(
      const Duration(hours: 24),
    );

    // If the appointment is less than 24 hours away,
    // schedule the reminder immediately.
    if (reminderTime.isBefore(now)) {
      reminderTime = now;
    }

    db.execute(
      '''
      INSERT INTO reminders (
        appointment_id,
        scheduled_at,
        status,
        attempt_count,
        max_attempts,
        created_at
      )
      VALUES (?, ?, 'pending', 0, 3, ?)
    ''',
      [appointmentId, reminderTime.toIso8601String(), now.toIso8601String()],
    );

    final reminderId = db.lastInsertRowId;

    logEvent(
      reminderId,
      'reminder_scheduled',
      'Scheduled for ${reminderTime.toIso8601String()}',
    );
  }

  // =====================================================
  // SIMULATED DELIVERY AND RETRY SYSTEM
  // =====================================================

  void processReminder(Row row) {
    final reminderId = row['id'] as int;
    final attempts = (row['attempt_count'] as int) + 1;
    final maximum = row['max_attempts'] as int;

    final purpose = (row['purpose'] as String).toUpperCase();

    String outcome = 'success';

    // Controlled failure scenarios for Week 13.
    if (purpose.contains('TEST_PERMANENT')) {
      outcome = 'permanent';
    } else if (purpose.contains('TEST_ALWAYS_FAIL')) {
      outcome = 'temporary';
    } else if (purpose.contains('TEST_TRANSIENT') && attempts == 1) {
      outcome = 'temporary';
    }

    logEvent(
      reminderId,
      'delivery_attempt',
      'Attempt $attempts of $maximum; '
          'mode=$outcome; simulated',
    );

    // Successful simulated delivery.
    if (outcome == 'success') {
      db.execute(
        '''
        UPDATE reminders
        SET status = 'delivered',
            attempt_count = ?,
            next_attempt_at = NULL,
            last_error = NULL,
            delivered_at = ?
        WHERE id = ?
      ''',
        [attempts, nowUtc(), reminderId],
      );

      logEvent(reminderId, 'delivered', 'Simulated delivery succeeded');

      return;
    }

    // Permanent failure or retry limit reached.
    if (outcome == 'permanent' || attempts >= maximum) {
      final reason = outcome == 'permanent'
          ? 'Simulated permanent delivery failure'
          : 'Maximum retry attempts exhausted';

      db.execute(
        '''
        UPDATE reminders
        SET status = 'manual_review',
            attempt_count = ?,
            next_attempt_at = NULL,
            last_error = ?
        WHERE id = ?
      ''',
        [attempts, reason, reminderId],
      );

      logEvent(reminderId, 'manual_review', reason);

      return;
    }

    // Temporary failure: retry after 15 seconds.
    final nextAttempt = DateTime.now()
        .toUtc()
        .add(const Duration(seconds: 15))
        .toIso8601String();

    db.execute(
      '''
      UPDATE reminders
      SET status = 'retry',
          attempt_count = ?,
          next_attempt_at = ?,
          last_error = ?
      WHERE id = ?
    ''',
      [
        attempts,
        nextAttempt,
        'Simulated temporary delivery failure',
        reminderId,
      ],
    );

    logEvent(
      reminderId,
      'retry_scheduled',
      'Attempt $attempts failed; retry at $nextAttempt',
    );
  }

  // =====================================================
  // AUTOMATIC APPOINTMENT EXPIRATION
  // =====================================================

  void runAutomation() {
    final now = nowUtc();

    // Pending appointments expire one hour after
    // the scheduled appointment time.
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 1))
        .toIso8601String();

    final expired = db.select(
      '''
      SELECT id
      FROM appointments
      WHERE status = 'pending'
        AND scheduled_at <= ?
    ''',
      [cutoff],
    );

    for (final row in expired) {
      final appointmentId = row['id'] as int;

      db.execute('BEGIN IMMEDIATE TRANSACTION');

      try {
        db.execute(
          '''
          UPDATE appointments
          SET status = 'expired'
          WHERE id = ? AND status = 'pending'
        ''',
          [appointmentId],
        );

        db.execute(
          '''
          UPDATE reminders
          SET status = 'cancelled',
              next_attempt_at = NULL
          WHERE appointment_id = ?
            AND status IN ('pending', 'retry')
        ''',
          [appointmentId],
        );

        logEvent(
          null,
          'appointment_expired',
          'Appointment $appointmentId automatically closed',
        );

        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
    }

    // Find due reminders.
    final due = db.select(
      '''
      SELECT r.*, a.purpose
      FROM reminders r
      JOIN appointments a
        ON a.id = r.appointment_id
      WHERE a.status = 'pending'
        AND r.status IN ('pending', 'retry')
        AND r.scheduled_at <= ?
        AND (
          r.next_attempt_at IS NULL
          OR r.next_attempt_at <= ?
        )
      ORDER BY r.id
    ''',
      [now, now],
    );

    for (final row in due) {
      processReminder(row);
    }
  }

  // =====================================================
  // HTTP API ROUTES
  // =====================================================

  Future<Response> handleRequest(Request request) async {
    final path = request.url.path;
    final method = request.method;

    // -----------------------------
    // HEALTH CHECK
    // -----------------------------

    if (method == 'GET' && path == 'health') {
      return jsonResponse(200, {
        'status': 'ok',
        'message': 'Appointment backend is running',
      });
    }

    // -----------------------------
    // GET ALL APPOINTMENTS
    // -----------------------------

    if (method == 'GET' && path == 'appointments') {
      final rows = db.select('''
        SELECT *
        FROM appointments
        ORDER BY id DESC
      ''');

      return jsonResponse(200, convertRows(rows));
    }

    // -----------------------------
    // GET ALL REMINDERS
    // -----------------------------

    if (method == 'GET' && path == 'reminders') {
      final rows = db.select('''
        SELECT r.*, a.name, a.purpose
        FROM reminders r
        JOIN appointments a
          ON a.id = r.appointment_id
        ORDER BY r.id DESC
      ''');

      return jsonResponse(200, convertRows(rows));
    }

    // -----------------------------
    // GET MANUAL REVIEW RECORDS
    // -----------------------------

    if (method == 'GET' && path == 'manual-review') {
      final rows = db.select('''
        SELECT r.*, a.name, a.purpose
        FROM reminders r
        JOIN appointments a
          ON a.id = r.appointment_id
        WHERE r.status = 'manual_review'
        ORDER BY r.id DESC
      ''');

      return jsonResponse(200, convertRows(rows));
    }

    // -----------------------------
    // GET AUTOMATION LOGS
    // -----------------------------

    if (method == 'GET' && path == 'logs') {
      final rows = db.select('''
        SELECT *
        FROM automation_logs
        ORDER BY id DESC
        LIMIT 100
      ''');

      return jsonResponse(200, convertRows(rows));
    }

    // =====================================================
    // CANCEL AND RESCHEDULE ROUTES
    // =====================================================

    final segments = request.url.pathSegments;

    if (method == 'PATCH' &&
        segments.length == 3 &&
        segments[0] == 'appointments' &&
        (segments[2] == 'cancel' || segments[2] == 'reschedule')) {
      final appointmentId = int.tryParse(segments[1]);

      if (appointmentId == null || appointmentId <= 0) {
        return jsonResponse(400, {'error': 'Invalid appointment ID'});
      }

      final existing = db.select('SELECT * FROM appointments WHERE id = ?', [
        appointmentId,
      ]);

      if (existing.isEmpty) {
        return jsonResponse(404, {'error': 'Appointment not found'});
      }

      final currentStatus = existing.first['status'] as String;

      if (currentStatus != 'pending') {
        return jsonResponse(409, {
          'error': 'Only pending appointments can be modified',
        });
      }

      // =========================================
      // CANCEL APPOINTMENT
      // =========================================

      if (segments[2] == 'cancel') {
        db.execute('BEGIN IMMEDIATE TRANSACTION');

        try {
          db.execute(
            '''
            UPDATE appointments
            SET status = 'cancelled'
            WHERE id = ?
              AND status = 'pending'
          ''',
            [appointmentId],
          );

          // Cancel outstanding reminders.
          db.execute(
            '''
            UPDATE reminders
            SET status = 'cancelled',
                next_attempt_at = NULL
            WHERE appointment_id = ?
              AND status IN (
                'pending',
                'retry',
                'manual_review'
              )
          ''',
            [appointmentId],
          );

          logEvent(
            null,
            'appointment_cancelled',
            'Appointment $appointmentId cancelled',
          );

          db.execute('COMMIT');
        } catch (error) {
          db.execute('ROLLBACK');
          stderr.writeln('Cancellation failed: $error');

          return jsonResponse(500, {'error': 'Cancellation failed'});
        }

        return jsonResponse(200, {
          'message': 'Appointment cancelled successfully',
          'id': appointmentId,
          'status': 'cancelled',
        });
      }

      // =========================================
      // RESCHEDULE APPOINTMENT
      // =========================================

      try {
        final body = await request.readAsString();
        final decoded = jsonDecode(body);

        if (decoded is! Map<String, dynamic>) {
          return jsonResponse(400, {'error': 'Expected a JSON object'});
        }

        final scheduledAt = decoded['scheduled_at'];

        if (scheduledAt is! String) {
          return jsonResponse(400, {
            'error': 'Scheduled date and time are required',
          });
        }

        final newSchedule = DateTime.tryParse(scheduledAt);

        if (newSchedule == null || !newSchedule.isAfter(DateTime.now())) {
          return jsonResponse(400, {
            'error': 'Please choose a future appointment time',
          });
        }

        db.execute('BEGIN IMMEDIATE TRANSACTION');

        try {
          // Update appointment schedule.
          db.execute(
            '''
            UPDATE appointments
            SET scheduled_at = ?
            WHERE id = ?
              AND status = 'pending'
          ''',
            [newSchedule.toUtc().toIso8601String(), appointmentId],
          );

          // Cancel old undelivered reminders.
          db.execute(
            '''
            UPDATE reminders
            SET status = 'cancelled',
                next_attempt_at = NULL
            WHERE appointment_id = ?
              AND status IN (
                'pending',
                'retry',
                'manual_review'
              )
          ''',
            [appointmentId],
          );

          // Create new reminder.
          scheduleReminder(appointmentId, newSchedule);

          logEvent(
            null,
            'appointment_rescheduled',
            'Appointment $appointmentId updated to '
                '${newSchedule.toUtc().toIso8601String()}',
          );

          db.execute('COMMIT');
        } catch (_) {
          db.execute('ROLLBACK');
          rethrow;
        }

        return jsonResponse(200, {
          'message': 'Appointment rescheduled successfully',
          'id': appointmentId,
          'status': 'pending',
          'scheduled_at': newSchedule.toUtc().toIso8601String(),
        });
      } on FormatException {
        return jsonResponse(400, {'error': 'Invalid JSON request'});
      } catch (error) {
        stderr.writeln('Rescheduling failed: $error');

        return jsonResponse(500, {'error': 'Internal server error'});
      }
    }

    // =====================================================
    // CREATE APPOINTMENT
    // =====================================================

    if (method == 'POST' && path == 'appointments') {
      try {
        final body = await request.readAsString();
        final decoded = jsonDecode(body);

        if (decoded is! Map<String, dynamic>) {
          return jsonResponse(400, {'error': 'Expected a JSON object'});
        }

        final name = decoded['name'];
        final email = decoded['email'];
        final purpose = decoded['purpose'];
        final scheduledAt = decoded['scheduled_at'];

        // Validate fields.
        if (name is! String ||
            email is! String ||
            purpose is! String ||
            scheduledAt is! String ||
            name.trim().isEmpty ||
            purpose.trim().isEmpty ||
            !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim())) {
          return jsonResponse(400, {'error': 'Invalid appointment details'});
        }

        final schedule = DateTime.tryParse(scheduledAt);

        if (schedule == null || !schedule.isAfter(DateTime.now())) {
          return jsonResponse(400, {
            'error': 'Appointment must be in the future',
          });
        }

        db.execute('BEGIN IMMEDIATE TRANSACTION');

        late final int appointmentId;

        try {
          db.execute(
            '''
            INSERT INTO appointments (
              name,
              email,
              purpose,
              scheduled_at,
              created_at
            )
            VALUES (?, ?, ?, ?, ?)
          ''',
            [
              name.trim(),
              email.trim(),
              purpose.trim(),
              schedule.toUtc().toIso8601String(),
              nowUtc(),
            ],
          );

          appointmentId = db.lastInsertRowId;

          scheduleReminder(appointmentId, schedule);

          db.execute('COMMIT');
        } catch (_) {
          db.execute('ROLLBACK');
          rethrow;
        }

        return jsonResponse(201, {
          'message': 'Appointment created successfully',
          'id': appointmentId,
          'status': 'pending',
          'reminder_scheduled': true,
        });
      } on FormatException {
        return jsonResponse(400, {'error': 'Invalid JSON request'});
      } catch (error) {
        stderr.writeln('Appointment creation failed: $error');

        return jsonResponse(500, {'error': 'Internal server error'});
      }
    }

    // Unknown endpoint.
    return jsonResponse(404, {'error': 'Endpoint not found'});
  }

  // =====================================================
  // CORS CONFIGURATION
  // =====================================================

  // Local development only.
  const corsHeaders = {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET, POST, PATCH, OPTIONS',
    'access-control-allow-headers': 'Content-Type',
  };

  final handler = const Pipeline().addMiddleware(logRequests()).addHandler((
    Request request,
  ) async {
    if (request.method == 'OPTIONS') {
      return Response(204, headers: corsHeaders);
    }

    final response = await handleRequest(request);

    return response.change(headers: {...response.headers, ...corsHeaders});
  });

  // =====================================================
  // START SERVER
  // =====================================================

  final server = await shelf_io.serve(
    handler,
    InternetAddress.loopbackIPv4,
    8080,
  );

  print('Appointment backend running at:');
  print('http://${server.address.address}:${server.port}');

  print('Automation checks every 5 seconds.');
  print('Delivery mode: SIMULATED (no real emails).');

  // =====================================================
  // AUTOMATIC BACKGROUND SCHEDULER
  // =====================================================

  Timer.periodic(const Duration(seconds: 5), (_) {
    try {
      runAutomation();
    } catch (error, stack) {
      stderr.writeln('Automation error: $error');
      stderr.writeln(stack);
    }
  });

  // Check due reminders when server starts.
  runAutomation();
}
