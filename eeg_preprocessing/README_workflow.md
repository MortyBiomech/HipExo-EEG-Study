# EEG Preprocessing Workflow

This folder contains the EEG preprocessing workflow for the HipExo EEG PilotTest2 dataset.

The scripts should be run in this order:

```text
1. check_eeg_streams.m
2. import_table.m
3. bemobil_import.m
4. bemobil_process_all_EEG_data.m
5. check_preprocessed_EEG.m
6. bemobil_run_AMICA_only.m
```

## Script purpose

### `paths.m`

Defines all central project paths, such as the raw data folder, output folder, EEGLAB folder, FieldTrip folder, BeMoBIL folder, and import table path.

Only this file should be edited when the project location changes.

### `bemobil_config_.m`

Contains the BeMoBIL preprocessing settings, including channel removal, channel renaming, resampling frequency, bad-channel detection, ZapLine-Plus settings, and AMICA parameters.

### `check_eeg_streams.m`

Scans all XDF files and checks which files contain a real EEG stream.

It saves two summary tables:

```text
xdf_file_stream_summary.csv
xdf_stream_detail_table.csv
```

### `import_table.m`

Creates the central import table:

```text
bemobil_import_table.csv
```

This table stores the XDF path, file name, subject/session labels, task, run number, EEG stream name, sampling rate, and channel count.

### `bemobil_import.m`

Imports selected XDF files where:

```text
DoImport = 1
```

It converts the data from:

```text
XDF → BIDS → EEGLAB .set
```

### `bemobil_process_all_EEG_data.m`

Runs basic EEG preprocessing for rows where:

```text
DoPreprocess = 1
```

This script does not run AMICA. AMICA is separated because it is slow and should only be run after preprocessing is checked.

### `check_preprocessed_EEG.m`

Checks the preprocessed EEG output for rows where:

```text
DoQC = 1
```

It checks the number of channels, sampling rate, channel locations, ACC channel removal, and source information.

### `bemobil_run_AMICA_only.m`

Runs AMICA for rows where:

```text
DoAMICA = 1
```

This script loads the already preprocessed EEG dataset and does not rerun basic preprocessing.

## Control table columns

The main control columns are:

```text
DoImport = 1        import this XDF file
DoPreprocess = 1    run basic EEG preprocessing
DoQC = 1            check preprocessing output
DoAMICA = 1         run AMICA
```

Set the value to `0` to skip that step for a file.



## Summary

This workflow first scans the raw XDF files, creates a central import table, imports selected EEG files, runs basic preprocessing, checks the preprocessing output, and finally runs AMICA only on selected preprocessed datasets.
