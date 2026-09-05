% GOAL
%   Verify the AMICA, ICA, ICLabel, and DIPFIT outputs produced by Step 07
%   before any manual cortical IC decision is made.
% INPUT
%   Updated subject_level_EEG_table.csv from Step 07.
%   AMICA.set, dipfitted.set, preprocessed_and_ICA.set, and
%   cleaned_with_ICA.set for each completed participant/session.
% APPROACH
%   1. Select completed and provenance-verified Step 07 outputs.
%   2. Check cleaned EEG structure, sampling rate, finite data, and rank.
%   3. Check ICA matrices, AMICA metadata/provenance, and bad-sample mask.
%   4. Check ICLabel and DIPFIT dimensions and summary metrics.
%   5. Write ICA-QC status and metrics back to the processing table.
% OUTPUT
%   Updated subject_level_EEG_table.csv
%   output_data/amica_ica_quality_summary.csv
% USED BY
%   step09_update_manual_ic_review.m

clear; clc; close all;

% Step 08 is a batch-QC step, so figures are hidden while it runs.
% IMPORTANT:
% MATLAB/EEGLAB figure visibility is restored to ON at the end of this
% script, including when Step 08 terminates with an error. This is required
% because Step 09 and manual IC inspection are interactive GUI steps.

try

    set(0, 'DefaultFigureVisible', 'off');
    set(groot, 'DefaultFigureVisible', 'off');

    %  LOAD PATHS, CONFIGURATION, AND STEP 08 QC SETTINGS

    runFolder = fileparts(mfilename('fullpath'));
    scriptsRoot = fileparts(runFolder);

    addpath(scriptsRoot, '-begin');
    addpath(fullfile(scriptsRoot, 'config'), '-begin');

    P = project_paths();

    bemobil_config = ...
        config_step05_09_eeg_preprocessing_ica(P);

    mappingFile = P.subjectLevelEEGTableFile;
    outputFolder = P.outputFolder;

    if ~exist(mappingFile, 'file')
        error([ ...
            'Subject-level processing table not found:\n%s\n' ...
            'Run step07_run_amica_dipfit_iclabel.m first.'], ...
            mappingFile);
    end

    expectedChannels = ...
        bemobil_config.icaQC.expectedChannels;

    if isempty(bemobil_config.resample_freq)
        expectedSrate = 500;
    else
        expectedSrate = double(bemobil_config.resample_freq);
    end

    reset_DoICAQC_from_AMICAStatus = ...
        bemobil_config.icaQC.reset_DoICAQC_from_AMICAStatus;

    rankSampleLimit = ...
        bemobil_config.icaQC.rankSampleLimit;

    rvThreshold15 = ...
        bemobil_config.icaQC.rvThreshold15;

    rvThreshold20 = ...
        bemobil_config.icaQC.rvThreshold20;

    maxAMICABadSamplesPercent = ...
        bemobil_config.icaQC.maxAMICABadSamplesPercent;

    %  INITIALIZE EEGLAB

    if ~exist('pop_loadset', 'file')
        eeglab nogui;
    end

    hide_all_figures_local();

    %  READ IMPORT TABLE

    optsImport = detectImportOptions(mappingFile, ...
        'FileType', 'text', ...
        'Delimiter', ',', ...
        'VariableNamingRule', 'preserve');

    sourceMap = readtable(mappingFile, optsImport);

    fprintf('\nLoaded import table:\n%s\n', mappingFile);
    fprintf('Rows in import table: %d\n', height(sourceMap));

    %  CHECK REQUIRED COLUMNS

    requiredColumns = { ...
        'FileName', ...
        'BidsSubject', ...
        'BidsSession', ...
        'AMICAStatus', ...
        'AMICAOutputStatus', ...
        'AMICAInputSignature', ...
        'AMICASetPath', ...
        'DipfittedSetPath', ...
        'PreprocessedICASetPath', ...
        'CleanedICASetPath' ...
    };

    for c = 1:numel(requiredColumns)
        if ~ismember(requiredColumns{c}, sourceMap.Properties.VariableNames)
            error(['Import table is missing required column: %s\n' ...
                   'Please run the latest step07_run_amica_dipfit_iclabel.m first, so AMICA/DIPFIT/output5 paths are written to the table.'], ...
                   requiredColumns{c});
        end
    end

    %  NORMALIZE IMPORTANT COLUMNS

    sourceMap = ensure_numeric_column_local(sourceMap, 'BidsSubject');

    sourceMap.FileName = string(sourceMap.FileName);
    sourceMap.BidsSession = string(sourceMap.BidsSession);
    sourceMap.AMICAStatus = string(sourceMap.AMICAStatus);
    sourceMap.AMICAOutputStatus = string(sourceMap.AMICAOutputStatus);
    sourceMap.AMICAInputSignature = string(sourceMap.AMICAInputSignature);
    sourceMap.AMICASetPath = string(sourceMap.AMICASetPath);
    sourceMap.DipfittedSetPath = string(sourceMap.DipfittedSetPath);
    sourceMap.PreprocessedICASetPath = string(sourceMap.PreprocessedICASetPath);
    sourceMap.CleanedICASetPath = string(sourceMap.CleanedICASetPath);

    sourceMap.FileName(ismissing(sourceMap.FileName)) = "";
    sourceMap.BidsSession(ismissing(sourceMap.BidsSession)) = "";
    sourceMap.AMICAStatus(ismissing(sourceMap.AMICAStatus)) = "";
    sourceMap.AMICAOutputStatus(ismissing(sourceMap.AMICAOutputStatus)) = "";
    sourceMap.AMICAInputSignature(ismissing(sourceMap.AMICAInputSignature)) = "";
    sourceMap.AMICASetPath(ismissing(sourceMap.AMICASetPath)) = "";
    sourceMap.DipfittedSetPath(ismissing(sourceMap.DipfittedSetPath)) = "";
    sourceMap.PreprocessedICASetPath(ismissing(sourceMap.PreprocessedICASetPath)) = "";
    sourceMap.CleanedICASetPath(ismissing(sourceMap.CleanedICASetPath)) = "";

    if ismember('ProcessingSubjectLabel', sourceMap.Properties.VariableNames)
        sourceMap.ProcessingSubjectLabel = string(sourceMap.ProcessingSubjectLabel);
        sourceMap.ProcessingSubjectLabel(ismissing(sourceMap.ProcessingSubjectLabel)) = "";
    end

    if ismember('ProcessingSubjectFolder', sourceMap.Properties.VariableNames)
        sourceMap.ProcessingSubjectFolder = string(sourceMap.ProcessingSubjectFolder);
        sourceMap.ProcessingSubjectFolder(ismissing(sourceMap.ProcessingSubjectFolder)) = "";
    end

    %  CREATE OR RESET DOICAQC

    readyForICAQC = ...
        sourceMap.AMICAStatus == "completed" & ...
        sourceMap.AMICAOutputStatus == "complete_outputs_verified" & ...
        strlength(strtrim(sourceMap.AMICAInputSignature)) > 0 & ...
        strlength(strtrim(sourceMap.AMICASetPath)) > 0 & ...
        strlength(strtrim(sourceMap.DipfittedSetPath)) > 0 & ...
        strlength(strtrim(sourceMap.PreprocessedICASetPath)) > 0 & ...
        strlength(strtrim(sourceMap.CleanedICASetPath)) > 0;

    if ~ismember('DoICAQC', sourceMap.Properties.VariableNames)

        sourceMap.DoICAQC = zeros(height(sourceMap), 1);
        sourceMap.DoICAQC(readyForICAQC) = 1;

        writetable(sourceMap, mappingFile);

        fprintf('\nDoICAQC column was not found. Created it from completed and fully verified AMICA outputs.\n');
        fprintf('Updated import table saved to:\n%s\n', mappingFile);

    else

        sourceMap = ensure_numeric_column_local(sourceMap, 'DoICAQC');

        if reset_DoICAQC_from_AMICAStatus
            sourceMap.DoICAQC = zeros(height(sourceMap), 1);
            sourceMap.DoICAQC(readyForICAQC) = 1;
            writetable(sourceMap, mappingFile);
            fprintf('\nReset DoICAQC from AMICAStatus == completed and AMICAOutputStatus == complete_outputs_verified.\n');
        else
            missingDoICAQC = isnan(sourceMap.DoICAQC);
            sourceMap.DoICAQC(missingDoICAQC) = 0;
            sourceMap.DoICAQC(missingDoICAQC & readyForICAQC) = 1;
            writetable(sourceMap, mappingFile);
            fprintf('\nPreserved explicit DoICAQC values and filled only missing values from verified AMICA outputs.\n');
        end

    end

    %  PREPARE OUTPUT COLUMNS

    sourceMap = ensure_string_column_local(sourceMap, 'ICAQCStatus');
    sourceMap = ensure_string_column_local(sourceMap, 'ICAQCNotes');
    sourceMap = ensure_string_column_local(sourceMap, 'ICAQCDate');
    sourceMap = ensure_string_column_local(sourceMap, 'ICAQCSetPath');

    numericColumns = { ...
        'ICAQCChannels', ...
        'ICAQCSrate', ...
        'ICAQCSamples', ...
        'ICAQCDurationSec', ...
        'ICAQCRankEstimate', ...
        'ICAQCNICs', ...
        'ICAQCHasAMICASet', ...
        'ICAQCHasDipfittedSet', ...
        'ICAQCHasPreprocessedICASet', ...
        'ICAQCHasCleanedICASet', ...
        'ICAQCHasICAWeights', ...
        'ICAQCHasICLabel', ...
        'ICAQCHasDIPFIT', ...
        'ICAQCICLabelDimOK', ...
        'ICAQCDIPFITDimOK', ...
        'ICAQCDipfittedHasDIPFIT', ...
        'ICAQCPreprocessedCleanedCompatible', ...
        'ICAQCICAMatrixDimOK', ...
        'ICAQCICAValuesFinite', ...
        'ICAQCAMICAPreprocessedEquivalent', ...
        'ICAQCDipfittedPreprocessedEquivalent', ...
        'ICAQCHasAMICAMetadata', ...
        'ICAQCAMICAInputSignatureOK', ...
        'ICAQCHasBadSampleMask', ...
        'ICAQCBadSamples', ...
        'ICAQCBadSamplesPercent', ...
        'ICAQCBrainICs', ...
        'ICAQCBrainICsP050', ...
        'ICAQCBrainICsP075', ...
        'ICAQCEyeICs', ...
        'ICAQCMuscleICs', ...
        'ICAQCHeartICs', ...
        'ICAQCLineNoiseICs', ...
        'ICAQCChannelNoiseICs', ...
        'ICAQCOtherICs', ...
        'ICAQCDipfitRVMedian', ...
        'ICAQCDipfitRVBelow15', ...
        'ICAQCDipfitRVBelow20' ...
    };

    for c = 1:numel(numericColumns)
        sourceMap = ensure_numeric_nan_column_local(sourceMap, numericColumns{c});
    end

    %  SELECT ROWS TO CHECK

    sourceMap = ensure_numeric_column_local(sourceMap, 'DoICAQC');

    candidateRows = find(sourceMap.DoICAQC == 1);

    if isempty(candidateRows)
        error('No rows with DoICAQC = 1 found in the subject-level processing table.');
    end

    hasAllOutputPaths = ...
        strlength(strtrim(sourceMap.AMICASetPath)) > 0 & ...
        strlength(strtrim(sourceMap.DipfittedSetPath)) > 0 & ...
        strlength(strtrim(sourceMap.PreprocessedICASetPath)) > 0 & ...
        strlength(strtrim(sourceMap.CleanedICASetPath)) > 0;

    completedAndVerifiedAMICA = ...
        sourceMap.AMICAStatus == "completed" & ...
        sourceMap.AMICAOutputStatus == "complete_outputs_verified" & ...
        strlength(strtrim(sourceMap.AMICAInputSignature)) > 0;

    validRows = candidateRows(hasAllOutputPaths(candidateRows) & completedAndVerifiedAMICA(candidateRows));

    if isempty(validRows)
        fprintf('\nRows with DoICAQC = 1 exist, but none have completed and fully verified AMICA outputs.\n');
        disp(sourceMap(candidateRows, intersect({'FileName', 'BidsSubject', 'BidsSession', ...
            'AMICAStatus', 'AMICAOutputStatus', 'DoICAQC', ...
            'AMICASetPath', 'DipfittedSetPath', 'PreprocessedICASetPath', 'CleanedICASetPath'}, ...
            sourceMap.Properties.VariableNames, 'stable')));
        error('No valid rows for ICA QC.');
    end

    % Safety: avoid checking the same cleaned ICA file more than once.
    cleanedPathsForValidRows = sourceMap.CleanedICASetPath(validRows);
    [~, uniqueIdx] = unique(cleanedPathsForValidRows, 'stable');
    rowsToCheck = validRows(uniqueIdx);

    fprintf('\n============================================================\n');
    fprintf('AMICA / ICA QUALITY CHECK STARTED\n');
    fprintf('============================================================\n');
    fprintf('Rows with DoICAQC = 1: %d\n', numel(candidateRows));
    fprintf('Rows with completed and verified AMICA outputs: %d\n', numel(validRows));
    fprintf('Unique cleaned ICA .set files to check: %d\n', numel(rowsToCheck));
    fprintf('Import table:\n%s\n', mappingFile);
    fprintf('============================================================\n\n');

    fprintf('Rows selected for ICA QC:\n');
    disp(sourceMap(rowsToCheck, intersect({'FileName', 'BidsSubject', 'BidsSession', ...
        'AMICAStatus', 'AMICAOutputStatus', 'CleanedICASetPath'}, ...
        sourceMap.Properties.VariableNames, 'stable')));

    hide_all_figures_local();

    %  CHECK LOOP

    for rr = 1:numel(rowsToCheck)

        hide_all_figures_local();

        rowIdx = rowsToCheck(rr);
        sessionRows = session_peer_rows_local(sourceMap, rowIdx);

        cleanedSetPath = char(sourceMap.CleanedICASetPath(rowIdx));
        preprocessedICASetPath = char(sourceMap.PreprocessedICASetPath(rowIdx));
        amicaSetPath = char(sourceMap.AMICASetPath(rowIdx));
        dipfittedSetPath = char(sourceMap.DipfittedSetPath(rowIdx));
        expectedAMICAInputSignature = ...
            string(sourceMap.AMICAInputSignature(rowIdx));

        fprintf('\n\n============================================================\n');
        fprintf('ICA QC FILE %d / %d\n', rr, numel(rowsToCheck));
        fprintf('FileName: %s\n', string(sourceMap.FileName(rowIdx)));
        fprintf('BidsSubject: %g\n', sourceMap.BidsSubject(rowIdx));
        fprintf('BidsSession: %s\n', string(sourceMap.BidsSession(rowIdx)));
        fprintf('AMICASetPath:\n%s\n', amicaSetPath);
        fprintf('DipfittedSetPath:\n%s\n', dipfittedSetPath);
        fprintf('PreprocessedICASetPath:\n%s\n', preprocessedICASetPath);
        fprintf('CleanedICASetPath:\n%s\n', cleanedSetPath);

        [status, notes, metrics] = hipexo.check_ica_output_quality( ...
            cleanedSetPath, ...
            preprocessedICASetPath, ...
            amicaSetPath, ...
            dipfittedSetPath, ...
            expectedChannels, ...
            expectedSrate, ...
            rankSampleLimit, ...
            rvThreshold15, ...
            rvThreshold20, ...
            maxAMICABadSamplesPercent, ...
            expectedAMICAInputSignature);

        sourceMap.ICAQCStatus(rowIdx) = string(status);
        sourceMap.ICAQCNotes(rowIdx) = string(notes);
        sourceMap.ICAQCDate(rowIdx) = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
        sourceMap.ICAQCSetPath(rowIdx) = string(cleanedSetPath);

        sourceMap = ensure_string_column_local(sourceMap, 'ExpertICReviewStatus');
        sourceMap = ensure_numeric_nan_column_local(sourceMap, 'AnalysisReady');

        emptyExpertRows = sessionRows( ...
            strlength(strtrim(sourceMap.ExpertICReviewStatus(sessionRows))) == 0);

        sourceMap.ExpertICReviewStatus(emptyExpertRows) = ...
            "pending_manual_cortical_IC_review";

        sourceMap.AnalysisReady(sessionRows) = 0;

        sourceMap.ICAQCChannels(rowIdx) = metrics.channels;
        sourceMap.ICAQCSrate(rowIdx) = metrics.srate;
        sourceMap.ICAQCSamples(rowIdx) = metrics.samples;
        sourceMap.ICAQCDurationSec(rowIdx) = metrics.durationSec;
        sourceMap.ICAQCRankEstimate(rowIdx) = metrics.rankEstimate;
        sourceMap.ICAQCNICs(rowIdx) = metrics.nICs;

        sourceMap.ICAQCHasAMICASet(rowIdx) = double(metrics.hasAMICASet);
        sourceMap.ICAQCHasDipfittedSet(rowIdx) = double(metrics.hasDipfittedSet);
        sourceMap.ICAQCHasPreprocessedICASet(rowIdx) = double(metrics.hasPreprocessedICASet);
        sourceMap.ICAQCHasCleanedICASet(rowIdx) = double(metrics.hasCleanedICASet);
        sourceMap.ICAQCHasICAWeights(rowIdx) = double(metrics.hasICAWeights);
        sourceMap.ICAQCHasICLabel(rowIdx) = double(metrics.hasICLabel);
        sourceMap.ICAQCHasDIPFIT(rowIdx) = double(metrics.hasDIPFIT);
        sourceMap.ICAQCICLabelDimOK(rowIdx) = double(metrics.icLabelDimOK);
        sourceMap.ICAQCDIPFITDimOK(rowIdx) = double(metrics.dipfitDimOK);
        sourceMap.ICAQCDipfittedHasDIPFIT(rowIdx) = double(metrics.dipfittedHasDIPFIT);
        sourceMap.ICAQCPreprocessedCleanedCompatible(rowIdx) = double(metrics.preprocessedCleanedCompatible);
        sourceMap.ICAQCICAMatrixDimOK(rowIdx) = double(metrics.icaMatrixDimOK);
        sourceMap.ICAQCICAValuesFinite(rowIdx) = double(metrics.icaValuesFinite);
        sourceMap.ICAQCAMICAPreprocessedEquivalent(rowIdx) = double(metrics.amicaPreprocessedEquivalent);
        sourceMap.ICAQCDipfittedPreprocessedEquivalent(rowIdx) = double(metrics.dipfittedPreprocessedEquivalent);
        sourceMap.ICAQCHasAMICAMetadata(rowIdx) = double(metrics.hasAMICAMetadata);
        sourceMap.ICAQCAMICAInputSignatureOK(rowIdx) = ...
            double(metrics.amicaInputSignatureOK);
        sourceMap.ICAQCHasBadSampleMask(rowIdx) = double(metrics.hasBadSampleMask);
        sourceMap.ICAQCBadSamples(rowIdx) = metrics.badSamples;
        sourceMap.ICAQCBadSamplesPercent(rowIdx) = metrics.badSamplesPercent;

        sourceMap.ICAQCBrainICs(rowIdx) = metrics.brainICs;
        sourceMap.ICAQCBrainICsP050(rowIdx) = metrics.brainICsP050;
        sourceMap.ICAQCBrainICsP075(rowIdx) = metrics.brainICsP075;
        sourceMap.ICAQCEyeICs(rowIdx) = metrics.eyeICs;
        sourceMap.ICAQCMuscleICs(rowIdx) = metrics.muscleICs;
        sourceMap.ICAQCHeartICs(rowIdx) = metrics.heartICs;
        sourceMap.ICAQCLineNoiseICs(rowIdx) = metrics.lineNoiseICs;
        sourceMap.ICAQCChannelNoiseICs(rowIdx) = metrics.channelNoiseICs;
        sourceMap.ICAQCOtherICs(rowIdx) = metrics.otherICs;
        sourceMap.ICAQCDipfitRVMedian(rowIdx) = metrics.dipfitRVMedian;
        sourceMap.ICAQCDipfitRVBelow15(rowIdx) = metrics.dipfitRVBelow15;
        sourceMap.ICAQCDipfitRVBelow20(rowIdx) = metrics.dipfitRVBelow20;

        % ICA outputs are session-level. Mirror all automatic ICA-QC results
        % to every enabled import-table row belonging to the same session.
        resultColumns = [ ...
            {'ICAQCStatus', 'ICAQCNotes', 'ICAQCDate', 'ICAQCSetPath'}, ...
            numericColumns ...
        ];

        sourceMap = copy_row_to_rows_local( ...
            sourceMap, ...
            rowIdx, ...
            sessionRows, ...
            resultColumns);

        fprintf('ICAQCStatus: %s\n', status);
        fprintf('ICAQCNotes: %s\n', notes);

        fprintf( ...
            'Cleaned EEG: channels %g | srate %.6f | samples %g | rank estimate %g\n', ...
            metrics.channels, ...
            metrics.srate, ...
            metrics.samples, ...
            metrics.rankEstimate);

        fprintf( ...
            'ICA file: ICs %g | ICA weights %d | ICLabel %d | DIPFIT %d\n', ...
            metrics.nICs, ...
            metrics.hasICAWeights, ...
            metrics.hasICLabel, ...
            metrics.hasDIPFIT);

        fprintf( ...
            'ICLabel dim OK: %d | DIPFIT dim OK: %d | cleaned/preprocessed compatible: %d\n', ...
            metrics.icLabelDimOK, ...
            metrics.dipfitDimOK, ...
            metrics.preprocessedCleanedCompatible);

        fprintf( ...
            'Brain ICs: %g | Brain p>=0.50: %g | Brain p>=0.75: %g\n', ...
            metrics.brainICs, ...
            metrics.brainICsP050, ...
            metrics.brainICsP075);

        fprintf( ...
            'DIPFIT RV median: %.6f | RV<15%%: %g | RV<20%%: %g\n', ...
            metrics.dipfitRVMedian, ...
            metrics.dipfitRVBelow15, ...
            metrics.dipfitRVBelow20);

        fprintf( ...
            'ICA dimensions OK: %d | ICA values finite: %d\n', ...
            metrics.icaMatrixDimOK, ...
            metrics.icaValuesFinite);

        fprintf( ...
            'AMICA/preprocessed equivalent: %d | dipfitted/preprocessed equivalent: %d\n', ...
            metrics.amicaPreprocessedEquivalent, ...
            metrics.dipfittedPreprocessedEquivalent);

        fprintf( ...
            'AMICA bad samples: %g (%.4f%%)\n', ...
            metrics.badSamples, ...
            metrics.badSamplesPercent);

        writetable(sourceMap, mappingFile);

    end

    %  FINAL SUMMARY

    fprintf('\n============================================================\n');
    fprintf('AMICA / ICA QUALITY CHECK FINISHED\n');
    fprintf('============================================================\n');

    checkedRows = rowsToCheck;

    summaryTable = sourceMap(checkedRows, intersect({ ...
        'FileName', ...
        'BidsSubject', ...
        'BidsSession', ...
        'ICAQCStatus', ...
        'ICAQCNotes', ...
        'ICAQCNICs', ...
        'ICAQCBrainICs', ...
        'ICAQCBrainICsP050', ...
        'ICAQCBrainICsP075', ...
        'ICAQCDipfitRVMedian', ...
        'ICAQCDipfitRVBelow15', ...
        'ICAQCDipfitRVBelow20', ...
        'ICAQCICLabelDimOK', ...
        'ICAQCDIPFITDimOK', ...
        'ICAQCPreprocessedCleanedCompatible', ...
        'ICAQCICAMatrixDimOK', ...
        'ICAQCICAValuesFinite', ...
        'ICAQCAMICAPreprocessedEquivalent', ...
        'ICAQCDipfittedPreprocessedEquivalent', ...
        'ICAQCBadSamples', ...
        'ICAQCBadSamplesPercent', ...
        'ExpertICReviewStatus', ...
        'AnalysisReady' ...
    }, sourceMap.Properties.VariableNames, 'stable'));

    summaryFile = ...
        fullfile( ...
            outputFolder, ...
            'amica_ica_quality_summary.csv');

    writetable( ...
        summaryTable, ...
        summaryFile);

    fprintf('\nICA QC finished.\n');

    % IMPORTANT:
    % Step 08 finished normally. Restore interactive figure behavior before
    % entering Step 09 / manual EEGLAB IC inspection.
    restore_figure_visibility_local();

catch ME

    % IMPORTANT:
    % Even if Step 08 fails, do not leave MATLAB/EEGLAB globally stuck in
    % DefaultFigureVisible = off.
    restore_figure_visibility_local();

    rethrow(ME);

end

%  HELPER FUNCTIONS

function T = ensure_string_column_local(T, columnName)

    if ~ismember(columnName, T.Properties.VariableNames)

        T.(columnName) = ...
            strings( ...
                height(T), ...
                1);

    else

        if ~isstring(T.(columnName))

            T.(columnName) = ...
                string(T.(columnName));

        end

        T.(columnName)( ...
            ismissing(T.(columnName))) = "";

    end

end


function T = ensure_numeric_column_local(T, columnName)

    if ~ismember(columnName, T.Properties.VariableNames)

        error( ...
            'Missing required numeric column: %s', ...
            columnName);

    end

    if isnumeric(T.(columnName))

        T.(columnName) = ...
            double(T.(columnName));

    elseif islogical(T.(columnName))

        T.(columnName) = ...
            double(T.(columnName));

    else

        T.(columnName) = ...
            str2double( ...
                string(T.(columnName)));

    end

end


function T = ensure_numeric_nan_column_local(T, columnName)

    if ~ismember(columnName, T.Properties.VariableNames)

        T.(columnName) = ...
            nan( ...
                height(T), ...
                1);

    else

        if isnumeric(T.(columnName))

            T.(columnName) = ...
                double(T.(columnName));

        elseif islogical(T.(columnName))

            T.(columnName) = ...
                double(T.(columnName));

        else

            T.(columnName) = ...
                str2double( ...
                    string(T.(columnName)));

        end

    end

end


function rows = session_peer_rows_local(T, rowIdx)

    rows = rowIdx;

    required = { ...
        'BidsSubject', ...
        'BidsSession' ...
    };

    if ~all( ...
            ismember( ...
                required, ...
                T.Properties.VariableNames))

        return;

    end

    subjectValues = ...
        T.BidsSubject;

    if ~isnumeric(subjectValues)

        subjectValues = ...
            str2double( ...
                string(subjectValues));

    end

    sessionValues = ...
        string(T.BidsSession);

    sessionValues( ...
        ismissing(sessionValues)) = "";

    subjectValue = ...
        subjectValues(rowIdx);

    sessionValue = ...
        sessionValues(rowIdx);

    if isnan(subjectValue) || ...
            strlength(strtrim(sessionValue)) == 0

        return;

    end

    mask = ...
        subjectValues == subjectValue & ...
        sessionValues == sessionValue;

    if ismember( ...
            'DoImport', ...
            T.Properties.VariableNames)

        doImport = ...
            T.DoImport;

        if ~isnumeric(doImport)

            doImport = ...
                str2double( ...
                    string(doImport));

        end

        mask = ...
            mask & ...
            doImport == 1;

    end

    matchedRows = ...
        find(mask);

    if ~isempty(matchedRows)

        rows = ...
            matchedRows;

    end

end


function T = copy_row_to_rows_local(T, rowIdx, rows, columnNames)

    for k = 1:numel(columnNames)

        name = ...
            columnNames{k};

        if ~ismember( ...
                name, ...
                T.Properties.VariableNames)

            continue;

        end

        value = ...
            T.(name)(rowIdx, :);

        T.(name)(rows, :) = ...
            repmat( ...
                value, ...
                numel(rows), ...
                1);

    end

end


function hide_all_figures_local()

    try

        set( ...
            0, ...
            'DefaultFigureVisible', ...
            'off');

        set( ...
            groot, ...
            'DefaultFigureVisible', ...
            'off');

        close all hidden;

    catch

    end

end


function restore_figure_visibility_local()

    % Restore normal interactive MATLAB/EEGLAB figure behavior.
    % Do NOT close figures here. The purpose is only to ensure that future
    % EEGLAB GUI actions such as Component maps / ICLabel properties can
    % create visible windows.

    try

        set( ...
            0, ...
            'DefaultFigureVisible', ...
            'on');

    catch

    end

    try

        set( ...
            groot, ...
            'DefaultFigureVisible', ...
            'on');

    catch

    end

end