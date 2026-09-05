function signature = struct_signature(S)
% GOAL
%   Create a compact deterministic signature for a MATLAB configuration
%   struct used in provenance checks.
% METHOD
%   Preserve the current working configuration-signature algorithm exactly:
%   serialize ordered fields, convert to UTF-8 bytes, then compute two
%   lightweight modular checksums.

try
    txt = jsonencode(orderfields(S));
catch
    txt = evalc('disp(S)');
end

bytes = ...
    double(unicode2native(txt, 'UTF-8'));

if isempty(bytes)
    signature = "0-0-0";
    return;
end

idx = 1:numel(bytes);
m = 4294967291;

s1 = mod(sum(bytes), m);

s2 = mod( ...
    sum(mod(bytes .* mod(idx, m), m)), ...
    m);

signature = ...
    string(numel(bytes)) + ...
    "-" + compose('%.0f', s1) + ...
    "-" + compose('%.0f', s2);

end
