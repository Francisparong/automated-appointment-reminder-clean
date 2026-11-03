import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String apiUrl = 'http://127.0.0.1:8080';

void main() {
  runApp(const AppointmentApp());
}

// ==========================================================
// APPLICATION
// ==========================================================

class AppointmentApp extends StatelessWidget {
  const AppointmentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Appointment Reminder System',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        scaffoldBackgroundColor: const Color(0xFFF8F7FC),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF2563EB),
          foregroundColor: Colors.white,
        ),
      ),
      home: const AppointmentDashboard(),
    );
  }
}

// ==========================================================
// APPOINTMENT MODEL
// ==========================================================

class Appointment {
  final int id;
  final String name;
  final String email;
  final String purpose;
  final DateTime schedule;
  final String status;

  const Appointment({
    required this.id,
    required this.name,
    required this.email,
    required this.purpose,
    required this.schedule,
    required this.status,
  });

  factory Appointment.fromJson(Map<String, dynamic> json) {
    return Appointment(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      email: json['email'] as String,
      purpose: json['purpose'] as String,
      schedule: DateTime.parse(json['scheduled_at'] as String).toLocal(),
      status: json['status'] as String,
    );
  }
}

class AppointmentData {
  final String name;
  final String email;
  final String purpose;
  final DateTime schedule;

  const AppointmentData({
    required this.name,
    required this.email,
    required this.purpose,
    required this.schedule,
  });
}

// ==========================================================
// API SERVICE
// ==========================================================

class AppointmentApi {
  static Future<List<Appointment>> getAppointments() async {
    final response = await http
        .get(Uri.parse('$apiUrl/appointments'))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! List) {
      throw const FormatException('Invalid appointment response');
    }

    return decoded.map((item) {
      return Appointment.fromJson(Map<String, dynamic>.from(item as Map));
    }).toList();
  }

  static Future<List<Map<String, dynamic>>> getRecords(String endpoint) async {
    final response = await http
        .get(Uri.parse('$apiUrl/$endpoint'))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! List) {
      throw const FormatException('Invalid API response');
    }

    return decoded.map((item) {
      return Map<String, dynamic>.from(item as Map);
    }).toList();
  }

  static Future<void> createAppointment(AppointmentData data) async {
    final response = await http
        .post(
          Uri.parse('$apiUrl/appointments'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': data.name,
            'email': data.email,
            'purpose': data.purpose,
            'scheduled_at': data.schedule.toUtc().toIso8601String(),
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 201) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  static Future<void> cancelAppointment(int id) async {
    final response = await http
        .patch(Uri.parse('$apiUrl/appointments/$id/cancel'))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  static Future<void> rescheduleAppointment(int id, DateTime date) async {
    final response = await http
        .patch(
          Uri.parse('$apiUrl/appointments/$id/reschedule'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'scheduled_at': date.toUtc().toIso8601String()}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }
}

// ==========================================================
// DASHBOARD
// ==========================================================

class AppointmentDashboard extends StatefulWidget {
  const AppointmentDashboard({super.key});

  @override
  State<AppointmentDashboard> createState() => _AppointmentDashboardState();
}

class _AppointmentDashboardState extends State<AppointmentDashboard> {
  List<Appointment> appointments = [];
  bool loading = false;
  bool processing = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    loadAppointments();
  }

  Future<void> loadAppointments() async {
    if (!mounted) return;

    setState(() {
      loading = true;
      errorMessage = null;
    });

    try {
      final result = await AppointmentApi.getAppointments();

      if (!mounted) return;
      setState(() {
        appointments = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  void showMessage(String message, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> addAppointment() async {
    final data = await showDialog<AppointmentData>(
      context: context,
      builder: (_) => const AppointmentForm(),
    );

    if (data == null || !mounted || processing) return;

    setState(() => processing = true);

    try {
      await AppointmentApi.createAppointment(data);
      await loadAppointments();

      if (errorMessage == null) {
        showMessage('Appointment saved to database!');
      } else {
        showMessage('Appointment saved. Refresh failed.', error: true);
      }
    } catch (e) {
      showMessage('Could not confirm appointment creation: $e', error: true);
    } finally {
      if (mounted) setState(() => processing = false);
    }
  }

  Future<void> cancelAppointment(Appointment item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel Appointment'),
        content: Text(
          'Are you sure you want to cancel '
          '${item.name}\'s appointment?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Go Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm Cancellation'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted || processing) return;
    setState(() => processing = true);

    try {
      await AppointmentApi.cancelAppointment(item.id);
      await loadAppointments();
      showMessage('Appointment cancelled successfully!');
    } catch (e) {
      showMessage('Cancellation failed: $e', error: true);
    } finally {
      if (mounted) setState(() => processing = false);
    }
  }

  Future<void> rescheduleAppointment(Appointment item) async {
    final now = DateTime.now();

    final newDate = await showDatePicker(
      context: context,
      initialDate: item.schedule.isAfter(now) ? item.schedule : now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );

    if (newDate == null || !mounted) return;

    final newTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(item.schedule),
    );

    if (newTime == null || !mounted) return;

    final selected = DateTime(
      newDate.year,
      newDate.month,
      newDate.day,
      newTime.hour,
      newTime.minute,
    );

    if (!selected.isAfter(DateTime.now())) {
      showMessage('Select a future appointment time.', error: true);
      return;
    }

    if (processing) return;
    setState(() => processing = true);

    try {
      await AppointmentApi.rescheduleAppointment(item.id, selected);
      await loadAppointments();
      showMessage('Appointment rescheduled successfully!');
    } catch (e) {
      showMessage('Reschedule failed: $e', error: true);
    } finally {
      if (mounted) setState(() => processing = false);
    }
  }

  void openMonitoring(String title, String endpoint) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MonitoringScreen(title: title, endpoint: endpoint),
      ),
    );
  }

  String formatSchedule(DateTime date) {
    final time = TimeOfDay.fromDateTime(date).format(context);
    return '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')} $time';
  }

  Color statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      case 'expired':
        return Colors.grey;
      case 'completed':
        return Colors.green;
      default:
        return Colors.blue;
    }
  }

  Widget monitoringCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String endpoint,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF2563EB)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => openMonitoring(title, endpoint),
      ),
    );
  }

  Widget appointmentCard(Appointment item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: ListTile(
          leading: const Icon(Icons.calendar_today, color: Color(0xFF2563EB)),
          title: Text(
            item.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.purpose),
                Text(item.email),
                Text(formatSchedule(item.schedule)),
                const SizedBox(height: 5),
                Text(
                  'Status: ${item.status.toUpperCase()}',
                  style: TextStyle(
                    color: statusColor(item.status),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          trailing: item.status == 'pending'
              ? PopupMenuButton<String>(
                  enabled: !processing,
                  tooltip: 'Appointment Actions',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'cancel') {
                      cancelAppointment(item);
                    } else if (value == 'reschedule') {
                      rescheduleAppointment(item);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'reschedule',
                      child: Text('Reschedule Appointment'),
                    ),
                    PopupMenuItem(
                      value: 'cancel',
                      child: Text('Cancel Appointment'),
                    ),
                  ],
                )
              : Icon(
                  Icons.check_circle_outline,
                  color: statusColor(item.status),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appointment Reminder System'),
        actions: [
          IconButton(
            onPressed: loading ? null : loadAppointments,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 20),
              const Icon(
                Icons.event_available,
                size: 70,
                color: Color(0xFF2563EB),
              ),
              const SizedBox(height: 15),
              const Text(
                'Appointment Dashboard',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Manage appointment requests and reminders.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 25),

              FilledButton.icon(
                onPressed: processing ? null : addAppointment,
                icon: const Icon(Icons.add),
                label: const Text('New Appointment'),
              ),
              const SizedBox(height: 18),

              monitoringCard(
                icon: Icons.notifications_active,
                title: 'Scheduled Reminders',
                subtitle: 'View reminder schedules and statuses',
                endpoint: 'reminders',
              ),

              monitoringCard(
                icon: Icons.refresh,
                title: 'Retry Monitor',
                subtitle: 'View retry and recovery events',
                endpoint: 'logs',
              ),

              monitoringCard(
                icon: Icons.warning_amber,
                title: 'Manual Review',
                subtitle: 'View permanent delivery failures',
                endpoint: 'manual-review',
              ),

              const SizedBox(height: 24),
              Text(
                'Appointments (${appointments.length})',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              if (loading) const Center(child: CircularProgressIndicator()),

              if (errorMessage != null)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Error loading appointments: $errorMessage'),
                  ),
                ),

              if (!loading && errorMessage == null && appointments.isEmpty)
                const Card(
                  child: ListTile(
                    title: Text('No appointments found'),
                    subtitle: Text('Click New Appointment to create one.'),
                  ),
                ),

              for (final item in appointments) appointmentCard(item),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================================
// NEW APPOINTMENT FORM
// ==========================================================

class AppointmentForm extends StatefulWidget {
  const AppointmentForm({super.key});

  @override
  State<AppointmentForm> createState() => _AppointmentFormState();
}

class _AppointmentFormState extends State<AppointmentForm> {
  final formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final purposeController = TextEditingController();

  DateTime? selectedDate;
  TimeOfDay? selectedTime;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    purposeController.dispose();
    super.dispose();
  }

  Future<void> selectDate() async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );

    if (picked != null && mounted) {
      setState(() => selectedDate = picked);
    }
  }

  Future<void> selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (picked != null && mounted) {
      setState(() => selectedTime = picked);
    }
  }

  void submit() {
    if (!formKey.currentState!.validate()) return;

    if (selectedDate == null || selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select date and time.')),
      );
      return;
    }

    final schedule = DateTime(
      selectedDate!.year,
      selectedDate!.month,
      selectedDate!.day,
      selectedTime!.hour,
      selectedTime!.minute,
    );

    if (!schedule.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a future appointment time.')),
      );
      return;
    }

    Navigator.pop(
      context,
      AppointmentData(
        name: nameController.text.trim(),
        email: emailController.text.trim(),
        purpose: purposeController.text.trim(),
        schedule: schedule,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Appointment'),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Please enter your name'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                        .hasMatch(email)) {
                      return 'Enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: purposeController,
                  decoration: const InputDecoration(
                    labelText: 'Appointment Purpose',
                    prefixIcon: Icon(Icons.description_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Please enter a purpose'
                      : null,
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: selectDate,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(
                    selectedDate == null
                        ? 'Select Date'
                        : '${selectedDate!.year}-'
                              '${selectedDate!.month}-'
                              '${selectedDate!.day}',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: selectTime,
                  icon: const Icon(Icons.access_time),
                  label: Text(
                    selectedTime == null
                        ? 'Select Time'
                        : selectedTime!.format(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: submit,
          child: const Text('Create Appointment'),
        ),
      ],
    );
  }
}

// ==========================================================
// MONITORING SCREEN
// ==========================================================

class MonitoringScreen extends StatefulWidget {
  final String title;
  final String endpoint;

  const MonitoringScreen({
    super.key,
    required this.title,
    required this.endpoint,
  });

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen> {
  List<Map<String, dynamic>> records = [];
  bool loading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    loadRecords();
  }

  Future<void> loadRecords() async {
    if (!mounted) return;

    setState(() {
      loading = true;
      errorMessage = null;
    });

    try {
      final result = await AppointmentApi.getRecords(widget.endpoint);

      if (!mounted) return;

      setState(() {
        records = result;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  bool isRetryRelated(Map<String, dynamic> record) {
    final event = record['event']?.toString() ?? '';

    return event == 'retry_scheduled' ||
        event == 'delivery_attempt' ||
        event == 'delivered' ||
        event == 'manual_review';
  }

  String readableValue(dynamic value) {
    if (value == null) return 'None';

    if (value is String) {
      final date = DateTime.tryParse(value);

      if (date != null && value.contains('T')) {
        final local = date.toLocal();
        return '${local.year}-'
            '${local.month.toString().padLeft(2, '0')}-'
            '${local.day.toString().padLeft(2, '0')} '
            '${local.hour.toString().padLeft(2, '0')}:'
            '${local.minute.toString().padLeft(2, '0')}';
      }
    }

    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final displayedRecords = widget.endpoint == 'logs'
        ? records.where(isRetryRelated).toList()
        : records;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: loading ? null : loadRecords,
            tooltip: 'Refresh records',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Unable to load records:\n$errorMessage',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: loadRecords,
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            )
          : displayedRecords.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.inbox_outlined,
                    size: 55,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 12),
                  const Text('No records found.'),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: loadRecords,
                    child: const Text('Refresh'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: loadRecords,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: displayedRecords.length,
                    itemBuilder: (context, index) {
                      final record = displayedRecords[index];

                      final title = widget.endpoint == 'logs'
                          ? record['event']?.toString() ?? 'System Event'
                          : record['name']?.toString() ?? 'Reminder Record';

                      final status = record['status']?.toString() ?? '';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (status.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Chip(
                                    label: Text(status.toUpperCase()),
                                  ),
                                ),
                              const Divider(height: 24),
                              for (final entry in record.entries)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 7),
                                  child: SelectableText(
                                    '${entry.key}: '
                                    '${readableValue(entry.value)}',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
    );
  }
}
