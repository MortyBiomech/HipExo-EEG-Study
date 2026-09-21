function signature = ica_identity_signature(EEG)
% GOAL
%   Identify the ICA decomposition used to review and group components.
% INPUT
%   An EEGLAB dataset or its loaded header.
% APPROACH
%   Hash the weights, sphere, ICA channel indices and channel order.
% OUTPUT
%   One content identity shared by runs using the same decomposition.
% USED BY
%   Manual IC review, ROI review and STUDY component selection.

assert(isfield(EEG, 'icaweights') && ~isempty(EEG.icaweights) && ...
    isfield(EEG, 'icasphere') && ~isempty(EEG.icasphere), ...
    'ICA identity requires weights and a sphere matrix.');

S.weights = double(EEG.icaweights);
S.sphere = double(EEG.icasphere);
assert(all(isfinite(S.weights(:))) && all(isfinite(S.sphere(:))) && ...
    size(S.weights, 2) == size(S.sphere, 1), ...
    'ICA weights and sphere must be finite and dimensionally compatible.');

assert(isfield(EEG, 'chanlocs') && ...
    numel(EEG.chanlocs) == EEG.nbchan, ...
    'ICA identity requires one channel label per EEG channel.');
S.channel_labels = reshape(string({EEG.chanlocs.labels}), 1, []);

if isfield(EEG, 'icachansind') && ~isempty(EEG.icachansind)
    S.channel_indices = double(EEG.icachansind(:)');
else
    assert(size(S.sphere, 2) == EEG.nbchan, ...
        'ICA channel indices are required for a channel subset.');
    S.channel_indices = 1:EEG.nbchan;
end

assert(numel(S.channel_indices) == size(S.sphere, 2) && ...
    all(S.channel_indices >= 1 & S.channel_indices <= EEG.nbchan & ...
        S.channel_indices == round(S.channel_indices)), ...
    'ICA channel indices do not match the sphere matrix.');

signature = hipexo.review_content_signature(S);
end
