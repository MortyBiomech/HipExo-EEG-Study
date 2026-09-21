function condition = canonical_condition(raw)
% GOAL
%   Resolve the existing recorded condition aliases to a canonical code.
% INPUT
%   One recorded condition label.
% APPROACH
%   Normalize punctuation and use the explicit priority in the condition table.
% OUTPUT
%   Canonical code, or an empty string for an unrecognized label.
% USED BY
%   Step10 recording and gait-event metadata.
key = regexprep(lower(char(string(raw))), '[^a-z0-9]', '');
conditions = sortrows(config_analysis_conditions(), 'MatchPriority');
condition = "";
for k = 1:height(conditions)
    if ~isempty(regexp(key, char(conditions.Pattern(k)), 'once'))
        condition = conditions.Code(k);
        return;
    end
end
end
