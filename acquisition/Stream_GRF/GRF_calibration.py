import time
import json
import serial
import tkinter as tk
import tkinter.ttk as ttk
from tkinter import messagebox
from pylsl import StreamInfo, StreamOutlet, local_clock


# ============================================================================
# CONFIGURATION  --  edit these to match your rig
# ============================================================================
SERIAL_PORT = 'COM6'
BAUD_RATE   = 1_000_000
CHUNK_SIZE  = 50
GRAVITY     = 9.81          # m/s^2;  Force[N] = mass[kg] * GRAVITY

# Which of the 8 GRF channels belong to each force plate.
# >>> VERIFY this against your wiring before you trust the calibration. <<<
CHANNEL_MAP = {
    'Right': [0, 1, 2, 3],
    'Left':  [4, 5, 6, 7],
}

N_LEVELS    = 7
LEVEL_NAMES = [f"user_weight+{i}" if i else "user_weight" for i in range(N_LEVELS)]
# Default *added* mass per level [kg] -- overwrite in the GUI with the real weights.
DEFAULT_ADDED_KG = [float(i) for i in range(N_LEVELS)]


def read_from_arduino(serial_port=SERIAL_PORT, baud_rate=BAUD_RATE, timeout=1):
    try:
        ser = serial.Serial(serial_port, baud_rate, timeout=timeout)
        print(f"Connected to Arduino on port {serial_port}")
        time.sleep(2)
        return ser
    except serial.SerialException as e:
        print(f"Error: {e}")
        return None


def parse_data(line):
    channels = [0] * 8
    try:
        parts = line.split(", ")
        if len(parts) == 8:
            channels = [int(part) for part in parts]
    except (ValueError, IndexError) as e:
        print(f"Parsing error: {e}")
    return channels


def linear_fit(xs, ys):
    """Ordinary least squares  y = slope*x + intercept.  Returns (slope, intercept, r2)."""
    n = len(xs)
    if n < 2:
        return float('nan'), float('nan'), float('nan')
    mx, my = sum(xs) / n, sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    if sxx == 0:
        return float('nan'), float('nan'), float('nan')
    slope = sxy / sxx
    intercept = my - slope * mx
    ss_tot = sum((y - my) ** 2 for y in ys)
    ss_res = sum((y - (slope * x + intercept)) ** 2 for x, y in zip(xs, ys))
    r2 = 1 - ss_res / ss_tot if ss_tot else float('nan')
    return slope, intercept, r2


def main():
    ser = read_from_arduino()
    if ser is None:
        return

    grf_info   = StreamInfo('GRF', 'Force', 8, 150.4, 'int32', 'myuid34234')
    grf_outlet = StreamOutlet(grf_info)
    mrk_info   = StreamInfo('GRF_Markers', 'Markers', 1, 0, 'string', 'myuid_markers')
    mrk_outlet = StreamOutlet(mrk_info)

    # calib_data[side][level_index] = mean summed-raw value over the interval
    calib_data = {'Left': {}, 'Right': {}}
    # state of the currently-open interval
    rec = {'on': False, 'side': None, 'level': None, 'buf': []}

    # --- GUI ----------------------------------------------------------------
    root = tk.Tk()
    root.title("GRF Calibration")
    root.geometry("820x760")

    # --- Top controls: body mass + side ------------------------------------
    top = tk.Frame(root)
    top.pack(pady=(10, 4), fill=tk.X, padx=12)

    tk.Label(top, text="Body mass [kg]:", font=('Arial', 11, 'bold')).pack(side=tk.LEFT)
    mass_var = tk.StringVar(value="")
    tk.Entry(top, textvariable=mass_var, width=8, font=('Arial', 11)).pack(side=tk.LEFT, padx=(4, 20))

    tk.Label(top, text="Plate:", font=('Arial', 11, 'bold')).pack(side=tk.LEFT)
    side_var = tk.StringVar(value='Right')
    for s in ('Right', 'Left'):
        tk.Radiobutton(top, text=s, variable=side_var, value=s,
                       font=('Arial', 11)).pack(side=tk.LEFT, padx=4)

    # --- Timer --------------------------------------------------------------
    timer_var, timer_start = tk.StringVar(value="--:--"), [None]
    timer_label = tk.Label(root, textvariable=timer_var, font=('Arial', 24, 'bold'),
                           fg='black', pady=2)
    timer_label.pack()

    def update_timer():
        if timer_start[0] is not None:
            e = time.time() - timer_start[0]
            timer_var.set(f"{int(e // 60):02d}:{int(e % 60):02d}")
            timer_label.config(fg='green')
        root.after(1000, update_timer)

    # --- Status -------------------------------------------------------------
    status_var = tk.StringVar(value="Idle.")
    tk.Label(root, textvariable=status_var, font=('Arial', 10), fg='gray25').pack()

    # --- Per-level rows -----------------------------------------------------
    added_vars  = []
    result_vars = []
    btns        = []   # (start_btn, start_txt, end_btn, end_txt) for tick reset

    def refresh_results(*_):
        """Show the stored raw value for the currently selected plate."""
        side = side_var.get()
        for i in range(N_LEVELS):
            v = calib_data[side].get(i)
            result_vars[i].set(f"{v:.1f}" if v is not None else "—")

    def start_level(i):
        side = side_var.get()
        rec.update(on=True, side=side, level=i, buf=[])
        mrk_outlet.push_sample([f"{LEVEL_NAMES[i]}_start"], local_clock())
        timer_start[0] = time.time()
        sb, st, _, _ = btns[i]
        sb.config(bg='green', text=f"{st} \u2713")
        status_var.set(f"Recording {side} | {LEVEL_NAMES[i]} ...")

    def end_level(i):
        side = side_var.get()
        mrk_outlet.push_sample([f"{LEVEL_NAMES[i]}_end"], local_clock())
        timer_start[0] = None
        timer_var.set("--:--")
        timer_label.config(fg='black')
        _, _, eb, et = btns[i]
        eb.config(bg='red', text=f"{et} \u2713")
        if rec['on'] and rec['side'] == side and rec['level'] == i and rec['buf']:
            mean_raw = sum(rec['buf']) / len(rec['buf'])
            calib_data[side][i] = mean_raw
            status_var.set(f"Stored {side} | {LEVEL_NAMES[i]}: raw={mean_raw:.1f} "
                           f"(n={len(rec['buf'])})")
            refresh_results()
        else:
            status_var.set("No samples captured for this interval.")
        rec.update(on=False, buf=[])

    rows = tk.Frame(root)
    rows.pack(pady=4)
    for i in range(N_LEVELS):
        r = tk.Frame(rows)
        r.pack(pady=2, fill=tk.X)

        tk.Label(r, text=LEVEL_NAMES[i], width=14, anchor='w',
                 font=('Arial', 10, 'bold')).pack(side=tk.LEFT)

        av = tk.StringVar(value=f"{DEFAULT_ADDED_KG[i]:g}")
        added_vars.append(av)
        tk.Label(r, text="+kg:", font=('Arial', 9)).pack(side=tk.LEFT)
        tk.Entry(r, textvariable=av, width=6, font=('Arial', 10)).pack(side=tk.LEFT, padx=(0, 8))

        sb = tk.Button(r, text="START", width=8, font=('Arial', 10))
        eb = tk.Button(r, text="END",   width=8, font=('Arial', 10))
        sb.config(command=lambda i=i: start_level(i))
        eb.config(command=lambda i=i: end_level(i))
        sb.pack(side=tk.LEFT, padx=3)
        eb.pack(side=tk.LEFT, padx=3)
        btns.append((sb, "START", eb, "END"))

        rv = tk.StringVar(value="—")
        result_vars.append(rv)
        tk.Label(r, text="raw:", font=('Arial', 9)).pack(side=tk.LEFT, padx=(8, 0))
        tk.Label(r, textvariable=rv, width=10, anchor='w',
                 font=('Arial', 10), fg='blue').pack(side=tk.LEFT)

    side_var.trace_add('write', refresh_results)

    # --- Compute / save -----------------------------------------------------
    results_var = tk.StringVar(value="")
    last = {'results': None}

    def compute():
        try:
            body = float(mass_var.get())
        except ValueError:
            messagebox.showerror("Input error", "Enter a valid body mass [kg].")
            return
        lines, fits = [], {}
        for side in ('Right', 'Left'):
            xs, ys, used = [], [], []
            for i in sorted(calib_data[side]):
                try:
                    added = float(added_vars[i].get())
                except ValueError:
                    continue
                xs.append(calib_data[side][i])
                ys.append((body + added) * GRAVITY)
                used.append(i)
            if len(xs) >= 2:
                m, c, r2 = linear_fit(xs, ys)
                lines.append(f"{side}:  F[N] = {m:.5g} * raw + {c:.5g}    "
                             f"R^2 = {r2:.4f}   ({len(xs)} pts)")
                fits[side] = {
                    'slope_N_per_count': m, 'intercept_N': c, 'r2': r2,
                    'points': [{'level': LEVEL_NAMES[i],
                                'added_kg': float(added_vars[i].get()),
                                'force_N': (body + float(added_vars[i].get())) * GRAVITY,
                                'raw': calib_data[side][i]} for i in used],
                }
            else:
                lines.append(f"{side}:  need >= 2 recorded levels (have {len(xs)})")
        results_var.set("\n".join(lines) if lines else "No data recorded yet.")
        last['results'] = {'body_mass_kg': body, 'gravity': GRAVITY,
                           'channel_map': CHANNEL_MAP, 'fits': fits}

    def save():
        if last['results'] is None:
            compute()
        if last['results'] is None:
            return
        fname = f"grf_calibration_{time.strftime('%Y%m%d_%H%M%S')}.json"
        with open(fname, 'w') as f:
            json.dump(last['results'], f, indent=2)
        status_var.set(f"Saved {fname}")

    def reset_marks():
        for sb, st, eb, et in btns:
            sb.config(bg='SystemButtonFace', text=st)
            eb.config(bg='SystemButtonFace', text=et)

    ctl = tk.Frame(root)
    ctl.pack(pady=(10, 4))
    tk.Button(ctl, text="Compute calibration", font=('Arial', 10, 'bold'),
              command=compute).pack(side=tk.LEFT, padx=6)
    tk.Button(ctl, text="Save (JSON)", font=('Arial', 10),
              command=save).pack(side=tk.LEFT, padx=6)
    tk.Button(ctl, text="Reset marks", font=('Arial', 10),
              command=reset_marks).pack(side=tk.LEFT, padx=6)

    tk.Label(root, textvariable=results_var, font=('Courier', 10),
             justify=tk.LEFT, fg='black').pack(pady=6, padx=12, anchor='w')

    # --- Acquisition loop ---------------------------------------------------
    chunk, timestamps = [], []

    def acquire():
        line = ser.readline().decode('latin-1').strip()
        if line:
            t = local_clock()
            channels = parse_data(line)
            chunk.append(channels)
            timestamps.append(t)
            if rec['on']:
                rec['buf'].append(sum(channels[c] for c in CHANNEL_MAP[rec['side']]))
            if len(chunk) >= CHUNK_SIZE:
                grf_outlet.push_chunk(chunk, timestamps)
                chunk.clear()
                timestamps.clear()
        root.after(1, acquire)

    refresh_results()
    update_timer()
    root.after(1, acquire)
    root.mainloop()
    ser.close()


if __name__ == "__main__":
    main()