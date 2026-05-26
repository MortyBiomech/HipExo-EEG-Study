#include <SPI.h>
#include "EasyCAT.h"  // Include the EasyCAT library

#define CONVST 6
#define Slave_S 8

EasyCAT EASYCAT(9);  // Create an EasyCAT object, specifying pin 9

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

  // Sending the results over serial
  for (byte i = 0; i < 8; i++) {
    Serial.print(channels[i]);
    if (i < 7) {
      Serial.print(", ");
    }
  }
  Serial.println();
}

void loop() {
  readAndPrintChannels();  // Read and print all channels
  delay(5);  // Short delay to ensure data is read frequently
}
