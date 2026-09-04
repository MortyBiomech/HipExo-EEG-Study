% GOAL
%   Run basic BeMoBIL EEG preprocessing on each verified subject-level
%   500 Hz dataset produced by Step 03.
%
% INPUT
%   2_raw-EEGLAB/subject-level/subject_level_EEG_processing_table.csv
%   Subject-level *_all_sessions_500Hz_with_GRF_events.set datasets.
%
% APPROACH
%   1. Select rows enabled by DoPreprocess.
%   2. Load one verified subject-level raw EEGLAB dataset per participant.
%   3. Run the established BeMoBIL bad-channel, interpolation, and
%      ZapLine-Plus preprocessing path.
%   4. Preserve gait events and disable event-based trimming.
%   5. Save preprocessing provenance/status without running AMICA.
%
% OUTPUT
%   3_EEG-preprocessing/sub-*/...
%   Updated subject_level_EEG_processing_table.csv
%
% USED BY
%   Step 06 preprocessing QC and Step 07 AMICA/DIPFIT/ICLabel.

clear; clc; close all;

% Keep figures hidden during batch preprocessing.
set(0, 'DefaultFigureVisible', 'off');
set(groot, 'DefaultFigureVisible', 'off');

%% ========================================================================
%  LOAD PATHS AND STEP 05-09 CONFIGURATION
%  ========================================================================

runFolder = fileparts(mfilename('fullpath'));
scriptsRoot = fileparts(runFolder);

addpath(scriptsRoot, '-begin');
addpath(fullfile(scriptsRoot, 'config'), '-begin');

P = project_paths();

bemobil_config = ...
    config_step05_09_eeg_preprocessing_ica(P);

mappingFile = P.subjectLevelEEGTableFile;

if ~exist(mappingFile, 'file')
    error([ ...
        'Subject-level EEG processing table not found:\n%s\n' ...
        'Run step03_process_subject_grf_eeg.m first and confirm that ' ...
        'subject concatenation completed.'], ...
        mappingFile);
end

%% ========================================================================
%  PROCESSING SETTINGS
%  ========================================================================

% If true:
%   DoPreprocess will be overwritten from RecommendedDoPreprocess.
%
% Recommended for the first run after a new import/audit.
%
% if you want to manually edit DoPreprocess in the CSV,
% set this to false.
reset_DoPreprocess_from_Recommended = ...
    bemobil_config.pipeline.reset_DoPreprocess_from_Recommended;

% Recompute BeMoBIL preprocessing output.
force_recompute = ...
    bemobil_config.pipeline.force_recompute_preprocessing;

%% ========================================================================
%  INITIALIZE EEGLAB
%  ========================================================================

if ~exist('ALLCOM', 'var')
    eeglab nogui;
end

hipexo.hide_all_figures();
%% ========================================================================
%  INITIALIZE FIELDTRIP
%  ========================================================================

global ft_default
ft_default.toolbox.signal = 'matlab';
ft_default.toolbox.stats  = 'matlab';
ft_default.toolbox.image  = 'matlab';

ft_defaults;

hipexo.hide_all_figures();

if isempty(which('load_xdf'))
    error('load_xdf was not found. Please check FieldTrip external/xdf path.');
end

if isempty(which('clean_data_with_zapline_plus_eeglab_wrapper'))
    error('zapline-plus was not found. Please install it via EEGLAB extension manager.');
else
    fprintf('Using zapline-plus from:\n%s\n', which('clean_data_with_zapline_plus_eeglab_wrapper'));
end

hipexo.hide_all_figures();
%% ========================================================================
%  FREEZE ONE CLEAN BASE CONFIG
%  ========================================================================

base_bemobil_config = bemobil_config;

preprocessingConfigSignature = ...
    hipexo.preprocessing_scientific_signature(base_bemobil_config);

hipexo.hide_all_figures();
%% ========================================================================
%  READ IMPORT TABLE
%  ========================================================================

optsImport = detectImportOptions(mappingFile, ...
    'FileType', 'text', ...
    'Delimiter', ',', ...
    'VariableNamingRule', 'preserve');

sourceMap = readtable(mappingFile, optsImport);


%% ========================================================================
%  CHECK REQUIRED COLUMNS
%  ========================================================================

requiredColumns = { ...
    'DoImport', ...
    'XdfPath', ...
    'FileName', ...
    'BidsSubject', ...
    'BidsSession', ...
    'RawSetPath', ...
    'RawSetStatus', ...
    'RecommendedDoPreprocess' ...
};

for c = 1:length(requiredColumns)
    if ~ismember(requiredColumns{c}, sourceMap.Properties.VariableNames)
        error(['Subject-level processing table is missing required column: %s\n' ...
               'Run step03_process_subject_grf_eeg.m and complete subject concatenation first.'], ...
               requiredColumns{c});
    end
end

%% ========================================================================
%  NORMALIZE IMPORTANT COLUMNS
%  ========================================================================

sourceMap = ensure_numeric_column(sourceMap, 'DoImport');
sourceMap = ensure_numeric_column(sourceMap, 'BidsSubject');
sourceMap = ensure_numeric_column(sourceMap, 'RecommendedDoPreprocess');

sourceMap.XdfPath = string(sourceMap.XdfPath);
sourceMap.FileName = string(sourceMap.FileName);
sourceMap.BidsSession = string(sourceMap.BidsSession);
sourceMap.RawSetPath = string(sourceMap.RawSetPath);
sourceMap.RawSetStatus = string(sourceMap.RawSetStatus);

sourceMap.XdfPath(ismissing(sourceMap.XdfPath)) = "";
sourceMap.FileName(ismissing(sourceMap.FileName)) = "";
sourceMap.BidsSession(ismissing(sourceMap.BidsSession)) = "";
sourceMap.RawSetPath(ismissing(sourceMap.RawSetPath)) = "";
sourceMap.RawSetStatus(ismissing(sourceMap.RawSetStatus)) = "";

if ismember('EEGStreamName', sourceMap.Properties.VariableNames)
    sourceMap.EEGStreamName = string(sourceMap.EEGStreamName);
    sourceMap.EEGStreamName(ismissing(sourceMap.EEGStreamName)) = "";
end

if ismember('RunNumber', sourceMap.Properties.VariableNames)
    sourceMap = ensure_numeric_column(sourceMap, 'RunNumber');
else
    sourceMap.RunNumber = nan(height(sourceMap), 1);
end

%% ========================================================================
%  CREATE OR RESET DOPREPROCESS
%  ========================================================================

if ~ismember('DoPreprocess', sourceMap.Properties.VariableNames)

    sourceMap.DoPreprocess = sourceMap.RecommendedDoPreprocess;

    writetable(sourceMap, mappingFile);

    fprintf('\nDoPreprocess column was not found.\n');
    fprintf('Created DoPreprocess from RecommendedDoPreprocess and saved it to:\n%s\n', mappingFile);

else

    sourceMap = ensure_numeric_column(sourceMap, 'DoPreprocess');

    if reset_DoPreprocess_from_Recommended

        sourceMap.DoPreprocess = sourceMap.RecommendedDoPreprocess;

        writetable(sourceMap, mappingFile);

        fprintf('\nDoPreprocess column already existed.\n');
        fprintf('Reset DoPreprocess from RecommendedDoPreprocess because reset_DoPreprocess_from_Recommended = true.\n');
        fprintf('Updated import table saved to:\n%s\n', mappingFile);

    else

        fprintf('\nDoPreprocess column already existed.\n');
        fprintf('Using existing DoPreprocess values because reset_DoPreprocess_from_Recommended = false.\n');

    end

end

%% ========================================================================
%  SELECT ROWS TO PROCESS
%  ========================================================================

sourceMap = ensure_numeric_column(sourceMap, 'DoPreprocess');

candidateRows = find(sourceMap.DoPreprocess == 1);

if isempty(candidateRows)
    error('No rows with DoPreprocess = 1 found in the subject-level processing table.');
end

% Only process rows that have an OK raw set status and a non-empty RawSetPath.
hasRawPath = strlength(strtrim(sourceMap.RawSetPath)) > 0;
hasOKRawSet = startsWith(sourceMap.RawSetStatus, "OK_");

validRows = candidateRows(hasRawPath(candidateRows) & hasOKRawSet(candidateRows));

if isempty(validRows)

    fprintf('\nRows with DoPreprocess = 1 exist, but none have OK RawSetStatus and non-empty RawSetPath.\n');
    fprintf('Problem rows:\n');
    disp(sourceMap(candidateRows, {'FileName', 'BidsSubject', 'BidsSession', ...
                                   'DoImport', 'DoPreprocess', ...
                                   'RawSetStatus', 'RawSetPath'}));

    error('No valid rows for preprocessing.');

end

% Safety: avoid processing the same RawSetPath more than once.
rawPathsForValidRows = sourceMap.RawSetPath(validRows);
[~, uniqueIdx] = unique(rawPathsForValidRows, 'stable');
rowsToProcess = validRows(uniqueIdx);

fprintf('\n============================================================\n');
fprintf('BASIC EEG PREPROCESSING STARTED\n');
fprintf('============================================================\n');
fprintf('Selection mode: table-driven raw-set-level preprocessing\n');
fprintf('Rows with DoPreprocess = 1: %d\n', length(candidateRows));
fprintf('Rows with OK RawSetStatus and RawSetPath: %d\n', length(validRows));
fprintf('Unique raw .set files to preprocess: %d\n', length(rowsToProcess));
fprintf('Import table:\n%s\n', mappingFile);
fprintf('============================================================\n\n');

fprintf('Rows selected for preprocessing:\n');
disp(sourceMap(rowsToProcess, {'FileName', 'BidsSubject', 'BidsSession', ...
                               'RawSetStatus', 'RawSetPath'}));

hipexo.hide_all_figures();
%% ========================================================================
%  PROCESSING LOOP
%  ========================================================================

for r = 1:length(rowsToProcess)

    hipexo.hide_all_figures();
    rowIdx = rowsToProcess(r);
    sessionRows = hipexo.session_peer_rows(sourceMap, rowIdx);

    % Reset config for each file.
    bemobil_config = base_bemobil_config;

    %% --------------------------------------------------------------------
    %  READ LABELS FROM IMPORT TABLE
    %  --------------------------------------------------------------------

    bidsSubject = sourceMap.BidsSubject(rowIdx);
    bidsSession = char(sourceMap.BidsSession(rowIdx));

    originalXDFName = char(sourceMap.FileName(rowIdx));
    originalXDFPath = char(sourceMap.XdfPath(rowIdx));

    rawSetStatus = char(sourceMap.RawSetStatus(rowIdx));
    importedSetPath = char(sourceMap.RawSetPath(rowIdx));

    if isnan(bidsSubject)

        warning('Invalid BidsSubject in row %d. Skipping this row.', rowIdx);

        sourceMap = update_mapping_status( ...
            sourceMap, rowIdx, ...
            "PreprocessingStatus", "failed_invalid_bids_subject", ...
            "PreprocessingNotes", "BidsSubject is NaN or invalid." ...
        );

        sourceMap = ensure_string_column(sourceMap, 'PreprocessingDate');
        sourceMap.PreprocessingDate(sessionRows) = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

        writetable(sourceMap, mappingFile);
        continue;

    end

    if strlength(strtrim(string(importedSetPath))) == 0

        warning('RawSetPath is empty in row %d. Skipping this row.', rowIdx);

        sourceMap = update_mapping_status( ...
            sourceMap, rowIdx, ...
            "PreprocessingStatus", "failed_empty_raw_set_path", ...
            "PreprocessingNotes", "RawSetPath is empty." ...
        );

        sourceMap = ensure_string_column(sourceMap, 'PreprocessingDate');
        sourceMap.PreprocessingDate(sessionRows) = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

        writetable(sourceMap, mappingFile);
        continue;

    end

    if ~startsWith(string(rawSetStatus), "OK_")

        warning('RawSetStatus is not OK in row %d. Skipping this row. Status: %s', rowIdx, rawSetStatus);

        sourceMap = update_mapping_status( ...
            sourceMap, rowIdx, ...
            "PreprocessingStatus", "failed_raw_set_status_not_ok", ...
            "PreprocessingNotes", "RawSetStatus is not OK." ...
        );

        sourceMap = ensure_string_column(sourceMap, 'PreprocessingDate');
        sourceMap.PreprocessingDate(sessionRows) = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

        writetable(sourceMap, mappingFile);
        continue;

    end

    %% --------------------------------------------------------------------
    %  PROCESSING LABEL
    %  --------------------------------------------------------------------

    % This label is used for preprocessing output.
    % It must be unique per final raw set/session.
    %
    % Example:
    %   BidsSession:
    %       Pilot2p3day2sesNoExoPost
    %
    %   ProcessingSubjectLabel:
    %       Pilot2p3day2sesNoExoPost
    %
    %   ProcessingSubjectFolder:
    %       sub-Pilot2p3day2sesNoExoPost

    processingSubjectLabel = char(make_bids_label(string(bidsSession)));
    processingSubjectFolder = [bemobil_config.filename_prefix processingSubjectLabel];

    fprintf('\n\n============================================================\n');
    fprintf('PROCESSING RAW SET %d / %d\n', r, length(rowsToProcess));
    fprintf('============================================================\n');
    fprintf('Table row: %d\n', rowIdx);
    fprintf('Original XDF name:\n%s\n\n', originalXDFName);
    fprintf('Original XDF path:\n%s\n\n', originalXDFPath);
    fprintf('Imported BIDS subject:\nsub-%d\n', bidsSubject);
    fprintf('Imported BIDS session:\n%s\n', bidsSession);
    fprintf('RawSetStatus:\n%s\n', rawSetStatus);
    fprintf('RawSetPath:\n%s\n', importedSetPath);
    fprintf('Processing label:\n%s\n', processingSubjectLabel);
    fprintf('Processing folder:\n%s\n', processingSubjectFolder);
    fprintf('============================================================\n\n');

    %% --------------------------------------------------------------------
    %  RESOLVE IMPORTED EEGLAB FILE PATH FROM RAWSETPATH
    %  --------------------------------------------------------------------

    if ~exist(importedSetPath, 'file')

        warning('Imported EEGLAB .set file does not exist. Skipping this row:\n%s', importedSetPath);

        sourceMap = update_mapping_status( ...
            sourceMap, rowIdx, ...
            "PreprocessingStatus", "failed_imported_set_not_found", ...
            "PreprocessingNotes", "RawSetPath points to a .set file that does not exist." ...
        );

        sourceMap = ensure_string_column(sourceMap, 'ImportedSetPath');
        sourceMap = ensure_string_column(sourceMap, 'PreprocessingDate');

        sourceMap.ImportedSetPath(sessionRows) = string(importedSetPath);
        sourceMap.PreprocessingDate(sessionRows) = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

        writetable(sourceMap, mappingFile);

        continue;

    end

    [input_filepath, input_name, input_ext] = fileparts(importedSetPath);
    input_filename = [input_name input_ext];


    %% --------------------------------------------------------------------
    %  PREPARE EXPECTED OUTPUT PATH
    %  --------------------------------------------------------------------

    preprocessedFolder = fullfile( ...
        bemobil_config.study_folder, ...
        bemobil_config.EEG_preprocessing_data_folder, ...
        processingSubjectFolder ...
    );

    preprocessedSetPath = fullfile( ...
        preprocessedFolder, ...
        [processingSubjectFolder '_' bemobil_config.preprocessed_filename] ...
    );

    basicPreparedSetPath = fullfile( ...
        preprocessedFolder, ...
        [processingSubjectFolder '_' bemobil_config.basic_prepared_filename] ...
    );

    % Do NOT create the single-subject analysis folder here.
    % This script only performs basic preprocessing.
    % The 5_single-subject-EEG-analysis folder belongs to the AMICA/ICA stage
    % and is created by bemobil_process_all_AMICA.m.

    %% --------------------------------------------------------------------
    %  PREPARE TABLE COLUMNS BEFORE POSSIBLE SKIP
    %  --------------------------------------------------------------------

    sourceMap = ensure_string_column(sourceMap, 'ProcessingSubjectLabel');
    sourceMap = ensure_string_column(sourceMap, 'ProcessingSubjectFolder');
    sourceMap = ensure_string_column(sourceMap, 'ImportedSetPath');
    sourceMap = ensure_string_column(sourceMap, 'PreprocessedSetPath');
    sourceMap = ensure_string_column(sourceMap, 'PreprocessingStatus');
    sourceMap = ensure_string_column(sourceMap, 'PreprocessingDate');
    sourceMap = ensure_string_column(sourceMap, 'PreprocessingNotes');
    sourceMap = ensure_string_column(sourceMap, 'PreprocessingInputSignature');

    sourceMap.ProcessingSubjectLabel(sessionRows) = string(processingSubjectLabel);
    sourceMap.ProcessingSubjectFolder(sessionRows) = string(processingSubjectFolder);
    sourceMap.ImportedSetPath(sessionRows) = string(importedSetPath);
    sourceMap.PreprocessedSetPath(sessionRows) = string(preprocessedSetPath);

    expectedInputSignature = hipexo.eeglab_dataset_signature(importedSetPath) + ...
        "|cfg=" + preprocessingConfigSignature;
    sessionAlreadyCompleted = any( ...
        sourceMap.PreprocessingStatus(sessionRows) == "completed" & ...
        sourceMap.PreprocessingInputSignature(sessionRows) == expectedInputSignature);

    %% --------------------------------------------------------------------
    %  SKIP ALREADY COMPLETED PREPROCESSING IF NOT RECOMPUTING
    %  --------------------------------------------------------------------

    if force_recompute == 0 && ...
            sessionAlreadyCompleted && ...
            exist(preprocessedSetPath, 'file') == 2

        fprintf('\nPreprocessing already completed. Skipping this raw set:\n%s\n', preprocessedSetPath);

        sourceMap.PreprocessingStatus(sessionRows) = "completed";
        sourceMap.PreprocessingInputSignature(sessionRows) = expectedInputSignature;
        sourceMap.PreprocessingNotes(sessionRows) = ...
            "Skipped because preprocessing was already completed and force_recompute = 0.";

        writetable(sourceMap, mappingFile);

        continue;

    end

    rowForceRecompute = force_recompute ~= 0;
    if (exist(preprocessedSetPath, 'file') == 2 || ...
            exist(basicPreparedSetPath, 'file') == 2) && ...
            ~sessionAlreadyCompleted
        rowForceRecompute = true;
        fprintf('\nExisting preprocessing output is stale or unverified. Forcing a complete BeMoBIL recomputation.\n');
    end

    %% --------------------------------------------------------------------
    %  UPDATE TABLE BEFORE PROCESSING
    %  --------------------------------------------------------------------

    sourceMap.PreprocessingStatus(sessionRows) = "running";
    sourceMap.PreprocessingDate(sessionRows) = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    sourceMap.PreprocessingNotes(sessionRows) = "";
    sourceMap.PreprocessingInputSignature(sessionRows) = expectedInputSignature;

    writetable(sourceMap, mappingFile);

    %% --------------------------------------------------------------------
    %  EEGLAB MEMORY/SAVE OPTIONS
    %  --------------------------------------------------------------------

    try
        pop_editoptions( ...
            'option_saveversion6', ...
            bemobil_config.eeglab_options.option_saveversion6, ...
            'option_single', ...
            bemobil_config.eeglab_options.option_single, ...
            'option_memmapdata', ...
            bemobil_config.eeglab_options.option_memmapdata, ...
            'option_savetwofiles', ...
            bemobil_config.eeglab_options.option_savetwofiles, ...
            'option_storedisk', ...
            bemobil_config.eeglab_options.option_storedisk);
    catch
        warning('Could NOT edit EEGLAB memory options.');
    end

    hipexo.hide_all_figures();
    %% --------------------------------------------------------------------
    %  RESET EEGLAB VARIABLES FOR THIS FILE
    %  --------------------------------------------------------------------

    STUDY = [];
    CURRENTSTUDY = 0;
    ALLEEG = [];
    CURRENTSET = [];
    EEG = [];
    EEG_interp_avref = [];
    EEG_single_subject_final = [];

    %% --------------------------------------------------------------------
    %  LOAD IMPORTED EEGLAB .SET FILE
    %  --------------------------------------------------------------------

    fprintf('\nLoading imported EEGLAB file:\n%s\nfrom:\n%s\n', input_filename, input_filepath);

    try
        EEG = pop_loadset( ...
            'filename', input_filename, ...
            'filepath', input_filepath ...
        );

        EEG = eeg_checkset(EEG);
    catch ME
        sourceMap = update_mapping_status(sourceMap, rowIdx, ...
            "PreprocessingStatus", "failed_load_raw_set", ...
            "PreprocessingNotes", string(ME.message));
        writetable(sourceMap, mappingFile);
        continue;
    end

    %% --------------------------------------------------------------------
    %  REQUIRE THE SUBJECT-LEVEL GRF/EVENT INPUT
    %  --------------------------------------------------------------------

    try

        if ~isfield(EEG, 'etc') || ...
                ~isfield( ...
                    EEG.etc, ...
                    'subject_level_concatenation') || ...
                ~logical(EEG.etc.subject_level_concatenation)

            error([ ...
                'Input is not a verified subject-level concatenated EEG. ' ...
                'Run step03_process_subject_grf_eeg.m first.']);
        end

        if EEG.nbchan ~= 64 || ...
                abs(double(EEG.srate) - 500) > 1e-6

            error([ ...
                'Expected subject-level input with 64 channels at 500 Hz. ' ...
                'Found %d channels at %.9g Hz.'], ...
                EEG.nbchan, ...
                EEG.srate);
        end

        if numel(EEG.chanlocs) ~= EEG.nbchan || ...
                ~all(isfield(EEG.chanlocs, {'X', 'Y', 'Z'})) || ...
                any(cellfun(@isempty, {EEG.chanlocs.X})) || ...
                any(cellfun(@isempty, {EEG.chanlocs.Y})) || ...
                any(cellfun(@isempty, {EEG.chanlocs.Z}))

            error('Project channel locations are missing or incomplete.');
        end

        eventTypes = ...
            string({EEG.event.type});

        requiredGaitEventTypes = ...
            ["RHS", "RTO", "LHS", "LTO"];

        missingGaitEventTypes = ...
            requiredGaitEventTypes( ...
                ~ismember( ...
                    requiredGaitEventTypes, ...
                    eventTypes));

        if ~isempty(missingGaitEventTypes)

            error([ ...
                'Required GRF-derived gait-event types are missing: %s'], ...
                strjoin(missingGaitEventTypes, ', '));
        end

    catch inputGateError

        sourceMap = update_mapping_status( ...
            sourceMap, ...
            rowIdx, ...
            "PreprocessingStatus", ...
            "failed_subject_level_input_gate", ...
            "PreprocessingNotes", ...
            string(inputGateError.message));

        writetable(sourceMap, mappingFile);
        continue;
    end

    hipexo.hide_all_figures();
    %% --------------------------------------------------------------------
    %  STORE SOURCE INFORMATION INSIDE EEG.ETC
    %  --------------------------------------------------------------------

    EEG.etc.source_original_xdf_name = originalXDFName;
    EEG.etc.source_original_xdf_path = originalXDFPath;
    EEG.etc.real_bids_subject = bidsSubject;
    EEG.etc.session_label = bidsSession;
    EEG.etc.processing_subject_label = processingSubjectLabel;
    EEG.etc.raw_set_status = rawSetStatus;
    EEG.etc.raw_set_path = importedSetPath;
    EEG.etc.preprocessing_input_signature = char(expectedInputSignature);
    EEG.etc.preprocessing_config_signature = char(preprocessingConfigSignature);
    EEG.etc.preprocessing_config_signature_version = ...
        'HipExo_preprocessing_scientific_config_v1';

    sourceRows = find(sourceMap.RawSetPath == string(importedSetPath));
    EEG.etc.source_original_xdf_names = sourceMap.FileName(sourceRows);
    EEG.etc.source_original_xdf_paths = sourceMap.XdfPath(sourceRows);
    EEG.etc.source_run_numbers = sourceMap.RunNumber(sourceRows);

    if ismember('EEGStreamName', sourceMap.Properties.VariableNames)
        EEG.etc.source_eeg_stream_name = char(sourceMap.EEGStreamName(rowIdx));
    end

    if ismember('RunNumber', sourceMap.Properties.VariableNames)
        EEG.etc.source_run_number = sourceMap.RunNumber(rowIdx);
    end

    %% --------------------------------------------------------------------
    %  CHECK AND FILTER CHANNELS_TO_REMOVE
    %  --------------------------------------------------------------------

    all_labels = {EEG.chanlocs.labels};

    disp('All channel labels in current EEG:');
    disp(all_labels');

    if isfield(bemobil_config, 'channels_to_remove') && ~isempty(bemobil_config.channels_to_remove)

        original_remove_list = bemobil_config.channels_to_remove;

        existing_remove_list = original_remove_list( ...
            ismember(original_remove_list, all_labels) ...
        );

        missing_remove_list = setdiff(original_remove_list, all_labels);

        disp('Requested channels to remove:');
        disp(original_remove_list');

        disp('Actually existing channels to remove:');
        disp(existing_remove_list');

        disp('Requested but missing channels, will be ignored:');
        disp(missing_remove_list');

        bemobil_config.channels_to_remove = existing_remove_list;

    else

        disp('No channels_to_remove specified.');

    end


    %% --------------------------------------------------------------------
    %  EVENT-BASED TRIMMING IS INTENTIONALLY DISABLED
    %  --------------------------------------------------------------------

    nEventsBeforePreprocessing = numel(EEG.event);


    EEG.etc.event_based_trimming_disabled = true;
    EEG.etc.event_based_trimming_note = ...
        'Whole recording was used. EEG.event was not used for trimming in this preprocessing script.';
    EEG.etc.n_events_before_preprocessing = nEventsBeforePreprocessing;

    hipexo.hide_all_figures();
    %% --------------------------------------------------------------------
    %  BASIC EEG PREPROCESSING
    %  --------------------------------------------------------------------

    try

        hipexo.hide_all_figures();
        [ALLEEG, EEG_preprocessed, CURRENTSET] = bemobil_process_all_EEG_preprocessing( ...
            processingSubjectLabel, ...
            bemobil_config, ...
            ALLEEG, ...
            EEG, ...
            CURRENTSET, ...
            rowForceRecompute);

        hipexo.hide_all_figures();
    catch ME

        hipexo.hide_all_figures();
        warning('Preprocessing failed for table row %d:\n%s', rowIdx, ME.message);

        sourceMap = update_mapping_status( ...
            sourceMap, rowIdx, ...
            "PreprocessingStatus", "failed", ...
            "PreprocessingNotes", string(ME.message) ...
        );

        sourceMap = ensure_string_column(sourceMap, 'PreprocessingDate');
        sourceMap.PreprocessingDate(sessionRows) = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

        writetable(sourceMap, mappingFile);

        continue;

    end

    %% --------------------------------------------------------------------
    %  CHECK OUTPUT AND UPDATE TABLE
    %  --------------------------------------------------------------------

    outputProvenanceOK = isfield(EEG_preprocessed, 'etc') && ...
        isfield(EEG_preprocessed.etc, 'preprocessing_input_signature') && ...
        string(EEG_preprocessed.etc.preprocessing_input_signature) == expectedInputSignature;

    if exist(preprocessedSetPath, 'file') && outputProvenanceOK

        sourceMap.PreprocessingStatus(sessionRows) = "completed";
        sourceMap.PreprocessingNotes(sessionRows) = "";

    elseif exist(preprocessedSetPath, 'file')

        sourceMap.PreprocessingStatus(sessionRows) = "failed_output_provenance_mismatch";
        sourceMap.PreprocessingNotes(sessionRows) = ...
            "Preprocessed output exists, but its stored input signature does not match the current raw set/config.";

    else

        sourceMap.PreprocessingStatus(sessionRows) = "finished_but_output_file_not_found";
        sourceMap.PreprocessingNotes(sessionRows) = "BeMoBIL finished, but expected preprocessed .set was not found. Check output folders.";

    end

    sourceMap.PreprocessingDate(sessionRows) = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

    writetable(sourceMap, mappingFile);

    hipexo.hide_all_figures();
end

hipexo.hide_all_figures();
%% ========================================================================
%  FINAL REPORT
%  ========================================================================

fprintf('\nBasic EEG preprocessing finished.\n');

sourceMapFinal = sourceMap;

if ismember('PreprocessingStatus', sourceMapFinal.Properties.VariableNames)

    sourceMapFinal.PreprocessingStatus = string(sourceMapFinal.PreprocessingStatus);
    sourceMapFinal.PreprocessingStatus(ismissing(sourceMapFinal.PreprocessingStatus)) = "";

    fprintf('\nPreprocessing status summary:\n');

    statusNonEmpty = sourceMapFinal.PreprocessingStatus(strlength(sourceMapFinal.PreprocessingStatus) > 0);
    uniqueStatus = unique(statusNonEmpty, 'stable');

    if isempty(uniqueStatus)
        fprintf('  No preprocessing status entries found.\n');
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
    % BIDS labels should be letters/numbers only.
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

function T = update_mapping_status(T, rowIdx, statusColumn, statusValue, notesColumn, notesValue)

    T = ensure_string_column(T, char(statusColumn));
    T = ensure_string_column(T, char(notesColumn));

    rows = hipexo.session_peer_rows(T, rowIdx);
    T.(char(statusColumn))(rows) = string(statusValue);
    T.(char(notesColumn))(rows) = string(notesValue);

end
