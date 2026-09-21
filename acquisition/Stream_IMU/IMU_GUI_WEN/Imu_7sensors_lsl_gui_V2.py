#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Xsens MTw2 (Awinda) -> LSL, with a Tkinter control GUI.
RETRANSMISSION-ENABLED BUILD (recorded-data path).

WHY THIS BUILD EXISTS
---------------------
The Awinda protocol can RE-TRANSMIT packets that were lost on the radio:
every MTw keeps a 1024-sample buffer and re-sends missed samples in the
spare retransmission slots (MTw Awinda User Manual MW0502P rev. L, sec.
6.6.6 + Table 1). But the manual is explicit that this only happens in
the RECORDING state (sec. 6.6, state table: "Recording - Any missed data
packets are retransmitted in this state, provided that the update rate
is less than maximum"). The previous bridge only called gotoMeasurement()
and pushed the LIVE callback to LSL, so it never entered Recording:
retransmission was never active, and every radio loss became a permanent
hole in the XDF.

This build:
  * enters Recording on START BROADCAST (createLogFile + startRecording);
    the .mtb log file doubles as a native, complete backup of the session;
  * pushes the RECORDED-data callback to LSL. XDA delivers that stream in
    order and INCLUDING retransmitted packets (it is the stream MT Manager
    writes to .mtb) - so the XDF itself becomes complete, no post-hoc
    merge needed;
  * keeps the LIVE callback running for two jobs only: the GUI health
    stats, and TIMESTAMPING (next section);
  * falls back automatically to the old live-push behaviour if the
    recorded path produces nothing within PROBE_S seconds (e.g. an SDK
    build whose recorded callback is named differently) - never worse
    than the previous bridge.

TIMESTAMPS - WHY THEY ARE NOT TAKEN AT PUSH TIME
------------------------------------------------
The recorded path lags the live path by the retransmission latency, and
that lag varies. Stamping recorded packets with local_clock() at push
time would add a VARIABLE offset between the IMU streams and every other
LSL stream (EMG, GRF, markers) - an alignment error the analysis pipeline
could not observe or remove. Instead each recorded packet is stamped with
the LIVE arrival time of the SAME packet counter:
  * packets that also arrived live (the vast majority) get exactly the
    stamp the old bridge would have given them (now taken in the XDA
    callback rather than in the worker loop: ~1 ms earlier, i.e. closer
    to true arrival - far below one 60 Hz sample);
  * packets recovered by retransmission (never seen live) get the stamp of
    the nearest live-stamped counter shifted by (counter delta)/rate, so
    they sit on the same counter-vs-time line the pipeline loader fits.
The recorded-path delay itself is shown per sensor in the GUI ("lag").

STOP / FLUSH
------------
After stopRecording() the MTws still flush their buffers. The IMU outlets
stay open and keep pushing until the flush is complete (or FLUSH_TIMEOUT_S),
then the log file is closed and the outlets dropped. WORKFLOW: press STOP
BROADCAST, wait for "streams OFF", THEN stop LabRecorder - otherwise the
tail of the recording (up to one 'lag' worth) is not in the XDF.

GUI features
------------
  * Connect / status panel (radio, sensor accept window, per-sensor stats)
  * START / STOP broadcasting (STOP destroys the LSL outlets after the
    flush - the 7 IMU streams AND the marker stream vanish from the net)
  * Stopwatch (starts on a *_Start marker, freezes on the matching *_End)
  * Event selector + Start / End buttons -> 'IMU_Markers' LSL stream
  * Per-sensor table: pushed, Hz (live), recovered (= packets saved by
    retransmission), lag (recorded-path delay), RSSI (2 s mean, dBm),
    battery (%), age. Rows turn red on low battery.

RSSI AND BATTERY (radio / power health, never touch the data path)
------------------------------------------------------------------
  * RSSI: the received signal strength the Awinda master measured for
    each MTw packet (manual sec. 6.12: "advised to use this to check what
    the signal strength was during measurements"). Read from every LIVE
    packet (XsDataPacket.rssi()) and shown as a sliding RSSI_WIN_S mean.
    Use it to compare channels and to spot badly placed sensors.
  * Battery: requested from every MTw each BATTERY_POLL_S
    (XsDevice.requestBatteryLevel(); the answer arrives through
    onInfoResponse with XIR_BatteryLevel, read via batteryLevel()). The
    manual gives ~6 h runtime (depends on rate and temperature) and a
    quick-triple-pulse LED at low battery; the GUI warns at
    BATTERY_WARN_PCT.
  Both are XDA SDK calls (not documented in the MTw user manual itself);
  if this SDK build does not provide them the column shows 'n/a' and
  nothing else changes.
  A battery level of 0 is treated as NO ANSWER, never as a reading: 0 is
  what batteryLevel() returns before any response has arrived, and an MTw
  that is transmitting cannot be at 0 % (it shuts down first). Reading the
  cache right after the request - as the first version did - showed that
  default 0 for fully charged sensors.

Threading model
---------------
  main thread   : Tkinter GUI only
  connect thread: port scan, config, radio, accept window, gotoMeasurement
  XDA thread    : callbacks -> two deques (live, recorded), nothing else
  worker thread : mode machine (start/stop recording), drains both deques,
                  stamps and pushes to LSL
"""

import os
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

PREFERRED_CHANNEL = 20        # Radio channel. 20 = 2450 MHz, the gap between
                              # WiFi channels 6 and 11, full TX power (manual
                              # sec. 6.6.2 suggests 11/15/20/25; 25 sits at the
                              # band edge, where TX power is cut - short range).
TARGET_RATE_HZ    = 60        # MUST be a legal Awinda rate (checked at connect
                              # against the station's own list). Keep it BELOW
                              # the maximum for your MTw count (7 MTw -> max 100,
                              # manual Table 1): at the maximum there are no
                              # retransmission slots.
ACCEPT_WINDOW_S   = 10.0      # How long to keep calling acceptConnection()

USE_RECORDED_PATH = True      # True: Recording state + recorded callback ->
                              # LSL (retransmission ON). False: old behaviour
                              # (live callback -> LSL, no retransmission).
MTB_DIR           = "mtb_backup"   # .mtb log files (native complete backup)
PROBE_S           = 8.0       # recorded path must deliver within this, else
                              # automatic fallback to live push
FLUSH_TIMEOUT_S   = 20.0      # hard cap on the post-stop flush wait
LAG_WARN_S        = 3.0       # warn if the recorded path lags more than this
NEIGHBOR_SEARCH   = 600       # counters searched (+-) to stamp a recovered
                              # packet from its nearest live neighbour

RSSI_WIN_S        = 2.0       # RSSI shown as the mean over this sliding window
BATTERY_POLL_S    = 60.0      # battery request interval (tiny downlink message)
BATTERY_READ_DELAY_S = 3.0    # cached level is read this long AFTER a request
                              # (the answer travels over the radio first)
BATTERY_WARN_PCT  = 20        # row turns red + one log warning below this

LSL_PREFIX  = "Xsens_MTw2"
LSL_TYPE    = "IMU"

MARKER_NAME = "IMU_Markers"
MARKER_UID  = "imu_markers_uid_0001"

# Optional: friendly names shown in the stats table only (stream names unchanged)
SENSOR_ALIASES = {
    # "00B4D0C8": "left thigh",
    # "00B4D0BE": "left shank",
}

# Manual Table 1: maximum update rate per number of MTws. At the maximum
# the retransmission slots are gone (sec. 6.6.6 NOTE), so the connect
# step warns when TARGET_RATE_HZ reaches it.
AWINDA_MAX_RATE = [(5, 120), (9, 100), (10, 80), (20, 60), (32, 40)]

# --- Events -----------------------------------------------------------------
# Labels are generated as  <event>_Start  /  <event>_End.
# Order below is the intended running order of the session.
EVENTS = [
    # reference / posture
    "rest_seated",
    # limb circling
    "right_leg_circling",
    "left_leg_circling",
    "right_foot_circling",
    "left_foot_circling",
    # hip
    "right_hip_FlxExt",
    "right_hip_AbdAdd",
    "left_hip_FlxExt",
    "left_hip_AbdAdd",
    "pelvis_motion",
    # exoskeleton assistance modes
    "NoExoPre_walking",
    "Eco_walking",
    "Aqua_walking",
    "Aquaplus_walking",
    "Sport_walking",
    "Boost_walking",
    "Transparent_walking",
    "NoExoPost_walking",
    # trial / closing
    "Pre_standing",
    "Post_standing",
]
# ===========================================================================


def labels_for(event: str):
    """<event>_Start / <event>_End - the event name leads, the phase
    trails, so the two labels of a pair can never disagree on spelling
    AND alphabetical sorting groups each event's pair together."""
    return f"{event}_Start", f"{event}_End"


def cdiff(a: int, b: int) -> int:
    """Signed difference a - b of two 16-bit wrapping packet counters."""
    return ((a - b + 32768) % 65536) - 32768


# --------------------------------------------------------------------------
# Xsens plumbing
# --------------------------------------------------------------------------
class PacketBuffer(xda.XsCallback):
    """XDA callbacks -> two deques. Runs on the XDA thread, so it does the
    minimum: timestamp, counter, (copy of) the packet, append. The packet
    object handed to a callback is only valid during the call, hence the
    XsDataPacket copy wherever the payload is needed later."""

    def __init__(self, maxlen=65536):
        super().__init__()
        self._lock = threading.Lock()
        self._live = deque(maxlen=maxlen)
        self._rec = deque(maxlen=maxlen)
        # The worker sets this False when live payloads are not needed
        # (REC / FLUSH / IDLE): the live path then only carries counter +
        # arrival time (+ RSSI), which is all the stamping needs.
        self.keep_live_packets = True
        self.battery = {}               # MTw id -> last reported level (%)

    @staticmethod
    def _src(dev, packet):
        try:
            return packet.deviceId().toXsString().upper()
        except Exception:
            return dev.deviceId().toXsString().upper()

    @staticmethod
    def _pc(packet):
        try:
            return int(packet.packetCounter())
        except Exception:
            return None

    @staticmethod
    def _rssi(packet):
        # dBm as measured by the master. Values outside (-127, 0) are not
        # real receptions (unknown / placeholder) and are ignored.
        try:
            if hasattr(packet, "containsRssi") and not packet.containsRssi():
                return None
            r = int(packet.rssi())
            return r if -127 < r < 0 else None
        except Exception:
            return None

    def onLiveDataAvailable(self, dev, packet):
        t = local_clock()                      # arrival stamp, taken first
        src = self._src(dev, packet)
        pc = self._pc(packet)
        rssi = self._rssi(packet)
        pkt = xda.XsDataPacket(packet) if self.keep_live_packets else None
        with self._lock:
            self._live.append((src, pc, t, pkt, rssi))

    def onInfoResponse(self, dev, request):
        # Battery answer to requestBatteryLevel(). Anything unexpected here
        # must never propagate into the XDA thread.
        try:
            if request == getattr(xda, "XIR_BatteryLevel", object()):
                lvl = int(dev.batteryLevel())
                if 0 < lvl <= 100:                 # 0 = no answer, see header
                    with self._lock:
                        self.battery[dev.deviceId().toXsString().upper()] = lvl
        except Exception:
            pass

    def battery_snapshot(self):
        with self._lock:
            return dict(self.battery)

    def onRecordedDataAvailable(self, dev, packet):
        t = local_clock()
        src = self._src(dev, packet)
        pc = self._pc(packet)
        pkt = xda.XsDataPacket(packet)
        with self._lock:
            self._rec.append((src, pc, t, pkt))

    def _drain(self, dq, max_items):
        out = []
        with self._lock:
            n = min(len(dq), max_items)
            for _ in range(n):
                out.append(dq.popleft())
        return out

    def drain_live(self, max_items=4096):
        return self._drain(self._live, max_items)

    def drain_rec(self, max_items=4096):
        return self._drain(self._rec, max_items)

    def rec_backlog(self):
        with self._lock:
            return len(self._rec)


def make_outlet(device_id_str: str, rate_hz: float):
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
        nominal_srate=float(rate_hz),
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


def supported_rates(master):
    """The station's own list of legal update rates, or None if this SDK
    build does not expose it (then the read-back check below still runs)."""
    for args in ((getattr(xda, "XDI_None", 0),), ()):
        try:
            arr = master.supportedUpdateRates(*args)
            return sorted({int(arr[i]) for i in range(arr.size())}, reverse=True)
        except Exception:
            continue
    return None


def try_set_master_rate(master, target_hz: int, log):
    legal = supported_rates(master)
    if legal:
        log(f"Legal Awinda update rates: {legal}")
        if target_hz not in legal:
            raise RuntimeError(
                f"TARGET_RATE_HZ = {target_hz} is not a legal Awinda rate. "
                f"Pick one of {legal} (and keep it below the maximum for your "
                f"MTw count so retransmission slots remain).")

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


def awinda_max_rate(n_mtw: int):
    for n_max, r in AWINDA_MAX_RATE:
        if n_mtw <= n_max:
            return r
    return None


# --------------------------------------------------------------------------
# Backend: connection + streaming worker
# --------------------------------------------------------------------------
class XsensBridge:
    """Mode machine (worker thread owns all transitions and all outlets):
        IDLE  -> PROBE  START pressed: log file + startRecording done,
                        waiting for the first recorded packet
        PROBE -> REC    first recorded packet: recorded path -> LSL
        PROBE -> LIVE   nothing recorded within PROBE_S: fallback
        IDLE  -> LIVE   USE_RECORDED_PATH False, or recording failed
        REC/LIVE/PROBE -> FLUSH  STOP pressed while recording: keep pushing
                        the tail until the MTw buffers are flushed
        FLUSH -> IDLE   flush done: close log file, drop outlets
        LIVE  -> IDLE   STOP pressed, nothing recording
    """

    MODE_TEXT = {
        "IDLE":  ("● streams OFF", "gray"),
        "PROBE": ("● starting recording - probing retransmission path ...", "orange"),
        "REC":   ("● REC→LSL   retransmission ON", "green"),
        "LIVE":  ("● LIVE→LSL   no retransmission", "dark orange"),
        "FLUSH": ("● flushing retransmissions ... keep LabRecorder running", "blue"),
    }

    def __init__(self, ui_q: queue.Queue):
        self.ui_q = ui_q
        self.control = None
        self.port_info = None
        self.master = None
        self.master_id = None
        self.rate_eff = float(TARGET_RATE_HZ)

        self.cb = PacketBuffer()
        self.outlets = {}

        self._want = threading.Event()      # GUI: broadcast wanted
        self._stop = threading.Event()
        self._worker = None
        self._lock = threading.Lock()
        self.stats = {}                     # id -> dict (read by the GUI)
        self.connected = False

        self.mode = "IDLE"
        self._recording = False
        self._log_open = False
        self._log_path = None
        self._push_rec = False              # recorded packets go to LSL
        self._probe_t0 = 0.0
        self._probe_buf = []
        self._flush_t0 = 0.0
        self._last_rec_t = 0.0

        # per sensor: counter -> live arrival time, plus FIFO for pruning
        self._live_t = {}
        self._live_keys = {}
        self._lag_warned = set()

        self.mtw_devs = {}                  # MTw id -> XsDevice (battery polls)
        self._bat_next = 0.0
        self._bat_read_at = 0.0             # when to read the cached levels
        self._bat_diag_done = False         # one-time 'where did it come from'
        self._bat_src = {}                  # MTw id -> 'callback' | 'cache'
        self._bat_warned = set()

    # ---- broadcast switch (called from the GUI thread) --------------------
    def set_broadcast(self, on: bool):
        if on:
            self._want.set()
        else:
            self._want.clear()

    # ---- UI messaging (thread safe: the GUI polls this queue) -------------
    def log(self, msg):
        self.ui_q.put(("log", msg))

    def status(self, msg):
        self.ui_q.put(("status", msg))

    def _set_mode(self, mode):
        self.mode = mode
        # live payload copies are only needed while live data may be pushed
        self.cb.keep_live_packets = mode in ("PROBE", "LIVE")
        self.ui_q.put(("mode", mode))

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
            try:
                self.rate_eff = float(self.master.updateRate())
            except Exception:
                self.rate_eff = float(TARGET_RATE_HZ)

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

            # Retransmission needs spare slots: warn when the rate sits at the
            # maximum for the connected MTw count (manual Table 1 / 6.6.6).
            # The count comes from the station's own device list; only if
            # that is unreadable does it fall back to the allowlist length
            # (and says so - the two can coincide and hide a missing MTw).
            self.mtw_devs = self._collect_mtws()
            if self.mtw_devs:
                n_mtw, n_src = len(self.mtw_devs), "station device list"
            else:
                n_mtw, n_src = len(MTW_IDS_ALLOWLIST), "ALLOWLIST LENGTH (device list unreadable)"
            r_max = awinda_max_rate(n_mtw)
            self.log(f"{n_mtw} MTw connected [{n_src}]; Awinda maximum for that "
                     f"count = {r_max} Hz; running at {self.rate_eff:g} Hz.")
            if self.mtw_devs:
                self.log("MTw on the station: " + ", ".join(sorted(self.mtw_devs)))
            if r_max is not None and self.rate_eff >= r_max:
                self.log("[WARN] update rate equals the maximum for this MTw count: "
                         "NO retransmission slots - lower TARGET_RATE_HZ.")

            self.status("Starting measurement ...")
            if not self.master.gotoMeasurement():
                raise RuntimeError("gotoMeasurement() failed")

            self._bat_next = time.time() + 2.0      # first battery poll soon
            self._worker = threading.Thread(target=self._worker_loop, daemon=True)
            self._worker.start()

            self.connected = True
            self.ui_q.put(("connected", None))
            self.log("Measurement running. Press START BROADCAST to feed LSL.")

        except Exception as e:
            self.ui_q.put(("error", str(e)))

    def _collect_mtws(self):
        devs = {}
        try:
            ch = self.master.children()
            for i in range(ch.size()):
                d = ch[i]
                did = d.deviceId().toXsString().upper()
                if not MTW_IDS_ALLOWLIST or did in {x.upper() for x in MTW_IDS_ALLOWLIST}:
                    devs[did] = d
        except Exception as e:
            self.log(f"[WARN] cannot list MTw devices ({e}) - battery column disabled.")
        return devs

    # ---- battery (worker thread) -----------------------------------------
    def _set_bat(self, did, lvl, src):
        st = self._st(did)
        with self._lock:
            st["bat"] = lvl
        self._bat_src[did] = src
        if lvl < BATTERY_WARN_PCT and did not in self._bat_warned:
            self._bat_warned.add(did)
            self.log(f"[WARN] {did} battery {lvl}% (< {BATTERY_WARN_PCT}%) "
                     "- ~6 h runtime when full; recharge before the next session.")

    def _service_battery(self):
        """Three independent steps, each cheap:
          1. every BATTERY_POLL_S: send requestBatteryLevel() to every MTw;
          2. every loop: merge answers delivered through onInfoResponse
             (they show up the moment they arrive, not at the next poll);
          3. BATTERY_READ_DELAY_S after a request: read the device's cached
             batteryLevel() for MTws that did not answer via the callback
             (some SDK builds update the cache without our override firing).
        0 is never accepted (header). After the first round, one log line
        says which path delivered and which MTws never answered."""
        if not self.mtw_devs:
            return
        now = time.time()
        if now >= self._bat_next:
            self._bat_next = now + BATTERY_POLL_S
            self._bat_read_at = now + BATTERY_READ_DELAY_S
            for did, d in self.mtw_devs.items():
                try:
                    d.requestBatteryLevel()      # answer -> onInfoResponse
                except Exception:
                    pass

        got = self.cb.battery_snapshot()         # step 2
        for did, lvl in got.items():
            if did in self.mtw_devs:
                self._set_bat(did, lvl, "callback")

        if self._bat_read_at and now >= self._bat_read_at:   # step 3
            self._bat_read_at = 0.0
            for did, d in self.mtw_devs.items():
                if did in got:
                    continue
                try:
                    v = int(d.batteryLevel())
                except Exception:
                    continue
                if 0 < v <= 100:
                    self._set_bat(did, v, "cache")
            if not self._bat_diag_done:
                self._bat_diag_done = True
                via_cb = sorted(k for k, v in self._bat_src.items() if v == "callback")
                via_ca = sorted(k for k, v in self._bat_src.items() if v == "cache")
                none = sorted(set(self.mtw_devs) - set(self._bat_src))
                self.log(f"Battery, first round: {len(via_cb)} via onInfoResponse, "
                         f"{len(via_ca)} via cached batteryLevel(), "
                         f"{len(none)} no answer.")
                if none:
                    self.log("[WARN] no battery answer from: " + ", ".join(none) +
                             " - column stays n/a for them (this SDK/firmware may not "
                             "report battery while measuring). Data path unaffected.")

    # ---- recording control (worker thread only) ---------------------------
    def _begin_broadcast(self):
        if not USE_RECORDED_PATH:
            self.log("USE_RECORDED_PATH = False -> live push, no retransmission.")
            self._set_mode("LIVE")
            return
        os.makedirs(MTB_DIR, exist_ok=True)
        path = os.path.abspath(os.path.join(
            MTB_DIR, f"MTw_{time.strftime('%Y%m%d_%H%M%S')}.mtb"))
        try:
            rv = self.master.createLogFile(path)
            ok = (rv == getattr(xda, "XRV_OK", 0))
        except Exception as e:
            self.log(f"[WARN] createLogFile threw: {e}")
            ok = False
        if not ok:
            self.log("[WARN] could not create the .mtb log file -> live push "
                     "(no retransmission).")
            self._set_mode("LIVE")
            return
        self._log_open = True
        self._log_path = path
        try:
            ok = bool(self.master.startRecording())
        except Exception as e:
            self.log(f"[WARN] startRecording threw: {e}")
            ok = False
        if not ok:
            self.log("[WARN] startRecording failed -> live push (no retransmission).")
            self._close_log()
            self._set_mode("LIVE")
            return
        self._recording = True
        self._push_rec = False
        self._probe_buf = []
        self._probe_t0 = time.time()
        self.log(f"Recording to {path}")
        self._set_mode("PROBE")

    def _fallback_live(self, reason):
        self.log(f"[WARN] {reason} -> falling back to LIVE push (no retransmission). "
                 "The .mtb backup keeps recording.")
        self._push_rec = False
        self._set_mode("LIVE")
        for src, pc, t, pkt in self._probe_buf:     # nothing from the probe
            if pkt is not None:                     # window is lost
                self._push(src, pkt, t)
        self._probe_buf = []

    def _begin_stop(self):
        if self._recording:
            try:
                self.master.stopRecording()
            except Exception as e:
                self.log(f"[WARN] stopRecording threw: {e}")
            self._recording = False
            self._flush_t0 = time.time()
            self._set_mode("FLUSH")
        else:
            self._finish_stop()

    def _flush_finished(self):
        el = time.time() - self._flush_t0
        if el > FLUSH_TIMEOUT_S:
            self.log(f"[WARN] flush not confirmed after {FLUSH_TIMEOUT_S:g} s - "
                     "closing anyway.")
            return True
        if el < 0.5:
            return False
        quiet = (time.time() - self._last_rec_t) > 1.0 and self.cb.rec_backlog() == 0
        busy_states = [getattr(xda, n, None) for n in ("XDS_FlushingData", "XDS_Recording")]
        busy_states = [s for s in busy_states if s is not None]
        try:
            st = self.master.deviceState()
            flushing = st in busy_states if busy_states else None
        except Exception:
            flushing = None
        if flushing is None:                        # state not readable:
            return quiet and el > 3.0               # rely on silence
        return (not flushing) and quiet

    def _close_log(self):
        if self._log_open:
            try:
                self.master.closeLogFile()
                self.log(f".mtb backup closed: {self._log_path}")
            except Exception as e:
                self.log(f"[WARN] closeLogFile threw: {e}")
            self._log_open = False

    def _finish_stop(self):
        self._close_log()
        if self.outlets:
            n = len(self.outlets)
            self.outlets.clear()                    # refcount -> streams close
            self.log(f"[LSL] {n} stream(s) closed")
        self._push_rec = False
        self._probe_buf = []
        self._set_mode("IDLE")

    def _service_mode(self):
        want = self._want.is_set()
        if want and self.mode == "IDLE":
            self._begin_broadcast()
        elif (not want) and self.mode in ("PROBE", "REC", "LIVE"):
            self._begin_stop()
        if self.mode == "PROBE" and time.time() - self._probe_t0 > PROBE_S:
            self._fallback_live(f"no recorded data within {PROBE_S:g} s")
        if self.mode == "FLUSH" and self._flush_finished():
            self._finish_stop()

    # ---- stamping / pushing (worker thread only) --------------------------
    def _remember_live(self, src, pc, t):
        tbl = self._live_t.setdefault(src, {})
        keys = self._live_keys.setdefault(src, deque())
        if pc not in tbl:
            keys.append(pc)
            if len(keys) > 8192:                    # ~2 min at 60 Hz, far
                tbl.pop(keys.popleft(), None)       # beyond the 1024 buffer
        tbl[pc] = t

    def _stamp_for(self, src, pc, t_rec):
        """(stamp, recovered): the live arrival time of this counter; for a
        packet that never arrived live, the nearest live neighbour shifted
        by (counter delta)/rate - it lands on the same counter-vs-time line
        the pipeline loader fits."""
        tbl = self._live_t.get(src)
        if tbl is not None and pc is not None:
            t = tbl.get(pc)
            if t is not None:
                return t, False
            for k in range(1, NEIGHBOR_SEARCH + 1):
                for d in (-k, k):
                    t2 = tbl.get((pc + d) & 0xFFFF)
                    if t2 is not None:
                        return t2 - d / self.rate_eff, True
        lag = self.stats.get(src, {}).get("lag", float("nan"))
        return (t_rec - lag if lag == lag else t_rec), True

    def _push(self, src, pkt, stamp):
        if src not in self.outlets:
            self.outlets[src] = make_outlet(src, self.rate_eff)
            self.ui_q.put(("log", f"[LSL] stream open: {LSL_PREFIX}_{src}"))
        # NB: never keep a StreamOutlet in a local variable -- a lingering
        # reference keeps that stream alive after self.outlets.clear().
        self.outlets[src].push_sample(packet_to_sample(pkt), stamp)

    def _st(self, src):
        with self._lock:
            if src not in self.stats:
                self.stats[src] = dict(live=0, pushed=0, recovered=0,
                                       lag=float("nan"), last=0.0,
                                       bat=float("nan"), rssi_q=deque(),
                                       rssi_seen=False)
            return self.stats[src]

    # ---- worker ----------------------------------------------------------
    def _worker_loop(self):
        allow = {x.upper() for x in MTW_IDS_ALLOWLIST} if MTW_IDS_ALLOWLIST else None

        def wanted(src):
            return src != self.master_id and (allow is None or src in allow)

        while not self._stop.is_set():
            self._service_mode()
            self._service_battery()

            live = self.cb.drain_live()
            rec = self.cb.drain_rec()
            if not live and not rec:
                time.sleep(0.001)
                continue

            # LIVE first, so every counter it carries is stampable before the
            # recorded copies of the same batch are processed.
            for src, pc, t, pkt, rssi in live:
                if not wanted(src):
                    continue
                st = self._st(src)
                now_w = time.time()
                with self._lock:
                    st["live"] += 1
                    st["last"] = now_w
                    if rssi is not None:
                        st["rssi_seen"] = True
                        q = st["rssi_q"]
                        q.append((now_w, rssi))
                        while q and now_w - q[0][0] > RSSI_WIN_S:
                            q.popleft()
                if pc is not None:
                    self._remember_live(src, pc, t)
                if self.mode == "LIVE" and pkt is not None:
                    self._push(src, pkt, t)
                    with self._lock:
                        st["pushed"] += 1
                elif self.mode == "PROBE":
                    self._probe_buf.append((src, pc, t, pkt))   # 4-tuple on purpose

            for src, pc, t_rec, pkt in rec:
                if not wanted(src):
                    continue
                self._last_rec_t = time.time()
                if self.mode == "PROBE":
                    self._push_rec = True
                    self._probe_buf = []
                    self.log("Recorded path is delivering -> REC→LSL, "
                             "retransmission ON.")
                    self._set_mode("REC")
                if not (self._push_rec and self.mode in ("REC", "FLUSH")):
                    continue
                stamp, recovered = self._stamp_for(src, pc, t_rec)
                self._push(src, pkt, stamp)
                st = self._st(src)
                with self._lock:
                    st["pushed"] += 1
                    if recovered:
                        st["recovered"] += 1
                    else:
                        d = t_rec - stamp            # recorded-path delay
                        st["lag"] = d if st["lag"] != st["lag"] else 0.95 * st["lag"] + 0.05 * d
                        if st["lag"] > LAG_WARN_S and src not in self._lag_warned:
                            self._lag_warned.add(src)
                            self.ui_q.put(("log", f"[WARN] {src}: recorded path lags "
                                                  f"{st['lag']:.1f} s behind live"))

    def snapshot(self):
        """Copy of the stats for the GUI, with the RSSI window reduced to
        its mean (dBm) over the last RSSI_WIN_S seconds."""
        now = time.time()
        out = {}
        with self._lock:
            for k, v in self.stats.items():
                q = v["rssi_q"]
                while q and now - q[0][0] > RSSI_WIN_S:
                    q.popleft()
                d = {kk: vv for kk, vv in v.items() if kk != "rssi_q"}
                d["rssi"] = (sum(r for _, r in q) / len(q)) if q else float("nan")
                out[k] = d
        return out

    # ---- shutdown --------------------------------------------------------
    def shutdown(self):
        self._want.clear()
        self._stop.set()
        if self._worker is not None:
            self._worker.join(timeout=1.5)
        if self._recording:
            try:
                self.master.stopRecording()
            except Exception:
                pass
            self._recording = False
            time.sleep(0.5)
        self._close_log()
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
        root.geometry("820x800")
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
        self.bc_label.pack(pady=(0, 2))
        tk.Label(bc, text=("End of session: STOP BROADCAST -> wait for 'streams OFF' "
                           "-> then stop LabRecorder"),
                 font=('Arial', 9), fg='gray').pack(pady=(0, 6))

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
                                       state='readonly', font=('Arial', 12), width=24,
                                       height=len(EVENTS))
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

        cols = ("sensor", "pushed", "hz_live", "recovered", "lag", "rssi", "bat", "age")
        heads = ("sensor", "pushed", "Hz (live)", "recovered", "lag [s]",
                 f"RSSI [dBm] ({RSSI_WIN_S:g} s)", "battery [%]", "age [s]")
        widths = (150, 70, 70, 75, 60, 110, 80, 60)
        self.tree = ttk.Treeview(st, columns=cols, show='headings', height=7)
        for c, txt, w in zip(cols, heads, widths):
            self.tree.heading(c, text=txt)
            self.tree.column(c, width=w, anchor='center')
        self.tree.tag_configure('lowbat', foreground='red')
        self.tree.pack(fill=tk.X, padx=6, pady=(6, 2))
        tk.Label(st, text=("recovered = packets lost live but saved by retransmission;  "
                           "lag = recorded-path delay behind live;  "
                           f"battery polled every {BATTERY_POLL_S:g} s"),
                 font=('Arial', 9), fg='gray').pack(pady=(0, 6))

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

    def _show_mode(self, mode):
        txt, col = XsensBridge.MODE_TEXT.get(mode, (mode, 'black'))
        if mode == "LIVE" and not USE_RECORDED_PATH:
            txt = "● LIVE→LSL   (recorded path disabled in settings)"
        self.bc_var.set(txt)
        self.bc_label.config(fg=col)
        if mode == "IDLE":
            self.btn_start_bc.config(state=tk.NORMAL)
            self.btn_stop_bc.config(state=tk.DISABLED)

    # ---- broadcast -------------------------------------------------------
    def start_broadcast(self):
        self.bridge.set_broadcast(True)

        if self.mrk_outlet is None:
            mrk_info = StreamInfo(MARKER_NAME, 'Markers', 1, 0, 'string', MARKER_UID)
            self.mrk_outlet = StreamOutlet(mrk_info)
            self.log(f"[LSL] stream open: {MARKER_NAME}")

        if not self.bridge.connected:
            self.bc_var.set("● broadcast requested (waiting for sensors)")
            self.bc_label.config(fg='orange')
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

        # START stays disabled until the worker reports IDLE (flush done)
        self.btn_start_bc.config(state=tk.DISABLED)
        self.btn_stop_bc.config(state=tk.DISABLED)
        self.btn_start_ev.config(state=tk.DISABLED)
        self.btn_end_ev.config(state=tk.DISABLED)
        self.log("Broadcast STOP requested")

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
                elif kind == "mode":
                    self._show_mode(payload)
                elif kind == "connected":
                    self.status_var.set("connected — measurement running")
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
            d = st["live"] - self.prev_counts.get(sid, 0)
            self.prev_counts[sid] = st["live"]
            hz_live = d / dt if dt > 0 else float('nan')
            age = now - st["last"] if st["last"] else float('inf')
            lag, rssi, bat = st["lag"], st["rssi"], st["bat"]
            name = f"{sid}  {SENSOR_ALIASES.get(sid, '')}".strip()
            # RSSI: 'n/a' = this SDK/packet never carried RSSI; 'LOST' = RSSI
            # works but NO packet arrived live in the last window (dropout).
            if rssi == rssi:
                rssi_txt = f"{rssi:0.1f}"
            else:
                rssi_txt = "LOST" if st["rssi_seen"] else "n/a"
            vals = (name, st["pushed"], f"{hz_live:0.1f}", st["recovered"],
                    "-" if lag != lag else f"{lag:0.2f}",
                    rssi_txt,
                    "n/a" if bat != bat else f"{bat:0.0f}",
                    f"{age:0.2f}" if age != float('inf') else "-")
            tags = ('lowbat',) if (bat == bat and bat < BATTERY_WARN_PCT) else ()
            if self.tree.exists(sid):
                self.tree.item(sid, values=vals, tags=tags)
            else:
                self.tree.insert('', tk.END, iid=sid, values=vals, tags=tags)

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