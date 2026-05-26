import xsensdeviceapi as xda

def open_awinda_master(control):
    ports = xda.XsScanner_scanPorts()

    for i in range(ports.size()):
        pi = ports[i]
        # Awinda station usually has a high baudrate (e.g., 2,000,000)
        if pi.baudrate() < 460800:
            continue

        port = pi.portName()
        baud = pi.baudrate()

        if not control.openPort(port, baud):
            continue

        dev = control.device(pi.deviceId())

        try:
            pc = dev.productCode()
        except Exception:
            pc = ""

        # Awinda master product codes start with "AW-" (yours is AW-A2)
        if isinstance(pc, str) and pc.upper().startswith("AW-"):
            return pi, dev

        control.closePort(port)

    return None, None


def main():
    control = xda.XsControl_construct()
    if control == 0:
        raise RuntimeError("Failed to construct XsControl")

    pi, master = open_awinda_master(control)
    if master is None:
        raise RuntimeError("Could not find/open Awinda master. Close MT Manager and retry.")

    master_id = master.deviceId().toXsString()
    try:
        pc = master.productCode()
    except Exception:
        pc = "N/A"

    print(f"Awinda master found:")
    print(f"  port       : {pi.portName()}")
    print(f"  baudrate   : {pi.baudrate()}")
    print(f"  productCode: {pc}")
    print(f"  deviceId   : {master_id}")

    print("\nMethods containing 'connect' or 'radio':")
    methods = sorted([m for m in dir(master) if ("connect" in m.lower() or "radio" in m.lower())])
    for m in methods:
        print(" ", m)

    # cleanup
    try:
        control.closePort(pi.portName())
    except Exception:
        pass
    try:
        control.close()
    except Exception:
        pass


if __name__ == "__main__":
    main()
