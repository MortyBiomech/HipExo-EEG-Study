function signature = file_metadata_signature(filePath)
% Historical function name retained for callers. Checks complete contents.
% MAT containers are read by variable so save headers/dates are irrelevant.
filePath = char(string(filePath));
assert(isfile(filePath), 'Input file does not exist: %s', filePath);
[~, ~, ext] = fileparts(filePath);
if strcmpi(ext, '.set')
    signature = hipexo.eeglab_dataset_signature(filePath);
    return;
end
if ismember(lower(string(ext)), [".mat", ".icatimef"])
    variables = whos('-file', filePath);
    names = sort(string({variables.name}));
    if any(names == "grfData")
        names = intersect(names, ["grfData","grfTimeStamps","grfTimeSec", ...
            "intervalTable","xdfFile","channelLabels","nominalSrate","measuredSrate"], 'stable');
    elseif any(names == "allEventTable")
        names = intersect(names, ["allEventTable","intervalTable"], 'stable');
    else
        names = names(~ismember(names, ["processingInfo","created_on","created_at"]));
    end
    parts = strings(numel(names), 1);
    for k = 1:numel(names)
        item = load(filePath, char(names(k)), '-mat');
        parts(k) = hipexo.content_signature(hipexo.remove_provenance_fields(item));
    end
    signature = hipexo.content_signature(struct('names', names, 'values', parts));
    return;
end
fid = fopen(filePath, 'rb');
assert(fid >= 0, 'Cannot read input: %s', filePath);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
% File length only bounds the read; it is NOT part of the content signature.
assert(fseek(fid, 0, 'eof') == 0, 'Cannot seek input: %s', filePath);
expectedBytes = ftell(fid);
assert(expectedBytes >= 0 && fseek(fid, 0, 'bof') == 0, ...
    'Cannot determine input length or rewind: %s', filePath);
remainingBytes = expectedBytes;
digest = java.security.MessageDigest.getInstance('SHA-256');
while remainingBytes > 0
    requestedBytes = min(2^20, remainingBytes); % I/O buffer only.
    [bytes, count] = fread(fid, requestedBytes, '*uint8');
    if count ~= requestedBytes
        message = ferror(fid);
        error('hipexo:IncompleteContentRead', ...
            'Incomplete read of %s: expected %g bytes, received %g. %s', ...
            filePath, requestedBytes, count, message);
    end
    digest.update(typecast(bytes(:), 'int8'));
    remainingBytes = remainingBytes - count;
end
% Do not use ferror == 0 as an EOF test: normal EOF can set a message.
assert(fseek(fid, 0, 'eof') == 0 && ftell(fid) == expectedBytes, ...
    'Input length changed while hashing; retry after saving completes: %s', filePath);
hashBytes = typecast(digest.digest(), 'uint8');
signature = "file-sha256:" + string(lower(reshape(dec2hex(hashBytes, 2).', 1, [])));
end
