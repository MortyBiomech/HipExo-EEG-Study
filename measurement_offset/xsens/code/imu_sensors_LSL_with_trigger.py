import time
import threading
from collections import deque

import xsensdeviceapi as xda
from pylsl import StreamInfo, StreamOutlet, local_clock


# =========================
# User settings
# =========================

MTW_IDS_ALLOWLIST = [
    "00B4D0C2",
    "00B4D0D0",
    "00B4D0C8",
    "00B4D0BF",
    "00B4D0C4",
    "00B4D0BE",
    "00B4D0C5",
]

# For debugging with all connected sensors:
# MTW_IDS_ALLOWLIST = []

PREFERRED_CHANNEL = 11
TARGET_RATE_HZ = 100

LSL_PREFIX = "Xsens_MTw2"
LSL_TYPE = "IMU"

TRIGGER_STREAM_NAME = "Xsens_TriggerIn"
TRIGGER_STREAM_TYPE = "Markers"

# Increase queue length to reduce packet loss if Python processing is briefly delayed
PACKET_BUFFER_MAXLEN = 200000

# Set this to False for formal recording if terminal printing slows things down
PRINT_EACH_TRIGGER = True


# =========================
# Callback buffer
# =========================

class PacketBuffer(xda.XsCallback):
    def __init__(self, maxlen=PACKET_BUFFER_MAXLEN):
        super().__init__()
        self._lock = threading.Lock()
        self._q = deque(maxlen=maxlen)
        self.total = 0
        self.dropped = 0

    def onLiveDataAvailable(self, dev, packet):
        # Timestamp as early as possible, at callback arrival time
        arrival_time = local_clock()

        try:
            src = packet.deviceId().toXsString().upper()
        except Exception:
            src = dev.deviceId().toXsString().upper()

        with self._lock:
            if len(self._q) == self._q.maxlen:
                self.dropped += 1

            self._q.append((src, xda.XsDataPacket(packet), arrival_time))
            self.total += 1

    def pop_all(self):
        with self._lock:
            items = list(self._q)
            self._q.clear()
            return items

    def size(self):
        with self._lock:
            return len(self._q)


# =========================
# LSL outlets
# =========================

def make_outlet(device_id_str: str):
    labels = [
        "qw", "qx", "qy", "qz",
        "ax", "ay", "az",
        "gx", "gy", "gz",
        "mx", "my", "mz",
        "packet_counter", "sample_time_fine",
    ]

    info = StreamInfo(
        name=f"{LSL_PREFIX}_{device_id_str}",
        type=LSL_TYPE,
        channel_count=len(labels),
        nominal_srate=float(TARGET_RATE_HZ),
        channel_format="float32",
        source_id=f"{LSL_PREFIX}_{device_id_str}",
    )

    ch = info.desc().append_child("channels")
    for lab in labels:
        ch.append_child("channel").append_child_value("label", lab)

    return StreamOutlet(info, chunk_size=0, max_buffered=360)


def make_trigger_outlet():
    labels = [
        "line",
        "polarity",
        "trigger_timestamp",
        "frame_number",
        "lsl_arrival_time",
    ]

    info = StreamInfo(
        name=TRIGGER_STREAM_NAME,
        type=TRIGGER_STREAM_TYPE,
        channel_count=len(labels),
        nominal_srate=0,
        channel_format="float32",
        source_id="Xsens_Awinda_TriggerIn",
    )

    ch = info.desc().append_child("channels")
    for lab in labels:
        ch.append_child("channel").append_child_value("label", lab)

    return StreamOutlet(info, chunk_size=0, max_buffered=360)


# =========================
# Packet conversion
# =========================

def packet_to_sample(pkt: xda.XsDataPacket):
    if pkt.containsOrientation():
        q = pkt.orientationQuaternion()
        qw, qx, qy, qz = map(float, q[:4])
    else:
        qw = qx = qy = qz = float("nan")

    if pkt.containsCalibratedAcceleration():
        a = pkt.calibratedAcceleration()
        ax, ay, az = float(a[0]), float(a[1]), float(a[2])
    else:
        ax = ay = az = float("nan")

    if pkt.containsCalibratedGyroscopeData():
        g = pkt.calibratedGyroscopeData()
        gx, gy, gz = float(g[0]), float(g[1]), float(g[2])
    else:
        gx = gy = gz = float("nan")

    if pkt.containsCalibratedMagneticField():
        m = pkt.calibratedMagneticField()
        mx, my, mz = float(m[0]), float(m[1]), float(m[2])
    else:
        mx = my = mz = float("nan")

    try:
        pc = float(pkt.packetCounter()) if pkt.containsPacketCounter() else float("nan")
    except Exception:
        pc = float("nan")

    try:
        stf = float(pkt.sampleTimeFine())
    except Exception:
        stf = float("nan")

    return [
        qw, qx, qy, qz,
        ax, ay, az,
        gx, gy, gz,
        mx, my, mz,
        pc, stf,
    ]


# =========================
# Trigger reading helpers
# =========================

def read_attr_or_method(obj, names, default=float("nan")):
    for name in names:
        try:
            value = getattr(obj, name)
            if callable(value):
                value = value()
            return float(value)
        except Exception:
            pass
    return default


def get_trigger_data(pkt, trigger_id):
    try:
        if not pkt.containsTriggerIndication(trigger_id):
            return None
    except Exception:
        return None

    try:
        trig = pkt.triggerIndication(trigger_id)
    except Exception:
        return None

    polarity = read_attr_or_method(
        trig,
        ["polarity", "m_polarity"],
    )

    timestamp = read_attr_or_method(
        trig,
        ["timestamp", "m_timestamp"],
    )

    frame_number = read_attr_or_method(
        trig,
        ["frameNumber", "frame_number", "m_frameNumber"],
    )

    return polarity, timestamp, frame_number


def get_trigger_ids():
    trigger_ids = []

    try:
        trigger_ids.append((1, xda.XDI_TriggerIn1))
    except Exception:
        trigger_ids.append((1, 0x4810))

    try:
        trigger_ids.append((2, xda.XDI_TriggerIn2))
    except Exception:
        trigger_ids.append((2, 0x4820))

    return trigger_ids


# =========================
# Awinda setup helpers
# =========================

def find_awinda_master(control: "xda.XsControl"):
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

    raise RuntimeError("No Awinda station found. Close MT Manager completely and retry.")


def try_set_master_rate(master, target_hz: int) -> bool:
    try:
        cur = int(master.updateRate())
    except Exception:
        cur = None

    try:
        supported = [
            int(master.supportedUpdateRates()[i])
            for i in range(master.supportedUpdateRates().size())
        ]
    except Exception:
        supported = []

    print(f"Master current updateRate = {cur}", flush=True)

    if supported:
        print(f"Master supportedUpdateRates = {supported}", flush=True)
    else:
        print("Master supportedUpdateRates = (could not read)", flush=True)

    if cur == target_hz:
        print(f"Master updateRate already {target_hz} Hz.", flush=True)
        return True

    print(f"Setting master updateRate -> {target_hz} Hz ...", flush=True)

    try:
        ok = bool(master.setUpdateRate(target_hz))
    except Exception as e:
        print(f"[WARN] master.setUpdateRate({target_hz}) threw: {e}", flush=True)
        ok = False

    try:
        newv = int(master.updateRate())
    except Exception:
        newv = None

    print(f"master.setUpdateRate returned {ok}, master.updateRate now = {newv}", flush=True)

    return ok and (newv == target_hz)


# =========================
# Main
# =========================

def main():
    control = xda.XsControl_construct()

    if control == 0:
        raise RuntimeError("Failed to construct XsControl")

    pi, master = find_awinda_master(control)
    master_id = master.deviceId().toXsString().upper()

    print(
        f"Awinda master opened: {pi.portName()} @ {pi.baudrate()} "
        f"product={master.productCode()} id={master_id}",
        flush=True,
    )

    cb = PacketBuffer()
    master.addCallbackHandler(cb)

    print("Going to CONFIG...", flush=True)

    if not master.gotoConfig():
        print("[WARN] master.gotoConfig() returned False (continuing)", flush=True)

    try:
        if master.isRadioEnabled():
            print("Radio is enabled -> disabling radio first...", flush=True)
            master.disableRadio()
            time.sleep(0.3)
    except Exception:
        pass

    rate_ok = try_set_master_rate(master, TARGET_RATE_HZ)

    if not rate_ok:
        print("[WARN] Could not confirm master updateRate set to target.", flush=True)

    print(f"Enabling radio on channel {PREFERRED_CHANNEL} ...", flush=True)

    if not master.enableRadio(PREFERRED_CHANNEL):
        raise RuntimeError("enableRadio(channel) failed")

    print("\nUndock sensors now and move them slightly for 25-30 seconds.\n", flush=True)

    t0 = time.time()
    accept_window = 30.0

    while time.time() - t0 < accept_window:
        if MTW_IDS_ALLOWLIST:
            for did in MTW_IDS_ALLOWLIST:
                try:
                    master.acceptConnection(did)
                except Exception:
                    pass
        time.sleep(0.2)

    print("Starting measurement on wireless master ...", flush=True)

    if not master.gotoMeasurement():
        raise RuntimeError("master.gotoMeasurement() failed")

    print("\nStreaming to LSL. Open LabRecorder. Ctrl+C to stop.\n", flush=True)

    outlets = {}
    last_seen = {}
    n_samples = {}

    trigger_outlet = make_trigger_outlet()
    seen_triggers = set()
    trigger_ids = get_trigger_ids()
    trigger_count = 0

    print(f"[NEW] LSL trigger stream created: {TRIGGER_STREAM_NAME}", flush=True)

    last_report_t = time.time()
    last_report_n = {}

    pc_last = {}
    pc_t_last = {}
    hz_pc = {}

    allowlist_upper = [x.upper() for x in MTW_IDS_ALLOWLIST]

    try:
        while True:
            items = cb.pop_all()

            if not items:
                time.sleep(0.001)
                continue

            for src_id, pkt, arrival_time in items:

                # ---------------------------------------------------------
                # Check Trigger In BEFORE ignoring master packets.
                # Trigger indications may be stored in Awinda master packets.
                # ---------------------------------------------------------
                for line_num, trig_id in trigger_ids:
                    trig_data = get_trigger_data(pkt, trig_id)

                    if trig_data is not None:
                        polarity, trig_timestamp, frame_number = trig_data

                        # Use callback arrival time, not delayed main-loop time
                        lsl_t = arrival_time

                        key = (
                            int(line_num),
                            int(frame_number) if frame_number == frame_number else -1,
                            int(trig_timestamp) if trig_timestamp == trig_timestamp else -1,
                        )

                        if key not in seen_triggers:
                            seen_triggers.add(key)
                            trigger_count += 1

                            trigger_outlet.push_sample(
                                [
                                    float(line_num),
                                    float(polarity),
                                    float(trig_timestamp),
                                    float(frame_number),
                                    float(lsl_t),
                                ],
                                timestamp=lsl_t,
                            )

                            if PRINT_EACH_TRIGGER:
                                print(
                                    f"[TRIGGER] #{trigger_count} In{line_num}: "
                                    f"polarity={polarity}, "
                                    f"timestamp={trig_timestamp}, "
                                    f"frame={frame_number}, "
                                    f"lsl_arrival={lsl_t:.6f}",
                                    flush=True,
                                )

                # Master packets are not IMU sensor packets.
                # We check them for trigger first, then skip IMU output.
                if src_id == master_id:
                    continue

                if MTW_IDS_ALLOWLIST and src_id not in allowlist_upper:
                    continue

                if src_id not in outlets:
                    outlets[src_id] = make_outlet(src_id)
                    last_seen[src_id] = 0.0
                    n_samples[src_id] = 0
                    last_report_n[src_id] = 0

                    print(f"[NEW] LSL stream created: {LSL_PREFIX}_{src_id}", flush=True)

                # Use callback arrival time for IMU samples as well
                outlets[src_id].push_sample(packet_to_sample(pkt), timestamp=arrival_time)

                now = time.time()
                last_seen[src_id] = now
                n_samples[src_id] += 1

                pc = None

                try:
                    if pkt.containsPacketCounter():
                        pc = int(pkt.packetCounter())
                except Exception:
                    pc = None

                if pc is not None:
                    if src_id in pc_last:
                        dt_pc = now - pc_t_last[src_id]
                        dpc = pc - pc_last[src_id]

                        if dpc > 0 and dt_pc > 0:
                            hz_pc[src_id] = dpc / dt_pc

                    pc_last[src_id] = pc
                    pc_t_last[src_id] = now

            # Report after each processed batch, at most every 2 seconds
            now = time.time()

            if now - last_report_t >= 2.0:
                qsize = cb.size()

                if not outlets:
                    print(
                        f"[STAT] No MTw packets yet. "
                        f"callback_total={cb.total}, queue={qsize}, "
                        f"dropped={cb.dropped}, triggers_sent={trigger_count}",
                        flush=True,
                    )
                else:
                    print(
                        f"[STAT] callback_total={cb.total}, queue={qsize}, "
                        f"dropped={cb.dropped}, triggers_sent={trigger_count}",
                        flush=True,
                    )

                    for did in outlets.keys():
                        dt = now - last_report_t
                        dn = n_samples[did] - last_report_n.get(did, 0)
                        arrival_hz = dn / dt if dt > 0 else float("nan")

                        age = now - last_seen[did] if last_seen[did] else float("inf")

                        if did in hz_pc:
                            pc_hz_txt = f"{hz_pc[did]:0.2f} Hz (pc)"
                        else:
                            pc_hz_txt = "n/a (pc)"

                        print(
                            f"[STAT] {did}: samples={n_samples[did]} "
                            f"last_age={age:0.2f}s | "
                            f"{arrival_hz:0.2f} Hz (arrival) | "
                            f"{pc_hz_txt}",
                            flush=True,
                        )

                        last_report_n[did] = n_samples[did]

                last_report_t = now

    except KeyboardInterrupt:
        print("Stopping...", flush=True)

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

    print("Closed.", flush=True)


if __name__ == "__main__":
    main()