% GOAL
%   Process all selected walking XDFs for one participant, or all participants,
%   from GRF extraction through gait-event mapping and subject concatenation.
%
% INPUT
%   output_data/bemobil_import_table.csv
%   Raw XDF recordings selected by DoImport and the Step 01/02 QC gates.
%
% APPROACH
%   1. Select official run-001/run-002 XDFs from the import-control table.
%   2. Process each XDF in true EEG-LSL chronological order.
%   3. Run GRF extraction, gait-event detection, and GRF-to-EEG mapping.
%   4. Verify/reuse outputs using provenance signatures when valid.
%   5. Concatenate all completed recordings for each participant.
%
% OUTPUT
%   GRF_segmentation_output/sub-*/GRF/*
%   GRF_segmentation_output/sub-*/EEG_with_GRF_events/*
%   2_raw-EEGLAB/subject-level/*_all_sessions_500Hz_with_GRF_events.set
%   Per-subject batch-status CSV files.
%
% USED BY
%   step04_check_grf_gait_cycles.m and the later EEG preprocessing pipeline.

function batchStatus = step03_process_subject_grf_eeg(subjectFolder, varargin)

if nargin < 1
    subjectFolder = "";
end

% Load Step 03 defaults before parsing optional overrides.
runFolder = fileparts(mfilename('fullpath'));
scriptsRoot = fileparts(runFolder);
internalFolder = fullfile(scriptsRoot, 'internal');

addpath(scriptsRoot, '-begin');
addpath(fullfile(scriptsRoot, 'config'), '-begin');

P = project_paths();
cfg = config_step03_04_grf_processing();

parser = inputParser;

addOptional(parser, 'subjectFolder', subjectFolder, ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));

addParameter(parser, 'ForceReprocess', cfg.batch.forceReprocess, ...
    @(x) islogical(x) && isscalar(x));

% Stage-specific recomputation switches. Dependencies cascade forward:
% extraction -> gait detection -> EEG mapping -> subject concatenation.
% Therefore ForceGaitDetection=true also refreshes mapping and the merged
% event structure, but it does not rerun GRF extraction.
addParameter(parser, 'ForceGRFExtraction', cfg.batch.forceGRFExtraction, ...
    @(x) islogical(x) && isscalar(x));

addParameter(parser, 'ForceGaitDetection', cfg.batch.forceGaitDetection, ...
    @(x) islogical(x) && isscalar(x));

addParameter(parser, 'ForceEEGMapping', cfg.batch.forceEEGMapping, ...
    @(x) islogical(x) && isscalar(x));

addParameter(parser, 'ForceConcatenation', cfg.batch.forceConcatenation, ...
    @(x) islogical(x) && isscalar(x));

addParameter(parser, 'ConcatenateSessions', cfg.batch.concatenateSessions, ...
    @(x) islogical(x) && isscalar(x));

addParameter(parser, 'AllowPartialSubject', cfg.batch.allowPartialSubject, ...
    @(x) islogical(x) && isscalar(x));

parse(parser, subjectFolder, varargin{:});

subjectFolder = char(string(parser.Results.subjectFolder));
forceReprocess = logical(parser.Results.ForceReprocess);
forceGRFExtraction = forceReprocess || ...
    logical(parser.Results.ForceGRFExtraction);
forceGaitDetection = forceReprocess || forceGRFExtraction || ...
    logical(parser.Results.ForceGaitDetection);
forceEEGMapping = forceReprocess || forceGaitDetection || ...
    logical(parser.Results.ForceEEGMapping);
forceConcatenation = forceReprocess || forceEEGMapping || ...
    logical(parser.Results.ForceConcatenation);
concatenateSessions = logical(parser.Results.ConcatenateSessions);
allowPartialSubject = logical(parser.Results.AllowPartialSubject);

expectedGRFExtractionVersion = ...
    "GRF_extraction_v2_strict_markers_2026-08-22";
expectedGaitEventVersion = ...
    "GRF_gait_events_v2_threshold_crossing_QC_2026-08-22";
expectedEEGMappingVersion = ...
    "GRF_to_EEG_mapping_v2_provenance_2026-08-22";

close all;

previousFigureVisibility = get(groot, 'DefaultFigureVisible');
set(groot, 'DefaultFigureVisible', 'off');

figureVisibilityCleanup = onCleanup( ...
    @() set(groot, 'DefaultFigureVisible', previousFigureVisibility)); %#ok<NASGU>

previousUnattendedValue = getenv('GRF_BATCH_UNATTENDED');
setenv('GRF_BATCH_UNATTENDED', '1');

unattendedCleanup = onCleanup( ...
    @() setenv('GRF_BATCH_UNATTENDED', previousUnattendedValue)); %#ok<NASGU>

rawDataFolder = P.rawDataFolder;
outputFolder = P.outputFolder;
grfSegmentationFolder = P.grfSegmentationFolder;
importTableFile = P.importTableFile;

extractScript = fullfile( ...
    internalFolder, ...
    'step03_extract_and_segment_grf_internal.m');

gaitEventScript = fullfile( ...
    internalFolder, ...
    'step03_detect_grf_gait_events_internal.m');

mapScript = fullfile( ...
    internalFolder, ...
    'step03_map_grf_events_to_eeg_internal.m');

requiredFiles = { ...
    extractScript, ...
    gaitEventScript, ...
    mapScript};

for iRequired = 1:numel(requiredFiles)
    if ~isfile(requiredFiles{iRequired})
        error('Cannot find required Step 03 internal file:\n%s', ...
            requiredFiles{iRequired});
    end
end

requiredFunctions = { ...
    'hipexo.detect_walking_intervals', ...
    'hipexo.detect_GRF_gait_events', ...
    'hipexo.file_signature', ...
    'hipexo.concatenate_subject_grf_eeg'};

for iRequired = 1:numel(requiredFunctions)
    if isempty(which(requiredFunctions{iRequired}))
        error('Required function is not available: %s', ...
            requiredFunctions{iRequired});
    end
end

if ~isfolder(rawDataFolder)
    error('Raw-data folder does not exist:\n%s', rawDataFolder);
end

if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

if ~isfolder(grfSegmentationFolder)
    mkdir(grfSegmentationFolder);
end

if ~isfile(importTableFile)
    error([ ...
        'The run-level import-control table does not exist:\n%s\n\n' ...
        'Run Step 01 and Step 02 first.'], ...
        importTableFile);
end

%% Run all subjects if no subject specified

if isempty(strtrim(subjectFolder))

    subjectFolders = discover_subject_folders(rawDataFolder);

    if isempty(subjectFolders)
        error('No subject folders containing eeg/*.xdf were found.');
    end

    batchStatus = table();

    for iSubject = 1:numel(subjectFolders)

        fprintf('Subject %d/%d: %s\n', ...
            iSubject, numel(subjectFolders), subjectFolders(iSubject));

        try
            currentStatus = step03_process_subject_grf_eeg( ...
                char(subjectFolders(iSubject)), ...
                'ForceReprocess', forceReprocess, ...
                'ForceGRFExtraction', forceGRFExtraction, ...
                'ForceGaitDetection', forceGaitDetection, ...
                'ForceEEGMapping', forceEEGMapping, ...
                'ForceConcatenation', forceConcatenation, ...
                'ConcatenateSessions', concatenateSessions, ...
                'AllowPartialSubject', allowPartialSubject);

            if isempty(batchStatus)
                batchStatus = currentStatus;
            else
                batchStatus = [batchStatus; currentStatus]; %#ok<AGROW>
            end

        catch subjectError
            fprintf(2, ...
                '\nSubject failed:\n%s\nReason:\n%s\n', ...
                subjectFolders(iSubject), ...
                subjectError.message);

            failureRow = failed_subject_status_row_local( ...
                subjectFolders(iSubject), ...
                subjectError.message);

            if isempty(batchStatus)
                batchStatus = failureRow;
            else
                batchStatus = [batchStatus; failureRow]; %#ok<AGROW>
            end
        end
    end

    if isempty(batchStatus)
        error('No subject produced a valid batch-status table.');
    end

    return;
end

%% Subject validation

subjectFolder = char(string(subjectFolder));

if ~isfolder(subjectFolder)
    error('Subject folder does not exist:\n%s', subjectFolder);
end

xdfDirectoryEntries = dir(fullfile( ...
    subjectFolder, '**', 'eeg', '*.xdf'));

if isempty(xdfDirectoryEntries)
    error('No XDF files found below:\n%s', subjectFolder);
end

allXDFPaths = strings(numel(xdfDirectoryEntries), 1);

for iFile = 1:numel(xdfDirectoryEntries)
    allXDFPaths(iFile) = string(fullfile( ...
        xdfDirectoryEntries(iFile).folder, ...
        xdfDirectoryEntries(iFile).name));
end

allXDFPaths = unique(allXDFPaths, 'stable');

xdfPaths = select_subject_xdf_from_import_table( ...
    subjectFolder, ...
    allXDFPaths, ...
    importTableFile, ...
    [1 2]);

if isempty(xdfPaths)
    error([ ...
        'No XDF files remained after applying DoImport/QC/run gates.']);
end

excludedXDFCount = numel(allXDFPaths) - numel(xdfPaths);

%% TRUE LSL ORDER

[xdfPaths, ...
 eegFirstLSLTime, ...
 eegLastLSLTime, ...
 grfFirstLSLTime, ...
 grfLastLSLTime] = ...
    sort_xdf_by_true_eeg_lsl_time(xdfPaths);

%% Subject token

subjectTokens = strings(numel(xdfPaths), 1);

for iFile = 1:numel(xdfPaths)
    [~, currentBaseName] = fileparts(char(xdfPaths(iFile)));
    subjectTokens(iFile) = extract_subject_token(currentBaseName);
end

validSubjectTokens = unique( ...
    subjectTokens(strlength(subjectTokens) > 0));

if numel(validSubjectTokens) ~= 1
    error('Selected files do not resolve to exactly one subject.');
end

subjectToken = validSubjectTokens(1);

subjectOutputName = "sub-" + regexprep( ...
    subjectToken, ...
    '[^a-zA-Z0-9_-]', ...
    '_');

subjectOutputFolder = fullfile( ...
    grfSegmentationFolder, ...
    char(subjectOutputName));

subjectGRFOutputFolder = fullfile( ...
    subjectOutputFolder, ...
    'GRF');

subjectEEGOutputFolder = fullfile( ...
    subjectOutputFolder, ...
    'EEG_with_GRF_events');

if ~isfolder(subjectOutputFolder)
    mkdir(subjectOutputFolder);
end

if ~isfolder(subjectGRFOutputFolder)
    mkdir(subjectGRFOutputFolder);
end

if ~isfolder(subjectEEGOutputFolder)
    mkdir(subjectEEGOutputFolder);
end

batchLogFile = fullfile( ...
    subjectOutputFolder, ...
    [char(subjectOutputName) '_GRF_EEG_batch_status.csv']);

%% File/session information

sessionNames = strings(numel(xdfPaths), 1);
xdfNames = strings(numel(xdfPaths), 1);

for iFile = 1:numel(xdfPaths)

    [eegFolder, currentName, currentExtension] = ...
        fileparts(char(xdfPaths(iFile)));

    [sessionFolder, ~] = fileparts(eegFolder);
    [~, currentSessionName] = fileparts(sessionFolder);

    sessionNames(iFile) = string(currentSessionName);
    xdfNames(iFile) = string([currentName currentExtension]);
end

eegLSLDurationSec = eegLastLSLTime - eegFirstLSLTime;
grfLSLDurationSec = grfLastLSLTime - grfFirstLSLTime;

grfEEGLSLOverlapSec = max( ...
    0, ...
    min(eegLastLSLTime, grfLastLSLTime) - ...
    max(eegFirstLSLTime, grfFirstLSLTime));

%% Batch table

nFiles = numel(xdfPaths);

batchStatus = table( ...
    repmat(subjectOutputName, nFiles, 1), ...
    sessionNames, ...
    xdfPaths, ...
    eegFirstLSLTime, ...
    eegLastLSLTime, ...
    eegLSLDurationSec, ...
    grfFirstLSLTime, ...
    grfLastLSLTime, ...
    grfLSLDurationSec, ...
    grfEEGLSLOverlapSec, ...
    repmat("pending", nFiles, 1), ...
    repmat("pending", nFiles, 1), ...
    repmat("pending", nFiles, 1), ...
    repmat("pending", nFiles, 1), ...
    strings(nFiles, 1), ...
    strings(nFiles, 1), ...
    strings(nFiles, 1), ...
    strings(nFiles, 1), ...
    nan(nFiles, 1), ...
    nan(nFiles, 1), ...
    nan(nFiles, 1), ...
    nan(nFiles, 1), ...
    nan(nFiles, 1), ...
    nan(nFiles, 1), ...
    nan(nFiles, 1), ...
    nan(nFiles, 1), ...
    nan(nFiles, 1), ...
    nan(nFiles, 1), ...
    nan(nFiles, 1), ...
    nan(nFiles, 1), ...
    nan(nFiles, 1), ...
    repmat("pending", nFiles, 1), ...
    strings(nFiles, 1), ...
    strings(nFiles, 1), ...
    strings(nFiles, 1), ...
    'VariableNames', { ...
        'Subject', ...
        'SessionFolder', ...
        'XDFPath', ...
        'EEG_LSL_Start', ...
        'EEG_LSL_End', ...
        'EEG_LSL_DurationSec', ...
        'GRF_LSL_Start', ...
        'GRF_LSL_End', ...
        'GRF_LSL_DurationSec', ...
        'GRF_EEG_LSL_OverlapSec', ...
        'OverallStatus', ...
        'GRFExtractionStatus', ...
        'GaitEventStatus', ...
        'EEGMappingStatus', ...
        'GRFStreamFile', ...
        'GaitEventFile', ...
        'EEGSetFile', ...
        'MappingCSVFile', ...
        'MappedEventCount', ...
        'ExcludedEventCount', ...
        'FirstGRFEventSample', ...
        'FirstGRFEventLSLTime', ...
        'FirstMappedEEGSample', ...
        'FirstMatchedEEGLSLTime', ...
        'LastGRFEventSample', ...
        'LastGRFEventLSLTime', ...
        'LastMappedEEGSample', ...
        'LastMatchedEEGLSLTime', ...
        'MedianAbsMappingErrorMs', ...
        'MaxAbsMappingErrorMs', ...
        'EEGBoundaryCount', ...
        'SubjectMergeStatus', ...
        'SubjectMergedSetFile', ...
        'CompletedAt', ...
        'ErrorMessage'});

clear_batch_environment;

environmentCleanup = onCleanup(@clear_batch_environment); %#ok<NASGU>

%% Process XDFs

for iFile = 1:nFiles

    currentXDF = char(xdfPaths(iFile));

    [~, currentBaseName] = fileparts(currentXDF);

    safeBaseName = regexprep( ...
        currentBaseName, ...
        '[^a-zA-Z0-9_-]', ...
        '_');

    grfStreamFile = fullfile( ...
        subjectGRFOutputFolder, ...
        [safeBaseName '_GRF_stream.mat']);

    gaitEventFile = fullfile( ...
        subjectGRFOutputFolder, ...
        [safeBaseName '_GRF_gait_events.mat']);

    eegSetFile = fullfile( ...
        subjectEEGOutputFolder, ...
        [currentBaseName '_EEG_500Hz_with_GRF_events.set']);

    mappingCSVFile = fullfile( ...
        subjectEEGOutputFolder, ...
        [currentBaseName '_GRF_to_EEG_event_mapping.csv']);

    gapCSVFile = fullfile( ...
        subjectEEGOutputFolder, ...
        [currentBaseName '_EEG_timestamp_gaps.csv']);

    batchStatus.GRFStreamFile(iFile) = string(grfStreamFile);
    batchStatus.GaitEventFile(iFile) = string(gaitEventFile);
    batchStatus.EEGSetFile(iFile) = string(eegSetFile);
    batchStatus.MappingCSVFile(iFile) = string(mappingCSVFile);

    fprintf('  File %d/%d: %s\n', iFile, nFiles, currentXDF);

    try

        %% GRF extraction

        reuseGRF = false;
        reuseGRFReason = "output_missing_or_forced";

        if isfile(grfStreamFile) && ~forceGRFExtraction
            [reuseGRF, reuseGRFReason] = ...
                verify_grf_reuse_local( ...
                    grfStreamFile, ...
                    currentXDF, ...
                    expectedGRFExtractionVersion);
        end

        if reuseGRF

            batchStatus.GRFExtractionStatus(iFile) = ...
                "reused_verified";

        else

            if isfile(grfStreamFile) && ~forceGRFExtraction
                fprintf('GRF extraction output is stale: %s\n', ...
                    reuseGRFReason);
            end

            setenv('GRF_BATCH_XDF_FILE', currentXDF);
            setenv( ...
                'GRF_BATCH_GRF_OUTPUT_FOLDER', ...
                subjectGRFOutputFolder);

            run_script_isolated(extractScript);

            if ~isfile(grfStreamFile)
                error('GRF stream was not created:\n%s', grfStreamFile);
            end

            batchStatus.GRFExtractionStatus(iFile) = "completed";
        end

        close all;

        %% Gait events

        reuseGait = false;
        reuseGaitReason = "output_missing_or_forced";

        if isfile(gaitEventFile) && ~forceGaitDetection
            [reuseGait, reuseGaitReason] = ...
                verify_gait_reuse_local( ...
                    gaitEventFile, ...
                    grfStreamFile, ...
                    expectedGaitEventVersion);
        end

        if reuseGait

            batchStatus.GaitEventStatus(iFile) = ...
                "reused_verified";

        else

            if isfile(gaitEventFile) && ~forceGaitDetection
                fprintf('Gait-event output is stale: %s\n', ...
                    reuseGaitReason);
            end

            setenv( ...
                'GRF_BATCH_GRF_STREAM_FILE', ...
                grfStreamFile);

            setenv( ...
                'GRF_BATCH_GRF_OUTPUT_FOLDER', ...
                subjectGRFOutputFolder);

            run_script_isolated(gaitEventScript);

            if ~isfile(gaitEventFile)
                error('Gait-event file was not created:\n%s', gaitEventFile);
            end

            batchStatus.GaitEventStatus(iFile) = "completed";
        end

        close all;

        %% Map GRF → EEG

        mappingOutputsComplete = ...
            isfile(eegSetFile) && ...
            isfile(mappingCSVFile) && ...
            isfile(gapCSVFile);

        reuseMapping = false;
        reuseMappingReason = "output_missing_or_forced";

        if mappingOutputsComplete && ~forceEEGMapping
            [reuseMapping, reuseMappingReason] = ...
                verify_mapping_reuse_local( ...
                    eegSetFile, ...
                    gaitEventFile, ...
                    currentXDF, ...
                    expectedEEGMappingVersion);
        end

        if reuseMapping

            batchStatus.EEGMappingStatus(iFile) = ...
                "reused_verified";

        else

            if mappingOutputsComplete && ~forceEEGMapping
                fprintf('EEG-mapping output is stale: %s\n', ...
                    reuseMappingReason);
            end

            setenv('GRF_BATCH_EVENT_FILE', gaitEventFile);

            setenv( ...
                'GRF_BATCH_GRF_OUTPUT_FOLDER', ...
                subjectGRFOutputFolder);

            setenv( ...
                'GRF_BATCH_EEG_OUTPUT_FOLDER', ...
                subjectEEGOutputFolder);

            run_script_isolated(mapScript);

            mappingOutputsComplete = ...
                isfile(eegSetFile) && ...
                isfile(mappingCSVFile) && ...
                isfile(gapCSVFile);

            if ~mappingOutputsComplete
                error('GRF-to-EEG mapping outputs are incomplete.');
            end

            batchStatus.EEGMappingStatus(iFile) = "completed";
        end

        %% Read mapping evidence

        mappingTable = readtable( ...
            mappingCSVFile, ...
            'TextType', 'string', ...
            'VariableNamingRule', 'preserve');

        requiredMappingAuditVariables = { ...
            'MappingStatus', ...
            'GRFSample', ...
            'LSLTime', ...
            'EEGSample', ...
            'MatchedEEGLSLTime', ...
            'MappingErrorMs'};

        missingMappingAuditVariables = ...
            requiredMappingAuditVariables( ...
            ~ismember( ...
                requiredMappingAuditVariables, ...
                mappingTable.Properties.VariableNames));

        if ~isempty(missingMappingAuditVariables)
            error([ ...
                'Mapping CSV is missing fields: %s\n' ...
                'Re-run this XDF with the current Step 03 GRF-to-EEG mapper.'], ...
                strjoin(missingMappingAuditVariables, ', '));
        end

        mappingStatus = ...
            lower(strtrim(string(mappingTable.MappingStatus)));

        mappedRows = mappingStatus == "mapped";

        batchStatus.MappedEventCount(iFile) = sum(mappedRows);
        batchStatus.ExcludedEventCount(iFile) = sum(~mappedRows);

        if ~any(mappedRows)
            error([ ...
                'GRF-to-EEG mapping produced zero mapped gait events. ' ...
                'This recording cannot enter subject concatenation.']);
        end

        if any(mappedRows)

            mappedAuditTable = mappingTable(mappedRows, :);

            mappedAuditTable.GRFSample = ...
                numeric_column_local(mappedAuditTable.GRFSample);

            mappedAuditTable.LSLTime = ...
                numeric_column_local(mappedAuditTable.LSLTime);

            mappedAuditTable.EEGSample = ...
                numeric_column_local(mappedAuditTable.EEGSample);

            mappedAuditTable.MatchedEEGLSLTime = ...
                numeric_column_local( ...
                mappedAuditTable.MatchedEEGLSLTime);

            mappedAuditTable.MappingErrorMs = ...
                numeric_column_local( ...
                mappedAuditTable.MappingErrorMs);

            mappedAuditTable = ...
                sortrows(mappedAuditTable, 'LSLTime');

            firstMappedRow = mappedAuditTable(1, :);
            lastMappedRow = mappedAuditTable(end, :);

            batchStatus.FirstGRFEventSample(iFile) = ...
                firstMappedRow.GRFSample;

            batchStatus.FirstGRFEventLSLTime(iFile) = ...
                firstMappedRow.LSLTime;

            batchStatus.FirstMappedEEGSample(iFile) = ...
                firstMappedRow.EEGSample;

            batchStatus.FirstMatchedEEGLSLTime(iFile) = ...
                firstMappedRow.MatchedEEGLSLTime;

            batchStatus.LastGRFEventSample(iFile) = ...
                lastMappedRow.GRFSample;

            batchStatus.LastGRFEventLSLTime(iFile) = ...
                lastMappedRow.LSLTime;

            batchStatus.LastMappedEEGSample(iFile) = ...
                lastMappedRow.EEGSample;

            batchStatus.LastMatchedEEGLSLTime(iFile) = ...
                lastMappedRow.MatchedEEGLSLTime;

            absoluteMappingErrorMs = ...
                abs(mappedAuditTable.MappingErrorMs);

            absoluteMappingErrorMs = ...
                absoluteMappingErrorMs( ...
                isfinite(absoluteMappingErrorMs));

            if ~isempty(absoluteMappingErrorMs)

                batchStatus.MedianAbsMappingErrorMs(iFile) = ...
                    median(absoluteMappingErrorMs);

                batchStatus.MaxAbsMappingErrorMs(iFile) = ...
                    max(absoluteMappingErrorMs);
            end
        end

        gapTable = readtable( ...
            gapCSVFile, ...
            'TextType', 'string', ...
            'VariableNamingRule', 'preserve');

        batchStatus.EEGBoundaryCount(iFile) = height(gapTable);

        batchStatus.OverallStatus(iFile) = "completed";
        batchStatus.CompletedAt(iFile) = current_time_text;
        batchStatus.ErrorMessage(iFile) = "";

    catch currentError

        batchStatus.OverallStatus(iFile) = "failed";
        batchStatus.CompletedAt(iFile) = current_time_text;
        batchStatus.ErrorMessage(iFile) = sanitize_error_message_local(currentError.message);

        fprintf(2, ...
            '\nBatch result: FAILED\n%s\n', ...
            currentError.message);
    end

    clear_batch_environment;
    close all;

    writetable(batchStatus, batchLogFile);
end

%% Subject-level concatenation

nCompleted = sum(batchStatus.OverallStatus == "completed");
nFailed = sum(batchStatus.OverallStatus == "failed");

if ~concatenateSessions

    batchStatus.SubjectMergeStatus(:) = "not_requested";

elseif nFailed > 0 && ~allowPartialSubject

    batchStatus.SubjectMergeStatus(:) = ...
        "blocked_failed_input";

else

    try

        [subjectMergedSetFile, ~] = ...
            hipexo.concatenate_subject_grf_eeg( ...
                subjectOutputFolder, ...
                'ForceReprocess', forceConcatenation, ...
                'AllowPartialSubject', allowPartialSubject);

        batchStatus.SubjectMergeStatus(:) = "completed";

        batchStatus.SubjectMergedSetFile(:) = ...
            string(subjectMergedSetFile);

    catch mergeError

        batchStatus.SubjectMergeStatus(:) = "failed";

        fprintf(2, ...
            '\nSubject concatenation failed:\n%s\n', ...
            mergeError.message);
    end
end

writetable(batchStatus, batchLogFile);

fprintf('Subject %s finished: %d/%d completed, %d failed.\n', ...
    subjectOutputName, nCompleted, nFiles, nFailed);

end

%% ------------------------------------------------------------
function run_script_isolated(scriptFile)
run(scriptFile);
end

function clear_batch_environment

setenv('GRF_BATCH_XDF_FILE', '');
setenv('GRF_BATCH_GRF_STREAM_FILE', '');
setenv('GRF_BATCH_EVENT_FILE', '');
setenv('GRF_BATCH_GRF_OUTPUT_FOLDER', '');
setenv('GRF_BATCH_EEG_OUTPUT_FOLDER', '');

end

function subjectFolders = discover_subject_folders(rawDataFolder)

directoryEntries = dir(rawDataFolder);
directoryEntries = directoryEntries([directoryEntries.isdir]);

directoryNames = string({directoryEntries.name});

keepDirectory = ...
    directoryNames ~= "." & ...
    directoryNames ~= "..";

directoryEntries = directoryEntries(keepDirectory);

subjectFolders = strings(0, 1);

for iDirectory = 1:numel(directoryEntries)

    currentFolder = fullfile( ...
        directoryEntries(iDirectory).folder, ...
        directoryEntries(iDirectory).name);

    xdfEntries = dir(fullfile( ...
        currentFolder, ...
        '**', ...
        'eeg', ...
        '*.xdf'));

    if ~isempty(xdfEntries)
        subjectFolders(end + 1, 1) = string(currentFolder); %#ok<AGROW>
    end
end

subjectFolders = sort(subjectFolders);

end

function subjectToken = extract_subject_token(fileName)

subjectToken = "";

match = regexpi( ...
    fileName, ...
    '^sub-(.+?)(?:_day\d+|_ses-)', ...
    'tokens', ...
    'once');

if ~isempty(match)
    subjectToken = string(match{1});
end

end

function [sortedXDFPaths, ...
          firstLSLTime, ...
          lastLSLTime, ...
          grfFirstLSLTime, ...
          grfLastLSLTime] = ...
        sort_xdf_by_true_eeg_lsl_time(xdfPaths)

if exist('load_xdf', 'file') ~= 2
    error('load_xdf is not available.');
end

xdfPaths = string(xdfPaths(:));
nFiles = numel(xdfPaths);

firstLSLTime = nan(nFiles, 1);
lastLSLTime = nan(nFiles, 1);
grfFirstLSLTime = nan(nFiles, 1);
grfLastLSLTime = nan(nFiles, 1);

for iFile = 1:nFiles

    [firstLSLTime(iFile), ...
     lastLSLTime(iFile), ...
     grfFirstLSLTime(iFile), ...
     grfLastLSLTime(iFile)] = ...
        read_true_eeg_grf_lsl_bounds_from_xdf( ...
        xdfPaths(iFile));
end

if numel(unique(firstLSLTime)) ~= nFiles
    error('Duplicate EEG first LSL timestamps found.');
end

[firstLSLTime, order] = sort(firstLSLTime, 'ascend');

sortedXDFPaths = xdfPaths(order);
lastLSLTime = lastLSLTime(order);
grfFirstLSLTime = grfFirstLSLTime(order);
grfLastLSLTime = grfLastLSLTime(order);

end

function [firstLSLTime, ...
          lastLSLTime, ...
          grfFirstLSLTime, ...
          grfLastLSLTime] = ...
        read_true_eeg_grf_lsl_bounds_from_xdf(xdfPath)

[streams, ~] = load_xdf(char(xdfPath));

nStreams = numel(streams);

streamName = strings(nStreams, 1);
streamType = strings(nStreams, 1);
nominalSrate = nan(nStreams, 1);
channelCount = nan(nStreams, 1);
sampleCount = nan(nStreams, 1);

for iStream = 1:nStreams

    currentStream = streams{iStream};

    streamName(iStream) = ...
        batch_xdf_stream_text_field(currentStream, 'name');

    streamType(iStream) = ...
        batch_xdf_stream_text_field(currentStream, 'type');

    nominalSrate(iStream) = ...
        batch_xdf_stream_nominal_srate(currentStream);

    if isfield(currentStream, 'time_series') && ...
            isnumeric(currentStream.time_series) && ...
            isfield(currentStream, 'time_stamps')

        currentData = currentStream.time_series;
        currentTimestamps = currentStream.time_stamps;

        sampleCount(iStream) = numel(currentTimestamps);

        if size(currentData, 2) == sampleCount(iStream)
            channelCount(iStream) = size(currentData, 1);

        elseif size(currentData, 1) == sampleCount(iStream)
            channelCount(iStream) = size(currentData, 2);
        end
    end
end

candidateMask = ...
    strcmpi(streamName, "LiveAmpSN-102108-1139") & ...
    channelCount >= 64 & ...
    channelCount <= 80 & ...
    abs(nominalSrate - 500) <= 1;

candidateIndices = find(candidateMask);

if isempty(candidateIndices)

    candidateMask = ...
        channelCount >= 64 & ...
        channelCount <= 80 & ...
        abs(nominalSrate - 500) <= 1 & ...
        (contains(lower(streamType), 'eeg') | ...
         contains(lower(streamName), 'liveamp'));

    candidateIndices = find(candidateMask);
end

if numel(candidateIndices) ~= 1

    streamSummary = table( ...
        (1:nStreams)', ...
        streamName, ...
        streamType, ...
        nominalSrate, ...
        channelCount, ...
        sampleCount, ...
        'VariableNames', ...
        {'StreamIndex','Name','Type','NominalSrate', ...
         'ChannelCount','SampleCount'});

    disp(streamSummary);

    error('Could not uniquely identify EEG stream:\n%s', xdfPath);
end

eegStream = streams{candidateIndices(1)};
eegTimestamps = double(eegStream.time_stamps(:));

if isempty(eegTimestamps) || ...
        any(~isfinite(eegTimestamps)) || ...
        any(diff(eegTimestamps) <= 0)

    error('Invalid EEG LSL timestamps:\n%s', xdfPath);
end

firstLSLTime = eegTimestamps(1);
lastLSLTime = eegTimestamps(end);

isMarkerStream = ...
    contains(upper(streamName), "MARKER") | ...
    contains(upper(streamType), "MARKER");

grfCandidateMask = ...
    (strcmpi(strtrim(streamName), "GRF") | ...
     contains(upper(streamType), "FORCE")) & ...
    ~isMarkerStream;

grfCandidateIndices = find(grfCandidateMask);

if numel(grfCandidateIndices) ~= 1

    streamSummary = table( ...
        (1:nStreams)', ...
        streamName, ...
        streamType, ...
        nominalSrate, ...
        channelCount, ...
        sampleCount, ...
        'VariableNames', ...
        {'StreamIndex','Name','Type','NominalSrate', ...
         'ChannelCount','SampleCount'});

    disp(streamSummary);

    error('Could not uniquely identify GRF stream:\n%s', xdfPath);
end

grfStream = streams{grfCandidateIndices(1)};
grfTimestamps = double(grfStream.time_stamps(:));

if isempty(grfTimestamps) || ...
        any(~isfinite(grfTimestamps)) || ...
        any(diff(grfTimestamps) <= 0)

    error('Invalid GRF LSL timestamps:\n%s', xdfPath);
end

grfFirstLSLTime = grfTimestamps(1);
grfLastLSLTime = grfTimestamps(end);

end

function textValue = batch_xdf_stream_text_field(stream, fieldName)

textValue = "";

if ~isfield(stream, 'info') || ...
        ~isfield(stream.info, fieldName)
    return;
end

rawValue = stream.info.(fieldName);

while iscell(rawValue) && ~isempty(rawValue)
    rawValue = rawValue{1};
end

if isempty(rawValue)
    return;
end

textValue = string(rawValue);
textValue = textValue(1);

end

function nominalSrate = batch_xdf_stream_nominal_srate(stream)

nominalSrate = NaN;

if ~isfield(stream, 'info') || ...
        ~isfield(stream.info, 'nominal_srate')
    return;
end

rawValue = stream.info.nominal_srate;

while iscell(rawValue) && ~isempty(rawValue)
    rawValue = rawValue{1};
end

if isnumeric(rawValue)
    nominalSrate = double(rawValue(1));
else
    nominalSrate = str2double(string(rawValue));
end

end

function selectedXDFPaths = ...
        select_subject_xdf_from_import_table( ...
            subjectFolder, ...
            allXDFPaths, ...
            importTableFile, ...
            allowedRunNumbers)

opts = detectImportOptions( ...
    importTableFile, ...
    'FileType', 'text', ...
    'Delimiter', ',', ...
    'VariableNamingRule', 'preserve');

importTable = readtable(importTableFile, opts);

requiredVariables = { ...
    'XdfPath', ...
    'DoImport', ...
    'HasUsableEEG', ...
    'RunNumber'};

for iVariable = 1:numel(requiredVariables)

    if ~ismember( ...
            requiredVariables{iVariable}, ...
            importTable.Properties.VariableNames)

        error('Import table is missing %s.', ...
            requiredVariables{iVariable});
    end
end

importTable.XdfPath = string(importTable.XdfPath);
importTable.DoImport = numeric_column_local(importTable.DoImport);
importTable.HasUsableEEG = numeric_column_local(importTable.HasUsableEEG);
importTable.RunNumber = numeric_column_local(importTable.RunNumber);

normalizedSubjectFolder = normalize_path_text(subjectFolder);
normalizedTablePaths = normalize_path_text(importTable.XdfPath);

subjectPrefix = normalizedSubjectFolder + "/";

belongsToSubject = ...
    normalizedTablePaths == normalizedSubjectFolder | ...
    startsWith(normalizedTablePaths, subjectPrefix);

candidateRows = find(belongsToSubject);

if isempty(candidateRows)
    error('No import-table rows belong to subject.');
end

candidatePaths = importTable.XdfPath(candidateRows);
candidateNames = strings(numel(candidateRows), 1);

for iCandidate = 1:numel(candidateRows)

    [~, candidateBase, candidateExtension] = ...
        fileparts(char(candidatePaths(iCandidate)));

    candidateNames(iCandidate) = ...
        string([candidateBase candidateExtension]);
end

isOld = ~cellfun( ...
    @isempty, ...
    regexpi( ...
        cellstr(candidateNames), ...
        '_old\d*\.xdf$'));

isNonWalking = ...
    contains(lower(candidatePaths), "calibration") | ...
    contains(lower(candidatePaths), "maziarcheck");

hasAllowedRun = ismember( ...
    importTable.RunNumber(candidateRows), ...
    allowedRunNumbers);

isSelected = ...
    importTable.DoImport(candidateRows) == 1 & ...
    importTable.HasUsableEEG(candidateRows) == 1 & ...
    hasAllowedRun & ...
    ~isOld & ...
    ~isNonWalking;

selectedXDFPaths = unique( ...
    candidatePaths(isSelected), ...
    'stable');

normalizedAllPaths = normalize_path_text(allXDFPaths);
normalizedSelectedPaths = normalize_path_text(selectedXDFPaths);

missingSelectedPaths = ...
    ~ismember(normalizedSelectedPaths, normalizedAllPaths);

if any(missingSelectedPaths)

    error('Selected XDF path does not exist below subject folder:\n%s', ...
        strjoin( ...
        selectedXDFPaths(missingSelectedPaths), ...
        newline));
end

end

function normalizedPath = normalize_path_text(pathValue)

normalizedPath = replace(string(pathValue), "\", "/");
normalizedPath = regexprep(normalizedPath, '/+$', '');

end

function values = numeric_column_local(values)

if isnumeric(values)

    values = double(values);

elseif islogical(values)

    values = double(values);

else

    textValues = lower(strtrim(string(values)));

    values = str2double(textValues);

    values(ismember(textValues, ["true","yes"])) = 1;
    values(ismember(textValues, ["false","no"])) = 0;
end

end

function [canReuse, reason] = verify_grf_reuse_local( ...
        grfFile, sourceXDF, expectedVersion)

canReuse = false;
reason = "unverified_GRF_output";

try
    loaded = load(grfFile, 'processingInfo', 'xdfFile');

    if ~isfield(loaded, 'processingInfo') || ...
            ~isfield(loaded, 'xdfFile')
        reason = "missing_GRF_provenance";
        return;
    end

    info = loaded.processingInfo;
    requiredFields = {'version', 'source_xdf', 'source_xdf_signature'};

    if ~all(isfield(info, requiredFields))
        reason = "incomplete_GRF_provenance";
        return;
    end

    if string(info.version) ~= expectedVersion
        reason = "GRF_processing_version_changed";
        return;
    end

    if ~strcmpi(normalize_path_text(info.source_xdf), ...
            normalize_path_text(sourceXDF)) || ...
            ~strcmpi(normalize_path_text(loaded.xdfFile), ...
            normalize_path_text(sourceXDF))
        reason = "GRF_source_XDF_changed";
        return;
    end

    if string(info.source_xdf_signature) ~= ...
            hipexo.file_signature(sourceXDF)
        reason = "GRF_source_XDF_signature_changed";
        return;
    end

    canReuse = true;
    reason = "verified";

catch verificationError
    reason = "GRF_verification_error: " + ...
        sanitize_error_message_local(verificationError.message);
end

end

function [canReuse, reason] = verify_gait_reuse_local( ...
        gaitFile, grfFile, expectedVersion)

canReuse = false;
reason = "unverified_gait_output";

try
    loaded = load(gaitFile, 'processingInfo', 'allEventTable');

    if ~isfield(loaded, 'processingInfo') || ...
            ~isfield(loaded, 'allEventTable') || ...
            isempty(loaded.allEventTable)
        reason = "missing_or_empty_gait_provenance";
        return;
    end

    info = loaded.processingInfo;
    requiredFields = { ...
        'version', 'source_grf_file', 'source_grf_signature', ...
        'threshold_on', 'threshold_off', 'minimum_contact_sec', ...
        'maximum_contact_sec', 'minimum_stride_sec', 'review_status'};

    if ~all(isfield(info, requiredFields))
        reason = "incomplete_gait_provenance";
        return;
    end

    if string(info.version) ~= expectedVersion
        reason = "gait_processing_version_changed";
        return;
    end

    if ~strcmpi(normalize_path_text(info.source_grf_file), ...
            normalize_path_text(grfFile)) || ...
            string(info.source_grf_signature) ~= ...
            hipexo.file_signature(grfFile)
        reason = "gait_source_GRF_changed";
        return;
    end

    expectedParameters = [0.03 0.02 0.20 1.50 0.60];
    actualParameters = [ ...
        double(info.threshold_on), ...
        double(info.threshold_off), ...
        double(info.minimum_contact_sec), ...
        double(info.maximum_contact_sec), ...
        double(info.minimum_stride_sec)];

    if ~isequaln(actualParameters, expectedParameters)
        reason = "gait_detection_parameters_changed";
        return;
    end

    allowedReviewStatus = [ ...
        "VISUALLY_ACCEPTED", ...
        "AUTOMATED_QC_PASS_NOT_VISUALLY_REVIEWED"];

    if ~ismember(string(info.review_status), allowedReviewStatus)
        reason = "gait_review_status_not_accepted";
        return;
    end

    canReuse = true;
    reason = "verified";

catch verificationError
    reason = "gait_verification_error: " + ...
        sanitize_error_message_local(verificationError.message);
end

end

function [canReuse, reason] = verify_mapping_reuse_local( ...
        eegSetFile, gaitFile, sourceXDF, expectedVersion)

canReuse = false;
reason = "unverified_mapping_output";

try
    loaded = load(eegSetFile, 'etc');

    if ~isfield(loaded, 'etc') || ...
            ~isfield(loaded.etc, 'grf_to_eeg_processing')
        reason = "missing_mapping_provenance";
        return;
    end

    info = loaded.etc.grf_to_eeg_processing;
    requiredFields = { ...
        'version', 'source_event_file', 'source_event_signature', ...
        'source_xdf', 'source_xdf_signature', ...
        'maximum_mapping_error_ms'};

    if ~all(isfield(info, requiredFields))
        reason = "incomplete_mapping_provenance";
        return;
    end

    if string(info.version) ~= expectedVersion
        reason = "mapping_processing_version_changed";
        return;
    end

    if ~strcmpi(normalize_path_text(info.source_event_file), ...
            normalize_path_text(gaitFile)) || ...
            string(info.source_event_signature) ~= ...
            hipexo.file_signature(gaitFile)
        reason = "mapping_source_event_file_changed";
        return;
    end

    if ~strcmpi(normalize_path_text(info.source_xdf), ...
            normalize_path_text(sourceXDF)) || ...
            string(info.source_xdf_signature) ~= ...
            hipexo.file_signature(sourceXDF)
        reason = "mapping_source_XDF_changed";
        return;
    end

    if double(info.maximum_mapping_error_ms) ~= 5
        reason = "mapping_error_limit_changed";
        return;
    end

    canReuse = true;
    reason = "verified";

catch verificationError
    reason = "mapping_verification_error: " + ...
        sanitize_error_message_local(verificationError.message);
end

end

function row = failed_subject_status_row_local(subjectFolder, errorMessage)

[~, subjectName] = fileparts(char(subjectFolder));

row = table( ...
    string(subjectName), ...
    "", ...
    string(subjectFolder), ...
    NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
    "failed_subject_initialization", ...
    "not_run", ...
    "not_run", ...
    "not_run", ...
    "", "", "", "", ...
    NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
    NaN, NaN, NaN, NaN, NaN, NaN, ...
    "failed", ...
    "", ...
    current_time_text, ...
    string(errorMessage), ...
    'VariableNames', { ...
        'Subject', 'SessionFolder', 'XDFPath', ...
        'EEG_LSL_Start', 'EEG_LSL_End', 'EEG_LSL_DurationSec', ...
        'GRF_LSL_Start', 'GRF_LSL_End', 'GRF_LSL_DurationSec', ...
        'GRF_EEG_LSL_OverlapSec', ...
        'OverallStatus', 'GRFExtractionStatus', 'GaitEventStatus', ...
        'EEGMappingStatus', 'GRFStreamFile', 'GaitEventFile', ...
        'EEGSetFile', 'MappingCSVFile', 'MappedEventCount', ...
        'ExcludedEventCount', 'FirstGRFEventSample', ...
        'FirstGRFEventLSLTime', 'FirstMappedEEGSample', ...
        'FirstMatchedEEGLSLTime', 'LastGRFEventSample', ...
        'LastGRFEventLSLTime', 'LastMappedEEGSample', ...
        'LastMatchedEEGLSLTime', 'MedianAbsMappingErrorMs', ...
        'MaxAbsMappingErrorMs', 'EEGBoundaryCount', ...
        'SubjectMergeStatus', 'SubjectMergedSetFile', ...
        'CompletedAt', 'ErrorMessage'});

end

function value = current_time_text

value = string(datetime( ...
    'now', ...
    'TimeZone', 'local', ...
    'Format', 'yyyy-MM-dd HH:mm:ss'));

end

function message = sanitize_error_message_local(rawMessage)

message = string(rawMessage);
message = replace(message, newline, " | ");
message = replace(message, sprintf('\r'), " | ");
message = regexprep(message, '\s*\|\s*\|+\s*', ' | ');
message = strtrim(message);

end

