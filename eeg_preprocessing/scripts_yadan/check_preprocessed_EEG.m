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
%
% Table-driven control:
%   DoQC = 1  -> check this row
%   DoQC = 0  -> skip this row
%
% Default behavior:
%   DoQC is reset from PreprocessingStatus == "completed".
%
% Important:
%   This script checks preprocessed raw EEG output.

clear; clc; close all;

% Keep figures hidden during QC.
set(0, 'DefaultFigureVisible', 'off');
set(groot, 'DefaultFigureVisible', 'off');

%% ========================================================================
%  LOAD CENTRAL PATHS
%  ========================================================================

run(fullfile(fileparts(mfilename('fullpath')), 'paths.m'));

if ~exist(mappingFile, 'file')
    error('Import table not found:\n%s\nPlease run import_table.m, bemobil_import.m, and preprocessing first.', mappingFile);
end

%% ========================================================================
%  QC SETTINGS
%  ========================================================================

expectedChannels = 64;
expectedSrate    = 250;
rankSampleLimit  = 10000;

% Quantitative residual line-noise review. The value is the 50 Hz band
% power relative to neighboring bands. Values above this threshold require
% review even if ZapLine metadata exists.
lineNoiseFrequencyHz = 50;
maxLineNoisePeakDb   = 8;
maxInterpolatedChannelFraction = 0.20;

% If true:
%   DoQC will be overwritten from PreprocessingStatus == "completed".
%
% Recommended after a new preprocessing run.
%
% Later, if you want to manually edit DoQC in the CSV,
% set this to false.
reset_DoQC_from_PreprocessingStatus = false;

%% ========================================================================
%  INITIALIZE EEGLAB
%  ========================================================================

if ~exist('pop_loadset', 'file')
    eeglab nogui;
end

hide_all_figures();

%% ========================================================================
%  LOAD BEMOBIL CONFIGURATION
%  ========================================================================

run(fullfile(fileparts(mfilename('fullpath')), 'bemobil_config_.m'));

hide_all_figures();

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
    'PreprocessedSetPath', ...
    'PreprocessingInputSignature' ...
};

for c = 1:length(requiredColumns)
    if ~ismember(requiredColumns{c}, sourceMap.Properties.VariableNames)
        error(['Import table is missing required column: %s\n' ...
               'Please run bemobil_process_all_EEG_data.m first.'], ...
               requiredColumns{c});
    end
end

%% ========================================================================
%  NORMALIZE IMPORTANT COLUMNS
%  ========================================================================

sourceMap = ensure_numeric_column(sourceMap, 'DoImport');
sourceMap = ensure_numeric_column(sourceMap, 'BidsSubject');

sourceMap.XdfPath             = string(sourceMap.XdfPath);
sourceMap.FileName            = string(sourceMap.FileName);
sourceMap.BidsSession         = string(sourceMap.BidsSession);
sourceMap.PreprocessingStatus = string(sourceMap.PreprocessingStatus);
sourceMap.PreprocessedSetPath = string(sourceMap.PreprocessedSetPath);
sourceMap.PreprocessingInputSignature = string(sourceMap.PreprocessingInputSignature);

sourceMap.XdfPath(ismissing(sourceMap.XdfPath)) = "";
sourceMap.FileName(ismissing(sourceMap.FileName)) = "";
sourceMap.BidsSession(ismissing(sourceMap.BidsSession)) = "";
sourceMap.PreprocessingStatus(ismissing(sourceMap.PreprocessingStatus)) = "";
sourceMap.PreprocessedSetPath(ismissing(sourceMap.PreprocessedSetPath)) = "";
sourceMap.PreprocessingInputSignature(ismissing(sourceMap.PreprocessingInputSignature)) = "";

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
%  CREATE OR RESET DOQC
%  ========================================================================

if ~ismember('DoQC', sourceMap.Properties.VariableNames)

    sourceMap.DoQC = zeros(height(sourceMap), 1);

    status = string(sourceMap.PreprocessingStatus);
    status(ismissing(status)) = "";

    sourceMap.DoQC(status == "completed") = 1;

    writetable(sourceMap, mappingFile);

    fprintf('\nDoQC column was not found.\n');
    fprintf('Created DoQC from PreprocessingStatus == "completed" and saved it to:\n%s\n', mappingFile);
    fprintf('You can manually edit DoQC later:\n');
    fprintf('  DoQC = 1 -> check this row\n');
    fprintf('  DoQC = 0 -> skip this row\n');

else

    sourceMap = ensure_numeric_column(sourceMap, 'DoQC');
    status = string(sourceMap.PreprocessingStatus);
    status(ismissing(status)) = "";

    if reset_DoQC_from_PreprocessingStatus

        sourceMap.DoQC = zeros(height(sourceMap), 1);

        sourceMap.DoQC(status == "completed") = 1;

        writetable(sourceMap, mappingFile);

        fprintf('\nDoQC column already existed.\n');
        fprintf('Reset DoQC from PreprocessingStatus == "completed" because reset_DoQC_from_PreprocessingStatus = true.\n');
        fprintf('Updated import table saved to:\n%s\n', mappingFile);

    else

        missingDoQC = isnan(sourceMap.DoQC);
        sourceMap.DoQC(missingDoQC) = 0;
        sourceMap.DoQC(missingDoQC & status == "completed") = 1;
        writetable(sourceMap, mappingFile);

        fprintf('\nDoQC column already existed.\n');
        fprintf('Preserved explicit DoQC values and filled only missing values from PreprocessingStatus.\n');

    end

end

%% ========================================================================
%  SELECT ROWS TO CHECK
%  ========================================================================

sourceMap = ensure_numeric_column(sourceMap, 'DoQC');

candidateRows = find(sourceMap.DoQC == 1);

if isempty(candidateRows)
    error('No rows with DoQC = 1 found in bemobil_import_table.csv.');
end

hasPreprocessedPath = strlength(strtrim(sourceMap.PreprocessedSetPath)) > 0;
completedRows = sourceMap.PreprocessingStatus == "completed";

validRows = candidateRows(hasPreprocessedPath(candidateRows) & completedRows(candidateRows));

if isempty(validRows)

    fprintf('\nRows with DoQC = 1 exist, but none have PreprocessingStatus == completed and non-empty PreprocessedSetPath.\n');
    fprintf('Problem rows:\n');
    disp(sourceMap(candidateRows, {'FileName', 'BidsSubject', 'BidsSession', ...
                                   'DoImport', 'DoQC', ...
                                   'PreprocessingStatus', 'PreprocessedSetPath'}));

    error('No valid rows for preprocessing QC.');

end

% Safety: avoid checking the same preprocessed file more than once.
preprocessedPathsForValidRows = sourceMap.PreprocessedSetPath(validRows);
[~, uniqueIdx] = unique(preprocessedPathsForValidRows, 'stable');
rowsToCheck = validRows(uniqueIdx);

fprintf('\n============================================================\n');
fprintf('PREPROCESSED EEG QUALITY CHECK STARTED\n');
fprintf('============================================================\n');
fprintf('Selection mode: table-driven preprocessing-QC\n');
fprintf('Rows with DoQC = 1: %d\n', length(candidateRows));
fprintf('Rows with completed preprocessing and PreprocessedSetPath: %d\n', length(validRows));
fprintf('Unique preprocessed .set files to check: %d\n', length(rowsToCheck));
fprintf('Import table:\n%s\n', mappingFile);
fprintf('============================================================\n\n');

fprintf('Rows selected for QC:\n');
disp(sourceMap(rowsToCheck, {'FileName', 'BidsSubject', 'BidsSession', ...
                             'PreprocessingStatus', 'PreprocessedSetPath'}));

hide_all_figures();

%% ========================================================================
%  CHECK LOOP
%  ========================================================================

for rr = 1:length(rowsToCheck)

    hide_all_figures();

    rowIdx = rowsToCheck(rr);
    sessionRows = session_peer_rows(sourceMap, rowIdx);

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
    %  RESOLVE PREPROCESSED .SET PATH
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

    %% --------------------------------------------------------------------
    %  PREPARE QUALITY CHECK OUTPUT FOLDER
    %  --------------------------------------------------------------------

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

    %% --------------------------------------------------------------------
    %  START DIARY LOG
    %  --------------------------------------------------------------------

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

    if ismember('RawSetPath', sourceMap.Properties.VariableNames)
        fprintf('RawSetPath:\n%s\n\n', char(sourceMap.RawSetPath(rowIdx)));
    end

    if ismember('RawSetStatus', sourceMap.Properties.VariableNames)
        fprintf('RawSetStatus:\n%s\n\n', char(sourceMap.RawSetStatus(rowIdx)));
    end

    fprintf('Input preprocessed file:\n%s\n\n', preprocessedSetPath);
    fprintf('Quality check output folder:\n%s\n\n', checkOutputFolder);

    %% --------------------------------------------------------------------
    %  LOAD EEG
    %  --------------------------------------------------------------------

    try

        hide_all_figures();

        EEG = pop_loadset( ...
            'filename', setFilename, ...
            'filepath', preprocFolder ...
        );

        EEG = eeg_checkset(EEG);

        hide_all_figures();

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

    %% --------------------------------------------------------------------
    %  BASIC INFORMATION
    %  --------------------------------------------------------------------

    fprintf('============================================================\n');
    fprintf('Basic EEG information\n');
    fprintf('============================================================\n');

    fprintf('Channels: %d\n', EEG.nbchan);
    fprintf('Sampling rate: %.2f Hz\n', EEG.srate);
    fprintf('Samples: %d\n', EEG.pnts);
    fprintf('Duration: %.2f seconds\n', EEG.pnts / EEG.srate);
    fprintf('Events: %d\n', length(EEG.event));

    channelLabels = {EEG.chanlocs.labels}';
    dataFiniteOK = check_data_finite_blockwise(EEG.data);
    durationOK = EEG.pnts > 1 && (EEG.pnts - 1) / EEG.srate >= 120;
    labelsUniqueOK = numel(channelLabels) == numel(unique(string(channelLabels)));
    labelsNonemptyOK = all(strlength(strtrim(string(channelLabels))) > 0);

    expectedPreprocessingSignature = sourceMap.PreprocessingInputSignature(rowIdx);
    [provenanceOK, provenanceNotes] = check_preprocessing_provenance( ...
        EEG, expectedPreprocessingSignature, bidsSubject, bidsSession, ...
        processingSubjectLabel);

    rankEstimate = estimate_data_rank_sampled(EEG.data, rankSampleLimit);
    [rankMetadataValue, rankMetadataValid] = get_rank_metadata(EEG);
    rankOK = rankMetadataValid && ~isnan(rankEstimate) && ...
        abs(rankMetadataValue - rankEstimate) <= 2;

    lineNoisePeakDb = estimate_line_noise_peak_db( ...
        EEG.data, EEG.srate, lineNoiseFrequencyHz);
    lineNoiseOK = ~isnan(lineNoisePeakDb) && ...
        lineNoisePeakDb <= maxLineNoisePeakDb;

    hasZaplineMetadata = isfield(EEG, 'etc') && isfield(EEG.etc, 'zapline');
    hasChannelRejectionMetadata = isfield(EEG, 'etc') && ...
        isfield(EEG.etc, 'channel_rejection');
    hasInterpolationMetadata = isfield(EEG, 'etc') && ...
        isfield(EEG.etc, 'interpolated_channels');
    hasAverageReferenceMetadata = isfield(EEG, 'etc') && ...
        isfield(EEG.etc, 'bemobil_reref') && ~isempty(EEG.etc.bemobil_reref);
    [interpolatedChannelCount, interpolationCountOK] = ...
        check_interpolated_channel_count( ...
        EEG, maxInterpolatedChannelFraction);

    fprintf('\nProvenance check: %d\n', provenanceOK);
    fprintf('Provenance detail: %s\n', provenanceNotes);
    fprintf('Stored rank metadata: %.6g\n', rankMetadataValue);
    fprintf('Estimated sampled data rank: %.6g\n', rankEstimate);
    fprintf('Rank agreement within tolerance: %d\n', rankOK);
    fprintf('Residual %.1f Hz peak relative to neighboring bands: %.4f dB\n', ...
        lineNoiseFrequencyHz, lineNoisePeakDb);
    fprintf('Residual line-noise check <= %.2f dB: %d\n', ...
        maxLineNoisePeakDb, lineNoiseOK);
    fprintf('Interpolated channels: %.0f\n', interpolatedChannelCount);
    fprintf('Interpolated-channel fraction <= %.2f: %d\n', ...
        maxInterpolatedChannelFraction, interpolationCountOK);

    %% --------------------------------------------------------------------
    %  SOURCE INFORMATION CHECK
    %  --------------------------------------------------------------------

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

        if isfield(EEG.etc, 'event_based_trimming_disabled')
            fprintf('event_based_trimming_disabled:\n%d\n', EEG.etc.event_based_trimming_disabled);
        end

        if isfield(EEG.etc, 'n_events_before_preprocessing')
            fprintf('n_events_before_preprocessing:\n%d\n', EEG.etc.n_events_before_preprocessing);
        end

    else

        fprintf('CHECK: EEG.etc does not exist.\n');

    end

    %% --------------------------------------------------------------------
    %  ACC CHANNEL CHECK
    %  --------------------------------------------------------------------

    fprintf('\n============================================================\n');
    fprintf('ACC channel check\n');
    fprintf('============================================================\n');

    accKeywords = {'ACC_X', 'ACC_Y', 'ACC_Z'};
    hasACC = false(size(accKeywords));

    for i = 1:length(accKeywords)
        hasACC(i) = any(contains(channelLabels, accKeywords{i}, 'IgnoreCase', true));
    end

    if any(hasACC)
        fprintf('CHECK: Some ACC channels still exist:\n');
        disp(accKeywords(hasACC)');
    else
        fprintf('OK: ACC_X / ACC_Y / ACC_Z channels were removed.\n');
    end

    %% --------------------------------------------------------------------
    %  CHANNEL LOCATION CHECK
    %  --------------------------------------------------------------------

    fprintf('\n============================================================\n');
    fprintf('Channel location check\n');
    fprintf('============================================================\n');

    hasLoc = arrayfun(@channel_has_valid_xyz, EEG.chanlocs);

    fprintf('Channels with locations: %d / %d\n', sum(hasLoc), EEG.nbchan);

    if sum(hasLoc) == EEG.nbchan
        fprintf('OK: All EEG channels have locations.\n');
    else
        fprintf('CHECK: Some EEG channels do not have locations.\n');

        missingLocLabels = {EEG.chanlocs(~hasLoc).labels}';
        fprintf('Channels without locations:\n');
        disp(missingLocLabels);
    end

    %% --------------------------------------------------------------------
    %  EVENT CHECK
    %  --------------------------------------------------------------------

    fprintf('\n============================================================\n');
    fprintf('Event check\n');
    fprintf('============================================================\n');

    if isempty(EEG.event)
        fprintf('NOTE: EEG.event is empty.\n');
        fprintf('This is acceptable for the current basic preprocessing check.\n');
        fprintf('However, gait-event-aligned PSD/ERSP still requires gait events later.\n');
    else
        fprintf('OK: Events exist. Number of events: %d\n', length(EEG.event));
        fprintf('Note: this preprocessing script intentionally did not trim data based on events.\n');
    end

    sourceMap = ensure_string_column(sourceMap, 'GaitEventStatus');
    sourceMap = ensure_numeric_optional_column(sourceMap, 'PreprocessingQCEventCount');
    sourceMap = ensure_numeric_optional_column(sourceMap, 'AnalysisReady');
    sourceMap.PreprocessingQCEventCount(sessionRows) = numel(EEG.event);
    sourceMap.AnalysisReady(sessionRows) = 0;
    if isempty(EEG.event)
        sourceMap.GaitEventStatus(sessionRows) = "events_missing_not_ready_for_gait_analysis";
    else
        sourceMap.GaitEventStatus(sessionRows) = "events_present_types_not_yet_validated";
    end

    %% --------------------------------------------------------------------
    %  EXISTING BEMOBIL PREPROCESSING FIGURES CHECK
    %  --------------------------------------------------------------------

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

    %% --------------------------------------------------------------------
    %  SAVE CHANNEL LOCATION FIGURE
    %  --------------------------------------------------------------------

    fprintf('\n============================================================\n');
    fprintf('Saving electrode location plot\n');
    fprintf('============================================================\n');

    try

        hide_all_figures();

        fig1 = figure('Color', 'w', 'Visible', 'off');

        topoplot([], EEG.chanlocs, ...
            'style', 'blank', ...
            'electrodes', 'labelpoint');

        title(['EEG channel locations: ' processingSubjectFolder], 'Interpreter', 'none');

        saveas(fig1, locationFig);

        fprintf('Saved:\n%s\n', locationFig);

        close(fig1);
        hide_all_figures();

    catch ME

        fprintf('CHECK: Could not save channel location figure.\n');
        fprintf('Reason:\n%s\n', ME.message);
        locationFig = "";

        hide_all_figures();

    end

    %% --------------------------------------------------------------------
    %  FINAL AUTOMATIC CHECK CONCLUSION
    %  --------------------------------------------------------------------

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

    fprintf('Data finite: %d\n', dataFiniteOK);
    fprintf('Duration >= 120 s: %d\n', durationOK);
    fprintf('Channel labels unique: %d\n', labelsUniqueOK);
    fprintf('Channel labels non-empty: %d\n', labelsNonemptyOK);
    fprintf('Preprocessing provenance verified: %d\n', provenanceOK);
    fprintf('Rank metadata agrees with sampled data rank: %d\n', rankOK);
    fprintf('Residual line-noise check passed: %d\n', lineNoiseOK);
    fprintf('ZapLine metadata present: %d\n', hasZaplineMetadata);
    fprintf('Channel-rejection metadata present: %d\n', hasChannelRejectionMetadata);
    fprintf('Interpolation metadata present: %d\n', hasInterpolationMetadata);
    fprintf('Interpolated-channel count acceptable: %d\n', interpolationCountOK);
    fprintf('Average-reference metadata present: %d\n', hasAverageReferenceMetadata);

    if isempty(EEG.event)
        fprintf('NOTE: Events are empty.\n');
        eventNote = "events_empty";
    else
        fprintf('OK: Events exist.\n');
        eventNote = "events_exist";
    end

    fprintf('\nCheck finished.\n');

    diary off;

    %% --------------------------------------------------------------------
    %  UPDATE IMPORT TABLE WITH QUALITY CHECK STATUS
    %  --------------------------------------------------------------------

    metadataOK = hasZaplineMetadata && hasChannelRejectionMetadata && ...
        hasInterpolationMetadata && hasAverageReferenceMetadata;

    allCheckNames = [ ...
        "channel_count", "sampling_rate", "ACC_removed", "XYZ_locations", ...
        "data_finite", "duration", "labels_unique", "labels_nonempty", ...
        "preprocessing_metadata", "interpolated_channel_count", ...
        "provenance", "rank", "line_noise_residual"];
    allCheckValues = [ ...
        channelOK, srateOK, accOK, locOK, dataFiniteOK, durationOK, ...
        labelsUniqueOK, labelsNonemptyOK, metadataOK, interpolationCountOK, provenanceOK, ...
        rankOK, lineNoiseOK];

    if all(allCheckValues)

        qcStatus = "passed_basic_checks";
        qcNotes  = "Basic preprocessing checks passed. " + eventNote + ".";

    else

        qcStatus = "check_required";
        failedCheckNames = allCheckNames(~allCheckValues);
        qcNotes  = "Failed checks: " + join(failedCheckNames, "; ") + ...
            ". See summary file. " + eventNote + ".";

    end

    metricNames = {'PreprocessingQCDataFinite', 'PreprocessingQCDurationOK', ...
        'PreprocessingQCLabelsUnique', 'PreprocessingQCHasZaplineMetadata', ...
        'PreprocessingQCHasChannelRejectionMetadata', ...
        'PreprocessingQCHasInterpolationMetadata', ...
        'PreprocessingQCHasAverageReferenceMetadata', ...
        'PreprocessingQCLabelsNonempty', ...
        'PreprocessingQCProvenanceOK', ...
        'PreprocessingQCRankOK', ...
        'PreprocessingQCLineNoiseOK', ...
        'PreprocessingQCInterpolationCountOK'};
    metricValues = [dataFiniteOK, durationOK, labelsUniqueOK, ...
        hasZaplineMetadata, hasChannelRejectionMetadata, ...
        hasInterpolationMetadata, hasAverageReferenceMetadata, ...
        labelsNonemptyOK, provenanceOK, rankOK, lineNoiseOK, ...
        interpolationCountOK];

    for mi = 1:numel(metricNames)
        sourceMap = ensure_numeric_optional_column(sourceMap, metricNames{mi});
        sourceMap.(metricNames{mi})(sessionRows) = double(metricValues(mi));
    end

    sourceMap = ensure_numeric_optional_column(sourceMap, 'PreprocessingQCRankMetadata');
    sourceMap = ensure_numeric_optional_column(sourceMap, 'PreprocessingQCRankEstimate');
    sourceMap = ensure_numeric_optional_column(sourceMap, 'PreprocessingQCLineNoisePeakDb');
    sourceMap = ensure_numeric_optional_column(sourceMap, 'PreprocessingQCInterpolatedChannelCount');
    sourceMap.PreprocessingQCRankMetadata(sessionRows) = rankMetadataValue;
    sourceMap.PreprocessingQCRankEstimate(sessionRows) = rankEstimate;
    sourceMap.PreprocessingQCLineNoisePeakDb(sessionRows) = lineNoisePeakDb;
    sourceMap.PreprocessingQCInterpolatedChannelCount(sessionRows) = interpolatedChannelCount;

    sourceMap = update_qc_status( ...
        sourceMap, rowIdx, ...
        qcStatus, ...
        qcNotes, ...
        summaryFile, locationFig ...
    );

    writetable(sourceMap, mappingFile);

    hide_all_figures();

    fprintf('\n============================================================\n');
    fprintf('CHECK FINISHED FOR THIS FILE\n');
    fprintf('Summary saved to:\n%s\n', summaryFile);
    fprintf('Channel location figure saved to:\n%s\n', locationFig);
    fprintf('Import table updated:\n%s\n', mappingFile);
    fprintf('============================================================\n');

end

hide_all_figures();

%% ========================================================================
%  FINAL REPORT
%  ========================================================================

fprintf('\n\n============================================================\n');
fprintf('ALL SELECTED PREPROCESSING QC FINISHED\n');
fprintf('============================================================\n');
fprintf('Import table:\n%s\n', mappingFile);

optsFinal = detectImportOptions(mappingFile, ...
    'FileType', 'text', ...
    'Delimiter', ',', ...
    'VariableNamingRule', 'preserve');

sourceMapFinal = readtable(mappingFile, optsFinal);

if ismember('PreprocessingQCStatus', sourceMapFinal.Properties.VariableNames)

    sourceMapFinal.PreprocessingQCStatus = string(sourceMapFinal.PreprocessingQCStatus);
    sourceMapFinal.PreprocessingQCStatus(ismissing(sourceMapFinal.PreprocessingQCStatus)) = "";

    fprintf('\nPreprocessing QC status summary:\n');

    statusNonEmpty = sourceMapFinal.PreprocessingQCStatus(strlength(sourceMapFinal.PreprocessingQCStatus) > 0);
    uniqueStatus = unique(statusNonEmpty, 'stable');

    if isempty(uniqueStatus)
        fprintf('  No preprocessing QC status entries found.\n');
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

function T = update_qc_status(T, rowIdx, qcStatus, qcNotes, summaryFile, locationFig)

    T = ensure_string_column(T, 'PreprocessingQCStatus');
    T = ensure_string_column(T, 'PreprocessingQCDate');
    T = ensure_string_column(T, 'PreprocessingQCSummaryPath');
    T = ensure_string_column(T, 'PreprocessingQCFigurePath');
    T = ensure_string_column(T, 'PreprocessingQCNotes');

    rows = session_peer_rows(T, rowIdx);
    T.PreprocessingQCStatus(rows) = string(qcStatus);
    T.PreprocessingQCNotes(rows) = string(qcNotes);
    T.PreprocessingQCSummaryPath(rows) = string(summaryFile);
    T.PreprocessingQCFigurePath(rows) = string(locationFig);
    T.PreprocessingQCDate(rows) = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

end

function T = ensure_numeric_optional_column(T, columnName)

    if ~ismember(columnName, T.Properties.VariableNames)
        T.(columnName) = nan(height(T), 1);
    elseif ~isnumeric(T.(columnName))
        T.(columnName) = str2double(string(T.(columnName)));
    end

end

function finiteOK = check_data_finite_blockwise(data)

    finiteOK = ~isempty(data);
    if ~finiteOK
        return;
    end

    blockSize = 100000;
    nSamples = size(data, 2);
    for firstSample = 1:blockSize:nSamples
        lastSample = min(nSamples, firstSample + blockSize - 1);
        block = double(data(:, firstSample:lastSample));
        if any(~isfinite(block(:)))
            finiteOK = false;
            return;
        end
    end

end

function tf = channel_has_valid_xyz(chanloc)

    tf = true;
    coordinateNames = {'X', 'Y', 'Z'};

    for k = 1:numel(coordinateNames)
        name = coordinateNames{k};
        if ~isfield(chanloc, name) || isempty(chanloc.(name)) || ...
                ~isnumeric(chanloc.(name)) || ~isscalar(chanloc.(name)) || ...
                ~isfinite(double(chanloc.(name)))
            tf = false;
            return;
        end
    end

end

function [ok, notes] = check_preprocessing_provenance( ...
    EEG, expectedSignature, expectedSubject, expectedSession, expectedProcessingLabel)

    problems = strings(0, 1);
    expectedSignature = string(expectedSignature);

    if strlength(strtrim(expectedSignature)) == 0
        problems(end+1, 1) = "table_preprocessing_signature_missing";
    elseif ~isfield(EEG, 'etc') || ...
            ~isfield(EEG.etc, 'preprocessing_input_signature') || ...
            string(EEG.etc.preprocessing_input_signature) ~= expectedSignature
        problems(end+1, 1) = "preprocessing_signature_mismatch";
    end

    if ~isfield(EEG, 'etc') || ~isfield(EEG.etc, 'real_bids_subject')
        problems(end+1, 1) = "stored_bids_subject_missing";
    else
        storedSubject = scalar_number(EEG.etc.real_bids_subject);
        if isnan(storedSubject) || storedSubject ~= double(expectedSubject)
            problems(end+1, 1) = "stored_bids_subject_mismatch";
        end
    end

    if ~isfield(EEG, 'etc') || ~isfield(EEG.etc, 'session_label') || ...
            string(EEG.etc.session_label) ~= string(expectedSession)
        problems(end+1, 1) = "stored_session_label_mismatch";
    end

    if ~isfield(EEG, 'etc') || ~isfield(EEG.etc, 'processing_subject_label') || ...
            string(EEG.etc.processing_subject_label) ~= string(expectedProcessingLabel)
        problems(end+1, 1) = "stored_processing_label_mismatch";
    end

    ok = isempty(problems);
    if ok
        notes = "OK";
    else
        notes = join(problems, "; ");
    end

end

function value = scalar_number(x)

    value = NaN;
    try
        if isnumeric(x) || islogical(x)
            if isscalar(x)
                value = double(x);
            end
        else
            parsed = str2double(string(x));
            if isscalar(parsed)
                value = parsed;
            end
        end
    catch
        value = NaN;
    end

end

function [rankValue, valid] = get_rank_metadata(EEG)

    rankValue = NaN;
    valid = false;

    if ~isfield(EEG, 'etc') || ~isfield(EEG.etc, 'rank')
        return;
    end

    rankValue = scalar_number(EEG.etc.rank);
    valid = isfinite(rankValue) && rankValue >= 1 && ...
        rankValue <= EEG.nbchan && abs(rankValue - round(rankValue)) < 1e-6;

end

function [count, ok] = check_interpolated_channel_count(EEG, maxFraction)

    count = NaN;
    ok = false;

    if ~isfield(EEG, 'etc') || ~isfield(EEG.etc, 'interpolated_channels')
        return;
    end

    channels = EEG.etc.interpolated_channels;
    if isempty(channels)
        count = 0;
        ok = true;
        return;
    end

    if ~isnumeric(channels) || any(~isfinite(double(channels(:)))) || ...
            any(channels(:) < 1) || any(channels(:) > EEG.nbchan) || ...
            any(abs(double(channels(:)) - round(double(channels(:)))) > 1e-6)
        return;
    end

    count = numel(unique(double(channels(:))));
    ok = count <= floor(double(EEG.nbchan) * maxFraction);

end

function rankEstimate = estimate_data_rank_sampled(data, sampleLimit)

    rankEstimate = NaN;
    try
        data = reshape(data, size(data, 1), []);
        nSamples = size(data, 2);
        if nSamples < 2 || isempty(data)
            return;
        end
        if nSamples > sampleLimit
            sampleIdx = unique(round(linspace(1, nSamples, sampleLimit)));
            data = data(:, sampleIdx);
        end
        rankEstimate = rank(double(data'));
    catch
        rankEstimate = NaN;
    end

end

function peakDb = estimate_line_noise_peak_db(data, srate, targetHz)

    peakDb = NaN;
    try
        if isempty(data) || ~isfinite(srate) || srate <= 0 || ...
                targetHz + 3 >= srate / 2
            return;
        end

        data = reshape(data, size(data, 1), []);
        nAvailable = size(data, 2);
        nSamples = min(nAvailable, max(round(10 * srate), round(60 * srate)));
        if nAvailable < round(10 * srate) || nSamples < 4
            return;
        end

        firstSample = floor((nAvailable - nSamples) / 2) + 1;
        data = double(data(:, firstSample:firstSample + nSamples - 1));
        data = data - mean(data, 2);

        window = 0.5 - 0.5 * cos(2 * pi * (0:nSamples-1) / (nSamples-1));
        spectrum = fft(data .* window, [], 2);
        powerSpectrum = mean(abs(spectrum).^2, 1);
        frequency = (0:nSamples-1) * (srate / nSamples);

        positive = frequency <= srate / 2;
        frequency = frequency(positive);
        powerSpectrum = powerSpectrum(positive);

        targetMask = abs(frequency - targetHz) <= 0.5;
        neighborMask = (frequency >= targetHz - 3 & frequency <= targetHz - 1) | ...
            (frequency >= targetHz + 1 & frequency <= targetHz + 3);

        if ~any(targetMask) || ~any(neighborMask)
            return;
        end

        targetPower = mean(powerSpectrum(targetMask));
        neighborPower = mean(powerSpectrum(neighborMask));
        if targetPower <= 0 || neighborPower <= 0 || ...
                ~isfinite(targetPower) || ~isfinite(neighborPower)
            return;
        end

        peakDb = 10 * log10(targetPower / neighborPower);
    catch
        peakDb = NaN;
    end

end

function rows = session_peer_rows(T, rowIdx)

    rows = rowIdx;
    required = {'BidsSubject', 'BidsSession'};
    if ~all(ismember(required, T.Properties.VariableNames))
        return;
    end

    subjectValues = T.BidsSubject;
    if ~isnumeric(subjectValues)
        subjectValues = str2double(string(subjectValues));
    end
    sessionValues = string(T.BidsSession);
    sessionValues(ismissing(sessionValues)) = "";

    subjectValue = subjectValues(rowIdx);
    sessionValue = sessionValues(rowIdx);
    if isnan(subjectValue) || strlength(strtrim(sessionValue)) == 0
        return;
    end

    mask = subjectValues == subjectValue & sessionValues == sessionValue;
    if ismember('DoImport', T.Properties.VariableNames)
        doImport = T.DoImport;
        if ~isnumeric(doImport)
            doImport = str2double(string(doImport));
        end
        mask = mask & doImport == 1;
    end

    matchedRows = find(mask);
    if ~isempty(matchedRows)
        rows = matchedRows;
    end

end
