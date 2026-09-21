function fileBase = tf_cache_file_base(STUDY, datasetIndex)
% GOAL
%   Resolve the EEGLAB subject/session component TF cache name.
% INPUT
%   STUDY and a datasetinfo position belonging to the ICA unit.
% APPROACH
%   Follow the single-session versus multiple-session EEGLAB naming rule.
% OUTPUT
%   Full filename without the .icatimef extension.
% USED BY
%   Step14 precomputation and component/run ERSP reading.
sessions = cellfun(@(x) session_text(x), {STUDY.datasetinfo.session}, ...
    'UniformOutput', false);
info = STUDY.datasetinfo(datasetIndex);
if numel(unique(string(sessions))) == 1
    name = char(string(info.subject));
else
    name = sprintf('%s_ses-%s', char(string(info.subject)), sessions{datasetIndex});
end
fileBase = fullfile(info.filepath, name);
end

function value = session_text(raw)
if isempty(raw), raw = 1; end
value = char(string(raw));
end
