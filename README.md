
# Automated Appointment Reminder System

## Project Overview

An Automated Appointment Reminder System built using Flutter Web,
Dart, REST APIs, and SQLite.

This project demonstrates appointment management and automated
reminder workflows for a Week 13 Automation Foundation activity.

## Technologies

- Flutter Web
- Dart
- Shelf REST API
- SQLite
- HTTP

## Features

- Create appointments
- Validate appointment information
- View appointment records
- Cancel appointments
- Reschedule appointments
- Automatically schedule reminders
- Simulate reminder delivery
- Retry temporary delivery failures
- Apply a maximum retry limit
- Route permanent failures to manual review
- Close expired appointments
- Record structured automation logs
- Monitor reminders and retry events in Flutter

## Project Structure

flutter_frontend/ - Flutter Web application

appointment_backend/ - Dart REST API and SQLite backend

## Running the Backend

Open a terminal:

```powershell
cd appointment_backend
dart pub get
dart run
```

The API runs locally at:

http://127.0.0.1:8080

## Running Flutter Web

Open another terminal:

```powershell
cd flutter_frontend
flutter pub get
flutter run -d chrome
```

## API Endpoints

- GET /health
- GET /appointments
- POST /appointments
- PATCH /appointments/{id}/cancel
- PATCH /appointments/{id}/reschedule
- GET /reminders
- GET /logs
- GET /manual-review

## Important Notes

The system uses simulated reminder delivery for educational testing.

The SQLite database is stored locally and is not committed to GitHub.

This is a local educational prototype and does not provide production
authentication or real email delivery.
