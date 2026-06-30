% Current workflow:
%   1) check_eeg_streams.m
%   2) import_table.m
%   3) bemobil_import.m
%   4) bemobil_process_all_EEG_data.m
%   5) this AMICA-only script
%
% This script:
% 1. Reads bemobil_import_table.csv.
% 2. Selects rows using DoAMICA.
% 3. Loads the existing preprocessed .set file.
% 4. Runs AMICA only.
% 5. Updates bemobil_import_table.csv with AMICA status and output path.
%
% Important:
% This script does NOT rerun basic preprocessing.
%
% Table-driven control:
%   DoAMICA = 1  -> run AMICA for this row
%   DoAMICA = 0  -> skip this row
%
% If DoAMICA does not exist yet:
%   - this script creates it automatically.
%   - rows with PreprocessingStatus == "completed" are selected by default.
%   - if PreprocessingStatus does not exist, it falls back to DoPreprocess.

clear; clc; close all;

%% Load central paths

run(fullfile(fileparts(mfilename('fullpath')), 'paths.m'));

if ~exist(mappingFile, 'file')
    error('Import table not found:\n%s\nPlease run import_table.m, bemobil_import.m, and preprocessing first.', mappingFile);
end

%% AMICA safe current folder

% Force MATLAB current folder to a simple local path.
% This avoids AMICA problems with OneDrive paths, spaces, or non-ASCII characters.

if ~exist(amicaTempFolder, 'dir')
    mkdir(amicaTempFolder);
end

cd(amicaTempFolder);

fprintf('Current MATLAB folder for AMICA temp files:\n%s\n', pwd);

%% AMICA settings

% Set to 1 if you want to recompute AMICA even if output already exists.
% For first test, 1 is safer.
% For large batch processing, usually use 0 after confirming the pipeline.
force_recompute_amica = 1;

%% Start EEGLAB

[ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab;

%% Load BeMoBIL config

run(fullfile(scriptsFolder, 'bemobil_config_.m'));

%% AMICA parameters

% Final analysis can stay at 2000.
% For a quick test only, you may temporarily reduce this to 100.
bemobil_config.AMICA_max_iter = 2000;

% Keep 4 threads unless your PC crashes.
bemobil_config.max_threads = 4;

%% Read import table

optsImport = detectImportOptions(mappingFile, ...
    'FileType', 'text', ...
    'Delimiter', ',', ...
    'VariableNamingRule', 'preserve');

sourceMap = readtable(mappingFile, optsImport);

%% Check required columns

requiredColumns = { ...
    'DoImport', ...
    'XdfPath', ...
    'FileName', ...
    'BidsSubject', ...
    'BidsSession' ...
};

for c = 1:length(requiredColumns)
    if ~ismember(requiredColumns{c}, sourceMap.Properties.VariableNames)
        error('Import table is missing required column: %s', requiredColumns{c});
    end
end

%% Normalize important columns

sourceMap = ensure_numeric_column(sourceMap, 'DoImport');
sourceMap = ensure_numeric_column(sourceMap, 'BidsSubject');

sourceMap.XdfPath     = string(sourceMap.XdfPath);
sourceMap.FileName    = string(sourceMap.FileName);
sourceMap.BidsSession = string(sourceMap.BidsSession);

if ismember('DoPreprocess', sourceMap.Properties.VariableNames)
    sourceMap = ensure_numeric_column(sourceMap, 'DoPreprocess');
end

if ismember('PreprocessingStatus', sourceMap.Properties.VariableNames)
    sourceMap.PreprocessingStatus = string(sourceMap.PreprocessingStatus);
end

if ismember('ProcessingSubjectLabel', sourceMap.Properties.VariableNames)
    sourceMap.ProcessingSubjectLabel = string(sourceMap.ProcessingSubjectLabel);
end

if ismember('PreprocessedSetPath', sourceMap.Properties.VariableNames)
    sourceMap.PreprocessedSetPath = string(sourceMap.PreprocessedSetPath);
end

if ismember('EEGStreamName', sourceMap.Properties.VariableNames)
    sourceMap.EEGStreamName = string(sourceMap.EEGStreamName);
end

%% Create or read DoAMICA

if ~ismember('DoAMICA', sourceMap.Properties.VariableNames)

    sourceMap.DoAMICA = zeros(height(sourceMap), 1);

    if ismember('PreprocessingStatus', sourceMap.Properties.VariableNames)

        status = string(sourceMap.PreprocessingStatus);

        % Only completed preprocessing rows are selected for AMICA by default.
        sourceMap.DoAMICA(status == "completed") = 1;

    elseif ismember('DoPreprocess', sourceMap.Properties.VariableNames)

        sourceMap.DoAMICA = sourceMap.DoPreprocess;

    else

        % Last fallback: use imported rows.
        sourceMap.DoAMICA = sourceMap.DoImport;

    end

    writetable(sourceMap, mappingFile);

    fprintf('\nDoAMICA column was not found.\n');
    fprintf('Created DoAMICA automatically and saved it to:\n%s\n', mappingFile);
    fprintf('You can manually edit DoAMICA later:\n');
    fprintf('  DoAMICA = 1 -> run AMICA for this row\n');
    fprintf('  DoAMICA = 0 -> skip this row\n');

else

    sourceMap = ensure_numeric_column(sourceMap, 'DoAMICA');

end

%% Select rows from table

rowsToProcess = find(sourceMap.DoAMICA == 1);

if isempty(rowsToProcess)
    error('No rows with DoAMICA = 1 found in bemobil_import_table.csv.');
end

fprintf('\n============================================================\n');
fprintf('AMICA-ONLY PROCESSING STARTED\n');
fprintf('============================================================\n');
fprintf('Selection mode: table-driven\n');
fprintf('Rows with DoAMICA = 1: %d\n', length(rowsToProcess));
fprintf('Import table:\n%s\n', mappingFile);
fprintf('============================================================\n\n');

%% AMICA loop

for r = 1:length(rowsToProcess)

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

    %% Resolve processing label

    if ismember('ProcessingSubjectLabel', sourceMap.Properties.VariableNames) && ...
            ~ismissing(string(sourceMap.ProcessingSubjectLabel(rowIdx))) && ...
            strlength(strtrim(string(sourceMap.ProcessingSubjectLabel(rowIdx)))) > 0

        processingSubjectLabel = char(sourceMap.ProcessingSubjectLabel(rowIdx));

    else

        % Fallback:
        % preprocessing script uses BidsSession as unique processing label.
        processingSubjectLabel = char(make_bids_label(string(bidsSession)));

    end

    processingSubjectFolder = ['sub-' processingSubjectLabel];

    %% Resolve preprocessed .set file path

    preprocessedSetPath = "";

    if ismember('PreprocessedSetPath', sourceMap.Properties.VariableNames)

        candidatePath = string(sourceMap.PreprocessedSetPath(rowIdx));

        if ~ismissing(candidatePath) && strlength(strtrim(candidatePath)) > 0
            preprocessedSetPath = candidatePath;
        end

    end

    if strlength(preprocessedSetPath) == 0

        % Fallback: reconstruct expected preprocessed path.
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
    fprintf('Preprocessed file:\n%s\n', preprocessedSetPath);
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

    %% Prepare AMICA status columns

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

    %% Reset EEGLAB variables for this AMICA run

    STUDY = [];
    CURRENTSTUDY = 0;
    ALLEEG = [];
    CURRENTSET = [];
    EEG = [];

    %% Load existing preprocessed EEG

    fprintf('\nLoading existing preprocessed EEG:\n%s\n', preprocessedSetPath);

    try

        EEG_preprocessed = pop_loadset( ...
            'filename', preprocFile, ...
            'filepath', preprocFolder ...
        );

        EEG_preprocessed = eeg_checkset(EEG_preprocessed);

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

    %% Store source information inside EEG.etc again

    EEG_preprocessed.etc.source_original_xdf_name = originalXDFName;
    EEG_preprocessed.etc.source_original_xdf_path = originalXDFPath;
    EEG_preprocessed.etc.real_bids_subject = bidsSubject;
    EEG_preprocessed.etc.session_label = bidsSession;
    EEG_preprocessed.etc.processing_subject_label = processingSubjectLabel;

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

    %% Run AMICA only

    try

        bemobil_process_all_AMICA( ...
            ALLEEG, ...
            EEG_preprocessed, ...
            CURRENTSET, ...
            processingSubjectLabel, ...
            bemobil_config, ...
            force_recompute_amica);

    catch ME

        sourceMap = update_amica_status( ...
            sourceMap, rowIdx, ...
            "failed", ...
            string(ME.message), ...
            "" ...
        );

        writetable(sourceMap, mappingFile);
        continue;

    end

    %% Try to find AMICA output file

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

    fprintf('\n============================================================\n');
    fprintf('AMICA FINISHED FOR THIS FILE\n');
    fprintf('============================================================\n');
    fprintf('Import table updated:\n%s\n', mappingFile);

end

fprintf('\n\n============================================================\n');
fprintf('ALL SELECTED AMICA RUNS FINISHED\n');
fprintf('============================================================\n');
fprintf('Import table:\n%s\n', mappingFile);
fprintf('Done.\n');

%% Helper functions

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