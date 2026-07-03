% Current workflow:
%   1) check_eeg_streams.m
%   2) import_table.m
%   3) bemobil_import.m
%   4) bemobil_process_all_EEG_data.m
%   5) check_preprocessed_EEG.m
%   6) this AMICA-only script
%
% This script:
% 1. Reads bemobil_import_table.csv.
% 2. Selects rows using DoAMICA.
% 3. Loads the existing preprocessed .set file from PreprocessedSetPath.
% 4. Runs AMICA only.
% 5. Updates bemobil_import_table.csv with AMICA status and output path.
%
% Important:
% This script does NOT rerun basic preprocessing.
% This script should only run AMICA for files that passed preprocessing QC.
%
% Table-driven control:
%   DoAMICA = 1  -> run AMICA for this row
%   DoAMICA = 0  -> skip this row
%
% Default behavior:
%   If DoAMICA does not exist, it is created from:
%       PreprocessingStatus == "completed"
%       AND
%       PreprocessingQCStatus == "passed_basic_checks"
%
%   If DoAMICA already exists, this script uses the existing table values.


clear; clc; close all;

% Keep figures hidden during AMICA batch processing.
set(0, 'DefaultFigureVisible', 'off');
set(groot, 'DefaultFigureVisible', 'off');

%% ========================================================================
%  LOAD CENTRAL PATHS
%  ========================================================================

run(fullfile(fileparts(mfilename('fullpath')), 'paths.m'));

if ~exist(mappingFile, 'file')
    error('Import table not found:\n%s\nPlease run import_table.m, bemobil_import_resample_merge.m, preprocessing, and QC first.', mappingFile);
end

%% ========================================================================
%  AMICA SAFE CURRENT FOLDER
%  ========================================================================

% Force MATLAB current folder to a simple local path.
% This avoids AMICA problems with OneDrive paths, spaces, or non-ASCII characters.

if ~exist(amicaTempFolder, 'dir')
    mkdir(amicaTempFolder);
end

cd(amicaTempFolder);

fprintf('Current MATLAB folder for AMICA temp files:\n%s\n', pwd);

%% ========================================================================
%  AMICA SETTINGS
%  ========================================================================

% If true:
%   DoAMICA will be overwritten from:
%       PreprocessingStatus == "completed"
%       AND
%       PreprocessingQCStatus == "passed_basic_checks"
%
% If false:
%   Existing DoAMICA values in the CSV are used.
%
% Recommended:
%   false, because AMICA selection should be controlled manually by the table.
reset_DoAMICA_from_PreprocessingQC = false;

% Set to 1 if you want to recompute AMICA even if output already exists.
% For the first technical run, 1 is fine.
% After confirming the pipeline, use 0 to avoid recomputing completed AMICA results.
force_recompute_amica = 0;

%% ========================================================================
%  INITIALIZE EEGLAB
%  ========================================================================

if ~exist('ALLCOM', 'var')
    [ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab('nogui');
end

hide_all_figures();

%% ========================================================================
%  LOAD BEMOBIL CONFIGURATION
%  ========================================================================

run(fullfile(scriptsFolder, 'bemobil_config_.m'));

hide_all_figures();

%% ========================================================================
%  AMICA PARAMETERS
%  ========================================================================

% Final analysis can stay at 2000.
% For a quick technical test only, you may temporarily reduce this to 100.
bemobil_config.AMICA_max_iter = 2000;

% Keep 4 threads unless your PC crashes or becomes unstable.
bemobil_config.max_threads = 4;

fprintf('\nAMICA settings:\n');
fprintf('AMICA_max_iter: %d\n', bemobil_config.AMICA_max_iter);
fprintf('max_threads: %d\n', bemobil_config.max_threads);
fprintf('force_recompute_amica: %d\n', force_recompute_amica);
fprintf('reset_DoAMICA_from_PreprocessingQC: %d\n', reset_DoAMICA_from_PreprocessingQC);

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
               'Please run preprocessing and check_preprocessed_EEG_1.m first.'], ...
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

        fprintf('\nDoAMICA column already existed.\n');
        fprintf('Using existing DoAMICA values from the table because reset_DoAMICA_from_PreprocessingQC = false.\n');

    end

end

%% ========================================================================
%  SELECT ROWS TO PROCESS
%  ========================================================================

sourceMap = ensure_numeric_column(sourceMap, 'DoAMICA');

candidateRows = find(sourceMap.DoAMICA == 1);

if isempty(candidateRows)
    error('No rows with DoAMICA = 1 found in bemobil_import_table.csv.');
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

hide_all_figures();

%% ========================================================================
%  AMICA LOOP
%  ========================================================================

for r = 1:length(rowsToProcess)

    hide_all_figures();

    rowIdx = rowsToProcess(r);

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
        sourceMap.PreprocessedSetPath(rowIdx) = string(preprocessedSetPath);

        writetable(sourceMap, mappingFile);
        continue;

    end

    [preprocFolder, preprocFileNoExt, preprocExt] = fileparts(preprocessedSetPath);
    preprocFile = [preprocFileNoExt preprocExt];

    %% --------------------------------------------------------------------
    %  PREPARE AMICA STATUS COLUMNS
    %  --------------------------------------------------------------------

    sourceMap = ensure_string_column(sourceMap, 'AMICAStatus');
    sourceMap = ensure_string_column(sourceMap, 'AMICADate');
    sourceMap = ensure_string_column(sourceMap, 'AMICANotes');
    sourceMap = ensure_string_column(sourceMap, 'AMICASetPath');
    sourceMap = ensure_string_column(sourceMap, 'PreprocessedSetPath');

    sourceMap.PreprocessedSetPath(rowIdx) = string(preprocessedSetPath);
    sourceMap.AMICAStatus(rowIdx) = "running";
    sourceMap.AMICADate(rowIdx) = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    sourceMap.AMICANotes(rowIdx) = "";

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

    hide_all_figures();

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

        hide_all_figures();

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

    if EEG_preprocessed.nbchan ~= 64

        warning('Unexpected channel count before AMICA. Expected 64, got %d. Skipping.', EEG_preprocessed.nbchan);

        sourceMap = update_amica_status( ...
            sourceMap, rowIdx, ...
            "failed_unexpected_channel_count", ...
            "Expected 64 channels before AMICA.", ...
            "" ...
        );

        writetable(sourceMap, mappingFile);
        continue;

    end

    if abs(EEG_preprocessed.srate - 250) > 0.001

        warning('Unexpected sampling rate before AMICA. Expected 250 Hz, got %.2f Hz. Skipping.', EEG_preprocessed.srate);

        sourceMap = update_amica_status( ...
            sourceMap, rowIdx, ...
            "failed_unexpected_sampling_rate", ...
            "Expected 250 Hz sampling rate before AMICA.", ...
            "" ...
        );

        writetable(sourceMap, mappingFile);
        continue;

    end

    %% --------------------------------------------------------------------
    %  RUN AMICA ONLY
    %  --------------------------------------------------------------------

    try

        hide_all_figures();

        bemobil_process_all_AMICA( ...
            ALLEEG, ...
            EEG_preprocessed, ...
            CURRENTSET, ...
            processingSubjectLabel, ...
            bemobil_config, ...
            force_recompute_amica);

        hide_all_figures();

    catch ME

        hide_all_figures();

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
    %  TRY TO FIND AMICA OUTPUT FILE
    %  --------------------------------------------------------------------

    amicaCandidates = { ...
        fullfile(outputFolder, ...
            bemobil_config.spatial_filters_folder, ...
            processingSubjectFolder, ...
            bemobil_config.spatial_filters_folder_AMICA, ...
            [processingSubjectFolder '_' bemobil_config.amica_filename_output]), ...
        fullfile(outputFolder, ...
            bemobil_config.spatial_filters_folder, ...
            bemobil_config.spatial_filters_folder_AMICA, ...
            processingSubjectFolder, ...
            [processingSubjectFolder '_' bemobil_config.amica_filename_output]), ...
        fullfile(outputFolder, ...
            bemobil_config.spatial_filters_folder, ...
            processingSubjectFolder, ...
            [processingSubjectFolder '_' bemobil_config.amica_filename_output]) ...
    };

    foundAMICASetPath = "";

    for k = 1:length(amicaCandidates)

        if exist(amicaCandidates{k}, 'file')
            foundAMICASetPath = string(amicaCandidates{k});
            break;
        end

    end

    % Extra fallback: recursive search inside outputFolder.
    if strlength(foundAMICASetPath) == 0

        recursiveCandidates = dir(fullfile(outputFolder, '**', [processingSubjectFolder '*AMICA*.set']));

        if isempty(recursiveCandidates)
            recursiveCandidates = dir(fullfile(outputFolder, '**', [processingSubjectFolder '*amica*.set']));
        end

        if ~isempty(recursiveCandidates)
            foundAMICASetPath = string(fullfile(recursiveCandidates(1).folder, recursiveCandidates(1).name));
        end

    end

    sourceMap.AMICADate(rowIdx) = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

    if strlength(foundAMICASetPath) > 0

        sourceMap.AMICAStatus(rowIdx) = "completed";
        sourceMap.AMICASetPath(rowIdx) = foundAMICASetPath;
        sourceMap.AMICANotes(rowIdx) = "";

        fprintf('\nAMICA output found:\n%s\n', foundAMICASetPath);

    else

        sourceMap.AMICAStatus(rowIdx) = "finished_but_output_file_not_found";
        sourceMap.AMICANotes(rowIdx) = "AMICA function finished, but expected AMICA .set file was not found. Check 4_spatial-filters folder manually.";

        fprintf('\nWARNING: AMICA finished, but AMICA .set file was not found in expected candidate paths.\n');
        fprintf('Candidate paths checked:\n');

        for k = 1:length(amicaCandidates)
            fprintf('%s\n', amicaCandidates{k});
        end

    end

    writetable(sourceMap, mappingFile);

    hide_all_figures();

    fprintf('\n============================================================\n');
    fprintf('AMICA FINISHED FOR THIS FILE\n');
    fprintf('============================================================\n');
    fprintf('Import table updated:\n%s\n', mappingFile);

end

hide_all_figures();

%% ========================================================================
%  FINAL REPORT
%  ========================================================================

fprintf('\n\n============================================================\n');
fprintf('ALL SELECTED AMICA RUNS FINISHED\n');
fprintf('============================================================\n');
fprintf('Import table:\n%s\n', mappingFile);

optsFinal = detectImportOptions(mappingFile, ...
    'FileType', 'text', ...
    'Delimiter', ',', ...
    'VariableNamingRule', 'preserve');

sourceMapFinal = readtable(mappingFile, optsFinal);

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

fprintf('\nDone.\n');

hide_all_figures();

%% ========================================================================
%  HELPER FUNCTIONS
%  ========================================================================

function hide_all_figures()

    try
        set(0, 'DefaultFigureVisible', 'off');
        set(groot, 'DefaultFigureVisible', 'off');
        set(0, 'ShowHiddenHandles', 'on');
    catch
    end

    try
        figs = findall(groot, 'Type', 'figure');

        if ~isempty(figs)
            set(figs, 'Visible', 'off');
            close(figs);
        end

    catch
        try
            close all force;
        catch
        end
    end

end

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

function T = update_amica_status(T, rowIdx, statusValue, notesValue, setPathValue)

    T = ensure_string_column(T, 'AMICAStatus');
    T = ensure_string_column(T, 'AMICADate');
    T = ensure_string_column(T, 'AMICANotes');
    T = ensure_string_column(T, 'AMICASetPath');

    T.AMICAStatus(rowIdx) = string(statusValue);
    T.AMICANotes(rowIdx) = string(notesValue);
    T.AMICADate(rowIdx) = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

    if strlength(string(setPathValue)) > 0
        T.AMICASetPath(rowIdx) = string(setPathValue);
    end

end