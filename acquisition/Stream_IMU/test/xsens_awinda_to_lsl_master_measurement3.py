import time
import threading
from collections import deque
import math

import xsensdeviceapi as xda
from pylsl import StreamInfo, StreamOutlet, local_clock


# ========================= USER SETTINGS =========================
MTW_IDS = ["00B4D0C2", "00B4D0D0"]   # your MTw device IDs

RATE_HZ = 100                       # desired output rate
DEFAULT_CHANNEL = 11                # used if channel cannot be read
FORCE_CHANNEL = None                # set to an int (e.g., 11) to force, or None

ACCEPT_WINDOW_S = 12.0              # how long to keep accepting MTw connections
CONNECT_WAIT_S  = 15.0              # wait for MTw device handles to appear in XDA

LSL_PREFIX = "Xsens_MTw2"
LSL_TYPE   = "IMU"
# ================================================================


# ------------------------ Callback buffer ------------------------
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
            # copy packet NOW
            self._q.append((src, xda.XsDataPacket(packet)))
            self.total += 1

    def pop(self):
        with self._lock:
            if not self._q:
                return None
            return self._q.popleft()


# ------------------------ LSL helpers ------------------------
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
        nominal_srate=float(RATE_HZ),    # metadata only
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

    # Counters
    try:
        pc = float(pkt.packetCounter())
    except Exception:
        pc = float("nan")

    try:
        stf = float(pkt.sampleTimeFine())
    except Exception:
        stf = float("nan")

    return [qw,qx,qy,qz, ax,ay,az, gx,gy,gz, pc, stf]


# ------------------------ Xsens helpers ------------------------
def open_awinda_master(control: "xda.XsControl"):
    ports = xda.XsScanner_scanPorts()
    for i in range(ports.size()):
        pi = ports[i]
        # Awinda uses high baud (you saw 2,000,000)
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

    raise RuntimeError(
        "No Awinda station found. Make sure MT Manager is CLOSED, then replug the station and retry."
    )


def try_get_radio_channel(master: "xda.XsDevice"):
    # Some bindings expose radioChannel()
    if hasattr(master, "radioChannel"):
        try:
            ch = master.radioChannel()
            if isinstance(ch, int) and ch >= 0:
                return ch
        except Exception:
            pass
    return None


def ensure_radio(master: "xda.XsDevice", channel: int):
    # config mode
    if not master.gotoConfig():
        # some versions return False even if it actually works
        pass

    # reset radio if already enabled
    try:
        if master.isRadioEnabled():
            master.disableRadio()
            time.sleep(0.2)
    except Exception:
        pass

    if not master.enableRadio(channel):
        raise RuntimeError(f"enableRadio({channel}) failed")


def accept_mtw_connections(master: "xda.XsDevice", mtw_ids, seconds: float):
    t0 = time.time()
    while time.time() - t0 < seconds:
        for did in mtw_ids:
            try:
                master.acceptConnection(did)
            except Exception:
                pass
        time.sleep(0.2)


def get_control_device_id_strings(control: "xda.XsControl"):
    """
    Return list of device-id strings known to XDA control.
    Different SDK versions expose slightly different methods.
    """
    for attr in ("deviceIds", "mainDeviceIds"):
        if hasattr(control, attr):
            arr = getattr(control, attr)()
            out = []
            for i in range(arr.size()):
                out.append(arr[i].toXsString().upper())
            return out
    return []


def get_device_handle_by_id(control: "xda.XsControl", did_str: str):
    did_str = did_str.upper()
    for attr in ("deviceIds", "mainDeviceIds"):
        if hasattr(control, attr):
            arr = getattr(control, attr)()
            for i in range(arr.size()):
                if arr[i].toXsString().upper() == did_str:
                    return control.device(arr[i])
    return None


def configure_mtw_output_100hz(mtw: "xda.XsDevice"):
    """
    Force MTw output config to 100 Hz:
    - Quaternion
    - Acceleration
    - Rate of Turn
    - PacketCounter, SampleTimeFine
    """
    if not mtw.gotoConfig():
        pass

    cfg = xda.XsOutputConfigurationArray()

    # Timestamp / counters
    cfg.push_back(xda.XsOutputConfiguration(xda.XDI_PacketCounter, 0))
    cfg.push_back(xda.XsOutputConfiguration(xda.XDI_SampleTimeFine, 0))

    # Motion data at RATE_HZ
    cfg.push_back(xda.XsOutputConfiguration(xda.XDI_Quaternion, RATE_HZ))
    cfg.push_back(xda.XsOutputConfiguration(xda.XDI_Acceleration, RATE_HZ))
    cfg.push_back(xda.XsOutputConfiguration(xda.XDI_RateOfTurn, RATE_HZ))

    ok = mtw.setOutputConfiguration(cfg)
    if not ok:
        raise RuntimeError(f"setOutputConfiguration failed for {mtw.deviceId().toXsString().upper()}")


# ------------------------ Main ------------------------
def main():
    control = xda.XsControl_construct()
    if control == 0:
        raise RuntimeError("Failed to construct XsControl")

    pi, master = open_awinda_master(control)
    master_id = master.deviceId().toXsString().upper()
    print(f"Awinda master opened: {pi.portName()} @ {pi.baudrate()} product={master.productCode()} id={master_id}")

    # callback
    cb = PacketBuffer()
    master.addCallbackHandler(cb)

    # channel
    ch = FORCE_CHANNEL
    if ch is None:
        ch = try_get_radio_channel(master)
    if ch is None:
        ch = DEFAULT_CHANNEL
    print(f"Using radio channel: {ch}")

    # enable radio
    ensure_radio(master, ch)

    print("\nUndock sensors now and move them slightly for 5–10 seconds.\n")
    accept_mtw_connections(master, MTW_IDS, ACCEPT_WINDOW_S)

    # wait for MTw device handles to appear, then configure 100 Hz output
    print("Waiting for MTw devices to appear in XDA control...")
    t0 = time.time()
    seen = set()
    while time.time() - t0 < CONNECT_WAIT_S and len(seen) < len(MTW_IDS):
        ids_now = set(get_control_device_id_strings(control))
        for did in MTW_IDS:
            if did.upper() in ids_now:
                seen.add(did.upper())
        time.sleep(0.1)

    if not seen:
        print("WARN: MTw device handles not visible in control yet. Proceeding without forcing output config.")
    else:
        print(f"XDA sees MTw IDs: {sorted(seen)}")
        for did in sorted(seen):
            dev = get_device_handle_by_id(control, did)
            if dev is None:
                print(f"WARN: Could not get handle for MTw {did}, skipping config.")
                continue
            print(f"Configuring MTw {did} output to {RATE_HZ} Hz...")
            configure_mtw_output_100hz(dev)

    # Start measurement (this is the MT Manager button)
    print("Starting measurement on wireless master ...")
    if not master.gotoMeasurement():
        raise RuntimeError("master.gotoMeasurement() failed")

    print("\nStreaming to LSL. Open LabRecorder. Ctrl+C to stop.\n")

    outlets = {}
    last_seen = {}
    n = {}

    # arrival Hz diagnostics
    last_n = {}
    last_t = {}
    hz_arrival = {}

    # packetCounter diagnostics
    pc_last = {}
    pc_t_last = {}
    hz_pc = {}

    # sampleTimeFine diagnostics (ticks per second)
    stf_last = {}
    stf_t_last = {}
    stf_tps = {}

    t_report = time.time()

    try:
        while True:
            item = cb.pop()
            if item is not None:
                src_id, pkt = item

                # ignore master packets
                if src_id == master_id:
                    continue

                if src_id not in outlets:
                    outlets[src_id] = make_outlet(src_id)
                    last_seen[src_id] = 0.0
                    n[src_id] = 0
                    last_n[src_id] = 0
                    last_t[src_id] = time.time()
                    print(f"[NEW] LSL stream created: {LSL_PREFIX}_{src_id}")

                now = time.time()

                # packetCounter rate
                try:
                    pc = int(pkt.packetCounter())
                except Exception:
                    pc = None

                if pc is not None:
                    if src_id in pc_last:
                        dt = now - pc_t_last[src_id]
                        dpc = pc - pc_last[src_id]
                        if dpc < 0:
                            # attempt 16-bit wrap
                            dpc16 = (pc + 65536) - pc_last[src_id]
                            if dpc16 > 0:
                                dpc = dpc16
                        if dt > 0.3 and dpc > 0:
                            hz_pc[src_id] = dpc / dt
                    pc_last[src_id] = pc
                    pc_t_last[src_id] = now

                # sampleTimeFine ticks/sec
                try:
                    stf = int(pkt.sampleTimeFine())
                except Exception:
                    stf = None

                if stf is not None:
                    if src_id in stf_last:
                        dt = now - stf_t_last[src_id]
                        dstf = stf - stf_last[src_id]
                        if dstf < 0:
                            # unknown wrap; ignore
                            dstf = None
                        if dt > 0.3 and dstf is not None and dstf > 0:
                            stf_tps[src_id] = dstf / dt
                    stf_last[src_id] = stf
                    stf_t_last[src_id] = now

                # push to LSL
                outlets[src_id].push_sample(packet_to_sample(pkt), local_clock())

                last_seen[src_id] = now
                n[src_id] += 1

            now = time.time()
            if now - t_report > 2.0:
                if not outlets:
                    print(f"[STAT] No MTw packets yet. callback_total={cb.total}")
                else:
                    for did in list(outlets.keys()):
                        age = now - last_seen[did] if last_seen[did] else float("inf")

                        # arrival Hz over last window
                        dt = now - last_t[did]
                        dn = n[did] - last_n[did]
                        if dt > 0:
                            hz_arrival[did] = dn / dt
                        last_t[did] = now
                        last_n[did] = n[did]

                        arr_txt = f"{hz_arrival.get(did, float('nan')):0.2f} Hz (arrival)"
                        pc_txt  = f"{hz_pc.get(did, float('nan')):0.2f} Hz (pc)" if did in hz_pc else "n/a (pc)"
                        stf_txt = f"{stf_tps.get(did, float('nan')):0.1f} ticks/s (stf)" if did in stf_tps else "n/a (stf)"

                        print(f"[STAT] {did}: samples={n[did]} last_age={age:0.2f}s | {arr_txt} | {pc_txt} | {stf_txt}")

                t_report = now

            time.sleep(0.001)

    except KeyboardInterrupt:
        print("Stopping...")

    # cleanup
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
