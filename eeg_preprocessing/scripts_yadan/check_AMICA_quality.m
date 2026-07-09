% Goal:
% Check AMICA / ICA / ICLabel / DIPFIT output quality using bemobil_import_table.csv.
%
% Run order:
%   1) check_eeg_streams.m
%   2) import_table.m
%   3) bemobil_import.m
%   4) bemobil_process_all_EEG_data.m
%   5) check_preprocessed_EEG.m
%   6) bemobil_run_AMICA_only.m
%   7) this script
%
% This script does NOT rerun AMICA.
% It only loads existing AMICA / ICA output files and writes quality
% information back into bemobil_import_table.csv.
%
% Main logic:
%   - Only rows with AMICAStatus == "completed" AND
%     AMICAOutputStatus == "complete_outputs_verified" are selected by default.
%   - cleaned_with_ICA.set is used to check the final cleaned EEG data.
%   - preprocessed_and_ICA.set is used to check ICA weights, ICLabel, and DIPFIT.
%   - AMICA.set and dipfitted.set are also checked for existence.
%
% This is a structural / consistency QC script. It does not change EEG data.

clear; clc; close all;

set(0, 'DefaultFigureVisible', 'off');
set(groot, 'DefaultFigureVisible', 'off');

%% ========================================================================
%  LOAD CENTRAL PATHS
%  ========================================================================

run(fullfile(fileparts(mfilename('fullpath')), 'paths.m'));

if ~exist(mappingFile, 'file')
    error('Import table not found:\n%s\nPlease run the previous pipeline steps first.', mappingFile);
end

%% ========================================================================
%  QC SETTINGS
%  ========================================================================

expectedChannels = 64;
expectedSrate = 250;

% Reset DoICAQC from completed and fully verified AMICA outputs.
% Set this to false if you manually edit DoICAQC in the CSV later.
reset_DoICAQC_from_AMICAStatus = true;

% Rank estimate is computed from a subset for speed.
rankSampleLimit = 10000;

% RV thresholds are fractions, not percent.
rvThreshold15 = 0.15;
rvThreshold20 = 0.20;

%% ========================================================================
%  INITIALIZE EEGLAB
%  ========================================================================

if ~exist('pop_loadset', 'file')
    eeglab nogui;
end

hide_all_figures_local();

%% ========================================================================
%  LOAD BEMOBIL CONFIGURATION
%  ========================================================================

run(fullfile(scriptsFolder, 'bemobil_config_.m'));

hide_all_figures_local();

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
    'FileName', ...
    'BidsSubject', ...
    'BidsSession', ...
    'AMICAStatus', ...
    'AMICAOutputStatus', ...
    'AMICASetPath', ...
    'DipfittedSetPath', ...
    'PreprocessedICASetPath', ...
    'CleanedICASetPath' ...
};

for c = 1:numel(requiredColumns)
    if ~ismember(requiredColumns{c}, sourceMap.Properties.VariableNames)
        error(['Import table is missing required column: %s\n' ...
               'Please run the latest bemobil_run_AMICA_only.m first, so AMICA/DIPFIT/output5 paths are written to the table.'], ...
               requiredColumns{c});
    end
end

%% ========================================================================
%  NORMALIZE IMPORTANT COLUMNS
%  ========================================================================

sourceMap = ensure_numeric_column_local(sourceMap, 'BidsSubject');

sourceMap.FileName = string(sourceMap.FileName);
sourceMap.BidsSession = string(sourceMap.BidsSession);
sourceMap.AMICAStatus = string(sourceMap.AMICAStatus);
sourceMap.AMICAOutputStatus = string(sourceMap.AMICAOutputStatus);
sourceMap.AMICASetPath = string(sourceMap.AMICASetPath);
sourceMap.DipfittedSetPath = string(sourceMap.DipfittedSetPath);
sourceMap.PreprocessedICASetPath = string(sourceMap.PreprocessedICASetPath);
sourceMap.CleanedICASetPath = string(sourceMap.CleanedICASetPath);

sourceMap.FileName(ismissing(sourceMap.FileName)) = "";
sourceMap.BidsSession(ismissing(sourceMap.BidsSession)) = "";
sourceMap.AMICAStatus(ismissing(sourceMap.AMICAStatus)) = "";
sourceMap.AMICAOutputStatus(ismissing(sourceMap.AMICAOutputStatus)) = "";
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

%% ========================================================================
%  CREATE OR RESET DOICAQC
%  ========================================================================

readyForICAQC = ...
    sourceMap.AMICAStatus == "completed" & ...
    sourceMap.AMICAOutputStatus == "complete_outputs_verified" & ...
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
        fprintf('\nUsing existing DoICAQC values from the table.\n');
    end

end

%% ========================================================================
%  PREPARE OUTPUT COLUMNS
%  ========================================================================

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
    'ICAQCBrainICs', ...
    'ICAQCBrainICsP050', ...
    'ICAQCBrainICsP070', ...
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

%% ========================================================================
%  SELECT ROWS TO CHECK
%  ========================================================================

sourceMap = ensure_numeric_column_local(sourceMap, 'DoICAQC');

candidateRows = find(sourceMap.DoICAQC == 1);

if isempty(candidateRows)
    error('No rows with DoICAQC = 1 found in bemobil_import_table.csv.');
end

hasAllOutputPaths = ...
    strlength(strtrim(sourceMap.AMICASetPath)) > 0 & ...
    strlength(strtrim(sourceMap.DipfittedSetPath)) > 0 & ...
    strlength(strtrim(sourceMap.PreprocessedICASetPath)) > 0 & ...
    strlength(strtrim(sourceMap.CleanedICASetPath)) > 0;

completedAndVerifiedAMICA = ...
    sourceMap.AMICAStatus == "completed" & ...
    sourceMap.AMICAOutputStatus == "complete_outputs_verified";

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

%% ========================================================================
%  CHECK LOOP
%  ========================================================================

for rr = 1:numel(rowsToCheck)

    hide_all_figures_local();

    rowIdx = rowsToCheck(rr);

    cleanedSetPath = char(sourceMap.CleanedICASetPath(rowIdx));
    preprocessedICASetPath = char(sourceMap.PreprocessedICASetPath(rowIdx));
    amicaSetPath = char(sourceMap.AMICASetPath(rowIdx));
    dipfittedSetPath = char(sourceMap.DipfittedSetPath(rowIdx));

    fprintf('\n\n============================================================\n');
    fprintf('ICA QC FILE %d / %d\n', rr, numel(rowsToCheck));
    fprintf('FileName: %s\n', string(sourceMap.FileName(rowIdx)));
    fprintf('BidsSubject: %g\n', sourceMap.BidsSubject(rowIdx));
    fprintf('BidsSession: %s\n', string(sourceMap.BidsSession(rowIdx)));
    fprintf('AMICASetPath:\n%s\n', amicaSetPath);
    fprintf('DipfittedSetPath:\n%s\n', dipfittedSetPath);
    fprintf('PreprocessedICASetPath:\n%s\n', preprocessedICASetPath);
    fprintf('CleanedICASetPath:\n%s\n', cleanedSetPath);

    [status, notes, metrics] = check_one_ica_output( ...
        cleanedSetPath, ...
        preprocessedICASetPath, ...
        amicaSetPath, ...
        dipfittedSetPath, ...
        expectedChannels, ...
        expectedSrate, ...
        rankSampleLimit, ...
        rvThreshold15, ...
        rvThreshold20);

    sourceMap.ICAQCStatus(rowIdx) = string(status);
    sourceMap.ICAQCNotes(rowIdx) = string(notes);
    sourceMap.ICAQCDate(rowIdx) = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    sourceMap.ICAQCSetPath(rowIdx) = string(cleanedSetPath);

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

    sourceMap.ICAQCBrainICs(rowIdx) = metrics.brainICs;
    sourceMap.ICAQCBrainICsP050(rowIdx) = metrics.brainICsP050;
    sourceMap.ICAQCBrainICsP070(rowIdx) = metrics.brainICsP070;
    sourceMap.ICAQCEyeICs(rowIdx) = metrics.eyeICs;
    sourceMap.ICAQCMuscleICs(rowIdx) = metrics.muscleICs;
    sourceMap.ICAQCHeartICs(rowIdx) = metrics.heartICs;
    sourceMap.ICAQCLineNoiseICs(rowIdx) = metrics.lineNoiseICs;
    sourceMap.ICAQCChannelNoiseICs(rowIdx) = metrics.channelNoiseICs;
    sourceMap.ICAQCOtherICs(rowIdx) = metrics.otherICs;
    sourceMap.ICAQCDipfitRVMedian(rowIdx) = metrics.dipfitRVMedian;
    sourceMap.ICAQCDipfitRVBelow15(rowIdx) = metrics.dipfitRVBelow15;
    sourceMap.ICAQCDipfitRVBelow20(rowIdx) = metrics.dipfitRVBelow20;

    fprintf('ICAQCStatus: %s\n', status);
    fprintf('ICAQCNotes: %s\n', notes);
    fprintf('Cleaned EEG: channels %g | srate %.6f | samples %g | rank estimate %g\n', ...
        metrics.channels, metrics.srate, metrics.samples, metrics.rankEstimate);
    fprintf('ICA file: ICs %g | ICA weights %d | ICLabel %d | DIPFIT %d\n', ...
        metrics.nICs, metrics.hasICAWeights, metrics.hasICLabel, metrics.hasDIPFIT);
    fprintf('ICLabel dim OK: %d | DIPFIT dim OK: %d | cleaned/preprocessed compatible: %d\n', ...
        metrics.icLabelDimOK, metrics.dipfitDimOK, metrics.preprocessedCleanedCompatible);
    fprintf('Brain ICs: %g | Brain p>=0.5: %g | Brain p>=0.7: %g\n', ...
        metrics.brainICs, metrics.brainICsP050, metrics.brainICsP070);
    fprintf('DIPFIT RV median: %.6f | RV<15%%: %g | RV<20%%: %g\n', ...
        metrics.dipfitRVMedian, metrics.dipfitRVBelow15, metrics.dipfitRVBelow20);

    writetable(sourceMap, mappingFile);

end

%% ========================================================================
%  FINAL SUMMARY
%  ========================================================================

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
    'ICAQCBrainICsP070', ...
    'ICAQCDipfitRVMedian', ...
    'ICAQCDipfitRVBelow15', ...
    'ICAQCDipfitRVBelow20', ...
    'ICAQCICLabelDimOK', ...
    'ICAQCDIPFITDimOK', ...
    'ICAQCPreprocessedCleanedCompatible' ...
}, sourceMap.Properties.VariableNames, 'stable'));

disp(summaryTable);

summaryFile = fullfile(outputFolder, 'amica_ica_quality_summary.csv');
writetable(summaryTable, summaryFile);

fprintf('\nICA QC summary saved to:\n%s\n', summaryFile);
fprintf('Import table updated:\n%s\n', mappingFile);
fprintf('\nDone.\n');

%% ========================================================================
%  HELPER FUNCTIONS
%  ========================================================================

function [status, notes, metrics] = check_one_ica_output(cleanedSetPath, preprocessedICASetPath, amicaSetPath, dipfittedSetPath, expectedChannels, expectedSrate, rankSampleLimit, rvThreshold15, rvThreshold20)

    metrics = empty_ica_metrics();
    warnings = strings(0, 1);
    failures = strings(0, 1);

    metrics.hasCleanedICASet = exist(cleanedSetPath, 'file') == 2;
    metrics.hasPreprocessedICASet = exist(preprocessedICASetPath, 'file') == 2;
    metrics.hasAMICASet = exist(amicaSetPath, 'file') == 2;
    metrics.hasDipfittedSet = exist(dipfittedSetPath, 'file') == 2;

    if ~metrics.hasCleanedICASet
        status = "failed_cleaned_ica_set_missing";
        notes = "CleanedICASetPath does not exist.";
        return;
    end

    if ~metrics.hasPreprocessedICASet
        failures(end+1, 1) = "preprocessed_and_ICA_set_missing";
    end

    if ~metrics.hasAMICASet
        failures(end+1, 1) = "AMICA_set_missing";
    end

    if ~metrics.hasDipfittedSet
        failures(end+1, 1) = "dipfitted_set_missing";
    end

    %% --------------------------------------------------------------------
    %  Load cleaned_with_ICA.set for final cleaned EEG data checks
    %  --------------------------------------------------------------------

    try
        EEG_cleaned = load_set_local(cleanedSetPath);
    catch ME
        status = "failed_load_cleaned_ica_set";
        notes = "Could not load cleaned ICA set: " + string(ME.message);
        return;
    end

    metrics.channels = safe_get_numeric_field(EEG_cleaned, 'nbchan');
    metrics.srate = safe_get_numeric_field(EEG_cleaned, 'srate');
    metrics.samples = safe_get_numeric_field(EEG_cleaned, 'pnts');

    if ~isnan(metrics.srate) && metrics.srate > 0 && ~isnan(metrics.samples) && metrics.samples > 1
        metrics.durationSec = (metrics.samples - 1) / metrics.srate;
    end

    if metrics.channels ~= expectedChannels
        failures(end+1, 1) = "unexpected_cleaned_channel_count";
    end

    if isnan(metrics.srate) || abs(metrics.srate - expectedSrate) > 1e-6
        failures(end+1, 1) = "unexpected_cleaned_sampling_rate";
    end

    if isempty(EEG_cleaned.data)
        failures(end+1, 1) = "empty_cleaned_EEG_data";
    else
        finiteOK = check_data_finite_sampled(EEG_cleaned.data);
        if ~finiteOK
            failures(end+1, 1) = "NaN_or_Inf_in_cleaned_EEG_data";
        end
        metrics.rankEstimate = estimate_data_rank_sampled(EEG_cleaned.data, rankSampleLimit);
    end

    cleanedLabels = get_channel_labels(EEG_cleaned);
    if numel(cleanedLabels) ~= numel(unique(cleanedLabels))
        warnings(end+1, 1) = "duplicate_channel_labels_in_cleaned_set";
    end

    %% --------------------------------------------------------------------
    %  Load preprocessed_and_ICA.set for ICA / ICLabel / DIPFIT checks
    %  --------------------------------------------------------------------

    if metrics.hasPreprocessedICASet

        try
            EEG_ica = load_set_local(preprocessedICASetPath);
        catch ME
            failures(end+1, 1) = "failed_load_preprocessed_and_ICA_set";
            warnings(end+1, 1) = "preprocessed_and_ICA_load_error: " + string(ME.message);
            EEG_ica = [];
        end

    else

        EEG_ica = [];

    end

    if ~isempty(EEG_ica)

        icaChannels = safe_get_numeric_field(EEG_ica, 'nbchan');
        icaSrate = safe_get_numeric_field(EEG_ica, 'srate');
        icaSamples = safe_get_numeric_field(EEG_ica, 'pnts');

        if icaChannels == metrics.channels && ...
                abs(icaSrate - metrics.srate) <= 1e-6 && ...
                icaSamples == metrics.samples
            metrics.preprocessedCleanedCompatible = true;
        else
            metrics.preprocessedCleanedCompatible = false;
            warnings(end+1, 1) = "preprocessed_and_ICA_not_fully_compatible_with_cleaned_set";
        end

        icaLabels = get_channel_labels(EEG_ica);
        if numel(icaLabels) ~= numel(unique(icaLabels))
            warnings(end+1, 1) = "duplicate_channel_labels_in_preprocessed_and_ICA_set";
        end

        metrics.hasICAWeights = isfield(EEG_ica, 'icaweights') && ~isempty(EEG_ica.icaweights) && ...
            isfield(EEG_ica, 'icasphere') && ~isempty(EEG_ica.icasphere);

        if metrics.hasICAWeights
            metrics.nICs = size(EEG_ica.icaweights, 1);
        else
            failures(end+1, 1) = "missing_ICA_weights_or_sphere_in_preprocessed_and_ICA";
        end

        [hasICLabel, icLabelMetrics, icLabelDimOK] = extract_iclabel_metrics(EEG_ica, metrics.nICs);
        metrics.hasICLabel = hasICLabel;
        metrics.icLabelDimOK = icLabelDimOK;

        if hasICLabel
            metrics.brainICs = icLabelMetrics.brainICs;
            metrics.brainICsP050 = icLabelMetrics.brainICsP050;
            metrics.brainICsP070 = icLabelMetrics.brainICsP070;
            metrics.eyeICs = icLabelMetrics.eyeICs;
            metrics.muscleICs = icLabelMetrics.muscleICs;
            metrics.heartICs = icLabelMetrics.heartICs;
            metrics.lineNoiseICs = icLabelMetrics.lineNoiseICs;
            metrics.channelNoiseICs = icLabelMetrics.channelNoiseICs;
            metrics.otherICs = icLabelMetrics.otherICs;

            if ~icLabelDimOK
                failures(end+1, 1) = "ICLabel_dimension_does_not_match_IC_count";
            end
        else
            warnings(end+1, 1) = "missing_ICLabel_classification_in_preprocessed_and_ICA";
        end

        [hasDIPFIT, dipfitMetrics, dipfitDimOK] = extract_dipfit_metrics(EEG_ica, metrics.nICs, rvThreshold15, rvThreshold20);
        metrics.hasDIPFIT = hasDIPFIT;
        metrics.dipfitDimOK = dipfitDimOK;

        if hasDIPFIT
            metrics.dipfitRVMedian = dipfitMetrics.rvMedian;
            metrics.dipfitRVBelow15 = dipfitMetrics.rvBelow15;
            metrics.dipfitRVBelow20 = dipfitMetrics.rvBelow20;

            if ~dipfitDimOK
                failures(end+1, 1) = "DIPFIT_model_count_does_not_match_IC_count";
            end
        else
            warnings(end+1, 1) = "missing_DIPFIT_model_or_RV_in_preprocessed_and_ICA";
        end

    end

    %% --------------------------------------------------------------------
    %  Check dipfitted.set contains DIPFIT as expected
    %  --------------------------------------------------------------------

    if metrics.hasDipfittedSet

        try
            EEG_dipfitted = load_set_local(dipfittedSetPath);
            [dipfittedHasDIPFIT, ~, dipfittedDimOK] = extract_dipfit_metrics(EEG_dipfitted, metrics.nICs, rvThreshold15, rvThreshold20);
            metrics.dipfittedHasDIPFIT = dipfittedHasDIPFIT;

            if ~dipfittedHasDIPFIT
                warnings(end+1, 1) = "dipfitted_set_has_no_DIPFIT_RV_values";
            elseif ~dipfittedDimOK && ~isnan(metrics.nICs)
                warnings(end+1, 1) = "dipfitted_set_DIPFIT_count_does_not_match_IC_count";
            end
        catch ME
            warnings(end+1, 1) = "failed_load_dipfitted_set: " + string(ME.message);
        end

    end

    %% --------------------------------------------------------------------
    %  Rank sanity check
    %  --------------------------------------------------------------------

    if metrics.hasICAWeights && ~isnan(metrics.nICs) && ~isnan(metrics.rankEstimate)
        if metrics.nICs > metrics.rankEstimate + 2
            warnings(end+1, 1) = "IC_count_larger_than_estimated_cleaned_data_rank";
        end
    end

    %% --------------------------------------------------------------------
    %  Final status
    %  --------------------------------------------------------------------

    if isempty(failures) && isempty(warnings)
        status = "passed_ica_quality_basic_checks";
        notes = "All basic ICA output checks passed. Still visually inspect IC maps/classes before final analysis.";
    elseif isempty(failures)
        status = "warning_ica_quality_needs_review";
        notes = "Warnings: " + join(warnings, "; ");
    else
        status = "failed_ica_quality_basic_checks";
        if isempty(warnings)
            notes = "Failures: " + join(failures, "; ");
        else
            notes = "Failures: " + join(failures, "; ") + "; Warnings: " + join(warnings, "; ");
        end
    end

end

function metrics = empty_ica_metrics()

    metrics = struct();
    metrics.channels = NaN;
    metrics.srate = NaN;
    metrics.samples = NaN;
    metrics.durationSec = NaN;
    metrics.rankEstimate = NaN;
    metrics.nICs = NaN;

    metrics.hasAMICASet = false;
    metrics.hasDipfittedSet = false;
    metrics.hasPreprocessedICASet = false;
    metrics.hasCleanedICASet = false;

    metrics.hasICAWeights = false;
    metrics.hasICLabel = false;
    metrics.hasDIPFIT = false;
    metrics.icLabelDimOK = false;
    metrics.dipfitDimOK = false;
    metrics.dipfittedHasDIPFIT = false;
    metrics.preprocessedCleanedCompatible = false;

    metrics.brainICs = NaN;
    metrics.brainICsP050 = NaN;
    metrics.brainICsP070 = NaN;
    metrics.eyeICs = NaN;
    metrics.muscleICs = NaN;
    metrics.heartICs = NaN;
    metrics.lineNoiseICs = NaN;
    metrics.channelNoiseICs = NaN;
    metrics.otherICs = NaN;

    metrics.dipfitRVMedian = NaN;
    metrics.dipfitRVBelow15 = NaN;
    metrics.dipfitRVBelow20 = NaN;

end

function EEG = load_set_local(setPath)

    [folderPath, fileNameNoExt, fileExt] = fileparts(setPath);
    EEG = pop_loadset('filename', [fileNameNoExt fileExt], 'filepath', folderPath);
    EEG = eeg_checkset(EEG);

end

function value = safe_get_numeric_field(S, fieldName)

    value = NaN;

    if isfield(S, fieldName)
        rawValue = S.(fieldName);
        if isnumeric(rawValue) && ~isempty(rawValue)
            value = double(rawValue(1));
        end
    end

end

function labels = get_channel_labels(EEG)

    labels = strings(0, 1);

    if ~isfield(EEG, 'chanlocs') || isempty(EEG.chanlocs)
        return;
    end

    labels = strings(numel(EEG.chanlocs), 1);

    for k = 1:numel(EEG.chanlocs)
        if isfield(EEG.chanlocs(k), 'labels')
            labels(k) = string(EEG.chanlocs(k).labels);
        else
            labels(k) = "";
        end
    end

end

function finiteOK = check_data_finite_sampled(data)

    finiteOK = true;

    try
        n = numel(data);
        if n == 0
            finiteOK = false;
            return;
        end
        step = max(1, floor(n / 500000));
        sampledData = double(data(1:step:end));
        finiteOK = all(isfinite(sampledData(:)));
    catch
        finiteOK = false;
    end

end

function rankEstimate = estimate_data_rank_sampled(data, rankSampleLimit)

    rankEstimate = NaN;

    try
        dataDouble = double(data);
        nSamples = size(dataDouble, 2);

        if nSamples > rankSampleLimit
            idx = round(linspace(1, nSamples, rankSampleLimit));
            dataDouble = dataDouble(:, idx);
        end

        dataDouble = dataDouble - mean(dataDouble, 2, 'omitnan');
        rankEstimate = rank(dataDouble');
    catch
        rankEstimate = NaN;
    end

end

function [hasICLabel, metrics, dimOK] = extract_iclabel_metrics(EEG, nICs)

    hasICLabel = false;
    dimOK = false;

    metrics = struct();
    metrics.brainICs = NaN;
    metrics.brainICsP050 = NaN;
    metrics.brainICsP070 = NaN;
    metrics.eyeICs = NaN;
    metrics.muscleICs = NaN;
    metrics.heartICs = NaN;
    metrics.lineNoiseICs = NaN;
    metrics.channelNoiseICs = NaN;
    metrics.otherICs = NaN;

    if ~isfield(EEG, 'etc') || ...
            ~isfield(EEG.etc, 'ic_classification') || ...
            ~isfield(EEG.etc.ic_classification, 'ICLabel') || ...
            ~isfield(EEG.etc.ic_classification.ICLabel, 'classifications')
        return;
    end

    probs = EEG.etc.ic_classification.ICLabel.classifications;

    if isempty(probs) || size(probs, 2) < 7
        return;
    end

    hasICLabel = true;

    if ~isnan(nICs) && size(probs, 1) == nICs
        dimOK = true;
    end

    [~, dominantClass] = max(probs, [], 2);

    metrics.brainICs = sum(dominantClass == 1);
    metrics.muscleICs = sum(dominantClass == 2);
    metrics.eyeICs = sum(dominantClass == 3);
    metrics.heartICs = sum(dominantClass == 4);
    metrics.lineNoiseICs = sum(dominantClass == 5);
    metrics.channelNoiseICs = sum(dominantClass == 6);
    metrics.otherICs = sum(dominantClass == 7);

    metrics.brainICsP050 = sum(probs(:, 1) >= 0.50);
    metrics.brainICsP070 = sum(probs(:, 1) >= 0.70);

end

function [hasDIPFIT, metrics, dimOK] = extract_dipfit_metrics(EEG, nICs, rvThreshold15, rvThreshold20)

    hasDIPFIT = false;
    dimOK = false;

    metrics = struct();
    metrics.rvMedian = NaN;
    metrics.rvBelow15 = NaN;
    metrics.rvBelow20 = NaN;

    if ~isfield(EEG, 'dipfit') || ~isfield(EEG.dipfit, 'model') || isempty(EEG.dipfit.model)
        return;
    end

    if ~isnan(nICs) && numel(EEG.dipfit.model) == nICs
        dimOK = true;
    end

    rvValues = [];

    for k = 1:numel(EEG.dipfit.model)
        if isfield(EEG.dipfit.model(k), 'rv') && ~isempty(EEG.dipfit.model(k).rv)
            rvValues(end+1, 1) = double(EEG.dipfit.model(k).rv);
        end
    end

    rvValues = rvValues(isfinite(rvValues));

    if isempty(rvValues)
        return;
    end

    hasDIPFIT = true;
    metrics.rvMedian = median(rvValues);
    metrics.rvBelow15 = sum(rvValues < rvThreshold15);
    metrics.rvBelow20 = sum(rvValues < rvThreshold20);

end

function T = ensure_string_column_local(T, columnName)

    if ~ismember(columnName, T.Properties.VariableNames)
        T.(columnName) = strings(height(T), 1);
    else
        if ~isstring(T.(columnName))
            T.(columnName) = string(T.(columnName));
        end
        T.(columnName)(ismissing(T.(columnName))) = "";
    end

end

function T = ensure_numeric_column_local(T, columnName)

    if ~ismember(columnName, T.Properties.VariableNames)
        error('Missing required numeric column: %s', columnName);
    end

    if isnumeric(T.(columnName))
        T.(columnName) = double(T.(columnName));
    elseif islogical(T.(columnName))
        T.(columnName) = double(T.(columnName));
    else
        T.(columnName) = str2double(string(T.(columnName)));
    end

end

function T = ensure_numeric_nan_column_local(T, columnName)

    if ~ismember(columnName, T.Properties.VariableNames)
        T.(columnName) = nan(height(T), 1);
    else
        if isnumeric(T.(columnName))
            T.(columnName) = double(T.(columnName));
        elseif islogical(T.(columnName))
            T.(columnName) = double(T.(columnName));
        else
            T.(columnName) = str2double(string(T.(columnName)));
        end
    end

end

function hide_all_figures_local()

    try
        set(0, 'DefaultFigureVisible', 'off');
        set(groot, 'DefaultFigureVisible', 'off');
        close all hidden;
    catch
    end

end
