function [allCycleQC, allSegmentSummary, allEdgeEvents] = ...
    step04_check_grf_gait_cycles(grfRootFolder, varargin)
% GOAL
%   Validate the already detected GRF gait-event sequences and identify
%   RHS-to-RHS cycles suitable for later EEG epoching.
% INPUT
%   Step 03 GRF gait-event outputs below GRF_segmentation_output.
%   An explicit GRF root folder may optionally be supplied.
% APPROACH
%   1. Collect every unique condition/run gait-event source.
%   2. Validate RHS -> LTO -> LHS -> RTO -> RHS sequence structure.
%   3. Apply stride-duration and robust outlier QC.
%   4. Exclude edge cycles conservatively when configured.
%   5. Save one all-subject set of derived QC tables.
% OUTPUT
%   GRF_gait_cycle_QC_all_subjects.csv
%   GRF_gait_cycle_QC_summary_all_subjects.csv
%   GRF_gait_edge_events_QC_all_subjects.csv
%   GRF_RHS_timewarp_cycles_recommended_all_subjects.csv
% USED BY
%   Step 12 RHS epoching and time-warp generation.

%% Resolve input folder

runFolder = fileparts(mfilename('fullpath'));
scriptsRoot = fileparts(runFolder);

addpath(scriptsRoot, '-begin');
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

%% Settings

parser = inputParser;

addParameter(parser, 'ExcludeFirstAndLastCycle', ...
    cfg.cycleQC.excludeFirstAndLastCycle, ...
    @(x) islogical(x) && isscalar(x));

addParameter(parser, 'MinimumStrideSec', ...
    cfg.cycleQC.minimumStrideSec, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);

addParameter(parser, 'MaximumStrideSec', ...
    cfg.cycleQC.maximumStrideSec, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);

addParameter(parser, 'RobustOutlierZ', ...
    cfg.cycleQC.robustOutlierZ, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);

parse(parser, varargin{:});

settings = parser.Results;

if settings.MaximumStrideSec <= settings.MinimumStrideSec
    error('MaximumStrideSec must be greater than MinimumStrideSec.');
end

%% Collect every unique condition/run from existing batch outputs

eventSources = collect_existing_event_sources(grfRootFolder);

allCycleQC = empty_cycle_table();
allSegmentSummary = empty_summary_table();
allEdgeEvents = empty_edge_event_table();

fprintf('Validating %d GRF condition/run sources.\n', numel(eventSources));

%% Validate every unique condition/run

for iSource = 1:numel(eventSources)

    currentEventFile = eventSources(iSource).SourceEventFile;
    eventTable = eventSources(iSource).EventTable;

    fprintf('\n[%d/%d] Validating %s source:\n%s\n', ...
        iSource, numel(eventSources), ...
        eventSources(iSource).SourceKind, ...
        currentEventFile);

    [cycleQC, segmentSummary, edgeEvents] = ...
        validate_one_event_table( ...
            eventTable, currentEventFile, settings);

    if isempty(allCycleQC)
        allCycleQC = cycleQC;
    else
        allCycleQC = [allCycleQC; cycleQC]; %#ok<AGROW>
    end

    if isempty(allSegmentSummary)
        allSegmentSummary = segmentSummary;
    else
        allSegmentSummary = [ ...
            allSegmentSummary; segmentSummary]; %#ok<AGROW>
    end

    if isempty(allEdgeEvents)
        allEdgeEvents = edgeEvents;
    else
        allEdgeEvents = [allEdgeEvents; edgeEvents]; %#ok<AGROW>
    end

    fprintf('Cycles: %d | logic valid: %d | recommended: %d\n', ...
        height(cycleQC), ...
        sum(cycleQC.LogicValid), ...
        sum(cycleQC.RecommendedForEpoch));
end

%% Write all-subject master outputs in one root QC folder

if ~isempty(allCycleQC)
    allCycleQC = sortrows(allCycleQC, ...
        {'Subject', 'RHS1_LSLTime', 'SegmentIndex', 'CycleIndex'});
end

if ~isempty(allSegmentSummary)
    allSegmentSummary = sortrows(allSegmentSummary, ...
        {'Subject', 'RecordingStartLSLTime', 'SegmentIndex'});
end

if ~isempty(allEdgeEvents)
    allEdgeEvents = sortrows(allEdgeEvents, ...
        {'Subject', 'XDFPath', 'SegmentIndex', 'LSLTime'});
end

masterQCFolder = fullfile(grfRootFolder, 'grf_quality_check');

if ~isfolder(masterQCFolder)
    mkdir(masterQCFolder);
end

masterCycleFile = fullfile( ...
    masterQCFolder, 'GRF_gait_cycle_QC_all_subjects.csv');

masterSummaryFile = fullfile( ...
    masterQCFolder, 'GRF_gait_cycle_QC_summary_all_subjects.csv');

masterEdgeFile = fullfile( ...
    masterQCFolder, 'GRF_gait_edge_events_QC_all_subjects.csv');

masterRecommendedFile = fullfile( ...
    masterQCFolder, ...
    'GRF_RHS_timewarp_cycles_recommended_all_subjects.csv');

writetable(allCycleQC, masterCycleFile);
writetable(allSegmentSummary, masterSummaryFile);
writetable(allEdgeEvents, masterEdgeFile);

allRecommendedCycles = ...
    allCycleQC(allCycleQC.RecommendedForEpoch, :);

writetable(allRecommendedCycles, masterRecommendedFile);

%% Console summary

fprintf('\nGRF gait-cycle validation finished.\n');
fprintf('Total RHS-to-RHS cycles: %d\n', height(allCycleQC));
fprintf('Logic-valid cycles: %d\n', sum(allCycleQC.LogicValid));
fprintf('Logic-invalid cycles: %d\n', sum(~allCycleQC.LogicValid));
fprintf('Recommended RHS/timewarp cycles: %d\n', ...
    sum(allCycleQC.RecommendedForEpoch));
fprintf('Cycles requiring raw-GRF review: %d\n', ...
    sum(allCycleQC.ManualGRFReviewRecommended));


reviewRows = allSegmentSummary( ...
    allSegmentSummary.SegmentStatus == "needs_raw_grf_review", :);

if ~isempty(reviewRows)
    warning([ ...
        '%d segment(s) contain internal sequence errors or stride ' ...
        'outliers. Inspect their original GRF waveform before epoching.'], ...
        height(reviewRows));
end

end


function eventSources = collect_existing_event_sources(grfRootFolder)

sourceTemplate = struct( ...
    'EventTable', table(), ...
    'SourceEventFile', '', ...
    'SourceKind', '', ...
    'OutputFolder', '', ...
    'Subject', "", ...
    'FirstLSLTime', NaN);

eventSources = repmat(sourceTemplate, 0, 1);
seenXDFKeys = strings(0, 1);

%% Preferred source: one authoritative MAT file per XDF/condition

matFileInfo = dir(fullfile( ...
    grfRootFolder, '**', '*_GRF_gait_events.mat'));

if ~isempty(matFileInfo)

    matFilePaths = string(fullfile( ...
        {matFileInfo.folder}, {matFileInfo.name}));

    matFilePaths = sort(unique(matFilePaths(:), 'stable'));

    for iFile = 1:numel(matFilePaths)

        currentFile = char(matFilePaths(iFile));

        try
            loadedData = load(currentFile, 'allEventTable');
        catch loadError
            warning('Could not load event MAT:\n%s\nReason: %s', ...
                currentFile, loadError.message);
            continue;
        end

        if ~isfield(loadedData, 'allEventTable') || ...
                ~istable(loadedData.allEventTable)
            warning([ ...
                'Skipping MAT without a table named allEventTable:\n%s'], ...
                currentFile);
            continue;
        end

        [eventSources, seenXDFKeys] = append_unseen_xdf_sources( ...
            eventSources, seenXDFKeys, ...
            loadedData.allEventTable, currentFile, 'per-XDF MAT');
    end
end

%% Fallback source: current CSV plus the condition snapshots in backups

currentCSVInfo = dir(fullfile( ...
    grfRootFolder, '**', 'grf_gait_events.csv'));

backupCSVInfo = dir(fullfile( ...
    grfRootFolder, '**', 'grf_gait_events_backup_*.csv'));

% Prefer the current CSV. Read backup snapshots newest-first only for XDFs
% that were not already represented by a MAT/current CSV source.
if ~isempty(backupCSVInfo)
    [~, backupOrder] = sort([backupCSVInfo.datenum], 'descend');
    backupCSVInfo = backupCSVInfo(backupOrder);
end

csvFileInfo = [currentCSVInfo(:); backupCSVInfo(:)];

for iFile = 1:numel(csvFileInfo)

    currentFile = fullfile( ...
        csvFileInfo(iFile).folder, csvFileInfo(iFile).name);

    try
        currentTable = readtable( ...
            currentFile, ...
            'TextType', 'string', ...
            'VariableNamingRule', 'preserve');
    catch readError
        warning('Could not read event CSV:\n%s\nReason: %s', ...
            currentFile, readError.message);
        continue;
    end

    [eventSources, seenXDFKeys] = append_unseen_xdf_sources( ...
        eventSources, seenXDFKeys, currentTable, currentFile, ...
        'CSV fallback');
end

if isempty(eventSources)
    error([ ...
        'No usable GRF gait-event MAT or CSV source was found below:\n%s'], ...
        grfRootFolder);
end

% Preserve the real recording order within every subject. File modification
% time and backup filename are not used as experimental timing evidence.
sourceOrderTable = table( ...
    (1:numel(eventSources))', ...
    string({eventSources.Subject})', ...
    [eventSources.FirstLSLTime]', ...
    'VariableNames', {'OriginalIndex', 'Subject', 'FirstLSLTime'});

sourceOrderTable = sortrows( ...
    sourceOrderTable, {'Subject', 'FirstLSLTime'});

eventSources = eventSources(sourceOrderTable.OriginalIndex);

matSourceCount = sum(strcmp( ...
    {eventSources.SourceKind}, 'per-XDF MAT'));

csvSourceCount = sum(strcmp( ...
    {eventSources.SourceKind}, 'CSV fallback'));

fprintf('Event sources selected: %d MAT, %d CSV fallback.\n', ...
    matSourceCount, csvSourceCount);

end


function [eventSources, seenXDFKeys] = append_unseen_xdf_sources( ...
    eventSources, seenXDFKeys, eventTable, sourceFile, sourceKind)

if ~istable(eventTable) || isempty(eventTable)
    return;
end

if ~ismember('XDFPath', eventTable.Properties.VariableNames)
    warning('Skipping event source without XDFPath:\n%s', sourceFile);
    return;
end

xdfPaths = strtrim(string(eventTable.XDFPath));
uniqueXDFPaths = unique(xdfPaths, 'stable');

for iXDF = 1:numel(uniqueXDFPaths)

    currentXDF = uniqueXDFPaths(iXDF);

    if ismissing(currentXDF) || strlength(currentXDF) == 0
        continue;
    end

    normalizedKey = lower(replace(currentXDF, '/', '\'));

    if any(seenXDFKeys == normalizedKey)
        continue;
    end

    currentRows = xdfPaths == currentXDF;

    currentEventTable = eventTable(currentRows, :);

    if ismember('Subject', currentEventTable.Properties.VariableNames)
        sourceSubject = string(currentEventTable.Subject(1));
    else
        sourceSubject = "unknown";
    end

    if ismember('LSLTime', currentEventTable.Properties.VariableNames)
        sourceLSLTimes = numeric_column_local( ...
            currentEventTable.LSLTime);
        sourceLSLTimes = sourceLSLTimes(isfinite(sourceLSLTimes));
    else
        sourceLSLTimes = [];
    end

    if isempty(sourceLSLTimes)
        firstLSLTime = Inf;
    else
        firstLSLTime = min(sourceLSLTimes);
    end

    sourceEntry = struct( ...
        'EventTable', currentEventTable, ...
        'SourceEventFile', sourceFile, ...
        'SourceKind', sourceKind, ...
        'OutputFolder', fileparts(sourceFile), ...
        'Subject', sourceSubject, ...
        'FirstLSLTime', firstLSLTime);

    eventSources(end + 1, 1) = sourceEntry; %#ok<AGROW>
    seenXDFKeys(end + 1, 1) = normalizedKey; %#ok<AGROW>
end

end


function [cycleQC, segmentSummary, edgeEvents] = ...
    validate_one_event_table(eventTable, sourceEventFile, settings)

requiredVariables = { ...
    'Subject', ...
    'Day', ...
    'Session', ...
    'Condition', ...
    'SegmentIndex', ...
    'EventType', ...
    'Side', ...
    'GRFSample', ...
    'SegmentSample', ...
    'LSLTime', ...
    'TimeFromSegmentStartSec', ...
    'XDFPath', ...
    'SourceGRFFile'};

missingVariables = requiredVariables( ...
    ~ismember(requiredVariables, eventTable.Properties.VariableNames));

if ~isempty(missingVariables)
    error('Event source is missing required columns: %s\nFile: %s', ...
        strjoin(missingVariables, ', '), sourceEventFile);
end

stringVariables = { ...
    'Subject', 'Day', 'Session', 'Condition', 'EventType', ...
    'Side', 'XDFPath', 'SourceGRFFile'};

for iVariable = 1:numel(stringVariables)
    variableName = stringVariables{iVariable};
    eventTable.(variableName) = ...
        strtrim(string(eventTable.(variableName)));
end

eventTable.EventType = upper(eventTable.EventType);

numericVariables = { ...
    'SegmentIndex', 'GRFSample', 'SegmentSample', ...
    'LSLTime', 'TimeFromSegmentStartSec'};

for iVariable = 1:numel(numericVariables)
    variableName = numericVariables{iVariable};
    eventTable.(variableName) = ...
        numeric_column_local(eventTable.(variableName));
end

if any(~isfinite(eventTable.SegmentIndex)) || ...
        any(~isfinite(eventTable.SegmentSample)) || ...
        any(~isfinite(eventTable.LSLTime))
    error([ ...
        'Event source contains non-numeric segment/sample/time values:\n%s'], ...
        sourceEventFile);
end

knownEventTypes = ["RHS", "LTO", "LHS", "RTO"];
unknownEventTypes = unique(eventTable.EventType( ...
    ~ismember(eventTable.EventType, knownEventTypes)));

if ~isempty(unknownEventTypes)
    warning('Unknown event type(s) in %s: %s', ...
        sourceEventFile, strjoin(unknownEventTypes, ', '));
end

cycleQC = empty_cycle_table();
segmentSummary = empty_summary_table();
edgeEvents = empty_edge_event_table();

xdfPaths = unique(eventTable.XDFPath, 'stable');

for iXDF = 1:numel(xdfPaths)

    currentXDF = xdfPaths(iXDF);
    xdfRows = eventTable.XDFPath == currentXDF;
    segmentIndices = unique(eventTable.SegmentIndex(xdfRows), 'stable');

    for iSegment = 1:numel(segmentIndices)

        currentSegment = segmentIndices(iSegment);

        currentRows = xdfRows & ...
            eventTable.SegmentIndex == currentSegment;

        segmentEvents = eventTable(currentRows, :);
        segmentEvents = sortrows(segmentEvents, ...
            {'SegmentSample', 'LSLTime'});

        [currentCycles, currentSummary, currentEdgeEvents] = ...
            validate_one_segment( ...
                segmentEvents, sourceEventFile, settings);

        if isempty(cycleQC)
            cycleQC = currentCycles;
        else
            cycleQC = [cycleQC; currentCycles]; %#ok<AGROW>
        end

        if isempty(segmentSummary)
            segmentSummary = currentSummary;
        else
            segmentSummary = [ ...
                segmentSummary; currentSummary]; %#ok<AGROW>
        end

        if isempty(edgeEvents)
            edgeEvents = currentEdgeEvents;
        else
            edgeEvents = [edgeEvents; currentEdgeEvents]; %#ok<AGROW>
        end
    end
end

end


function [cycleQC, summaryTable, edgeEvents] = ...
    validate_one_segment(segmentEvents, sourceEventFile, settings)

eventTypes = string(segmentEvents.EventType);
rhsRows = find(eventTypes == "RHS");
numberOfCycles = max(0, numel(rhsRows) - 1);

cycleRows = repmat(cycle_row_template(), 0, 1);

subject = string(segmentEvents.Subject(1));
day = string(segmentEvents.Day(1));
session = string(segmentEvents.Session(1));
condition = string(segmentEvents.Condition(1));
xdfPath = string(segmentEvents.XDFPath(1));
sourceGRFFile = string(segmentEvents.SourceGRFFile(1));
segmentIndex = double(segmentEvents.SegmentIndex(1));
runLabel = extract_run_label(xdfPath);

[~, xdfBaseName] = fileparts(char(xdfPath));

for iCycle = 1:numberOfCycles

    firstRHSRow = rhsRows(iCycle);
    secondRHSRow = rhsRows(iCycle + 1);
    cycleIndices = firstRHSRow:secondRHSRow;
    sequence = eventTypes(cycleIndices);

    row = cycle_row_template();

    row.SourceEventFile = string(sourceEventFile);
    row.Subject = subject;
    row.Day = day;
    row.Session = session;
    row.Condition = condition;
    row.Run = runLabel;
    row.XDFPath = xdfPath;
    row.SourceGRFFile = sourceGRFFile;
    row.SegmentIndex = segmentIndex;
    row.CycleIndex = iCycle;
    row.CycleID = string(sprintf( ...
        '%s_segment-%02d_cycle-%04d', ...
        xdfBaseName, round(segmentIndex), iCycle));

    row.SequenceObserved = strjoin(sequence, "-");
    row.LTOCount = sum(sequence == "LTO");
    row.LHSCount = sum(sequence == "LHS");
    row.RTOCount = sum(sequence == "RTO");
    row.RHSCountInWindow = sum(sequence == "RHS");

    expectedSequence = ["RHS"; "LTO"; "LHS"; "RTO"; "RHS"];

    row.LogicValid = ...
        numel(sequence) == numel(expectedSequence) && ...
        all(sequence(:) == expectedSequence);

    row.EdgeCycle = ...
        iCycle == 1 || iCycle == numberOfCycles;

    row.RHS1_GRFSample = ...
        segmentEvents.GRFSample(firstRHSRow);

    row.RHS2_GRFSample = ...
        segmentEvents.GRFSample(secondRHSRow);

    row.RHS1_SegmentSample = ...
        segmentEvents.SegmentSample(firstRHSRow);

    row.RHS2_SegmentSample = ...
        segmentEvents.SegmentSample(secondRHSRow);

    row.RHS1_LSLTime = segmentEvents.LSLTime(firstRHSRow);
    row.RHS2_LSLTime = segmentEvents.LSLTime(secondRHSRow);

    row.RHS1_TimeFromSegmentStartSec = ...
        segmentEvents.TimeFromSegmentStartSec(firstRHSRow);

    row.RHS2_TimeFromSegmentStartSec = ...
        segmentEvents.TimeFromSegmentStartSec(secondRHSRow);

    row.LTO_GRFSample = first_event_value( ...
        segmentEvents, eventTypes, cycleIndices, ...
        "LTO", 'GRFSample');

    row.LHS_GRFSample = first_event_value( ...
        segmentEvents, eventTypes, cycleIndices, ...
        "LHS", 'GRFSample');

    row.RTO_GRFSample = first_event_value( ...
        segmentEvents, eventTypes, cycleIndices, ...
        "RTO", 'GRFSample');

    row.LTO_LSLTime = first_event_value( ...
        segmentEvents, eventTypes, cycleIndices, ...
        "LTO", 'LSLTime');

    row.LHS_LSLTime = first_event_value( ...
        segmentEvents, eventTypes, cycleIndices, ...
        "LHS", 'LSLTime');

    row.RTO_LSLTime = first_event_value( ...
        segmentEvents, eventTypes, cycleIndices, ...
        "RTO", 'LSLTime');

    row.LTO_TimeFromSegmentStartSec = first_event_value( ...
        segmentEvents, eventTypes, cycleIndices, ...
        "LTO", 'TimeFromSegmentStartSec');

    row.LHS_TimeFromSegmentStartSec = first_event_value( ...
        segmentEvents, eventTypes, cycleIndices, ...
        "LHS", 'TimeFromSegmentStartSec');

    row.RTO_TimeFromSegmentStartSec = first_event_value( ...
        segmentEvents, eventTypes, cycleIndices, ...
        "RTO", 'TimeFromSegmentStartSec');

    row.StrideSec = row.RHS2_LSLTime - row.RHS1_LSLTime;

    if row.LTOCount == 1 && row.LHSCount == 1 && ...
            row.RTOCount == 1

        row.RHS_to_LTO_Sec = ...
            row.LTO_LSLTime - row.RHS1_LSLTime;

        row.LTO_to_LHS_Sec = ...
            row.LHS_LSLTime - row.LTO_LSLTime;

        row.LHS_to_RTO_Sec = ...
            row.RTO_LSLTime - row.LHS_LSLTime;

        row.RTO_to_RHS2_Sec = ...
            row.RHS2_LSLTime - row.RTO_LSLTime;

        row.RightStanceSec = ...
            row.RTO_LSLTime - row.RHS1_LSLTime;
    end

    row.AbsoluteStrideFlag = ...
        ~isfinite(row.StrideSec) || ...
        row.StrideSec < settings.MinimumStrideSec || ...
        row.StrideSec > settings.MaximumStrideSec;

    row.QCReason = structural_reason( ...
        sequence, row.LTOCount, row.LHSCount, row.RTOCount, ...
        row.LogicValid);

    cycleRows(end + 1, 1) = row; %#ok<AGROW>
end

if isempty(cycleRows)
    cycleQC = empty_cycle_table();
else
    cycleQC = struct2table(cycleRows);
end

%% Robust stride outlier detection within this segment

if ~isempty(cycleQC)

    usableForReference = ...
        cycleQC.LogicValid & ...
        isfinite(cycleQC.StrideSec) & ...
        ~cycleQC.AbsoluteStrideFlag;

    referenceStrides = cycleQC.StrideSec(usableForReference);

    if numel(referenceStrides) >= 5

        strideMedian = median(referenceStrides);
        strideMAD = median(abs(referenceStrides - strideMedian));

        if isfinite(strideMAD) && strideMAD > eps(strideMedian)

            robustScale = 1.4826 * strideMAD;
            robustDistance = abs( ...
                cycleQC.StrideSec - strideMedian) ./ robustScale;

            cycleQC.RobustStrideOutlier = ...
                cycleQC.LogicValid & ...
                isfinite(robustDistance) & ...
                robustDistance > settings.RobustOutlierZ;
        end
    end

    cycleQC.StrideFlag = ...
        cycleQC.AbsoluteStrideFlag | ...
        cycleQC.RobustStrideOutlier;

    conservativeEdgeExclusion = ...
        settings.ExcludeFirstAndLastCycle & cycleQC.EdgeCycle;

    cycleQC.RecommendedForEpoch = ...
        cycleQC.LogicValid & ...
        ~cycleQC.StrideFlag & ...
        ~conservativeEdgeExclusion;

    cycleQC.ManualGRFReviewRecommended = ...
        (~cycleQC.LogicValid & ~cycleQC.EdgeCycle) | ...
        cycleQC.StrideFlag;

    for iCycle = 1:height(cycleQC)

        reason = cycleQC.QCReason(iCycle);

        if cycleQC.AbsoluteStrideFlag(iCycle)
            reason = append_reason(reason, sprintf( ...
                'StrideOutside%.2fTo%.2fSec', ...
                settings.MinimumStrideSec, ...
                settings.MaximumStrideSec));
        end

        if cycleQC.RobustStrideOutlier(iCycle)
            reason = append_reason(reason, 'RobustStrideOutlier');
        end

        if conservativeEdgeExclusion(iCycle)
            reason = append_reason( ...
                reason, 'ConservativeSegmentEdgeExclusion');
        end

        if strlength(reason) == 0
            reason = "OK";
        end

        cycleQC.QCReason(iCycle) = reason;
    end
end

%% Leading and trailing partial events

edgeEvents = build_edge_event_table( ...
    segmentEvents, rhsRows, sourceEventFile, runLabel);

leadingEventCount = sum( ...
    edgeEvents.EdgePosition == "before_first_RHS");

trailingPartialEventCount = sum( ...
    edgeEvents.EdgePosition == "trailing_partial_cycle");

%% Segment summary

summary = summary_row_template();
summary.SourceEventFile = string(sourceEventFile);
summary.Subject = subject;
summary.Day = day;
summary.Session = session;
summary.Condition = condition;
summary.Run = runLabel;
summary.XDFPath = xdfPath;
summary.SourceGRFFile = sourceGRFFile;
summary.SegmentIndex = segmentIndex;
summary.RecordingStartLSLTime = min(segmentEvents.LSLTime);
summary.TotalEventCount = height(segmentEvents);
summary.RHSCount = numel(rhsRows);
summary.CycleCount = height(cycleQC);
summary.LogicValidCycleCount = sum(cycleQC.LogicValid);
summary.LogicInvalidCycleCount = sum(~cycleQC.LogicValid);
summary.InternalInvalidCycleCount = sum( ...
    ~cycleQC.LogicValid & ~cycleQC.EdgeCycle);
summary.EdgeInvalidCycleCount = sum( ...
    ~cycleQC.LogicValid & cycleQC.EdgeCycle);
summary.StrideFlagCount = sum(cycleQC.StrideFlag);
summary.RecommendedCycleCount = sum(cycleQC.RecommendedForEpoch);
summary.ManualGRFReviewCycleCount = sum( ...
    cycleQC.ManualGRFReviewRecommended);
summary.LeadingEventCount = leadingEventCount;
summary.TrailingPartialEventCount = trailingPartialEventCount;

finiteStrides = cycleQC.StrideSec(isfinite(cycleQC.StrideSec));

if ~isempty(finiteStrides)
    summary.MedianStrideSec = median(finiteStrides);
    summary.MinimumStrideSec = min(finiteStrides);
    summary.MaximumStrideSec = max(finiteStrides);
end

if numel(rhsRows) < 2
    summary.SegmentStatus = "fail_no_complete_RHS_cycle";
elseif summary.InternalInvalidCycleCount > 0 || ...
        summary.StrideFlagCount > 0
    summary.SegmentStatus = "needs_raw_grf_review";
elseif summary.LogicInvalidCycleCount > 0 || ...
        leadingEventCount > 0 || trailingPartialEventCount > 0
    summary.SegmentStatus = "pass_with_edge_exclusions";
else
    summary.SegmentStatus = "pass";
end

summaryTable = struct2table(summary);

end


function edgeTable = build_edge_event_table( ...
    segmentEvents, rhsRows, sourceEventFile, runLabel)

edgeRows = repmat(edge_event_row_template(), 0, 1);

if isempty(rhsRows)

    edgeIndices = 1:height(segmentEvents);
    edgePositions = repmat("no_RHS_in_segment", ...
        numel(edgeIndices), 1);

else

    leadingIndices = 1:(rhsRows(1) - 1);

    % Include the final RHS only when later events form an unfinished cycle.
    if rhsRows(end) < height(segmentEvents)
        trailingIndices = rhsRows(end):height(segmentEvents);
    else
        trailingIndices = zeros(1, 0);
    end

    edgeIndices = [leadingIndices, trailingIndices];

    edgePositions = [ ...
        repmat("before_first_RHS", numel(leadingIndices), 1); ...
        repmat("trailing_partial_cycle", ...
            numel(trailingIndices), 1)];
end

for iEvent = 1:numel(edgeIndices)

    sourceRow = edgeIndices(iEvent);
    row = edge_event_row_template();

    row.SourceEventFile = string(sourceEventFile);
    row.Subject = string(segmentEvents.Subject(sourceRow));
    row.Day = string(segmentEvents.Day(sourceRow));
    row.Session = string(segmentEvents.Session(sourceRow));
    row.Condition = string(segmentEvents.Condition(sourceRow));
    row.Run = runLabel;
    row.XDFPath = string(segmentEvents.XDFPath(sourceRow));
    row.SourceGRFFile = ...
        string(segmentEvents.SourceGRFFile(sourceRow));
    row.SegmentIndex = ...
        double(segmentEvents.SegmentIndex(sourceRow));
    row.EventType = string(segmentEvents.EventType(sourceRow));
    row.Side = string(segmentEvents.Side(sourceRow));
    row.GRFSample = double(segmentEvents.GRFSample(sourceRow));
    row.SegmentSample = ...
        double(segmentEvents.SegmentSample(sourceRow));
    row.LSLTime = double(segmentEvents.LSLTime(sourceRow));
    row.TimeFromSegmentStartSec = double( ...
        segmentEvents.TimeFromSegmentStartSec(sourceRow));
    row.EdgePosition = edgePositions(iEvent);

    edgeRows(end + 1, 1) = row; %#ok<AGROW>
end

if isempty(edgeRows)
    edgeTable = empty_edge_event_table();
else
    edgeTable = struct2table(edgeRows);
end

end


function reason = structural_reason( ...
    sequence, ltoCount, lhsCount, rtoCount, logicValid)

if logicValid
    reason = "";
    return;
end

reasons = strings(0, 1);

reasons = add_count_reason(reasons, "LTO", ltoCount);
reasons = add_count_reason(reasons, "LHS", lhsCount);
reasons = add_count_reason(reasons, "RTO", rtoCount);

knownTypes = ["RHS", "LTO", "LHS", "RTO"];
unknownTypes = unique(sequence(~ismember(sequence, knownTypes)));

if ~isempty(unknownTypes)
    reasons(end + 1, 1) = ...
        "UnexpectedEventType(" + strjoin(unknownTypes, "+") + ")";
end

if isempty(reasons)
    reasons(end + 1, 1) = "WrongEventOrder";
end

reason = strjoin(reasons, ";");

end


function reasons = add_count_reason(reasons, eventType, count)

if count == 0
    reasons(end + 1, 1) = "Missing" + eventType;
elseif count > 1
    reasons(end + 1, 1) = ...
        "Duplicate" + eventType + "(" + string(count) + ")";
end

end


function value = first_event_value( ...
    eventTable, eventTypes, cycleIndices, targetType, variableName)

matchingRows = cycleIndices( ...
    eventTypes(cycleIndices) == targetType);

if isempty(matchingRows)
    value = NaN;
else
    value = double(eventTable.(variableName)(matchingRows(1)));
end

end


function outputReason = append_reason(inputReason, newReason)

inputReason = string(inputReason);
newReason = string(newReason);

if strlength(inputReason) == 0
    outputReason = newReason;
else
    outputReason = inputReason + ";" + newReason;
end

end


function runLabel = extract_run_label(xdfPath)

tokens = regexp(char(xdfPath), ...
    'run-([0-9]+)', 'tokens', 'once');

if isempty(tokens)
    runLabel = "unknown";
else
    runLabel = "run-" + string(tokens{1});
end

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


function row = cycle_row_template()

row = struct( ...
    'SourceEventFile', "", ...
    'Subject', "", ...
    'Day', "", ...
    'Session', "", ...
    'Condition', "", ...
    'Run', "", ...
    'XDFPath', "", ...
    'SourceGRFFile', "", ...
    'SegmentIndex', NaN, ...
    'CycleIndex', NaN, ...
    'CycleID', "", ...
    'SequenceObserved', "", ...
    'LTOCount', NaN, ...
    'LHSCount', NaN, ...
    'RTOCount', NaN, ...
    'RHSCountInWindow', NaN, ...
    'LogicValid', false, ...
    'EdgeCycle', false, ...
    'RHS1_GRFSample', NaN, ...
    'LTO_GRFSample', NaN, ...
    'LHS_GRFSample', NaN, ...
    'RTO_GRFSample', NaN, ...
    'RHS2_GRFSample', NaN, ...
    'RHS1_SegmentSample', NaN, ...
    'RHS2_SegmentSample', NaN, ...
    'RHS1_LSLTime', NaN, ...
    'LTO_LSLTime', NaN, ...
    'LHS_LSLTime', NaN, ...
    'RTO_LSLTime', NaN, ...
    'RHS2_LSLTime', NaN, ...
    'RHS1_TimeFromSegmentStartSec', NaN, ...
    'LTO_TimeFromSegmentStartSec', NaN, ...
    'LHS_TimeFromSegmentStartSec', NaN, ...
    'RTO_TimeFromSegmentStartSec', NaN, ...
    'RHS2_TimeFromSegmentStartSec', NaN, ...
    'StrideSec', NaN, ...
    'RHS_to_LTO_Sec', NaN, ...
    'LTO_to_LHS_Sec', NaN, ...
    'LHS_to_RTO_Sec', NaN, ...
    'RTO_to_RHS2_Sec', NaN, ...
    'RightStanceSec', NaN, ...
    'AbsoluteStrideFlag', false, ...
    'RobustStrideOutlier', false, ...
    'StrideFlag', false, ...
    'RecommendedForEpoch', false, ...
    'ManualGRFReviewRecommended', false, ...
    'QCReason', "");

end


function tableOutput = empty_cycle_table()

tableOutput = struct2table(cycle_row_template());
tableOutput(1, :) = [];

end


function row = summary_row_template()

row = struct( ...
    'SourceEventFile', "", ...
    'Subject', "", ...
    'Day', "", ...
    'Session', "", ...
    'Condition', "", ...
    'Run', "", ...
    'XDFPath', "", ...
    'SourceGRFFile', "", ...
    'SegmentIndex', NaN, ...
    'RecordingStartLSLTime', NaN, ...
    'TotalEventCount', NaN, ...
    'RHSCount', NaN, ...
    'CycleCount', NaN, ...
    'LogicValidCycleCount', NaN, ...
    'LogicInvalidCycleCount', NaN, ...
    'InternalInvalidCycleCount', NaN, ...
    'EdgeInvalidCycleCount', NaN, ...
    'StrideFlagCount', NaN, ...
    'RecommendedCycleCount', NaN, ...
    'ManualGRFReviewCycleCount', NaN, ...
    'LeadingEventCount', NaN, ...
    'TrailingPartialEventCount', NaN, ...
    'MedianStrideSec', NaN, ...
    'MinimumStrideSec', NaN, ...
    'MaximumStrideSec', NaN, ...
    'SegmentStatus', "");

end


function tableOutput = empty_summary_table()

tableOutput = struct2table(summary_row_template());
tableOutput(1, :) = [];

end


function row = edge_event_row_template()

row = struct( ...
    'SourceEventFile', "", ...
    'Subject', "", ...
    'Day', "", ...
    'Session', "", ...
    'Condition', "", ...
    'Run', "", ...
    'XDFPath', "", ...
    'SourceGRFFile', "", ...
    'SegmentIndex', NaN, ...
    'EventType', "", ...
    'Side', "", ...
    'GRFSample', NaN, ...
    'SegmentSample', NaN, ...
    'LSLTime', NaN, ...
    'TimeFromSegmentStartSec', NaN, ...
    'EdgePosition', "");

end


function tableOutput = empty_edge_event_table()

tableOutput = struct2table(edge_event_row_template());
tableOutput(1, :) = [];

end
