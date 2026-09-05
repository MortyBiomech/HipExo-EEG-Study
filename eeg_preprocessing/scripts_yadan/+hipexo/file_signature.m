function signature = file_signature(filePath)
% GOAL
%   Create a lightweight provenance signature for one existing file.
% METHOD
%   Use file metadata rather than reading file contents so provenance checks
%   remain fast for large XDF, MAT, and EEGLAB files.

filePath = char(string(filePath));

fileInfo = dir(filePath);

if numel(fileInfo) ~= 1
    error('Cannot create a file signature for:\n%s', filePath);
end

signature = string(sprintf( ...
    '%s|bytes=%d|datenum=%.15f', ...
    filePath, ...
    fileInfo.bytes, ...
    fileInfo.datenum));

end
