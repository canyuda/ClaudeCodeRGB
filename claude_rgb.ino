// ESP32-C3 SuperMini + 共阴极 4P RGB 模块
// Claude Code RGB 状态灯
//
// 支持串口命令：
// STATE:idle
// STATE:done
// STATE:running
// STATE:tool
// STATE:ask
// STATE:error
// PING
// HELP
//
// 共阴极逻辑：HIGH = 亮，LOW = 灭

#define RED_PIN    2
#define GREEN_PIN  3
#define BLUE_PIN   4

enum LedState {
  STATE_IDLE,
  STATE_DONE,
  STATE_RUNNING,
  STATE_TOOL,
  STATE_ASK,
  STATE_ERROR
};

LedState currentState = STATE_IDLE;

String inputLine = "";

unsigned long lastEffectMs = 0;
bool blinkOn = true;

const unsigned long RUNNING_INTERVAL_MS = 500;  // 蓝灯慢闪
const unsigned long TOOL_INTERVAL_MS    = 150;  // 紫灯快闪
const unsigned long ASK_INTERVAL_MS     = 250;  // 黄灯快闪
const unsigned long ERROR_INTERVAL_MS   = 100;  // 红灯快闪

void setColor(bool red, bool green, bool blue) {
  digitalWrite(RED_PIN, red ? HIGH : LOW);
  digitalWrite(GREEN_PIN, green ? HIGH : LOW);
  digitalWrite(BLUE_PIN, blue ? HIGH : LOW);
}

void allOff() {
  setColor(false, false, false);
}

void greenOn() {
  setColor(false, true, false);
}

void blueOn() {
  setColor(false, false, true);
}

void purpleOn() {
  setColor(true, false, true);
}

void yellowOn() {
  setColor(true, true, false);
}

void redOn() {
  setColor(true, false, false);
}

const char* stateName(LedState state) {
  switch (state) {
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
    case STATE_DONE:
      greenOn();
      break;

    case STATE_RUNNING:
      blueOn();
      break;

    case STATE_TOOL:
      purpleOn();
      break;

    case STATE_ASK:
      yellowOn();
      break;

    case STATE_ERROR:
      redOn();
      break;
  }
}

void setState(LedState newState) {
  currentState = newState;
  lastEffectMs = millis();
  blinkOn = true;

  applyImmediateColor();

  Serial.print("OK STATE:");
  Serial.println(stateName(currentState));
}

void printHelp() {
  Serial.println("Claude RGB Ready");
  Serial.println("Commands:");
  Serial.println("  STATE:idle");
  Serial.println("  STATE:done");
  Serial.println("  STATE:running");
  Serial.println("  STATE:tool");
  Serial.println("  STATE:ask");
  Serial.println("  STATE:error");
  Serial.println("  PING");
  Serial.println("  HELP");
}

void handleCommand(String cmd) {
  cmd.trim();

  if (cmd.length() == 0) {
    return;
  }

  String original = cmd;

  cmd.toLowerCase();

  if (cmd == "ping") {
    Serial.print("PONG STATE:");
    Serial.println(stateName(currentState));
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

  if (cmd == "idle") {
    setState(STATE_IDLE);
  } else if (cmd == "done") {
    setState(STATE_DONE);
  } else if (cmd == "running") {
    setState(STATE_RUNNING);
  } else if (cmd == "tool") {
    setState(STATE_TOOL);
  } else if (cmd == "ask") {
    setState(STATE_ASK);
  } else if (cmd == "error") {
    setState(STATE_ERROR);
  } else {
    Serial.print("ERR UNKNOWN_COMMAND:");
    Serial.println(original);
  }
}

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

      // 防止异常输入占用内存
      if (inputLine.length() > 100) {
        inputLine = "";
        Serial.println("ERR INPUT_TOO_LONG");
      }
    }
  }
}

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

      if (blinkOn) {
        blueOn();
      } else {
        allOff();
      }
      break;

    case STATE_TOOL:
      if (now - lastEffectMs >= TOOL_INTERVAL_MS) {
        lastEffectMs = now;
        blinkOn = !blinkOn;
      }

      if (blinkOn) {
        purpleOn();
      } else {
        allOff();
      }
      break;

    case STATE_ASK:
      if (now - lastEffectMs >= ASK_INTERVAL_MS) {
        lastEffectMs = now;
        blinkOn = !blinkOn;
      }

      if (blinkOn) {
        yellowOn();
      } else {
        allOff();
      }
      break;

    case STATE_ERROR:
      if (now - lastEffectMs >= ERROR_INTERVAL_MS) {
        lastEffectMs = now;
        blinkOn = !blinkOn;
      }

      if (blinkOn) {
        redOn();
      } else {
        allOff();
      }
      break;
  }
}

void bootFlash() {
  // 上电自检：红、绿、蓝各闪一次
  redOn();
  delay(150);
  allOff();
  delay(80);

  greenOn();
  delay(150);
  allOff();
  delay(80);

  blueOn();
  delay(150);
  allOff();
  delay(80);
}

void setup() {
  pinMode(RED_PIN, OUTPUT);
  pinMode(GREEN_PIN, OUTPUT);
  pinMode(BLUE_PIN, OUTPUT);

  Serial.begin(115200);

  bootFlash();

  // 默认空闲：绿灯常亮
  setState(STATE_IDLE);

  Serial.println("Claude RGB Controller Started");
  printHelp();
}

void loop() {
  readSerialCommands();
  updateLedEffect();
}
