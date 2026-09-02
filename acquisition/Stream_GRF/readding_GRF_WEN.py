import serial
import time
from pylsl import StreamInfo, StreamOutlet, local_clock

#
# Fixes relative to the original simple bridge:
#   1. per-sample push with an explicit local_clock() timestamp.
#      The original pushed 50-sample chunks WITHOUT timestamps, so LSL
#      fabricated the sample times from the nominal rate (which was set
#      to 200 Hz against a true ~150 Hz - a 23% compressed timebase).
#   2. ser.reset_input_buffer() after the 2 s boot wait. Opening the port
#      resets the Arduino (DTR); everything that piles up in the OS serial
#      buffer during the wait is stale and, if not flushed, gets drained
#      in a burst with near-identical timestamps (the +2..3 s "head
#      anomaly" measured in old recordings).
#   3. malformed lines are SKIPPED (parse_data returns None), never pushed
#      as fake all-zero samples - the Arduino's setup() text lines used to
#      enter the stream as zeros.
#   4. no per-sample print. A console write per sample (150/s) on Windows
#      can be slower than the sample period and silently throttles the
#      reader below the producer rate - unbounded backlog. A low-rate
#      heartbeat (every 10 s) replaces it.
#   5. nine channels at the honest nominal rate (the micros()-paced
#      firmware runs at ~150.0 Hz).
#
# The blocking readline in the main thread is the GOOD part of the simple
# bridge and is kept: consumption is driven by data arrival, and with no
# GUI sharing this thread there is nothing to steal the cadence.
# =========================================================================

N_FIELDS = 9        # 8 force channels + trailing counter


def read_from_arduino(serial_port='COM11', baud_rate=1_000_000, timeout=1):
    """Open the serial port, wait out the Arduino DTR reset, flush the
    stale boot backlog, and return the serial object (or None)."""
    try:
        ser = serial.Serial(serial_port, baud_rate, timeout=timeout)
        print(f"Connected to Arduino on port {serial_port} at {baud_rate} baud")
        time.sleep(2)              # Arduino reboots on port open
        ser.reset_input_buffer()   # discard everything that piled up
        return ser
    except serial.SerialException as e:
        print(f"Error: {e}")
        return None


def parse_data(line):
    """Return a list of N_FIELDS ints, or None for anything malformed.

    Malformed lines (Arduino setup() text, serial glitches) are skipped
    by the caller - never pushed as fake all-zero samples."""
    parts = line.split(", ")
    if len(parts) != N_FIELDS:
        return None
    try:
        return [int(p) for p in parts]
    except (ValueError, IndexError):
        return None


def main():
    serial_port = 'COM11'
    baud_rate   = 1_000_000

    ser = read_from_arduino(serial_port=serial_port, baud_rate=baud_rate)
    if ser is None:
        return

    # ONE stream, NINE channels: [ch1..ch8, counter]. 150.0 matches the
    # micros()-paced firmware; with the counter in the stream this is
    # metadata only.
    info   = StreamInfo('GRF', 'Force', N_FIELDS, 150.0, 'int32', 'myuid34234')
    outlet = StreamOutlet(info)

    n_sent  = 0
    n_bad   = 0
    t_beat  = time.time()

    print("Streaming... Ctrl+C to stop.")
    try:
        while True:
            line = ser.readline().decode('latin-1').strip()
            if not line:
                continue
            t        = local_clock()          # stamp at arrival, per sample
            channels = parse_data(line)
            if channels is None:
                n_bad += 1
                continue
            outlet.push_sample(channels, t)   # one in, one stamp, one out
            n_sent += 1

            # low-rate heartbeat: cheap, and confirms the bridge is alive
            now = time.time()
            if now - t_beat >= 10.0:
                print(f"[bridge] {n_sent} samples sent, {n_bad} bad lines skipped")
                t_beat = now
    except KeyboardInterrupt:
        pass
    finally:
        ser.close()
        print(f"Stopped. {n_sent} samples sent, {n_bad} bad lines skipped.")


if __name__ == "__main__":
    main()