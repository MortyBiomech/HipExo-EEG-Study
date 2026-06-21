import time
import serial
from pylsl import StreamInfo, StreamOutlet, local_clock

ARDUINO_PORT = "COM5"
BAUDRATE = 115200

info = StreamInfo(
    name="Arduino_TTL_Markers",
    type="Markers",
    channel_count=1,
    nominal_srate=0,
    channel_format="int32",
    source_id="arduino_ttl_markers_001"
)

outlet = StreamOutlet(info)

ser = serial.Serial(ARDUINO_PORT, BAUDRATE, timeout=1)
time.sleep(2.0)

print("Arduino-to-LSL started.")

trigger_count = 0

try:
    while True:
        line = ser.readline().decode("utf-8", errors="ignore").strip()

        if not line:
            continue

        print("Serial:", line)

        if line == "Trigger LOW":
            trigger_count += 1
            t = local_clock()
            outlet.push_sample([trigger_count], timestamp=t)
            print(f"[LSL] marker {trigger_count} at {t:.6f}")

except KeyboardInterrupt:
    print("Stopping...")

finally:
    ser.close()