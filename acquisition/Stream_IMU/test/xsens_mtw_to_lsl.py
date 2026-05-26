import time
import threading
from collections import deque

import xsensdeviceapi as xda
from pylsl import StreamInfo, StreamOutlet, local_clock


# ---- YOUR MTw IDs (paired sensors) ----
MTW_IDS = ["00B4D0C2", "00B4D0D0"]   # add more if needed

# ---- Channel scan range ----
CHANNEL_CANDIDATES = list(range(11, 26))
WAIT_FOR_MTW_SECONDS = 4.0

RATE_HZ = 100
LSL_PREFIX = "Xsens_MTw2"
LSL_TYPE = "IMU"


class PacketBuffer(xda.XsCallback):
    def __init__(self, maxlen=4096):
        super().__init__()
        self._lock = threading.Lock()
        self._q = deque(maxlen=maxlen)

    def onLiveDataAvailable(self, dev, packet):
        with self._lock:
            self._q.append(xda.XsDataPacket(packet))

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
        q = pkt.orientationQuaternion()     # numpy [w,x,y,z] in your binding
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


def list_device_id_strings(control):
    arr = control.deviceIds()
    return [arr[i].toXsString().upper() for i in range(arr.size())]


def accept_known_mtw(master, mtw_ids):
    # Try string form first (works with your binding for enableRadio channel)
    for did in mtw_ids:
        try:
            master.acceptConnection(did)
        except Exception:
            pass


def wait_until_mtw_present(control, mtw_ids, timeout_s):
    t0 = time.time()
    while time.time() - t0 < timeout_s:
        ids = set(list_device_id_strings(control))
        if all(d in ids for d in mtw_ids):
            return True
        time.sleep(0.1)
    return False


def configure_and_start_mtw(dev):
    # configure outputs then start measurement
    dev.gotoConfig()

    cfg = xda.XsOutputConfigurationArray()
    cfg.push_back(xda.XsOutputConfiguration(xda.XDI_PacketCounter, 0))
    cfg.push_back(xda.XsOutputConfiguration(xda.XDI_SampleTimeFine, 0))
    cfg.push_back(xda.XsOutputConfiguration(xda.XDI_Quaternion, RATE_HZ))
    cfg.push_back(xda.XsOutputConfiguration(xda.XDI_Acceleration, RATE_HZ))
    cfg.push_back(xda.XsOutputConfiguration(xda.XDI_RateOfTurn, RATE_HZ))

    if not dev.setOutputConfiguration(cfg):
        raise RuntimeError("setOutputConfiguration failed")

    if not dev.gotoMeasurement():
        raise RuntimeError("gotoMeasurement failed")


def main():
    control = xda.XsControl_construct()
    pi, master = open_awinda_master(control)

    master_id = master.deviceId().toXsString().upper()
    print(f"Master opened: {pi.portName()} @ {pi.baudrate()} product={master.productCode()} id={master_id}")

    master.gotoConfig()

    print("\nUndock sensors now and keep them near the station.\n")

    locked_channel = None

    for ch in CHANNEL_CANDIDATES:
        # reset radio state
        try:
            if master.isRadioEnabled():
                master.disableRadio()
                time.sleep(0.2)
        except Exception:
            pass

        print(f"Trying channel {ch} ...")
        if not master.enableRadio(ch):
            print("  enableRadio failed")
            continue

        if not master.gotoMeasurement():
            print("  master gotoMeasurement failed")
            continue

        # Key difference: accept known MTw connections, then wait for them to show up as devices
        accept_known_mtw(master, MTW_IDS)
        ok = wait_until_mtw_present(control, MTW_IDS, WAIT_FOR_MTW_SECONDS)

        if ok:
            locked_channel = ch
            print(f"✅ Locked channel {ch}: MTw devices present: {MTW_IDS}")
            break
        else:
            print("  MTw not present on this channel.")

    if locked_channel is None:
        raise RuntimeError("Could not bring MTw online on any channel. Check pairing/battery/distance/interference.")

    # Attach callbacks + LSL outlets to MTw devices (NOT the master)
    devices = {}
    for did_str in MTW_IDS:
        did_arr = control.deviceIds()
        did_obj = None
        for i in range(did_arr.size()):
            if did_arr[i].toXsString().upper() == did_str:
                did_obj = did_arr[i]
                break
        if did_obj is None:
            raise RuntimeError(f"MTw {did_str} disappeared unexpectedly")

        dev = control.device(did_obj)
        cb = PacketBuffer()
        dev.addCallbackHandler(cb)

        configure_and_start_mtw(dev)

        outlet = make_outlet(did_str)
        devices[did_str] = {"dev": dev, "cb": cb, "outlet": outlet, "n": 0, "last": 0.0}
        print(f"Streaming {did_str} -> LSL {LSL_PREFIX}_{did_str}")

    print("\nNow record in LabRecorder. Ctrl+C to stop.\n")
    t_report = time.time()

    try:
        while True:
            now = time.time()
            for did_str, obj in devices.items():
                pkt = obj["cb"].pop()
                if pkt is None:
                    continue
                obj["outlet"].push_sample(packet_to_sample(pkt), local_clock())
                obj["n"] += 1
                obj["last"] = now

            if now - t_report > 2.0:
                for did_str, obj in devices.items():
                    age = now - obj["last"] if obj["last"] else float("inf")
                    print(f"[STAT] {did_str}: samples={obj['n']} last_age={age:0.2f}s (channel={locked_channel})")
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
        if master.isRadioEnabled():
            master.disableRadio()
    except Exception:
        pass

    control.closePort(pi.portName())
    control.close()
    print("Closed.")


if __name__ == "__main__":
    main()
