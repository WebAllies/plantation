#include <Arduino.h>

// Analog channels on the Arduino Nano
const int PH_PIN = A2;
const int TDS_PIN = A1;

// Ultrasonic sensors on the Arduino Nano
const int PH_UP_TRIG_PIN = 4;
const int PH_UP_ECHO_PIN = 5;
const int PH_DOWN_TRIG_PIN = 6;
const int PH_DOWN_ECHO_PIN = 7;
const int NUTRIENT_TRIG_PIN = 8;
const int NUTRIENT_ECHO_PIN = 9;

// Sampling and timing
const size_t ANALOG_SAMPLE_COUNT = 15;
const unsigned long PUBLISH_INTERVAL_MS = 1000;
const unsigned long ULTRASONIC_TIMEOUT_US = 50000;
const unsigned long SERIAL_BAUD = 115200;
const uint8_t ULTRASONIC_ATTEMPTS = 3;
const float ADC_REFERENCE_VOLTAGE = 5.0f;
const float ADC_MAX_READING = 1023.0f;

// Calibration constants: tune these with your actual probes/solutions.
const float PH_SLOPE = -5.70f;
const float PH_OFFSET = 21.34f;
const float TDS_FACTOR = 0.5f;
const float TDS_COMPENSATION_C = 25.0f;
const float LEVEL_MIN_PCT = 0.0f;
const float LEVEL_MAX_PCT = 100.0f;
const float TANK_HEIGHT_CM = 10.0f;
const float PH_UP_FULL_DISTANCE_CM = 5.0f;
const float PH_UP_EMPTY_DISTANCE_CM = PH_UP_FULL_DISTANCE_CM + TANK_HEIGHT_CM;
const float PH_DOWN_FULL_DISTANCE_CM = 5.0f;
const float PH_DOWN_EMPTY_DISTANCE_CM = PH_DOWN_FULL_DISTANCE_CM + TANK_HEIGHT_CM;
const float NUTRIENT_FULL_DISTANCE_CM = 5.0f;
const float NUTRIENT_EMPTY_DISTANCE_CM = NUTRIENT_FULL_DISTANCE_CM + TANK_HEIGHT_CM;

unsigned long lastPublishMs = 0;

void sortFloatArray(float *values, size_t length) {
  for (size_t i = 0; i < length; i++) {
    for (size_t j = i + 1; j < length; j++) {
      if (values[j] < values[i]) {
        float tmp = values[i];
        values[i] = values[j];
        values[j] = tmp;
      }
    }
  }
}

float readMedianAverageAnalog(int pin) {
  float samples[ANALOG_SAMPLE_COUNT];
  for (size_t i = 0; i < ANALOG_SAMPLE_COUNT; i++) {
    samples[i] = (float)analogRead(pin);
    delay(5);
  }

  sortFloatArray(samples, ANALOG_SAMPLE_COUNT);

  size_t trim = ANALOG_SAMPLE_COUNT / 3;
  size_t start = trim / 2;
  size_t end = ANALOG_SAMPLE_COUNT - start;

  float sum = 0.0f;
  size_t count = 0;
  for (size_t i = start; i < end; i++) {
    sum += samples[i];
    count++;
  }

  return count == 0 ? NAN : sum / (float)count;
}

float analogToVoltage(float raw) {
  return (raw / ADC_MAX_READING) * ADC_REFERENCE_VOLTAGE;
}

float computePh(float raw) {
  float voltage = analogToVoltage(raw);
  float phValue = (PH_SLOPE * voltage) + PH_OFFSET;
  if (phValue < 0.0f) phValue = 0.0f;
  if (phValue > 14.0f) phValue = 14.0f;
  return phValue;
}

float computeTds(float raw, float waterTempC) {
  float voltage = analogToVoltage(raw);
  float compensationCoefficient = 1.0f + 0.02f * (waterTempC - 25.0f);
  if (compensationCoefficient < 0.01f) compensationCoefficient = 1.0f;

  float compensatedVoltage = voltage / compensationCoefficient;
  float tdsValue =
    (133.42f * compensatedVoltage * compensatedVoltage * compensatedVoltage
     - 255.86f * compensatedVoltage * compensatedVoltage
     + 857.39f * compensatedVoltage) * TDS_FACTOR;

  if (tdsValue < 0.0f) tdsValue = 0.0f;
  return tdsValue;
}

float mapToPercent(float raw, float emptyRaw, float fullRaw) {
  if (fabs(fullRaw - emptyRaw) < 0.001f) return NAN;
  float percent = ((raw - emptyRaw) * 100.0f) / (fullRaw - emptyRaw);
  if (percent < LEVEL_MIN_PCT) percent = LEVEL_MIN_PCT;
  if (percent > LEVEL_MAX_PCT) percent = LEVEL_MAX_PCT;
  return percent;
}

float readDistanceCm(int trigPin, int echoPin) {
  float bestReading = NAN;

  for (uint8_t attempt = 0; attempt < ULTRASONIC_ATTEMPTS; attempt++) {
    digitalWrite(trigPin, LOW);
    delayMicroseconds(4);
    digitalWrite(trigPin, HIGH);
    delayMicroseconds(12);
    digitalWrite(trigPin, LOW);

    unsigned long durationUs = pulseIn(echoPin, HIGH, ULTRASONIC_TIMEOUT_US);
    if (durationUs > 0) {
      float distanceCm = durationUs * 0.0343f / 2.0f;
      if (isfinite(distanceCm) && distanceCm > 1.0f && distanceCm < 450.0f) {
        bestReading = distanceCm;
        break;
      }
    }

    delay(25);
  }

  return bestReading;
}

void primeUltrasonicPin(int trigPin, int echoPin) {
  pinMode(trigPin, OUTPUT);
  digitalWrite(trigPin, LOW);
  pinMode(echoPin, INPUT);
}

void printMachineMetric(const char *key, float value) {
  if (!isfinite(value)) return;
  Serial.print(key);
  Serial.print(":");
  Serial.println(value, 2);
}

void printUltrasonicError(const char *key, int trigPin, int echoPin) {
  Serial.print("ERR:");
  Serial.print(key);
  Serial.print(":NO_ECHO trig=D");
  Serial.print(trigPin);
  Serial.print(" echo=D");
  Serial.println(echoPin);
}

void printMonitorMetric(const char *label, float value, const char *unit) {
  Serial.print("MON:");
  Serial.print(label);
  Serial.print(" = ");
  if (isfinite(value)) {
    Serial.print(value, 2);
    if (unit != nullptr && unit[0] != '\0') {
      Serial.print(" ");
      Serial.print(unit);
    }
  } else {
    Serial.print("NO READING");
  }
  Serial.println();
}

void printStartupWiring() {
  Serial.println("MON:Nano aquaponics sensor sketch started");
  Serial.println("MON:Baud = 115200");
  Serial.println("MON:pH AO -> A2");
  Serial.println("MON:TDS AO -> A1");
  Serial.println("MON:pH Up ultrasonic TRIG=D4 ECHO=D5");
  Serial.println("MON:pH Down ultrasonic TRIG=D6 ECHO=D7");
  Serial.println("MON:Nutrient ultrasonic TRIG=D8 ECHO=D9");
  Serial.println("MON:If a sensor shows ERR:<KEY>:NO_ECHO, check VCC/GND/TRIG/ECHO for that exact pair.");
}

float distanceToPercent(float distanceCm, float emptyDistanceCm, float fullDistanceCm) {
  return mapToPercent(distanceCm, emptyDistanceCm, fullDistanceCm);
}

void setup() {
  Serial.begin(SERIAL_BAUD);
  primeUltrasonicPin(PH_UP_TRIG_PIN, PH_UP_ECHO_PIN);
  primeUltrasonicPin(PH_DOWN_TRIG_PIN, PH_DOWN_ECHO_PIN);
  primeUltrasonicPin(NUTRIENT_TRIG_PIN, NUTRIENT_ECHO_PIN);
  delay(1000);
  printStartupWiring();
}

void loop() {
  if (millis() - lastPublishMs < PUBLISH_INTERVAL_MS) {
    return;
  }
  lastPublishMs = millis();

  float phRaw = readMedianAverageAnalog(PH_PIN);
  float tdsRaw = readMedianAverageAnalog(TDS_PIN);
  float phUpDistanceCm = readDistanceCm(PH_UP_TRIG_PIN, PH_UP_ECHO_PIN);
  float phDownDistanceCm = readDistanceCm(PH_DOWN_TRIG_PIN, PH_DOWN_ECHO_PIN);
  float nutrientDistanceCm = readDistanceCm(NUTRIENT_TRIG_PIN, NUTRIENT_ECHO_PIN);
  float phValue = isfinite(phRaw) ? computePh(phRaw) : NAN;
  float tdsValue = isfinite(tdsRaw) ? computeTds(tdsRaw, TDS_COMPENSATION_C) : NAN;
  float phUpLevelPct = isfinite(phUpDistanceCm)
    ? distanceToPercent(
        phUpDistanceCm,
        PH_UP_EMPTY_DISTANCE_CM,
        PH_UP_FULL_DISTANCE_CM
      )
    : NAN;
  float phDownLevelPct = isfinite(phDownDistanceCm)
    ? distanceToPercent(
        phDownDistanceCm,
        PH_DOWN_EMPTY_DISTANCE_CM,
        PH_DOWN_FULL_DISTANCE_CM
      )
    : NAN;
  float nutrientLevelPct = isfinite(nutrientDistanceCm)
    ? distanceToPercent(
        nutrientDistanceCm,
        NUTRIENT_EMPTY_DISTANCE_CM,
        NUTRIENT_FULL_DISTANCE_CM
      )
    : NAN;

  printMachineMetric("PH", phValue);
  printMachineMetric("TDS", tdsValue);
  printMachineMetric("PHUP", phUpLevelPct);
  printMachineMetric("PHDOWN", phDownLevelPct);
  printMachineMetric("NUTRIENT", nutrientLevelPct);
  if (!isfinite(phUpDistanceCm)) printUltrasonicError("PHUP", PH_UP_TRIG_PIN, PH_UP_ECHO_PIN);
  if (!isfinite(phDownDistanceCm)) printUltrasonicError("PHDOWN", PH_DOWN_TRIG_PIN, PH_DOWN_ECHO_PIN);
  if (!isfinite(nutrientDistanceCm)) printUltrasonicError("NUTRIENT", NUTRIENT_TRIG_PIN, NUTRIENT_ECHO_PIN);

  Serial.println("MON:------------------------------");
  printMonitorMetric("pH", phValue, "pH");
  printMonitorMetric("TDS", tdsValue, "ppm");
  printMonitorMetric("pH raw ADC", phRaw, "");
  printMonitorMetric("TDS raw ADC", tdsRaw, "");
  printMonitorMetric("pH Up tank level", phUpLevelPct, "%");
  printMonitorMetric("pH Down tank level", phDownLevelPct, "%");
  printMonitorMetric("Nutrient tank level", nutrientLevelPct, "%");
  printMonitorMetric("pH Up distance", phUpDistanceCm, "cm");
  printMonitorMetric("pH Down distance", phDownDistanceCm, "cm");
  printMonitorMetric("Nutrient distance", nutrientDistanceCm, "cm");
  Serial.println("MON:------------------------------");
}
