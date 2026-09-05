function signature = preprocessing_scientific_signature(bemobil_config)
% GOAL
%   Create a provenance signature from only settings that can change the
%   numerical/basic EEG preprocessing result.
% METHOD
%   Exclude force/skip switches, QC thresholds, workbook settings, output
%   paths/filenames, AMICA/DIPFIT/ICLabel settings, and later analysis
%   parameters.

S = struct();

S.signature_version = ...
    "HipExo_preprocessing_scientific_config_v1";

S.channels_to_remove = bemobil_config.channels_to_remove;
S.eog_channels = bemobil_config.eog_channels;
S.ref_channel = bemobil_config.ref_channel;
S.rename_channels = bemobil_config.rename_channels;
S.resample_freq = bemobil_config.resample_freq;

S.chancorr_crit = bemobil_config.chancorr_crit;
S.chan_max_broken_time = bemobil_config.chan_max_broken_time;
S.chan_detect_num_iter = bemobil_config.chan_detect_num_iter;
S.chan_detected_fraction_threshold = ...
    bemobil_config.chan_detected_fraction_threshold;

S.flatline_crit = bemobil_config.flatline_crit;
S.line_noise_crit = bemobil_config.line_noise_crit;
S.num_chan_rej_max_target = bemobil_config.num_chan_rej_max_target;
S.channel_locations_filename = bemobil_config.channel_locations_filename;
S.zaplineConfig = bemobil_config.zaplineConfig;

signature = hipexo.struct_signature(S);

end
