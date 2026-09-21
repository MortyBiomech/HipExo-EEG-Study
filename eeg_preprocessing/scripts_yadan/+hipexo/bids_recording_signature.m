function signature = bids_recording_signature(headerPath)
%BIDS_RECORDING_SIGNATURE Content signature for one BIDS EEG recording.
% Includes every file sharing the recording entity prefix in the same eeg/
% directory (BrainVision files and recording-level BIDS sidecars).

headerPath = char(string(headerPath));
assert(isfile(headerPath), 'BIDS EEG header does not exist:\n%s', headerPath);
[folder, stem, ext] = fileparts(headerPath);
assert(strcmpi(ext,'.vhdr'), 'Expected a BrainVision .vhdr file: %s', headerPath);
prefix = regexprep(stem, '_eeg$', '');
entries = dir(fullfile(folder, [prefix '*']));
entries = entries(~[entries.isdir]);
assert(~isempty(entries), 'No files found for BIDS recording prefix %s.', prefix);
paths = sort(string(fullfile({entries.folder},{entries.name})))';
parts = strings(numel(paths),1);
for i = 1:numel(paths)
    parts(i) = hipexo.file_metadata_signature(char(paths(i)));
end
signature = hipexo.content_signature(struct( ...
    'files', sort(string({entries.name})), 'contents', parts));
end
