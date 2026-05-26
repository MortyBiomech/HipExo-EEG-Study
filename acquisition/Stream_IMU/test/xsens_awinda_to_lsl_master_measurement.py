import time
import threading
from collections import deque

import xsensdeviceapi as xda
from pylsl import StreamInfo, StreamOutlet, local_clock


# Put your MTw IDs here (from your earlier output)
MTW_IDS = ["00B4D0C2", "00B4D0D0"]

CHANNEL = 11
RATE_HZ = 100

LSL_PREFIX = "Xsens_MTw2"
LSL_TYPE   = "IMU"


class PacketBuffer(xda.XsCallback):
    def __init__(self, maxlen=16384):
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
    labels = ["qw","qx","qy","qz","ax","ay","az","gx","gy","gz","packet_counter","sample_time_fine"]
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

    pc  = float(pkt.packetCounter()) if hasattr(pkt, "packetCounter") else float("nan")
    stf = float(pkt.sampleTimeFine()) if hasattr(pkt, "sampleTimeFine") else float("nan")

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

    raise RuntimeError("Could not find/open Awinda master. Close MT Manager and retry.")


def main():
    control = xda.XsControl_construct()
    if control == 0:
        raise RuntimeError("Failed to construct XsControl")

    pi, master = open_awinda_master(control)
    master_id = master.deviceId().toXsString().upper()
    print(f"Master opened: {pi.portName()} @ {pi.baudrate()} product={master.productCode()} id={master_id}")

    cb = PacketBuffer()
    master.addCallbackHandler(cb)

    # Go config, enable radio
    print("Going to config (master)...")
    if not master.gotoConfig():
        print("WARN: master.gotoConfig() returned False (continuing)")

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

    # Try to accept connections repeatedly for a short window (MT Manager effectively does this)
    t0 = time.time()
    accept_window = 12.0
    while time.time() - t0 < accept_window:
        for did in MTW_IDS:
            try:
                master.acceptConnection(did)
            except Exception:
                pass
        time.sleep(0.2)

    print("Starting measurement on wireless master ...")
    if not master.gotoMeasurement():
        raise RuntimeError("master.gotoMeasurement() failed")

    print("\nStreaming to LSL. Open LabRecorder. Ctrl+C to stop.\n")

    outlets = {}
    last_seen = {}
    n = {}
    t_report = time.time()

    # --- rate diagnostics ---
    pc_last = {}       # last packetCounter per device
    pc_t_last = {}     # wall-clock time when last pc was recorded
    stf_last = {}      # last sampleTimeFine per device
    stf_t_last = {}    # wall-clock time when last stf was recorded
    hz_pc = {}         # computed Hz from packetCounter
    hz_stf = {}        # computed Hz from sampleTimeFine

    try:
        while True:
            item = cb.pop()
            if item is not None:
                src_id, pkt = item

                pc = pkt.packetCounter() if hasattr(pkt, "packetCounter") else None
                stf = pkt.sampleTimeFine() if hasattr(pkt, "sampleTimeFine") else None


                if src_id == master_id:
                    continue

                if src_id not in outlets:
                    outlets[src_id] = make_outlet(src_id)
                    last_seen[src_id] = 0.0
                    n[src_id] = 0
                    print(f"[NEW] LSL stream created: {LSL_PREFIX}_{src_id}")


                now = time.time()

                # --- compute Hz from packetCounter ---
                try:
                    pc = int(pkt.packetCounter())
                except Exception:
                    pc = None

                if pc is not None:
                    if src_id in pc_last:
                        dt = now - pc_t_last[src_id]
                        dpc = pc - pc_last[src_id]
                        if dt > 0.2 and dpc >= 0:   # avoid tiny dt, handle counter wrap poorly but safely
                            hz_pc[src_id] = dpc / dt
                    pc_last[src_id] = pc
                    pc_t_last[src_id] = now

                # --- compute Hz from sampleTimeFine (device clock ticks) ---
                # sampleTimeFine is typically in 0.1 ms ticks (depends on device); we still compute relative Hz from dt ticks.
                try:
                    stf = int(pkt.sampleTimeFine())
                except Exception:
                    stf = None

                if stf is not None:
                    if src_id in stf_last:
                        dtw = now - stf_t_last[src_id]
                        dstf = stf - stf_last[src_id]
                        if dtw > 0.2 and dstf > 0:
                            # Hz estimate based on "device ticks per wall second"
                            # If your ticks are 0.0001 s, then Hz ≈ (dstf*0.0001)/dtw inverted -> dtw/(dstf*0.0001)
                            # But we don’t assume tick size here; we report "ticks/sec" as well.
                            hz_stf[src_id] = dstf / dtw  # ticks per second
                    stf_last[src_id] = stf
                    stf_t_last[src_id] = now

                    

                outlets[src_id].push_sample(packet_to_sample(pkt), local_clock())
                last_seen[src_id] = time.time()
                n[src_id] += 1

            now = time.time()
            if now - t_report > 2.0:
                if not outlets:
                    print(f"[STAT] No MTw packets yet. callback_total={cb.total}")
                else:
                    for did in outlets.keys():
                        age = now - last_seen[did] if last_seen[did] else float("inf")
                        pc_hz_txt  = f"{hz_pc.get(did, float('nan')):0.2f} Hz (pc)" if did in hz_pc else "n/a (pc)"
                        stf_txt    = f"{hz_stf.get(did, float('nan')):0.1f} ticks/s (stf)" if did in hz_stf else "n/a (stf)"

                        print(f"[STAT] {did}: samples={n[did]} last_age={age:0.2f}s | {pc_hz_txt} | {stf_txt}")

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
