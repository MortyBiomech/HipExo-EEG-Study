import os
import glob
import statistics
import numpy as np
import pandas as pd
import scipy.io
from scipy.interpolate import interp1d
import pyxdf
import mne
from mne_bids import BIDSPath, write_raw_bids

# ==========================================
# 0. Configuration
# ==========================================
CURRENT_SUBJECT = "subject_1"
SUBJECT_FOLDER = "Sub-P2_1"
SUBJECT_ID = "Pilot2_1"
EXPERIMENT_DAY = "day2"
RUN_ID = "001"

PROJECT_ROOT = r"C:\2026SSArbeit\HipExo-EEG-Study"
DATA_ROOT = r"C:\2026SSArbeit\data\PilotTest2"
BIDS_ROOT = r"C:\2026SSArbeit\data\HipExo-EEG-Study_BIDS"

data_path = os.path.join(DATA_ROOT, SUBJECT_FOLDER, EXPERIMENT_DAY, "data")
if not os.path.exists(data_path):
    raise FileNotFoundError(f" Path does not exist: {data_path}")


# ==========================================
# 1. Dynamically load subject mapping dictionary
# ==========================================
def get_subject_info(subject_name, exp_day):
    # Use BDF-compatible abbreviated muscle names (strictly <= 16 characters)
    muscle_names = [
        'Tib_ant_R', 'Soleus_R', 'Gast_med_R', 'Vastus_med_R', 'Rect_fem_R', 'Biceps_fem_R', 'Glut_max_R',
        'Tib_ant_L', 'Soleus_L', 'Gast_med_L', 'Vastus_med_L', 'Rect_fem_L', 'Biceps_fem_L', 'Glut_max_L',
        'Trapezius_R', 'Trapezius_L', 'SCM_R', 'SCM_L', 'Zygomaticus'
    ]

    if subject_name == 'subject_1':
        signal_names = ['Delsys_S3_EMG', 'Delsys_S4_EMG', 'Delsys_S1_EMG', 'Delsys_S5_EMG', 'Delsys_S6_EMG',
                        'Delsys_S0_EMG', 'Delsys_S7_EMG', 'Delsys_S8_EMG', 'Delsys_S9_EMG', 'Delsys_S10_EMG',
                        'Delsys_S11_EMG', 'Delsys_S12_EMG', 'Delsys_S13_EMG', 'Delsys_S14_EMG', 'Delsys_S15_EMG',
                        'Delsys_S2_EMG', 'Delsys_S16_EMG', 'Delsys_S17_EMG', 'Delsys_S18_EMG']
    elif subject_name == 'subject_2':
        signal_names = ['4_Delsys_(0)AvantiSensor_Pair0_EMG', '5_Delsys_(0)AvantiSensor_Pair0_EMG',
                        '2_Delsys_(0)AvantiSensor_Pair0_EMG', '6_Delsys_(4)AvantiSensor_Pair4_EMG',
                        '7_Delsys_(5)AvantiSensor_Pair5_EMG', '1_Delsys_(0)AvantiSensor_Pair0_EMG',
                        '8_Delsys_(7)AvantiSensor_Pair7_EMG', '9_Delsys_(8)AvantiSensor_Pair8_EMG',
                        '10_Delsys_(9)AvantiSensor_Pair9_EMG', '11_Delsys_(10)AvantiSensor_Pair10_EMG',
                        '12_Delsys_(11)AvantiSensor_Pair11_EMG', '13_Delsys_(12)AvantiSensor_Pair12_EMG',
                        '14_Delsys_(13)AvantiSensor_Pair13_EMG', '15_Delsys_(14)AvantiSensor_Pair14_EMG',
                        '16_Delsys_(15)AvantiSensor_Pair15_EMG', '3_Delsys_(0)AvantiSensor_Pair0_EMG',
                        '17_Delsys_(17)DuoSensor_Pair17_EMG', '18_Delsys_(18)DuoSensor_Pair18_EMG',
                        '19_Delsys_(19)DuoSensor_Pair19_EMG']
    elif subject_name == 'subject_3':
        if exp_day == 'day1':
            signal_names = ['3_Delsys_(0)AvantiSensor_Pair0_EMG', '12_Delsys_(12)AvantiSensor_Pair12_EMG',
                            '10_Delsys_(10)AvantiSensor_Pair10_EMG', '13_Delsys_(13)AvantiSensor_Pair13_EMG',
                            '15_Delsys_(15)AvantiSensor_Pair15_EMG', '14_Delsys_(14)AvantiSensor_Pair14_EMG',
                            '5_Delsys_(4)AvantiSensor_Pair4_EMG', '7_Delsys_(7)AvantiSensor_Pair7_EMG',
                            '18_Delsys_(19)DuoSensor_Pair19_EMG', '16_Delsys_(17)DuoSensor_Pair17_EMG',
                            '9_Delsys_(9)AvantiSensor_Pair9_EMG', '6_Delsys_(5)AvantiSensor_Pair5_EMG',
                            '2_Delsys_(0)AvantiSensor_Pair0_EMG', '1_Delsys_(0)AvantiSensor_Pair0_EMG',
                            '8_Delsys_(8)AvantiSensor_Pair8_EMG', '4_Delsys_(0)AvantiSensor_Pair0_EMG',
                            '11_Delsys_(11)AvantiSensor_Pair11_EMG', '17_Delsys_(18)DuoSensor_Pair18_EMG', 'None']
        else:  # day2
            signal_names = ['3_Delsys_(0)AvantiSensor_Pair0_EMG', '4_Delsys_(0)AvantiSensor_Pair0_EMG',
                            '5_Delsys_(0)AvantiSensor_Pair0_EMG', '6_Delsys_(4)AvantiSensor_Pair4_EMG',
                            '7_Delsys_(5)AvantiSensor_Pair5_EMG', '1_Delsys_(0)AvantiSensor_Pair0_EMG',
                            '8_Delsys_(7)AvantiSensor_Pair7_EMG', '9_Delsys_(8)AvantiSensor_Pair8_EMG',
                            '10_Delsys_(9)AvantiSensor_Pair9_EMG', '11_Delsys_(10)AvantiSensor_Pair10_EMG',
                            '12_Delsys_(11)AvantiSensor_Pair11_EMG', '13_Delsys_(12)AvantiSensor_Pair12_EMG',
                            '14_Delsys_(13)AvantiSensor_Pair13_EMG', '15_Delsys_(14)AvantiSensor_Pair14_EMG',
                            '16_Delsys_(15)AvantiSensor_Pair15_EMG', '2_Delsys_(0)AvantiSensor_Pair0_EMG',
                            '17_Delsys_(17)DuoSensor_Pair17_EMG', '18_Delsys_(18)DuoSensor_Pair18_EMG',
                            '19_Delsys_(19)DuoSensor_Pair19_EMG']
    else:
        raise ValueError(f"Unknown subject: {subject_name}")

    # Create a DataFrame (like an Excel table in memory) to link IDs and names
    df = pd.DataFrame({'SensorID': range(1, 20), 'MuscleName': muscle_names, 'SignalName': signal_names})
    return df


subj_table = get_subject_info(CURRENT_SUBJECT, EXPERIMENT_DAY)


# ==========================================
# 2. Dynamic Session sorting
# ==========================================
def get_session_order(base_path):
    folder_names = [f for f in os.listdir(base_path) if os.path.isdir(os.path.join(base_path, f))]
    order_sessions = [None] * 8

    pre_match = [f for f in folder_names if 'NoExoPre' in f]
    order_sessions[0] = pre_match[0] if pre_match else 'NoExoPre_Missing'

    for k in range(1, 7):
        exo_match = [f for f in folder_names if f'Exo{k}' in f]
        order_sessions[k] = exo_match[0] if exo_match else f'Exo{k}_Missing'

    post_match = [f for f in folder_names if 'NoExoPost' in f]
    order_sessions[7] = post_match[0] if post_match else 'NoExoPost_Missing'

    return order_sessions


order_sessions = get_session_order(data_path)

# ==========================================
# 3. Main loop
# ==========================================
for s_idx, current_session in enumerate(order_sessions):
    if 'Missing' in current_session:
        continue

    print(f"\n========================================================")
    print(f"Processing Session [{s_idx + 1}/8]: {current_session} for {CURRENT_SUBJECT}...")

    session_eeg_dir = os.path.join(data_path, current_session, 'eeg')
    if not os.path.exists(session_eeg_dir):
        continue

    if SUBJECT_ID != 'Pilot2_2':
        filename = f"sub-{SUBJECT_ID}_{EXPERIMENT_DAY}_{current_session}_task-Default_run-{RUN_ID}_eeg.xdf"
    else:
        filename = f"sub-{SUBJECT_ID}_{current_session}_task-Default_run-{RUN_ID}_eeg.xdf"

    xdf_file = os.path.join(session_eeg_dir, filename)
    if not os.path.exists(xdf_file):
        print(f">> Cannot find the corresponding XDF file: {filename}. Skipping.")
        continue

    print(f">> Loading XDF: {filename}")
    streams, header = pyxdf.load_xdf(xdf_file)



    marker_stream = next((s for s in streams if 'GRF_Marker' in s['info']['name'][0]), None)
    emg_streams = [s for s in streams if s['info']['type'][0] == 'EMG' and len(s['time_stamps']) > 0]
    if not emg_streams:
        continue

    for s in emg_streams:
        print("=" * 40)
        print(s["info"]["name"][0])

        if "desc" in s["info"]:
            print(s["info"]["desc"])

    # 3.1 Core logic for interpolation alignment
    lengths = [len(s['time_stamps']) for s in emg_streams]
    mode_len = statistics.mode(lengths)
    ref_stream = next(s for s in emg_streams if len(s['time_stamps']) == mode_len)
    majority_time_stamps = ref_stream['time_stamps']
    majority_points = mode_len

    expected_labels, expected_stream_names = [], []
    for _, row in subj_table.iterrows():
        sig_name = row['SignalName'].strip()
        muscle = row['MuscleName'].strip()
        if sig_name == 'None': continue
        if any(kw in sig_name for kw in ['DuoSensor', 'S16', 'S17', 'S18']):
            expected_labels.extend([f"{muscle}_CH1", f"{muscle}_CH2"])
            expected_stream_names.extend([sig_name, sig_name])
        else:
            expected_labels.append(muscle)
            expected_stream_names.append(sig_name)

    num_expected_chans = len(expected_labels)
    raw_data_matrix = np.zeros((num_expected_chans, majority_points))

    for s in emg_streams:
        sname = s['info']['name'][0]
        raw_time = s['time_stamps']
        unique_time, unique_idx = np.unique(raw_time, return_index=True)
        target_rows = [i for i, name in enumerate(expected_stream_names) if name == sname]

        if target_rows:
            n_chans_in_stream = s['time_series'].shape[1]
            for ch_offset, row_idx in enumerate(target_rows):
                if ch_offset < n_chans_in_stream:
                    raw_data = s['time_series'][unique_idx, ch_offset]
                    interpolator = interp1d(unique_time, raw_data, kind='cubic', fill_value="extrapolate")
                    raw_data_matrix[row_idx, :] = interpolator(majority_time_stamps)
        # print(raw_data_matrix.min())
        # print(raw_data_matrix.max())
        # print(raw_data_matrix.dtype)

    # ---------------------------------------------------------
    # 4. Convert values from minivolts (mV) to MNE standard volts (V)
    # ---------------------------------------------------------
    raw_data_matrix *= 1e-3

    # print("\n========== Check each channel ==========")
    #
    # for i, ch_name in enumerate(expected_labels):
    #     ch_data = raw_data_matrix[i]
    #
    #     print(
    #         f"{i:02d} {ch_name:<20}"
    #         f" min={ch_data.min():.6f}"
    #         f" max={ch_data.max():.6f}"
    #         f" mean={ch_data.mean():.6f}"
    #     )
    #
    # print("\nOverall:")
    # print("min =", raw_data_matrix.min())
    # print("max =", raw_data_matrix.max())

    # 4.1  Construct MNE Raw object
    sfreq = float(emg_streams[0]['info']['nominal_srate'][0])
    info = mne.create_info(ch_names=expected_labels, sfreq=sfreq, ch_types=['emg'] * num_expected_chans)
    raw = mne.io.RawArray(raw_data_matrix, info)

    # print("\n========== Raw object ==========")
    #
    # for ch_name, ch_data in zip(raw.ch_names, raw.get_data()):
    #     print(
    #         f"{ch_name:<20}"
    #         f" min={ch_data.min():.6f}"
    #         f" max={ch_data.max():.6f}"
    #     )

    raw.info['line_freq'] = 50.0

    # 5. Extract and merge events
    annotations_onset, annotations_duration, annotations_description = [], [], []

    if marker_stream and len(marker_stream['time_stamps']) > 0:
        for t, name in zip(marker_stream['time_stamps'], marker_stream['time_series']):
            ev_type = name[0] if isinstance(name, list) else str(name)
            onset = t - majority_time_stamps[0]
            if onset >= 0:
                annotations_onset.append(onset)
                annotations_duration.append(0.0)
                annotations_description.append(ev_type)

    gait_mat_path = os.path.join(DATA_ROOT, SUBJECT_FOLDER, EXPERIMENT_DAY, "processed_EMG",
                                 f"{current_session}_run-{RUN_ID}_gait_events.mat")
    if os.path.exists(gait_mat_path):
        mat_data = scipy.io.loadmat(gait_mat_path, squeeze_me=True)
        if 'all_events' in mat_data:
            events_struct = mat_data['all_events']
            if not isinstance(events_struct, np.ndarray):
                events_struct = [events_struct]

            for ev in events_struct:
                ev_type = ev['type'] if isinstance(ev, np.void) else ev.type
                ev_time = ev['time'] if isinstance(ev, np.void) else ev.time
                if ('START' in str(ev_type) or 'END' in str(ev_type)) and 'Manual' not in str(ev_type): continue
                onset = float(ev_time) - majority_time_stamps[0]
                if onset >= 0:
                    annotations_onset.append(onset)
                    annotations_duration.append(0.0)
                    annotations_description.append(str(ev_type))

    # Labels must be added before resampling, so MNE automatically adjusts event timestamps
    if annotations_onset:
        my_annot = mne.Annotations(onset=annotations_onset, duration=annotations_duration,
                                   description=annotations_description)
        raw.set_annotations(my_annot)

    # ---------------------------------------------------------
    # 6. Integer resampling to resolve BDF block length divisibility error
    # ---------------------------------------------------------
    TARGET_SFREQ = 2000.0
    print(f">> Resampling data from {sfreq:.2f} Hz to {TARGET_SFREQ} Hz to meet BDF block requirements...")
    raw.resample(TARGET_SFREQ)

    # 7. Export to BIDS standard format
    clean_session = current_session.replace('ses-', '').replace('_', '')
    clean_subj_id = SUBJECT_ID.replace('_', '')

    bids_path = BIDSPath(
        subject=clean_subj_id,
        session=clean_session,
        task='Default',
        run=RUN_ID,
        datatype='emg',
        root=BIDS_ROOT,
        extension='.bdf'
    )

    # print("\n========== Physical range ==========")
    #
    # for ch_name, ch_data in zip(raw.ch_names, raw.get_data()):
    #     print(
    #         f"{ch_name:<20}"
    #         f"{np.nanmin(ch_data):.6f}  {np.nanmax(ch_data):.6f}"
    #     )
    #
    # print("Overall:")
    # print(np.nanmin(raw.get_data()))
    # print(np.nanmax(raw.get_data()))

    write_raw_bids(
        raw=raw,
        bids_path=bids_path,
        format='BDF',
        allow_preload=True,
        emg_placement='Measured',
        overwrite=True
    )
    print(f">> ✅ Successfully exported BIDS: Session {current_session}")

print("\n========================================================")
print("BIDS conversion fully completed!")