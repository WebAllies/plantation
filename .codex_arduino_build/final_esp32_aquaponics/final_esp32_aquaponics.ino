#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include <WebSocketsServer.h>
#include <WebSocketsClient.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <ESP32Servo.h>
#include <math.h>
#include <stdlib.h>
#include <limits.h>
#include <time.h>

#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"

// -------------------- WIFI --------------------
#define WIFI_SSID "muhammad"
#define WIFI_SSID_FALLBACK "Muhammad"
#define WIFI_PASS "qwertyuiop"

// -------------------- FIREBASE --------------------
#define API_KEY "AIzaSyCKU-jSEXoftXGq9653hJql7YWXG7_Rtr8"
#define FIREBASE_PROJECT_ID "iotaquaapp"
#define USER_EMAIL "device@iot.com" 
#define USER_PASSWORD "device12345"

// -------------------- MQTT --------------------
#define MQTT_BROKER_HOST "116.203.96.119"
#define MQTT_BROKER_PORT 1883
#define MQTT_USE_TLS 0
#define MQTT_USERNAME ""
#define MQTT_PASSWORD ""
#define BACKEND_WS_HOST MQTT_BROKER_HOST
#define BACKEND_WS_PORT 8080

// -------------------- DEVICE --------------------
#define DEVICE_ID "esp32_aquaponics_01"
const char *deviceId = DEVICE_ID;
const uint16_t WS_PORT = 81;

// -------------------- GPIO --------------------
const int RELAY_PH_UP_PIN = 18;
const int RELAY_PH_DOWN_PIN = 19;
const int RELAY_NUTRIENT_PIN = 21;
const int RELAY_FISH_TO_FILTER_PIN = 22;
const int FISH_FEEDER_SERVO_PIN = 23;
// Most small ESP32 relay boards are active-low: LOW energizes the relay.
// Set this to true only if your relay board switches on when the GPIO is HIGH.
const bool RELAY_ACTIVE_HIGH = false;
const int FISH_FEEDER_SERVO_IDLE_DEG = 90;
const int FISH_FEEDER_SERVO_ACTIVE_DEG = 180;
const int FISH_FEEDER_SERVO_MIN_US = 500;
const int FISH_FEEDER_SERVO_MAX_US = 2400;
const int FISH_FEEDER_ROTATION_COUNT = 2;
const unsigned long FISH_FEEDER_FULL_ROTATION_MS = 1000;

// UART from optional Arduino Nano. Protect ESP32 RX from 5V Nano TX with a level shifter/divider.
const bool USE_UNO_UART = true;
const int UNO_UART_RX_PIN = 16;
const int UNO_UART_TX_PIN = 17;
const uint32_t UNO_UART_BAUD = 115200;
const unsigned long UNO_DATA_TIMEOUT_MS = 15000;

// Sensor and sampling settings
const unsigned long SENSOR_INTERVAL_MS = 1000;
const unsigned long STATUS_INTERVAL_MS = 2000;
const unsigned long CMD_POLL_INTERVAL_MS = 700;
const unsigned long HISTORY_INTERVAL_MS = 300000;
const unsigned long MQTT_RECONNECT_INTERVAL_MS = 5000;
const bool CONSOLE_OUTPUT_ENABLED = true;
const char *NTP_SERVER_1 = "pool.ntp.org";
const char *NTP_SERVER_2 = "time.google.com";
const char *NTP_SERVER_3 = "time.nist.gov";

const float PH_MIN_VALID = 0.0f;
const float PH_MAX_VALID = 14.0f;
const float TDS_MIN_VALID = 0.0f;
const float TDS_MAX_VALID = 3000.0f;

const int SENSOR_FAILURE_DEGRADED_THRESHOLD = 3;

float ph = 6.8f;
float waterLevelPct = 82.0f;
float tdsPpm = 900.0f;
float phUpTankLevelPct = 100.0f;
float phDownTankLevelPct = 100.0f;
float nutrientTankLevelPct = 100.0f;

bool lastReadOk = true;
uint32_t sampleCount = 0;
String sensorStatus = "booting";
bool relayPhUpState = false;
bool relayPhDownState = false;
bool relayNutrientState = false;
bool relayFishToFilterState = false;
bool relayFishFeederState = false;

String wsUrl = "";
String mqttTopicLive = "";
String mqttStatusTopic = "";
String mqttCommandTopic = "";
String mqttCommandAckTopic = "";
String mqttNanoTelemetryTopic = "";
String backendWsPath = "";

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

WebSocketsServer wsServer(WS_PORT);
WebSocketsClient backendWsClient;
#if MQTT_USE_TLS
WiFiClientSecure mqttSecureClient;
PubSubClient mqttClient(mqttSecureClient);
#else
WiFiClient mqttPlainClient;
PubSubClient mqttClient(mqttPlainClient);
#endif
HardwareSerial unoSerial(2);
Servo fishFeederServo;

unsigned long lastSensorMs = 0;
unsigned long lastStatusMs = 0;
unsigned long lastCmdPollMs = 0;
unsigned long lastHistoryMs = 0;
unsigned long lastMqttReconnectAttemptMs = 0;
bool feederPulseActive = false;
unsigned long feederPulseEndMs = 0;
String feederPulseCommandPath = "";
unsigned long feederPulseDurationMs = 0;
bool lastNanoOnlineState = false;
bool backendWsConnected = false;

struct UnoTelemetry {
  bool hasPh = false;
  bool hasTds = false;
  bool hasFishLevel = false;
  bool hasPhUpLevel = false;
  bool hasPhDownLevel = false;
  bool hasNutrientLevel = false;
  float phValue = NAN;
  float tdsValue = NAN;
  float fishLevelPct = NAN;
  float phUpLevelPct = NAN;
  float phDownLevelPct = NAN;
  float nutrientLevelPct = NAN;
  unsigned long lastUpdateMs = 0;
  String lineBuffer = "";
};

struct SensorChannel {
  const char *name;
  float value;
  float lastGoodValue;
  uint8_t consecutiveFailures;
  bool lastCycleOk;
};

UnoTelemetry unoTelemetry;
SensorChannel phChannel = {"ph", 6.8f, 6.8f, 0, true};
SensorChannel tdsChannel = {"tds", 900.0f, 900.0f, 0, true};
SensorChannel fishLevelChannel = {"fishTankLevel", 82.0f, 82.0f, 0, true};
SensorChannel phUpLevelChannel = {"phUpTankLevel", 100.0f, 100.0f, 0, true};
SensorChannel phDownLevelChannel = {"phDownTankLevel", 100.0f, 100.0f, 0, true};
SensorChannel nutrientLevelChannel = {"nutrientTankLevel", 100.0f, 100.0f, 0, true};

String buildSnapshotJson();

String deviceDocPath() {
  return String("devices/") + deviceId;
}

String commandsColPath() {
  return String("devices/") + deviceId + "/commands";
}

String logsColPath() {
  return String("devices/") + deviceId + "/logs";
}

String readingsColPath() {
  return String("devices/") + deviceId + "/readings";
}

bool hasValidUtcTime() {
  return time(nullptr) >= 1700000000;
}

String firestoreTimestampNow() {
  time_t now = time(nullptr);
  if (now < 1700000000) return "";

  struct tm utcTm;
  gmtime_r(&now, &utcTm);

  char ts[25];
  strftime(ts, sizeof(ts), "%Y-%m-%dT%H:%M:%SZ", &utcTm);
  return String(ts);
}

bool setTimestampField(FirebaseJson &content, const String &path) {
  String ts = firestoreTimestampNow();
  if (ts.length() == 0) {
    Serial.println("[Firestore] skip write: UTC time not synchronized yet");
    return false;
  }
  content.set(path.c_str(), ts);
  return true;
}

bool waitForValidUtcTime(unsigned long timeoutMs) {
  unsigned long start = millis();
  while (!hasValidUtcTime() && millis() - start < timeoutMs) {
    delay(200);
    Serial.print(".");
  }
  return hasValidUtcTime();
}

bool syncUtcTimeViaNtp(unsigned long timeoutMs) {
  configTime(0, 0, NTP_SERVER_1, NTP_SERVER_2, NTP_SERVER_3);
  return waitForValidUtcTime(timeoutMs);
}

void printFirestoreResult(const String &operation, bool ok) {
  if (ok) {
    Serial.println("[Firestore] " + operation + " OK");
    return;
  }
  Serial.println("[Firestore] " + operation + " FAIL: " + fbdo.errorReason());
}

void printConsoleLine(const String &label, const String &value) {
  if (!CONSOLE_OUTPUT_ENABLED) return;
  Serial.print("[Console] ");
  Serial.print(label);
  Serial.print(": ");
  Serial.println(value);
}

void printConsoleJson(const String &label, const String &payload) {
  printConsoleLine(label, payload);
}

const char *wifiStatusLabel(wl_status_t status) {
  switch (status) {
    case WL_IDLE_STATUS:
      return "idle";
    case WL_NO_SSID_AVAIL:
      return "ssid_not_available";
    case WL_SCAN_COMPLETED:
      return "scan_completed";
    case WL_CONNECTED:
      return "connected";
    case WL_CONNECT_FAILED:
      return "connect_failed";
    case WL_CONNECTION_LOST:
      return "connection_lost";
    case WL_DISCONNECTED:
      return "disconnected";
    default:
      return "unknown";
  }
}

void printWifiScan() {
  Serial.println("[WiFi] scanning nearby networks");
  int networkCount = WiFi.scanNetworks();
  if (networkCount < 0) {
    Serial.printf("[WiFi] scan failed: %d\n", networkCount);
    return;
  }

  Serial.printf("[WiFi] scan found %d network(s)\n", networkCount);
  for (int i = 0; i < networkCount; i++) {
    Serial.printf(
      "[WiFi] #%d SSID='%s' RSSI=%d dBm channel=%d encryption=%d%s\n",
      i + 1,
      WiFi.SSID(i).c_str(),
      WiFi.RSSI(i),
      WiFi.channel(i),
      WiFi.encryptionType(i),
      WiFi.SSID(i) == WIFI_SSID ? " <-- target" : ""
    );
  }
}

bool connectWifiCandidate(const char *ssid, const char *password, unsigned long timeoutMs) {
  Serial.printf("[WiFi] connecting to SSID='%s'\n", ssid);
  WiFi.begin(ssid, password);

  unsigned long startMs = millis();
  wl_status_t lastStatus = WL_IDLE_STATUS;
  unsigned long lastStatusPrintMs = 0;
  while (millis() - startMs < timeoutMs) {
    wl_status_t status = WiFi.status();
    if (status != lastStatus) {
      Serial.printf("[WiFi] status=%s (%d)\n", wifiStatusLabel(status), status);
      lastStatus = status;
      lastStatusPrintMs = millis();
    } else if (millis() - lastStatusPrintMs >= 3000) {
      Serial.printf("[WiFi] still %s (%d)\n", wifiStatusLabel(status), status);
      lastStatusPrintMs = millis();
    }
    if (status == WL_CONNECTED) {
      Serial.println("[WiFi] connected");
      Serial.println("[WiFi] ip=" + WiFi.localIP().toString());
      Serial.printf("[WiFi] rssi=%d dBm\n", WiFi.RSSI());
      return true;
    }
    delay(500);
    Serial.print(".");
  }

  Serial.println();
  Serial.printf("[WiFi] failed to connect to SSID='%s', final status=%s (%d)\n",
                ssid,
                wifiStatusLabel(WiFi.status()),
                WiFi.status());
  WiFi.disconnect(false);
  delay(1000);
  return false;
}

void connectWifi() {
  WiFi.persistent(false);
  WiFi.disconnect(true, true);
  delay(1000);
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  delay(500);

  printWifiScan();

  while (WiFi.status() != WL_CONNECTED) {
    if (connectWifiCandidate(WIFI_SSID, WIFI_PASS, 20000)) return;
    if (String(WIFI_SSID_FALLBACK) != String(WIFI_SSID) &&
        connectWifiCandidate(WIFI_SSID_FALLBACK, WIFI_PASS, 20000)) {
      return;
    }
    Serial.println("[WiFi] retrying after failed connection attempts");
    delay(3000);
  }
}

float clampFloat(float value, float minValue, float maxValue) {
  if (value < minValue) return minValue;
  if (value > maxValue) return maxValue;
  return value;
}

float round2(float value) {
  return roundf(value * 100.0f) / 100.0f;
}

bool parseStrictFloat(const String &raw, float &outValue) {
  if (raw.length() == 0) return false;

  char buffer[32];
  size_t copyLen = raw.length();
  if (copyLen >= sizeof(buffer)) copyLen = sizeof(buffer) - 1;
  raw.substring(0, copyLen).toCharArray(buffer, copyLen + 1);

  char *endPtr = nullptr;
  float parsed = strtof(buffer, &endPtr);
  if (endPtr == buffer || *endPtr != '\0' || !isfinite(parsed)) {
    return false;
  }

  outValue = parsed;
  return true;
}

void setRelayOutputPin(int pin, bool state) {
  int level = state ? (RELAY_ACTIVE_HIGH ? HIGH : LOW) : (RELAY_ACTIVE_HIGH ? LOW : HIGH);
  digitalWrite(pin, level);
  Serial.printf(
    "[Relay] pin=%d state=%s gpio_level=%s polarity=%s\n",
    pin,
    state ? "ON" : "OFF",
    level == HIGH ? "HIGH" : "LOW",
    RELAY_ACTIVE_HIGH ? "active-high" : "active-low"
  );
}

void setFishFeederServoState(bool active) {
  if (!fishFeederServo.attached()) return;

  int angle = active ? FISH_FEEDER_SERVO_ACTIVE_DEG : FISH_FEEDER_SERVO_IDLE_DEG;
  angle = (int)clampFloat((float)angle, 0.0f, 180.0f);
  fishFeederServo.write(angle);
}

bool *relayStatePtr(const String &type) {
  if (type == "ph_up") return &relayPhUpState;
  if (type == "ph_down") return &relayPhDownState;
  if (type == "nutrient") return &relayNutrientState;
  if (type == "fish_to_filter") return &relayFishToFilterState;
  if (type == "fish_feeder") return &relayFishFeederState;
  return nullptr;
}

int relayPinForType(const String &type) {
  if (type == "ph_up") return RELAY_PH_UP_PIN;
  if (type == "ph_down") return RELAY_PH_DOWN_PIN;
  if (type == "nutrient") return RELAY_NUTRIENT_PIN;
  if (type == "fish_to_filter") return RELAY_FISH_TO_FILTER_PIN;
  return -1;
}

bool isLatchedRelayType(const String &type) {
  return type == "ph_up" ||
         type == "ph_down" ||
         type == "nutrient" ||
         type == "fish_to_filter";
}

String relayStateSummary() {
  return String("ph_up=") + (relayPhUpState ? "on" : "off") +
         ",ph_down=" + (relayPhDownState ? "on" : "off") +
         ",nutrient=" + (relayNutrientState ? "on" : "off") +
         ",fish_to_filter=" + (relayFishToFilterState ? "on" : "off") +
         ",fish_feeder=" + (relayFishFeederState ? "on" : "off");
}

void applyRelayState(const String &type, bool state) {
  bool *statePtr = relayStatePtr(type);
  if (statePtr == nullptr) return;

  if (type == "fish_feeder") {
    *statePtr = state;
    setFishFeederServoState(state);
    return;
  }

  int pin = relayPinForType(type);
  if (pin < 0) return;

  *statePtr = state;
  setRelayOutputPin(pin, state);
}

String epochMillisString() {
  time_t now = time(nullptr);
  if (now < 1700000000) {
    return String((unsigned long)millis());
  }
  unsigned long long epochMs = ((unsigned long long)now) * 1000ULL;
  return String(epochMs);
}

bool updateChannel(SensorChannel &channel, float candidateValue, float minValue, float maxValue) {
  bool valid = isfinite(candidateValue) && candidateValue >= minValue && candidateValue <= maxValue;
  channel.lastCycleOk = valid;

  if (valid) {
    channel.value = round2(candidateValue);
    channel.lastGoodValue = channel.value;
    channel.consecutiveFailures = 0;
    return true;
  }

  channel.consecutiveFailures++;
  channel.value = channel.lastGoodValue;
  return false;
}

String channelStateLabel(const SensorChannel &channel) {
  if (channel.consecutiveFailures >= SENSOR_FAILURE_DEGRADED_THRESHOLD) {
    return "degraded";
  }
  return channel.lastCycleOk ? "ok" : "stale";
}

unsigned long nanoAgeMs() {
  if (unoTelemetry.lastUpdateMs == 0) return ULONG_MAX;
  return millis() - unoTelemetry.lastUpdateMs;
}

bool isNanoOnline() {
  return USE_UNO_UART &&
         unoTelemetry.lastUpdateMs > 0 &&
         nanoAgeMs() <= UNO_DATA_TIMEOUT_MS;
}

String nanoMissingFields() {
  String missing = "";
  if (!unoTelemetry.hasPh) missing += "PH,";
  if (!unoTelemetry.hasTds) missing += "TDS,";
  if (!unoTelemetry.hasPhUpLevel) missing += "PHUP,";
  if (!unoTelemetry.hasPhDownLevel) missing += "PHDOWN,";
  if (!unoTelemetry.hasNutrientLevel) missing += "NUTRIENT,";
  if (missing.endsWith(",")) missing.remove(missing.length() - 1);
  return missing;
}

String nanoErrorMessage() {
  if (!USE_UNO_UART) return "Nano UART disabled in firmware";
  if (!isNanoOnline()) {
    return "No valid Arduino Nano UART data for 15s. Check Nano power, common GND, Nano TX(D1) to ESP32 RX16 through level shifting, and 115200 baud.";
  }
  String missing = nanoMissingFields();
  if (missing.length() > 0) {
    return "Arduino Nano is connected, but these readings are missing: " + missing;
  }
  return "";
}

void refreshSensorStatusSummary() {
  bool nanoOnline = isNanoOnline();
  lastReadOk =
    nanoOnline &&
    phChannel.lastCycleOk &&
    tdsChannel.lastCycleOk &&
    phUpLevelChannel.lastCycleOk &&
    phDownLevelChannel.lastCycleOk &&
    nutrientLevelChannel.lastCycleOk;

  sensorStatus =
    String("nano=") + (nanoOnline ? "online" : "offline") +
    ",ph=" + channelStateLabel(phChannel) +
    ",tds=" + channelStateLabel(tdsChannel) +
    ",phUp=" + channelStateLabel(phUpLevelChannel) +
    ",phDown=" + channelStateLabel(phDownLevelChannel) +
    ",nutrient=" + channelStateLabel(nutrientLevelChannel);
}

void parseUnoLine(const String &line) {
  int sep = line.indexOf(':');
  if (sep <= 0) return;

  String key = line.substring(0, sep);
  String rawValue = line.substring(sep + 1);
  key.trim();
  rawValue.trim();
  key.toUpperCase();

  if (rawValue.length() == 0) return;

  float value = NAN;
  if (!parseStrictFloat(rawValue, value)) return;
  printConsoleLine("uno", key + "=" + String(value, 2));

  if (key == "PH") {
    unoTelemetry.phValue = value;
    unoTelemetry.hasPh = true;
    unoTelemetry.lastUpdateMs = millis();
  } else if (key == "TDS") {
    unoTelemetry.tdsValue = value;
    unoTelemetry.hasTds = true;
    unoTelemetry.lastUpdateMs = millis();
  } else if (key == "FISH") {
    unoTelemetry.fishLevelPct = value;
    unoTelemetry.hasFishLevel = true;
    unoTelemetry.lastUpdateMs = millis();
  } else if (key == "PHUP") {
    unoTelemetry.phUpLevelPct = value;
    unoTelemetry.hasPhUpLevel = true;
    unoTelemetry.lastUpdateMs = millis();
  } else if (key == "PHDOWN") {
    unoTelemetry.phDownLevelPct = value;
    unoTelemetry.hasPhDownLevel = true;
    unoTelemetry.lastUpdateMs = millis();
  } else if (key == "NUTRIENT") {
    unoTelemetry.nutrientLevelPct = value;
    unoTelemetry.hasNutrientLevel = true;
    unoTelemetry.lastUpdateMs = millis();
  }
}

void applyNanoReading(const String &key, float value) {
  if (key == "PH") {
    unoTelemetry.phValue = value;
    unoTelemetry.hasPh = true;
    unoTelemetry.lastUpdateMs = millis();
  } else if (key == "TDS") {
    unoTelemetry.tdsValue = value;
    unoTelemetry.hasTds = true;
    unoTelemetry.lastUpdateMs = millis();
  } else if (key == "PHUP") {
    unoTelemetry.phUpLevelPct = value;
    unoTelemetry.hasPhUpLevel = true;
    unoTelemetry.lastUpdateMs = millis();
  } else if (key == "PHDOWN") {
    unoTelemetry.phDownLevelPct = value;
    unoTelemetry.hasPhDownLevel = true;
    unoTelemetry.lastUpdateMs = millis();
  } else if (key == "NUTRIENT") {
    unoTelemetry.nutrientLevelPct = value;
    unoTelemetry.hasNutrientLevel = true;
    unoTelemetry.lastUpdateMs = millis();
  }
}

void applyNanoJsonReading(FirebaseJson &js, const char *path, const String &key) {
  FirebaseJsonData data;
  js.get(data, path);
  if (!data.success) return;

  float value = data.stringValue.length() > 0
    ? data.stringValue.toFloat()
    : (float)data.doubleValue;
  if (!isfinite(value)) return;

  applyNanoReading(key, value);
}

void onNanoMqttTelemetry(const String &payloadStr) {
  printConsoleJson("mqtt_nano_telemetry_received", payloadStr);
  FirebaseJson js;
  js.setJsonData(payloadStr);
  applyNanoJsonReading(js, "ph", "PH");
  applyNanoJsonReading(js, "tdsPpm", "TDS");
  applyNanoJsonReading(js, "phUpTankLevelPct", "PHUP");
  applyNanoJsonReading(js, "phDownTankLevelPct", "PHDOWN");
  applyNanoJsonReading(js, "nutrientTankLevelPct", "NUTRIENT");
}

void pollUnoSerial() {
  if (!USE_UNO_UART) return;

  while (unoSerial.available()) {
    char ch = (char)unoSerial.read();
    if (ch == '\r') continue;
    if (ch == '\n') {
      if (unoTelemetry.lineBuffer.length() > 0) {
        if (CONSOLE_OUTPUT_ENABLED) {
          Serial.println("[UNO] " + unoTelemetry.lineBuffer);
        }
        parseUnoLine(unoTelemetry.lineBuffer);
        unoTelemetry.lineBuffer = "";
      }
      continue;
    }
    if (unoTelemetry.lineBuffer.length() < 64) {
      unoTelemetry.lineBuffer += ch;
    } else {
      unoTelemetry.lineBuffer = "";
    }
  }

  if (millis() - unoTelemetry.lastUpdateMs > UNO_DATA_TIMEOUT_MS) {
    unoTelemetry.hasPh = false;
    unoTelemetry.hasTds = false;
    unoTelemetry.hasFishLevel = false;
    unoTelemetry.hasPhUpLevel = false;
    unoTelemetry.hasPhDownLevel = false;
    unoTelemetry.hasNutrientLevel = false;
  }

  bool nanoOnline = isNanoOnline();
  if (nanoOnline != lastNanoOnlineState) {
    lastNanoOnlineState = nanoOnline;
    Serial.println(String("[UNO] status ") + (nanoOnline ? "online" : "offline") + " - " + nanoErrorMessage());
  }
}

float resolvePhReading() {
  if (USE_UNO_UART && unoTelemetry.hasPh) return unoTelemetry.phValue;
  return NAN;
}

float resolveTdsReading() {
  if (USE_UNO_UART && unoTelemetry.hasTds) return unoTelemetry.tdsValue;
  return NAN;
}

void acquireSensors() {
  pollUnoSerial();

  float phCandidate = resolvePhReading();
  float tdsCandidate = resolveTdsReading();
  float phUpCandidate = unoTelemetry.hasPhUpLevel ? unoTelemetry.phUpLevelPct : NAN;
  float phDownCandidate = unoTelemetry.hasPhDownLevel ? unoTelemetry.phDownLevelPct : NAN;
  float nutrientCandidate = unoTelemetry.hasNutrientLevel ? unoTelemetry.nutrientLevelPct : NAN;

  updateChannel(phChannel, phCandidate, PH_MIN_VALID, PH_MAX_VALID);
  updateChannel(tdsChannel, tdsCandidate, TDS_MIN_VALID, TDS_MAX_VALID);
  updateChannel(phUpLevelChannel, phUpCandidate, 0.0f, 100.0f);
  updateChannel(phDownLevelChannel, phDownCandidate, 0.0f, 100.0f);
  updateChannel(nutrientLevelChannel, nutrientCandidate, 0.0f, 100.0f);

  ph = phChannel.value;
  tdsPpm = tdsChannel.value;
  // No fish tank level sensor is installed in this build. Keep the last
  // configured value for backward-compatible app fields, but do not mark the
  // Nano unhealthy when no FISH line is received.
  waterLevelPct = fishLevelChannel.value;
  phUpTankLevelPct = phUpLevelChannel.value;
  phDownTankLevelPct = phDownLevelChannel.value;
  nutrientTankLevelPct = nutrientLevelChannel.value;
  sampleCount++;

  refreshSensorStatusSummary();
  printConsoleJson("sensor_snapshot", buildSnapshotJson());
}

String buildSnapshotJson() {
  FirebaseJson js;
  js.set("deviceId", deviceId);
  js.set("espStatus", "online");
  js.set("tsEpochMs", epochMillisString());
  js.set("ph", ph);
  js.set("waterLevelPct", waterLevelPct);
  js.set("tdsPpm", tdsPpm);
  js.set("phUpTankLevelPct", phUpTankLevelPct);
  js.set("phDownTankLevelPct", phDownTankLevelPct);
  js.set("nutrientTankLevelPct", nutrientTankLevelPct);
  js.set("sensorStatus", sensorStatus);
  js.set("lastReadOk", lastReadOk);
  js.set("nanoOnline", isNanoOnline());
  js.set("nanoLastSeenMs", unoTelemetry.lastUpdateMs == 0 ? 0 : (int)unoTelemetry.lastUpdateMs);
  js.set("nanoAgeMs", nanoAgeMs() == ULONG_MAX ? -1 : (int)nanoAgeMs());
  js.set("nanoError", nanoErrorMessage());
  js.set("sampleCount", (int)sampleCount);
  js.set("heartbeatSeq", (int)sampleCount);
  js.set("relayStates/phUp", relayPhUpState);
  js.set("relayStates/phDown", relayPhDownState);
  js.set("relayStates/nutrient", relayNutrientState);
  js.set("relayStates/fishToFilter", relayFishToFilterState);
  js.set("relayStates/fishFeeder", relayFishFeederState);
  js.set("relaySummary", relayStateSummary());
  js.set("rssi", WiFi.RSSI());
  js.set("mqttTopicLive", mqttTopicLive);
  js.set("mqttStatusTopic", mqttStatusTopic);
  js.set("mqttCommandTopic", mqttCommandTopic);
  js.set("mqttCommandAckTopic", mqttCommandAckTopic);

  String out;
  js.toString(out, false);
  return out;
}

String buildStatusJson(const String &status) {
  FirebaseJson js;
  js.set("deviceId", deviceId);
  js.set("status", status);
  js.set("tsEpochMs", epochMillisString());

  String out;
  js.toString(out, false);
  return out;
}

String commandIdFromDocPath(const String &docPath) {
  int slash = docPath.lastIndexOf('/');
  if (slash < 0 || slash >= (int)docPath.length() - 1) return docPath;
  return docPath.substring(slash + 1);
}

void publishMqttCommandAck(const String &commandId, const String &status, const String &message) {
  if (!mqttClient.connected()) return;
  if (mqttCommandAckTopic.length() == 0 || commandId.length() == 0) return;

  FirebaseJson js;
  js.set("deviceId", deviceId);
  js.set("id", commandId);
  js.set("commandId", commandId);
  js.set("status", status);
  js.set("message", message);
  js.set("tsEpochMs", epochMillisString());
  js.set("relayStates/phUp", relayPhUpState);
  js.set("relayStates/phDown", relayPhDownState);
  js.set("relayStates/nutrient", relayNutrientState);
  js.set("relayStates/fishFeeder", relayFishFeederState);
  js.set("relaySummary", relayStateSummary());

  String out;
  js.toString(out, false);
  mqttClient.publish(mqttCommandAckTopic.c_str(), out.c_str(), false);
  printConsoleJson("mqtt_command_ack", out);
}

void publishBackendWsCommandAck(const String &commandId, const String &status, const String &message) {
  if (!backendWsClient.isConnected()) return;
  if (commandId.length() == 0) return;

  FirebaseJson js;
  js.set("type", "command_ack");
  js.set("deviceId", deviceId);
  js.set("id", commandId);
  js.set("commandId", commandId);
  js.set("status", status);
  js.set("message", message);
  js.set("tsEpochMs", epochMillisString());
  js.set("relayStates/phUp", relayPhUpState);
  js.set("relayStates/phDown", relayPhDownState);
  js.set("relayStates/nutrient", relayNutrientState);
  js.set("relayStates/fishFeeder", relayFishFeederState);
  js.set("relaySummary", relayStateSummary());

  String out;
  js.toString(out, false);
  backendWsClient.sendTXT(out);
  printConsoleJson("backend_ws_command_ack", out);
}

bool mqttConnectWithWill(const String &clientId, const String &willPayload) {
  if (strlen(MQTT_USERNAME) > 0 || strlen(MQTT_PASSWORD) > 0) {
    return mqttClient.connect(
      clientId.c_str(),
      MQTT_USERNAME,
      MQTT_PASSWORD,
      mqttStatusTopic.c_str(),
      1,
      true,
      willPayload.c_str()
    );
  }

  return mqttClient.connect(
    clientId.c_str(),
    mqttStatusTopic.c_str(),
    1,
    true,
    willPayload.c_str()
  );
}

bool connectMqtt() {
  if (mqttClient.connected()) return true;

  if (mqttTopicLive.length() == 0 || mqttStatusTopic.length() == 0) {
    return false;
  }

  String clientId = String("esp32-aqua-") + deviceId + "-" + String(esp_random(), HEX);
  String willPayload = buildStatusJson("offline");
  bool ok = mqttConnectWithWill(clientId, willPayload);

  if (!ok) {
    Serial.printf("[MQTT] connect failed (state=%d)\n", mqttClient.state());
    return false;
  }

  if (mqttCommandTopic.length() > 0) {
    bool subscribed = mqttClient.subscribe(mqttCommandTopic.c_str(), 1);
    Serial.printf("[MQTT] command subscribe %s: %s\n",
                  mqttCommandTopic.c_str(),
                  subscribed ? "ok" : "failed");
  }

  if (mqttNanoTelemetryTopic.length() > 0) {
    bool subscribed = mqttClient.subscribe(mqttNanoTelemetryTopic.c_str(), 1);
    Serial.printf("[MQTT] nano telemetry subscribe %s: %s\n",
                  mqttNanoTelemetryTopic.c_str(),
                  subscribed ? "ok" : "failed");
  }

  String onlinePayload = buildStatusJson("online");
  mqttClient.publish(mqttStatusTopic.c_str(), onlinePayload.c_str(), true);
  printConsoleJson("mqtt_status_publish", onlinePayload);
  Serial.println("[MQTT] connected");
  return true;
}

void ensureMqttConnected() {
  if (mqttClient.connected()) return;
  if (millis() - lastMqttReconnectAttemptMs < MQTT_RECONNECT_INTERVAL_MS) return;

  lastMqttReconnectAttemptMs = millis();
  connectMqtt();
}

void publishMqttSnapshot() {
  if (!mqttClient.connected()) return;
  if (mqttTopicLive.length() == 0) return;

  String payload = buildSnapshotJson();
  mqttClient.publish(mqttTopicLive.c_str(), payload.c_str(), false);
  printConsoleJson("mqtt_live_publish", payload);
}

void broadcastSnapshot() {
  String payload = buildSnapshotJson();
  wsServer.broadcastTXT(payload);
  printConsoleJson("websocket_broadcast", payload);
}

void logEvent(const String &level, const String &event, const String &detail) {
  printConsoleLine("event", level + "/" + event + " - " + detail);

  // Skip the blocking Firestore event-log write while the local backend link
  // is up so command handling and telemetry stay responsive.
  if (mqttClient.connected()) return;

  FirebaseJson content;
  if (!setTimestampField(content, "fields/ts/timestampValue")) return;
  content.set("fields/level/stringValue", level);
  content.set("fields/event/stringValue", event);
  content.set("fields/detail/stringValue", detail);
  content.set("fields/by/stringValue", "esp32_aquaponics");

  bool ok = Firebase.Firestore.createDocument(
    &fbdo,
    FIREBASE_PROJECT_ID,
    "",
    logsColPath().c_str(),
    content.raw()
  );
  printFirestoreResult("logEvent", ok);
}

void setDeviceFields(FirebaseJson &content) {
  content.set("fields/name/stringValue", "Aquaponics ESP32");
  content.set("fields/online/booleanValue", true);
  content.set("fields/espStatus/stringValue", "online");
  content.set("fields/rssi/integerValue", String(WiFi.RSSI()));
  content.set("fields/ph/doubleValue", ph);
  content.set("fields/waterLevelPct/doubleValue", waterLevelPct);
  content.set("fields/tdsPpm/doubleValue", tdsPpm);
  content.set("fields/phUpTankLevelPct/doubleValue", phUpTankLevelPct);
  content.set("fields/phDownTankLevelPct/doubleValue", phDownTankLevelPct);
  content.set("fields/nutrientTankLevelPct/doubleValue", nutrientTankLevelPct);
  content.set("fields/sensorStatus/stringValue", sensorStatus);
  content.set("fields/lastReadOk/booleanValue", lastReadOk);
  content.set("fields/nanoOnline/booleanValue", isNanoOnline());
  content.set("fields/nanoLastSeenMs/integerValue", String(unoTelemetry.lastUpdateMs));
  content.set("fields/nanoAgeMs/integerValue", String(nanoAgeMs() == ULONG_MAX ? -1 : (int)nanoAgeMs()));
  content.set("fields/nanoError/stringValue", nanoErrorMessage());
  content.set("fields/sampleCount/integerValue", String(sampleCount));
  content.set("fields/heartbeatSeq/integerValue", String(sampleCount));
  content.set("fields/relayStates/mapValue/fields/phUp/booleanValue", relayPhUpState);
  content.set("fields/relayStates/mapValue/fields/phDown/booleanValue", relayPhDownState);
  content.set("fields/relayStates/mapValue/fields/nutrient/booleanValue", relayNutrientState);
  content.set(
    "fields/relayStates/mapValue/fields/fishToFilter/booleanValue",
    relayFishToFilterState
  );
  content.set(
    "fields/relayStates/mapValue/fields/fishFeeder/booleanValue",
    relayFishFeederState
  );
  content.set("fields/relaySummary/stringValue", relayStateSummary());
  content.set("fields/wsUrl/stringValue", wsUrl);
  content.set("fields/realtimeTransport/stringValue", "mqtt");
  content.set("fields/mqttTopicLive/stringValue", mqttTopicLive);
  content.set("fields/mqttStatusTopic/stringValue", mqttStatusTopic);
  content.set("fields/mqttCommandTopic/stringValue", mqttCommandTopic);
  content.set("fields/mqttCommandAckTopic/stringValue", mqttCommandAckTopic);
  content.set("fields/mqttEnabled/booleanValue", true);
  content.set("fields/simulator/booleanValue", false);
}

void updateDeviceStatus(bool online) {
  printConsoleLine("device_status", String(online ? "online" : "offline") + " " + buildSnapshotJson());

  // The local backend derives device online/offline + relay state from MQTT
  // (telemetry, status topic LWT, command snapshots) and mirrors it to
  // Firestore, so skip this blocking Firestore write while MQTT is connected.
  if (mqttClient.connected()) return;

  FirebaseJson content;
  setDeviceFields(content);
  content.set("fields/online/booleanValue", online);
  content.set("fields/espStatus/stringValue", online ? "online" : "offline");
  if (!setTimestampField(content, "fields/lastSeen/timestampValue")) return;

  bool patchOk = Firebase.Firestore.patchDocument(
    &fbdo,
    FIREBASE_PROJECT_ID,
    "",
    deviceDocPath().c_str(),
    content.raw(),
    "name,online,espStatus,lastSeen,rssi,ph,waterLevelPct,tdsPpm,phUpTankLevelPct,phDownTankLevelPct,nutrientTankLevelPct,sensorStatus,lastReadOk,nanoOnline,nanoLastSeenMs,nanoAgeMs,nanoError,sampleCount,heartbeatSeq,relayStates,relaySummary,wsUrl,realtimeTransport,mqttTopicLive,mqttStatusTopic,mqttCommandTopic,mqttCommandAckTopic,mqttEnabled,simulator"
  );
  printFirestoreResult("updateDeviceStatus", patchOk);
}

void writeReadingSnapshot() {
  printConsoleJson("history_snapshot", buildSnapshotJson());

  FirebaseJson content;
  if (!setTimestampField(content, "fields/ts/timestampValue")) return;
  content.set("fields/ph/doubleValue", ph);
  content.set("fields/waterLevelPct/doubleValue", waterLevelPct);
  content.set("fields/tdsPpm/doubleValue", tdsPpm);
  content.set("fields/phUpTankLevelPct/doubleValue", phUpTankLevelPct);
  content.set("fields/phDownTankLevelPct/doubleValue", phDownTankLevelPct);
  content.set("fields/nutrientTankLevelPct/doubleValue", nutrientTankLevelPct);
  content.set("fields/sensorStatus/stringValue", sensorStatus);
  content.set("fields/lastReadOk/booleanValue", lastReadOk);
  content.set("fields/nanoOnline/booleanValue", isNanoOnline());
  content.set("fields/nanoLastSeenMs/integerValue", String(unoTelemetry.lastUpdateMs));
  content.set("fields/nanoAgeMs/integerValue", String(nanoAgeMs() == ULONG_MAX ? -1 : (int)nanoAgeMs()));
  content.set("fields/nanoError/stringValue", nanoErrorMessage());
  content.set("fields/sampleCount/integerValue", String(sampleCount));
  content.set("fields/relayStates/mapValue/fields/phUp/booleanValue", relayPhUpState);
  content.set("fields/relayStates/mapValue/fields/phDown/booleanValue", relayPhDownState);
  content.set("fields/relayStates/mapValue/fields/nutrient/booleanValue", relayNutrientState);
  content.set(
    "fields/relayStates/mapValue/fields/fishToFilter/booleanValue",
    relayFishToFilterState
  );
  content.set(
    "fields/relayStates/mapValue/fields/fishFeeder/booleanValue",
    relayFishFeederState
  );
  content.set("fields/relaySummary/stringValue", relayStateSummary());
  content.set("fields/rssi/integerValue", String(WiFi.RSSI()));

  bool ok = Firebase.Firestore.createDocument(
    &fbdo,
    FIREBASE_PROJECT_ID,
    "",
    readingsColPath().c_str(),
    content.raw()
  );
  printFirestoreResult("writeReadingSnapshot", ok);
}

bool ensureDeviceDocument() {
  FirebaseJson content;
  setDeviceFields(content);
  content.set("fields/online/booleanValue", true);
  if (!setTimestampField(content, "fields/lastSeen/timestampValue")) return false;
  if (!setTimestampField(content, "fields/createdAt/timestampValue")) return false;

  bool created = Firebase.Firestore.createDocument(
    &fbdo,
    FIREBASE_PROJECT_ID,
    "",
    "devices",
    deviceId,
    content.raw(),
    ""
  );
  if (created) {
    printFirestoreResult("ensureDeviceDocument create", true);
    return true;
  }

  String reason = fbdo.errorReason();
  if (reason.indexOf("ALREADY_EXISTS") >= 0 ||
      reason.indexOf("already exists") >= 0 ||
      reason.indexOf("409") >= 0) {
    Serial.println("[Firestore] ensureDeviceDocument: existing document found");
    return true;
  }

  printFirestoreResult("ensureDeviceDocument create", false);
  return false;
}

bool patchCommandStatus(
  const String &docPath,
  const String &status,
  const String &message,
  bool includeExecutedAt
) {
  // Acknowledge over MQTT first (fast, non-blocking). When the local backend
  // link is up it records command status from this ack, so skip the blocking
  // Firestore write that would otherwise stall the loop after every command.
  String commandId = commandIdFromDocPath(docPath);
  publishBackendWsCommandAck(commandId, status, message);
  publishMqttCommandAck(commandId, status, message);
  if (backendWsClient.isConnected() || mqttClient.connected()) return true;

  FirebaseJson patch;
  patch.set("fields/status/stringValue", status);
  patch.set("fields/message/stringValue", message);
  String updateMask = "status,message";
  if (includeExecutedAt && setTimestampField(patch, "fields/executedAt/timestampValue")) {
    updateMask = "status,message,executedAt";
  }

  bool patchOk = Firebase.Firestore.patchDocument(
    &fbdo,
    FIREBASE_PROJECT_ID,
    "",
    docPath.c_str(),
    patch.raw(),
    updateMask.c_str()
  );
  printFirestoreResult("patchCommandStatus", patchOk);
  return patchOk;
}

void finalizeFeederPulse() {
  if (!feederPulseActive) return;

  feederPulseActive = false;
  feederPulseEndMs = 0;
  applyRelayState("fish_feeder", false);
  printConsoleLine("feeder_pulse", "completed 2 full rotations");
  logEvent("info", "feeder_servo_completed", "fish_feeder servo completed 2 full rotations");
  updateDeviceStatus(true);
  broadcastSnapshot();
  publishMqttSnapshot();

  if (feederPulseCommandPath.length() > 0) {
    patchCommandStatus(
      feederPulseCommandPath,
      "executed",
      String("fish_feeder servo completed ") + String(FISH_FEEDER_ROTATION_COUNT) + " full rotations",
      true
    );
  }

  feederPulseCommandPath = "";
  feederPulseDurationMs = 0;
}

void startFeederPulse(const String &docPath) {
  applyRelayState("fish_feeder", true);
  feederPulseActive = true;
  feederPulseDurationMs = FISH_FEEDER_FULL_ROTATION_MS * FISH_FEEDER_ROTATION_COUNT;
  feederPulseEndMs = millis() + feederPulseDurationMs;
  feederPulseCommandPath = docPath;
}

void executeCommand(
  const String &docFullName,
  const String &type,
  bool hasTargetState,
  bool targetState,
  bool hasDurationMs,
  unsigned long durationMs
) {
  int idx = docFullName.indexOf("/documents/");
  if (idx < 0) return;
  String docPath = docFullName.substring(idx + 11);

  Serial.printf(
    "Executing command: %s -> %s\n",
    type.c_str(),
    hasTargetState ? (targetState ? "true" : "false") : "n/a"
  );
  printConsoleLine(
    "command",
    String("type=") + type +
      ", targetState=" + (hasTargetState ? (targetState ? "true" : "false") : "n/a") +
      ", durationMs=" + (hasDurationMs ? String(durationMs) : "n/a")
  );

  bool ok = false;
  String msg = "Unsupported command";

  if (isLatchedRelayType(type)) {
    if (!hasTargetState) {
      msg = "targetState is required";
      logEvent("warn", "command_failed", type + " missing targetState");
    } else {
      patchCommandStatus(
        docPath,
        "executing",
        String("executing ") + type + (targetState ? " ON" : " OFF"),
        false
      );
      bool *statePtr = relayStatePtr(type);
      if (statePtr != nullptr && *statePtr == targetState) {
        msg = "Relay already in requested state";
        logEvent("info", "command_executed", type + " already in requested state");
      } else {
        applyRelayState(type, targetState);
        msg = String(type) + (targetState ? " turned ON" : " turned OFF");
        logEvent("info", "command_executed", msg);
      }
      ok = true;
    }
  } else if (type == "fish_feeder") {
    if (feederPulseActive) {
      msg = "fish_feeder servo already active";
      logEvent("warn", "command_failed", msg);
    } else {
      startFeederPulse(docPath);
      logEvent(
        "info",
        "feeder_servo_started",
        String("fish_feeder servo started ") + String(FISH_FEEDER_ROTATION_COUNT) + " full rotations"
      );
      updateDeviceStatus(true);
      broadcastSnapshot();
      publishMqttSnapshot();
      patchCommandStatus(
        docPath,
        "executing",
        String("fish_feeder servo running ") + String(FISH_FEEDER_ROTATION_COUNT) + " full rotations",
        false
      );
      return;
    }
  } else {
    msg = "Unknown command type";
    logEvent("warn", "command_failed", "Unknown command type: " + type);
  }

  updateDeviceStatus(true);
  broadcastSnapshot();
  publishMqttSnapshot();
  patchCommandStatus(docPath, ok ? "executed" : "failed", msg, true);
}

void pollLatestPendingCommand() {
  bool ok = Firebase.Firestore.listDocuments(
    &fbdo,
    FIREBASE_PROJECT_ID,
    "",
    commandsColPath().c_str(),
    10,
    "",
    "",
    "",
    false
  );
  if (!ok) {
    printFirestoreResult("pollLatestPendingCommand listDocuments", false);
    return;
  }
  printFirestoreResult("pollLatestPendingCommand listDocuments", true);

  FirebaseJson js;
  js.setJsonData(fbdo.payload());

  FirebaseJsonData arr;
  js.get(arr, "documents");
  if (!arr.success) return;

  FirebaseJsonArray docs;
  docs.setJsonArrayData(arr.stringValue);
  String selectedDocName = "";
  String selectedDocType = "";
  bool selectedHasTargetState = false;
  bool selectedTargetState = false;
  bool selectedHasDurationMs = false;
  unsigned long selectedDurationMs = 0;
  String selectedSortKey = "";

  for (size_t i = 0; i < docs.size(); i++) {
    FirebaseJsonData docData;
    docs.get(docData, i);
    if (!docData.success) continue;

    FirebaseJson docJson;
    docJson.setJsonData(docData.stringValue);

    FirebaseJsonData nameData;
    FirebaseJsonData statusData;
    FirebaseJsonData typeData;
    FirebaseJsonData targetData;
    FirebaseJsonData durationMsData;
    FirebaseJsonData durationMsDoubleData;
    FirebaseJsonData durationSecData;
    FirebaseJsonData durationSecDoubleData;
    FirebaseJsonData createdAtData;
    FirebaseJsonData createTimeData;

    docJson.get(nameData, "name");
    docJson.get(statusData, "fields/status/stringValue");
    docJson.get(typeData, "fields/type/stringValue");
    docJson.get(targetData, "fields/targetState/booleanValue");
    docJson.get(durationMsData, "fields/durationMs/integerValue");
    docJson.get(durationMsDoubleData, "fields/durationMs/doubleValue");
    docJson.get(durationSecData, "fields/durationSec/integerValue");
    docJson.get(durationSecDoubleData, "fields/durationSec/doubleValue");
    docJson.get(createdAtData, "fields/createdAt/timestampValue");
    docJson.get(createTimeData, "createTime");

    if (!nameData.success || !statusData.success || !typeData.success) {
      continue;
    }

    if (statusData.stringValue == "pending") {
      bool hasTargetState = targetData.success;
      bool parsedTargetState = targetData.success ? targetData.boolValue : false;
      bool hasDurationMs = false;
      unsigned long durationMs = 0;

      if (durationMsData.success) {
        durationMs = (unsigned long)strtoull(durationMsData.stringValue.c_str(), nullptr, 10);
        hasDurationMs = durationMs > 0;
      } else if (durationMsDoubleData.success) {
        durationMs = (unsigned long)durationMsDoubleData.doubleValue;
        hasDurationMs = durationMs > 0;
      } else if (durationSecData.success) {
        durationMs = (unsigned long)strtoull(durationSecData.stringValue.c_str(), nullptr, 10) * 1000UL;
        hasDurationMs = durationMs > 0;
      } else if (durationSecDoubleData.success) {
        durationMs = (unsigned long)(durationSecDoubleData.doubleValue * 1000.0);
        hasDurationMs = durationMs > 0;
      }

      String sortKey = createdAtData.success ? createdAtData.stringValue : "";
      if (sortKey.length() == 0 && createTimeData.success) {
        sortKey = createTimeData.stringValue;
      }
      if (sortKey.length() == 0) {
        sortKey = nameData.stringValue;
      }

      if (selectedDocName.length() == 0 || sortKey > selectedSortKey) {
        selectedDocName = nameData.stringValue;
        selectedDocType = typeData.stringValue;
        selectedHasTargetState = hasTargetState;
        selectedTargetState = parsedTargetState;
        selectedHasDurationMs = hasDurationMs;
        selectedDurationMs = durationMs;
        selectedSortKey = sortKey;
      }
    }
  }

  if (selectedDocName.length() == 0) return;

  executeCommand(
    selectedDocName,
    selectedDocType,
    selectedHasTargetState,
    selectedTargetState,
    selectedHasDurationMs,
    selectedDurationMs
  );
}

void executeJsonCommandPayload(const String &payloadStr, const String &source, const String &prefix) {
  FirebaseJson js;
  js.setJsonData(payloadStr);

  FirebaseJsonData idData;
  FirebaseJsonData commandIdData;
  FirebaseJsonData typeData;
  FirebaseJsonData targetData;
  FirebaseJsonData durationMsData;
  FirebaseJsonData durationSecData;

  String base = prefix;
  if (base.length() > 0 && !base.endsWith("/")) base += "/";

  js.get(idData, (base + "id").c_str());
  js.get(commandIdData, (base + "commandId").c_str());
  js.get(typeData, (base + "type").c_str());
  js.get(targetData, (base + "targetState").c_str());
  js.get(durationMsData, (base + "durationMs").c_str());
  js.get(durationSecData, (base + "durationSec").c_str());

  if (!typeData.success || typeData.stringValue.length() == 0) {
    publishBackendWsCommandAck("unknown", "failed", source + " command missing type");
    publishMqttCommandAck("unknown", "failed", source + " command missing type");
    return;
  }

  String commandId = idData.success ? idData.stringValue : "";
  if (commandId.length() == 0 && commandIdData.success) {
    commandId = commandIdData.stringValue;
  }
  if (commandId.length() == 0) {
    commandId = source + "-" + String(millis());
  }

  bool hasTargetState = targetData.success;
  bool targetState = false;
  if (hasTargetState) {
    String targetRaw = targetData.stringValue;
    targetRaw.toLowerCase();
    targetState = targetData.boolValue ||
                  targetRaw == "true" ||
                  targetRaw == "1" ||
                  (targetData.doubleValue > 0.5);
  }
  bool hasDurationMs = false;
  unsigned long durationMs = 0;

  if (durationMsData.success) {
    if (durationMsData.type == "int" || durationMsData.type == "integer") {
      durationMs = (unsigned long)strtoull(durationMsData.stringValue.c_str(), nullptr, 10);
    } else {
      durationMs = (unsigned long)durationMsData.doubleValue;
    }
    hasDurationMs = durationMs > 0;
  } else if (durationSecData.success) {
    if (durationSecData.type == "int" || durationSecData.type == "integer") {
      durationMs = (unsigned long)strtoull(durationSecData.stringValue.c_str(), nullptr, 10) * 1000UL;
    } else {
      durationMs = (unsigned long)(durationSecData.doubleValue * 1000.0);
    }
    hasDurationMs = durationMs > 0;
  }

  String docFullName =
    String("projects/local/databases/(default)/documents/devices/") +
    deviceId +
    "/commands/" +
    commandId;

  executeCommand(
    docFullName,
    typeData.stringValue,
    hasTargetState,
    targetState,
    hasDurationMs,
    durationMs
  );
}

void onMqttMessage(char *topic, byte *payload, unsigned int length) {
  String topicStr(topic);
  String payloadStr;
  payloadStr.reserve(length + 1);
  for (unsigned int i = 0; i < length; i++) {
    payloadStr += (char)payload[i];
  }

  if (topicStr == mqttNanoTelemetryTopic) {
    onNanoMqttTelemetry(payloadStr);
    return;
  }

  if (topicStr != mqttCommandTopic) return;
  printConsoleJson("mqtt_command_received", payloadStr);
  executeJsonCommandPayload(payloadStr, "mqtt", "");
}

void processFeederPulse() {
  if (!feederPulseActive) return;
  if ((long)(millis() - feederPulseEndMs) < 0) return;
  finalizeFeederPulse();
}

void onBackendWsText(const String &payloadStr) {
  printConsoleJson("backend_ws_received", payloadStr);
  FirebaseJson js;
  js.setJsonData(payloadStr);

  FirebaseJsonData typeData;
  js.get(typeData, "type");
  if (!typeData.success) return;

  if (typeData.stringValue == "device_command") {
    executeJsonCommandPayload(payloadStr, "backend_ws", "command");
    return;
  }

  if (typeData.stringValue == "telemetry") {
    FirebaseJsonData payloadData;
    js.get(payloadData, "payload");
    if (payloadData.success && payloadData.stringValue.length() > 0) {
      onNanoMqttTelemetry(payloadData.stringValue);
    }
  }
}

void onBackendWsEvent(WStype_t type, uint8_t *payload, size_t length) {
  switch (type) {
    case WStype_CONNECTED:
      backendWsConnected = true;
      Serial.println("[BackendWS] connected");
      backendWsClient.sendTXT(String("{\"type\":\"ping\",\"deviceId\":\"") + deviceId + "\"}");
      break;
    case WStype_DISCONNECTED:
      backendWsConnected = false;
      Serial.println("[BackendWS] disconnected");
      break;
    case WStype_TEXT: {
      String payloadStr;
      payloadStr.reserve(length + 1);
      for (size_t i = 0; i < length; i++) payloadStr += (char)payload[i];
      onBackendWsText(payloadStr);
      break;
    }
    default:
      break;
  }
}

void onWsEvent(uint8_t clientNum, WStype_t type, uint8_t *payload, size_t length) {
  (void) payload;
  (void) length;

  if (type == WStype_CONNECTED) {
    String payloadStr = buildSnapshotJson();
    wsServer.sendTXT(clientNum, payloadStr);
    printConsoleJson("websocket_client_send", payloadStr);
  }
}

void setup() {
  Serial.begin(115200);

  pinMode(RELAY_PH_UP_PIN, OUTPUT);
  pinMode(RELAY_PH_DOWN_PIN, OUTPUT);
  pinMode(RELAY_NUTRIENT_PIN, OUTPUT);
  pinMode(RELAY_FISH_TO_FILTER_PIN, OUTPUT);
  ESP32PWM::allocateTimer(0);
  fishFeederServo.setPeriodHertz(50);
  fishFeederServo.attach(
    FISH_FEEDER_SERVO_PIN,
    FISH_FEEDER_SERVO_MIN_US,
    FISH_FEEDER_SERVO_MAX_US
  );
  applyRelayState("ph_up", false);
  applyRelayState("ph_down", false);
  applyRelayState("nutrient", false);
  applyRelayState("fish_to_filter", false);
  applyRelayState("fish_feeder", false);

  if (USE_UNO_UART) {
    unoSerial.setRxBufferSize(512);
    unoSerial.begin(UNO_UART_BAUD, SERIAL_8N1, UNO_UART_RX_PIN, UNO_UART_TX_PIN);
    Serial.printf(
      "[UNO] UART2 listening rx=%d tx=%d baud=%lu\n",
      UNO_UART_RX_PIN,
      UNO_UART_TX_PIN,
      (unsigned long)UNO_UART_BAUD
    );
  }

  connectWifi();

  mqttTopicLive = "plantation/" + String(deviceId) + "/telemetry/live";
  mqttStatusTopic = "plantation/" + String(deviceId) + "/status";
  mqttCommandTopic = "plantation/" + String(deviceId) + "/commands";
  mqttCommandAckTopic = "plantation/" + String(deviceId) + "/commands/ack";
  mqttNanoTelemetryTopic = "plantation/" + String(deviceId) + "/nano/telemetry";
  backendWsPath = "/ws?deviceId=" + String(deviceId) + "&role=device";
  wsUrl = "ws://" + WiFi.localIP().toString() + ":" + String(WS_PORT);
  Serial.println("WebSocket endpoint: " + wsUrl);
  Serial.println("Backend WebSocket: ws://" + String(BACKEND_WS_HOST) + ":" + String(BACKEND_WS_PORT) + backendWsPath);
  Serial.println("MQTT live topic: " + mqttTopicLive);
  Serial.println("MQTT status topic: " + mqttStatusTopic);
  Serial.println("MQTT command topic: " + mqttCommandTopic);
  Serial.println("MQTT command ack topic: " + mqttCommandAckTopic);
  Serial.println("MQTT nano telemetry topic: " + mqttNanoTelemetryTopic);

  wsServer.begin();
  wsServer.onEvent(onWsEvent);

#if MQTT_USE_TLS
  mqttSecureClient.setInsecure();
#endif
  mqttClient.setServer(MQTT_BROKER_HOST, MQTT_BROKER_PORT);
  mqttClient.setCallback(onMqttMessage);
  mqttClient.setKeepAlive(20);
  mqttClient.setBufferSize(1536);
  backendWsClient.begin(BACKEND_WS_HOST, BACKEND_WS_PORT, backendWsPath);
  backendWsClient.onEvent(onBackendWsEvent);
  backendWsClient.setReconnectInterval(2000);
  backendWsClient.enableHeartbeat(15000, 3000, 2);
  connectMqtt();

  config.api_key = API_KEY;
  auth.user.email = USER_EMAIL;
  auth.user.password = USER_PASSWORD;
  config.token_status_callback = tokenStatusCallback;

  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  const bool mqttReadyAtBoot = mqttClient.connected();
  if (mqttReadyAtBoot) {
    Serial.println("[Firebase] local MQTT connected; skipping blocking Firebase boot wait");
  } else {
    Serial.print("Waiting Firebase auth");
    unsigned long authStartMs = millis();
    while (!Firebase.ready() && millis() - authStartMs < 20000) {
      delay(200);
      Serial.print(".");
    }
    Serial.println();

    Serial.print("Waiting UTC time sync");
    bool timeReady = syncUtcTimeViaNtp(30000);
    Serial.println();
    if (!timeReady) {
      Serial.println("[Firestore] UTC time sync timeout; timestamped writes will retry later");
    } else {
      Serial.println("[Firestore] UTC time synchronized");
    }
  }

  acquireSensors();
  if (!mqttReadyAtBoot) {
    ensureDeviceDocument();
    updateDeviceStatus(true);
    writeReadingSnapshot();
  }
  publishMqttSnapshot();
  broadcastSnapshot();
  logEvent("info", "device_online", "Aquaponics ESP32 connected and reporting online");
}

void loop() {
  wsServer.loop();
  backendWsClient.loop();
  ensureMqttConnected();
  mqttClient.loop();
  pollUnoSerial();
  processFeederPulse();

  if (millis() - lastSensorMs >= SENSOR_INTERVAL_MS) {
    lastSensorMs = millis();
    acquireSensors();
    broadcastSnapshot();
    publishMqttSnapshot();
    // Service MQTT again right after publishing so a command that arrived
    // during sensor work is handled without waiting for the next loop pass.
    mqttClient.loop();
  }

  // When the MQTT/local backend link is up, commands and status flow over MQTT.
  // Skip the blocking Firestore REST poll and Firebase status writes in that
  // case so they don't stall the loop and delay live command handling. They
  // resume automatically as a fallback whenever MQTT is disconnected.
  const bool mqttUp = mqttClient.connected();

  if (!Firebase.ready()) {
    delay(mqttUp ? 5 : 50);
    return;
  }

  if (millis() - lastStatusMs >= STATUS_INTERVAL_MS) {
    lastStatusMs = millis();
    if (!mqttUp) updateDeviceStatus(true);
  }

  if (millis() - lastCmdPollMs >= CMD_POLL_INTERVAL_MS) {
    lastCmdPollMs = millis();
    if (!mqttUp) pollLatestPendingCommand();
  }

  if (millis() - lastHistoryMs >= HISTORY_INTERVAL_MS) {
    lastHistoryMs = millis();
    if (!mqttUp) writeReadingSnapshot();
  }
}
