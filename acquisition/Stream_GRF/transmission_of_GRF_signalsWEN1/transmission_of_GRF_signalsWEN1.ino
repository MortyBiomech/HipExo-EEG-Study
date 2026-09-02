#include <SPI.h>
#include "EasyCAT.h"  // Include the EasyCAT library

#define CONVST 6
#define Slave_S 8

// Sampling period in microseconds. 6667 us -> 149.99 Hz, effectively the
// intended 150 Hz. The loop is paced with micros() instead of delay(5), so
// the rate no longer depends on code-path overhead (the old delay(5) loop
// actually ran at ~153.3 Hz = 5 ms + ~1.5 ms of ADC/serial time).
#define PERIOD_US 6667UL

EasyCAT EASYCAT(9);  // Create an EasyCAT object, specifying pin 9

uint32_t sample_n = 0;        // sample counter, first field of every line
uint32_t next_t   = 0;        // next scheduled sample time, micros()

void setup() {
  Serial.begin(1000000);  // Initialize serial communication at 1000000 baud

  SPI.begin();
  SPI.setClockDivider(SPI_CLOCK_DIV2);  // Set for 8MHz SPI
  SPI.setBitOrder(MSBFIRST);  // Set SPI bit order
  SPI.setDataMode(SPI_MODE0);  // Set SPI mode

  pinMode(CONVST, OUTPUT);  // Set CONVST as an output pin
  pinMode(Slave_S, OUTPUT);  // Set Slave_S as an output pin

  digitalWrite(CONVST, LOW);  // Set CONVST low by default
  digitalWrite(Slave_S, HIGH);  // Deselect the ADC initially

  // Initialize EasyCAT
  if (EASYCAT.Init() == true) {
    Serial.println("EasyCAT initialized successfully");
    pinMode(13, OUTPUT);  // Set the onboard LED pin as output
    digitalWrite(13, HIGH);  // Turn on the onboard LED
  } else {
    Serial.println("EasyCAT initialization failed");
    pinMode(13, OUTPUT);  // Set the onboard LED pin as output
    while (1) {
      digitalWrite(13, LOW);  // Blink the onboard LED to indicate failure
      delay(500);
      digitalWrite(13, HIGH);
      delay(500);
    }
  }

  Serial.println("Setup complete. Starting to read data...");
  next_t = micros() + PERIOD_US;
}

uint16_t readChannel(byte channel) {
  byte commandByte = 0b10001000 | (channel << 4);  // Construct command byte for the specified channel
  byte highByte = 0;
  byte lowByte = 0;
  uint16_t data = 0;

  digitalWrite(CONVST, HIGH);  // Start conversion
  delayMicroseconds(2);  // Ensure the minimum conversion start time
  digitalWrite(CONVST, LOW);  // Stop conversion
  delayMicroseconds(4);  // Ensure the minimum conversion hold time

  digitalWrite(Slave_S, LOW);  // Select the ADC
  delayMicroseconds(1);  // Small delay to allow settling
  highByte = SPI.transfer(commandByte);  // Send command byte and receive high byte
  lowByte = SPI.transfer(0x00);  // Send filler byte and receive low byte
  digitalWrite(Slave_S, HIGH);  // Deselect the ADC

  data = (highByte << 8) | lowByte;  // Combine high and low byte

  return data;  // Return the combined data
}

void readAndPrintChannels() {
  uint16_t channels[8];

  // Read all 8 channels
  for (byte i = 0; i < 8; i++) {
    channels[i] = readChannel(i);
  }

  // Line format: ch1, ..., ch8, counter  (9 comma-separated fields).
  // The counter is the LAST field, so the force channels keep their
  // familiar 1..8 positions (same indices as the old 8-channel format).
  // The counter is the device-side timebase: downstream rebuilds the time
  // axis from it exactly like the IMU packet counter, so LSL timestamp
  // quality only affects the anchoring regression, never the rate.
  for (byte i = 0; i < 8; i++) {
    Serial.print(channels[i]);
    Serial.print(", ");
  }
  Serial.print(sample_n++);
  Serial.println();
}

void loop() {
  // Constant-rate pacing: wait until the scheduled instant, then sample.
  // Overflow-safe comparison (micros() wraps every ~71 minutes).
  while ((int32_t)(micros() - next_t) < 0) { /* wait */ }
  next_t += PERIOD_US;
  readAndPrintChannels();
}
