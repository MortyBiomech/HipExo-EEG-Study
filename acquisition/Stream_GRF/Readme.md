# GRF Stream

This folder contains the code for reading ground reaction force (GRF) signals from force sensors connected to an Arduino and streaming them over the Lab Streaming Layer (LSL) network.

---

## Prerequisites

- [Arduino IDE](https://www.arduino.cc/en/software) (to deploy the `.ino` sketch and identify the COM port)
- Python 3 installed on your system
- For WSL users: [`usbipd-win`](https://github.com/dorssel/usbipd-win) installed on Windows

---

## Hardware Setup

1. Connect the GRF(Z) USB to the computer.
2. Open the Arduino IDE and deploy `transmission_of_GRF_signals.ino` to the Arduino.
   - After deployment, open the Serial Monitor to verify that force sensor data is being received.

---

## Running on Windows (native, not WSL)

### First-time setup

Open a terminal in the folder containing the Python code (right-click → *Open in Terminal*) and run:

```powershell
# Create a virtual environment
python -m venv .venv_grf

# Activate it
.\.venv_grf\Scripts\Activate.ps1

# Update pip
python -m pip install --upgrade pip

# Install required packages
python -m pip install pyserial pylsl
```

### Running the script

In the terminal (with the virtual environment still activated), open VS Code:

```powershell
code .
```

In VS Code:
1. Select the Python interpreter from the virtual environment: press `Ctrl+Shift+P` → *Python: Select Interpreter* → choose `.venv_grf`.
2. Open `reading_GRF.py` and run it with the play button (▶) or press `F5`.

> **Note:** Check the correct COM port in the Arduino IDE (*Tools → Port*) and make sure it matches the port set in `reading_GRF.py`.

---

## Running from WSL

WSL cannot access USB devices directly. You need to forward the USB connection from Windows to WSL using `usbipd`.

### Step 1 — Attach the USB device to WSL (Windows side)

Open **PowerShell as Administrator** and run:

```powershell
usbipd list
```

Find the `busid` corresponding to the GRF Arduino in the list, then attach it:

```powershell
usbipd attach --wsl --busid <busid>   # e.g. usbipd attach --wsl --busid 1-4
```

> **Note:** You need to repeat this `attach` step every time the USB device is reconnected or the computer is restarted.

### Step 2 — Set up the Python environment (WSL side, first time only)

Open your WSL terminal and navigate to the folder with the Python code:

```bash
cd /path/to/GRF_Stream
```

Create and activate a conda environment:

```bash
conda create --name grf
conda activate grf
```

Install required packages:

```bash
conda install pyserial
pip install pylsl   # pylsl is not reliably available on conda-forge; use pip instead
```

### Step 3 — Run the script

In your WSL terminal (with the conda environment activated), open VS Code:

```bash
code .
```

In VS Code:
1. Select the Python interpreter from the conda environment: press `Ctrl+Shift+P` → *Python: Select Interpreter* → choose the `grf` conda environment.
2. Open `reading_GRF.py` and run it with the play button (▶) or press `F5`.

> **Note:** In WSL, the device will appear as a serial port under `/dev/ttyUSB0` or similar — not as a COM port. Verify with `ls /dev/tty*` after attaching the USB device, and make sure the port in `reading_GRF.py` is set accordingly.