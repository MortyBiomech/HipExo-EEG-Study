const int TRIG_PIN = 46;    
const int PULSE_MS = 100;
const int INTERVAL_MS = 500;

void setup() {
  pinMode(TRIG_PIN, OUTPUT);
  digitalWrite(TRIG_PIN, HIGH);
  Serial.begin(115200);
  Serial.println("Active-low TTL trigger test started.");
}

void loop() {
  digitalWrite(TRIG_PIN, LOW);
  Serial.println("Trigger LOW");

  delay(PULSE_MS);

  digitalWrite(TRIG_PIN, HIGH);
  Serial.println("Back HIGH");

  delay(INTERVAL_MS);
}