function signature = amica_scientific_signature(bemobil_config)
% GOAL
%   Create a provenance signature from only settings that can change the
%   AMICA/DIPFIT/ICLabel/final-cleaned output.
% METHOD
%   Exclude force/skip switches, QC thresholds, workbook settings, output
%   paths/filenames, and later clustering/ERSP parameters. The input
%   .set/.fdt signature separately captures the preprocessed EEG data.

S = struct();

S.signature_version = ...
    "HipExo_amica_scientific_config_v1";

S.filter_lowCutoffFreqAMICA = ...
    bemobil_config.filter_lowCutoffFreqAMICA;

S.filter_AMICA_highPassOrder = ...
    bemobil_config.filter_AMICA_highPassOrder;

S.filter_highCutoffFreqAMICA = ...
    bemobil_config.filter_highCutoffFreqAMICA;

S.filter_AMICA_lowPassOrder = ...
    bemobil_config.filter_AMICA_lowPassOrder;

S.num_models = bemobil_config.num_models;
S.AMICA_autoreject = bemobil_config.AMICA_autoreject;
S.AMICA_n_rej = bemobil_config.AMICA_n_rej;

S.AMICA_reject_sigma_threshold = ...
    bemobil_config.AMICA_reject_sigma_threshold;

S.AMICA_max_iter = bemobil_config.AMICA_max_iter;
S.max_threads = bemobil_config.max_threads;
S.use_reject_continuous = bemobil_config.use_reject_continuous;
S.warping_channel_names = bemobil_config.warping_channel_names;

S.residualVariance_threshold = ...
    bemobil_config.residualVariance_threshold;

S.do_remove_outside_head = ...
    bemobil_config.do_remove_outside_head;

S.number_of_dipoles = ...
    bemobil_config.number_of_dipoles;

S.iclabel_classifier = bemobil_config.iclabel_classifier;
S.iclabel_classes = bemobil_config.iclabel_classes;
S.iclabel_threshold = bemobil_config.iclabel_threshold;

S.final_filter_lower_edge = ...
    bemobil_config.final_filter_lower_edge;

S.final_filter_higher_edge = ...
    bemobil_config.final_filter_higher_edge;

signature = hipexo.struct_signature(S);

end
