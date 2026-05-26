import serial
import time
import tkinter as tk
from pylsl import StreamInfo, StreamOutlet, local_clock

def read_from_arduino(serial_port='COM6', baud_rate=1000000, timeout=1):
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

def main():
    serial_port = 'COM6'
    baud_rate   = 1000000
    chunk_size  = 50

    condition_name = input("Enter condition name (e.g. No_Exo_Pre, Eco_Mode): ").strip()
    print(f"Condition: {condition_name}")

    ser = read_from_arduino(serial_port=serial_port, baud_rate=baud_rate)
    if ser is None:
        return

    grf_info   = StreamInfo('GRF', 'Force', 8, 150.4, 'int32', 'myuid34234')
    grf_outlet = StreamOutlet(grf_info)

    mrk_info   = StreamInfo('GRF_Markers', 'Markers', 1, 0, 'string', 'myuid_markers')
    mrk_outlet = StreamOutlet(mrk_info)

    # --- GUI ----------------------------------------------------------------
    root = tk.Tk()
    root.title(f"GRF Marker Control — {condition_name}")
    root.geometry("420x340")

    tk.Label(root, text=f"Condition: {condition_name}",
             font=('Arial', 12, 'bold'), pady=5).pack()

    # --- Timer display ------------------------------------------------------
    timer_var   = tk.StringVar(value="--:--")
    timer_start = [None]   # list so it's mutable inside callbacks

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
    def send_marker(label, button, color, is_start):
        t = local_clock()
        mrk_outlet.push_sample([label], t)
        button.config(bg=color, text=f"{button['text'].split(' ✓')[0]} ✓")
        print(f"Marker sent: {label} at {t:.4f}")
        if is_start:
            start_timer()
        else:
            reset_timer()

    # --- Buttons ------------------------------------------------------------
    tk.Label(root, text="Standing before walking:",
             font=('Arial', 10)).pack()
    frame1 = tk.Frame(root); frame1.pack(pady=2)
    btn_s1_start = tk.Button(frame1, text="START standing 1", width=18,
                             font=('Arial', 10),
                             command=lambda: send_marker(
                                 f"START_standing_{condition_name}_1",
                                 btn_s1_start, 'green', is_start=True))
    btn_s1_start.pack(side=tk.LEFT, padx=5)
    btn_s1_end = tk.Button(frame1, text="END standing 1", width=18,
                           font=('Arial', 10),
                           command=lambda: send_marker(
                               f"END_standing_{condition_name}_1",
                               btn_s1_end, 'red', is_start=False))
    btn_s1_end.pack(side=tk.LEFT, padx=5)

    tk.Label(root, text="Steady-state walking (4.2 km/h):",
             font=('Arial', 10)).pack(pady=(8,0))
    frame2 = tk.Frame(root); frame2.pack(pady=2)
    btn_w_start = tk.Button(frame2, text="START walking", width=18,
                            font=('Arial', 10),
                            command=lambda: send_marker(
                                f"START_{condition_name}",
                                btn_w_start, 'green', is_start=True))
    btn_w_start.pack(side=tk.LEFT, padx=5)
    btn_w_end = tk.Button(frame2, text="END walking", width=18,
                          font=('Arial', 10),
                          command=lambda: send_marker(
                              f"END_{condition_name}",
                              btn_w_end, 'red', is_start=False))
    btn_w_end.pack(side=tk.LEFT, padx=5)

    tk.Label(root, text="Standing after walking:",
             font=('Arial', 10)).pack(pady=(8,0))
    frame3 = tk.Frame(root); frame3.pack(pady=2)
    btn_s2_start = tk.Button(frame3, text="START standing 2", width=18,
                             font=('Arial', 10),
                             command=lambda: send_marker(
                                 f"START_standing_{condition_name}_2",
                                 btn_s2_start, 'green', is_start=True))
    btn_s2_start.pack(side=tk.LEFT, padx=5)
    btn_s2_end = tk.Button(frame3, text="END standing 2", width=18,
                           font=('Arial', 10),
                           command=lambda: send_marker(
                               f"END_standing_{condition_name}_2",
                               btn_s2_end, 'red', is_start=False))
    btn_s2_end.pack(side=tk.LEFT, padx=5)

    # --- Acquisition loop ---------------------------------------------------
    chunk      = []
    timestamps = []

    def acquire():
        line = ser.readline().decode('latin-1').strip()
        if line:
            t        = local_clock()
            channels = parse_data(line)
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