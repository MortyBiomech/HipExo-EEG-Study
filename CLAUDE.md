# CLAUDE.md

This file describes the project structure and conventions for Claude Code.

---

## Project Overview

This repository contains a multimodal mobile brain/body imaging (MoBI) analysis
pipeline for investigating cortical dynamics during exoskeleton-assisted walking.
EEG, EMG, and ground reaction force (GRF) data are recorded simultaneously via
Lab Streaming Layer (LSL) during treadmill walking across multiple exoskeleton
assistance conditions.

Developed at the Lauflabor Locomotion Lab, Technical University of Darmstadt.

---

## Repository Structure

```
config/                       - study parameters, subject list, condition names,
                                channel indices, threshold values, folder paths
acquisition/                  - Python GUI for GRF streaming and event marking,
                                Arduino timer interrupt code for GRF acquisition
stage1_per_condition/         - per-condition processing: GRF event detection,
                                EEG event import, saving .set and .mat outputs
stage2_concatenated/          - merging conditions, BeMoBIL preprocessing, AMICA
stage3_postprocessing/        - epoching, ERSP, CMC, statistical analysis
utils/                        - shared helper functions used across stages
run_all.m                     - master script looping over all subjects and conditions
CONTRIBUTING.md               - collaboration guide for students
CLAUDE.md                     - this file
```

---

## Data Structure (outside this repository)

```
data/
└── sub-XX/
    ├── 0_raw_xdf/            - raw LSL recordings (.xdf files, one per condition)
    ├── 1_stage1/             - per-condition EEG .set files and events .mat files
    ├── 2_stage2/             - merged, preprocessed, and ICA-decomposed datasets
    └── 3_stage3/             - epoched data, ERSP, CMC, statistical outputs
```

Data is never committed to git. Local data path is set in
`config/study_config.m` which is gitignored.

---

## Experimental Design

- Participants walk on an instrumented split-belt treadmill at 4.2 km/h
- Conditions: No_Exo_Pre, multiple exoskeleton assistance profiles, No_Exo_Post
- Each condition recording contains:
  - Standing period before walking (standing_1)
  - Steady-state walking at 4.2 km/h (~4 minutes)
  - Standing period after walking (standing_2)
- Conditions are recorded as separate XDF files
- Order is randomized per subject
- Between conditions: subject fills a questionnaire (not recorded)

---

## Key Streams (LSL)

- **GRF** - 8-channel force data from instrumented treadmill at ~150 Hz
  - Right leg: channels [1 4 5 8]
  - Left leg:  channels [2 3 6 7]
- **GRF_Markers** - string-based marker stream (irregular rate)
  - Marker labels: START_standing_ConditionX_1, END_standing_ConditionX_1,
                   START_ConditionX, END_ConditionX,
                   START_standing_ConditionX_2, END_standing_ConditionX_2
- **EEG** - 67-channel EEG from Brain Products LiveAmp at 500 Hz

---

## Gait Events

Detected from GRF signals during steady-state walking period:

- **RHS** - Right Heel Strike
- **RTO** - Right Toe Off
- **LHS** - Left Heel Strike
- **LTO** - Left Toe Off

Detection uses hysteresis thresholding. Parameters are set in
`config/study_config.m`. Events are stored with LSL timestamps for
cross-stream synchronization with EEG and EMG.

---

## Key Conventions

- All parameters come from `config/study_config.m` - no hardcoded values
- No hardcoded paths anywhere in the codebase
- No hardcoded subject numbers or condition names
- Every MATLAB function has a header comment with inputs and outputs documented
- Data files (.xdf, .set, .fdt, .mat) are never committed to git
- Timestamps are always in LSL clock reference frame for cross-stream alignment

---

## Pipeline Stages

### Stage 1 - Per condition
Run `stage1_per_condition/stage1_process_condition.m` for each subject
and condition. Loads GRF and EEG from XDF, detects gait events, adds all
events to the EEG structure, saves .set and .mat outputs.

### Stage 2 - Concatenated
Merges all conditions in chronological order, rejects non-experimental
periods, runs BeMoBIL preprocessing pipeline (line noise removal, bad
channel detection and interpolation, full-rank average reference,
high-pass filter at 1 Hz), then runs AMICA, dipole fitting, and IC labeling.

### Stage 3 - Post-processing
Epochs around RHS events, computes ERSP and corticomuscular coherence (CMC),
performs statistical comparison across conditions. Analysis domain (time,
frequency, time-frequency) and baseline strategy are defined per analysis.

---

## Dependencies

- MATLAB R2022b or later
- EEGLAB (latest stable)
- BeMoBIL Pipeline (EEGLAB plugin)
- AMICA
- Python 3.x with pyserial and pylsl (acquisition only)

---

## Branch Structure

```
main      - stable pipeline only
dev       - integration branch
feature/  - individual development branches
```

Always work on feature branches. Never commit directly to main or dev.
See CONTRIBUTING.md for full collaboration guide.
