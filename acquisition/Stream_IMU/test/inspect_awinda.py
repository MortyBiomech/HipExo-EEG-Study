import xsensdeviceapi as xda

MASTER_ID_HEX = "01200CEF"  # your station id from scanPorts

control = xda.XsControl_construct()
ports = xda.XsScanner_scanPorts()

master_pi = None
for i in range(ports.size()):
    pi = ports[i]
    if pi.deviceId().toXsString().upper() == MASTER_ID_HEX:
        master_pi = pi
        break

if master_pi is None:
    raise RuntimeError("Awinda Station not found by scanPorts. Close MT Manager and retry.")

print("Master port:", master_pi.portName(), "baud:", master_pi.baudrate(), "id:", master_pi.deviceId().toXsString())

if not control.openPort(master_pi.portName(), master_pi.baudrate()):
    raise RuntimeError("Failed to open Awinda Station port.")

master = control.device(master_pi.deviceId())
print("Master productCode:", master.productCode() if hasattr(master, "productCode") else "N/A")
print("Master deviceId:", master.deviceId().toXsString())

# List wireless-related methods exposed by the Python binding
methods = [m for m in dir(master) if any(k in m.lower() for k in ["wire", "mtw", "awinda", "radio", "connect", "pair", "discover"])]
print("\nWireless-related methods:")
for m in methods:
    print(" ", m)

control.close()
