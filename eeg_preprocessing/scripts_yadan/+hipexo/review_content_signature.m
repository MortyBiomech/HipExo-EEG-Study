function signature = review_content_signature(value)
% Keep the established manual-review identifier format for existing workbooks.
% GOAL
%   Identify small analysis inputs by their content.
% INPUT
%   JSON-serializable values, configuration structs or tables.
% APPROACH
%   Order struct fields and hash UTF-8 JSON with SHA-256.
% OUTPUT
%   A hexadecimal string independent of file paths and modification times.
% USED BY
%   Review identities and stage-specific input comparisons.

value = canonical_value_local(value);
bytes = unicode2native(jsonencode(value), 'UTF-8');
digest = java.security.MessageDigest.getInstance('SHA-256');
digest.update(typecast(uint8(bytes(:)), 'int8'));
hashBytes = typecast(digest.digest(), 'uint8');
signature = string(lower(reshape(dec2hex(hashBytes, 2).', 1, [])));
end

function value = canonical_value_local(value)
if istable(value)
    value = table2struct(value);
end
if isstruct(value)
    value = orderfields(value);
    names = fieldnames(value);
    for k = 1:numel(value)
        for n = 1:numel(names)
            value(k).(names{n}) = canonical_value_local(value(k).(names{n}));
        end
    end
elseif iscell(value)
    for k = 1:numel(value)
        value{k} = canonical_value_local(value{k});
    end
end
end
