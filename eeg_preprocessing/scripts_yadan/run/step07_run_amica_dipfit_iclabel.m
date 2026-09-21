% GOAL
%   Run AMICA source decomposition followed by DIPFIT source localization
%   and ICLabel classification for EEG datasets that passed Step 06 QC.
%
% INPUT
%   Updated subject_level_EEG_table.csv from Step 06.
%   Verified preprocessed .set/.fdt datasets produced by Step 05.
%
% APPROACH
%   1. Process only rows with DoAMICA = 1 that passed preprocessing QC.
%   2. Use only the canonical project output paths.
%   3. Skip complete outputs when their current or legacy-equivalent AMICA
%      input provenance matches the unchanged preprocessed dataset.
%   4. Resume compatible partial outputs, but force a full recomputation when
%      any reusable saved stage belongs to different preprocessing/configuration.
%   5. Run the project AMICA/DIPFIT/ICLabel wrapper and verify final outputs.
%
% OUTPUT
%   AMICA.set
%   dipfitted.set
%   preprocessed_and_ICA.set
%   cleaned_with_ICA.set
%   Updated subject_level_EEG_table.csv
%
% USED BY
%   Step 08 AMICA / ICA / ICLabel / DIPFIT quality control.

clear;
clc;
close all;

set(0, 'DefaultFigureVisible', 'off');
set(groot, 'DefaultFigureVisible', 'off');

%  LOAD PATHS AND CONFIGURATION

thisFile = mfilename('fullpath');

if isempty(thisFile)
    error('Could not resolve the current Step 07 script path.');
end

runFolder = fileparts(thisFile);
scriptsRoot = fileparts(runFolder);

addpath(scriptsRoot, '-begin');
addpath(fullfile(scriptsRoot, 'config'), '-begin');

P = project_paths();
bemobil_config = config_step05_09_eeg_preprocessing_ica(P);

mappingFile = P.subjectLevelEEGTableFile;
amicaTempFolder = P.amicaTempFolder;
fieldtripFolder = P.fieldtripFolder;

if ~isfile(mappingFile)
    error([ ...
        'Subject-level processing table not found:\n%s\n' ...
        'Run step06_check_preprocessed_eeg.m first.'], ...
        mappingFile);
end

if ~isfolder(amicaTempFolder)
    mkdir(amicaTempFolder);
end

cd(amicaTempFolder);

force_recompute_amica = ...
    logical(bemobil_config.pipeline.force_recompute_amica);

skip_existing_complete_outputs = ...
    logical(bemobil_config.pipeline.skip_existing_complete_amica_outputs);

expectedChannelsBeforeAMICA = ...
    double(bemobil_config.pipeline.expectedChannelsBeforeAMICA);

if isempty(bemobil_config.resample_freq)
    expectedPreprocessedSrate = 500;
else
    expectedPreprocessedSrate = double(bemobil_config.resample_freq);
end

amicaConfigSignature = ...
    hipexo.amica_scientific_signature(bemobil_config);

%  INITIALIZE EEGLAB, FIELDTRIP, AND DIPFIT

[ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab('nogui');
clear EEG

hipexo.hide_all_figures();

if strlength(strtrim(string(fieldtripFolder))) == 0 || ...
        ~isfolder(fieldtripFolder)

    error([ ...
        'Configured FieldTrip folder does not exist:\n%s\n' ...
        'Correct fieldtripFolder in project_paths.m.'], ...
        char(string(fieldtripFolder)));
end

currentPathEntries = strsplit(path, pathsep);

for pathIndex = numel(currentPathEntries):-1:1
    thisPathEntry = strtrim(currentPathEntries{pathIndex});

    if ~isempty(thisPathEntry) && ...
            contains(lower(thisPathEntry), 'fieldtrip-lite')
        rmpath(thisPathEntry);
    end
end

clear ft_defaults ft_version ft_read_headmodel ft_dipolefitting
rehash toolboxcache;

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

dipfitDefsFile = which('dipfitdefs.m');

if isempty(dipfitDefsFile)
    error([ ...
        'DIPFIT is not available on the MATLAB path.\n' ...
        'Enable the EEGLAB DIPFIT plugin before running Step 07.']);
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
        error('Required DIPFIT folder does not exist:\n%s', ...
            dipfitResourceFolders{folderIndex});
    end

    addpath(dipfitResourceFolders{folderIndex}, '-begin');
end

dipfitHeadModelFile = fullfile( ...
    dipfitRoot, 'standard_BEM', 'standard_vol.mat');

dipfitMRIFile = fullfile( ...
    dipfitRoot, 'standard_BEM', 'standard_mri.mat');

dipfitChannelFile = fullfile( ...
    dipfitRoot, 'standard_BEM', 'elec', 'standard_1005.elc');

requiredDipfitFiles = { ...
    dipfitHeadModelFile, ...
    dipfitMRIFile, ...
    dipfitChannelFile ...
};

for fileIndex = 1:numel(requiredDipfitFiles)
    if ~isfile(requiredDipfitFiles{fileIndex})
        error('Required DIPFIT file does not exist:\n%s', ...
            requiredDipfitFiles{fileIndex});
    end
end

try
    dipfitHeadModelTest = ft_read_headmodel(dipfitHeadModelFile);
catch ME
    error([ ...
        'DIPFIT head-model preflight failed.\n' ...
        'Head model:\n%s\n' ...
        'Original error:\n%s'], ...
        dipfitHeadModelFile, ...
        ME.message);
end

if ~isstruct(dipfitHeadModelTest)
    error('DIPFIT head-model preflight returned an unexpected result.');
end

clear dipfitHeadModelTest

%  READ AND SELECT SUBJECTS

optsImport = detectImportOptions( ...
    mappingFile, ...
    'FileType', 'text', ...
    'Delimiter', ',', ...
    'VariableNamingRule', 'preserve');

sourceMap = readtable(mappingFile, optsImport);

requiredColumns = { ...
    'BidsSubject', ...
    'BidsSession', ...
    'PreprocessingStatus', ...
    'PreprocessingQCStatus', ...
    'PreprocessedSetPath', ...
    'DoAMICA' ...
};

for columnIndex = 1:numel(requiredColumns)
    if ~ismember(requiredColumns{columnIndex}, ...
            sourceMap.Properties.VariableNames)

        error([ ...
            'Processing table is missing required column: %s\n' ...
            'Run step06_check_preprocessed_eeg.m first.'], ...
            requiredColumns{columnIndex});
    end
end

sourceMap = ensure_numeric_column(sourceMap, 'BidsSubject');
sourceMap = ensure_numeric_column(sourceMap, 'DoAMICA');

sourceMap.BidsSession = string(sourceMap.BidsSession);
sourceMap.PreprocessingStatus = string(sourceMap.PreprocessingStatus);
sourceMap.PreprocessingQCStatus = string(sourceMap.PreprocessingQCStatus);
sourceMap.PreprocessedSetPath = string(sourceMap.PreprocessedSetPath);

sourceMap.BidsSession(ismissing(sourceMap.BidsSession)) = "";
sourceMap.PreprocessingStatus(ismissing(sourceMap.PreprocessingStatus)) = "";
sourceMap.PreprocessingQCStatus(ismissing(sourceMap.PreprocessingQCStatus)) = "";
sourceMap.PreprocessedSetPath(ismissing(sourceMap.PreprocessedSetPath)) = "";

sourceMap = ensure_string_column(sourceMap, 'AMICAStatus');
sourceMap = ensure_string_column(sourceMap, 'AMICADate');
sourceMap = ensure_string_column(sourceMap, 'AMICANotes');
sourceMap = ensure_string_column(sourceMap, 'AMICASetPath');
sourceMap = ensure_string_column(sourceMap, 'DipfittedSetPath');
sourceMap = ensure_string_column(sourceMap, 'PreprocessedICASetPath');
sourceMap = ensure_string_column(sourceMap, 'CleanedICASetPath');
sourceMap = ensure_string_column(sourceMap, 'AMICAOutputStatus');
sourceMap = ensure_string_column(sourceMap, 'AMICAInputSignature');
sourceMap = ensure_string_column(sourceMap, 'AMICAConfigSignature');
sourceMap = ensure_string_column(sourceMap, 'AMICAPrefinalSignature');

candidateRows = find(sourceMap.DoAMICA == 1);

if isempty(candidateRows)
    fprintf('\nNo rows with DoAMICA = 1. Nothing to run.\n');

    % Restore normal MATLAB/EEGLAB figure behavior before leaving Step 07.
    set(0, 'ShowHiddenHandles', 'off');
    set(0, 'DefaultFigureVisible', 'on');
    set(groot, 'DefaultFigureVisible', 'on');

    return;
end

validMask = ...
    sourceMap.PreprocessingStatus(candidateRows) == "completed" & ...
    sourceMap.PreprocessingQCStatus(candidateRows) == ...
        "passed_basic_checks" & ...
    strlength(strtrim(sourceMap.PreprocessedSetPath(candidateRows))) > 0;

validRows = candidateRows(validMask);

if isempty(validRows)
    error([ ...
        'Rows with DoAMICA = 1 exist, but none passed the Step 07 gate.\n' ...
        'Run Step 06 and inspect PreprocessingStatus and ' ...
        'PreprocessingQCStatus.']);
end

[~, uniquePathIndex] = unique( ...
    sourceMap.PreprocessedSetPath(validRows), ...
    'stable');

rowsToProcess = validRows(uniquePathIndex);
rowsToProcess = rowsToProcess(hipexo.subject_is_selected(sourceMap.BidsSubject(rowsToProcess)));

%  PROCESS EACH SUBJECT

for rowNumber = 1:numel(rowsToProcess)

    hipexo.hide_all_figures();

    rowIdx = rowsToProcess(rowNumber);
    sessionRows = hipexo.session_peer_rows(sourceMap, rowIdx);

    bidsSubject = sourceMap.BidsSubject(rowIdx);

    if ~isfinite(bidsSubject) || ...
            bidsSubject < 1 || ...
            abs(bidsSubject - round(bidsSubject)) > 1e-6

        sourceMap = set_amica_failure( ...
            sourceMap, ...
            sessionRows, ...
            "failed_invalid_bids_subject", ...
            "BidsSubject must be a positive integer.");

        writetable(sourceMap, mappingFile);
        continue;
    end

    processingSubjectLabel = sprintf('%02d', round(bidsSubject));
    processingSubjectFolder = ['sub-' processingSubjectLabel];
    bidsSession = char(sourceMap.BidsSession(rowIdx));
    preprocessedSetPath = char(sourceMap.PreprocessedSetPath(rowIdx));

    fprintf('Subject %d / %d: %s\n', ...
        rowNumber, numel(rowsToProcess), processingSubjectFolder);

    if ~isfile(preprocessedSetPath)
        sourceMap = set_amica_failure( ...
            sourceMap, ...
            sessionRows, ...
            "failed_preprocessed_file_not_found", ...
            "Preprocessed .set file was not found.");

        writetable(sourceMap, mappingFile);
        continue;
    end

    try
        preprocessedDatasetSignature = ...
            hipexo.eeglab_dataset_signature(preprocessedSetPath, "signal");
    catch ME
        sourceMap = set_amica_failure( ...
            sourceMap, ...
            sessionRows, ...
            "failed_preprocessed_signature", ...
            string(ME.message));

        writetable(sourceMap, mappingFile);
        continue;
    end

    expectedAMICAInputSignature = ...
        preprocessedDatasetSignature + ...
        "|cfg=" + amicaConfigSignature;
    stageSignatures = hipexo.amica_stage_signatures(bemobil_config, preprocessedDatasetSignature);
    stageNames = {'amica', 'dipfit', 'prefinal', 'cleaned'};
    legacySignature = expectedAMICAInputSignature;
    if bemobil_config.use_reject_continuous
        legacySignature = "";
    end

    [ ...
        amicaSetPath, ...
        dipfittedSetPath, ...
        preprocessedICASetPath, ...
        cleanedICASetPath ...
    ] = canonical_amica_paths( ...
        bemobil_config, ...
        processingSubjectFolder);

    outputPaths = [ ...
        string(amicaSetPath), ...
        string(dipfittedSetPath), ...
        string(preprocessedICASetPath), ...
        string(cleanedICASetPath) ...
    ];

    outputExists = false(1, numel(outputPaths));

    for outputIndex = 1:numel(outputPaths)
        outputExists(outputIndex) = isfile(outputPaths(outputIndex));
    end

    existingOutputStatus = describe_output_status(outputExists);

    stageProvenanceOK = true(1, numel(outputPaths));

    if ~force_recompute_amica
        for outputIndex = find(outputExists)
            stageProvenanceOK(outputIndex) = ...
                verify_amica_output_provenance( ...
                    outputPaths(outputIndex), ...
                    legacySignature, stageSignatures, stageNames{outputIndex});
        end
    end

    completeOutputsExist = all(outputExists);

    completeOutputsMatch = ...
        completeOutputsExist && ...
        stageProvenanceOK(3) && ...
        stageProvenanceOK(4);

    if ~force_recompute_amica && ...
            skip_existing_complete_outputs && ...
            completeOutputsMatch

        fprintf('Complete outputs match the current input. Skipping.\n');

        sourceMap.AMICAStatus(sessionRows) = "completed";
        sourceMap.AMICANotes(sessionRows) = ...
            "Verified current AMICA outputs already exist; skipped.";
        sourceMap.AMICASetPath(sessionRows) = string(amicaSetPath);
        sourceMap.DipfittedSetPath(sessionRows) = string(dipfittedSetPath);
        sourceMap.PreprocessedICASetPath(sessionRows) = ...
            string(preprocessedICASetPath);
        sourceMap.CleanedICASetPath(sessionRows) = ...
            string(cleanedICASetPath);
        sourceMap.AMICAOutputStatus(sessionRows) = ...
            "complete_outputs_verified";
        sourceMap.AMICAInputSignature(sessionRows) = ...
            expectedAMICAInputSignature;
        sourceMap.AMICAPrefinalSignature(sessionRows) = stageSignatures.prefinal;
    sourceMap.AMICAConfigSignature(sessionRows) = ...
            amicaConfigSignature;

        writetable(sourceMap, mappingFile);
        continue;
    end

    if force_recompute_amica
        rowForceRecomputeAMICA = true;
        runReason = "force_recompute_amica = 1";

    elseif any(outputExists) && ...
            ~all(stageProvenanceOK(outputExists))

        rowForceRecomputeAMICA = false;
        runReason = "Resume from the latest compatible stage";

    elseif completeOutputsExist && ...
            ~skip_existing_complete_outputs

        rowForceRecomputeAMICA = true;
        runReason = ...
            "Skipping complete outputs is disabled";

    else
        rowForceRecomputeAMICA = false;

        if any(outputExists)
            runReason = "Compatible partial output; resume";
        else
            runReason = "No existing output; start normally";
        end
    end

    fprintf('Decision: %s.\n', runReason);

    sourceMap.AMICAStatus(sessionRows) = "running";
    sourceMap.AMICADate(sessionRows) = current_timestamp();
    sourceMap.AMICANotes(sessionRows) = runReason;
    sourceMap.AMICASetPath(sessionRows) = ...
        existing_file_path(amicaSetPath);
    sourceMap.DipfittedSetPath(sessionRows) = ...
        existing_file_path(dipfittedSetPath);
    sourceMap.PreprocessedICASetPath(sessionRows) = ...
        existing_file_path(preprocessedICASetPath);
    sourceMap.CleanedICASetPath(sessionRows) = ...
        existing_file_path(cleanedICASetPath);
    sourceMap.AMICAOutputStatus(sessionRows) = ...
        "running__" + existingOutputStatus;
    sourceMap.AMICAInputSignature(sessionRows) = ...
        expectedAMICAInputSignature;
    sourceMap.AMICAPrefinalSignature(sessionRows) = stageSignatures.prefinal;
    sourceMap.AMICAConfigSignature(sessionRows) = ...
        amicaConfigSignature;

    writetable(sourceMap, mappingFile);

    ALLEEG = [];
    EEG = [];
    CURRENTSET = 0;
    EEG_preprocessed = [];

    [preprocFolder, preprocBase, preprocExt] = ...
        fileparts(preprocessedSetPath);

    try
        EEG_preprocessed = pop_loadset( ...
            'filename', [preprocBase preprocExt], ...
            'filepath', preprocFolder);

        EEG_preprocessed = eeg_checkset(EEG_preprocessed);
    catch ME
        sourceMap = set_amica_failure( ...
            sourceMap, ...
            sessionRows, ...
            "failed_load_preprocessed_set", ...
            string(ME.message));

        writetable(sourceMap, mappingFile);
        clear EEG_preprocessed ALLEEG EEG CURRENTSET
        continue;
    end

    if EEG_preprocessed.nbchan ~= expectedChannelsBeforeAMICA
        sourceMap = set_amica_failure( ...
            sourceMap, ...
            sessionRows, ...
            "failed_unexpected_channel_count", ...
            "Expected " + string(expectedChannelsBeforeAMICA) + ...
            " channels, found " + string(EEG_preprocessed.nbchan) + ".");

        writetable(sourceMap, mappingFile);
        clear EEG_preprocessed ALLEEG EEG CURRENTSET
        continue;
    end

    if abs(EEG_preprocessed.srate - expectedPreprocessedSrate) > 0.001
        sourceMap = set_amica_failure( ...
            sourceMap, ...
            sessionRows, ...
            "failed_unexpected_sampling_rate", ...
            "Expected " + string(expectedPreprocessedSrate) + ...
            " Hz, found " + string(EEG_preprocessed.srate) + " Hz.");

        writetable(sourceMap, mappingFile);
        clear EEG_preprocessed ALLEEG EEG CURRENTSET
        continue;
    end

    [amicaDataRank, rankMetadataValid] = ...
        get_rank_metadata(EEG_preprocessed);

    if ~rankMetadataValid
        sourceMap = set_amica_failure( ...
            sourceMap, ...
            sessionRows, ...
            "failed_invalid_rank_metadata", ...
            "EEG.etc.rank must be a finite integer from 1 to EEG.nbchan.");

        writetable(sourceMap, mappingFile);
        clear EEG_preprocessed ALLEEG EEG CURRENTSET
        continue;
    end

    if ~isfield(EEG_preprocessed, 'etc') || ...
            isempty(EEG_preprocessed.etc)
        EEG_preprocessed.etc = struct();
    end

    EEG_preprocessed.etc.real_bids_subject = bidsSubject;
    EEG_preprocessed.etc.session_label = bidsSession;
    EEG_preprocessed.etc.processing_subject_label = ...
        processingSubjectLabel;
    EEG_preprocessed.etc.preprocessing_status_for_amica = ...
        char(sourceMap.PreprocessingStatus(rowIdx));
    EEG_preprocessed.etc.preprocessing_qc_status_for_amica = ...
        char(sourceMap.PreprocessingQCStatus(rowIdx));
    EEG_preprocessed.etc.amica_input_signature = ...
        char(expectedAMICAInputSignature);
    EEG_preprocessed.etc.amica_stage_signatures = stageSignatures;
    EEG_preprocessed.etc.amica_legacy_match_signature = char(legacySignature);
    EEG_preprocessed.etc.amica_config_signature = ...
        char(amicaConfigSignature);
    EEG_preprocessed.etc.amica_config_signature_version = ...
        'HipExo_amica_scientific_config_v2';

    [ALLEEG, EEG_preprocessed, CURRENTSET] = ...
        eeg_store(ALLEEG, EEG_preprocessed, 1);

    try
        hipexo.mod_bemobil_process_all_AMICA( ...
            ALLEEG, ...
            EEG_preprocessed, ...
            CURRENTSET, ...
            processingSubjectLabel, ...
            bemobil_config, ...
            rowForceRecomputeAMICA);

    catch ME
        fprintf(2, ...
            '\nAMICA / DIPFIT / ICLabel failed for %s.\n%s\n', ...
            processingSubjectFolder, ...
            getReport(ME, 'extended', 'hyperlinks', 'off'));

        outputExistsAfterFailure = [ ...
            isfile(amicaSetPath), ...
            isfile(dipfittedSetPath), ...
            isfile(preprocessedICASetPath), ...
            isfile(cleanedICASetPath) ...
        ];

        sourceMap = set_amica_failure( ...
            sourceMap, ...
            sessionRows, ...
            "failed", ...
            string(ME.message));

        sourceMap.AMICASetPath(sessionRows) = ...
            existing_file_path(amicaSetPath);
        sourceMap.DipfittedSetPath(sessionRows) = ...
            existing_file_path(dipfittedSetPath);
        sourceMap.PreprocessedICASetPath(sessionRows) = ...
            existing_file_path(preprocessedICASetPath);
        sourceMap.CleanedICASetPath(sessionRows) = ...
            existing_file_path(cleanedICASetPath);
        sourceMap.AMICAOutputStatus(sessionRows) = ...
            "run_failed__" + ...
            describe_output_status(outputExistsAfterFailure);

        writetable(sourceMap, mappingFile);
        clear EEG_preprocessed ALLEEG EEG CURRENTSET
        continue;
    end

    outputExistsAfterRun = [ ...
        isfile(amicaSetPath), ...
        isfile(dipfittedSetPath), ...
        isfile(preprocessedICASetPath), ...
        isfile(cleanedICASetPath) ...
    ];

    finalOutputStatus = ...
        describe_output_status(outputExistsAfterRun);

    if all(outputExistsAfterRun)
        finalProvenanceOK = ...
            verify_amica_output_provenance( ...
                preprocessedICASetPath, ...
                legacySignature, stageSignatures, 'prefinal') && ...
            verify_amica_output_provenance( ...
                cleanedICASetPath, ...
                legacySignature, stageSignatures, 'cleaned');

        if ~finalProvenanceOK
            finalOutputStatus = "output_provenance_mismatch";
        end
    end

    sourceMap.AMICADate(sessionRows) = current_timestamp();
    sourceMap.AMICASetPath(sessionRows) = ...
        existing_file_path(amicaSetPath);
    sourceMap.DipfittedSetPath(sessionRows) = ...
        existing_file_path(dipfittedSetPath);
    sourceMap.PreprocessedICASetPath(sessionRows) = ...
        existing_file_path(preprocessedICASetPath);
    sourceMap.CleanedICASetPath(sessionRows) = ...
        existing_file_path(cleanedICASetPath);
    sourceMap.AMICAOutputStatus(sessionRows) = finalOutputStatus;
    sourceMap.AMICAInputSignature(sessionRows) = ...
        expectedAMICAInputSignature;
    sourceMap.AMICAPrefinalSignature(sessionRows) = stageSignatures.prefinal;
    sourceMap.AMICAConfigSignature(sessionRows) = ...
        amicaConfigSignature;

    if finalOutputStatus == "complete_outputs_verified"
        sourceMap.AMICAStatus(sessionRows) = "completed";
        sourceMap.AMICANotes(sessionRows) = "";

    elseif finalOutputStatus == "output_provenance_mismatch"
        sourceMap.AMICAStatus(sessionRows) = ...
            "failed_output_provenance_mismatch";
        sourceMap.AMICANotes(sessionRows) = ...
            "Final outputs do not contain the current AMICA input signature.";
        fprintf(2, ...
            'Final output provenance failed: %s\n', ...
            processingSubjectFolder);

    else
        sourceMap.AMICAStatus(sessionRows) = ...
            "partial_outputs_missing";
        sourceMap.AMICANotes(sessionRows) = ...
            "AMICA processing returned, but one or more expected outputs are missing.";
        fprintf(2, ...
            'Incomplete outputs for %s: %s\n', ...
            processingSubjectFolder, ...
            finalOutputStatus);
    end

    writetable(sourceMap, mappingFile);

    clear EEG_preprocessed ALLEEG EEG CURRENTSET
    hipexo.hide_all_figures();
end

%  FINAL REPORT

statusValues = sourceMap.AMICAStatus( ...
    strlength(sourceMap.AMICAStatus) > 0);

uniqueStatusValues = unique(statusValues, 'stable');

if isempty(uniqueStatusValues)
else
    for statusIndex = 1:numel(uniqueStatusValues)
        thisStatus = uniqueStatusValues(statusIndex);
    end
end

% Restore normal MATLAB/EEGLAB figure behavior after batch processing.
set(0, 'ShowHiddenHandles', 'off');
set(0, 'DefaultFigureVisible', 'on');
set(groot, 'DefaultFigureVisible', 'on');

%  LOCAL FUNCTIONS

function T = ensure_numeric_column(T, columnName)

    if ~ismember(columnName, T.Properties.VariableNames)
        error('Table is missing required column: %s', columnName);
    end

    if isnumeric(T.(columnName))
        return;
    end

    if islogical(T.(columnName))
        T.(columnName) = double(T.(columnName));
    else
        T.(columnName) = str2double(string(T.(columnName)));
    end
end

function T = ensure_string_column(T, columnName)

    if ~ismember(columnName, T.Properties.VariableNames)
        T.(columnName) = strings(height(T), 1);
    else
        T.(columnName) = string(T.(columnName));
        T.(columnName)(ismissing(T.(columnName))) = "";
    end
end

function [ ...
    amicaSetPath, ...
    dipfittedSetPath, ...
    preprocessedICASetPath, ...
    cleanedICASetPath ...
] = canonical_amica_paths( ...
    bemobil_config, ...
    processingSubjectFolder)

    spatialOutputFolder = fullfile( ...
        bemobil_config.study_folder, ...
        bemobil_config.spatial_filters_folder, ...
        bemobil_config.spatial_filters_folder_AMICA, ...
        processingSubjectFolder);

    singleSubjectOutputFolder = fullfile( ...
        bemobil_config.study_folder, ...
        bemobil_config.single_subject_analysis_folder, ...
        processingSubjectFolder);

    amicaSetPath = fullfile( ...
        spatialOutputFolder, ...
        [processingSubjectFolder '_' ...
         bemobil_config.amica_filename_output]);

    dipfittedSetPath = fullfile( ...
        spatialOutputFolder, ...
        [processingSubjectFolder '_' ...
         bemobil_config.dipfitted_filename]);

    preprocessedICASetPath = fullfile( ...
        singleSubjectOutputFolder, ...
        [processingSubjectFolder '_' ...
         bemobil_config.preprocessed_and_ICA_filename]);

    cleanedICASetPath = fullfile( ...
        singleSubjectOutputFolder, ...
        [processingSubjectFolder '_' ...
         bemobil_config.single_subject_cleaned_ICA_filename]);
end

function pathValue = existing_file_path(filePath)

    if isfile(filePath)
        pathValue = string(filePath);
    else
        pathValue = "";
    end
end

function outputStatus = describe_output_status(outputExists)

    outputNames = [ ...
        "AMICA", ...
        "dipfitted", ...
        "preprocessed_and_ICA", ...
        "cleaned_with_ICA" ...
    ];

    if all(outputExists)
        outputStatus = "complete_outputs_verified";
        return;
    end

    missingNames = outputNames(~outputExists);
    outputStatus = "missing_" + join(missingNames, "_");
end

function [rankValue, valid] = get_rank_metadata(EEG)

    rankValue = NaN;
    valid = false;

    if ~isfield(EEG, 'etc') || ~isfield(EEG.etc, 'rank')
        return;
    end

    if isnumeric(EEG.etc.rank) || islogical(EEG.etc.rank)
        if isscalar(EEG.etc.rank)
            rankValue = double(EEG.etc.rank);
        end
    else
        parsedRank = str2double(string(EEG.etc.rank));

        if isscalar(parsedRank)
            rankValue = parsedRank;
        end
    end

    valid = ...
        isfinite(rankValue) && ...
        rankValue >= 1 && ...
        rankValue <= EEG.nbchan && ...
        abs(rankValue - round(rankValue)) < 1e-6;
end

function T = set_amica_failure(T, rows, statusValue, notesValue)

    T.AMICAStatus(rows) = string(statusValue);
    T.AMICADate(rows) = current_timestamp();
    T.AMICANotes(rows) = string(notesValue);
end

function timestamp = current_timestamp()

    timestamp = string(datetime( ...
        'now', ...
        'Format', ...
        'yyyy-MM-dd HH:mm:ss'));
end

function ok = verify_amica_output_provenance(setPath, legacySignature, stages, stageName)
ok = false;
if ~isfile(setPath), return; end
try
    [folder, base, ext] = fileparts(char(setPath));
    EEGinfo = pop_loadset('filename', [base ext], 'filepath', folder);
    if ~isnumeric(EEGinfo.data) || isempty(EEGinfo.data) || ...
            numel(EEGinfo.data) ~= double(EEGinfo.nbchan)*double(EEGinfo.pnts)*double(EEGinfo.trials)
        return;
    end
    ok = hipexo.amica_stage_matches(EEGinfo, stages, stageName, legacySignature);
catch
    ok = false;
end
end

