import xsensdeviceapi as xda

control = xda.XsControl_construct()
assert control != 0

ports = xda.XsScanner_scanPorts()
print(f"Found {ports.size()} ports\n")

for i in range(ports.size()):
    p = ports[i]
    did = p.deviceId()
    print(f"[{i}] port={p.portName()} baud={p.baudrate()} id={did.toXsString()} "
          f"isMti={did.isMti()} isMtig={did.isMtig()}")

# close control
control.close()
