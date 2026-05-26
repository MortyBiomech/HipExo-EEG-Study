import time
import xsensdeviceapi as xda

MASTER_ID = "01200CEF"

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
    return None, None

def dump_obj_methods(obj, substrings=("device", "mtw", "port", "id", "state", "wire")):
    ms = sorted([m for m in dir(obj) if any(s in m.lower() for s in substrings)])
    for m in ms:
        print(" ", m)

def main():
    control = xda.XsControl_construct()
    pi, master = open_awinda_master(control)
    if master is None:
        raise RuntimeError("Awinda master not found. Close MT Manager and retry.")

    print(f"Master: {pi.portName()} baud={pi.baudrate()} product={master.productCode()} id={master.deviceId().toXsString()}")
    master.gotoConfig()

    ch = 11
    try:
        rc = int(master.radioChannel())
        if rc > 0:
            ch = rc
    except Exception:
        pass

    print(f"Enabling radio on channel {ch} ...")
    master.enableRadio(ch)

    print("\nUndock sensors now. I will print connectivityState() 10 times.\n")

    for k in range(10):
        cs = master.connectivityState()
        print(f"\n--- connectivityState sample {k+1} ---")
        print("type:", type(cs))
        print("dir (filtered):")
        dump_obj_methods(cs)

        # also try plain print
        try:
            print("cs str:", str(cs))
        except Exception:
            pass

        time.sleep(1.0)

    print("\nDone. Ctrl+C if stuck.")
    # cleanup
    try:
        master.disableRadio()
    except Exception:
        pass
    control.closePort(pi.portName())
    control.close()

if __name__ == "__main__":
    main()
