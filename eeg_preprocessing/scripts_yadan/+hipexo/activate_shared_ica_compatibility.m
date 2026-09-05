function info = activate_shared_ica_compatibility(compatibilityFolder)
% GOAL
%   Activate and verify the project-local shared-ICA compatibility copies of
%   EEGLAB std_preclust and BeMoBIL bemobil_dipoles.
% METHOD
%   Resolve original package functions with the compatibility folder removed,
%   then activate fixed audited copies at the front of the MATLAB path.
%   Original EEGLAB/BeMoBIL installation files are never modified.

compatibilityFolder = char(string(compatibilityFolder));

assert(exist(compatibilityFolder, 'dir') == 7, ...
    'Compatibility folder does not exist:\n%s', ...
    compatibilityFolder);

stdPatch = fullfile(compatibilityFolder, 'std_preclust.m');
dipolesPatch = fullfile(compatibilityFolder, 'bemobil_dipoles.m');

assert(exist(stdPatch, 'file') == 2, ...
    'Missing shared-ICA std_preclust compatibility file:\n%s', ...
    stdPatch);

assert(exist(dipolesPatch, 'file') == 2, ...
    'Missing shared-ICA bemobil_dipoles compatibility file:\n%s', ...
    dipolesPatch);

try
    rmpath(compatibilityFolder);
catch
end

clear std_preclust;
clear bemobil_dipoles;
rehash path;

stdOriginal = which('std_preclust');
dipolesOriginal = which('bemobil_dipoles');

assert(~isempty(stdOriginal), ...
    'Could not locate original EEGLAB std_preclust.m.');

assert(~isempty(dipolesOriginal), ...
    'Could not locate original BeMoBIL bemobil_dipoles.m.');

assert(~same_path_local(stdOriginal, stdPatch), ...
    'Original std_preclust unexpectedly resolves to compatibility/.');

assert(~same_path_local(dipolesOriginal, dipolesPatch), ...
    'Original bemobil_dipoles unexpectedly resolves to compatibility/.');

addpath(compatibilityFolder, '-begin');

clear std_preclust;
clear bemobil_dipoles;
rehash path;

activeStd = which('std_preclust');
activeDipoles = which('bemobil_dipoles');

assert(same_path_local(activeStd, stdPatch), ...
    ['std_preclust compatibility copy is not active.\n' ...
     'Active:\n%s\nExpected:\n%s'], ...
    activeStd, stdPatch);

assert(same_path_local(activeDipoles, dipolesPatch), ...
    ['bemobil_dipoles compatibility copy is not active.\n' ...
     'Active:\n%s\nExpected:\n%s'], ...
    activeDipoles, dipolesPatch);

stdText = fileread(stdPatch);

assert(contains(stdText, ...
        'find(isfinite(STUDY.cluster(cluster_ind).sets(:,si))'), ...
    ['std_preclust compatibility copy does not contain the audited ' ...
     'shared-ICA representative-dataset handling.']);

dipolesText = fileread(dipolesPatch);

requiredFragments = { ...
    'isfinite(thisICdatasets)', ...
    'abset = thisICdatasets(1)', ...
    'isOutlierCluster'};

assert(all(cellfun( ...
        @(fragment) contains(dipolesText, fragment), ...
        requiredFragments)), ...
    ['bemobil_dipoles compatibility copy does not contain the audited ' ...
     'shared-ICA / optional-Outlier handling.']);

info = struct();
info.patchFolder = compatibilityFolder;
info.stdPreclustOriginal = stdOriginal;
info.stdPreclustPatch = stdPatch;
info.bemobilDipolesOriginal = dipolesOriginal;
info.bemobilDipolesPatch = dipolesPatch;

end


function tf = same_path_local(firstPath, secondPath)

tf = strcmpi( ...
    normalize_path_local(firstPath), ...
    normalize_path_local(secondPath));

end


function outputPath = normalize_path_local(inputPath)

outputPath = char(string(inputPath));

try
    outputPath = char(java.io.File(outputPath).getCanonicalPath());
catch
    outputPath = strrep(outputPath, '/', filesep);
end

end
