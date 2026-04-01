# Aquaponics Wiring README

This document describes the current hardware wiring for the `uno_aquaponics` and `esp32_aquaponics` sketches in this repo.

Current architecture:
- Arduino Nano handles all analog and ultrasonic sensors
- ESP32 handles DS18B20 temperature, Wi-Fi, MQTT, Firebase, and app/backend telemetry
- Nano sends sensor values to the ESP32 over UART

## Firmware Upload
- Upload [uno_aquaponics](/mnt/e/shuaib/plantation/uno_aquaponics) to the Arduino Nano
- Upload [esp32_aquaponics](/mnt/e/shuaib/plantation/esp32_aquaponics) to the ESP32

## Board Roles
### Arduino Nano
- Reads pH sensor on `A2`
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
- Receives Nano serial data on `GPIO 16`
- Drives 5 relays on GPIO outputs
- Publishes telemetry to MQTT and Firebase

## Arduino Nano Wiring
### pH Sensor Module
- `AO` -> Nano `A2`
- `VCC` -> Nano `5V` or the module's rated supply
- `GND` -> Nano `GND`

### TDS Sensor Module
- `AO` -> Nano `A1`
- `VCC` -> Nano `5V` or the module's rated supply
- `GND` -> Nano `GND`

### Fish Tank Ultrasonic Sensor
- `TRIG` -> Nano `D2`
- `ECHO` -> Nano `D3`
- `VCC` -> Nano `5V`
- `GND` -> Nano `GND`

### pH Up Tank Ultrasonic Sensor
- `TRIG` -> Nano `D4`
- `ECHO` -> Nano `D5`
- `VCC` -> Nano `5V`
- `GND` -> Nano `GND`

### pH Down Tank Ultrasonic Sensor
- `TRIG` -> Nano `D6`
- `ECHO` -> Nano `D7`
- `VCC` -> Nano `5V`
- `GND` -> Nano `GND`

### Nutrient Tank Ultrasonic Sensor
- `TRIG` -> Nano `D8`
- `ECHO` -> Nano `D9`
- `VCC` -> Nano `5V`
- `GND` -> Nano `GND`

## ESP32 Wiring
### DS18B20 Water Temperature Sensor
- `DATA` -> ESP32 `GPIO 4`
- `VDD` -> ESP32 `3.3V`
- `GND` -> ESP32 `GND`
- Add a `4.7k` resistor between `DATA` and `3.3V`

### Nano To ESP32 UART
- Nano `TX` -> ESP32 `GPIO 16` through a voltage divider or logic level shifter
- Nano `GND` -> ESP32 `GND`
- Optional: ESP32 `GPIO 17` -> Nano `RX` if you later want 2-way serial

### ESP32 Outputs
- `GPIO 18` -> pH Up relay input
- `GPIO 19` -> pH Down relay input
- `GPIO 21` -> nutrient relay input
- `GPIO 22` -> fish tank to filter bed relay input
- `GPIO 23` -> fish feeder servo signal
- relay module `GND` -> ESP32 `GND`
- relay module `VCC` -> module-rated supply
- fish feeder servo `GND` -> common `GND`
- fish feeder servo `VCC` -> stable `5V` supply
- fish feeder servo `SIG` -> ESP32 `GPIO 23`

Note:
- current firmware assumes active-high relay control
- if your relay board is active-low, firmware constants must be adjusted
- the fish feeder is now a servo, not a relay
- do not power the servo from the ESP32 `3.3V` pin

## Required Common Ground
All grounds must be connected together:
- Nano `GND`
- ESP32 `GND`
- pH sensor `GND`
- TDS sensor `GND`
- all ultrasonic sensor `GND` pins
- DS18B20 `GND`

Without common ground, UART and sensor readings will not be reliable.

## Important Voltage Note
Do not connect Nano `TX` directly to ESP32 `GPIO 16`.

Why:
- Nano serial output is `5V`
- ESP32 GPIO is `3.3V` only

Use one of these:
- logic level shifter
- resistor divider

Simple resistor divider example:
- Nano `TX` -> `1k resistor` -> junction -> ESP32 `GPIO 16`
- junction -> `2k resistor` -> `GND`

## Serial Monitor Output On The Nano
The Nano sketch prints both machine-readable lines and human-readable monitor lines.

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

Use Nano Serial Monitor at:
- `115200 baud`

## Calibration Notes
The current sketches use placeholder calibration constants. These must be tuned on your real hardware.

### Nano pH/TDS
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
### Nano
- No extra libraries required for the current `uno_aquaponics` sketch

### ESP32
- `Firebase ESP Client`
- `ESP32Servo`
- `WebSockets`
- `PubSubClient`
- `OneWire`
- `DallasTemperature`

## Troubleshooting
### Nano upload says port access denied
- Close Serial Monitor
- Close any serial terminal using the Nano COM port
- Replug the board
- Re-select the COM port

### ESP32 compile says `OneWire.h` not found
- Install the `OneWire` library in Arduino IDE

### ESP32 receives no pH/TDS/level data
- Check Nano is powered and running
- Check Nano `TX` to ESP32 `GPIO 16`
- Check shared ground
- Check baud rate is `115200`
- Check level shifting from Nano `TX` to ESP32 `RX`
