function [allCycleQC, allSegmentSummary, allEdgeEvents] = ...
    step04_process_subject_grf_eeg(grfRootFolder, varargin)
% GOAL
%   Process Step 03-approved GRF gait cycles together with EEG.
%   Step 04 maps GRF events onto retained EEG, applies the final gait-EEG
%   validity gate, and concatenates only eligible recordings for Step 05.
%
% INPUT
%   Step 03 subject folders below GRF_segmentation_output, including:
%     *_GRF_gait_batch_status.csv
%     grf_quality_check/grf_gait_cycle_qc_grf_only.mat
%
% APPROACH
%   1. Read Step 03 GRF-only cycle QC.
%   2. Skip EEG mapping when no GRF-recommended cycle exists.
%   3. Map GRF events to retained EEG only for GRF-eligible recordings.
%   4. Require every GRF-recommended cycle to have all five gait events
%      mapped into retained EEG and not cross an EEG timing boundary.
%   5. Save final gait-EEG QC tables and concatenate only included runs.
%
% OUTPUT
%   grf_gait_cycle_qc.csv
%   grf_gait_cycle_qc_summary.csv
%   grf_gait_edge_events_qc.csv
%   grf_RHS_timewarp_cycles_recommended.csv
%   Updated Step 03 batch-status CSV.
%   Subject-level concatenated EEG for Step 05.
%
% V3 FIXES
%   - Verified mapping outputs are truly reused by default.
%   - Reuse provenance is read with EEGLAB pop_loadset, not MATLAB load,
%     because the saved EEGLAB .set format is not reliably readable by load().
%   - Reuse validation now matches the provenance fields actually written
%     by the mapper; optional newer provenance fields are checked when present.
%   - Every reuse/rebuild decision prints an explicit reason.
%   - Subject-level concatenation defaults to reuse and reports whether the
%     existing merged EEG was reused.
%   - Routine subject_level_EEG_table.csv.before_subject_update_* files are
%     automatically removed.

thisFile = mfilename('fullpath');
if isempty(thisFile)
    error('Could not resolve the current Step file path.');
end

scriptsRoot = fileparts(fileparts(thisFile));
internalFolder = fullfile(scriptsRoot, 'internal');

addpath(scriptsRoot, '-begin');
addpath(internalFolder, '-begin');
addpath(fullfile(scriptsRoot, 'config'), '-begin');

P = project_paths();
cfg = config_step03_04_grf_processing();

if nargin < 1 || isempty(grfRootFolder)
    grfRootFolder = P.grfSegmentationFolder;
end

grfRootFolder = char(string(grfRootFolder));

if ~isfolder(grfRootFolder)
    error('GRF segmentation output folder does not exist:\n%s', ...
        grfRootFolder);
end

parser = inputParser;
% Resume-safe defaults: reuse verified outputs unless explicitly forced.
addParameter(parser, 'ForceEEGMapping', false, ...
    @(x) islogical(x) && isscalar(x));
addParameter(parser, 'ForceConcatenation', false, ...
    @(x) islogical(x) && isscalar(x));
addParameter(parser, 'AllowPartialSubject', cfg.batch.allowPartialSubject, ...
    @(x) islogical(x) && isscalar(x));
parse(parser, varargin{:});

forceEEGMapping = logical(parser.Results.ForceEEGMapping);
forceConcatenation = logical(parser.Results.ForceConcatenation);
allowPartialSubject = logical(parser.Results.AllowPartialSubject);

expectedEEGMappingVersion = ...
    "GRF_to_BIDS_EEGLAB_mapping_v6_retained_samples";

requiredFunctions = { ...
    'step04_map_grf_events_to_eeg_internal', ...
    'hipexo.concatenate_subject_grf_eeg', ...
    'hipexo.check_eeg_segments'};

for iRequired = 1:numel(requiredFunctions)
    if isempty(which(requiredFunctions{iRequired}))
        error('Required function is not available: %s', ...
            requiredFunctions{iRequired});
    end
end

importTable = hipexo.read_csv_with_string_text(P.importTableFile);
requiredImportColumns = {'XdfPath','OriginalSubjectID'};

if ~all(ismember(requiredImportColumns, importTable.Properties.VariableNames))
    error('Import table is missing XdfPath or OriginalSubjectID.');
end

importTable.XdfPath = string(importTable.XdfPath);
importTable.OriginalSubjectID = string(importTable.OriginalSubjectID);

subjectDirectories = dir(fullfile(grfRootFolder, 'sub-*'));
subjectDirectories = subjectDirectories([subjectDirectories.isdir]);

if isempty(subjectDirectories)
    error('No Step 03 subject folders were found below:\n%s', grfRootFolder);
end

allCycleQC = table();
allSegmentSummary = table();
allEdgeEvents = table();

% The concatenation helper currently creates timestamped
% ".before_subject_update_*" copies whenever it refreshes the central
% subject-level table. They are routine update snapshots, not scientific
% outputs. Remove historical copies now and guarantee cleanup on exit.
cleanup_subject_table_backups_local(P.subjectLevelEEGTableFile);
routineBackupCleanup = onCleanup(@() ...
    cleanup_subject_table_backups_local(P.subjectLevelEEGTableFile)); %#ok<NASGU>

for iSubject = 1:numel(subjectDirectories)

    subjectFolder = fullfile( ...
        subjectDirectories(iSubject).folder, ...
        subjectDirectories(iSubject).name);

    fprintf('\nStep 04 subject %d/%d: %s\n', ...
        iSubject, numel(subjectDirectories), subjectDirectories(iSubject).name);

    if hipexo.subject_is_selected(string(subjectDirectories(iSubject).name))
        [subjectCycleQC, subjectSummary, subjectEdgeEvents] = ...
            process_one_subject_local( ...
                subjectFolder, ...
                importTable, ...
                cfg, ...
                expectedEEGMappingVersion, ...
                forceEEGMapping, ...
                forceConcatenation, ...
                allowPartialSubject);
    else
        qcFolder = fullfile(subjectFolder, 'grf_quality_check');
        subjectCycleQC = read_existing_qc_local(qcFolder, 'grf_gait_cycle_qc.csv');
        subjectSummary = read_existing_qc_local(qcFolder, 'grf_gait_cycle_qc_summary.csv');
        subjectEdgeEvents = read_existing_qc_local(qcFolder, 'grf_gait_edge_events_qc.csv');
    end

    allCycleQC = append_table_local(allCycleQC, subjectCycleQC);
    allSegmentSummary = append_table_local( ...
        allSegmentSummary, subjectSummary);
    allEdgeEvents = append_table_local(allEdgeEvents, subjectEdgeEvents);

    % Keep the output folder clean even when the helper updates the central
    % subject-level table for this subject.
    cleanup_subject_table_backups_local(P.subjectLevelEEGTableFile);
end

masterQCFolder = fullfile(grfRootFolder, 'grf_quality_check');
if ~isfolder(masterQCFolder)
    mkdir(masterQCFolder);
end

if ~isempty(allCycleQC)
    allCycleQC = sortrows(allCycleQC, ...
        {'Subject','RHS1_LSLTime','SegmentIndex','CycleIndex'});
end

if ~isempty(allSegmentSummary)
    allSegmentSummary = sortrows(allSegmentSummary, ...
        {'Subject','RecordingStartLSLTime','SegmentIndex'});
end

if ~isempty(allEdgeEvents)
    allEdgeEvents = sortrows(allEdgeEvents, ...
        {'Subject','XDFPath','SegmentIndex','LSLTime'});
end

writetable(allCycleQC, fullfile( ...
    masterQCFolder, 'GRF_gait_cycle_QC_all_subjects.csv'));

writetable(allSegmentSummary, fullfile( ...
    masterQCFolder, 'GRF_gait_cycle_QC_summary_all_subjects.csv'));

writetable(allEdgeEvents, fullfile( ...
    masterQCFolder, 'GRF_gait_edge_events_QC_all_subjects.csv'));

if isempty(allCycleQC)
    allRecommendedCycles = allCycleQC;
else
    allRecommendedCycles = ...
        allCycleQC(allCycleQC.RecommendedForEpoch, :);
end

masterRecommendedFile = fullfile( ...
    masterQCFolder, ...
    'GRF_RHS_timewarp_cycles_recommended_all_subjects.csv');

writetable(allRecommendedCycles, masterRecommendedFile);

fprintf('\nStep 04 gait-EEG validation finished.\n');

if isempty(allCycleQC)
    nGRFRecommended = 0;
    nEEGValid = 0;
    nFinalRecommended = 0;
else
    nGRFRecommended = sum(allCycleQC.GRFRecommendedForEpoch);
    nEEGValid = sum(allCycleQC.EEGValidCycle);
    nFinalRecommended = sum(allCycleQC.RecommendedForEpoch);
end

fprintf('GRF-recommended cycles entering EEG gate: %d\n', ...
    nGRFRecommended);
fprintf('Cycles valid in retained EEG: %d\n', ...
    nEEGValid);
fprintf('Final recommended gait-EEG cycles: %d\n', ...
    nFinalRecommended);
fprintf('Final recommended-cycle table:\n%s\n', ...
    masterRecommendedFile);

end

function [cycleQC, summaryTable, edgeEvents] = process_one_subject_local( ...
        subjectFolder, importTable, cfg, expectedMappingVersion, ...
        forceEEGMapping, forceConcatenation, allowPartialSubject)

batchLogs = dir(fullfile( ...
    subjectFolder, '*_GRF_gait_batch_status.csv'));

if numel(batchLogs) ~= 1
    error('Expected exactly one Step 03 GRF gait batch-status CSV below:\n%s', ...
        subjectFolder);
end

step03BatchLogFile = fullfile(batchLogs(1).folder, batchLogs(1).name);
batchStatus = hipexo.read_csv_with_string_text(step03BatchLogFile);

subjectIDForLog = string(batchStatus.Subject(1));
finalBatchLogFile = fullfile( ...
    subjectFolder, ...
    [char(subjectIDForLog) '_GRF_EEG_batch_status.csv']);

requiredBatchColumns = { ...
    'Subject', ...
    'XDFPath', ...
    'BidsEEGLABSet', ...
    'OverallStatus', ...
    'GRFGaitQCStatus', ...
    'GRFRecommendedCycleCount', ...
    'GaitEventFile', ...
    'EEGMappingStatus', ...
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
    'SubjectMergedSetFile'};

missingBatchColumns = requiredBatchColumns( ...
    ~ismember(requiredBatchColumns, batchStatus.Properties.VariableNames));

if ~isempty(missingBatchColumns)
    error('Step 03 batch-status CSV is missing fields: %s', ...
        strjoin(missingBatchColumns, ', '));
end

batchStatus.Subject = string(batchStatus.Subject);
batchStatus.XDFPath = string(batchStatus.XDFPath);
batchStatus.BidsEEGLABSet = string(batchStatus.BidsEEGLABSet);
batchStatus.OverallStatus = string(batchStatus.OverallStatus);
batchStatus.GRFGaitQCStatus = string(batchStatus.GRFGaitQCStatus);
batchStatus.GaitEventFile = string(batchStatus.GaitEventFile);
batchStatus.EEGMappingStatus = string(batchStatus.EEGMappingStatus);
batchStatus.EEGSetFile = string(batchStatus.EEGSetFile);
batchStatus.MappingCSVFile = string(batchStatus.MappingCSVFile);

qcFolder = fullfile(subjectFolder, 'grf_quality_check');
grOnlyMat = fullfile(qcFolder, 'grf_gait_cycle_qc_grf_only.mat');

if ~isfile(grOnlyMat)
    error([ ...
        'Step 03 GRF-only gait-cycle QC MAT is missing:\n%s\n' ...
        'Re-run Step 03 first.'], grOnlyMat);
end

loadedQC = load(grOnlyMat, 'allCycleQC', 'allSummary', 'allEdgeEvents');

if ~isfield(loadedQC, 'allCycleQC') || ...
        ~isfield(loadedQC, 'allSummary') || ...
        ~isfield(loadedQC, 'allEdgeEvents')
    error('GRF-only QC MAT is incomplete:\n%s', grOnlyMat);
end

cycleQC = loadedQC.allCycleQC;
summaryTable = loadedQC.allSummary;
edgeEvents = loadedQC.allEdgeEvents;

% Reset all EEG-domain fields because Step 04 is authoritative for them.
if ~isempty(cycleQC)
    cycleQC.EEGMappingAvailable(:) = false;
    cycleQC.EEGAllEventsMapped(:) = false;
    cycleQC.EEGCycleCrossesBoundary(:) = false;
    cycleQC.EEGValidCycle(:) = false;
    cycleQC.EEGQCReason(:) = "not_evaluated_not_GRF_recommended";
    cycleQC.RecommendedForEpoch(:) = false;
end

batchStatus.FinalGRFRecommendedCycleCount = ...
    zeros(height(batchStatus), 1);
batchStatus.FinalEEGValidCycleCount = ...
    zeros(height(batchStatus), 1);
batchStatus.FinalRecommendedCycleCount = ...
    zeros(height(batchStatus), 1);
batchStatus.FinalGaitEEGStatus = ...
    strings(height(batchStatus), 1);

subjectEEGOutputFolder = fullfile(subjectFolder, 'EEG_with_GRF_events');
if ~isfolder(subjectEEGOutputFolder)
    mkdir(subjectEEGOutputFolder);
end

for iRow = 1:height(batchStatus)

    currentXDF = string(batchStatus.XDFPath(iRow));
    currentOverallStatus = lower(strtrim(batchStatus.OverallStatus(iRow)));
    currentGRFStatus = lower(strtrim(batchStatus.GRFGaitQCStatus(iRow)));

    cycleRows = false(height(cycleQC), 1);
    if ~isempty(cycleQC)
        cycleRows = normalize_path_local(cycleQC.XDFPath) == ...
            normalize_path_local(currentXDF);
    end

    nGRFRecommended = 0;
    if any(cycleRows)
        nGRFRecommended = ...
            sum(cycleQC.GRFRecommendedForEpoch(cycleRows));
    end

    batchStatus.FinalGRFRecommendedCycleCount(iRow) = nGRFRecommended;

    if currentOverallStatus == "failed"
        batchStatus.EEGMappingStatus(iRow) = "not_run_step03_failure";
        batchStatus.FinalGaitEEGStatus(iRow) = ...
            "blocked_processing_failure";
        continue;
    end

    if currentGRFStatus ~= "ready_for_step04" || nGRFRecommended == 0
        batchStatus.EEGMappingStatus(iRow) = ...
            "not_run_no_recommended_GRF_cycle";
        batchStatus.OverallStatus(iRow) = "completed";
        batchStatus.FinalGaitEEGStatus(iRow) = ...
            "excluded_no_recommended_GRF_cycle";
        continue;
    end

    currentBidsSet = char(batchStatus.BidsEEGLABSet(iRow));
    currentEventFile = char(batchStatus.GaitEventFile(iRow));

    if ~isfile(currentBidsSet)
        batchStatus.OverallStatus(iRow) = "failed";
        batchStatus.EEGMappingStatus(iRow) = "failed";
        batchStatus.FinalGaitEEGStatus(iRow) = ...
            "blocked_processing_failure";
        continue;
    end

    originalSubject = original_subject_for_xdf_local( ...
        currentXDF, importTable);

    [~, bidsRawBaseName] = fileparts(currentBidsSet);
    outputStem = regexprep( ...
        bidsRawBaseName, '_desc-bidsraw_eeg$', '');

    eegSetFile = fullfile( ...
        subjectEEGOutputFolder, ...
        [outputStem '_desc-grfevents_eeg.set']);

    mappingCSVFile = fullfile( ...
        subjectEEGOutputFolder, ...
        [outputStem '_desc-grfeventmapping_events.csv']);

    gapCSVFile = fullfile( ...
        subjectEEGOutputFolder, ...
        [outputStem '_desc-eegtimestampgaps_events.csv']);

    batchStatus.EEGSetFile(iRow) = string(eegSetFile);
    batchStatus.MappingCSVFile(iRow) = string(mappingCSVFile);

    try
        mappingOutputsComplete = ...
            isfile(eegSetFile) && ...
            isfile(mappingCSVFile) && ...
            isfile(gapCSVFile);

        reuseMapping = false;
        reuseReason = "mapping_outputs_missing";

        if mappingOutputsComplete && ~forceEEGMapping
            [reuseMapping, reuseReason] = verify_mapping_reuse_local( ...
                eegSetFile, ...
                currentEventFile, ...
                char(currentXDF), ...
                currentBidsSet, ...
                expectedMappingVersion, ...
                cfg, ...
                batchStatus.Subject(iRow), ...
                originalSubject);
        elseif forceEEGMapping
            reuseReason = "forced_reprocess";
        end

        if reuseMapping
            batchStatus.EEGMappingStatus(iRow) = "reused_verified";
            fprintf('[REUSE] %s | %s\n', ...
                outputStem, reuseReason);
        else
            fprintf('[REBUILD] %s | %s\n', ...
                outputStem, reuseReason);

            step04_map_grf_events_to_eeg_internal( ...
                currentEventFile, ...
                currentBidsSet, ...
                outputStem, ...
                char(batchStatus.Subject(iRow)), ...
                char(originalSubject), ...
                fullfile(subjectFolder, 'GRF'), ...
                subjectEEGOutputFolder);

            if ~isfile(eegSetFile) || ...
                    ~isfile(mappingCSVFile) || ...
                    ~isfile(gapCSVFile)
                error('GRF-to-EEG mapping outputs are incomplete.');
            end

            batchStatus.EEGMappingStatus(iRow) = "completed";
        end

        evidence = load_mapping_evidence_local( ...
            mappingCSVFile, gapCSVFile);

        cycleQC = apply_eeg_gate_for_rows_local( ...
            cycleQC, cycleRows, evidence);

        batchStatus = fill_mapping_audit_local( ...
            batchStatus, iRow, evidence.MappingTable, evidence.GapTable);

        batchStatus.OverallStatus(iRow) = "completed";

    catch mappingError

        if is_expected_mapping_exclusion_local(mappingError.message)
            batchStatus.EEGMappingStatus(iRow) = ...
                "excluded_no_usable_gait_eeg";
            batchStatus.OverallStatus(iRow) = ...
                "excluded_no_usable_gait_eeg";

            if any(cycleRows)
                evaluateRows = cycleRows & cycleQC.GRFRecommendedForEpoch;
                cycleQC.EEGQCReason(evaluateRows) = ...
                    "no_usable_retained_EEG_for_cycle";
            end
        else
            batchStatus.EEGMappingStatus(iRow) = "failed";
            batchStatus.OverallStatus(iRow) = "failed";
            batchStatus.FinalGaitEEGStatus(iRow) = ...
                "blocked_processing_failure";

            if ismember('ErrorMessage', batchStatus.Properties.VariableNames)
                batchStatus.ErrorMessage(iRow) = ...
                    sanitize_error_message_local(mappingError.message);
            end
        end
    end
end

if ~isempty(cycleQC)
    cycleQC.RecommendedForEpoch = ...
        cycleQC.GRFRecommendedForEpoch & cycleQC.EEGValidCycle;

    for iCycle = 1:height(cycleQC)
        if cycleQC.GRFRecommendedForEpoch(iCycle) && ...
                ~cycleQC.EEGValidCycle(iCycle)
            cycleQC.QCReason(iCycle) = append_reason_local( ...
                cycleQC.QCReason(iCycle), ...
                cycleQC.EEGQCReason(iCycle));
        end
    end
end

summaryTable = update_final_summary_local(summaryTable, cycleQC);

for iRow = 1:height(batchStatus)

    currentPath = normalize_path_local(batchStatus.XDFPath(iRow));
    cycleRows = false(height(cycleQC), 1);

    if ~isempty(cycleQC)
        cycleRows = normalize_path_local(cycleQC.XDFPath) == currentPath;
    end

    if any(cycleRows)
        batchStatus.FinalGRFRecommendedCycleCount(iRow) = ...
            sum(cycleQC.GRFRecommendedForEpoch(cycleRows));
        batchStatus.FinalEEGValidCycleCount(iRow) = ...
            sum(cycleQC.GRFRecommendedForEpoch(cycleRows) & ...
                cycleQC.EEGValidCycle(cycleRows));
        batchStatus.FinalRecommendedCycleCount(iRow) = ...
            sum(cycleQC.RecommendedForEpoch(cycleRows));
    end

    currentOverallStatus = lower(strtrim(batchStatus.OverallStatus(iRow)));

    if currentOverallStatus == "failed"
        batchStatus.FinalGaitEEGStatus(iRow) = ...
            "blocked_processing_failure";
    elseif batchStatus.FinalGRFRecommendedCycleCount(iRow) == 0
        batchStatus.FinalGaitEEGStatus(iRow) = ...
            "excluded_no_recommended_GRF_cycle";
    elseif batchStatus.FinalRecommendedCycleCount(iRow) > 0
        batchStatus.FinalGaitEEGStatus(iRow) = "included";
    else
        batchStatus.FinalGaitEEGStatus(iRow) = ...
            "excluded_no_recommended_gait_EEG_cycle";
    end
end

perSubjectCycleFile = fullfile(qcFolder, 'grf_gait_cycle_qc.csv');
perSubjectSummaryFile = fullfile(qcFolder, 'grf_gait_cycle_qc_summary.csv');
perSubjectEdgeFile = fullfile(qcFolder, 'grf_gait_edge_events_qc.csv');
perSubjectRecommendedFile = fullfile( ...
    qcFolder, 'grf_RHS_timewarp_cycles_recommended.csv');

writetable(cycleQC, perSubjectCycleFile);
writetable(summaryTable, perSubjectSummaryFile);
writetable(edgeEvents, perSubjectEdgeFile);

if isempty(cycleQC)
    recommendedCycles = cycleQC;
else
    recommendedCycles = cycleQC(cycleQC.RecommendedForEpoch, :);
end

writetable(recommendedCycles, perSubjectRecommendedFile);
writetable(batchStatus, finalBatchLogFile);

if isfield(cfg, 'batch') && ...
        isfield(cfg.batch, 'concatenateSessions') && ...
        ~logical(cfg.batch.concatenateSessions)
    batchStatus.SubjectMergeStatus(:) = "not_requested";
    batchStatus.SubjectMergedSetFile(:) = "";
    writetable(batchStatus, finalBatchLogFile);
    return;
end

includedRows = batchStatus.FinalGaitEEGStatus == "included";

if ~any(includedRows)
    batchStatus.SubjectMergeStatus(:) = ...
        "not_available_no_recommended_cycles";
    invalidate_subject_row_local(subjectIDForLog, "no_recommended_cycles");
    batchStatus.SubjectMergedSetFile(:) = "";
    writetable(batchStatus, finalBatchLogFile);
    return;
end

try
    [mergedSetFile, mergeSummary] = hipexo.concatenate_subject_grf_eeg( ...
        subjectFolder, ...
        'ForceReprocess', forceConcatenation, ...
        'AllowPartialSubject', allowPartialSubject);

    mergeStatusText = "completed";
    if ~isempty(mergeSummary) && ...
            ismember('MergeStatus', mergeSummary.Properties.VariableNames)
        mergeStatusText = string(mergeSummary.MergeStatus(1));
    end

    batchStatus.SubjectMergeStatus(:) = mergeStatusText;
    batchStatus.SubjectMergedSetFile(:) = string(mergedSetFile);

    if lower(strtrim(mergeStatusText)) == "reused_existing"
        fprintf('[REUSE] Subject-level EEG: %s\n', string(mergedSetFile));
    else
        fprintf('[MERGE] Subject-level EEG status: %s\n', mergeStatusText);
    end
catch mergeError
    invalidate_subject_row_local(subjectIDForLog, "subject_merge_failed");
    batchStatus.SubjectMergedSetFile(:) = "";
    batchStatus.SubjectMergeStatus(:) = "failed";
    fprintf(2, ...
        '\nStep 04 subject concatenation failed for %s:\n%s\n', ...
        subjectFolder, mergeError.message);
end

writetable(batchStatus, finalBatchLogFile);

end

function cycleQC = apply_eeg_gate_for_rows_local( ...
        cycleQC, cycleRows, evidence)

indices = find(cycleRows & cycleQC.GRFRecommendedForEpoch);

for iIndex = 1:numel(indices)

    iCycle = indices(iIndex);
    cycleQC.EEGMappingAvailable(iCycle) = true;

    expectedTypes = ["RHS"; "LTO"; "LHS"; "RTO"; "RHS"];
    expectedSamples = [ ...
        cycleQC.RHS1_GRFSample(iCycle); ...
        cycleQC.LTO_GRFSample(iCycle); ...
        cycleQC.LHS_GRFSample(iCycle); ...
        cycleQC.RTO_GRFSample(iCycle); ...
        cycleQC.RHS2_GRFSample(iCycle)];

    if any(~isfinite(expectedSamples))
        cycleQC.EEGQCReason(iCycle) = ...
            "cycle_event_identity_incomplete";
        continue;
    end

    segmentIndex = cycleQC.SegmentIndex(iCycle);
    allMapped = true;

    for iEvent = 1:numel(expectedTypes)
        currentRows = ...
            evidence.MappingTable.SegmentIndex == segmentIndex & ...
            evidence.MappingTable.GRFSample == expectedSamples(iEvent) & ...
            evidence.MappingTable.EventType == expectedTypes(iEvent);

        if sum(currentRows) ~= 1
            allMapped = false;
            break;
        end

        if evidence.MappingTable.MappingStatus(currentRows) ~= "mapped" || ...
                ~isfinite(evidence.MappingTable.EEGSample(currentRows))
            allMapped = false;
            break;
        end
    end

    cycleQC.EEGAllEventsMapped(iCycle) = allMapped;

    rhs1 = cycleQC.RHS1_LSLTime(iCycle);
    rhs2 = cycleQC.RHS2_LSLTime(iCycle);
    crossesBoundary = false;

    if ~isempty(evidence.GapTable) && isfinite(rhs1) && isfinite(rhs2)
        crossesBoundary = any( ...
            evidence.GapTable.LSLBeforeGap < rhs2 & ...
            evidence.GapTable.LSLAfterGap > rhs1);
    end

    cycleQC.EEGCycleCrossesBoundary(iCycle) = crossesBoundary;
    cycleQC.EEGValidCycle(iCycle) = allMapped && ~crossesBoundary;

    if ~allMapped
        cycleQC.EEGQCReason(iCycle) = ...
            "not_all_cycle_events_mapped_to_retained_EEG";
    elseif crossesBoundary
        cycleQC.EEGQCReason(iCycle) = "cycle_crosses_EEG_boundary";
    else
        cycleQC.EEGQCReason(iCycle) = "OK";
    end
end

end

function evidence = load_mapping_evidence_local(mappingFile, gapFile)

evidence = struct('MappingTable', table(), 'GapTable', table());

mappingTable = hipexo.read_csv_with_string_text(mappingFile);
gapTable = hipexo.read_csv_with_string_text(gapFile);

requiredMappingColumns = { ...
    'EventType','SegmentIndex','GRFSample','MappingStatus','EEGSample', ...
    'LSLTime','MatchedEEGLSLTime','MappingErrorMs'};

if ~all(ismember(requiredMappingColumns, ...
        mappingTable.Properties.VariableNames))
    error('Mapping CSV is missing required columns:\n%s', mappingFile);
end

mappingTable.EventType = upper(strtrim(string(mappingTable.EventType)));
mappingTable.MappingStatus = ...
    lower(strtrim(string(mappingTable.MappingStatus)));
mappingTable.SegmentIndex = numeric_column_local(mappingTable.SegmentIndex);
mappingTable.GRFSample = numeric_column_local(mappingTable.GRFSample);
mappingTable.EEGSample = numeric_column_local(mappingTable.EEGSample);
mappingTable.LSLTime = numeric_column_local(mappingTable.LSLTime);
mappingTable.MatchedEEGLSLTime = ...
    numeric_column_local(mappingTable.MatchedEEGLSLTime);
mappingTable.MappingErrorMs = numeric_column_local(mappingTable.MappingErrorMs);

if ~isempty(gapTable)
    requiredGapColumns = {'LSLBeforeGap','LSLAfterGap'};
    if ~all(ismember(requiredGapColumns, gapTable.Properties.VariableNames))
        error('EEG gap CSV is missing required columns:\n%s', gapFile);
    end
    gapTable.LSLBeforeGap = numeric_column_local(gapTable.LSLBeforeGap);
    gapTable.LSLAfterGap = numeric_column_local(gapTable.LSLAfterGap);
end

evidence.MappingTable = mappingTable;
evidence.GapTable = gapTable;

end

function batchStatus = fill_mapping_audit_local( ...
        batchStatus, iRow, mappingTable, gapTable)

mappedRows = mappingTable.MappingStatus == "mapped";
batchStatus.MappedEventCount(iRow) = sum(mappedRows);
batchStatus.ExcludedEventCount(iRow) = sum(~mappedRows);
batchStatus.EEGBoundaryCount(iRow) = height(gapTable);

if ~any(mappedRows)
    return;
end

mappedTable = sortrows(mappingTable(mappedRows, :), 'LSLTime');
firstRow = mappedTable(1, :);
lastRow = mappedTable(end, :);

batchStatus.FirstGRFEventSample(iRow) = firstRow.GRFSample;
batchStatus.FirstGRFEventLSLTime(iRow) = firstRow.LSLTime;
batchStatus.FirstMappedEEGSample(iRow) = firstRow.EEGSample;
batchStatus.FirstMatchedEEGLSLTime(iRow) = firstRow.MatchedEEGLSLTime;
batchStatus.LastGRFEventSample(iRow) = lastRow.GRFSample;
batchStatus.LastGRFEventLSLTime(iRow) = lastRow.LSLTime;
batchStatus.LastMappedEEGSample(iRow) = lastRow.EEGSample;
batchStatus.LastMatchedEEGLSLTime(iRow) = lastRow.MatchedEEGLSLTime;

absoluteError = abs(mappedTable.MappingErrorMs);
absoluteError = absoluteError(isfinite(absoluteError));

if ~isempty(absoluteError)
    batchStatus.MedianAbsMappingErrorMs(iRow) = median(absoluteError);
    batchStatus.MaxAbsMappingErrorMs(iRow) = max(absoluteError);
end

end

function summaryTable = update_final_summary_local(summaryTable, cycleQC)

if isempty(summaryTable)
    return;
end

summaryTable.EEGValidCycleCount(:) = 0;
summaryTable.EEGInvalidCycleCount(:) = 0;
summaryTable.RecommendedCycleCount(:) = 0;

for iSummary = 1:height(summaryTable)

    rows = ...
        normalize_path_local(cycleQC.XDFPath) == ...
            normalize_path_local(summaryTable.XDFPath(iSummary)) & ...
        cycleQC.SegmentIndex == summaryTable.SegmentIndex(iSummary);

    if ~any(rows)
        continue;
    end

    grfRows = rows & cycleQC.GRFRecommendedForEpoch;
    summaryTable.EEGValidCycleCount(iSummary) = ...
        sum(grfRows & cycleQC.EEGValidCycle);
    summaryTable.EEGInvalidCycleCount(iSummary) = ...
        sum(grfRows & ~cycleQC.EEGValidCycle);
    summaryTable.RecommendedCycleCount(iSummary) = ...
        sum(rows & cycleQC.RecommendedForEpoch);

    if summaryTable.SegmentStatus(iSummary) == "needs_raw_grf_review" || ...
            summaryTable.SegmentStatus(iSummary) == "fail_no_complete_RHS_cycle" || ...
            summaryTable.SegmentStatus(iSummary) == "fail_no_recommended_GRF_cycle"
        continue;
    end

    if summaryTable.RecommendedCycleCount(iSummary) == 0
        summaryTable.SegmentStatus(iSummary) = ...
            "fail_no_recommended_gait_EEG_cycle";
    elseif summaryTable.EEGInvalidCycleCount(iSummary) > 0
        summaryTable.SegmentStatus(iSummary) = "pass_with_exclusions";
    end
end

end

function originalSubject = original_subject_for_xdf_local(xdfPath, importTable)

mask = normalize_path_local(importTable.XdfPath) == ...
    normalize_path_local(xdfPath);

values = unique(strtrim(importTable.OriginalSubjectID(mask)));
values(values == "" | ismissing(values)) = [];

if numel(values) ~= 1
    error('Could not resolve one OriginalSubjectID for XDF:\n%s', xdfPath);
end

originalSubject = values(1);

end

function [canReuse, reason] = verify_mapping_reuse_local( ...
        eegSetFile, gaitFile, sourceXDF, sourceBidsEEGLABSet, ...
        expectedVersion, cfg, expectedCanonicalSubject, expectedOriginalSubject)

canReuse = false;
reason = "unverified_mapping_output";

try
    % Read EEGLAB metadata with EEGLAB itself.
    % IMPORTANT:
    %   Do NOT use load(eegSetFile,'etc') here. The mapped .set files written
    %   by the current EEGLAB save configuration are not guaranteed to be
    %   directly readable by MATLAB load(), even though pop_loadset reads them
    %   correctly. The old implementation therefore threw before it could ever
    %   reach the fallback and forced every run to rebuild.
    if exist('pop_loadset','file') ~= 2
        eeglab nogui;
    end

    [setFolder,setBase,setExt] = fileparts(eegSetFile);

    tmpEEG = pop_loadset( ...
        'filename', [setBase setExt], ...
        'filepath', setFolder);
    assert(isnumeric(tmpEEG.data) && ~isempty(tmpEEG.data) && ...
        numel(tmpEEG.data) == double(tmpEEG.nbchan)*double(tmpEEG.pnts)*double(tmpEEG.trials), ...
        'Mapped EEG sample data are incomplete.');

    outputEtc = struct();

    if isfield(tmpEEG,'etc') && isstruct(tmpEEG.etc)
        outputEtc = tmpEEG.etc;
    end

    clear tmpEEG;

    if ~isfield(outputEtc, 'grf_to_eeg_processing') || ...
            ~isstruct(outputEtc.grf_to_eeg_processing)
        reason = "missing_mapping_provenance";
        return;
    end

    info = outputEtc.grf_to_eeg_processing;

    % Require the actual data, QC and channel-location dependencies.
    requiredFields = { ...
        'mapping_parameters','eeg_qc_parameters','eeg_segment_code_signature', ...
        'channel_location_signature', ...
        'source_event_file','source_event_signature', ...
        'source_xdf','source_xdf_signature', ...
        'source_bids_eeg_set','source_bids_eeg_set_signature', ...
        'canonical_subject_id','original_subject_id', ...
        'sample_count_identity_verified','sample_values_resampled', ...
        'output_nominal_srate_hz','maximum_mapping_error_ms', ...
        'timestamp_gap_factor','minimum_timestamp_gap_sec'};

    missingFields = requiredFields(~isfield(info, requiredFields));
    if ~isempty(missingFields)
        reason = "incomplete_mapping_provenance:" + ...
            strjoin(string(missingFields), ",");
        return;
    end


    if ~strcmpi(strtrim(string(info.canonical_subject_id)), ...
            strtrim(string(expectedCanonicalSubject))) || ...
            ~strcmpi(strtrim(string(info.original_subject_id)), ...
            strtrim(string(expectedOriginalSubject)))
        reason = "mapping_subject_identity_changed";
        return;
    end

    % If the output also stores top-level subject identities, verify them.
    if isfield(outputEtc,'canonical_subject_id') && ...
            strlength(strtrim(string(outputEtc.canonical_subject_id))) > 0 && ...
            ~strcmpi(strtrim(string(outputEtc.canonical_subject_id)), ...
            strtrim(string(expectedCanonicalSubject)))
        reason = "mapping_output_canonical_subject_changed";
        return;
    end

    if isfield(outputEtc,'original_subject_id') && ...
            strlength(strtrim(string(outputEtc.original_subject_id))) > 0 && ...
            ~strcmpi(strtrim(string(outputEtc.original_subject_id)), ...
            strtrim(string(expectedOriginalSubject)))
        reason = "mapping_output_original_subject_changed";
        return;
    end

    if ~strcmpi(normalize_path_local(info.source_event_file), ...
            normalize_path_local(gaitFile))
        reason = "mapping_source_event_path_changed";
        return;
    end

    currentEventSignature = hipexo.file_metadata_signature(gaitFile);
    if string(info.source_event_signature) ~= string(currentEventSignature)
        reason = "mapping_source_event_signature_changed";
        return;
    end

    if ~strcmpi(normalize_path_local(info.source_xdf), ...
            normalize_path_local(sourceXDF))
        reason = "mapping_source_XDF_path_changed";
        return;
    end

    currentXDFSignature = hipexo.file_metadata_signature(sourceXDF);
    if string(info.source_xdf_signature) ~= string(currentXDFSignature)
        reason = "mapping_source_XDF_signature_changed";
        return;
    end

    if ~strcmpi(normalize_path_local(info.source_bids_eeg_set), ...
            normalize_path_local(sourceBidsEEGLABSet))
        reason = "mapping_source_BIDS_EEGLAB_path_changed";
        return;
    end

    currentBidsSignature = ...
        hipexo.eeglab_dataset_signature(sourceBidsEEGLABSet);
    if string(info.source_bids_eeg_set_signature) ~= ...
            string(currentBidsSignature)
        reason = "mapping_source_BIDS_EEGLAB_signature_changed";
        return;
    end

    if ~logical(info.sample_count_identity_verified) || ...
            logical(info.sample_values_resampled)
        reason = "mapping_sample_identity_policy_changed";
        return;
    end

    if abs(double(info.output_nominal_srate_hz) - ...
            double(cfg.mapping.targetEEGSrateHz)) > 1e-9
        reason = "mapping_output_rate_changed";
        return;
    end

    if abs(double(info.maximum_mapping_error_ms) - ...
            double(cfg.mapping.maximumMappingErrorMs)) > 1e-12
        reason = "mapping_error_tolerance_changed";
        return;
    end

    if abs(double(info.timestamp_gap_factor) - ...
            double(cfg.mapping.timestampGapFactor)) > 1e-12
        reason = "mapping_timestamp_gap_factor_changed";
        return;
    end

    if abs(double(info.minimum_timestamp_gap_sec) - ...
            double(cfg.mapping.minimumTimestampGapSec)) > 1e-12
        reason = "mapping_minimum_gap_changed";
        return;
    end

    if ~isequaln(info.mapping_parameters, cfg.mapping)
        reason = "mapping_parameters_changed";
        return;
    end

    P = project_paths();
    if string(info.channel_location_signature) ~= ...
            hipexo.file_metadata_signature(P.channelLocationFile)
        reason = "mapping_channel_locations_changed";
        return;
    end

    % QC settings and checker code are required calculation dependencies.
    if isfield(info,'eeg_qc_parameters')
        eegQC = config_step01_02_xdf_import();
        currentEEGQC = ...
            struct('eeg', eegQC.eeg, 'timestamp', eegQC.timestamp);

        if ~isequaln(info.eeg_qc_parameters, currentEEGQC)
            reason = "mapping_EEG_QC_parameters_changed";
            return;
        end
    end

    if isfield(info,'eeg_segment_code_signature')
        segmentFunction = which('hipexo.check_eeg_segments');
        if isempty(segmentFunction)
            reason = "mapping_EEG_segment_checker_missing";
            return;
        end

        currentSegmentCodeSignature = ...
            hipexo.content_signature(fileread(segmentFunction));

        if string(info.eeg_segment_code_signature) ~= ...
                string(currentSegmentCodeSignature)
            reason = "mapping_EEG_segment_code_changed";
            return;
        end
    end

    canReuse = true;
    reason = "verified_inputs_and_mapping_provenance";

catch verificationError
    canReuse = false;
    reason = "mapping_reuse_verification_error:" + ...
        sanitize_error_message_local(verificationError.message);
end

end



function tf = is_expected_mapping_exclusion_local(message)
message = lower(strtrim(string(message)));
expectedMessages = [ ...
    "no continuous eeg segment passes the current step 01 qc", ...
    "no grf gait events overlap retained eeg samples", ...
    "grf-to-eeg mapping produced zero mapped gait events"];
tf = any(contains(message, expectedMessages));
end

function outputReason = append_reason_local(inputReason, newReason)
inputReason = string(inputReason);
newReason = string(newReason);
if strlength(inputReason) == 0 || inputReason == "OK"
    outputReason = newReason;
else
    outputReason = inputReason + ";" + newReason;
end
end

function output = append_table_local(output, input)
if isempty(input)
    return;
elseif isempty(output)
    output = input;
else
    output = [output; input]; %#ok<AGROW>
end
end

function value = normalize_path_local(value)
value = lower(strtrim(string(value)));
value = replace(value, "\", "/");
value = regexprep(value, '/+$', '');
end

function values = numeric_column_local(values)
if isnumeric(values)
    values = double(values);
elseif islogical(values)
    values = double(values);
else
    values = str2double(string(values));
end
end

function cleanup_subject_table_backups_local(tableFile)
% Remove only routine timestamped "before_subject_update" snapshots.
% Deliberately keep incompatible-schema backups because those are recovery
% copies created for a structurally different table.

if nargin < 1 || ...
        strlength(strtrim(string(tableFile))) == 0
    return;
end

tableFile = char(string(tableFile));
[tableFolder, tableName, tableExt] = fileparts(tableFile);

if isempty(tableFolder)
    tableFolder = pwd;
end

pattern = [tableName tableExt '.before_subject_update_*.csv'];
backupFiles = dir(fullfile(tableFolder, pattern));

for iFile = 1:numel(backupFiles)
    backupPath = fullfile(backupFiles(iFile).folder, backupFiles(iFile).name);
    try
        delete(backupPath);
    catch cleanupError
        warning('Could not delete routine subject-table backup:\n%s\n%s', ...
            backupPath, cleanupError.message);
    end
end

end

function message = sanitize_error_message_local(rawMessage)
message = string(rawMessage);
message = replace(message, newline, " | ");
message = replace(message, sprintf('\r'), " | ");
message = regexprep(message, '\s*\|\s*\|+\s*', ' | ');
message = strtrim(message);
end

function T = read_existing_qc_local(folder, name)
T = table();
file = fullfile(folder, name);
if isfile(file), T = hipexo.read_csv_with_string_text(file); end
end

function invalidate_subject_row_local(subject, reason)
% A previous successful row must not survive a newly excluded/failed subject.
P = project_paths();
if ~isfile(P.subjectLevelEEGTableFile), return; end
T = hipexo.read_csv_with_string_text(P.subjectLevelEEGTableFile);
if ~ismember('BidsSubject', T.Properties.VariableNames), return; end
number = str2double(regexprep(lower(string(subject)), '^sub-', ''));
rows = str2double(string(T.BidsSubject)) == number;
if ~any(rows), return; end
flags = {'DoPreprocess','RecommendedDoPreprocess','DoQC','AnalysisReady','DoAMICA','DoICAQC'};
for k = 1:numel(flags)
    if ismember(flags{k}, T.Properties.VariableNames), T.(flags{k})(rows) = 0; end
end
statuses = {'PreprocessingStatus','PreprocessingQCStatus','AMICAStatus','ICAQCStatus'};
for k = 1:numel(statuses)
    if ismember(statuses{k}, T.Properties.VariableNames)
        T.(statuses{k}) = string(T.(statuses{k}));
        T.(statuses{k})(rows) = "unavailable_" + string(reason);
    end
end
if ismember('RawSetStatus', T.Properties.VariableNames)
    T.RawSetStatus = string(T.RawSetStatus);
    T.RawSetStatus(rows) = "unavailable_" + string(reason);
end
writetable(T, P.subjectLevelEEGTableFile);
end
