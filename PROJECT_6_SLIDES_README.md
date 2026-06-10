# Aquaponics IoT Project: 6-Slide Explanation

Use this file as a simple presentation script. Each section can become one slide.

## Slide 1: Project Overview

This project is a smart aquaponics monitoring and control system.

It combines a Flutter mobile app, ESP32 controller, Arduino Nano sensor board, relays, a fish feeder servo, a realtime server, PostgreSQL, and Firebase.

Main goal:
- Monitor fish tank and dosing tank readings live.
- Control relays and fish feeder from the mobile app.
- Keep data fast through the realtime server.
- Keep Firebase as a backup NoSQL copy of the server database.

## Slide 2: Hardware System

The hardware is split into two microcontrollers:

- Arduino Nano reads the analog and ultrasonic sensors.
- ESP32 connects to WiFi, receives Nano readings, controls relays, controls the servo feeder, and sends data online.

Main hardware parts:
- pH sensor.
- TDS sensor.
- Fish tank ultrasonic level sensor.
- pH Up tank level sensor.
- pH Down tank level sensor.
- Nutrient tank level sensor.
- Relay outputs for dosing and water movement.
- Fish feeder servo on GPIO 23.

Important connection:
- Nano TX D1 sends serial data to ESP32 RX16.
- Both boards must share GND.
- Nano TX is 5V, so ESP32 RX should be protected using a level shifter or voltage divider.

## Slide 3: Firmware And Sensor Flow

The Arduino Nano continuously prints sensor readings over serial at 115200 baud.

The ESP32 listens to this serial stream and builds a live telemetry snapshot.

The ESP32 sends:
- pH.
- TDS.
- Fish tank water level.
- pH Up tank level.
- pH Down tank level.
- Nutrient tank level.
- Relay states.
- Fish feeder state.
- ESP online/offline status.
- Nano health status.

If the ESP32 does not receive valid Nano data for 15 seconds, it reports:
- `nanoOnline: false`
- `nanoError` with a wiring/baud/power troubleshooting message.

This makes Nano connection problems visible inside the app.

## Slide 4: Realtime Server And Data Streaming

The realtime server is the primary communication layer.

Data path:

1. ESP32 publishes telemetry using MQTT.
2. Realtime server receives MQTT messages.
3. Server stores data in PostgreSQL.
4. Server streams live updates to the Flutter app using WebSocket.
5. App sends relay and feeder commands back through WebSocket or HTTP.
6. Server publishes commands to the ESP32 over MQTT.
7. ESP32 executes the command and sends an acknowledgement.

Why this is fast:
- MQTT is lightweight for ESP32 communication.
- WebSocket keeps a live connection open to the app.
- The app does not need to wait for Firebase reads/writes before showing live data.

## Slide 5: Mobile App Features

The Flutter app provides the user interface.

Main screens/features:
- Live dashboard for all sensor readings.
- ESP online/offline status.
- Last seen time.
- Realtime stream status.
- Nano data error warning.
- Manual relay controls.
- pH Up, pH Down, and Nutrient dosing controls.
- Fish feeder button for two full rotations.
- Automation settings.
- Firebase login/authentication.

The app uses neutral wording like "Realtime Server" and "Cloud Sync" instead of showing infrastructure/vendor names.

## Slide 6: Database, Backup, And Reliability

PostgreSQL is the primary database.

It stores:
- Latest device state.
- Telemetry history.
- Relay states.
- Commands.
- Command acknowledgements.
- Device online/offline state.

Firebase Firestore is the backup NoSQL database.

How backup works:
- Every PostgreSQL write creates a sync queue item.
- A backend worker reads the queue.
- The worker copies the data into Firebase Firestore.
- Synced items are marked complete.

This gives the system:
- Fast local/server-first operation.
- Live app updates.
- Firebase login.
- Firebase NoSQL backup of telemetry, commands, and device state.
- Offline detection when ESP32 stops sending heartbeats.

## One-Sentence Summary

This project is a realtime aquaponics control system where ESP32 and Arduino Nano collect sensor data, a realtime server streams it quickly to the Flutter app, PostgreSQL stores the primary data, and Firebase keeps a synchronized NoSQL backup.
