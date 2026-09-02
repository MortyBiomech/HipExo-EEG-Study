import serial
import time
from pylsl import StreamInfo, StreamOutlet

#read_from_arduino(serial_port='/dev/ttyACM0', baud_rate=1000000, timeout=1):
def read_from_arduino(serial_port='COM11', baud_rate=1000000, timeout=1):
    """
    Reads data from the Arduino via the specified serial port.
    
    Parameters:
    - serial_port: The port to which the Arduino is connected (e.g., '/dev/ttyACM0').
    - baud_rate: The baud rate for the serial communication (must match the Arduino code).
    - timeout: Read timeout value in seconds.
    
    Returns:
    - ser: The serial object.
    """
    try:
        # Open the serial port
        ser = serial.Serial(serial_port, baud_rate, timeout=timeout)
        print(f"Connected to Arduino on port {serial_port} at {baud_rate} baud")

        # Allow time for the connection to establish
        time.sleep(2)

        return ser

    except serial.SerialException as e:
        print(f"Error: {e}")
        return None

def parse_data(line):
    """
    Parses a line of data from the Arduino.
    """
    channels = [0] * 8
    try:
        parts = line.split(", ")
        if len(parts) == 8:
            channels = [int(part) for part in parts]
    except (ValueError, IndexError) as e:
        print(f"Parsing error: {e}")
    return channels

def main():
    # serial_port = '/dev/ttyACM0'
    serial_port = 'COM11'
    baud_rate = 1000000
    chunk_size = 50  # Number of samples to collect before sending as a chunk

    ser = read_from_arduino(serial_port=serial_port, baud_rate=baud_rate)
    if ser is None:
        return

    # Create LSL stream info and outlet for 8 channels
    info = StreamInfo('GRF', 'Force', 8, 200, 'int32', 'myuid34234')
    outlet = StreamOutlet(info)

    chunk = []

    while True:
        line = ser.readline().decode('latin-1').strip()
        if line:
            channels = parse_data(line)
            print(f"Channels: {channels}")

            # Collect data in chunks
            chunk.append(channels)

            if len(chunk) >= chunk_size:
                # Send the collected chunk to LSL
                outlet.push_chunk(chunk)
                print(f"Sent chunk of {len(chunk)} samples")

                # Clear the chunk list for the next batch
                chunk = []

if __name__ == "__main__":
    main()
