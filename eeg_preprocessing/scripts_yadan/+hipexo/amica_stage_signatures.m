function stages = amica_stage_signatures(cfg, datasetSignature)
% GOAL
%   Identify the inputs of each AMICA pipeline stage separately.
% INPUT
%   Effective BeMoBIL configuration and preprocessed .set/.fdt signature.
% APPROACH
%   Each stage includes its upstream signature and only its own method settings.
% OUTPUT
%   AMICA, DIPFIT, ICLabel, final-filter and cleaned-output identities.
% USED BY
%   Step07 and mod_bemobil_process_all_AMICA.
trainNames = {'filter_lowCutoffFreqAMICA', 'filter_AMICA_highPassOrder', ...
    'filter_highCutoffFreqAMICA', 'filter_AMICA_lowPassOrder', ...
    'num_models', 'AMICA_autoreject', 'AMICA_n_rej', ...
    'AMICA_reject_sigma_threshold', 'AMICA_max_iter', 'max_threads', ...
    'use_reject_continuous'};
train = take_fields(cfg, trainNames);
if cfg.use_reject_continuous
    threshold = 0.07;
    if isfield(cfg, 'reject_continuous_fixed_threshold') && ...
            ~isempty(cfg.reject_continuous_fixed_threshold)
        threshold = cfg.reject_continuous_fixed_threshold;
    end
    train.reject_continuous = struct('threshold', threshold, ...
        'length', 0.5, 'overlap', 0.125, 'buffer', 0.0625, ...
        'weights', [1 1 1 1], 'kneepoint', 0, 'offset', 0, 'highpass', 10);
end
stages.amica = sign_stage(datasetSignature, train);
stages.dipfit = sign_stage(stages.amica, take_fields(cfg, ...
    {'warping_channel_names', 'residualVariance_threshold', ...
    'do_remove_outside_head', 'number_of_dipoles'}));
stages.iclabel = sign_stage(stages.dipfit, take_fields(cfg, {'iclabel_classifier'}));
stages.prefinal = sign_stage(stages.iclabel, take_fields(cfg, ...
    {'final_filter_lower_edge', 'final_filter_higher_edge'}));
stages.cleaned = sign_stage(stages.prefinal, take_fields(cfg, ...
    {'iclabel_classes', 'iclabel_threshold'}));
end

function S = take_fields(cfg, names)
S = struct();
for k = 1:numel(names), S.(names{k}) = cfg.(names{k}); end
end

function signature = sign_stage(upstream, settings)
signature = hipexo.content_signature(struct('upstream', upstream, 'settings', settings));
end
