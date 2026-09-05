function rows = session_peer_rows(T, rowIdx)
% GOAL
%   Return all imported table rows that belong to the same BIDS subject and
%   session as one reference row.
% METHOD
%   Match BidsSubject and BidsSession and, when DoImport exists, restrict the
%   peer set to rows with DoImport == 1.

rows = rowIdx;

required = {'BidsSubject', 'BidsSession'};

if ~all(ismember(required, T.Properties.VariableNames))
    return;
end

subjectValues = T.BidsSubject;

if ~isnumeric(subjectValues)
    subjectValues = str2double(string(subjectValues));
end

sessionValues = string(T.BidsSession);
sessionValues(ismissing(sessionValues)) = "";

subjectValue = subjectValues(rowIdx);
sessionValue = sessionValues(rowIdx);

if isnan(subjectValue) || ...
        strlength(strtrim(sessionValue)) == 0
    return;
end

mask = ...
    subjectValues == subjectValue & ...
    sessionValues == sessionValue;

if ismember('DoImport', T.Properties.VariableNames)

    doImport = T.DoImport;

    if ~isnumeric(doImport)
        doImport = str2double(string(doImport));
    end

    mask = ...
        mask & ...
        doImport == 1;
end

matchedRows = find(mask);

if ~isempty(matchedRows)
    rows = matchedRows;
end

end
