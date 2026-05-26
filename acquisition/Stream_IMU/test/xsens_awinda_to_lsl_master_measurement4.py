import time
import threading
from collections import deque

import xsensdeviceapi as xda
from pylsl import StreamInfo, StreamOutlet, local_clock


# ========================= USER SETTINGS =========================
MTW_IDS = ["00B4D0C2", "00B4D0D0"]   # MTw device IDs
RATE_HZ = 100                       # desired rate
CHANNEL = 11                        # radio channel (use what MT Manager shows)

LSL_PREFIX = "Xsens_MTw2"
LSL_TYPE   = "IMU"

ACCEPT_WINDOW_S = 12.0              # keep accepting connections
WAIT_FOR_HANDLES_S = 20.0           # wait for MTw handles in XDA
PRINT_PACKET_CAPS_N = 10            # print packet capabilities for first N packets per MTw
# ================================================================


class PacketBuffer(xda.XsCallback):
    def __init__(self, maxlen=32768):
        super().__init__()
        self._lock = threading.Lock()
        self._q = deque(maxlen=maxlen)
        self.total = 0

    def onLiveDataAvailable(self, dev, packet):
        try:
            src = packet.deviceId().toXsString().upper()
        except Exception:
            src = dev.deviceId().toXsString().upper()

        with self._lock:
            self._q.append((src, xda.XsDataPacket(packet)))
            self.total += 1

    def pop(self):
        with self._lock:
            if not self._q:
                return None
            return self._q.popleft()


def make_outlet(device_id_str: str):
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
        nominal_srate=float(RATE_HZ),
        channel_format="float32",
        source_id=f"{LSL_PREFIX}_{device_id_str}",
    )
    ch = info.desc().append_child("channels")
    for lab in labels:
        ch.append_child("channel").append_child_value("label", lab)
    return StreamOutlet(info, chunk_size=0, max_buffered=360)


def packet_to_sample(pkt: xda.XsDataPacket):
    # Quaternion
    if pkt.containsOrientation():
        q = pkt.orientationQuaternion()
        qw, qx, qy, qz = map(float, q[:4])
    else:
        qw = qx = qy = qz = float("nan")

    # Acc
    if pkt.containsCalibratedAcceleration():
        a = pkt.calibratedAcceleration()
        ax, ay, az = float(a[0]), float(a[1]), float(a[2])
    else:
        ax = ay = az = float("nan")

    # Gyro
    if pkt.containsCalibratedGyroscopeData():
        g = pkt.calibratedGyroscopeData()
        gx, gy, gz = float(g[0]), float(g[1]), float(g[2])
    else:
        gx = gy = gz = float("nan")

    # Counters (may not exist unless output config includes them)
    try:
        pc = float(pkt.packetCounter())
    except Exception:
        pc = float("nan")

    try:
        stf = float(pkt.sampleTimeFine())
    except Exception:
        stf = float("nan")

    return [qw,qx,qy,qz, ax,ay,az, gx,gy,gz, pc, stf]


def open_awinda_master(control):
    ports = xda.XsScanner_scanPorts()
    for i in range(ports.size()):
        pi = ports[i]
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

        control.closePort(pi.portName())

    raise RuntimeError("No Awinda station found. Close MT Manager and retry.")


def get_device_handle_by_id(control, did_str: str):
    did_str = did_str.upper()
    if not hasattr(control, "deviceIds"):
        return None
    arr = control.deviceIds()
    for i in range(arr.size()):
        if arr[i].toXsString().upper() == did_str:
            return control.device(arr[i])
    return None


def force_mtw_output_config(mtw_dev):
    """
    Force exactly the output we want.
    IMPORTANT: This must be called AFTER the MTw device handle is available.
    """
    if not mtw_dev.gotoConfig():
        pass

    cfg = xda.XsOutputConfigurationArray()

    # timestamps/counters
    cfg.push_back(xda.XsOutputConfiguration(xda.XDI_PacketCounter, 0))
    cfg.push_back(xda.XsOutputConfiguration(xda.XDI_SampleTimeFine, 0))

    # 100 Hz motion data
    cfg.push_back(xda.XsOutputConfiguration(xda.XDI_Quaternion, RATE_HZ))
    cfg.push_back(xda.XsOutputConfiguration(xda.XDI_Acceleration, RATE_HZ))
    cfg.push_back(xda.XsOutputConfiguration(xda.XDI_RateOfTurn, RATE_HZ))

    ok = mtw_dev.setOutputConfiguration(cfg)
    if not ok:
        raise RuntimeError(f"setOutputConfiguration failed for {mtw_dev.deviceId().toXsString().upper()}")


def main():
    control = xda.XsControl_construct()
    if control == 0:
        raise RuntimeError("Failed to construct XsControl")

    pi, master = open_awinda_master(control)
    master_id = master.deviceId().toXsString().upper()
    print(f"Master opened: {pi.portName()} @ {pi.baudrate()} product={master.productCode()} id={master_id}")

    cb = PacketBuffer()
    master.addCallbackHandler(cb)

    # config + radio
    print("Going to config (master)...")
    master.gotoConfig()

    try:
        if master.isRadioEnabled():
            master.disableRadio()
            time.sleep(0.2)
    except Exception:
        pass

    print(f"Enabling radio on channel {CHANNEL} ...")
    if not master.enableRadio(CHANNEL):
        raise RuntimeError("enableRadio(channel) failed")

    print("\nUndock sensors now and move them slightly for 5–10 seconds.\n")

    # Accept connections repeatedly (like MT Manager)
    t0 = time.time()
    while time.time() - t0 < ACCEPT_WINDOW_S:
        for did in MTW_IDS:
            try:
                master.acceptConnection(did)
            except Exception:
                pass
        time.sleep(0.2)

    # Wait for MTw device handles then force output config
    print("Waiting for MTw device handles in XDA, then forcing output config...")
    t0 = time.time()
    configured = set()
    while time.time() - t0 < WAIT_FOR_HANDLES_S and len(configured) < len(MTW_IDS):
        for did in MTW_IDS:
            if did.upper() in configured:
                continue
            dev = get_device_handle_by_id(control, did)
            if dev is None:
                continue
            print(f"Found MTw handle for {did}. Forcing output config to {RATE_HZ} Hz + counters...")
            force_mtw_output_config(dev)
            configured.add(did.upper())
        time.sleep(0.2)

    if not configured:
        print("WARN: Could not obtain MTw handles in XDA. Output config not forced.")
    else:
        print("Configured MTw devices:", sorted(configured))

    # Start measurement (equivalent to MT Manager’s start measurement)
    print("Starting measurement on wireless master ...")
    if not master.gotoMeasurement():
        raise RuntimeError("master.gotoMeasurement() failed")

    print("\nStreaming to LSL. Open LabRecorder. Ctrl+C to stop.\n")

    outlets = {}
    n = {}
    last_t = {}
    last_n = {}
    hz_arrival = {}

    # capability print counters
    caps_printed = {}

    try:
        while True:
            item = cb.pop()
            if item is not None:
                src_id, pkt = item

                if src_id == master_id:
                    continue

                if src_id not in outlets:
                    outlets[src_id] = make_outlet(src_id)
                    n[src_id] = 0
                    last_t[src_id] = time.time()
                    last_n[src_id] = 0
                    caps_printed[src_id] = 0
                    print(f"[NEW] LSL stream created: {LSL_PREFIX}_{src_id}")

                # print what is actually present in the packet (first few packets)
                if caps_printed[src_id] < PRINT_PACKET_CAPS_N:
                    caps_printed[src_id] += 1
                    has_q  = pkt.containsOrientation()
                    has_a  = pkt.containsCalibratedAcceleration()
                    has_g  = pkt.containsCalibratedGyroscopeData()

                    # counters may throw if not present in this mode
                    try:
                        _ = pkt.packetCounter()
                        has_pc = True
                    except Exception:
                        has_pc = False
                    try:
                        _ = pkt.sampleTimeFine()
                        has_stf = True
                    except Exception:
                        has_stf = False

                    print(f"[PKT] {src_id}: q={has_q} acc={has_a} gyro={has_g} pc={has_pc} stf={has_stf}")

                outlets[src_id].push_sample(packet_to_sample(pkt), local_clock())
                n[src_id] += 1

            now = time.time()
            # stats every 2 seconds
            if outlets and (now - min(last_t.values())) > 2.0:
                for did in list(outlets.keys()):
                    dt = now - last_t[did]
                    dn = n[did] - last_n[did]
                    if dt > 0:
                        hz_arrival[did] = dn / dt
                    last_t[did] = now
                    last_n[did] = n[did]
                    print(f"[STAT] {did}: samples={n[did]} | {hz_arrival.get(did, float('nan')):0.2f} Hz (arrival)")
                time.sleep(0.01)

            time.sleep(0.001)

    except KeyboardInterrupt:
        print("Stopping...")

    try:
        master.gotoConfig()
    except Exception:
        pass
    try:
        master.disableRadio()
    except Exception:
        pass

    control.closePort(pi.portName())
    control.close()
    print("Closed.")


if __name__ == "__main__":
    main()
