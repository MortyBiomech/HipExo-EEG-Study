import time
import threading
from collections import deque

import xsensdeviceapi as xda
from pylsl import StreamInfo, StreamOutlet, local_clock


CHANNEL = 11          # start with the one that works in MT Manager
RATE_HZ = 100         # match MT Manager
LSL_PREFIX = "Xsens_MTw2"
LSL_TYPE = "IMU"


class PacketBuffer(xda.XsCallback):
    def __init__(self, maxlen=16384):
        super().__init__()
        self._lock = threading.Lock()
        self._q = deque(maxlen=maxlen)
        self.total = 0

    def onLiveDataAvailable(self, dev, packet):
        # IMPORTANT: wireless MTw ID is in the packet, not necessarily in dev
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
        q = pkt.orientationQuaternion()  # numpy [w,x,y,z]
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

    # Register callback on master
    cb = PacketBuffer()
    master.addCallbackHandler(cb)

    # Put system in config, enable radio, then start measurement SYSTEM-WIDE
    print("Going to config (control)...")
    if hasattr(control, "gotoConfig"):
        control.gotoConfig()
    else:
        master.gotoConfig()

    print(f"Enabling radio on channel {CHANNEL} ...")
    try:
        if master.isRadioEnabled():
            master.disableRadio()
            time.sleep(0.2)
    except Exception:
        pass

    if not master.enableRadio(CHANNEL):
        raise RuntimeError("enableRadio(channel) failed")

    print("\nUndock sensors now, wait ~5s, then streaming should start.\n")
    time.sleep(5.0)

    print("Starting measurement (control.gotoMeasurement) ...")
    if hasattr(control, "gotoMeasurement"):
        if not control.gotoMeasurement():
            raise RuntimeError("control.gotoMeasurement() failed")
    else:
        if not master.gotoMeasurement():
            raise RuntimeError("master.gotoMeasurement() failed")

    # Stream to LSL, auto-create outlets per MTw ID
    outlets = {}
    last_seen = {}
    n = {}

    t_report = time.time()

    try:
        while True:
            item = cb.pop()
            if item is not None:
                src_id, pkt = item

                # ignore master-id packets (if any)
                if src_id == master_id:
                    continue

                if src_id not in outlets:
                    outlets[src_id] = make_outlet(src_id)
                    last_seen[src_id] = 0.0
                    n[src_id] = 0
                    print(f"[NEW] LSL stream created: {LSL_PREFIX}_{src_id}")

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
                        print(f"[STAT] {did}: samples={n[did]} last_age={age:0.2f}s")
                t_report = now

            time.sleep(0.001)

    except KeyboardInterrupt:
        print("Stopping...")

    # cleanup
    try:
        if hasattr(control, "gotoConfig"):
            control.gotoConfig()
        else:
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
