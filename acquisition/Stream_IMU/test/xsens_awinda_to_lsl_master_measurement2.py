# xsens_awinda_to_lsl_master_measurement.py
#
# Streams Xsens MTw (via Awinda Station) to Lab Streaming Layer (LSL).
# - Auto-detects the Awinda station (AW-*) by scanning ports and opening candidates
# - Enables radio on a chosen channel
# - Accepts wireless MTw connections (by MTw IDs)
# - Starts measurement on the wireless master
# - Publishes one LSL stream per MTw
# - Prints diagnostics, including ARRIVAL rate (samples/sec) per MTw
#
# Notes:
# - Set NOMINAL_SRATE = 0.0 until you have confirmed arrival is truly 100 Hz.
#   Then you can set NOMINAL_SRATE = 100.0.
# - Close Xsens MT Manager before running (it can lock the device).
#
import time
import threading
from collections import deque

import xsensdeviceapi as xda
from pylsl import StreamInfo, StreamOutlet, local_clock


# ---- User settings ----
MTW_IDS = ["00B4D0C2", "00B4D0D0"]  # your MTw device IDs (hex strings)

CHANNEL = 11                       # try 20/25/26 if needed
RATE_HZ = 100                      # target (device config); arrival rate is diagnosed below

LSL_PREFIX = "Xsens_MTw2"
LSL_TYPE   = "IMU"

# Publish LSL nominal rate:
# - Use 0.0 while debugging/when not guaranteed.
# - Set to 100.0 only once you're truly receiving 100 Hz.
NOMINAL_SRATE = 0.0

# Connection timing
ACCEPT_WINDOW_SEC = 12.0
ACCEPT_POLL_SEC   = 0.05
CONNECTIVITY_WAIT_SEC = 6.0

# ---- Helpers ----
def xsid_from_hex(hexstr: str):
    """Convert hex device-id string (e.g., '00B4D0C2') to XsDeviceId."""
    return xda.XsDeviceId(int(hexstr, 16))


class PacketBuffer(xda.XsCallback):
    """Thread-safe queue of incoming packets from XDA callback."""
    def __init__(self, maxlen=65536):
        super().__init__()
        self._lock = threading.Lock()
        self._q = deque(maxlen=maxlen)
        self.total = 0

    def onLiveDataAvailable(self, dev, packet):
        try:
            src = packet.deviceId().toXsString().upper()
        except Exception:
            try:
                src = dev.deviceId().toXsString().upper()
            except Exception:
                src = "UNKNOWN"

        with self._lock:
            # copy packet (important: XDA reuses memory)
            self._q.append((src, xda.XsDataPacket(packet)))
            self.total += 1

    def pop(self):
        with self._lock:
            if not self._q:
                return None
            return self._q.popleft()


def make_outlet(device_id_str: str):
    # Channel order/labels (you can change these, but keep consistent)
    labels = [
        "qw","qx","qy","qz",
        "ax","ay","az",
        "gx","gy","gz",
        "packet_counter","sample_time_fine"
    ]

    info = StreamInfo(
        name=f"{LSL_PREFIX}_{device_id_str}",
        type=LSL_TYPE,
        channel_count=len(labels),
        nominal_srate=float(NOMINAL_SRATE),
        channel_format="float32",
        source_id=f"{LSL_PREFIX}_{device_id_str}",
    )
    ch = info.desc().append_child("channels")
    for lab in labels:
        ch.append_child("channel").append_child_value("label", lab)

    # chunk_size=0 => push immediately
    return StreamOutlet(info, chunk_size=0, max_buffered=360)


def packet_to_sample(pkt: xda.XsDataPacket):
    # Orientation quaternion
    if pkt.containsOrientation():
        q = pkt.orientationQuaternion()
        # Xsens uses [w, x, y, z] ordering
        qw, qx, qy, qz = map(float, q[:4])
    else:
        qw = qx = qy = qz = float("nan")

    # Acceleration
    if pkt.containsCalibratedAcceleration():
        a = pkt.calibratedAcceleration()
        ax, ay, az = float(a[0]), float(a[1]), float(a[2])
    else:
        ax = ay = az = float("nan")

    # Gyroscope
    if pkt.containsCalibratedGyroscopeData():
        g = pkt.calibratedGyroscopeData()
        gx, gy, gz = float(g[0]), float(g[1]), float(g[2])
    else:
        gx = gy = gz = float("nan")

    # Timing fields (if available)
    try:
        pc = float(pkt.packetCounter())
    except Exception:
        pc = float("nan")

    try:
        stf = float(pkt.sampleTimeFine())
    except Exception:
        stf = float("nan")

    return [qw,qx,qy,qz, ax,ay,az, gx,gy,gz, pc, stf]


def open_awinda_master(control: "xda.XsControl"):
    """
    Robust Awinda detection:
    - scan ports
    - open candidates with high baudrate
    - check device.productCode() starts with 'AW-'
    """
    ports = xda.XsScanner_scanPorts()
    for i in range(ports.size()):
        pi = ports[i]

        # Awinda stations typically show high baud (2,000,000)
        if pi.baudrate() < 460800:
            continue

        if not control.openPort(pi.portName(), pi.baudrate()):
            continue

        dev = control.device(pi.deviceId())
        try:
            pc = dev.productCode()
        except Exception:
            pc = ""

        if isinstance(pc, str) and pc.upper().startswith("AW-"):
            return pi, dev

        # not Awinda -> close and continue
        control.closePort(pi.portName())

    raise RuntimeError("Could not find/open Awinda master. Close MT Manager and retry.")


def maybe_set_wireless_priority(master):
    """
    Try to set wireless priority if the API exposes it.
    We don't know the exact enum type for your binding, so we try ints.
    """
    if not hasattr(master, "setWirelessPriority"):
        return

    for cand in [3, 2, 1, 0]:
        try:
            master.setWirelessPriority(cand)
            print(f"[INFO] Wireless priority set to {cand}")
            return
        except Exception:
            continue

    print("[WARN] Could not set wireless priority (API present, but all candidates failed).")


def print_connectivity_state(master, seconds=6.0):
    """Print connectivityState repeatedly (helps mimic MT Manager timing)."""
    t0 = time.time()
    while time.time() - t0 < seconds:
        try:
            cs = master.connectivityState()
            print(f"[INFO] connectivityState={cs}")
        except Exception as e:
            print(f"[WARN] connectivityState() failed: {e}")
        #time.sleep(0.2)


def main():
    control = xda.XsControl_construct()
    if control == 0:
        raise RuntimeError("Failed to construct XsControl")

    pi, master = open_awinda_master(control)
    master_id = master.deviceId().toXsString().upper()

    try:
        prod = master.productCode()
    except Exception:
        prod = "UNKNOWN"

    print(f"Master opened: {pi.portName()} @ {pi.baudrate()} product={prod} id={master_id}")

    cb = PacketBuffer()
    master.addCallbackHandler(cb)

    # --- Configure radio (config mode) ---
    print("Going to config (master)...")
    try:
        ok = master.gotoConfig()
        if not ok:
            print("[WARN] master.gotoConfig() returned False (continuing)")
    except Exception as e:
        print(f"[WARN] gotoConfig() error: {e}")

    # Reset radio deterministically
    try:
        if master.isRadioEnabled():
            master.disableRadio()
            #time.sleep(0.5)
    except Exception:
        pass

    print(f"Enabling radio on channel {CHANNEL} ...")
    if not master.enableRadio(CHANNEL):
        raise RuntimeError("enableRadio(channel) failed")
    #time.sleep(0.5)

    # Optional: wireless priority
    maybe_set_wireless_priority(master)

    print("\nUndock sensors now and move them slightly for 5–10 seconds.\n")

    # Accept connections (use XsDeviceId objects)
    mtw_xsids = [xsid_from_hex(x) for x in MTW_IDS]
    t0 = time.time()
    while time.time() - t0 < ACCEPT_WINDOW_SEC:
        for xsid in mtw_xsids:
            try:
                master.acceptConnection(xsid)
            except Exception:
                pass
        #time.sleep(ACCEPT_POLL_SEC)

    # Let connectivity settle (like MT Manager)
    print("Waiting for MTw connections (connectivityState)...")
    print_connectivity_state(master, seconds=CONNECTIVITY_WAIT_SEC)

    # --- Start measurement on wireless master ---
    print("Starting measurement on wireless master ...")
    if not master.gotoMeasurement():
        raise RuntimeError("master.gotoMeasurement() failed")

    print("\nStreaming to LSL. Open LabRecorder. Ctrl+C to stop.\n")

    outlets = {}
    last_seen = {}
    n = {}
    t_report = time.time()

    # Arrival-rate diagnostics (samples/sec based on wall time)
    t0_arr = {}
    n0_arr = {}
    hz_arr = {}

    try:
        while True:
            item = cb.pop()
            if item is not None:
                src_id, pkt = item

                # skip packets sourced from master itself
                if src_id == master_id:
                    continue

                if src_id not in outlets:
                    outlets[src_id] = make_outlet(src_id)
                    last_seen[src_id] = 0.0
                    n[src_id] = 0
                    t0_arr[src_id] = time.time()
                    n0_arr[src_id] = 0
                    print(f"[NEW] LSL stream created: {LSL_PREFIX}_{src_id}")

                now = time.time()

                # Push sample
                outlets[src_id].push_sample(packet_to_sample(pkt), local_clock())

                # Stats
                last_seen[src_id] = now
                n[src_id] += 1

                # Arrival rate estimate
                dt = now - t0_arr[src_id]
                dn = n[src_id] - n0_arr[src_id]
                if dt >= 2.0:
                    hz_arr[src_id] = dn / dt

            now = time.time()
            if now - t_report > 2.0:
                if not outlets:
                    print(f"[STAT] No MTw packets yet. callback_total={cb.total}")
                else:
                    for did in list(outlets.keys()):
                        age = now - last_seen[did] if last_seen[did] else float("inf")
                        arr_txt = f"{hz_arr.get(did, float('nan')):0.2f} Hz (arrival)" if did in hz_arr else "warming up"
                        print(f"[STAT] {did}: samples={n[did]} last_age={age:0.2f}s | {arr_txt}")

                t_report = now

            #time.sleep(0.001)

    except KeyboardInterrupt:
        print("Stopping...")

    # --- Cleanup ---
    try:
        master.gotoConfig()
    except Exception:
        pass

    try:
        master.disableRadio()
    except Exception:
        pass

    try:
        control.closePort(pi.portName())
    except Exception:
        pass

    try:
        control.close()
    except Exception:
        pass

    print("Closed.")


if __name__ == "__main__":
    main()
