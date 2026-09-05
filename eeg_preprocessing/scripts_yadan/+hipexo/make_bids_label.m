function label = make_bids_label(rawLabel)
% GOAL
%   Convert a raw project label into the compact alphanumeric label format
%   used by the HipExo-EEG BIDS/session naming rules.
% METHOD
%   Split the input into alphanumeric tokens, preserve the first token, and
%   concatenate later tokens using an uppercase first character.

rawLabel = char(string(rawLabel));

parts = regexp( ...
    rawLabel, ...
    '[A-Za-z0-9]+', ...
    'match');

if isempty(parts)
    label = "unknown";
    return;
end

label = string(parts{1});

for i = 2:numel(parts)

    p = string(parts{i});

    if strlength(p) == 0
        continue;
    end

    firstChar = ...
        upper(extractBetween(p, 1, 1));

    restChars = ...
        extractAfter(p, 1);

    label = ...
        label + firstChar + restChars;
end

end
