#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Xsens MTw2 (Awinda) -> LSL, with a Tkinter control GUI.

GUI features
------------
  * Connect / status panel  (radio, sensor accept window, per-sensor stats)
  * START / STOP broadcasting buttons  (real stream on/off: STOP destroys the
    LSL outlets -- the 7 IMU streams AND the marker stream -- so they vanish
    from the network, START re-creates them)
  * Stopwatch (starts on a Start_* marker, freezes on the matching End_* marker)
  * Event selector + Start / End buttons that push event labels to an
    'IMU_Markers' LSL stream (same idea as the GRF marker GUI)

Threading model
---------------
  main thread   : Tkinter GUI only
  connect thread: port scan, config, radio, accept window, gotoMeasurement
  worker thread : drains the Xsens callback queue and pushes samples to LSL

The Xsens callback fills a deque; the worker DRAINS the whole deque each
iteration (the old script popped a single packet per loop and then slept 1 ms,
which on Windows can easily fall behind 7 sensors x 100 Hz).
"""

import time
import queue
import threading
from collections import deque

import tkinter as tk
import tkinter.ttk as ttk

import xsensdeviceapi as xda
from pylsl import StreamInfo, StreamOutlet, local_clock


# ============================ USER SETTINGS ================================
# Leave empty to accept ALL MTw that connect.
MTW_IDS_ALLOWLIST = ["00B4D0C2", "00B4D0D0", "00B4D0C8", "00B4D0BF",
                     "00B4D0C4", "00B4D0BE", "00B4D0C5"]

PREFERRED_CHANNEL = 11          # Wireless channel (as in MT Manager)
TARGET_RATE_HZ    = 60          # MT Manager "Rate (Hz)"
ACCEPT_WINDOW_S   = 30.0        # How long to keep calling acceptConnection()

LSL_PREFIX  = "Xsens_MTw2"
LSL_TYPE    = "IMU"

MARKER_NAME = "IMU_Markers"
MARKER_UID  = "imu_markers_uid_0001"

# Optional: friendly names shown in the stats table only (stream names unchanged)
SENSOR_ALIASES = {
    # "00B4D0C8": "left thigh",
    # "00B4D0BE": "left shank",
}

# --- Events -----------------------------------------------------------------
# Labels are generated as  Start_<event>  /  End_<event>.
EVENTS = [
    "right_knee_FlxExt",
    "left_knee_FlxExt",
    "right_foot_PlanfDorsif",
    "left_foot_PlanfDorsif",
    "pelvis_FlxExt",
    "right_hip_AbdAdd",
    "left_hip_AbdAdd",
    "standing",
    "sitted_pose",
]
# ===========================================================================


def labels_for(event: str):
    """All labels are lower-case except the leading Start_/End_ and the
    movement suffix (FlxExt / PlanfDorsif / AbdAdd)."""
    return f"Start_{event}", f"End_{event}"


# --------------------------------------------------------------------------
# Xsens plumbing
# --------------------------------------------------------------------------
class PacketBuffer(xda.XsCallback):
    def __init__(self, maxlen=65536):
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

    def drain(self, max_items=4096):
        """Pop everything currently queued (bounded), oldest first."""
        out = []
        with self._lock:
            n = min(len(self._q), max_items)
            for _ in range(n):
                out.append(self._q.popleft())
        return out

    def backlog(self):
        with self._lock:
            return len(self._q)


def make_outlet(device_id_str: str):
    labels = [
        "qw", "qx", "qy", "qz",
        "ax", "ay", "az",
        "gx", "gy", "gz",
        "mx", "my", "mz",
        "packet_counter", "sample_time_fine"]
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
        pc = float(pkt.packetCounter())
    except Exception:
        pc = float("nan")

    try:
        stf = float(pkt.sampleTimeFine())
    except Exception:
        stf = float("nan")

    return [qw, qx, qy, qz,
            ax, ay, az,
            gx, gy, gz,
            mx, my, mz,
            pc, stf]


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


def try_set_master_rate(master, target_hz: int, log):
    try:
        cur = int(master.updateRate())
    except Exception:
        cur = None

    if cur == target_hz:
        log(f"Master updateRate already {target_hz} Hz.")
        return True

    log(f"Setting master updateRate {cur} -> {target_hz} Hz ...")
    try:
        ok = bool(master.setUpdateRate(target_hz))
    except Exception as e:
        log(f"[WARN] setUpdateRate({target_hz}) threw: {e}")
        ok = False

    try:
        newv = int(master.updateRate())
    except Exception:
        newv = None

    log(f"setUpdateRate returned {ok}, updateRate now = {newv}")
    return ok and (newv == target_hz)


# --------------------------------------------------------------------------
# Backend: connection + streaming worker
# --------------------------------------------------------------------------
class XsensBridge:
    def __init__(self, ui_q: queue.Queue):
        self.ui_q = ui_q
        self.control = None
        self.port_info = None
        self.master = None
        self.master_id = None

        self.cb = PacketBuffer()
        self.outlets = {}

        self.broadcast = threading.Event()      # set -> streams exist & push
        self._drop_outlets = threading.Event()  # set -> worker closes the streams
        self._stop = threading.Event()
        self._worker = None
        self._lock = threading.Lock()
        self.stats = {}                          # id -> dict
        self.connected = False

    # ---- broadcast switch ------------------------------------------------
    def set_broadcast(self, on: bool):
        """ON  -> outlets are (re)created as packets arrive and pushed to LSL.
        OFF -> outlets are destroyed, so the LSL streams really go away."""
        if on:
            self._drop_outlets.clear()
            self.broadcast.set()
        else:
            self.broadcast.clear()
            self._drop_outlets.set()

    # ---- UI messaging (thread safe: the GUI polls this queue) -------------
    def log(self, msg):
        self.ui_q.put(("log", msg))

    def status(self, msg):
        self.ui_q.put(("status", msg))

    # ---- connection ------------------------------------------------------
    def connect_async(self):
        threading.Thread(target=self._connect, daemon=True).start()

    def _connect(self):
        try:
            self.status("Constructing XsControl ...")
            self.control = xda.XsControl_construct()
            if self.control == 0:
                raise RuntimeError("Failed to construct XsControl")

            self.status("Scanning ports for the Awinda station ...")
            self.port_info, self.master = find_awinda_master(self.control)
            self.master_id = self.master.deviceId().toXsString().upper()
            self.log(f"Awinda master: {self.port_info.portName()} @ "
                     f"{self.port_info.baudrate()} product={self.master.productCode()} "
                     f"id={self.master_id}")

            self.master.addCallbackHandler(self.cb)

            self.status("Going to CONFIG ...")
            if not self.master.gotoConfig():
                self.log("[WARN] gotoConfig() returned False (continuing)")

            try:
                if self.master.isRadioEnabled():
                    self.log("Radio enabled -> disabling first ...")
                    self.master.disableRadio()
                    time.sleep(0.3)
            except Exception:
                pass

            if not try_set_master_rate(self.master, TARGET_RATE_HZ, self.log):
                self.log("[WARN] Could not confirm master updateRate; "
                         "you may stay at a lower rate.")

            self.status(f"Enabling radio on channel {PREFERRED_CHANNEL} ...")
            if not self.master.enableRadio(PREFERRED_CHANNEL):
                raise RuntimeError("enableRadio(channel) failed")

            self.log("Undock the sensors now and move them slightly.")
            t0 = time.time()
            while True:
                left = ACCEPT_WINDOW_S - (time.time() - t0)
                if left <= 0:
                    break
                self.status(f"Undock sensors & move them ... {left:0.0f} s left")
                if MTW_IDS_ALLOWLIST:
                    for did in MTW_IDS_ALLOWLIST:
                        try:
                            self.master.acceptConnection(did)
                        except Exception:
                            pass
                time.sleep(0.2)

            self.status("Starting measurement ...")
            if not self.master.gotoMeasurement():
                raise RuntimeError("gotoMeasurement() failed")

            self._worker = threading.Thread(target=self._worker_loop, daemon=True)
            self._worker.start()

            self.connected = True
            self.ui_q.put(("connected", None))
            self.log("Measurement running. Press START BROADCAST to feed LSL.")

        except Exception as e:
            self.ui_q.put(("error", str(e)))

    # ---- worker ----------------------------------------------------------
    def _worker_loop(self):
        allow = {x.upper() for x in MTW_IDS_ALLOWLIST} if MTW_IDS_ALLOWLIST else None

        while not self._stop.is_set():
            # STOP pressed -> drop the outlets here, in the thread that owns them.
            if self._drop_outlets.is_set():
                if self.outlets:
                    names = sorted(self.outlets.keys())
                    self.outlets.clear()          # refcount -> LSL streams close
                    self.ui_q.put(("log", f"[LSL] {len(names)} stream(s) closed"))
                self._drop_outlets.clear()

            items = self.cb.drain()
            if not items:
                time.sleep(0.001)
                continue

            pushing = self.broadcast.is_set()
            now = time.time()

            for src_id, pkt in items:
                if src_id == self.master_id:
                    continue
                if allow is not None and src_id not in allow:
                    continue

                # sensors show up in the table as soon as they are heard from,
                # whether or not we are broadcasting
                with self._lock:
                    if src_id not in self.stats:
                        self.stats[src_id] = dict(n=0, dropped=0, last=0.0,
                                                  pc=None, pc_t=0.0, hz_pc=float("nan"))

                if pushing:
                    # NB: never keep a StreamOutlet in a local variable -- a
                    # lingering reference keeps that stream alive after
                    # self.outlets.clear(), so it would never disappear.
                    if src_id not in self.outlets:
                        self.outlets[src_id] = make_outlet(src_id)
                        self.ui_q.put(("log", f"[LSL] stream open: {LSL_PREFIX}_{src_id}"))
                    self.outlets[src_id].push_sample(packet_to_sample(pkt), local_clock())

                try:
                    pc = int(pkt.packetCounter())
                except Exception:
                    pc = None

                with self._lock:
                    st = self.stats[src_id]
                    if pushing:
                        st["n"] += 1
                    else:
                        st["dropped"] += 1
                    st["last"] = now
                    if pc is not None:
                        if st["pc"] is not None:
                            dt = now - st["pc_t"]
                            dpc = pc - st["pc"]
                            if dt > 0.5 and dpc >= 0:
                                st["hz_pc"] = dpc / dt
                                st["pc"], st["pc_t"] = pc, now
                        else:
                            st["pc"], st["pc_t"] = pc, now

    def snapshot(self):
        with self._lock:
            return {k: dict(v) for k, v in self.stats.items()}

    # ---- shutdown --------------------------------------------------------
    def shutdown(self):
        self.broadcast.clear()
        self._stop.set()
        if self._worker is not None:
            self._worker.join(timeout=1.5)
        self.outlets.clear()

        for fn in ("gotoConfig", "disableRadio"):
            try:
                if self.master is not None:
                    getattr(self.master, fn)()
            except Exception:
                pass
        try:
            if self.control is not None and self.port_info is not None:
                self.control.closePort(self.port_info.portName())
        except Exception:
            pass
        try:
            if self.control is not None:
                self.control.close()
        except Exception:
            pass


# --------------------------------------------------------------------------
# GUI
# --------------------------------------------------------------------------
class App:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.ui_q = queue.Queue()
        self.bridge = XsensBridge(self.ui_q)

        # the marker outlet follows the broadcast switch, like the IMU streams
        self.mrk_outlet = None

        self.timer_t0 = None
        self.timer_frozen = None
        self.prev_counts = {}
        self.prev_t = time.time()

        root.title("Xsens MTw2 -> LSL  |  Marker Control")
        root.geometry("640x780")
        self._build_ui()

        root.protocol("WM_DELETE_WINDOW", self.on_close)
        self.bridge.connect_async()
        self._poll_queue()
        self._tick_timer()
        self._refresh_stats()

    # ---- layout ----------------------------------------------------------
    def _build_ui(self):
        r = self.root

        # --- status ------------------------------------------------------
        top = tk.Frame(r)
        top.pack(fill=tk.X, padx=10, pady=(10, 4))
        tk.Label(top, text="Status:", font=('Arial', 10, 'bold')).pack(side=tk.LEFT)
        self.status_var = tk.StringVar(value="starting ...")
        tk.Label(top, textvariable=self.status_var, font=('Arial', 10),
                 fg='blue', anchor='w').pack(side=tk.LEFT, padx=6)

        # --- broadcast ---------------------------------------------------
        bc = tk.LabelFrame(r, text="LSL broadcast", font=('Arial', 10, 'bold'))
        bc.pack(fill=tk.X, padx=10, pady=6)

        row = tk.Frame(bc)
        row.pack(pady=6)
        self.btn_start_bc = tk.Button(row, text="START BROADCAST", width=20,
                                      font=('Arial', 11, 'bold'),
                                      command=self.start_broadcast)
        self.btn_stop_bc = tk.Button(row, text="STOP BROADCAST", width=20,
                                     font=('Arial', 11, 'bold'), state=tk.DISABLED,
                                     command=self.stop_broadcast)
        self.btn_start_bc.pack(side=tk.LEFT, padx=6)
        self.btn_stop_bc.pack(side=tk.LEFT, padx=6)

        self.bc_var = tk.StringVar(value="● streams OFF")
        self.bc_label = tk.Label(bc, textvariable=self.bc_var,
                                 font=('Arial', 11, 'bold'), fg='gray')
        self.bc_label.pack(pady=(0, 6))

        # --- stopwatch ---------------------------------------------------
        sw = tk.LabelFrame(r, text="Stopwatch", font=('Arial', 10, 'bold'))
        sw.pack(fill=tk.X, padx=10, pady=6)

        self.timer_var = tk.StringVar(value="--:--.-")
        self.timer_label = tk.Label(sw, textvariable=self.timer_var,
                                    font=('Arial', 34, 'bold'), fg='black')
        self.timer_label.pack(pady=2)
        tk.Button(sw, text="Reset stopwatch", command=self.reset_timer).pack(pady=(0, 6))

        # --- events ------------------------------------------------------
        ev = tk.LabelFrame(r, text="Event marker", font=('Arial', 10, 'bold'))
        ev.pack(fill=tk.X, padx=10, pady=6)

        sel = tk.Frame(ev)
        sel.pack(pady=8)
        tk.Label(sel, text="Event:", font=('Arial', 12, 'bold')).pack(side=tk.LEFT, padx=(0, 8))
        self.event_var = tk.StringVar(value=EVENTS[0])
        self.event_menu = ttk.Combobox(sel, textvariable=self.event_var, values=EVENTS,
                                       state='readonly', font=('Arial', 12), width=26)
        self.event_menu.pack(side=tk.LEFT)

        btns = tk.Frame(ev)
        btns.pack(pady=(0, 6))
        self.btn_start_ev = tk.Button(btns, text="START event", width=18,
                                      font=('Arial', 11, 'bold'), state=tk.DISABLED,
                                      command=lambda: self.send_marker(True))
        self.btn_end_ev = tk.Button(btns, text="END event", width=18,
                                    font=('Arial', 11, 'bold'), state=tk.DISABLED,
                                    command=lambda: self.send_marker(False))
        self.btn_start_ev.pack(side=tk.LEFT, padx=6)
        self.btn_end_ev.pack(side=tk.LEFT, padx=6)

        self.next_var = tk.StringVar()
        tk.Label(ev, textvariable=self.next_var, font=('Arial', 9), fg='gray').pack(pady=(0, 6))
        self.event_var.trace_add('write', self.on_event_change)
        self.on_event_change()

        # --- per-sensor stats --------------------------------------------
        st = tk.LabelFrame(r, text="Sensors", font=('Arial', 10, 'bold'))
        st.pack(fill=tk.BOTH, expand=False, padx=10, pady=6)

        cols = ("sensor", "samples", "hz_arr", "hz_pc", "age")
        self.tree = ttk.Treeview(st, columns=cols, show='headings', height=7)
        for c, txt, w in zip(cols,
                             ("sensor", "samples", "Hz (arrival)", "Hz (pc)", "age [s]"),
                             (170, 90, 110, 90, 80)):
            self.tree.heading(c, text=txt)
            self.tree.column(c, width=w, anchor='center')
        self.tree.pack(fill=tk.X, padx=6, pady=6)

        # --- log ----------------------------------------------------------
        lg = tk.LabelFrame(r, text="Log", font=('Arial', 10, 'bold'))
        lg.pack(fill=tk.BOTH, expand=True, padx=10, pady=(6, 10))
        self.log_txt = tk.Text(lg, height=8, font=('Consolas', 9), state=tk.DISABLED)
        sb = tk.Scrollbar(lg, command=self.log_txt.yview)
        self.log_txt.config(yscrollcommand=sb.set)
        sb.pack(side=tk.RIGHT, fill=tk.Y)
        self.log_txt.pack(fill=tk.BOTH, expand=True)

    # ---- helpers ---------------------------------------------------------
    def log(self, msg):
        self.log_txt.config(state=tk.NORMAL)
        self.log_txt.insert(tk.END, f"{time.strftime('%H:%M:%S')}  {msg}\n")
        self.log_txt.see(tk.END)
        self.log_txt.config(state=tk.DISABLED)
        print(msg)

    def on_event_change(self, *_):
        s, e = labels_for(self.event_var.get())
        self.next_var.set(f"will send:   {s}   /   {e}")
        self.btn_start_ev.config(bg='SystemButtonFace', text="START event")
        self.btn_end_ev.config(bg='SystemButtonFace', text="END event")

    # ---- broadcast -------------------------------------------------------
    def start_broadcast(self):
        self.bridge.set_broadcast(True)

        if self.mrk_outlet is None:
            mrk_info = StreamInfo(MARKER_NAME, 'Markers', 1, 0, 'string', MARKER_UID)
            self.mrk_outlet = StreamOutlet(mrk_info)
            self.log(f"[LSL] stream open: {MARKER_NAME}")

        armed = self.bridge.connected
        self.bc_var.set("● streams ON" if armed else "● streams ON (waiting for sensors)")
        self.bc_label.config(fg='green')
        self.btn_start_bc.config(state=tk.DISABLED)
        self.btn_stop_bc.config(state=tk.NORMAL)
        self.btn_start_ev.config(state=tk.NORMAL)
        self.btn_end_ev.config(state=tk.NORMAL)
        self.log("Broadcast STARTED")

    def stop_broadcast(self):
        self.bridge.set_broadcast(False)

        if self.mrk_outlet is not None:
            self.mrk_outlet = None            # refcount -> marker stream closes
            self.log(f"[LSL] {MARKER_NAME} closed")

        self.bc_var.set("● streams OFF")
        self.bc_label.config(fg='gray')
        self.btn_start_bc.config(state=tk.NORMAL)
        self.btn_stop_bc.config(state=tk.DISABLED)
        self.btn_start_ev.config(state=tk.DISABLED)
        self.btn_end_ev.config(state=tk.DISABLED)
        self.log("Broadcast STOPPED")

    # ---- markers ---------------------------------------------------------
    def send_marker(self, is_start: bool):
        if self.mrk_outlet is None:
            self.log("[WARN] marker NOT sent: streams are OFF "
                     "(press START BROADCAST first)")
            return

        start_lbl, end_lbl = labels_for(self.event_var.get())
        label = start_lbl if is_start else end_lbl
        t = local_clock()
        self.mrk_outlet.push_sample([label], t)
        self.log(f"Marker: {label}  @ {t:.4f}")

        if is_start:
            self.btn_start_ev.config(bg='green', text="START event ✓")
            self.btn_end_ev.config(bg='SystemButtonFace', text="END event")
            self.start_timer()
        else:
            self.btn_end_ev.config(bg='red', text="END event ✓")
            self.stop_timer()


    # ---- stopwatch -------------------------------------------------------
    def start_timer(self):
        self.timer_t0 = time.time()
        self.timer_frozen = None
        self.timer_label.config(fg='green')

    def stop_timer(self):
        if self.timer_t0 is not None:
            self.timer_frozen = time.time() - self.timer_t0
        self.timer_t0 = None
        self.timer_label.config(fg='red')

    def reset_timer(self):
        self.timer_t0 = None
        self.timer_frozen = None
        self.timer_var.set("--:--.-")
        self.timer_label.config(fg='black')

    def _tick_timer(self):
        if self.timer_t0 is not None:
            el = time.time() - self.timer_t0
            self.timer_var.set(f"{int(el // 60):02d}:{int(el % 60):02d}.{int((el * 10) % 10)}")
        elif self.timer_frozen is not None:
            el = self.timer_frozen
            self.timer_var.set(f"{int(el // 60):02d}:{int(el % 60):02d}.{int((el * 10) % 10)}")
        self.root.after(100, self._tick_timer)

    # ---- periodic UI updates --------------------------------------------
    def _poll_queue(self):
        try:
            while True:
                kind, payload = self.ui_q.get_nowait()
                if kind == "log":
                    self.log(payload)
                elif kind == "status":
                    self.status_var.set(payload)
                elif kind == "connected":
                    self.status_var.set("connected — measurement running")
                    if self.bridge.broadcast.is_set():
                        self.bc_var.set("● streams ON")
                elif kind == "error":
                    self.status_var.set(f"ERROR: {payload}")
                    self.log(f"[ERROR] {payload}")
        except queue.Empty:
            pass
        self.root.after(100, self._poll_queue)

    def _refresh_stats(self):
        now = time.time()
        dt = now - self.prev_t
        snap = self.bridge.snapshot()

        for sid in sorted(snap.keys()):
            st = snap[sid]
            total = st["n"] + st["dropped"]
            d = total - self.prev_counts.get(sid, 0)
            self.prev_counts[sid] = total
            hz_arr = d / dt if dt > 0 else float('nan')
            age = now - st["last"] if st["last"] else float('inf')
            name = f"{sid}  {SENSOR_ALIASES.get(sid, '')}".strip()
            vals = (name, st["n"], f"{hz_arr:0.1f}",
                    "n/a" if st["hz_pc"] != st["hz_pc"] else f"{st['hz_pc']:0.1f}",
                    f"{age:0.2f}" if age != float('inf') else "-")
            if self.tree.exists(sid):
                self.tree.item(sid, values=vals)
            else:
                self.tree.insert('', tk.END, iid=sid, values=vals)

        self.prev_t = now
        self.root.after(1000, self._refresh_stats)

    # ---- shutdown --------------------------------------------------------
    def on_close(self):
        self.status_var.set("shutting down ...")
        self.root.update_idletasks()
        self.mrk_outlet = None
        self.bridge.shutdown()
        self.root.destroy()


def main():
    root = tk.Tk()
    App(root)
    root.mainloop()
    print("Closed.")


if __name__ == "__main__":
    main()