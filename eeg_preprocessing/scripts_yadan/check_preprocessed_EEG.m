% Goal:
% Check BeMoBIL preprocessed EEG output using bemobil_import_table.csv.
%
% Current workflow:
%   1) check_eeg_streams.m
%   2) import_table.m
%   3) bemobil_import.m
%   4) bemobil_process_all_EEG_data.m
%   5) this quality-check script
%
% This script checks the preprocessing output, not AMICA/final ICA output.
%
% Table-driven control:
%   DoQC = 1  -> check this row
%   DoQC = 0  -> skip this row
%
% If DoQC does not exist yet:
%   - this script creates it automatically.
%   - rows with PreprocessingStatus == "completed" are selected by default.
%   - if PreprocessingStatus does not exist, it falls back to DoPreprocess.

clear; clc; close all;

%% Load central paths

run(fullfile(fileparts(mfilename('fullpath')), 'paths.m'));

if ~exist(mappingFile, 'file')
    error('Import table not found:\n%s\nPlease run import_table.m, bemobil_import.m, and preprocessing first.', mappingFile);
end

%% Expected preprocessing result

expectedChannels = 64;
expectedSrate    = 250;

if ~exist('pop_loadset', 'file')
    eeglab;
end

%% Load BeMoBIL configuration

run(fullfile(scriptsFolder, 'bemobil_config_.m'));

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

if ismember('PreprocessingStatus', sourceMap.Properties.VariableNames)
    sourceMap.PreprocessingStatus = string(sourceMap.PreprocessingStatus);
end

if ismember('PreprocessedSetPath', sourceMap.Properties.VariableNames)
    sourceMap.PreprocessedSetPath = string(sourceMap.PreprocessedSetPath);
end

if ismember('EEGStreamName', sourceMap.Properties.VariableNames)
    sourceMap.EEGStreamName = string(sourceMap.EEGStreamName);
end

%% Create or read DoQC

if ~ismember('DoQC', sourceMap.Properties.VariableNames)

    sourceMap.DoQC = zeros(height(sourceMap), 1);

    if ismember('PreprocessingStatus', sourceMap.Properties.VariableNames)

        status = string(sourceMap.PreprocessingStatus);

        % Only rows that successfully produced a preprocessed file are selected.
        sourceMap.DoQC(status == "completed") = 1;

    elseif ismember('DoPreprocess', sourceMap.Properties.VariableNames)

        sourceMap = ensure_numeric_column(sourceMap, 'DoPreprocess');
        sourceMap.DoQC = sourceMap.DoPreprocess;

    else

        % Last fallback: check imported rows.
        sourceMap.DoQC = sourceMap.DoImport;

    end

    writetable(sourceMap, mappingFile);

    fprintf('\nDoQC column was not found.\n');
    fprintf('Created DoQC automatically and saved it to:\n%s\n', mappingFile);
    fprintf('You can manually edit DoQC later:\n');
    fprintf('  DoQC = 1 -> check this row\n');
    fprintf('  DoQC = 0 -> skip this row\n');

else

    sourceMap = ensure_numeric_column(sourceMap, 'DoQC');

end

%% Select rows from table

rowsToCheck = find(sourceMap.DoQC == 1);

if isempty(rowsToCheck)
    error('No rows with DoQC = 1 found in bemobil_import_table.csv.');
end

fprintf('\n============================================================\n');
fprintf('PREPROCESSED EEG QUALITY CHECK STARTED\n');
fprintf('============================================================\n');
fprintf('Selection mode: table-driven\n');
fprintf('Rows with DoQC = 1: %d\n', length(rowsToCheck));
fprintf('Import table:\n%s\n', mappingFile);
fprintf('============================================================\n\n');

%% Check loop

for rr = 1:length(rowsToCheck)

    rowIdx = rowsToCheck(rr);

    bidsSubject = sourceMap.BidsSubject(rowIdx);
    bidsSession = char(sourceMap.BidsSession(rowIdx));

    originalXDFName = char(sourceMap.FileName(rowIdx));
    originalXDFPath = char(sourceMap.XdfPath(rowIdx));

    if isnan(bidsSubject)
        warning('Invalid BidsSubject in row %d. Skipping this row.', rowIdx);

        sourceMap = update_qc_status( ...
            sourceMap, rowIdx, ...
            "failed_invalid_bids_subject", ...
            "BidsSubject is NaN or invalid.", ...
            "", "" ...
        );

        writetable(sourceMap, mappingFile);
        continue;
    end

    %% Resolve processing label

    % Preprocessing script used:
    %   processingSubjectLabel = BidsSession
    %   processingSubjectFolder = sub-BidsSession
    %
    % Example:
    %   BidsSession = Pilot2p1day2sesExo1Sport
    %   processingSubjectFolder = sub-Pilot2p1day2sesExo1Sport

    if ismember('ProcessingSubjectLabel', sourceMap.Properties.VariableNames) && ...
            ~ismissing(string(sourceMap.ProcessingSubjectLabel(rowIdx))) && ...
            strlength(strtrim(string(sourceMap.ProcessingSubjectLabel(rowIdx)))) > 0

        processingSubjectLabel = char(sourceMap.ProcessingSubjectLabel(rowIdx));

    else

        processingSubjectLabel = char(make_bids_label(string(bidsSession)));

    end

    processingSubjectFolder = ['sub-' processingSubjectLabel];

    %% Resolve preprocessed .set path

    preprocessedSetPath = "";

    if ismember('PreprocessedSetPath', sourceMap.Properties.VariableNames)

        candidatePath = string(sourceMap.PreprocessedSetPath(rowIdx));

        if ~ismissing(candidatePath) && strlength(strtrim(candidatePath)) > 0
            preprocessedSetPath = candidatePath;
        end

    end

    if strlength(preprocessedSetPath) == 0

        % Fallback: reconstruct the expected path from BeMoBIL config.
        preprocessedSetPath = string(fullfile( ...
            bemobil_config.study_folder, ...
            bemobil_config.EEG_preprocessing_data_folder, ...
            processingSubjectFolder, ...
            [processingSubjectFolder '_' bemobil_config.preprocessed_filename] ...
        ));

    end

    preprocessedSetPath = char(preprocessedSetPath);

    [preprocFolder, setFilenameNoExt, setExt] = fileparts(preprocessedSetPath);
    setFilename = [setFilenameNoExt setExt];

    fprintf('\n\n============================================================\n');
    fprintf('CHECKING FILE %d / %d\n', rr, length(rowsToCheck));
    fprintf('============================================================\n');
    fprintf('Table row: %d\n', rowIdx);
    fprintf('Original XDF name:\n%s\n\n', originalXDFName);
    fprintf('Original XDF path:\n%s\n\n', originalXDFPath);
    fprintf('Imported BIDS subject:\nsub-%d\n', bidsSubject);
    fprintf('Imported BIDS session:\n%s\n', bidsSession);
    fprintf('Processing subject label:\n%s\n', processingSubjectLabel);
    fprintf('Processing folder:\n%s\n', processingSubjectFolder);
    fprintf('Preprocessed .set file:\n%s\n', preprocessedSetPath);
    fprintf('============================================================\n\n');

    if ~exist(preprocessedSetPath, 'file')

        warning('Preprocessed .set file not found. Skipping this row:\n%s', preprocessedSetPath);

        sourceMap = update_qc_status( ...
            sourceMap, rowIdx, ...
            "failed_preprocessed_set_not_found", ...
            "Preprocessed .set file was not found.", ...
            preprocessedSetPath, "" ...
        );

        writetable(sourceMap, mappingFile);
        continue;

    end

    %% Prepare quality check output folder

    checkOutputFolder = fullfile( ...
        outputFolder, ...
        'quality_check', ...
        processingSubjectFolder ...
    );

    if ~exist(checkOutputFolder, 'dir')
        mkdir(checkOutputFolder);
    end

    summaryFile = fullfile( ...
        checkOutputFolder, ...
        [processingSubjectFolder '_preprocessed_check_summary.txt'] ...
    );

    locationFig = fullfile( ...
        checkOutputFolder, ...
        [processingSubjectFolder '_channel_locations.png'] ...
    );

    %% Start diary log

    if exist(summaryFile, 'file')
        delete(summaryFile);
    end

    diary(summaryFile);

    fprintf('============================================================\n');
    fprintf('Preprocessed EEG quality check\n');
    fprintf('============================================================\n\n');

    fprintf('Table row: %d\n\n', rowIdx);

    fprintf('Original XDF name:\n%s\n\n', originalXDFName);
    fprintf('Original XDF path:\n%s\n\n', originalXDFPath);

    fprintf('Imported BIDS subject:\nsub-%d\n', bidsSubject);
    fprintf('Imported BIDS session:\n%s\n', bidsSession);
    fprintf('Processing subject label:\n%s\n', processingSubjectLabel);
    fprintf('Processing folder:\n%s\n\n', processingSubjectFolder);

    fprintf('Input preprocessed file:\n%s\n\n', preprocessedSetPath);
    fprintf('Quality check output folder:\n%s\n\n', checkOutputFolder);

    %% Load EEG

    try

        EEG = pop_loadset( ...
            'filename', setFilename, ...
            'filepath', preprocFolder ...
        );

        EEG = eeg_checkset(EEG);

    catch ME

        fprintf('\nERROR while loading EEG:\n%s\n', ME.message);
        diary off;

        sourceMap = update_qc_status( ...
            sourceMap, rowIdx, ...
            "failed_load_preprocessed_set", ...
            string(ME.message), ...
            summaryFile, "" ...
        );

        writetable(sourceMap, mappingFile);
        continue;

    end

    %% Basic information

    fprintf('============================================================\n');
    fprintf('Basic EEG information\n');
    fprintf('============================================================\n');

    fprintf('Channels: %d\n', EEG.nbchan);
    fprintf('Sampling rate: %.2f Hz\n', EEG.srate);
    fprintf('Samples: %d\n', EEG.pnts);
    fprintf('Duration: %.2f seconds\n', EEG.pnts / EEG.srate);
    fprintf('Events: %d\n', length(EEG.event));

    channelLabels = {EEG.chanlocs.labels}';

    %% Source information check

    fprintf('\n============================================================\n');
    fprintf('Source information stored in EEG.etc\n');
    fprintf('============================================================\n');

    if isfield(EEG, 'etc')

        if isfield(EEG.etc, 'source_original_xdf_name')
            fprintf('source_original_xdf_name:\n%s\n', EEG.etc.source_original_xdf_name);
        else
            fprintf('CHECK: EEG.etc.source_original_xdf_name does not exist.\n');
        end

        if isfield(EEG.etc, 'source_original_xdf_path')
            fprintf('source_original_xdf_path:\n%s\n', EEG.etc.source_original_xdf_path);
        else
            fprintf('CHECK: EEG.etc.source_original_xdf_path does not exist.\n');
        end

        if isfield(EEG.etc, 'real_bids_subject')
            fprintf('real_bids_subject:\n%d\n', EEG.etc.real_bids_subject);
        elseif isfield(EEG.etc, 'real_subject_label')
            fprintf('real_subject_label:\n%s\n', EEG.etc.real_subject_label);
        else
            fprintf('CHECK: neither EEG.etc.real_bids_subject nor EEG.etc.real_subject_label exists.\n');
        end

        if isfield(EEG.etc, 'session_label')
            fprintf('session_label:\n%s\n', EEG.etc.session_label);
        else
            fprintf('CHECK: EEG.etc.session_label does not exist.\n');
        end

        if isfield(EEG.etc, 'processing_subject_label')
            fprintf('processing_subject_label:\n%s\n', EEG.etc.processing_subject_label);
        else
            fprintf('CHECK: EEG.etc.processing_subject_label does not exist.\n');
        end

        if isfield(EEG.etc, 'source_eeg_stream_name')
            fprintf('source_eeg_stream_name:\n%s\n', EEG.etc.source_eeg_stream_name);
        else
            fprintf('CHECK: EEG.etc.source_eeg_stream_name does not exist.\n');
        end

    else

        fprintf('CHECK: EEG.etc does not exist.\n');

    end

    %% ACC channel check

    fprintf('\n============================================================\n');
    fprintf('ACC channel check\n');
    fprintf('============================================================\n');

    accKeywords = {'ACC_X', 'ACC_Y', 'ACC_Z'};
    hasACC = false(size(accKeywords));

    for i = 1:length(accKeywords)
        hasACC(i) = any(contains(channelLabels, accKeywords{i}));
    end

    if any(hasACC)
        fprintf('CHECK: Some ACC channels still exist:\n');
        disp(accKeywords(hasACC)');
    else
        fprintf('OK: ACC_X / ACC_Y / ACC_Z channels were removed.\n');
    end

    %% Channel location check

    fprintf('\n============================================================\n');
    fprintf('Channel location check\n');
    fprintf('============================================================\n');

    hasLoc = arrayfun(@(c) ...
        isfield(c, 'X') && ~isempty(c.X) && ~isnan(c.X), ...
        EEG.chanlocs);

    fprintf('Channels with locations: %d / %d\n', sum(hasLoc), EEG.nbchan);

    if sum(hasLoc) == EEG.nbchan
        fprintf('OK: All EEG channels have locations.\n');
    else
        fprintf('CHECK: Some EEG channels do not have locations.\n');

        missingLocLabels = {EEG.chanlocs(~hasLoc).labels}';
        fprintf('Channels without locations:\n');
        disp(missingLocLabels);
    end

    %% Event check

    fprintf('\n============================================================\n');
    fprintf('Event check\n');
    fprintf('============================================================\n');

    if isempty(EEG.event)
        fprintf('NOTE: EEG.event is empty.\n');
        fprintf('This is acceptable for the current basic preprocessing test.\n');
        fprintf('However, gait-event-aligned PSD/ERSP still requires gait events later.\n');
    else
        fprintf('OK: Events exist. Number of events: %d\n', length(EEG.event));
    end

    %% Existing BeMoBIL preprocessing figures check

    fprintf('\n============================================================\n');
    fprintf('Existing BeMoBIL preprocessing figures\n');
    fprintf('============================================================\n');

    expectedFigures = { ...
        [processingSubjectFolder '_raw.png'], ...
        [processingSubjectFolder '_bad_channels_detection.png'], ...
        [processingSubjectFolder '_bad_channels.png'], ...
        [processingSubjectFolder '_interpolated_channels.png'] ...
    };

    for i = 1:length(expectedFigures)
        figPath = fullfile(preprocFolder, expectedFigures{i});

        if exist(figPath, 'file')
            fprintf('FOUND: %s\n', figPath);
        else
            fprintf('MISSING: %s\n', figPath);
        end
    end

    zaplineFiles = dir(fullfile(preprocFolder, '*zapline*.png'));

    if isempty(zaplineFiles)
        fprintf('MISSING: No ZapLine PNG figure found.\n');
    else
        fprintf('FOUND ZapLine figure(s):\n');
        for i = 1:length(zaplineFiles)
            fprintf('%s\n', fullfile(zaplineFiles(i).folder, zaplineFiles(i).name));
        end
    end

    %% Save channel location figure

    fprintf('\n============================================================\n');
    fprintf('Saving electrode location plot\n');
    fprintf('============================================================\n');

    try

        fig1 = figure('Color', 'w', 'Visible', 'off');

        topoplot([], EEG.chanlocs, ...
            'style', 'blank', ...
            'electrodes', 'labelpoint');

        title(['EEG channel locations: ' processingSubjectFolder], 'Interpreter', 'none');

        saveas(fig1, locationFig);

        fprintf('Saved:\n%s\n', locationFig);

        close(fig1);

    catch ME

        fprintf('CHECK: Could not save channel location figure.\n');
        fprintf('Reason:\n%s\n', ME.message);
        locationFig = "";

    end

    %% Final conclusion

    fprintf('\n============================================================\n');
    fprintf('Final automatic check conclusion\n');
    fprintf('============================================================\n');

    if EEG.nbchan == expectedChannels
        fprintf('OK: Channel number is %d.\n', expectedChannels);
        channelOK = true;
    else
        fprintf('CHECK: Channel number is not %d. Current channel number: %d\n', expectedChannels, EEG.nbchan);
        channelOK = false;
    end

    if abs(EEG.srate - expectedSrate) < 0.001
        fprintf('OK: Sampling rate is %.0f Hz.\n', expectedSrate);
        srateOK = true;
    else
        fprintf('CHECK: Sampling rate is not %.0f Hz. Current sampling rate: %.2f Hz\n', expectedSrate, EEG.srate);
        srateOK = false;
    end

    if ~any(hasACC)
        fprintf('OK: ACC channels were removed.\n');
        accOK = true;
    else
        fprintf('CHECK: ACC channels still exist.\n');
        accOK = false;
    end

    if sum(hasLoc) == EEG.nbchan
        fprintf('OK: Channel locations are complete.\n');
        locOK = true;
    else
        fprintf('CHECK: Channel locations are incomplete.\n');
        locOK = false;
    end

    if isempty(EEG.event)
        fprintf('NOTE: Events are empty.\n');
    else
        fprintf('OK: Events exist.\n');
    end

    fprintf('\nCheck finished.\n');

    diary off;

    %% Update import table with quality check status

    if channelOK && srateOK && accOK && locOK

        qcStatus = "passed_basic_checks";
        qcNotes  = "Events may still be empty; this is expected for current preprocessing test.";

    else

        qcStatus = "check_required";
        qcNotes  = "One or more basic checks failed. See summary file.";

    end

    sourceMap = update_qc_status( ...
        sourceMap, rowIdx, ...
        qcStatus, ...
        qcNotes, ...
        summaryFile, locationFig ...
    );

    writetable(sourceMap, mappingFile);

    fprintf('\n============================================================\n');
    fprintf('CHECK FINISHED FOR THIS FILE\n');
    fprintf('Summary saved to:\n%s\n', summaryFile);
    fprintf('Channel location figure saved to:\n%s\n', locationFig);
    fprintf('Import table updated:\n%s\n', mappingFile);
    fprintf('============================================================\n');

end

fprintf('\n\n============================================================\n');
fprintf('ALL SELECTED PREPROCESSING QC FINISHED\n');
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

function T = update_qc_status(T, rowIdx, qcStatus, qcNotes, summaryFile, locationFig)

    T = ensure_string_column(T, 'PreprocessingQCStatus');
    T = ensure_string_column(T, 'PreprocessingQCDate');
    T = ensure_string_column(T, 'PreprocessingQCSummaryPath');
    T = ensure_string_column(T, 'PreprocessingQCFigurePath');
    T = ensure_string_column(T, 'PreprocessingQCNotes');

    T.PreprocessingQCStatus(rowIdx) = string(qcStatus);
    T.PreprocessingQCNotes(rowIdx) = string(qcNotes);
    T.PreprocessingQCSummaryPath(rowIdx) = string(summaryFile);
    T.PreprocessingQCFigurePath(rowIdx) = string(locationFig);
    T.PreprocessingQCDate(rowIdx) = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

end