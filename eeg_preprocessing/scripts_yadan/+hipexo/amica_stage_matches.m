function matches = amica_stage_matches(EEG, stages, stageName, legacySignature)
% GOAL
%   Decide whether a saved stage has the current data and method identity.
% INPUT
%   Dataset header, expected stage signatures, stage name and full legacy key.
% APPROACH
%   Match the stage key; accept legacy output only on a complete data/config match.
% OUTPUT
%   True when the stage can be reused.
% USED BY
%   Step07 output checks and AMICA stage resume.
matches = false;
if ~isfield(EEG, 'etc'), return; end
if isfield(EEG.etc, 'amica_stage_signatures') && ...
        isfield(EEG.etc.amica_stage_signatures, stageName)
    matches = string(EEG.etc.amica_stage_signatures.(stageName)) == ...
        string(stages.(stageName));
elseif strlength(string(legacySignature)) > 0 && ...
        isfield(EEG.etc, 'amica_input_signature')
    matches = string(EEG.etc.amica_input_signature) == string(legacySignature);
end
end
