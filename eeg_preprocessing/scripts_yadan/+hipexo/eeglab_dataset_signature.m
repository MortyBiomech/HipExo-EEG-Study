function signature = eeglab_dataset_signature(filePath)
% GOAL
%   Create the provenance signature used for an EEGLAB dataset input.
% METHOD
%   Preserve the current working signature logic exactly. For a .set file,
%   include both .set and companion .fdt metadata when the .fdt exists.

info = dir(char(filePath));

if isempty(info)
    signature = "missing";
else
    signature = ...
        string(info.bytes) + "|" + ...
        compose('%.15g', info.datenum);

    [folder, base, ext] = ...
        fileparts(char(filePath));

    if strcmpi(ext, '.set')

        fdtInfo = ...
            dir(fullfile(folder, [base '.fdt']));

        if ~isempty(fdtInfo)

            signature = ...
                signature + ...
                "|fdt=" + ...
                string(fdtInfo.bytes) + ...
                "|" + ...
                compose('%.15g', fdtInfo.datenum);
        end
    end
end

end
