# Infant Urination Alert & Monitoring System
## Hardware + Software Setup Guide

---

## Wiring Diagram

```
NodeMCU Pin   →   Component
──────────────────────────────
A0            →   Moisture sensor AOUT
D5 (GPIO14)   →   Active buzzer + (other leg to GND)
D6 (GPIO12)   →   Green LED anode → 220Ω resistor → GND
D7 (GPIO13)   →   Red LED anode   → 220Ω resistor → GND
3.3V          →   Moisture sensor VCC
GND           →   Moisture sensor GND, Buzzer GND, LED GND
```

### Moisture Sensor Module Connections
```
Sensor pin   NodeMCU pin
VCC      →   3.3V  (or 5V if your module accepts it)
GND      →   GND
AOUT     →   A0    (analog out — the one we use)
DOUT     →   not connected
```

---

## Arduino IDE Setup

1. Install **ESP8266 board** in Arduino IDE
   - Boards Manager URL: `http://arduino.esp8266.com/stable/package_esp8266com_index.json`
   - Install: "ESP8266 by ESP8266 Community"

2. Install libraries via Library Manager:
   - `ArduinoJson` by Benoit Blanchon (v6.x)

3. Board settings:
   - Board: **NodeMCU 1.0 (ESP-12E Module)**
   - Upload Speed: 115200
   - CPU Frequency: 80MHz

4. Open `infant_alert.ino`, set your threshold (line ~20), upload.

---

## Threshold Calibration

Run the serial monitor at 115200 baud. Watch the raw values:
- Place sensor on **dry diaper** → note the value (e.g. 200–400)
- Place sensor on **wet diaper** → note the value (e.g. 700–900)
- Set `WET_THRESHOLD` halfway between those two values

Default is 600. Adjust in the sketch top section.

---

## Flutter App Setup

1. Add `http` package:
   ```
   cd flutter_app
   flutter pub get
   ```

2. Android — add internet permission in `android/app/src/main/AndroidManifest.xml`:
   ```xml
   <uses-permission android:name="android.permission.INTERNET"/>
   ```

3. Android cleartext (HTTP not HTTPS) — add in AndroidManifest.xml `<application>` tag:
   ```xml
   android:usesCleartextTraffic="true"
   ```

4. Build and run:
   ```
   flutter run
   ```

---

## Using the System

1. Power up NodeMCU
2. On your phone → WiFi settings → connect to **"InfantMonitor"** network
   - Password: `baby12345`
3. Open the Flutter app — it connects automatically to `192.168.4.1`
4. The app polls every 2 seconds — status updates in real time

---

## API Endpoints

| Endpoint                  | Description                          |
|---------------------------|--------------------------------------|
| GET /data                 | Full JSON sensor data                |
| GET /buzzer?enable=true   | Turn buzzer on                       |
| GET /buzzer?enable=false  | Turn buzzer off (silence alert)      |
| GET /reset                | Reset wet event counter and log      |
| GET /                     | Simple HTML status page              |

### JSON Response Example
```json
{
  "raw": 720,
  "percentage": 70,
  "status": "WET",
  "isWet": true,
  "buzzerOn": false,
  "buzzerEnabled": true,
  "wetEvents": 3,
  "lastChanged": "0h 12m 34s",
  "wetDuration": 45,
  "uptime": 3600,
  "threshold": 600,
  "ip": "192.168.4.1"
}
```

---

## Exhibition Demo Tips

- Use a wet sponge/cloth to simulate urination for live demos
- Show the serial monitor on laptop alongside the phone app
- Explain the AP mode — no router/internet needed, self-contained system
- Show the event log building up as you wet/dry the sensor repeatedly
