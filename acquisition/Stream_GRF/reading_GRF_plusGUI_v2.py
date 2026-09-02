import serial
import time
import tkinter.ttk as ttk
from pylsl import StreamInfo, StreamOutlet, local_clock


CONDITIONS = [
    "No_Exo_Pre",
    "No_Exo_Post",
    "AquaPlus",
    "Aqua",
    "Transparent",
    "Eco",
    "Sport",
    "Boost",
]


def read_from_arduino(serial_port='COM11', baud_rate=1_000_000, timeout=1):
    try:
        ser = serial.Serial(serial_port, baud_rate, timeout=timeout)
        print(f"Connected to Arduino on port {serial_port}")
        time.sleep(2)                # let the Arduino finish its reset
        ser.reset_input_buffer()     # discard stale bytes from before/during reset
        ser.readline()               # throw away the (possibly partial) first line
        return ser
    except serial.SerialException as e:
        print(f"Error: {e}")
        return None


def parse_data(line):
    """Return a list of 8 ints, or None if the line is corrupted/incomplete."""
    try:
        parts = line.split(", ")
        if len(parts) == 8:
            return [int(part) for part in parts]
    except ValueError:
        pass
    print(f"Skipped bad line: {line!r}")
    return None


def main():
    serial_port = 'COM11'
    baud_rate   = 1_000_000
    chunk_size  = 50

    ser = read_from_arduino(serial_port=serial_port, baud_rate=baud_rate)
    if ser is None:
        return

    grf_info   = StreamInfo('GRF', 'Force', 8, 150.4, 'int32', 'myuid34234')
    grf_outlet = StreamOutlet(grf_info)

    mrk_info   = StreamInfo('GRF_Markers', 'Markers', 1, 0, 'string', 'myuid_markers')
    mrk_outlet = StreamOutlet(mrk_info)

    # --- GUI ----------------------------------------------------------------
    root = ttk.Tk()
    root.title("GRF Marker Control")
    root.geometry("460x400")

    # --- Condition selector -------------------------------------------------
    condition_var = ttk.StringVar(value=CONDITIONS[0])

    selector_frame = ttk.Frame(root)
    selector_frame.pack(pady=8)

    ttk.Label(selector_frame, text="Condition:", font=('Arial', 12, 'bold')).pack(side=tk.LEFT, padx=(0, 8))

    condition_menu = ttk.Combobox(
        selector_frame,
        textvariable=condition_var,
        values=CONDITIONS,
        state='readonly',
        font=('Arial', 12),
        width=16,
    )
    condition_menu.pack(side=ttk.LEFT)

    def on_condition_change(*_):
        root.title(f"GRF Marker Control — {condition_var.get()}")

    condition_var.trace_add('write', on_condition_change)
    on_condition_change()   # set title on startup

    # --- Timer display ------------------------------------------------------
    timer_var   = tk.StringVar(value="--:--")
    timer_start = [None]

    timer_label = tk.Label(root, textvariable=timer_var,
                           font=('Arial', 28, 'bold'), fg='black', pady=5)
    timer_label.pack()

    def update_timer():
        if timer_start[0] is not None:
            elapsed = time.time() - timer_start[0]
            mins    = int(elapsed // 60)
            secs    = int(elapsed % 60)
            timer_var.set(f"{mins:02d}:{secs:02d}")
            timer_label.config(fg='green')
        root.after(1000, update_timer)

    def start_timer():
        timer_start[0] = time.time()

    def reset_timer():
        timer_start[0] = None
        timer_var.set("--:--")
        timer_label.config(fg='black')

    # --- Marker sender ------------------------------------------------------
    def send_marker(label_template, button, color, is_start):
        """label_template uses {c} as placeholder for the condition name."""
        cond  = condition_var.get()
        label = label_template.format(c=cond)
        t     = local_clock()
        mrk_outlet.push_sample([label], t)
        base_text = button['text'].split(' ✓')[0]
        button.config(bg=color, text=f"{base_text} ✓")
        print(f"Marker sent: {label} at {t:.4f}")
        if is_start:
            start_timer()
        else:
            reset_timer()

    # Reset button tick marks whenever the condition changes so they don't
    # carry over from the previous condition.
    all_buttons = []

    def reset_button_marks(*_):
        for btn, original_text in all_buttons:
            btn.config(bg='SystemButtonFace', text=original_text)

    condition_var.trace_add('write', reset_button_marks)

    # --- Helper to build a button row ---------------------------------------
    def add_button_row(parent, section_label, start_text, end_text,
                       start_template, end_template):
        tk.Label(root, text=section_label, font=('Arial', 10)).pack(pady=(8, 0))
        frame = tk.Frame(root)
        frame.pack(pady=2)

        btn_start = tk.Button(frame, text=start_text, width=18, font=('Arial', 10))
        btn_end   = tk.Button(frame, text=end_text,   width=18, font=('Arial', 10))

        btn_start.config(command=lambda: send_marker(start_template, btn_start, 'green', is_start=True))
        btn_end  .config(command=lambda: send_marker(end_template,   btn_end,   'red',   is_start=False))

        btn_start.pack(side=tk.LEFT, padx=5)
        btn_end  .pack(side=tk.LEFT, padx=5)

        all_buttons.append((btn_start, start_text))
        all_buttons.append((btn_end,   end_text))

    # --- Buttons ------------------------------------------------------------
    add_button_row(root,
                   "Standing before walking:",
                   "START standing 1", "END standing 1",
                   "START_standing_{c}_1", "END_standing_{c}_1")

    add_button_row(root,
                   "Steady-state walking (4.2 km/h):",
                   "START walking", "END walking",
                   "START_{c}", "END_{c}")

    add_button_row(root,
                   "Standing after walking:",
                   "START standing 2", "END standing 2",
                   "START_standing_{c}_2", "END_standing_{c}_2")

    # --- Acquisition loop ---------------------------------------------------
    chunk      = []
    timestamps = []

    def acquire():
        line = ser.readline().decode('latin-1').strip()
        if line:
            t        = local_clock()
            channels = parse_data(line)
            if channels is not None:
                chunk.append(channels)
                timestamps.append(t)

                if len(chunk) >= chunk_size:
                    grf_outlet.push_chunk(chunk, timestamps)
                    chunk.clear()
                    timestamps.clear()

        root.after(1, acquire)

    update_timer()
    root.after(1, acquire)
    root.mainloop()
    ser.close()


if __name__ == "__main__":
    main()