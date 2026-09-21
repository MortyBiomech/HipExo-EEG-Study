function signature = eeglab_dataset_signature(filePath, profile)
% Compare loaded EEG values, not SET/FDT size, save date, or history.
% "signal" is for continuous preprocessing/AMICA: gait annotations do not
% affect training, but discontinuity boundaries and channel/rank data do.
% The default "analysis" also includes events, ICA, dipoles and timewarp data.
if nargin < 2, profile = "analysis"; end
assert(ismember(string(profile), ["signal", "analysis"]), 'Unknown EEG signature profile.');
if isstruct(filePath)
    EEG = filePath;
else
    assert(isfile(filePath), 'EEGLAB dataset not found: %s', char(filePath));
    if exist('pop_loadset', 'file') ~= 2, eeglab('nogui'); end
    [folder, name, ext] = fileparts(char(filePath));
    EEG = pop_loadset('filename', [name ext], 'filepath', folder);
end
assert(isnumeric(EEG.data) && ~isempty(EEG.data), 'EEG samples could not be read.');
assert(numel(EEG.data) == double(EEG.nbchan) * double(EEG.pnts) * double(EEG.trials), ...
    'EEG sample count does not match its header.');
S.samples = hipexo.content_signature(EEG.data);
fields = {'nbchan','srate','pnts','trials','xmin','xmax','times','chanlocs','ref'};
for k = 1:numel(fields)
    if isfield(EEG, fields{k}), S.(fields{k}) = EEG.(fields{k}); end
end
S.etc = struct();
etcFields = {'rank','interpolated_channels','bemobil_reref'};
if string(profile) == "analysis"
    fields = {'subject','condition','session','run','event','urevent','epoch', ...
        'icaweights','icasphere','icawinv','icachansind','dipfit','timewarp'};
    for k = 1:numel(fields)
        if isfield(EEG, fields{k}), S.(fields{k}) = EEG.(fields{k}); end
    end
    etcFields = [etcFields, {'bad_samples','remove_data_intervals','ic_classification', ...
        'eeg_retained_source_sample_ranges','eeg_source_sample_count', ...
        'subject_merge_source_manifest','rhs_epoching','grf_to_eeg_mapping', ...
        'eeg_timestamp_gaps','subject_level_concatenation', ...
        'eeg_first_lsl_time','eeg_last_lsl_time','source_xdf','source_metadata', ...
        'canonical_subject_id','original_subject_id', ...
        'hipexo_canonical_subject_id','hipexo_original_subject_id', ...
        'hipexo_bids_to_eeglab_no_resampling'}];
else
    S.boundaries = struct('latency', {}, 'duration', {});
    if isfield(EEG, 'event')
        for k = 1:numel(EEG.event)
            if ischar(EEG.event(k).type) || isstring(EEG.event(k).type)
                if strcmpi(string(EEG.event(k).type), "boundary")
                    duration = [];
                    if isfield(EEG.event, 'duration'), duration = EEG.event(k).duration; end
                    S.boundaries(end+1) = struct('latency', EEG.event(k).latency, 'duration', duration);
                end
            end
        end
    end
end
if isfield(EEG, 'etc')
    for k = 1:numel(etcFields)
        if isfield(EEG.etc, etcFields{k}), S.etc.(etcFields{k}) = EEG.etc.(etcFields{k}); end
    end
end
S = hipexo.remove_provenance_fields(S);
signature = hipexo.content_signature(S);
end
