#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <ArduinoJson.h>

// ── WiFi AP Configuration ──────────────────────────────────────────────────
const char* AP_SSID     = "InfantMonitor";
const char* AP_PASSWORD = "baby12345";
IPAddress   AP_IP(192, 168, 4, 1);
IPAddress   AP_GATEWAY(192, 168, 4, 1);
IPAddress   AP_SUBNET(255, 255, 255, 0);

// ── Pin Configuration ──────────────────────────────────────────────────────
#define MOISTURE_PIN  A0   // Analog moisture sensor
#define BUZZER_PIN    D5   // Active buzzer
#define LED_GREEN     D6   // Green LED  → DRY
#define LED_RED       D7   // Red LED    → WET

// ── Threshold Configuration ────────────────────────────────────────────────
// Moisture sensor: higher analog value = more wet (adjust after testing)
#define WET_THRESHOLD     600   // Raw ADC value above this = WET  (0–1023)
#define BUZZER_BEEP_MS    200   // Buzzer beep duration in ms
#define BUZZER_INTERVAL   3000  // Beep every 3 seconds when wet

// ── State Variables ────────────────────────────────────────────────────────
ESP8266WebServer server(80);

int     rawValue      = 0;
int     percentage    = 0;
bool    isWet         = false;
bool    buzzerOn      = false;
bool    buzzerEnabled = true;   // Can be toggled by app
String  lastStatus    = "DRY";
String  lastChanged   = "Never";
int     wetEventCount = 0;
unsigned long lastBuzzerTime  = 0;
unsigned long wetStartTime    = 0;
unsigned long lastReadTime    = 0;
unsigned long sessionStart    = 0;

// ── CORS helper ────────────────────────────────────────────────────────────
void addCORSHeaders() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
}

// ── /data endpoint ─────────────────────────────────────────────────────────
// Returns all sensor data as JSON, polled continuously by Flutter app
void handleData() {
  addCORSHeaders();

  unsigned long uptimeSec = (millis() - sessionStart) / 1000;
  unsigned long wetDuration = isWet ? (millis() - wetStartTime) / 1000 : 0;

  StaticJsonDocument<300> doc;
  doc["raw"]          = rawValue;
  doc["percentage"]   = percentage;
  doc["status"]       = isWet ? "WET" : "DRY";
  doc["isWet"]        = isWet;
  doc["buzzerOn"]     = buzzerOn;
  doc["buzzerEnabled"]= buzzerEnabled;
  doc["wetEvents"]    = wetEventCount;
  doc["lastChanged"]  = lastChanged;
  doc["wetDuration"]  = (int)wetDuration;   // seconds currently wet
  doc["uptime"]       = (int)uptimeSec;
  doc["threshold"]    = WET_THRESHOLD;
  doc["ip"]           = AP_IP.toString();

  String response;
  serializeJson(doc, response);
  server.send(200, "application/json", response);
}

// ── /buzzer endpoint ───────────────────────────────────────────────────────
// Flutter app can toggle buzzer on/off via GET /buzzer?enable=true|false
void handleBuzzer() {
  addCORSHeaders();
  if (server.hasArg("enable")) {
    buzzerEnabled = (server.arg("enable") == "true");
    if (!buzzerEnabled) {
      digitalWrite(BUZZER_PIN, LOW);
      buzzerOn = false;
    }
  }
  server.send(200, "application/json",
    "{\"buzzerEnabled\":" + String(buzzerEnabled ? "true" : "false") + "}");
}

// ── /reset endpoint ────────────────────────────────────────────────────────
void handleReset() {
  addCORSHeaders();
  wetEventCount = 0;
  lastChanged   = "Never";
  server.send(200, "application/json", "{\"reset\":true}");
}

// ── / root endpoint ────────────────────────────────────────────────────────
void handleRoot() {
  addCORSHeaders();
  String html = "<html><body style='font-family:sans-serif;text-align:center;padding:20px'>";
  html += "<h2>Infant Monitor</h2>";
  html += "<p>Status: <b>" + lastStatus + "</b></p>";
  html += "<p>Raw: " + String(rawValue) + " | " + String(percentage) + "%</p>";
  html += "<p><a href='/data'>JSON Data</a></p>";
  html += "</body></html>";
  server.send(200, "text/html", html);
}

// ── Setup ──────────────────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);

  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(LED_GREEN,  OUTPUT);
  pinMode(LED_RED,    OUTPUT);

  // Boot blink — 3 flashes to confirm startup
  for (int i = 0; i < 3; i++) {
    digitalWrite(LED_GREEN, HIGH);
    digitalWrite(LED_RED,   HIGH);
    delay(150);
    digitalWrite(LED_GREEN, LOW);
    digitalWrite(LED_RED,   LOW);
    delay(150);
  }

  // Start WiFi Access Point with fixed IP
  WiFi.mode(WIFI_AP);
  WiFi.softAPConfig(AP_IP, AP_GATEWAY, AP_SUBNET);
  WiFi.softAP(AP_SSID, AP_PASSWORD);

  Serial.println("\n=== Infant Monitor ===");
  Serial.print("AP IP: ");
  Serial.println(WiFi.softAPIP());

  // Register HTTP routes
  server.on("/",        handleRoot);
  server.on("/data",    handleData);
  server.on("/buzzer",  handleBuzzer);
  server.on("/reset",   handleReset);
  server.onNotFound([]() {
    addCORSHeaders();
    server.send(404, "application/json", "{\"error\":\"Not found\"}");
  });

  server.begin();
  sessionStart = millis();
  Serial.println("HTTP server started on port 80");

  // Start with green LED = dry
  digitalWrite(LED_GREEN, HIGH);
}

// ── Main loop ──────────────────────────────────────────────────────────────
void loop() {
  server.handleClient();

  // Read sensor every 500ms
  if (millis() - lastReadTime >= 500) {
    lastReadTime = millis();

    rawValue   = analogRead(MOISTURE_PIN);
    percentage = map(rawValue, 0, 1023, 0, 100);
    bool nowWet = (rawValue > WET_THRESHOLD);

    // Detect state transition
    if (nowWet != isWet) {
      isWet      = nowWet;
      lastStatus = isWet ? "WET" : "DRY";

      // Timestamp (uptime seconds as proxy since no RTC)
      unsigned long sec = millis() / 1000;
      lastChanged = String(sec / 3600) + "h "
                  + String((sec % 3600) / 60) + "m "
                  + String(sec % 60) + "s";

      if (isWet) {
        wetEventCount++;
        wetStartTime = millis();
        Serial.println("[ALERT] WET detected! Event #" + String(wetEventCount));
      } else {
        Serial.println("[OK] Back to DRY");
      }

      // Update LEDs immediately on state change
      digitalWrite(LED_GREEN, isWet ? LOW  : HIGH);
      digitalWrite(LED_RED,   isWet ? HIGH : LOW);
    }

    // Buzzer beeping logic — beep every BUZZER_INTERVAL ms while wet
    if (isWet && buzzerEnabled) {
      if (millis() - lastBuzzerTime >= BUZZER_INTERVAL) {
        lastBuzzerTime = millis();
        digitalWrite(BUZZER_PIN, HIGH);
        buzzerOn = true;
      }
    }

    // Turn buzzer off after BUZZER_BEEP_MS
    if (buzzerOn && (millis() - lastBuzzerTime >= BUZZER_BEEP_MS)) {
      digitalWrite(BUZZER_PIN, LOW);
      buzzerOn = false;
    }

    // If dry, ensure buzzer and red LED are off
    if (!isWet) {
      digitalWrite(BUZZER_PIN, LOW);
      buzzerOn = false;
    }

    Serial.printf("Raw: %d | %%: %d | Status: %s\n",
                  rawValue, percentage, isWet ? "WET" : "DRY");
  }
}
