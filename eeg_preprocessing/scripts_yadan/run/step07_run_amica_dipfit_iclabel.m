% GOAL
%   Run AMICA source decomposition followed by DIPFIT source localization
%   and ICLabel classification for EEG datasets that passed Step 06 QC.
%
% INPUT
%   Updated subject_level_EEG_processing_table.csv from Step 06.
%   Verified preprocessed .set/.fdt datasets produced by Step 05.
%
% APPROACH
%   1. Select rows enabled by DoAMICA after preprocessing QC.
%   2. Verify FieldTrip/DIPFIT resources before starting the expensive run.
%   3. Reuse only complete AMICA outputs with matching provenance.
%   4. Otherwise run the established BeMoBIL AMICA/DIPFIT/ICLabel pipeline.
%   5. Verify all expected output datasets and update processing status.
%
% OUTPUT
%   AMICA.set
%   dipfitted.set
%   preprocessed_and_ICA.set
%   cleaned_with_ICA.set
%   Updated subject_level_EEG_processing_table.csv
%
% USED BY
%   Step 08 AMICA / ICA / ICLabel / DIPFIT quality control.

clear; clc; close all;

% Keep figures hidden during AMICA batch processing.
set(0, 'DefaultFigureVisible', 'off');
set(groot, 'DefaultFigureVisible', 'off');

%% ========================================================================
%  LOAD PATHS, CONFIGURATION, AND RUN CONTROL
%  ========================================================================

runFolder = fileparts(mfilename('fullpath'));
scriptsRoot = fileparts(runFolder);

addpath(scriptsRoot, '-begin');
addpath(fullfile(scriptsRoot, 'config'), '-begin');

P = project_paths();

bemobil_config = ...
    config_step05_09_eeg_preprocessing_ica(P);

mappingFile = P.subjectLevelEEGTableFile;
outputFolder = P.outputFolder;
amicaTempFolder = P.amicaTempFolder;
fieldtripFolder = P.fieldtripFolder;

if ~exist(mappingFile, 'file')
    error([ ...
        'Subject-level processing table not found:\n%s\n' ...
        'Run step06_check_preprocessed_eeg.m first.'], ...
        mappingFile);
end

if ~exist(amicaTempFolder, 'dir')
    mkdir(amicaTempFolder);
end

cd(amicaTempFolder);

reset_DoAMICA_from_PreprocessingQC = ...
    bemobil_config.pipeline.reset_DoAMICA_from_PreprocessingQC;

force_recompute_amica = ...
    bemobil_config.pipeline.force_recompute_amica;

skip_existing_complete_outputs = ...
    bemobil_config.pipeline.skip_existing_complete_amica_outputs;

expectedChannelsBeforeAMICA = ...
    bemobil_config.pipeline.expectedChannelsBeforeAMICA;

%% ========================================================================
%  INITIALIZE EEGLAB
%  ========================================================================

if ~exist('ALLCOM', 'var')
    [ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab('nogui');
end

hipexo.hide_all_figures();

%% ========================================================================
%  PREPARE FIELDTRIP AND DIPFIT RESOURCES
%  ========================================================================

% The XDF inspection stage uses the complete FieldTrip installation, while
% EEGLAB can additionally place Fieldtrip-lite on the MATLAB path. Keeping
% both versions active can make DIPFIT resolve functions and template files
% from different installations.
%
% For this AMICA/DIPFIT stage, use the complete FieldTrip installation
% configured in project_paths.m and remove only Fieldtrip-lite path entries from the
% current MATLAB session. This does not modify the saved MATLAB path and does
% not affect the XDF files or any previously generated EEG data.

if ~exist('fieldtripFolder', 'var')

    error([ ...
        'fieldtripFolder was not defined by project_paths.m.\n' ...
        'Define the complete FieldTrip installation in project_paths.m before ' ...
        'running AMICA.']);

end

if strlength(strtrim(string(fieldtripFolder))) == 0 || ...
        ~isfolder(fieldtripFolder)

    error([ ...
        'Configured FieldTrip folder does not exist:\n%s\n' ...
        'Correct fieldtripFolder in project_paths.m before running AMICA.'], ...
        char(string(fieldtripFolder)));

end

currentPathEntries = strsplit(path, pathsep);
removedFieldtripLitePaths = 0;

for pathIndex = numel(currentPathEntries):-1:1

    thisPathEntry = strtrim(currentPathEntries{pathIndex});

    if ~isempty(thisPathEntry) && ...
            contains(lower(thisPathEntry), 'fieldtrip-lite')

        rmpath(thisPathEntry);
        removedFieldtripLitePaths = removedFieldtripLitePaths + 1;

    end

end

% Clear the main FieldTrip entry points so MATLAB resolves them again after
% the path cleanup.
clear ft_defaults ft_version ft_read_headmodel ft_dipolefitting
rehash toolboxcache;

% Explicitly select and initialize the configured complete FieldTrip.
addpath(fieldtripFolder, '-begin');
ft_defaults;

activeFieldTripFile = which('ft_defaults.m');

if isempty(activeFieldTripFile) || ...
        ~startsWith( ...
            lower(string(activeFieldTripFile)), ...
            lower(string(fieldtripFolder)))

    error([ ...
        'Could not activate the configured FieldTrip installation.\n' ...
        'Configured folder:\n%s\n' ...
        'Active ft_defaults.m:\n%s'], ...
        char(string(fieldtripFolder)), ...
        char(string(activeFieldTripFile)));

end

% DIPFIT sometimes stores the standard template resources by filename only
% (for example, "standard_vol.mat"). Therefore, explicitly add all required
% DIPFIT resource folders on every run instead of relying on a previous
% MATLAB session to have configured them.

dipfitDefsFile = which('dipfitdefs.m');

if isempty(dipfitDefsFile)

    error([ ...
        'DIPFIT is not available on the MATLAB path.\n' ...
        'Install or enable the EEGLAB DIPFIT plugin before running AMICA.']);

end

dipfitRoot = fileparts(dipfitDefsFile);

dipfitResourceFolders = { ...
    fullfile(dipfitRoot, 'standard_BEM'), ...
    fullfile(dipfitRoot, 'standard_BEM', 'elec'), ...
    fullfile(dipfitRoot, 'standard_BEM', 'skin'), ...
    fullfile(dipfitRoot, 'standard_BESA') ...
};

for folderIndex = 1:numel(dipfitResourceFolders)

    if ~isfolder(dipfitResourceFolders{folderIndex})

        error([ ...
            'Required DIPFIT resource folder does not exist:\n%s\n' ...
            'Repair the DIPFIT plugin installation before running AMICA.'], ...
            dipfitResourceFolders{folderIndex});

    end

    addpath(dipfitResourceFolders{folderIndex}, '-begin');

end

dipfitHeadModelFile = fullfile( ...
    dipfitRoot, ...
    'standard_BEM', ...
    'standard_vol.mat');

dipfitMRIFile = fullfile( ...
    dipfitRoot, ...
    'standard_BEM', ...
    'standard_mri.mat');

dipfitChannelFile = fullfile( ...
    dipfitRoot, ...
    'standard_BEM', ...
    'elec', ...
    'standard_1005.elc');

requiredDipfitFiles = { ...
    dipfitHeadModelFile, ...
    dipfitMRIFile, ...
    dipfitChannelFile ...
};

for fileIndex = 1:numel(requiredDipfitFiles)

    if ~isfile(requiredDipfitFiles{fileIndex})

        error([ ...
            'Required DIPFIT model file does not exist:\n%s\n' ...
            'Repair the DIPFIT plugin installation before running AMICA.'], ...
            requiredDipfitFiles{fileIndex});

    end

end

resolvedDipfitHeadModel = which('standard_vol.mat');

if isempty(resolvedDipfitHeadModel)

    error([ ...
        'DIPFIT standard_vol.mat exists on disk but cannot be resolved ' ...
        'from the MATLAB path.']);

end

% Read the model before AMICA starts. If DIPFIT cannot use the configured
% model, stop now rather than after a long AMICA computation.
try

    dipfitHeadModelTest = ...
        ft_read_headmodel('standard_vol.mat');

catch ME

    error([ ...
        'DIPFIT head-model preflight failed before AMICA started.\n' ...
        'Resolved model:\n%s\n' ...
        'Original error:\n%s'], ...
        resolvedDipfitHeadModel, ...
        ME.message);

end

if ~isstruct(dipfitHeadModelTest)

    error([ ...
        'DIPFIT head-model preflight returned an unexpected result for:\n%s'], ...
        resolvedDipfitHeadModel);

end

clear dipfitHeadModelTest

fprintf('\nDIPFIT / FieldTrip preflight passed.\n');
fprintf('Removed Fieldtrip-lite path entries: %d\n', ...
    removedFieldtripLitePaths);
fprintf('Active FieldTrip:\n%s\n', activeFieldTripFile);
fprintf('DIPFIT root:\n%s\n', dipfitRoot);
fprintf('Resolved head model:\n%s\n', resolvedDipfitHeadModel);

%% ========================================================================
%  FINALIZE AMICA CONFIGURATION
%  ========================================================================

if isempty(bemobil_config.resample_freq)
    expectedPreprocessedSrate = 500;
else
    expectedPreprocessedSrate = ...
        double(bemobil_config.resample_freq);
end

amicaConfigSignature = ...
    hipexo.amica_scientific_signature(bemobil_config);

fprintf('\nAMICA settings:\n');
fprintf('AMICA_max_iter: %d\n', ...
    bemobil_config.AMICA_max_iter);
fprintf('max_threads: %d\n', ...
    bemobil_config.max_threads);
fprintf('force_recompute_amica: %d\n', ...
    force_recompute_amica);
fprintf('skip_existing_complete_outputs: %d\n', ...
    skip_existing_complete_outputs);
fprintf('reset_DoAMICA_from_PreprocessingQC: %d\n', ...
    reset_DoAMICA_from_PreprocessingQC);

%% ========================================================================
%  READ IMPORT TABLE
%  ========================================================================

optsImport = detectImportOptions(mappingFile, ...
    'FileType', 'text', ...
    'Delimiter', ',', ...
    'VariableNamingRule', 'preserve');

sourceMap = readtable(mappingFile, optsImport);

fprintf('\nLoaded import table:\n%s\n', mappingFile);
fprintf('Rows in import table: %d\n', height(sourceMap));

%% ========================================================================
%  CHECK REQUIRED COLUMNS
%  ========================================================================

requiredColumns = { ...
    'DoImport', ...
    'XdfPath', ...
    'FileName', ...
    'BidsSubject', ...
    'BidsSession', ...
    'PreprocessingStatus', ...
    'PreprocessingQCStatus', ...
    'PreprocessedSetPath' ...
};

for c = 1:length(requiredColumns)
    if ~ismember(requiredColumns{c}, sourceMap.Properties.VariableNames)
        error(['Import table is missing required column: %s\n' ...
               'Please run preprocessing and step06_check_preprocessed_eeg.m first.'], ...
               requiredColumns{c});
    end
end

%% ========================================================================
%  NORMALIZE IMPORTANT COLUMNS
%  ========================================================================

sourceMap = ensure_numeric_column(sourceMap, 'DoImport');
sourceMap = ensure_numeric_column(sourceMap, 'BidsSubject');

sourceMap.XdfPath               = string(sourceMap.XdfPath);
sourceMap.FileName              = string(sourceMap.FileName);
sourceMap.BidsSession           = string(sourceMap.BidsSession);
sourceMap.PreprocessingStatus   = string(sourceMap.PreprocessingStatus);
sourceMap.PreprocessingQCStatus = string(sourceMap.PreprocessingQCStatus);
sourceMap.PreprocessedSetPath   = string(sourceMap.PreprocessedSetPath);

sourceMap.XdfPath(ismissing(sourceMap.XdfPath)) = "";
sourceMap.FileName(ismissing(sourceMap.FileName)) = "";
sourceMap.BidsSession(ismissing(sourceMap.BidsSession)) = "";
sourceMap.PreprocessingStatus(ismissing(sourceMap.PreprocessingStatus)) = "";
sourceMap.PreprocessingQCStatus(ismissing(sourceMap.PreprocessingQCStatus)) = "";
sourceMap.PreprocessedSetPath(ismissing(sourceMap.PreprocessedSetPath)) = "";

if ismember('DoPreprocess', sourceMap.Properties.VariableNames)
    sourceMap = ensure_numeric_column(sourceMap, 'DoPreprocess');
end

if ismember('DoQC', sourceMap.Properties.VariableNames)
    sourceMap = ensure_numeric_column(sourceMap, 'DoQC');
end

if ismember('ProcessingSubjectLabel', sourceMap.Properties.VariableNames)
    sourceMap.ProcessingSubjectLabel = string(sourceMap.ProcessingSubjectLabel);
    sourceMap.ProcessingSubjectLabel(ismissing(sourceMap.ProcessingSubjectLabel)) = "";
end

if ismember('ProcessingSubjectFolder', sourceMap.Properties.VariableNames)
    sourceMap.ProcessingSubjectFolder = string(sourceMap.ProcessingSubjectFolder);
    sourceMap.ProcessingSubjectFolder(ismissing(sourceMap.ProcessingSubjectFolder)) = "";
end

if ismember('EEGStreamName', sourceMap.Properties.VariableNames)
    sourceMap.EEGStreamName = string(sourceMap.EEGStreamName);
    sourceMap.EEGStreamName(ismissing(sourceMap.EEGStreamName)) = "";
end

if ismember('RawSetPath', sourceMap.Properties.VariableNames)
    sourceMap.RawSetPath = string(sourceMap.RawSetPath);
    sourceMap.RawSetPath(ismissing(sourceMap.RawSetPath)) = "";
end

if ismember('RawSetStatus', sourceMap.Properties.VariableNames)
    sourceMap.RawSetStatus = string(sourceMap.RawSetStatus);
    sourceMap.RawSetStatus(ismissing(sourceMap.RawSetStatus)) = "";
end

%% ========================================================================
%  CREATE OR READ DOAMICA
%  ========================================================================

readyForAMICA = ...
    sourceMap.PreprocessingStatus == "completed" & ...
    sourceMap.PreprocessingQCStatus == "passed_basic_checks" & ...
    strlength(strtrim(sourceMap.PreprocessedSetPath)) > 0;

if ~ismember('DoAMICA', sourceMap.Properties.VariableNames)

    sourceMap.DoAMICA = zeros(height(sourceMap), 1);
    sourceMap.DoAMICA(readyForAMICA) = 1;

    writetable(sourceMap, mappingFile);

    fprintf('\nDoAMICA column was not found.\n');
    fprintf('Created DoAMICA from completed preprocessing + passed preprocessing QC and saved it to:\n%s\n', mappingFile);
    fprintf('You can manually edit DoAMICA now:\n');
    fprintf('  DoAMICA = 1 -> run AMICA for this row\n');
    fprintf('  DoAMICA = 0 -> skip this row\n');

else

    sourceMap = ensure_numeric_column(sourceMap, 'DoAMICA');

    if reset_DoAMICA_from_PreprocessingQC

        sourceMap.DoAMICA = zeros(height(sourceMap), 1);
        sourceMap.DoAMICA(readyForAMICA) = 1;

        writetable(sourceMap, mappingFile);

        fprintf('\nDoAMICA column already existed.\n');
        fprintf('Reset DoAMICA from completed preprocessing + passed preprocessing QC because reset_DoAMICA_from_PreprocessingQC = true.\n');
        fprintf('Updated import table saved to:\n%s\n', mappingFile);

    else

        missingDoAMICA = isnan(sourceMap.DoAMICA);
        sourceMap.DoAMICA(missingDoAMICA) = 0;
        sourceMap.DoAMICA(missingDoAMICA & readyForAMICA) = 1;
        writetable(sourceMap, mappingFile);

        fprintf('\nDoAMICA column already existed.\n');
        fprintf('Preserved explicit DoAMICA values and filled only missing values from preprocessing QC.\n');

    end

end

%% ========================================================================
%  CHECK FOR STALE AMICA RESULTS
%  ========================================================================

% If preprocessing was updated after AMICA, the old AMICA output no longer
% belongs to the current preprocessed .set file. Such rows must be rerun.

sourceMap = ensure_string_column(sourceMap, 'PreprocessingDate');
sourceMap = ensure_string_column(sourceMap, 'AMICAStatus');
sourceMap = ensure_string_column(sourceMap, 'AMICADate');
sourceMap = ensure_string_column(sourceMap, 'AMICANotes');
sourceMap = ensure_string_column(sourceMap, 'AMICASetPath');
sourceMap = ensure_string_column(sourceMap, 'DipfittedSetPath');
sourceMap = ensure_string_column(sourceMap, 'PreprocessedICASetPath');
sourceMap = ensure_string_column(sourceMap, 'CleanedICASetPath');
sourceMap = ensure_string_column(sourceMap, 'AMICAOutputStatus');
sourceMap = ensure_string_column(sourceMap, 'AMICAInputSignature');

preDate = parse_datetime_column(sourceMap.PreprocessingDate);
amicaDate = parse_datetime_column(sourceMap.AMICADate);

staleAMICA = ...
    sourceMap.AMICAStatus == "completed" & ...
    ~isnat(preDate) & ...
    ~isnat(amicaDate) & ...
    preDate > amicaDate;

if any(staleAMICA)

    fprintf('\nWARNING: Found %d stale AMICA row(s).\n', sum(staleAMICA));
    fprintf('These rows have PreprocessingDate later than AMICADate.\n');
    fprintf('They will be marked as stale_needs_rerun and DoAMICA will be set to 1.\n');

    sourceMap.AMICAStatus(staleAMICA) = "stale_needs_rerun";
    sourceMap.AMICANotes(staleAMICA) = ...
        "PreprocessingDate is newer than AMICADate. AMICA output is stale and must be rerun.";
    sourceMap.DoAMICA(staleAMICA) = 1;

    writetable(sourceMap, mappingFile);

    disp(sourceMap(staleAMICA, intersect({'FileName', 'BidsSubject', 'BidsSession', ...
                                           'PreprocessingDate', 'AMICADate', ...
                                           'PreprocessingStatus', 'PreprocessingQCStatus', ...
                                           'AMICAStatus', 'DoAMICA'}, ...
                                           sourceMap.Properties.VariableNames, 'stable')));

else

    fprintf('\nNo stale AMICA rows found based on PreprocessingDate and AMICADate.\n');

end

%% ========================================================================
%  SELECT ROWS TO PROCESS
%  ========================================================================

sourceMap = ensure_numeric_column(sourceMap, 'DoAMICA');

candidateRows = find(sourceMap.DoAMICA == 1);

if isempty(candidateRows)
    error('No rows with DoAMICA = 1 found in the subject-level processing table.');
end

hasPreprocessedPath = strlength(strtrim(sourceMap.PreprocessedSetPath)) > 0;

passedPreprocessing = sourceMap.PreprocessingStatus == "completed";
passedQC = sourceMap.PreprocessingQCStatus == "passed_basic_checks";

validRows = candidateRows( ...
    hasPreprocessedPath(candidateRows) & ...
    passedPreprocessing(candidateRows) & ...
    passedQC(candidateRows) ...
);

if isempty(validRows)

    fprintf('\nRows with DoAMICA = 1 exist, but none passed the AMICA selection gate.\n');
    fprintf('Problem rows:\n');

    disp(sourceMap(candidateRows, {'FileName', 'BidsSubject', 'BidsSession', ...
                                   'DoAMICA', ...
                                   'PreprocessingStatus', ...
                                   'PreprocessingQCStatus', ...
                                   'PreprocessedSetPath'}));

    error('No valid rows for AMICA.');

end

% Safety: avoid running AMICA multiple times for the same preprocessed .set file.
preprocessedPathsForValidRows = sourceMap.PreprocessedSetPath(validRows);
[~, uniqueIdx] = unique(preprocessedPathsForValidRows, 'stable');
rowsToProcess = validRows(uniqueIdx);

fprintf('\n============================================================\n');
fprintf('AMICA-ONLY PROCESSING STARTED\n');
fprintf('============================================================\n');
fprintf('Selection mode: table-driven AMICA after preprocessing QC\n');
fprintf('Rows with DoAMICA = 1: %d\n', length(candidateRows));
fprintf('Rows passing AMICA gate: %d\n', length(validRows));
fprintf('Unique preprocessed .set files selected for AMICA: %d\n', length(rowsToProcess));
fprintf('Files selected by DoAMICA table column will be processed.\n');
fprintf('Import table:\n%s\n', mappingFile);
fprintf('============================================================\n\n');

fprintf('Rows selected for AMICA:\n');
disp(sourceMap(rowsToProcess, {'FileName', 'BidsSubject', 'BidsSession', ...
                               'DoAMICA', ...
                               'PreprocessingStatus', ...
                               'PreprocessingQCStatus', ...
                               'PreprocessedSetPath'}));

hipexo.hide_all_figures();

%% ========================================================================
%  AMICA LOOP
%  ========================================================================

for r = 1:length(rowsToProcess)

    hipexo.hide_all_figures();

    rowIdx = rowsToProcess(r);
    sessionRows = hipexo.session_peer_rows(sourceMap, rowIdx);

    bidsSubject = sourceMap.BidsSubject(rowIdx);
    bidsSession = char(sourceMap.BidsSession(rowIdx));

    originalXDFName = char(sourceMap.FileName(rowIdx));
    originalXDFPath = char(sourceMap.XdfPath(rowIdx));

    if isnan(bidsSubject)

        warning('Invalid BidsSubject in row %d. Skipping this row.', rowIdx);

        sourceMap = update_amica_status( ...
            sourceMap, rowIdx, ...
            "failed_invalid_bids_subject", ...
            "BidsSubject is NaN or invalid.", ...
            "" ...
        );

        writetable(sourceMap, mappingFile);
        continue;

    end

    %% --------------------------------------------------------------------
    %  RESOLVE PROCESSING LABEL
    %  --------------------------------------------------------------------

    if ismember('ProcessingSubjectLabel', sourceMap.Properties.VariableNames) && ...
            strlength(strtrim(string(sourceMap.ProcessingSubjectLabel(rowIdx)))) > 0

        processingSubjectLabel = char(sourceMap.ProcessingSubjectLabel(rowIdx));

    else

        processingSubjectLabel = char(make_bids_label(string(bidsSession)));

    end

    if ismember('ProcessingSubjectFolder', sourceMap.Properties.VariableNames) && ...
            strlength(strtrim(string(sourceMap.ProcessingSubjectFolder(rowIdx)))) > 0

        processingSubjectFolder = char(sourceMap.ProcessingSubjectFolder(rowIdx));

    else

        processingSubjectFolder = ['sub-' processingSubjectLabel];

    end

    %% --------------------------------------------------------------------
    %  RESOLVE PREPROCESSED .SET FILE PATH
    %  --------------------------------------------------------------------

    preprocessedSetPath = string(sourceMap.PreprocessedSetPath(rowIdx));

    if strlength(strtrim(preprocessedSetPath)) == 0

        preprocessedSetPath = string(fullfile( ...
            bemobil_config.study_folder, ...
            bemobil_config.EEG_preprocessing_data_folder, ...
            processingSubjectFolder, ...
            [processingSubjectFolder '_' bemobil_config.preprocessed_filename] ...
        ));

    end

    preprocessedSetPath = char(preprocessedSetPath);

    fprintf('\n\n============================================================\n');
    fprintf('RUNNING AMICA FOR FILE %d / %d\n', r, length(rowsToProcess));
    fprintf('============================================================\n');
    fprintf('Table row: %d\n', rowIdx);
    fprintf('Original XDF name:\n%s\n\n', originalXDFName);
    fprintf('Original XDF path:\n%s\n\n', originalXDFPath);
    fprintf('Imported BIDS subject:\nsub-%d\n', bidsSubject);
    fprintf('Imported BIDS session:\n%s\n', bidsSession);
    fprintf('Processing label:\n%s\n', processingSubjectLabel);
    fprintf('Processing folder:\n%s\n', processingSubjectFolder);
    fprintf('DoAMICA:\n%d\n', sourceMap.DoAMICA(rowIdx));
    fprintf('PreprocessingStatus:\n%s\n', char(sourceMap.PreprocessingStatus(rowIdx)));
    fprintf('PreprocessingQCStatus:\n%s\n', char(sourceMap.PreprocessingQCStatus(rowIdx)));
    fprintf('Preprocessed file:\n%s\n', preprocessedSetPath);

    if ismember('RawSetPath', sourceMap.Properties.VariableNames)
        fprintf('RawSetPath:\n%s\n', char(sourceMap.RawSetPath(rowIdx)));
    end

    if ismember('RawSetStatus', sourceMap.Properties.VariableNames)
        fprintf('RawSetStatus:\n%s\n', char(sourceMap.RawSetStatus(rowIdx)));
    end

    fprintf('============================================================\n\n');

    if ~exist(preprocessedSetPath, 'file')

        warning('Preprocessed .set file not found. Skipping this row:\n%s', preprocessedSetPath);

        sourceMap = update_amica_status( ...
            sourceMap, rowIdx, ...
            "failed_preprocessed_file_not_found", ...
            "Preprocessed .set file was not found. Run preprocessing first.", ...
            "" ...
        );

        sourceMap = ensure_string_column(sourceMap, 'PreprocessedSetPath');
        sourceMap.PreprocessedSetPath(sessionRows) = string(preprocessedSetPath);

        writetable(sourceMap, mappingFile);
        continue;

    end

    [preprocFolder, preprocFileNoExt, preprocExt] = fileparts(preprocessedSetPath);
    preprocFile = [preprocFileNoExt preprocExt];

    %% --------------------------------------------------------------------
    %  PREPARE AMICA STATUS COLUMNS BEFORE POSSIBLE SKIP
    %  --------------------------------------------------------------------

    sourceMap = ensure_string_column(sourceMap, 'AMICAStatus');
    sourceMap = ensure_string_column(sourceMap, 'AMICADate');
    sourceMap = ensure_string_column(sourceMap, 'AMICANotes');
    sourceMap = ensure_string_column(sourceMap, 'AMICASetPath');
    sourceMap = ensure_string_column(sourceMap, 'DipfittedSetPath');
    sourceMap = ensure_string_column(sourceMap, 'PreprocessedICASetPath');
    sourceMap = ensure_string_column(sourceMap, 'CleanedICASetPath');
    sourceMap = ensure_string_column(sourceMap, 'AMICAOutputStatus');
    sourceMap = ensure_string_column(sourceMap, 'PreprocessedSetPath');
    sourceMap = ensure_string_column(sourceMap, 'AMICAInputSignature');

    sourceMap.PreprocessedSetPath(sessionRows) = string(preprocessedSetPath);

    expectedAMICAInputSignature = hipexo.eeglab_dataset_signature(preprocessedSetPath) + ...
        "|cfg=" + amicaConfigSignature;
    sessionMarkedStale = any(sourceMap.AMICAStatus(sessionRows) == "stale_needs_rerun");

    [existingAMICASetPath, existingDipfittedSetPath, existingPreprocessedICASetPath, ...
        existingCleanedICASetPath, existingOutputStatus, amicaCandidates] = find_all_amica_outputs( ...
        outputFolder, ...
        bemobil_config, ...
        processingSubjectFolder);

    existingProvenanceOK = false;
    if existingOutputStatus == "complete_outputs_verified"
        existingProvenanceOK = verify_amica_output_provenance( ...
            existingPreprocessedICASetPath, expectedAMICAInputSignature);
    end

    %% --------------------------------------------------------------------
    %  SKIP EXISTING COMPLETE AMICA OUTPUTS IF NOT RECOMPUTING
    %  --------------------------------------------------------------------

    if skip_existing_complete_outputs && ...
            force_recompute_amica == 0 && ...
            ~sessionMarkedStale && ...
            existingOutputStatus == "complete_outputs_verified" && ...
            existingProvenanceOK

        fprintf('\nAll expected AMICA/DIPFIT/output5 files already exist. Updating CSV and skipping AMICA rerun.\n');
        fprintf('AMICA set:\n%s\n', existingAMICASetPath);
        fprintf('DIPFIT set:\n%s\n', existingDipfittedSetPath);
        fprintf('Preprocessed+ICA set:\n%s\n', existingPreprocessedICASetPath);
        fprintf('Cleaned ICA set:\n%s\n', existingCleanedICASetPath);

        sourceMap.AMICAStatus(sessionRows) = "completed";
        sourceMap.AMICASetPath(sessionRows) = existingAMICASetPath;
        sourceMap.DipfittedSetPath(sessionRows) = existingDipfittedSetPath;
        sourceMap.PreprocessedICASetPath(sessionRows) = existingPreprocessedICASetPath;
        sourceMap.CleanedICASetPath(sessionRows) = existingCleanedICASetPath;
        sourceMap.AMICAOutputStatus(sessionRows) = existingOutputStatus;
        sourceMap.AMICAInputSignature(sessionRows) = expectedAMICAInputSignature;
        sourceMap.AMICANotes(sessionRows) = ...
            "Skipped because all expected AMICA/DIPFIT/output5 files already exist, CSV paths were updated, and force_recompute_amica = 0.";

        writetable(sourceMap, mappingFile);

        continue;

    end

    rowForceRecomputeAMICA = force_recompute_amica ~= 0 || ...
        sessionMarkedStale || ...
        existingOutputStatus ~= "complete_outputs_verified" || ...
        ~existingProvenanceOK;

    if rowForceRecomputeAMICA
        fprintf('\nAMICA/DIPFIT outputs are stale, incomplete, or unverified. Forcing full BeMoBIL AMICA recomputation.\n');
    end

    if force_recompute_amica == 0 && ...
            any(sourceMap.AMICAStatus(sessionRows) == "completed") && ...
            existingOutputStatus ~= "complete_outputs_verified"

        fprintf('\nWARNING: AMICAStatus is completed, but expected output files are incomplete.\n');
        fprintf('Existing output status: %s\n', existingOutputStatus);
        fprintf('This row will be rerun because completed AMICA cannot be verified.\n');
        fprintf('Candidate paths checked:\n');

        for k = 1:length(amicaCandidates)
            fprintf('%s\n', amicaCandidates{k});
        end

    end

    %% --------------------------------------------------------------------
    %  UPDATE TABLE BEFORE AMICA
    %  --------------------------------------------------------------------

    sourceMap.AMICAStatus(sessionRows) = "running";
    sourceMap.AMICADate(sessionRows) = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    sourceMap.AMICANotes(sessionRows) = "";

    % Clear stale output paths before this AMICA run.
    % New paths are written only after the current run outputs are verified.
    sourceMap.AMICASetPath(sessionRows) = "";
    sourceMap.DipfittedSetPath(sessionRows) = "";
    sourceMap.PreprocessedICASetPath(sessionRows) = "";
    sourceMap.CleanedICASetPath(sessionRows) = "";
    sourceMap.AMICAOutputStatus(sessionRows) = "running_outputs_not_verified";
    sourceMap.AMICAInputSignature(sessionRows) = expectedAMICAInputSignature;

    writetable(sourceMap, mappingFile);

    %% --------------------------------------------------------------------
    %  RESET EEGLAB VARIABLES FOR THIS AMICA RUN
    %  --------------------------------------------------------------------

    STUDY = [];
    CURRENTSTUDY = 0;
    ALLEEG = [];
    CURRENTSET = [];
    EEG = [];
    EEG_preprocessed = [];

    hipexo.hide_all_figures();

    %% --------------------------------------------------------------------
    %  LOAD EXISTING PREPROCESSED EEG
    %  --------------------------------------------------------------------

    fprintf('\nLoading existing preprocessed EEG:\n%s\n', preprocessedSetPath);

    try

        EEG_preprocessed = pop_loadset( ...
            'filename', preprocFile, ...
            'filepath', preprocFolder ...
        );

        EEG_preprocessed = eeg_checkset(EEG_preprocessed);

        hipexo.hide_all_figures();

    catch ME

        sourceMap = update_amica_status( ...
            sourceMap, rowIdx, ...
            "failed_load_preprocessed_set", ...
            string(ME.message), ...
            "" ...
        );

        writetable(sourceMap, mappingFile);
        continue;

    end

    %% --------------------------------------------------------------------
    %  STORE SOURCE INFORMATION INSIDE EEG.ETC AGAIN
    %  --------------------------------------------------------------------

    EEG_preprocessed.etc.source_original_xdf_name = originalXDFName;
    EEG_preprocessed.etc.source_original_xdf_path = originalXDFPath;
    EEG_preprocessed.etc.real_bids_subject = bidsSubject;
    EEG_preprocessed.etc.session_label = bidsSession;
    EEG_preprocessed.etc.processing_subject_label = processingSubjectLabel;
    EEG_preprocessed.etc.preprocessing_status_for_amica = char(sourceMap.PreprocessingStatus(rowIdx));
    EEG_preprocessed.etc.preprocessing_qc_status_for_amica = char(sourceMap.PreprocessingQCStatus(rowIdx));
    EEG_preprocessed.etc.amica_input_signature = char(expectedAMICAInputSignature);
    EEG_preprocessed.etc.amica_config_signature = char(amicaConfigSignature);
    EEG_preprocessed.etc.amica_config_signature_version = ...
        'HipExo_amica_scientific_config_v1';

    if ismember('EEGStreamName', sourceMap.Properties.VariableNames)
        EEG_preprocessed.etc.source_eeg_stream_name = char(sourceMap.EEGStreamName(rowIdx));
    end

    [ALLEEG, EEG_preprocessed, CURRENTSET] = eeg_store(ALLEEG, EEG_preprocessed, 1);

    fprintf('\nLoaded preprocessed EEG:\n');
    fprintf('Channels: %d\n', EEG_preprocessed.nbchan);
    fprintf('Sampling rate: %.2f Hz\n', EEG_preprocessed.srate);
    fprintf('Samples: %d\n', EEG_preprocessed.pnts);
    fprintf('Duration: %.2f seconds\n', EEG_preprocessed.xmax - EEG_preprocessed.xmin);
    fprintf('Events: %d\n', length(EEG_preprocessed.event));

    %% --------------------------------------------------------------------
    %  BASIC SAFETY CHECK BEFORE AMICA
    %  --------------------------------------------------------------------

    if EEG_preprocessed.nbchan ~= expectedChannelsBeforeAMICA

        warning('Unexpected channel count before AMICA. Expected %d, got %d. Skipping.', ...
            expectedChannelsBeforeAMICA, EEG_preprocessed.nbchan);

        sourceMap = update_amica_status( ...
            sourceMap, rowIdx, ...
            "failed_unexpected_channel_count", ...
            "Expected " + string(expectedChannelsBeforeAMICA) + " channels before AMICA.", ...
            "" ...
        );

        writetable(sourceMap, mappingFile);
        continue;

    end

    if abs( ...
            EEG_preprocessed.srate - ...
            expectedPreprocessedSrate) > 0.001

        warning([ ...
            'Unexpected sampling rate before AMICA. Expected %.2f Hz, ' ...
            'got %.2f Hz. Skipping.'], ...
            expectedPreprocessedSrate, ...
            EEG_preprocessed.srate);

        sourceMap = update_amica_status( ...
            sourceMap, rowIdx, ...
            "failed_unexpected_sampling_rate", ...
            "Expected " + string(expectedPreprocessedSrate) + ...
                " Hz sampling rate before AMICA.", ...
            "" ...
        );

        writetable(sourceMap, mappingFile);
        continue;

    end

    [amicaDataRank, amicaDataRankValid] = get_rank_metadata(EEG_preprocessed);
    if ~amicaDataRankValid

        warning('Invalid or missing EEG.etc.rank before AMICA. Skipping.');

        sourceMap = update_amica_status( ...
            sourceMap, rowIdx, ...
            "failed_invalid_rank_metadata", ...
            "EEG.etc.rank must be a finite integer between 1 and EEG.nbchan.", ...
            "" ...
        );

        writetable(sourceMap, mappingFile);
        continue;

    end

    fprintf('AMICA PCA rank from EEG.etc.rank: %d\n', amicaDataRank);

    %% --------------------------------------------------------------------
    %  RUN AMICA ONLY
    %  --------------------------------------------------------------------

    try

        hipexo.hide_all_figures();

        bemobil_process_all_AMICA( ...
            ALLEEG, ...
            EEG_preprocessed, ...
            CURRENTSET, ...
            processingSubjectLabel, ...
            bemobil_config, ...
            rowForceRecomputeAMICA);

        hipexo.hide_all_figures();

    catch ME

        hipexo.hide_all_figures();

        fprintf(2, ...
            '\nAMICA / DIPFIT / ICLabel processing failed for %s.\n%s\n', ...
            processingSubjectLabel, ...
            getReport(ME, 'extended', 'hyperlinks', 'off'));

        sourceMap = update_amica_status( ...
            sourceMap, rowIdx, ...
            "failed", ...
            string(ME.message), ...
            "" ...
        );

        writetable(sourceMap, mappingFile);
        continue;

    end

    %% --------------------------------------------------------------------
    %  VERIFY ALL EXPECTED AMICA / DIPFIT / ICA OUTPUT FILES
    %  --------------------------------------------------------------------

    [foundAMICASetPath, foundDipfittedSetPath, foundPreprocessedICASetPath, ...
        foundCleanedICASetPath, amicaOutputStatus, amicaCandidates] = find_all_amica_outputs( ...
        outputFolder, ...
        bemobil_config, ...
        processingSubjectFolder);

    if amicaOutputStatus == "complete_outputs_verified" && ...
            ~verify_amica_output_provenance(foundPreprocessedICASetPath, expectedAMICAInputSignature)
        amicaOutputStatus = "output_provenance_mismatch";
    end

    sourceMap.AMICADate(sessionRows) = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    sourceMap.AMICASetPath(sessionRows) = foundAMICASetPath;
    sourceMap.DipfittedSetPath(sessionRows) = foundDipfittedSetPath;
    sourceMap.PreprocessedICASetPath(sessionRows) = foundPreprocessedICASetPath;
    sourceMap.CleanedICASetPath(sessionRows) = foundCleanedICASetPath;
    sourceMap.AMICAOutputStatus(sessionRows) = amicaOutputStatus;

    if amicaOutputStatus == "complete_outputs_verified"

        sourceMap.AMICAStatus(sessionRows) = "completed";
        sourceMap.AMICANotes(sessionRows) = "";

        fprintf('\nAMICA, DIPFIT, preprocessed+ICA, and cleaned ICA outputs found.\n');
        fprintf('AMICA set:\n%s\n', foundAMICASetPath);
        fprintf('DIPFIT set:\n%s\n', foundDipfittedSetPath);
        fprintf('Preprocessed+ICA set:\n%s\n', foundPreprocessedICASetPath);
        fprintf('Cleaned ICA set:\n%s\n', foundCleanedICASetPath);

    elseif amicaOutputStatus == "output_provenance_mismatch"

        sourceMap.AMICAStatus(sessionRows) = "failed_output_provenance_mismatch";
        sourceMap.AMICANotes(sessionRows) = ...
            "AMICA outputs exist, but preprocessed_and_ICA does not contain the current AMICA input signature.";

        fprintf('\nWARNING: AMICA outputs failed provenance verification.\n');

    elseif strlength(foundAMICASetPath) > 0 || ...
            strlength(foundDipfittedSetPath) > 0 || ...
            strlength(foundPreprocessedICASetPath) > 0 || ...
            strlength(foundCleanedICASetPath) > 0

        sourceMap.AMICAStatus(sessionRows) = "partial_outputs_missing";
        sourceMap.AMICANotes(sessionRows) = ...
            "AMICA function finished, but one or more expected AMICA/DIPFIT/ICA output files were missing.";

        fprintf('\nWARNING: AMICA finished, but expected outputs are incomplete.\n');
        fprintf('Output status: %s\n', amicaOutputStatus);
        fprintf('Candidate paths checked:\n');

        for k = 1:length(amicaCandidates)
            fprintf('%s\n', amicaCandidates{k});
        end

    else

        sourceMap.AMICAStatus(sessionRows) = "finished_but_output_file_not_found";
        sourceMap.AMICANotes(sessionRows) = ...
            "AMICA function finished, but no expected AMICA/DIPFIT/ICA .set files were found.";

        fprintf('\nWARNING: AMICA finished, but no expected output .set files were found.\n');
        fprintf('Candidate paths checked:\n');

        for k = 1:length(amicaCandidates)
            fprintf('%s\n', amicaCandidates{k});
        end

    end

    writetable(sourceMap, mappingFile);

    hipexo.hide_all_figures();


end

hipexo.hide_all_figures();

%% ========================================================================
%  FINAL REPORT
%  ========================================================================

fprintf('\nAMICA/DIPFIT/ICLabel processing finished.\n');

sourceMapFinal = sourceMap;

if ismember('AMICAStatus', sourceMapFinal.Properties.VariableNames)

    sourceMapFinal.AMICAStatus = string(sourceMapFinal.AMICAStatus);
    sourceMapFinal.AMICAStatus(ismissing(sourceMapFinal.AMICAStatus)) = "";

    fprintf('\nAMICA status summary:\n');

    statusNonEmpty = sourceMapFinal.AMICAStatus(strlength(sourceMapFinal.AMICAStatus) > 0);
    uniqueStatus = unique(statusNonEmpty, 'stable');

    if isempty(uniqueStatus)
        fprintf('  No AMICA status entries found.\n');
    else

        for k = 1:numel(uniqueStatus)
            thisStatus = uniqueStatus(k);
            n = sum(statusNonEmpty == thisStatus);
            fprintf('  %-45s %d\n', thisStatus, n);
        end

    end

end

hipexo.hide_all_figures();

%% ========================================================================
%  HELPER FUNCTIONS
%  ========================================================================


function label = make_bids_label(x)

    label = char(x);

    % Remove underscores and other non-alphanumeric characters.
    label = regexprep(label, '[^A-Za-z0-9]', '');

    label = string(label);

end

function T = ensure_string_column(T, columnName)

    if ~ismember(columnName, T.Properties.VariableNames)

        T.(columnName) = strings(height(T), 1);

    else

        if ~isstring(T.(columnName))
            T.(columnName) = string(T.(columnName));
        end

        T.(columnName)(ismissing(T.(columnName))) = "";

    end

end

function T = ensure_numeric_column(T, columnName)

    if ~ismember(columnName, T.Properties.VariableNames)
        error('Table is missing required column: %s', columnName);
    end

    if isnumeric(T.(columnName))
        return;
    elseif islogical(T.(columnName))
        T.(columnName) = double(T.(columnName));
    else
        T.(columnName) = str2double(string(T.(columnName)));
    end

end

function dt = parse_datetime_column(x)

    x = string(x);
    x(ismissing(x)) = "";

    dt = NaT(size(x));

    formats = { ...
        'yyyy-MM-dd HH:mm:ss', ...
        'yyyy/M/d HH:mm:ss', ...
        'yyyy/MM/dd HH:mm:ss', ...
        'dd-MMM-yyyy HH:mm:ss' ...
    };

    for f = 1:numel(formats)

        mask = strlength(strtrim(x)) > 0 & isnat(dt);

        if ~any(mask)
            break;
        end

        try
            dt(mask) = datetime(x(mask), 'InputFormat', formats{f});
        catch
        end

    end

    % Last fallback: let MATLAB try automatic parsing.
    mask = strlength(strtrim(x)) > 0 & isnat(dt);

    if any(mask)
        try
            dt(mask) = datetime(x(mask));
        catch
        end
    end

end


function [foundAMICASetPath, foundDipfittedSetPath, foundPreprocessedICASetPath, ...
    foundCleanedICASetPath, outputStatus, allCandidates] = find_all_amica_outputs( ...
    outputFolder, bemobil_config, processingSubjectFolder)

    [foundAMICASetPath, c1] = find_expected_output_file( ...
        outputFolder, ...
        bemobil_config.spatial_filters_folder, ...
        bemobil_config.spatial_filters_folder_AMICA, ...
        processingSubjectFolder, ...
        bemobil_config.amica_filename_output);

    [foundDipfittedSetPath, c2] = find_expected_output_file( ...
        outputFolder, ...
        bemobil_config.spatial_filters_folder, ...
        bemobil_config.spatial_filters_folder_AMICA, ...
        processingSubjectFolder, ...
        bemobil_config.dipfitted_filename);

    [foundPreprocessedICASetPath, c3] = find_expected_output_file( ...
        outputFolder, ...
        bemobil_config.single_subject_analysis_folder, ...
        '', ...
        processingSubjectFolder, ...
        bemobil_config.preprocessed_and_ICA_filename);

    [foundCleanedICASetPath, c4] = find_expected_output_file( ...
        outputFolder, ...
        bemobil_config.single_subject_analysis_folder, ...
        '', ...
        processingSubjectFolder, ...
        bemobil_config.single_subject_cleaned_ICA_filename);

    allCandidates = [c1(:); c2(:); c3(:); c4(:)];

    missing = strings(0, 1);

    if strlength(foundAMICASetPath) == 0
        missing(end+1, 1) = "AMICA";
    end

    if strlength(foundDipfittedSetPath) == 0
        missing(end+1, 1) = "dipfitted";
    end

    if strlength(foundPreprocessedICASetPath) == 0
        missing(end+1, 1) = "preprocessed_and_ICA";
    end

    if strlength(foundCleanedICASetPath) == 0
        missing(end+1, 1) = "cleaned_with_ICA";
    end

    if isempty(missing)
        outputStatus = "complete_outputs_verified";
    else
        outputStatus = "missing_" + join(missing, "_");
    end

end

function [foundPath, candidates] = find_expected_output_file( ...
    outputFolder, parentFolder, subFolder, processingSubjectFolder, filenameSuffix)

    outputFilename = [processingSubjectFolder '_' filenameSuffix];

    candidates = {};

    if strlength(string(subFolder)) > 0

        candidates = { ...
            fullfile(outputFolder, parentFolder, subFolder, processingSubjectFolder, outputFilename), ...
            fullfile(outputFolder, parentFolder, processingSubjectFolder, subFolder, outputFilename), ...
            fullfile(outputFolder, parentFolder, processingSubjectFolder, outputFilename) ...
        };

    else

        candidates = { ...
            fullfile(outputFolder, parentFolder, processingSubjectFolder, outputFilename), ...
            fullfile(outputFolder, parentFolder, outputFilename) ...
        };

    end

    foundPath = "";

    for k = 1:length(candidates)

        if exist(candidates{k}, 'file') == 2
            foundPath = string(candidates{k});
            return;
        end

    end

end


function T = update_amica_status(T, rowIdx, statusValue, notesValue, setPathValue)

    T = ensure_string_column(T, 'AMICAStatus');
    T = ensure_string_column(T, 'AMICADate');
    T = ensure_string_column(T, 'AMICANotes');
    T = ensure_string_column(T, 'AMICASetPath');
    T = ensure_string_column(T, 'DipfittedSetPath');
    T = ensure_string_column(T, 'PreprocessedICASetPath');
    T = ensure_string_column(T, 'CleanedICASetPath');
    T = ensure_string_column(T, 'AMICAOutputStatus');

    rows = hipexo.session_peer_rows(T, rowIdx);
    T.AMICAStatus(rows) = string(statusValue);
    T.AMICANotes(rows) = string(notesValue);
    T.AMICADate(rows) = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

    if strlength(string(setPathValue)) > 0
        T.AMICASetPath(rows) = string(setPathValue);
    end

end

function [rankValue, valid] = get_rank_metadata(EEG)

    rankValue = NaN;
    valid = false;

    if ~isfield(EEG, 'etc') || ~isfield(EEG.etc, 'rank')
        return;
    end

    try
        if isnumeric(EEG.etc.rank) || islogical(EEG.etc.rank)
            if isscalar(EEG.etc.rank)
                rankValue = double(EEG.etc.rank);
            end
        else
            parsed = str2double(string(EEG.etc.rank));
            if isscalar(parsed)
                rankValue = parsed;
            end
        end
    catch
        rankValue = NaN;
    end

    valid = isfinite(rankValue) && rankValue >= 1 && ...
        rankValue <= EEG.nbchan && abs(rankValue - round(rankValue)) < 1e-6;

end




function ok = verify_amica_output_provenance(setPath, expectedSignature)

    ok = false;
    try
        [folder, base, ext] = fileparts(char(setPath));
        EEG = pop_loadset('filename', [base ext], 'filepath', folder);
        EEG = eeg_checkset(EEG);
        ok = isfield(EEG, 'etc') && isfield(EEG.etc, 'amica_input_signature') && ...
            string(EEG.etc.amica_input_signature) == string(expectedSignature);
    catch ME
        warning('Could not verify AMICA output provenance: %s', ME.message);
        ok = false;
    end

end
