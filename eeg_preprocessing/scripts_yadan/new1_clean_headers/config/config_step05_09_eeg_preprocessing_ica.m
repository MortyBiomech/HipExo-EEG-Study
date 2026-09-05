function bemobil_config = config_step05_09_eeg_preprocessing_ica(P)
% GOAL
%   Define the BeMoBIL EEG preprocessing, AMICA, DIPFIT, and ICLabel
%   parameters used before manual cortical IC review.
%
% METHOD
%   Preserve the current working preprocessing settings while keeping
%   repeated clustering, ROI, and ERSP parameters out of this configuration.

arguments
    P (1,1) struct
end

%% Step 05 run control
% Operational switches only; these do not change the preprocessing method.

% If true, overwrite DoPreprocess from RecommendedDoPreprocess.
% Keep false when DoPreprocess is manually edited in the CSV.
bemobil_config.pipeline.reset_DoPreprocess_from_Recommended = false;

% Current working script setting:
% 1 = recompute preprocessing even when output exists.
% 0 = reuse verified output when provenance matches.
bemobil_config.pipeline.force_recompute_preprocessing = 1;

%% Step 06 preprocessing QC

bemobil_config.preprocessingQC.expectedChannels = 64;
bemobil_config.preprocessingQC.rankSampleLimit = 10000;

bemobil_config.preprocessingQC.processingVersion = ...
    "preprocessed_EEG_QC_v2_output_signature_2026-08-22";

bemobil_config.preprocessingQC.lineNoiseFrequencyHz = 50;
bemobil_config.preprocessingQC.maxLineNoisePeakDb = 8;
bemobil_config.preprocessingQC.maxInterpolatedChannelFraction = 0.20;

% Keep false when DoQC is manually controlled in the processing table.
bemobil_config.preprocessingQC.reset_DoQC_from_PreprocessingStatus = false;

%% Step 07 AMICA / DIPFIT / ICLabel run control

% Keep false when DoAMICA is manually controlled in the processing table.
bemobil_config.pipeline.reset_DoAMICA_from_PreprocessingQC = false;

% 1 = recompute even when verified outputs already exist.
% 0 = reuse complete outputs when their provenance matches.
bemobil_config.pipeline.force_recompute_amica = 0;

% If true and all expected outputs exist with matching provenance,
% update the processing table and skip the expensive AMICA rerun.
bemobil_config.pipeline.skip_existing_complete_amica_outputs = true;

% Structural safety gate before AMICA.
bemobil_config.pipeline.expectedChannelsBeforeAMICA = 64;

%% Step 08 AMICA / ICA quality control

bemobil_config.icaQC.expectedChannels = 64;
bemobil_config.icaQC.rankSampleLimit = 10000;

% RV thresholds are fractions, not percentages.
bemobil_config.icaQC.rvThreshold15 = 0.15;
bemobil_config.icaQC.rvThreshold20 = 0.20;

bemobil_config.icaQC.maxAMICABadSamplesPercent = 20;

% Keep false when DoICAQC is manually controlled in the processing table.
bemobil_config.icaQC.reset_DoICAQC_from_AMICAStatus = false;

%% Step 09 manual IC review workbook

bemobil_config.manualICReview.workbookName = ...
    'manual_IC_selection_final.xlsx';

bemobil_config.manualICReview.sheetName = ...
    'Manual_IC_Selection';

%% General output structure

bemobil_config.study_folder = [P.outputFolder filesep];
bemobil_config.filename_prefix = 'sub-';

bemobil_config.raw_EEGLAB_data_folder = ...
    ['2_raw-EEGLAB' filesep];

bemobil_config.EEG_preprocessing_data_folder = ...
    ['3_EEG-preprocessing' filesep];

bemobil_config.spatial_filters_folder = ...
    ['4_spatial-filters' filesep];

bemobil_config.spatial_filters_folder_AMICA = ...
    ['4-1_AMICA' filesep];

bemobil_config.single_subject_analysis_folder = ...
    ['5_single-subject-EEG-analysis' filesep];

bemobil_config.single_subject_motion_folder = ...
    ['6_single-subject-motion-analysis' filesep];

bemobil_config.single_subject_eye_folder = ...
    ['7_single-subject-EYE-analysis' filesep];

%% Dataset filenames

bemobil_config.merged_filename = 'merged_EEG.set';
bemobil_config.basic_prepared_filename = 'basic_prepared.set';
bemobil_config.preprocessed_filename = 'preprocessed.set';
bemobil_config.filtered_filename = 'filtered.set';

bemobil_config.amica_filename_output = 'AMICA.set';
bemobil_config.dipfitted_filename = 'dipfitted.set';
bemobil_config.preprocessed_and_ICA_filename = ...
    'preprocessed_and_ICA.set';
bemobil_config.single_subject_cleaned_ICA_filename = ...
    'cleaned_with_ICA.set';

bemobil_config.raw_motion_filename = 'merged_MOTION.set';
bemobil_config.processed_motion_filename = 'motion_processed.set';

bemobil_config.eye_raw_filename = 'merged_PHYSIO.set';
bemobil_config.eye_clean_filename = 'eye_clean.set';

%% EEG preprocessing

bemobil_config.channels_to_remove = { ...
    'LiveAmpSN-102108-1139_ACC_X', ...
    'LiveAmpSN-102108-1139_ACC_Y', ...
    'LiveAmpSN-102108-1139_ACC_Z'};

bemobil_config.eog_channels = {};
bemobil_config.ref_channel = [];

bemobil_config.rename_channels = { ...
    'LiveAmpSN-102108-1139_'};

% Keep the original sampling frequency.
bemobil_config.resample_freq = [];

%% Automatic bad-channel cleaning

bemobil_config.chancorr_crit = 0.8;
bemobil_config.chan_max_broken_time = 0.3;
bemobil_config.chan_detect_num_iter = 10;
bemobil_config.chan_detected_fraction_threshold = 0.5;

bemobil_config.flatline_crit = 'off';
bemobil_config.line_noise_crit = 'off';

bemobil_config.num_chan_rej_max_target = 1/5;

% Channel locations already exist in the current imported datasets.
bemobil_config.channel_locations_filename = [];

%% ZapLine-Plus

% Empty = automatic line-noise-frequency detection.
bemobil_config.zaplineConfig.noisefreqs = [];

%% AMICA

bemobil_config.filter_lowCutoffFreqAMICA = 1.5;
bemobil_config.filter_AMICA_highPassOrder = 1650;

bemobil_config.filter_highCutoffFreqAMICA = [];
bemobil_config.filter_AMICA_lowPassOrder = [];

bemobil_config.num_models = 1;
bemobil_config.AMICA_autoreject = 1;
bemobil_config.AMICA_n_rej = 10;
bemobil_config.AMICA_reject_sigma_threshold = 3;
bemobil_config.AMICA_max_iter = 2000;
bemobil_config.max_threads = 4;

% Do not delete or ASR-reconstruct continuous samples before AMICA.
bemobil_config.use_reject_continuous = 0;

bemobil_config.warping_channel_names = [];

%% DIPFIT

bemobil_config.residualVariance_threshold = 100;
bemobil_config.do_remove_outside_head = 'off';
bemobil_config.number_of_dipoles = 1;

%% ICLabel

bemobil_config.iclabel_classifier = 'lite';

% Keep classes:
% 1 Brain
% 2 Muscle
% 4 Heart
% 5 Line Noise
% 6 Channel Noise
% 7 Other
%
% Dominant Eye components are removed from cleaned_with_ICA.
% preprocessed_and_ICA remains the source for manual cortical IC review.
bemobil_config.iclabel_classes = [1 2 4 5 6 7];
bemobil_config.iclabel_threshold = -1;

%% Final filtering

bemobil_config.final_filter_lower_edge = 0.2;
bemobil_config.final_filter_higher_edge = [];

%% Motion processing

bemobil_config.lowpass_motion = 8;
bemobil_config.lowpass_motion_after_derivative = 24;

%% EEGLAB storage settings

bemobil_config.eeglab_options.option_saveversion6 = 0;
bemobil_config.eeglab_options.option_single = 0;
bemobil_config.eeglab_options.option_memmapdata = 0;
bemobil_config.eeglab_options.option_savetwofiles = 1;
bemobil_config.eeglab_options.option_storedisk = 0;

end
