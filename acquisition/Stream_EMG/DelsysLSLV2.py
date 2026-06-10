import sys
import time
import threading
from pylsl import StreamInfo, StreamOutlet

# Import the official TrignoBase class
from AeroPy.TrignoBase import TrignoBase


class InteractiveLSLRunner:
    def __init__(self):
        # Call the TrignoBase function to decode the Aero library. Please enter the key and license on lines 20 and 21 of TrignoBase.py in the Aero folder.
        self.trigno = TrignoBase(collection_data_handler=None)
        # Extract the underlying core AeroPy API instance
        self.aero = self.trigno.TrigBase

        self.sensor_streams = []
        self.is_streaming = False
        self.stream_thread = None

        # Flag to track if the base station has been validated
        self.is_validated = False

    def step1_validate(self):
        # Step 1: Connect to the base station,Validate the base station using the built-in license keys.
        print("\nStep 1: Validating Base Station...")
        try:
            self.trigno.Connect_Callback()
            self.is_validated = True
            print(f"Success: Base Station validated. Type: {self.trigno.trigno_station_type.name}")
        except Exception as e:
            print(f"Error: Validation failed. Details: {e}")

    def step2_scan(self):
        # Step 2: Scan for sensors and display their hardware memory settings.
        if not self.is_validated:
            print("\nError: Base Station is not validated.")
            print("You must press '1' to validate the base station before scanning.")
            return

        print("\nStep 2: Scanning for sensors...")
        scan_task = self.aero.ScanSensors()
        while not scan_task.IsCompleted:
            time.sleep(0.1)

        sensors = self.aero.GetScannedSensorsFound()
        if not sensors:
            print("Warning: No sensors found. Please ensure sensors are turned on and paired.")
            return

        self.aero.SelectAllSensors()
        print(f"Scan complete. {len(sensors)} sensor(s) selected.")

        # Display current real working settings for each sensor
        print("\nCurrent Sensor Settings (Hardware Memory):")
        sensor_names = self.aero.GetSensorNames()
        for idx in range(len(sensor_names)):
            name = sensor_names[idx]
            pair_num = self.aero.GetSensorPairNumber(idx)
            current_mode = self.aero.GetCurrentSensorMode(idx)
            channel_info = self.aero.GetSensorChannelInfo(idx)

            # Count enabled channels safely
            enabled_count = 0
            for ch in channel_info:
                val = ch["Enabled"]
                if str(val).strip().lower() in ['true', '1'] or val is True:
                    enabled_count += 1

            print(f"  Sensor {idx}: {name} (Pair: {pair_num})")
            print(f"    Mode: {current_mode}")
            print(f"    Active Channels: {enabled_count}")

    def step3_configure(self):
        # Step 3: Configure the pipeline and dynamically create LSL streams.
        print("\nStep 3: Configuring pipeline and creating independent LSL streams...")
        try:
            # Disable the sync output interface and pass the parameter 148 Hz to pass the firmware check.
            if hasattr(self.trigno, 'trigno_station_type') and self.trigno.trigno_station_type.name == 'CENTRO':
                try:
                    self.aero.SetSyncOutput(False, 1, True, 148)
                except Exception:
                    pass

            # Lock the hardware pipeline
            self.aero.Configure()
            print("Success: Pipeline is armed.")

            self.sensor_streams.clear()
            sensor_names = self.aero.GetSensorNames()

            if not sensor_names:
                print("Warning: No sensors detected during LSL setup. Did you run Step 2?")
                return

            # Establish dual channels to split IMU and EMG.
            for idx in range(len(sensor_names)):
                ch_info = self.aero.GetSensorChannelInfo(idx)

                emg_guids = []
                imu_guids = []
                emg_rate = 0.0
                imu_rate = 0.0

                print(f"  -> Scanning {len(ch_info)} channels for Sensor {idx}...")

                for ch in ch_info:
                    # Iterate over the sensor channels to check if they are active.
                    enabled_val = ch["Enabled"]
                    is_enabled = str(enabled_val).strip().lower() in ['true', '1'] or enabled_val is True

                    if is_enabled:
                        guid = str(ch["Guid"])
                        if ch["Type"] == "EMG":
                            emg_guids.append(guid)
                            emg_rate = float(ch["Sample Rate"])
                        elif ch["Type"] in ["ACC", "GYRO", "AUX"]:
                            imu_guids.append(guid)
                            imu_rate = float(ch["Sample Rate"])

                emg_guids.sort()
                imu_guids.sort()

                stream_dict = {
                    'emg_guids': emg_guids, 'imu_guids': imu_guids,
                    'emg_outlet': None, 'imu_outlet': None
                }
                # LSL Outlet Creation
                if emg_guids:
                    info_emg = StreamInfo(f'Delsys_S{idx}_EMG', 'EMG', len(emg_guids), emg_rate, 'float32',
                                          f'delsys_s{idx}_emg')
                    stream_dict['emg_outlet'] = StreamOutlet(info_emg)
                    print(f"  -> LSL Stream Ready: [Delsys_S{idx}_EMG] | {len(emg_guids)} channels | {emg_rate} Hz")

                if imu_guids:
                    info_imu = StreamInfo(f'Delsys_S{idx}_IMU', 'IMU', len(imu_guids), imu_rate, 'float32',
                                          f'delsys_s{idx}_imu')
                    stream_dict['imu_outlet'] = StreamOutlet(info_imu)
                    print(f"  -> LSL Stream Ready: [Delsys_S{idx}_IMU] | {len(imu_guids)} channels | {imu_rate} Hz")

                if emg_guids or imu_guids:
                    self.sensor_streams.append(stream_dict)

            if not self.sensor_streams:
                print(
                    "Warning: Pipeline is armed, but zero channels were evaluated as 'Enabled'. No LSL streams created.")
            else:
                # Let Python pause briefly to catch the asynchronous C++ library logging output.
                # This keeps the main menu console output organized and clean.
                time.sleep(0.4)

        except Exception as e:
            print(f"Error: Configuration failed. Details: {e}")

    def _streaming_loop(self):
        # Background thread for LSL broadcasting
        print("\n[DEBUG] Background streaming thread started. Waiting for hardware data...")
        packet_count = 0
        try:
            while self.is_streaming:
                if self.aero.CheckDataQueue():
                    data_packet = self.aero.PollDataByString()

                    if data_packet is None:
                        continue

                    packet_count += 1
                    if packet_count == 1:
                        print(
                            "\n[DEBUG] Successfully received the first hardware data packet. LSL broadcasting active.")
                    elif packet_count % 2000 == 0:
                        print(f"[DEBUG] Continuing to stream... {packet_count} packets processed.")

                    # Iterate through each sensor and push chunks independently
                    for stream in self.sensor_streams:

                        # Process EMG data using strict C# Dictionary syntax
                        if stream['emg_outlet'] and stream['emg_guids']:
                            first_guid = stream['emg_guids'][0]
                            if data_packet.ContainsKey(first_guid) and data_packet[first_guid].Count > 0:
                                num_samples = data_packet[first_guid].Count
                                chunk = []
                                for i in range(num_samples):
                                    sample = [float(data_packet[g][i]) if (
                                                data_packet.ContainsKey(g) and i < data_packet[g].Count) else 0.0 for g
                                              in stream['emg_guids']]
                                    chunk.append(sample)
                                stream['emg_outlet'].push_chunk(chunk)

                        # Process IMU data using strict C# Dictionary syntax
                        if stream['imu_outlet'] and stream['imu_guids']:
                            first_guid = stream['imu_guids'][0]
                            if data_packet.ContainsKey(first_guid) and data_packet[first_guid].Count > 0:
                                num_samples = data_packet[first_guid].Count
                                chunk = []
                                for i in range(num_samples):
                                    sample = [float(data_packet[g][i]) if (
                                                data_packet.ContainsKey(g) and i < data_packet[g].Count) else 0.0 for g
                                              in stream['imu_guids']]
                                    chunk.append(sample)
                                stream['imu_outlet'].push_chunk(chunk)

            time.sleep(0.001)

        except Exception as e:
            print(f"\n[CRITICAL ERROR] Background thread crashed: {e}")
            import traceback
            traceback.print_exc()

    def step4_start(self):
        # Step 4: Start the hardware stream and the background thread.
        if self.is_streaming:
            print("\nWarning: Data stream is already running.")
            return

        # Safety check: Ensure the pipeline is armed before starting
        current_state = self.aero.GetPipelineState()
        if current_state != 'Armed':
            print(f"\nError: Pipeline is currently '{current_state}'.")
            print("You must press '3' (Configure) to arm the pipeline before starting.")
            return

        print("\nStep 4: Starting hardware and multi-stream LSL broadcast...")
        self.aero.Start()
        self.is_streaming = True
        self.stream_thread = threading.Thread(target=self._streaming_loop, daemon=True)
        self.stream_thread.start()
        print("Success: LSL is broadcasting in the background. Terminal is ready for commands.")

    def step5_stop(self):
        # Step 5: Safely stop the stream and reset the pipeline.
        if not self.is_streaming:
            print("\nWarning: No data stream is currently running.")
            return

        print("\nStep 5: Stopping data stream and resetting pipeline...")
        self.is_streaming = False
        if self.stream_thread:
            self.stream_thread.join(timeout=1.0)

        self.aero.Stop()
        self.aero.ResetPipeline()
        print("Success: Hardware stopped and pipeline reset. System is offline.")


def main():
    runner = InteractiveLSLRunner()

    try:
        while True:
            print("\n" + "=" * 40)
            print("Delsys LSL Interactive Console")
            print("=" * 40)
            print("1. Validate Base Station")
            print("2. Scan Sensors and View Settings")
            print("3. Configure Pipeline and LSL (Multi-Stream)")
            print("4. Start Data Stream")
            print("5. Stop Data Stream and Reset")
            print("0. Exit Program")
            print("-" * 40)

            choice = input("Enter command number: ").strip()

            if choice == '1':
                runner.step1_validate()
            elif choice == '2':
                runner.step2_scan()
            elif choice == '3':
                runner.step3_configure()
            elif choice == '4':
                runner.step4_start()
            elif choice == '5':
                runner.step5_stop()
            elif choice == '0':
                print("\nShutting down system safely...")
                if runner.is_streaming:
                    runner.step5_stop()
                print("Exit successful.")
                break
            else:
                print("\nInvalid command. Please enter a number between 0 and 5.")

    except KeyboardInterrupt:
        # Catch Ctrl+C to perform a safe shutdown and prevent C# memory crashes
        print("\n\nDetected KeyboardInterrupt (Ctrl+C). Initiating emergency safe shutdown...")
        if runner.is_streaming:
            runner.step5_stop()
        print("Emergency shutdown complete. Exiting program.")


if __name__ == "__main__":
    main()