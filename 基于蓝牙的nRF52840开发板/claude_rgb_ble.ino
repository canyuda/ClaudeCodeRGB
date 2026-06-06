// Seeed Studio XIAO nRF52840 — Claude Code RGB Status Light
// BLE UART (Nordic UART Service) + Built-in RGB LED
//
// Hardware: XIAO nRF52840 only (no external LED needed)
// Board package: Seeed nRF52 Boards (provides Bluefruit library)
//
// Serial commands (BLE UART or USB Serial):
//   STATE:idle      Green steady
//   STATE:done      Green steady
//   STATE:running   Blue slow blink (500ms)
//   STATE:tool      Purple fast blink (150ms)
//   STATE:ask       Yellow fast blink (250ms)
//   STATE:error     Red fast blink (100ms)
//   PING            Returns "PONG STATE:<current>"
//   HELP            Shows all commands
//
// Built-in RGB LED — common anode: LOW = ON, HIGH = OFF

#include <bluefruit.h>
#include <Adafruit_TinyUSB.h>  // Required for Serial with Seeed nRF52 Boards

// ---------------------------------------------------------------------------
// LED helpers (common anode)
// ---------------------------------------------------------------------------

void setColor(bool red, bool green, bool blue) {
  digitalWrite(LED_RED,   red   ? LOW : HIGH);
  digitalWrite(LED_GREEN, green ? LOW : HIGH);
  digitalWrite(LED_BLUE,  blue  ? LOW : HIGH);
}

void allOff()   { setColor(false, false, false); }
void greenOn()  { setColor(false, true,  false); }
void blueOn()   { setColor(false, false, true);  }
void purpleOn() { setColor(true,  false, true);  }
void yellowOn() { setColor(true,  true,  false); }
void redOn()    { setColor(true,  false, false); }

// ---------------------------------------------------------------------------
// State machine
// ---------------------------------------------------------------------------

enum LedState {
  STATE_IDLE,
  STATE_DONE,
  STATE_RUNNING,
  STATE_TOOL,
  STATE_ASK,
  STATE_ERROR
};

LedState currentState = STATE_IDLE;
unsigned long lastEffectMs = 0;
bool blinkOn = true;

const unsigned long RUNNING_INTERVAL_MS = 500;
const unsigned long TOOL_INTERVAL_MS    = 150;
const unsigned long ASK_INTERVAL_MS     = 250;
const unsigned long ERROR_INTERVAL_MS   = 100;

const char* stateName(LedState s) {
  switch (s) {
    case STATE_IDLE:    return "idle";
    case STATE_DONE:    return "done";
    case STATE_RUNNING: return "running";
    case STATE_TOOL:    return "tool";
    case STATE_ASK:     return "ask";
    case STATE_ERROR:   return "error";
    default:            return "unknown";
  }
}

void applyImmediateColor() {
  switch (currentState) {
    case STATE_IDLE:
    case STATE_DONE:    greenOn();  break;
    case STATE_RUNNING: blueOn();   break;
    case STATE_TOOL:    purpleOn(); break;
    case STATE_ASK:     yellowOn(); break;
    case STATE_ERROR:   redOn();    break;
  }
}

// ---------------------------------------------------------------------------
// BLE UART
// ---------------------------------------------------------------------------

BLEUart bleuart;

// ---------------------------------------------------------------------------
// Command handling
// ---------------------------------------------------------------------------

String inputLine = "";

void respond(const char* msg) {
  Serial.print(msg);
  if (bleuart.notifyEnabled()) {
    bleuart.print(msg);
  }
}

void respondLn(const char* msg) {
  Serial.println(msg);
  if (bleuart.notifyEnabled()) {
    bleuart.println(msg);
  }
}

void printHelp() {
  respondLn("Claude RGB BLE Ready");
  respondLn("Commands:");
  respondLn("  STATE:idle");
  respondLn("  STATE:done");
  respondLn("  STATE:running");
  respondLn("  STATE:tool");
  respondLn("  STATE:ask");
  respondLn("  STATE:error");
  respondLn("  PING");
  respondLn("  HELP");
}

void setState(LedState newState) {
  currentState = newState;
  lastEffectMs = millis();
  blinkOn = true;
  applyImmediateColor();

  char buf[40];
  snprintf(buf, sizeof(buf), "OK STATE:%s\n", stateName(currentState));
  respond(buf);
}

void handleCommand(String cmd) {
  cmd.trim();
  if (cmd.length() == 0) return;

  String original = cmd;
  cmd.toLowerCase();

  if (cmd == "ping") {
    char buf[40];
    snprintf(buf, sizeof(buf), "PONG STATE:%s\n", stateName(currentState));
    respond(buf);
    return;
  }

  if (cmd == "help") {
    printHelp();
    return;
  }

  if (cmd.startsWith("state:")) {
    cmd = cmd.substring(6);
    cmd.trim();
  }

  if      (cmd == "idle")    setState(STATE_IDLE);
  else if (cmd == "done")    setState(STATE_DONE);
  else if (cmd == "running") setState(STATE_RUNNING);
  else if (cmd == "tool")    setState(STATE_TOOL);
  else if (cmd == "ask")     setState(STATE_ASK);
  else if (cmd == "error")   setState(STATE_ERROR);
  else {
    Serial.print("ERR UNKNOWN_COMMAND:");
    Serial.println(original);
  }
}

// ---------------------------------------------------------------------------
// LED effect update
// ---------------------------------------------------------------------------

void updateLedEffect() {
  unsigned long now = millis();

  switch (currentState) {
    case STATE_IDLE:
    case STATE_DONE:
      greenOn();
      break;

    case STATE_RUNNING:
      if (now - lastEffectMs >= RUNNING_INTERVAL_MS) {
        lastEffectMs = now;
        blinkOn = !blinkOn;
      }
      blinkOn ? blueOn() : allOff();
      break;

    case STATE_TOOL:
      if (now - lastEffectMs >= TOOL_INTERVAL_MS) {
        lastEffectMs = now;
        blinkOn = !blinkOn;
      }
      blinkOn ? purpleOn() : allOff();
      break;

    case STATE_ASK:
      if (now - lastEffectMs >= ASK_INTERVAL_MS) {
        lastEffectMs = now;
        blinkOn = !blinkOn;
      }
      blinkOn ? yellowOn() : allOff();
      break;

    case STATE_ERROR:
      if (now - lastEffectMs >= ERROR_INTERVAL_MS) {
        lastEffectMs = now;
        blinkOn = !blinkOn;
      }
      blinkOn ? redOn() : allOff();
      break;
  }
}

// ---------------------------------------------------------------------------
// Boot self-test
// ---------------------------------------------------------------------------

void bootFlash() {
  redOn();   delay(150); allOff(); delay(80);
  greenOn(); delay(150); allOff(); delay(80);
  blueOn();  delay(150); allOff(); delay(80);
}

// ---------------------------------------------------------------------------
// BLE callbacks
// ---------------------------------------------------------------------------

void connectCallback(uint16_t connHandle) {
  (void) connHandle;
  Serial.println("[BLE] Connected");

  // Stop advertising once connected
  Bluefruit.Advertising.stop();
}

void disconnectCallback(uint16_t connHandle, uint8_t reason) {
  (void) connHandle;
  (void) reason;
  Serial.println("[BLE] Disconnected, restarting advertising");
  Bluefruit.Advertising.start(0);  // 0 = advertise forever
}

// BLE UART RX callback — data received from central
void bleuartRxCallback(void) {
  while (bleuart.available()) {
    char c = (char) bleuart.read();

    if (c == '\n' || c == '\r') {
      if (inputLine.length() > 0) {
        handleCommand(inputLine);
        inputLine = "";
      }
    } else {
      inputLine += c;
      if (inputLine.length() > 100) {
        inputLine = "";
        respondLn("ERR INPUT_TOO_LONG");
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Read USB Serial (debug / fallback)
// ---------------------------------------------------------------------------

void readSerialCommands() {
  while (Serial.available() > 0) {
    char c = Serial.read();

    if (c == '\n' || c == '\r') {
      if (inputLine.length() > 0) {
        handleCommand(inputLine);
        inputLine = "";
      }
    } else {
      inputLine += c;
      if (inputLine.length() > 100) {
        inputLine = "";
        Serial.println("ERR INPUT_TOO_LONG");
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Setup & Loop
// ---------------------------------------------------------------------------

void setup() {
  // Initialize built-in RGB LED pins
  pinMode(LED_RED,   OUTPUT);
  pinMode(LED_GREEN, OUTPUT);
  pinMode(LED_BLUE,  OUTPUT);
  allOff();

  // USB Serial for debug
  Serial.begin(115200);

  // Boot self-test
  bootFlash();

  // Default to idle (green steady)
  setState(STATE_IDLE);

  // ---- BLE setup ----
  Bluefruit.begin();
  Bluefruit.setName("ClaudeRGB-nRF52840");

  // Disable auto LED control — we manage LED ourselves
  Bluefruit.autoConnLed(false);

  // Connection callbacks
  Bluefruit.Periph.setConnectCallback(connectCallback);
  Bluefruit.Periph.setDisconnectCallback(disconnectCallback);

  // BLE UART service
  bleuart.begin();
  bleuart.setRxCallback(bleuartRxCallback);

  // Configure advertising
  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
  Bluefruit.Advertising.addTxPower();
  Bluefruit.Advertising.addService(bleuart);

  // Secondary scan response packet with device name
  Bluefruit.ScanResponse.addName();

  // Start advertising (0 = forever)
  Bluefruit.Advertising.start(0);

  Serial.println("Claude RGB BLE Controller Started");
  Serial.println("BLE Device: ClaudeRGB-nRF52840");
  printHelp();
}

void loop() {
  readSerialCommands();
  updateLedEffect();
}
