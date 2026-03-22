# Aquaponics Wiring README

This document describes the current hardware wiring for the `uno_aquaponics` and `esp32_aquaponics` sketches in this repo.

Current architecture:
- Arduino Uno handles all analog and ultrasonic sensors
- ESP32 handles DS18B20 temperature, Wi-Fi, MQTT, Firebase, and app/backend telemetry
- Uno sends sensor values to the ESP32 over UART

## Firmware Upload
- Upload [uno_aquaponics](/mnt/e/shuaib/plantation/uno_aquaponics) to the Arduino Uno
- Upload [esp32_aquaponics](/mnt/e/shuaib/plantation/esp32_aquaponics) to the ESP32

## Board Roles
### Arduino Uno
- Reads pH sensor on `A0`
- Reads TDS sensor on `A1`
- Reads 4 ultrasonic tank level sensors on digital pins
- Sends serial messages to the ESP32:
  - `PH:x.xx`
  - `TDS:xxx.xx`
  - `FISH:xx.xx`
  - `PHUP:xx.xx`
  - `PHDOWN:xx.xx`
  - `NUTRIENT:xx.xx`

### ESP32
- Reads DS18B20 water temperature on `GPIO 4`
- Receives Uno serial data on `GPIO 16`
- Publishes telemetry to MQTT and Firebase

## Arduino Uno Wiring
### pH Sensor Module
- `AO` -> Uno `A0`
- `VCC` -> Uno `5V` or the module's rated supply
- `GND` -> Uno `GND`

### TDS Sensor Module
- `AO` -> Uno `A1`
- `VCC` -> Uno `5V` or the module's rated supply
- `GND` -> Uno `GND`

### Fish Tank Ultrasonic Sensor
- `TRIG` -> Uno `D2`
- `ECHO` -> Uno `D3`
- `VCC` -> Uno `5V`
- `GND` -> Uno `GND`

### pH Up Tank Ultrasonic Sensor
- `TRIG` -> Uno `D4`
- `ECHO` -> Uno `D5`
- `VCC` -> Uno `5V`
- `GND` -> Uno `GND`

### pH Down Tank Ultrasonic Sensor
- `TRIG` -> Uno `D6`
- `ECHO` -> Uno `D7`
- `VCC` -> Uno `5V`
- `GND` -> Uno `GND`

### Nutrient Tank Ultrasonic Sensor
- `TRIG` -> Uno `D8`
- `ECHO` -> Uno `D9`
- `VCC` -> Uno `5V`
- `GND` -> Uno `GND`

## ESP32 Wiring
### DS18B20 Water Temperature Sensor
- `DATA` -> ESP32 `GPIO 4`
- `VDD` -> ESP32 `3.3V`
- `GND` -> ESP32 `GND`
- Add a `4.7k` resistor between `DATA` and `3.3V`

### Uno To ESP32 UART
- Uno `TX` -> ESP32 `GPIO 16` through a voltage divider or logic level shifter
- Uno `GND` -> ESP32 `GND`
- Optional: ESP32 `GPIO 17` -> Uno `RX` if you later want 2-way serial

## Required Common Ground
All grounds must be connected together:
- Uno `GND`
- ESP32 `GND`
- pH sensor `GND`
- TDS sensor `GND`
- all ultrasonic sensor `GND` pins
- DS18B20 `GND`

Without common ground, UART and sensor readings will not be reliable.

## Important Voltage Note
Do not connect Uno `TX` directly to ESP32 `GPIO 16`.

Why:
- Uno serial output is `5V`
- ESP32 GPIO is `3.3V` only

Use one of these:
- logic level shifter
- resistor divider

Simple resistor divider example:
- Uno `TX` -> `1k resistor` -> junction -> ESP32 `GPIO 16`
- junction -> `2k resistor` -> `GND`

## Serial Monitor Output On The Uno
The Uno sketch prints both machine-readable lines and human-readable monitor lines.

Examples:

```text
PH:6.42
TDS:913.20
FISH:78.50
PHUP:66.10
PHDOWN:81.30
NUTRIENT:54.90
MON:------------------------------
MON:pH = 6.42 pH
MON:TDS = 913.20 ppm
MON:Fish tank level = 78.50 %
MON:pH Up tank level = 66.10 %
MON:pH Down tank level = 81.30 %
MON:Nutrient tank level = 54.90 %
MON:Fish distance = 12.30 cm
MON:pH Up distance = 14.10 cm
MON:pH Down distance = 10.40 cm
MON:Nutrient distance = 16.50 cm
MON:------------------------------
```

Use Uno Serial Monitor at:
- `9600 baud`

## Calibration Notes
The current sketches use placeholder calibration constants. These must be tuned on your real hardware.

### Uno pH/TDS
Check and tune in [uno_aquaponics](/mnt/e/shuaib/plantation/uno_aquaponics):
- `PH_SLOPE`
- `PH_OFFSET`
- `TDS_FACTOR`

### Ultrasonic Tank Levels
Check and tune in [uno_aquaponics](/mnt/e/shuaib/plantation/uno_aquaponics):
- `FISH_TANK_EMPTY_DISTANCE_CM`
- `FISH_TANK_FULL_DISTANCE_CM`
- `PH_UP_EMPTY_DISTANCE_CM`
- `PH_UP_FULL_DISTANCE_CM`
- `PH_DOWN_EMPTY_DISTANCE_CM`
- `PH_DOWN_FULL_DISTANCE_CM`
- `NUTRIENT_EMPTY_DISTANCE_CM`
- `NUTRIENT_FULL_DISTANCE_CM`

Meaning:
- `EMPTY_DISTANCE_CM` = sensor is farther from the water surface
- `FULL_DISTANCE_CM` = water is closer to the sensor

## Libraries Needed
### Uno
- No extra libraries required for the current `uno_aquaponics` sketch

### ESP32
- `Firebase ESP Client`
- `WebSockets`
- `PubSubClient`
- `OneWire`
- `DallasTemperature`

## Troubleshooting
### Uno upload says port access denied
- Close Serial Monitor
- Close any serial terminal using the Uno COM port
- Replug the board
- Re-select the COM port

### ESP32 compile says `OneWire.h` not found
- Install the `OneWire` library in Arduino IDE

### ESP32 receives no pH/TDS/level data
- Check Uno is powered and running
- Check Uno `TX` to ESP32 `GPIO 16`
- Check shared ground
- Check baud rate is `9600`
- Check level shifting from Uno `TX` to ESP32 `RX`
