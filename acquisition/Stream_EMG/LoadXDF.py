import pyxdf
import matplotlib.pyplot as plt

# Fixed path using raw string to avoid escape error
file_path = r'C:\Users\54501\Documents\CurrentStudy\sub-P001\ses-S001\eeg\sub-P001_ses-S001_task-Default_run-001_eeg.xdf'

# Load the XDF file
streams, fileheader = pyxdf.load_xdf(file_path)

print(f"Total streams found: {len(streams)}\n")

# Setup plotting: Create a figure with subplots for each stream
fig, axes = plt.subplots(len(streams), 1, figsize=(12, 3 * len(streams)), sharex=True)

# If there is only 1 stream, wrapping axes in a list makes it iterable
if len(streams) == 1:
    axes = [axes]

for i, stream in enumerate(streams):
    print(f"========== Stream {i + 1} ==========")

    # 1. Extract metadata
    info = stream['info']
    name = info['name'][0]
    stream_type = info['type'][0]
    channel_count = int(info['channel_count'][0])
    sample_rate = info.get('nominal_srate', ['N/A'])[0]

    print(f"Stream Name: {name}")
    print(f"Stream Type: {stream_type}")
    print(f"Channels: {channel_count}")
    print(f"Sampling Rate: {sample_rate} Hz")

    # 2. Extract data and timestamps
    time_stamps = stream['time_stamps']
    time_series = stream['time_series']

    print(f"Total Data Points: {len(time_stamps)}")

    # 3. Visualization logic based on data type
    ax = axes[i]
    if len(time_stamps) > 0:
        # Check if the stream is a Marker/Event stream (usually strings)
        if stream_type.lower() == 'markers' or isinstance(time_series[0], (str, list)):
            # Convert marker content to string for labels
            marker_labels = [str(m[0]) if isinstance(m, (list, bytes)) else str(m) for m in time_series]

            # Plot discrete vertical lines for events
            ax.vlines(time_stamps, 0, 1, colors='r', linestyles='dashed', label='Events')

            # Add text labels next to the event lines (showing first 20 to avoid clutter)
            for ts, label in list(zip(time_stamps, marker_labels))[:20]:
                ax.text(ts, 0.5, label, rotation=90, verticalalignment='center', fontsize=8)

            ax.set_yticks([])
            ax.set_ylabel('Markers')
            print(f"Sample Markers: {marker_labels[:5]}")
        else:
            # Plot continuous signals (EEG, EMG, etc.)
            # Plotting all channels against timestamps
            ax.plot(time_stamps, time_series)
            ax.set_ylabel('Amplitude')
            if len(time_series) > 0:
                print(f"Sample Data (First 3 rows):\n{time_series[:3]}")

        ax.set_title(f"Stream {i + 1}: {name} ({stream_type})")
        ax.grid(True)
    else:
        ax.text(0.5, 0.5, 'Empty Stream (No Data)', transform=ax.transAxes, ha='center')
        print("Warning: This stream contains no data points.")

# Set the common X-axis label at the bottom
plt.xlabel('Timestamp (Seconds)')
plt.tight_layout()

print("\nDisplaying the visualization window...")
plt.show()