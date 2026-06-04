// ESP32-C3 SuperMini + 共阴极 4P RGB 模块
// Claude Code RGB 状态灯 - WiFi 版
//
// 支持串口命令 + WiFi HTTP API 控制
// WiFi Manager 配网门户：首次使用手机连 AP 自动配网
//
// 串口命令：
// STATE:idle / STATE:done / STATE:running / STATE:tool / STATE:ask / STATE:error
// WIFICONFIG:SSID:PASSWORD  (串口配网)
// WIFICLEAR                  (清除 WiFi 配置)
// PING / HELP
//
// HTTP API：
// GET /state/{idle|running|tool|ask|error|done}
// GET /status / GET /ping
// POST /wificfg {"ssid":"xxx","pass":"xxx"}
// GET /wifiscan
// GET /  (Web 控制页面)
//
// 共阴极逻辑：HIGH = 亮，LOW = 灭

#include <WiFi.h>
#include <WiFiAP.h>
#include <NetworkClient.h>
#include <NetworkServer.h>
#include <DNSServer.h>
#include <Preferences.h>

#define RED_PIN    2
#define GREEN_PIN  3
#define BLUE_PIN   4

#define AP_SSID    "ClaudeRGB"
#define AP_PASS    "12345678"  // WPA2 min 8 chars, shown on config page
#define HTTP_PORT  80
#define DNS_PORT   53
#define WIFI_STA_TIMEOUT_MS  15000
#define WIFI_MAX_RETRIES     3

enum LedState {
  STATE_IDLE,
  STATE_DONE,
  STATE_RUNNING,
  STATE_TOOL,
  STATE_ASK,
  STATE_ERROR,
  STATE_WIFI_CONFIG,     // AP mode, waiting for config
  STATE_WIFI_CONNECTING  // connecting to WiFi
};

LedState currentState = STATE_IDLE;

String inputLine = "";

unsigned long lastEffectMs = 0;
bool blinkOn = true;

const unsigned long RUNNING_INTERVAL_MS = 500;  // blue slow blink
const unsigned long TOOL_INTERVAL_MS    = 150;  // purple fast blink
const unsigned long ASK_INTERVAL_MS     = 250;  // yellow fast blink
const unsigned long ERROR_INTERVAL_MS   = 100;  // red fast blink
const unsigned long WIFI_CFG_INTERVAL_MS = 1000; // blue slow blink (config mode)
const unsigned long WIFI_CONN_INTERVAL_MS = 200; // blue fast blink (connecting)

// WiFi globals
DNSServer dnsServer;
NetworkServer* httpServer = nullptr;
Preferences prefs;
bool isAPMode = false;
String wifiSSID = "";
String wifiPass = "";

// HTTP request buffer
String httpLine = "";

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
    case STATE_IDLE:           return "idle";
    case STATE_DONE:           return "done";
    case STATE_RUNNING:        return "running";
    case STATE_TOOL:           return "tool";
    case STATE_ASK:            return "ask";
    case STATE_ERROR:          return "error";
    case STATE_WIFI_CONFIG:    return "wifi_config";
    case STATE_WIFI_CONNECTING: return "wifi_connecting";
    default:                   return "unknown";
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
    case STATE_WIFI_CONFIG:
    case STATE_WIFI_CONNECTING:
      blueOn();
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
  Serial.println("Claude RGB WiFi Ready");
  Serial.println("Commands:");
  Serial.println("  STATE:idle|done|running|tool|ask|error");
  Serial.println("  WIFICONFIG:SSID:PASSWORD");
  Serial.println("  WIFICLEAR");
  Serial.println("  WIFIDIAG");
  Serial.println("  PING");
  Serial.println("  HELP");
}

// --- WiFi NVS persistence ---

bool loadWiFiConfig() {
  prefs.begin("wifi", true);
  wifiSSID = prefs.getString("ssid", "");
  wifiPass = prefs.getString("pass", "");
  prefs.end();
  return wifiSSID.length() > 0;
}

void saveWiFiConfig(const String& ssid, const String& pass) {
  prefs.begin("wifi", false);
  prefs.putString("ssid", ssid);
  prefs.putString("pass", pass);
  prefs.end();
}

void clearWiFiConfig() {
  prefs.begin("wifi", false);
  prefs.clear();
  prefs.end();
  wifiSSID = "";
  wifiPass = "";
}

// --- WiFi Manager ---

void diagnoseRadio() {
  // Step 1: scan WiFi to verify the radio can receive
  Serial.println("[DIAG] Scanning WiFi networks...");
  WiFi.mode(WIFI_STA);
  delay(100);
  int n = WiFi.scanNetworks();
  Serial.print("[DIAG] Found ");
  Serial.print(n);
  Serial.println(" networks");
  for (int i = 0; i < n && i < 5; i++) {
    Serial.print("[DIAG]   ");
    Serial.print(WiFi.SSID(i));
    Serial.print(" (");
    Serial.print(WiFi.RSSI(i));
    Serial.println(" dBm)");
  }
  WiFi.scanDelete();

  if (n == 0) {
    Serial.println("[DIAG] *** NO networks found! Radio may not be working. ***");
  } else {
    Serial.println("[DIAG] Radio OK - can receive WiFi signals");
  }
}

void startAPMode() {
  // IMPORTANT: skip diagnoseRadio() here to avoid STA mode polluting AP.
  // The diagnoseRadio() is only called manually via serial "WIFIDIAG" command.

  // Step 1: full WiFi reset to clear any previous state
  WiFi.mode(WIFI_OFF);
  delay(200);

  // Step 2: start AP directly (no STA scan beforehand!)
  WiFi.mode(WIFI_AP);
  delay(200);

  // Step 3: reduce TX power - ESP32-C3 SuperMini has known issues at max power
  // WiFi.setTxPower() accepts values: WIFI_POWER_2dBm .. WIFI_POWER_20dBm
  // Lower power = more stable AP on SuperMini
  WiFi.setTxPower(WIFI_POWER_11dBm);
  Serial.println("[AP] TX power set to 11 dBm (fix for SuperMini TX issue)");

  // Step 4: start softAP with explicit channel
  bool apOk = WiFi.softAP(AP_SSID, AP_PASS, 6, 0);
  if (!apOk) {
    Serial.println("[AP] softAP() failed on channel 6, retrying channel 1...");
    delay(200);
    apOk = WiFi.softAP(AP_SSID, AP_PASS, 1, 0);
  }
  if (!apOk) {
    Serial.println("[AP] FATAL: softAP() failed");
  }

  isAPMode = true;

  // DNS hijack: redirect all requests to AP IP
  dnsServer.start(DNS_PORT, "*", WiFi.softAPIP());

  if (!httpServer) {
    httpServer = new NetworkServer(HTTP_PORT);
  }
  httpServer->begin();

  setState(STATE_WIFI_CONFIG);

  Serial.println("--- AP Mode ---");
  Serial.print("SSID: ");
  Serial.println(AP_SSID);
  Serial.print("Password: ");
  Serial.println(AP_PASS);
  Serial.print("IP: ");
  Serial.println(WiFi.softAPIP());
  Serial.print("softAP status: ");
  Serial.println(apOk ? "OK" : "FAILED");
  Serial.print("Channel: ");
  Serial.println(WiFi.channel());
  Serial.print("TX power: ");
  Serial.print(WiFi.getTxPower());
  Serial.println(" (raw units)");
  Serial.println("----------------");
}

bool connectSTA() {
  setState(STATE_WIFI_CONNECTING);

  // clean reset - same pattern as startAPMode()
  WiFi.mode(WIFI_OFF);
  delay(200);
  WiFi.mode(WIFI_STA);
  delay(200);

  // reduce TX power for SuperMini stability
  WiFi.setTxPower(WIFI_POWER_11dBm);

  WiFi.begin(wifiSSID.c_str(), wifiPass.c_str());

  Serial.print("Connecting to WiFi: ");
  Serial.println(wifiSSID);

  unsigned long startMs = millis();
  while (WiFi.status() != WL_CONNECTED) {
    if (millis() - startMs > WIFI_STA_TIMEOUT_MS) {
      Serial.println("WiFi connection timeout");
      return false;
    }
    delay(200);
    Serial.print(".");
  }

  Serial.println();
  Serial.print("WiFi connected. IP: ");
  Serial.println(WiFi.localIP());

  isAPMode = false;

  if (!httpServer) {
    httpServer = new NetworkServer(HTTP_PORT);
  }
  httpServer->begin();

  setState(STATE_IDLE);
  return true;
}

void setupWiFi() {
  if (loadWiFiConfig()) {
    // has saved config, try STA
    int retries = 0;
    while (retries < WIFI_MAX_RETRIES) {
      if (connectSTA()) {
        return;
      }
      retries++;
      Serial.print("Retry ");
      Serial.print(retries);
      Serial.print("/");
      Serial.println(WIFI_MAX_RETRIES);
      delay(1000);
    }
    Serial.println("All retries failed, falling back to AP mode");
    clearWiFiConfig();
    startAPMode();
  } else {
    // no config, start AP for provisioning
    startAPMode();
  }
}

// --- HTTP response helpers ---

void sendJsonResponse(NetworkClient& client, int code, const String& json) {
  client.print("HTTP/1.1 ");
  client.print(code);
  client.print(" OK\r\n");
  client.print("Content-Type: application/json\r\n");
  client.print("Connection: close\r\n");
  client.print("Content-Length: ");
  client.print(json.length());
  client.print("\r\n\r\n");
  client.print(json);
}

void sendHtmlResponse(NetworkClient& client, const String& html) {
  client.print("HTTP/1.1 200 OK\r\n");
  client.print("Content-Type: text/html\r\n");
  client.print("Connection: close\r\n");
  client.print("Content-Length: ");
  client.print(html.length());
  client.print("\r\n\r\n");
  client.print(html);
}

// --- HTML pages ---

const char CONFIG_PAGE[] PROGMEM = R"rawliteral(<!DOCTYPE html><html><head><meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>ClaudeRGB WiFi Setup</title>
<style>body{font-family:sans-serif;max-width:400px;margin:40px auto;padding:0 20px}
h1{color:#333;font-size:1.4em}input,button,select{width:100%;padding:10px;margin:6px 0;
box-sizing:border-box;font-size:16px}button{background:#4CAF50;color:#fff;border:none;
cursor:pointer;border-radius:4px}button:disabled{background:#999}.msg{padding:10px;
margin:10px 0;border-radius:4px}.ok{background:#d4edda;color:#155724}
.err{background:#f8d7da;color:#721c24}</style></head>
<body><h1>ClaudeRGB WiFi Setup</h1>
<div id='scan'><button onclick='doScan()'>Scan WiFi Networks</button></div>
<div id='nets'></div>
<form id='fm' onsubmit='return doConnect(event)'>
<input id='ssid' placeholder='WiFi Name (SSID)' required>
<input id='pass' type='password' placeholder='WiFi Password'>
<button type='submit' id='btn'>Connect</button></form>
<div id='msg'></div>
<script>
function pickS(s){document.getElementById('ssid').value=s}
function doScan(){document.getElementById('scan').innerHTML='Scanning...';
var xhr=new XMLHttpRequest();xhr.open('GET','/wifiscan',true);xhr.timeout=10000;
xhr.onload=function(){try{var d=JSON.parse(xhr.responseText);var h='<p>Select a network:</p>';
for(var i=0;i<d.networks.length;i++){var n=d.networks[i];
h+='<button onclick="pickS(this.dataset.s)" data-s="'+n.ssid+'">'+n.ssid+' ('+n.rssi+' dBm'+(n.enc?')':', open)')+'</button>'}
document.getElementById('nets').innerHTML=h;
document.getElementById('scan').innerHTML='<button onclick="doScan()">Rescan</button>'}
catch(ex){document.getElementById('scan').innerHTML='<button onclick="doScan()">Retry</button>'}};
xhr.onerror=function(){document.getElementById('scan').innerHTML='<button onclick="doScan()">Retry</button>'};
xhr.send()}
function doConnect(e){if(e)e.preventDefault();
var ssid=document.getElementById('ssid').value;
var pass=document.getElementById('pass').value;
if(!ssid){alert('Please enter WiFi name');return false}
document.getElementById('btn').disabled=true;
document.getElementById('btn').textContent='Connecting...';
var xhr=new XMLHttpRequest();
xhr.open('POST','/wificfg',true);
xhr.setRequestHeader('Content-Type','application/json');
xhr.timeout=8000;
xhr.onload=function(){try{var d=JSON.parse(xhr.responseText);
if(d.ok){document.getElementById('msg').innerHTML='<div class="msg ok">Connected! IP: '
+d.ip+'<br>Device is restarting...</div>';document.getElementById('fm').style.display='none'}
else{document.getElementById('msg').innerHTML='<div class="msg err">'+d.error+'</div>';
document.getElementById('btn').disabled=false;document.getElementById('btn').textContent='Connect'}}
catch(ex){document.getElementById('msg').innerHTML='<div class="msg ok">Sent! Check WiFi in a few seconds.</div>'}};
xhr.onerror=function(){document.getElementById('msg').innerHTML=
'<div class="msg ok">Sent! Check WiFi in a few seconds.</div>'};
xhr.ontimeout=function(){document.getElementById('msg').innerHTML=
'<div class="msg ok">Timeout - ESP32 may be restarting. Check your WiFi.</div>'};
xhr.send(JSON.stringify({ssid:ssid,pass:pass}));
return false}
</script></body></html>)rawliteral";

const char CONTROL_PAGE[] PROGMEM = R"rawliteral(<!DOCTYPE html><html><head><meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>ClaudeRGB Control</title>
<style>body{font-family:sans-serif;max-width:400px;margin:40px auto;padding:0 20px;text-align:center}
h1{color:#333;font-size:1.4em}#status{font-size:1.1em;margin:20px 0;padding:10px;
background:#f0f0f0;border-radius:4px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}
button{padding:15px;font-size:16px;border:none;border-radius:8px;color:#fff;cursor:pointer}
.idle{background:#4CAF50}.running{background:#2196F3}.tool{background:#9C27B0}
.ask{background:#FF9800}.error{background:#F44336}.done{background:#4CAF50}
.wifi{background:#607D8B}</style></head>
<body><h1>ClaudeRGB Control</h1>
<div id='status'>State: loading...</div>
<div class='grid'>
<button class='idle' onclick="setS('idle')">Idle</button>
<button class='running' onclick="setS('running')">Running</button>
<button class='tool' onclick="setS('tool')">Tool</button>
<button class='ask' onclick="setS('ask')">Ask</button>
<button class='error' onclick="setS('error')">Error</button>
<button class='done' onclick="setS('done')">Done</button>
</div>
<button class='wifi' onclick="location.href='/wifisetup'"
style='margin-top:15px;width:100%'>WiFi Settings</button>
<script>
function setS(s){fetch('/state/'+s).then(r=>r.json()).then(d=>
{document.getElementById('status').textContent='State: '+d.state})}
fetch('/status').then(r=>r.json()).then(d=>
{document.getElementById('status').textContent='State: '+d.state})
</script></body></html>)rawliteral";

// --- HTTP request handler ---

void handleHttpClient() {
  if (!httpServer) return;

  NetworkClient client = httpServer->accept();
  if (!client) return;
  if (!client.connected()) { client.stop(); return; }

  Serial.println("[HTTP] Client connected");

  // wait for data with timeout
  unsigned long timeoutMs = millis() + 3000;
  while (!client.available() && client.connected() && millis() < timeoutMs) {
    delay(1);
  }

  if (!client.available()) {
    Serial.println("[HTTP] No data received, closing");
    client.stop();
    return;
  }

  // read the first line (request line)
  String reqLine = client.readStringUntil('\n');
  reqLine.trim();

  Serial.print("[HTTP] Request: ");
  Serial.println(reqLine);

  // skip remaining headers
  timeoutMs = millis() + 1000;
  while (client.connected() && millis() < timeoutMs) {
    String hdr = client.readStringUntil('\n');
    if (hdr == "\r" || hdr == "" || hdr.length() == 0) break;
  }

  if (reqLine.length() == 0) {
    Serial.println("[HTTP] Empty request, closing");
    client.stop();
    return;
  }

  // parse "GET /path HTTP/1.1" or "POST /path HTTP/1.1"
  int spaceIdx = reqLine.indexOf(' ');
  if (spaceIdx < 0) { client.stop(); return; }
  String method = reqLine.substring(0, spaceIdx);
  method.toUpperCase();
  String rest = reqLine.substring(spaceIdx + 1);
  int secondSpace = rest.indexOf(' ');
  String path = (secondSpace > 0) ? rest.substring(0, secondSpace) : rest;

  Serial.print("[HTTP] Method: ");
  Serial.print(method);
  Serial.print(" Path: ");
  Serial.println(path);

  // Reject non-HTTP methods (TLS handshake garbage, etc.)
  if (method != "GET" && method != "POST") {
    client.stop();
    return;
  }

  // --- Route ---

  // Captive portal: redirect common detection URLs to config page (AP mode only)
  if (isAPMode && method == "GET" &&
      (path.startsWith("/generate_204") ||
       path.startsWith("/fwlink") ||
       path.startsWith("/hotspot-detect") ||
       path.startsWith("/canonical.html") ||
       path == "/connectivity-check.html" ||
       path == "/success.txt" ||
       path == "/check-network-status.txt")) {
    Serial.print("[HTTP] Captive portal redirect: ");
    Serial.println(path);
    client.print("HTTP/1.1 302 Found\r\n");
    client.print("Location: http://192.168.4.1/\r\n");
    client.print("Connection: close\r\n");
    client.print("Content-Length: 0\r\n\r\n");
    client.flush();
    client.stop();
    return;
  }

  // GET / or /? → config page (AP mode) or control page (STA mode)
  if (method == "GET" && (path == "/" || path == "/?")) {
    if (isAPMode) {
      sendHtmlResponse(client, String(FPSTR(CONFIG_PAGE)));
    } else {
      sendHtmlResponse(client, String(FPSTR(CONTROL_PAGE)));
    }
    client.flush();
    client.stop();
    Serial.println("[HTTP] Served root page");
    return;
  }

  // GET /wifisetup → always show config page
  if (method == "GET" && path == "/wifisetup") {
    sendHtmlResponse(client, String(FPSTR(CONFIG_PAGE)));
    client.flush();
    client.stop();
    return;
  }

  // GET /state/{name}
  if (method == "GET" && path.startsWith("/state/")) {
    String name = path.substring(7);
    name.toLowerCase();
    if (name == "idle") setState(STATE_IDLE);
    else if (name == "done") setState(STATE_DONE);
    else if (name == "running") setState(STATE_RUNNING);
    else if (name == "tool") setState(STATE_TOOL);
    else if (name == "ask") setState(STATE_ASK);
    else if (name == "error") setState(STATE_ERROR);
    else {
      sendJsonResponse(client, 400, "{\"ok\":false,\"error\":\"invalid state\"}");
      client.flush();
      client.stop();
      return;
    }
    String json = "{\"ok\":true,\"state\":\"";
    json += stateName(currentState);
    json += "\"}";
    sendJsonResponse(client, 200, json);
    client.flush();
    client.stop();
    Serial.println("[HTTP] State changed to " + name);
    return;
  }

  // GET /status
  if (method == "GET" && path == "/status") {
    String json = "{\"state\":\"";
    json += stateName(currentState);
    json += "\",\"ip\":\"";
    json += (isAPMode ? WiFi.softAPIP().toString() : WiFi.localIP().toString());
    json += "\",\"mode\":\"";
    json += (isAPMode ? "AP" : "STA");
    json += "\"}";
    sendJsonResponse(client, 200, json);
    client.flush();
    client.stop();
    return;
  }

  // GET /ping
  if (method == "GET" && path == "/ping") {
    String json = "{\"pong\":true,\"state\":\"";
    json += stateName(currentState);
    json += "\"}";
    sendJsonResponse(client, 200, json);
    client.flush();
    client.stop();
    return;
  }

  // GET /wifiscan
  if (method == "GET" && path == "/wifiscan") {
    int n = WiFi.scanNetworks();
    String json = "{\"networks\":[";
    for (int i = 0; i < n && i < 15; i++) {
      if (i > 0) json += ",";
      json += "{\"ssid\":\"";
      json += WiFi.SSID(i);
      json += "\",\"rssi\":";
      json += WiFi.RSSI(i);
      json += ",\"enc\":";
      json += (WiFi.encryptionType(i) != WIFI_AUTH_OPEN) ? "true" : "false";
      json += "}";
    }
    WiFi.scanDelete();
    json += "]}";
    sendJsonResponse(client, 200, json);
    client.flush();
    client.stop();
    return;
  }

  // POST /wificfg — the ONLY POST route we accept (read body only here)
  if (method == "POST" && path == "/wificfg") {
    String body = "";
    unsigned long bodyTimeout = millis() + 2000;
    while (!client.available() && client.connected() && millis() < bodyTimeout) {
      delay(1);
    }
    if (client.available()) {
      body = client.readString();
    }
    Serial.print("[HTTP] POST body length: ");
    Serial.println(body.length());

    int ssidIdx = body.indexOf("\"ssid\"");
    int passIdx = body.indexOf("\"pass\"");
    if (ssidIdx < 0) {
      sendJsonResponse(client, 400, "{\"ok\":false,\"error\":\"missing ssid\"}");
      client.flush();
      client.stop();
      return;
    }

    int ssidValStart = body.indexOf("\"", ssidIdx + 6) + 1;
    int ssidValEnd = body.indexOf("\"", ssidValStart);
    String newSSID = body.substring(ssidValStart, ssidValEnd);

    String newPass = "";
    if (passIdx > 0) {
      int passValStart = body.indexOf("\"", passIdx + 6) + 1;
      int passValEnd = body.indexOf("\"", passValStart);
      newPass = body.substring(passValStart, passValEnd);
    }

    if (newSSID.length() == 0) {
      sendJsonResponse(client, 400, "{\"ok\":false,\"error\":\"empty ssid\"}");
      client.flush();
      client.stop();
      return;
    }

    // save and try to connect
    saveWiFiConfig(newSSID, newPass);
    wifiSSID = newSSID;
    wifiPass = newPass;

    // respond first, then restart
    String json = "{\"ok\":true,\"ip\":\"restarting\"}";
    sendJsonResponse(client, 200, json);
    client.flush();
    client.stop();
    delay(500);

    // restart to apply new WiFi config
    ESP.restart();
    return;
  }

  // Unknown POST → reject immediately (don't waste time reading body)
  if (method == "POST") {
    sendJsonResponse(client, 404, "{\"ok\":false,\"error\":\"not found\"}");
    client.flush();
    client.stop();
    return;
  }

  // AP mode: redirect any unknown path to config page (captive portal catch-all)
  if (isAPMode && method == "GET") {
    Serial.print("[HTTP] AP catch-all redirect: ");
    Serial.println(path);
    client.print("HTTP/1.1 302 Found\r\n");
    client.print("Location: http://192.168.4.1/\r\n");
    client.print("Connection: close\r\n");
    client.print("Content-Length: 0\r\n\r\n");
    client.flush();
    client.stop();
    return;
  }

  // 404 (STA mode only)
  Serial.print("[HTTP] 404 for path: ");
  Serial.println(path);
  sendJsonResponse(client, 404, "{\"ok\":false,\"error\":\"not found\"}");
  client.flush();
  client.stop();
}

// --- Serial command handler (extended) ---

void handleCommand(String cmd) {
  cmd.trim();
  if (cmd.length() == 0) return;

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

  // WIFICONFIG:SSID:PASSWORD
  if (cmd.startsWith("wificonfig:")) {
    String params = cmd.substring(11);
    int colonIdx = params.indexOf(':');
    if (colonIdx < 0) {
      Serial.println("ERR WIFICONFIG format: WIFICONFIG:SSID:PASSWORD");
      return;
    }
    String newSSID = params.substring(0, colonIdx);
    String newPass = params.substring(colonIdx + 1);
    saveWiFiConfig(newSSID, newPass);
    Serial.print("OK WiFi config saved. SSID: ");
    Serial.println(newSSID);
    Serial.println("Restarting to apply...");
    delay(500);
    ESP.restart();
    return;
  }

  // WIFICLEAR
  if (cmd == "wificlear") {
    clearWiFiConfig();
    Serial.println("OK WiFi config cleared. Restarting...");
    delay(500);
    ESP.restart();
    return;
  }

  // WIFIDIAG - run WiFi radio diagnostic scan
  if (cmd == "wifidiag") {
    diagnoseRadio();
    return;
  }

  if (cmd.startsWith("state:")) {
    cmd = cmd.substring(6);
    cmd.trim();
  }

  if (cmd == "idle") setState(STATE_IDLE);
  else if (cmd == "done") setState(STATE_DONE);
  else if (cmd == "running") setState(STATE_RUNNING);
  else if (cmd == "tool") setState(STATE_TOOL);
  else if (cmd == "ask") setState(STATE_ASK);
  else if (cmd == "error") setState(STATE_ERROR);
  else {
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
      if (inputLine.length() > 200) {
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

    case STATE_WIFI_CONFIG:
      if (now - lastEffectMs >= WIFI_CFG_INTERVAL_MS) {
        lastEffectMs = now;
        blinkOn = !blinkOn;
      }
      blinkOn ? blueOn() : allOff();
      break;

    case STATE_WIFI_CONNECTING:
      if (now - lastEffectMs >= WIFI_CONN_INTERVAL_MS) {
        lastEffectMs = now;
        blinkOn = !blinkOn;
      }
      blinkOn ? blueOn() : allOff();
      break;
  }
}

void bootFlash() {
  redOn();   delay(150); allOff(); delay(80);
  greenOn(); delay(150); allOff(); delay(80);
  blueOn();  delay(150); allOff(); delay(80);
}

void setup() {
  pinMode(RED_PIN, OUTPUT);
  pinMode(GREEN_PIN, OUTPUT);
  pinMode(BLUE_PIN, OUTPUT);

  Serial.begin(115200);

  bootFlash();

  // WiFi setup (AP config portal or STA connect)
  setupWiFi();

  // only set idle if WiFi connected (STA mode);
  // AP mode keeps STATE_WIFI_CONFIG set by startAPMode()
  if (!isAPMode) {
    setState(STATE_IDLE);
  }

  Serial.println("Claude RGB WiFi Controller Started");
  printHelp();

  if (!isAPMode) {
    Serial.print("Web control: http://");
    Serial.println(WiFi.localIP());
  }
}

void loop() {
  if (isAPMode) {
    dnsServer.processNextRequest();
  }
  handleHttpClient();
  readSerialCommands();
  updateLedEffect();
}
