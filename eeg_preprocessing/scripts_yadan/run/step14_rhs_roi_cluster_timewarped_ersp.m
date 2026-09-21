% GOAL
%   Compute time-warped gait-cycle ERSPs for ROI clusters that passed Step 13.
%
% OUTPUT
%   Only outputs used for analysis/reporting:
%   1) one final ERSP heatmap PNG per ROI;
%   2) one MAT per ROI with subject/group ERSP and essential settings;
%   3) ROI_condition_subject_coverage.csv with actual subject/IC contributors.
%   Band/phase summaries remain inside the ROI MAT files; no summary CSV.
%
% NOTES
%   - One common baseline is applied across conditions.
%   - If a subject contributes multiple ICs to one ROI cluster, the lowest
%     numeric IC index is retained.
%   - Subjects are averaged equally at group level.
%   - Existing TF caches are reused when their scientific inputs are unchanged.

clear;
clc;

%% SETTINGS AND PATHS

runFolder = fileparts(mfilename('fullpath'));
scriptsRoot = fileparts(runFolder);

addpath(scriptsRoot, '-begin');
addpath(fullfile(scriptsRoot, 'config'), '-begin');

P = project_paths();
cfg = config_step12_14_clustering_roi_ersp();

processingVersion = string(cfg.ersp.processingVersion) + "_SLIM";

numberOfClusters = cfg.clustering.numberOfClusters;
numberOfRepetitions = cfg.clustering.numberOfRepetitions;

forceRecomputeERSP = cfg.ersp.forceRecomputeERSP;

frequencyRangeHz = cfg.ersp.frequencyRangeHz;
waveletCycles = cfg.ersp.waveletCycles;
numberOfFrequencies = cfg.ersp.numberOfFrequencies;
numberOfTimePoints = cfg.ersp.numberOfTimePoints;
paddingRatio = cfg.ersp.paddingRatio;

baselineNormalization = cfg.ersp.baselineNormalization;
trialBaselineMode = cfg.ersp.trialBaselineMode;

conditionOrder = string(cfg.ersp.conditionOrder(:));
conditionDisplayLabels = string(cfg.ersp.conditionDisplayLabels(:));
gaitEventNames = string(cfg.ersp.gaitEventNames(:));

summaryBandNames = string(cfg.ersp.summaryBandNames(:));
summaryBandRangesHz = double(cfg.ersp.summaryBandRangesHz);
gaitPhaseNames = string(cfg.ersp.gaitPhaseNames(:));
gaitPhaseDisplayLabels = string(cfg.ersp.gaitPhaseDisplayLabels(:));

assert(size(summaryBandRangesHz, 2) == 2 && ...
    size(summaryBandRangesHz, 1) == numel(summaryBandNames), ...
    'ERSP summary band names and ranges are inconsistent.');

outputFolder = P.outputFolder;

assert(exist('eeglab', 'file') == 2, ...
    'EEGLAB was not found after project_paths.m.');

[ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab('nogui'); %#ok<ASGLU>
pop_editoptions('option_storedisk', 1);

requiredFunctions = { ...
    'std_ersp', ...
    'std_combtrialinfo', ...
    'std_readfile', ...
    'newtimeftrialbaseln', ...
    'newtimefbaseln'};

for k = 1:numel(requiredFunctions)
    assert(exist(requiredFunctions{k}, 'file') == 2, ...
        'Required function is unavailable: %s', requiredFunctions{k});
end

%% INPUT / OUTPUT

rhsRoot = fullfile(outputFolder, cfg.clustering.rhsRootFolderName);

runRoot = fullfile( ...
    rhsRoot, ...
    cfg.clustering.outputFolderName, ...
    sprintf('K%02d_N%05d', numberOfClusters, numberOfRepetitions));

reviewWorkbook = fullfile( ...
    runRoot, ...
    cfg.roiClusterQC.qcFolderName, ...
    cfg.roiClusterQC.reviewWorkbookName);

erspOutputFolder = fullfile(rhsRoot, cfg.ersp.outputFolderName);
figureFolder = fullfile(erspOutputFolder, 'figures');
matrixFolder = fullfile(erspOutputFolder, 'matrices');

if ~isfolder(erspOutputFolder), mkdir(erspOutputFolder); end
if ~isfolder(figureFolder), mkdir(figureFolder); end
if ~isfolder(matrixFolder), mkdir(matrixFolder); end

%% READ STEP 13 REVIEW

reviewTable = readtable( ...
    reviewWorkbook, ...
    'Sheet', char(string(cfg.roiClusterQC.reviewSheetName)), ...
    'VariableNamingRule', 'preserve');

requiredColumns = { ...
    'ROIID', ...
    'OriginalClusterID', ...
    'ROIName', ...
    'SelectedClusterIndex', ...
    'ROIStudyPath', ...
    'ClusterAnatomyQC', ...
    'ClusterScalpQC', ...
    'ClusterSpectrumQC', ...
    'ClusterDecision', ...
    'ClusterReviewIdentity'};

for k = 1:numel(requiredColumns)
    assert(ismember(requiredColumns{k}, reviewTable.Properties.VariableNames), ...
        'Review table is missing column %s.', requiredColumns{k});
end

keepRows = upper(strtrim(string(reviewTable.ClusterDecision))) == ...
    upper(string(cfg.ersp.requiredClusterDecision));

assert(any(keepRows), 'No Step 13 ROI cluster is marked KEEP.');

selectedTable = reviewTable(keepRows, :);

assert(numel(unique(string(selectedTable.ROIID))) == height(selectedTable), ...
    'The review table contains duplicate retained ROI IDs.');

requiredManualValue = upper(string(cfg.ersp.requiredManualQCValue));
assert(all(upper(strtrim(string(selectedTable.ClusterAnatomyQC))) == requiredManualValue), ...
    'A retained ROI cluster has ClusterAnatomyQC ~= PASS.');
assert(all(upper(strtrim(string(selectedTable.ClusterScalpQC))) == requiredManualValue), ...
    'A retained ROI cluster has ClusterScalpQC ~= PASS.');
assert(all(upper(strtrim(string(selectedTable.ClusterSpectrumQC))) == requiredManualValue), ...
    'A retained ROI cluster has ClusterSpectrumQC ~= PASS.');

selectedTable.ROIStudyPath = string(selectedTable.ROIStudyPath);

for row = 1:height(selectedTable)
    selectedTable.ROIStudyPath(row) = resolve_study_path_local( ...
        selectedTable.ROIStudyPath(row), runRoot);
end

%% LOAD ROI STUDIES AND SELECT ONE IC PER SUBJECT

roiStudies = cell(height(selectedTable), 1);
roiSelections = cell(height(selectedTable), 1);

for row = 1:height(selectedTable)

    if row == 1
        [STUDY, firstALLEEG] = hipexo.load_study_with_headers( ...
            char(selectedTable.ROIStudyPath(row)), outputFolder);
        firstStudy = STUDY;
        firstDesignIndex = condition_design_local(STUDY);
        referenceDatasetKeys = dataset_keys_local(STUDY);
    else
        [STUDY, ~] = hipexo.load_study_with_headers( ...
            char(selectedTable.ROIStudyPath(row)), outputFolder, firstALLEEG);

        assert(isequal(referenceDatasetKeys, dataset_keys_local(STUDY)), ...
            'Retained ROI STUDYs do not reference the same RHS epoch datasets.');

        assert(condition_design_local(STUDY) == firstDesignIndex, ...
            'Retained ROI STUDYs do not use the same condition design.');
    end

    roiID = string(selectedTable.ROIID(row));
    clusterIndex = double(selectedTable.SelectedClusterIndex(row));

    assert_selected_cluster_local(STUDY, clusterIndex, roiID);

    roiDefinition = cfg.roi.table( ...
        string(cfg.roi.table.ROIID) == roiID & cfg.roi.table.Enabled, :);
    assert(height(roiDefinition) == 1, ...
        'Retained ROI %s is absent or disabled in the current configuration.', roiID);

    currentIdentity = hipexo.roi_review_identity( ...
        STUDY, firstALLEEG, clusterIndex, roiDefinition, cfg.roiClusterQC);

    assert(string(selectedTable.ClusterReviewIdentity(row)) == currentIdentity, ...
        '%s Step 13 review is stale. Rerun Step 13 before Step 14.', roiID);

    [~, uniqueMembers] = hipexo.cluster_membership(STUDY, clusterIndex);

    [subjects, ics] = lowest_ic_members_local( ...
        string(uniqueMembers.Subject), ...
        double(uniqueMembers.IC));

    roiSelections{row} = struct('subjects', subjects, 'ics', ics);
    roiStudies{row} = STUDY;
end

%% BUILD THE UNION OF REQUIRED COMPONENTS FOR TF PRECOMPUTE

tfStudy = firstStudy;

for datasetIndex = 1:numel(tfStudy.datasetinfo)

    subject = string(tfStudy.datasetinfo(datasetIndex).subject);
    keptICs = [];

    for row = 1:numel(roiSelections)
        selection = roiSelections{row};
        keptICs = [keptICs; selection.ics(selection.subjects == subject)]; %#ok<AGROW>
    end

    tfStudy.datasetinfo(datasetIndex).comps = unique(keptICs(:)');
end

componentCache = containers.Map('KeyType', 'char', 'ValueType', 'any');

%% COMMON TIME WARP AND BASELINE

groupWarpMs = group_median_warp_local(firstALLEEG);

assert(numel(groupWarpMs) == 5 && ...
    all(isfinite(groupWarpMs)) && ...
    all(diff(groupWarpMs) > 0), ...
    'Invalid group RHS-LTO-LHS-RTO-RHS time warp.');

groupWarpMs(1) = 0;
groupWarpPercent = 100 .* groupWarpMs ./ groupWarpMs(end);

assert(numel(gaitEventNames) == 5, ...
    'Five gait-event labels are required.');

assert(numel(gaitPhaseNames) == 4 && ...
    numel(gaitPhaseDisplayLabels) == 4, ...
    'Four gait-phase definitions are required.');

baselineValue = [0 groupWarpMs(end)];

erspParameters = { ...
    'cycles', waveletCycles, ...
    'freqs', frequencyRangeHz, ...
    'nfreqs', numberOfFrequencies, ...
    'ntimesout', numberOfTimePoints, ...
    'padratio', paddingRatio, ...
    'freqscale', 'log', ...
    'alpha', NaN, ...
    'savetrials', 'off', ...
    'baseline', baselineValue, ...
    'basenorm', baselineNormalization, ...
    'trialbase', trialBaselineMode, ...
    'timewarp', 0, ...
    'timewarpms', groupWarpMs};

%% COMPUTE / REUSE TF CACHES

tfCacheRecords = precompute_timewarped_component_ersp_local( ...
    tfStudy, firstALLEEG, forceRecomputeERSP, erspParameters);

analysisDefinition = struct( ...
    'baseline', baselineValue, ...
    'basenorm', baselineNormalization, ...
    'trialbase', trialBaselineMode, ...
    'conditionOrder', conditionOrder, ...
    'bandNames', summaryBandNames, ...
    'bandRangesHz', summaryBandRangesHz, ...
    'phaseNames', gaitPhaseNames, ...
    'phaseLabels', gaitPhaseDisplayLabels, ...
    'groupWarpMs', groupWarpMs);

processingSignature = hipexo.content_signature(struct( ...
    'version', processingVersion, ...
    'review', selectedTable(:, { ...
        'ROIID', ...
        'OriginalClusterID', ...
        'ROIName', ...
        'SelectedClusterIndex', ...
        'ClusterReviewIdentity'}), ...
    'tf', tfCacheRecords, ...
    'analysis', analysisDefinition));

%% ROI ERSP

allConditionCoverage = table();

for row = 1:height(selectedTable)

    roiID = string(selectedTable.ROIID(row));
    originalClusterID = string(selectedTable.OriginalClusterID(row));
    roiName = string(selectedTable.ROIName(row));
    clusterIndex = double(selectedTable.SelectedClusterIndex(row));

    fprintf('ROI %d / %d: %s | %s\n', ...
        row, height(selectedTable), char(roiID), char(roiName));

    STUDY = roiStudies{row};
    selection = roiSelections{row};

    conditionNames = design_condition_names_local(STUDY, firstDesignIndex);

    resultFile = fullfile( ...
        matrixFolder, ...
        sprintf('%s_timewarped_ERSP.mat', char(roiID)));

    figureFile = fullfile( ...
        figureFolder, ...
        sprintf('%s_timewarped_ERSP_all_conditions.png', char(roiID)));

    reuseROI = false;

    if ~forceRecomputeERSP && isfile(resultFile)
        try
            stored = load(resultFile, 'roiResult');
            reuseROI = isfield(stored, 'roiResult') && ...
                isfield(stored.roiResult, 'processing_signature') && ...
                isfield(stored.roiResult, 'band_phase_subject_summary') && ...
                string(stored.roiResult.processing_signature) == processingSignature;
        catch
            reuseROI = false;
        end
    end

    if reuseROI

        roiResult = stored.roiResult;

        fprintf('[REUSE] ERSP numerical result: %s\n', char(roiID));

        if ~isfile(figureFile)
            plotNames = condition_display_labels_local( ...
                string(roiResult.condition_names), ...
                conditionOrder, ...
                conditionDisplayLabels);

            plot_roi_heatmaps_local( ...
                roiResult.group_ersp, ...
                roiResult.contributing_subject_count, ...
                plotNames, ...
                roiResult.times_ms, ...
                roiResult.frequencies_hz, ...
                roiResult.group_timewarp_ms, ...
                gaitEventNames, ...
                roiID, ...
                roiName, ...
                figureFile);
        end

    else

        [subjectERSP, erspTimes, erspFreqs] = ...
            read_selected_components_ersp_local( ...
                STUDY, ...
                selection.subjects, ...
                selection.ics, ...
                conditionNames, ...
                [0 groupWarpMs(end)], ...
                frequencyRangeHz, ...
                baselineValue, ...
                baselineNormalization, ...
                trialBaselineMode, ...
                componentCache);

        [groupERSP, contributingSubjects] = ...
            average_one_ic_per_subject_local(subjectERSP);

        [conditionNames, subjectERSP, groupERSP, contributingSubjects] = ...
            reorder_conditions_local( ...
                conditionNames, ...
                subjectERSP, ...
                groupERSP, ...
                contributingSubjects, ...
                conditionOrder);

        plotNames = condition_display_labels_local( ...
            conditionNames, ...
            conditionOrder, ...
            conditionDisplayLabels);

        subjectBandPhaseSummary = summarize_subject_band_phase_local( ...
            subjectERSP, ...
            selection.subjects, ...
            conditionNames, ...
            plotNames, ...
            double(erspTimes(:)'), ...
            double(erspFreqs(:)'), ...
            groupWarpMs, ...
            gaitPhaseNames, ...
            gaitPhaseDisplayLabels, ...
            summaryBandNames, ...
            summaryBandRangesHz, ...
            roiID, ...
            originalClusterID, ...
            roiName);

        parameters = struct( ...
            'frequency_range_hz', frequencyRangeHz, ...
            'wavelet_cycles', waveletCycles, ...
            'number_of_frequencies', numberOfFrequencies, ...
            'number_of_time_points', numberOfTimePoints, ...
            'padding_ratio', paddingRatio, ...
            'baseline', baselineValue, ...
            'baseline_normalization', baselineNormalization, ...
            'trial_baseline_mode', trialBaselineMode, ...
            'ic_selection_rule', 'lowest numeric IC per subject');

        roiResult = struct();
        roiResult.roi_id = char(roiID);
        roiResult.original_cluster_id = char(originalClusterID);
        roiResult.roi_name = char(roiName);
        roiResult.cluster_index = clusterIndex;
        roiResult.review_identity = char(selectedTable.ClusterReviewIdentity(row));
        roiResult.condition_names = cellstr(conditionNames);
        roiResult.component_subjects = cellstr(selection.subjects);
        roiResult.component_ics = selection.ics;
        roiResult.subject_ersp = subjectERSP;
        roiResult.group_ersp = groupERSP;
        roiResult.contributing_subject_count = contributingSubjects;
        roiResult.times_ms = double(erspTimes(:)');
        roiResult.times_gait_cycle_percent = ...
            100 .* double(erspTimes(:)') ./ groupWarpMs(end);
        roiResult.frequencies_hz = double(erspFreqs(:)');
        roiResult.group_timewarp_ms = groupWarpMs;
        roiResult.group_timewarp_percent = groupWarpPercent;
        roiResult.parameters = parameters;
        roiResult.band_phase_subject_summary = subjectBandPhaseSummary;
        roiResult.processing_signature = char(processingSignature);

        save(resultFile, 'roiResult', '-v7.3');

        plot_roi_heatmaps_local( ...
            groupERSP, ...
            contributingSubjects, ...
            plotNames, ...
            double(erspTimes(:)'), ...
            double(erspFreqs(:)'), ...
            groupWarpMs, ...
            gaitEventNames, ...
            roiID, ...
            roiName, ...
            figureFile);
    end

    coverageRows = condition_subject_coverage_local(roiResult);

    if isempty(allConditionCoverage)
        allConditionCoverage = coverageRows;
    else
        allConditionCoverage = [allConditionCoverage; coverageRows]; %#ok<AGROW>
    end
end

%% ROI x CONDITION SUBJECT/IC COVERAGE

coverageFile = fullfile( ...
    erspOutputFolder, ...
    'ROI_condition_subject_coverage.csv');

writetable(allConditionCoverage, coverageFile);

fprintf('TIME-WARPED ERSP FINISHED\n');

%% LOCAL FUNCTIONS


function coverageTable = condition_subject_coverage_local(roiResult)

    roiID = string(roiResult.roi_id);
    roiName = string(roiResult.roi_name);
    conditionNames = string(roiResult.condition_names(:));
    subjects = string(roiResult.component_subjects(:));
    ics = double(roiResult.component_ics(:));
    subjectERSP = roiResult.subject_ersp;

    coverageTable = table();

    for c = 1:numel(conditionNames)

        data = subjectERSP{c};
        included = false(numel(subjects), 1);

        if ~isempty(data)
            if ndims(data) == 2 && numel(subjects) == 1
                data = reshape(data, size(data, 1), size(data, 2), 1);
            end

            for s = 1:numel(subjects)
                slice = data(:, :, s);
                included(s) = any(isfinite(slice(:)));
            end
        end

        includedSubjects = subjects(included);
        includedICs = ics(included);

        labels = strings(numel(includedSubjects), 1);
        for s = 1:numel(includedSubjects)
            labels(s) = includedSubjects(s) + ...
                " (IC" + string(includedICs(s)) + ")";
        end

        row = table( ...
            roiID, ...
            roiName, ...
            conditionNames(c), ...
            nnz(included), ...
            strjoin(labels, '; '), ...
            'VariableNames', {'ROIID','ROIName','Condition','n','Subjects'});

        if isempty(coverageTable)
            coverageTable = row;
        else
            coverageTable = [coverageTable; row]; %#ok<AGROW>
        end
    end
end

function resolvedPath = resolve_study_path_local(rawPath, runRoot)

    rawPath = strtrim(string(rawPath));
    assert(strlength(rawPath) > 0, 'ROIStudyPath is empty.');

    if isfile(rawPath)
        resolvedPath = rawPath;
        return;
    end

    [~, filename, extension] = fileparts(char(rawPath));
    matches = dir(fullfile(runRoot, '**', [filename extension]));
    matches = matches(~[matches.isdir]);

    assert(numel(matches) == 1, ...
        'ROIStudyPath could not be resolved uniquely: %s', rawPath);

    resolvedPath = string(fullfile(matches(1).folder, matches(1).name));
end

function designIndex = condition_design_local(STUDY)

    designIndex = [];

    for k = 1:numel(STUDY.design)
        if isempty(STUDY.design(k).variable), continue; end
        label = string(STUDY.design(k).variable(1).label);
        if strcmpi(strtrim(label), 'condition')
            designIndex = k;
            break;
        end
    end

    assert(~isempty(designIndex), ...
        'The ROI STUDY has no condition design.');
end

function names = design_condition_names_local(STUDY, designIndex)

    values = STUDY.design(designIndex).variable(1).value;

    if ischar(values)
        names = string({values});
    elseif iscell(values)
        names = strings(numel(values), 1);
        for k = 1:numel(values)
            value = values{k};
            if iscell(value) && numel(value) == 1, value = value{1}; end
            names(k) = string(value);
        end
    else
        names = string(values(:));
    end

    names = strtrim(names(:));
    assert(all(strlength(names) > 0), ...
        'Condition design contains an empty condition name.');
end

function assert_selected_cluster_local(STUDY, clusterIndex, roiID)

    assert(isfinite(clusterIndex) && ...
        clusterIndex == round(clusterIndex) && ...
        clusterIndex >= 2 && ...
        clusterIndex <= numel(STUDY.cluster), ...
        '%s has an invalid selected cluster index.', roiID);

    assert(isfield(STUDY.cluster(clusterIndex), 'sets') && ...
        isfield(STUDY.cluster(clusterIndex), 'comps') && ...
        ~isempty(STUDY.cluster(clusterIndex).sets) && ...
        ~isempty(STUDY.cluster(clusterIndex).comps), ...
        '%s selected cluster has no members.', roiID);
end

function groupWarpMs = group_median_warp_local(ALLEEG)

    warpRows = NaN(numel(ALLEEG), 5);

    for k = 1:numel(ALLEEG)
        assert(isfield(ALLEEG(k), 'timewarp') && ...
            isfield(ALLEEG(k).timewarp, 'warpto'), ...
            'Dataset %d has no EEG.timewarp.warpto.', k);

        warpto = double(ALLEEG(k).timewarp.warpto(:)');
        assert(numel(warpto) == 5 && ...
            all(isfinite(warpto)) && ...
            all(diff(warpto) > 0), ...
            'Dataset %d has invalid warpto values.', k);

        warpRows(k, :) = warpto;
    end

    groupWarpMs = median(warpRows, 1);
end

function keys = dataset_keys_local(STUDY)

    keys = strings(numel(STUDY.datasetinfo), 1);

    for k = 1:numel(STUDY.datasetinfo)
        info = STUDY.datasetinfo(k);

        runValue = "";
        if isfield(info, 'run') && ~isempty(info.run)
            runValue = string(info.run);
        end

        keys(k) = strjoin([ ...
            string(info.subject), ...
            string(info.condition), ...
            string(info.session), ...
            runValue, ...
            string(info.index)], '|');
    end
end

function [selectedSubjects, selectedICs] = ...
        lowest_ic_members_local(subjects, ics)

    subjects = string(subjects(:));
    ics = double(ics(:));

    assert(numel(subjects) == numel(ics), ...
        'Cluster member subject/IC counts differ.');

    uniqueSubjects = unique(subjects, 'stable');

    selectedSubjects = uniqueSubjects;
    selectedICs = NaN(numel(uniqueSubjects), 1);

    for k = 1:numel(uniqueSubjects)
        selectedICs(k) = min(ics(subjects == uniqueSubjects(k)));
    end
end

function [componentERSP, erspTimes, erspFreqs] = ...
        read_selected_components_ersp_local( ...
            STUDY, subjects, ics, conditionNames, timerangeMs, ...
            frequencyRangeHz, baselineValue, baselineNormalization, ...
            trialBaselineMode, componentCache)

    componentERSP = cell(numel(conditionNames), 1);
    erspTimes = [];
    erspFreqs = [];

    for member = 1:numel(subjects)

        key = char(subjects(member) + "|IC=" + string(ics(member)));

        if isKey(componentCache, key)
            R = componentCache(key);
        else
            R = hipexo.read_component_ersp( ...
                STUDY, ...
                subjects(member), ...
                ics(member), ...
                conditionNames, ...
                timerangeMs, ...
                frequencyRangeHz, ...
                baselineValue, ...
                baselineNormalization, ...
                trialBaselineMode);

            componentCache(key) = R;
        end

        assert(isequal(R.conditionNames, string(conditionNames(:))), ...
            'ROI STUDYs have different condition definitions.');

        if isempty(erspTimes)

            erspTimes = R.times;
            erspFreqs = R.freqs;

            for c = 1:numel(conditionNames)
                componentERSP{c} = NaN( ...
                    numel(erspFreqs), ...
                    numel(erspTimes), ...
                    numel(subjects));
            end

        else

            assert(isequal(erspTimes, R.times) && ...
                isequal(erspFreqs, R.freqs), ...
                'TF axes differ between retained components.');
        end

        for c = 1:numel(conditionNames)
            if ~isempty(R.conditionERSP{c})
                componentERSP{c}(:, :, member) = R.conditionERSP{c};
            end
        end
    end
end

function [groupERSP, contributingSubjects] = ...
        average_one_ic_per_subject_local(subjectERSP)

    groupERSP = cell(size(subjectERSP));
    contributingSubjects = zeros(numel(subjectERSP), 1);

    for c = 1:numel(subjectERSP)

        data = subjectERSP{c};

        if isempty(data)
            groupERSP{c} = [];
            continue;
        end

        valid = false(size(data, 3), 1);

        for s = 1:size(data, 3)
            slice = data(:, :, s);
            valid(s) = any(isfinite(slice(:)));
        end

        contributingSubjects(c) = nnz(valid);

        if any(valid)
            groupERSP{c} = mean(data(:, :, valid), 3, 'omitnan');
        else
            groupERSP{c} = NaN(size(data, 1), size(data, 2));
        end
    end
end

function [names, subjectData, groupData, nSubjects] = ...
        reorder_conditions_local( ...
            names, subjectData, groupData, nSubjects, preferredOrder)

    order = [];

    for k = 1:numel(preferredOrder)
        match = find(strcmpi(names, preferredOrder(k)), 1);
        if ~isempty(match)
            order(end + 1) = match; %#ok<AGROW>
        end
    end

    order = [order setdiff(1:numel(names), order, 'stable')];

    names = names(order);
    subjectData = subjectData(order);
    groupData = groupData(order);
    nSubjects = nSubjects(order);
end

function displayNames = condition_display_labels_local( ...
        conditionNames, conditionOrder, displayLabels)

    conditionNames = string(conditionNames(:));
    conditionOrder = string(conditionOrder(:));
    displayLabels = string(displayLabels(:));

    displayNames = conditionNames;

    for k = 1:numel(conditionNames)
        match = find(strcmpi(conditionOrder, conditionNames(k)), 1);
        if ~isempty(match)
            displayNames(k) = displayLabels(match);
        end
    end
end

function subjectSummary = summarize_subject_band_phase_local( ...
        subjectData, ...
        subjectNames, ...
        conditionNames, ...
        conditionDisplayNames, ...
        timesMs, ...
        frequenciesHz, ...
        groupWarpMs, ...
        gaitPhaseNames, ...
        gaitPhaseDisplayLabels, ...
        bandNames, ...
        bandRangesHz, ...
        roiID, ...
        originalClusterID, ...
        roiName)

    subjectNames = string(subjectNames(:));
    conditionNames = string(conditionNames(:));
    conditionDisplayNames = string(conditionDisplayNames(:));
    gaitPhaseNames = string(gaitPhaseNames(:));
    gaitPhaseDisplayLabels = string(gaitPhaseDisplayLabels(:));
    bandNames = string(bandNames(:));

    subjectSummary = table();

    for c = 1:numel(conditionNames)

        data = double(subjectData{c});

        if ndims(data) == 2
            data = reshape(data, size(data, 1), size(data, 2), 1);
        end

        assert(size(data, 1) == numel(frequenciesHz) && ...
            size(data, 2) == numel(timesMs) && ...
            size(data, 3) == numel(subjectNames), ...
            'Subject ERSP size is inconsistent for condition %s.', conditionNames(c));

        for phaseIndex = 1:numel(gaitPhaseNames)

            phaseStart = double(groupWarpMs(phaseIndex));
            phaseEnd = double(groupWarpMs(phaseIndex + 1));

            if phaseIndex < numel(gaitPhaseNames)
                timeMask = timesMs >= phaseStart & timesMs < phaseEnd;
            else
                timeMask = timesMs >= phaseStart & timesMs <= phaseEnd;
            end

            assert(any(timeMask), ...
                'No ERSP samples fall in gait phase %s.', gaitPhaseNames(phaseIndex));

            for bandIndex = 1:numel(bandNames)

                bandLow = bandRangesHz(bandIndex, 1);
                bandHigh = bandRangesHz(bandIndex, 2);

                frequencyMask = ...
                    frequenciesHz >= bandLow & ...
                    frequenciesHz <= bandHigh;

                assert(any(frequencyMask), ...
                    'No ERSP samples fall in band %s.', bandNames(bandIndex));

                for subjectIndex = 1:numel(subjectNames)

                    slice = data( ...
                        frequencyMask, ...
                        timeMask, ...
                        subjectIndex);

                    if ~any(isfinite(slice(:)))
                        continue;
                    end

                    meanERSP = mean(slice(:), 'omitnan');

                    row = table( ...
                        roiID, ...
                        originalClusterID, ...
                        roiName, ...
                        subjectNames(subjectIndex), ...
                        conditionNames(c), ...
                        conditionDisplayNames(c), ...
                        gaitPhaseNames(phaseIndex), ...
                        gaitPhaseDisplayLabels(phaseIndex), ...
                        bandNames(bandIndex), ...
                        bandLow, ...
                        bandHigh, ...
                        100 * phaseStart / groupWarpMs(end), ...
                        100 * phaseEnd / groupWarpMs(end), ...
                        meanERSP, ...
                        'VariableNames', { ...
                            'ROIID', ...
                            'OriginalClusterID', ...
                            'ROIName', ...
                            'Subject', ...
                            'Condition', ...
                            'ConditionDisplay', ...
                            'GaitPhase', ...
                            'GaitPhaseDisplay', ...
                            'Band', ...
                            'BandLow_Hz', ...
                            'BandHigh_Hz', ...
                            'PhaseStart_pct', ...
                            'PhaseEnd_pct', ...
                            'MeanERSP_dB'});

                    if isempty(subjectSummary)
                        subjectSummary = row;
                    else
                        subjectSummary = [subjectSummary; row]; %#ok<AGROW>
                    end
                end
            end
        end
    end
end

function plot_roi_heatmaps_local( ...
        groupData, ...
        nSubjects, ...
        conditionNames, ...
        timesMs, ...
        frequenciesHz, ...
        groupWarpMs, ...
        gaitEventNames, ...
        roiID, ...
        roiName, ...
        outputFile)

    timesPercent = 100 .* double(timesMs(:)') ./ double(groupWarpMs(end));
    eventPercent = 100 .* double(groupWarpMs(:)') ./ double(groupWarpMs(end));

    finiteValues = [];

    for c = 1:numel(groupData)
        if ~isempty(groupData{c})
            values = double(groupData{c});
            finiteValues = [finiteValues; values(isfinite(values))]; %#ok<AGROW>
        end
    end

    assert(~isempty(finiteValues), ...
        'No finite ERSP values are available for %s.', roiID);

    absoluteValues = sort(abs(finiteValues));
    colorLimit = absoluteValues(max(1, ceil(0.98 * numel(absoluteValues))));

    if ~isfinite(colorLimit) || colorLimit <= 0
        colorLimit = max(absoluteValues);
    end
    if ~isfinite(colorLimit) || colorLimit <= 0
        colorLimit = 1;
    end

    nConditions = numel(conditionNames);
    nColumns = min(4, nConditions);
    nRows = ceil(nConditions / nColumns);

    figureHandle = figure( ...
        'Color', 'w', ...
        'Visible', 'off', ...
        'Position', [80 80 420 * nColumns 330 * nRows]);

    layout = tiledlayout( ...
        figureHandle, ...
        nRows, ...
        nColumns, ...
        'Padding', 'compact', ...
        'TileSpacing', 'compact');

    for c = 1:nConditions

        axisHandle = nexttile(layout);
        data = groupData{c};

        if isempty(data) || ~any(isfinite(data(:)))
            axis(axisHandle, 'off');
            text(axisHandle, 0.5, 0.5, 'No data', ...
                'HorizontalAlignment', 'center');
            title(axisHandle, char(conditionNames(c)), 'Interpreter', 'none');
            continue;
        end

        surface( ...
            axisHandle, ...
            timesPercent, ...
            frequenciesHz, ...
            zeros(size(data)), ...
            double(data), ...
            'EdgeColor', 'none');

        view(axisHandle, 2);
        axis(axisHandle, 'tight');

        set(axisHandle, ...
            'YDir', 'normal', ...
            'YScale', 'log', ...
            'YTick', [3 4 6 8 10 13 20 30 45], ...
            'FontSize', 9, ...
            'Layer', 'top');

        xlim(axisHandle, [0 100]);
        xticks(axisHandle, 0:20:100);
        caxis(axisHandle, [-colorLimit colorLimit]);
        hold(axisHandle, 'on');

        for eventIndex = 1:numel(eventPercent)
            xline(axisHandle, eventPercent(eventIndex), '-', ...
                'Color', [0.15 0.15 0.15], ...
                'LineWidth', 0.8, ...
                'HandleVisibility', 'off');
        end

        yLimits = ylim(axisHandle);
        yText = exp(log(yLimits(2)) - ...
            0.05 * (log(yLimits(2)) - log(yLimits(1))));

        for eventIndex = 1:numel(eventPercent)
            alignment = 'center';
            if eventIndex == 1
                alignment = 'left';
            elseif eventIndex == numel(eventPercent)
                alignment = 'right';
            end

            text(axisHandle, ...
                eventPercent(eventIndex), ...
                yText, ...
                char(gaitEventNames(eventIndex)), ...
                'HorizontalAlignment', alignment, ...
                'VerticalAlignment', 'top', ...
                'FontSize', 8, ...
                'Clipping', 'on');
        end

        title(axisHandle, sprintf('%s (n=%d)', ...
            char(conditionNames(c)), nSubjects(c)), ...
            'Interpreter', 'none');

        xlabel(axisHandle, 'Gait cycle (%)');
        ylabel(axisHandle, 'Frequency (Hz)');
        colorbar(axisHandle);
    end

    colormap(figureHandle, jet(256));

    title(layout, sprintf('%s | %s | ERSP (dB)', ...
        char(roiID), strrep(char(roiName), '_', ' ')), ...
        'Interpreter', 'none', ...
        'FontWeight', 'bold');

    if exist('exportgraphics', 'file') == 2
        exportgraphics(figureHandle, outputFile, 'Resolution', 200);
    else
        print(figureHandle, outputFile, '-dpng', '-r200');
    end

    close(figureHandle);
end

function records = precompute_timewarped_component_ersp_local( ...
        STUDY, ALLEEG, forceRecompute, baseERSPParameters)

    assert(numel(STUDY.datasetinfo) == numel(ALLEEG), ...
        'STUDY.datasetinfo and ALLEEG lengths differ.');

    datasetIndices = double([STUDY.datasetinfo.index]);

    assert(isequal(datasetIndices, 1:numel(STUDY.datasetinfo)), ...
        'STUDY.datasetinfo.index must be 1:N.');

    subjects = string({STUDY.datasetinfo.subject});
    sessions = string(double([STUDY.datasetinfo.session]));

    subjectSessionKeys = subjects + "|session=" + sessions;
    uniqueKeys = unique(subjectSessionKeys, 'stable');
    allTrialCounts = double([ALLEEG.trials]);

    records = struct('unit', {}, 'signature', {}, 'components', {});

    for keyIndex = 1:numel(uniqueKeys)

        infoIndices = find(subjectSessionKeys == uniqueKeys(keyIndex));
        eegIndices = datasetIndices(infoIndices);

        referenceComponents = double( ...
            STUDY.datasetinfo(infoIndices(1)).comps(:)');

        if isempty(referenceComponents)
            continue;
        end

        latencyCells = cell(numel(eegIndices), 1);

        for localIndex = 1:numel(eegIndices)

            eegIndex = eegIndices(localIndex);

            assert(isfield(ALLEEG(eegIndex), 'timewarp') && ...
                isfield(ALLEEG(eegIndex).timewarp, 'latencies'), ...
                'Dataset %d has no timewarp latencies.', eegIndex);

            latencies = double(ALLEEG(eegIndex).timewarp.latencies);

            assert(size(latencies, 1) == ALLEEG(eegIndex).trials && ...
                size(latencies, 2) == 5 && ...
                all(isfinite(latencies(:))) && ...
                all(all(diff(latencies, 1, 2) > 0)), ...
                'Dataset %d has invalid timewarp latencies.', eegIndex);

            latencyCells{localIndex} = latencies;
        end

        timewarpMatrix = vertcat(latencyCells{:});

        erspParameters = set_parameter_local( ...
            baseERSPParameters, ...
            'timewarp', ...
            timewarpMatrix);

        trialInfo = std_combtrialinfo( ...
            STUDY.datasetinfo, ...
            infoIndices, ...
            allTrialCounts);

        sourceRecords = cell(numel(infoIndices), 1);
        legacySources = strings(numel(infoIndices), 1);

        for localIndex = 1:numel(infoIndices)

            info = STUDY.datasetinfo(infoIndices(localIndex));
            eegIndex = eegIndices(localIndex);
            % ALLEEG may contain only a data pointer; hash the actual samples.
            sourceEEG = ALLEEG(eegIndex);
            sourceEEG.data = eeg_getdatact(sourceEEG);
            dataSignature = hipexo.eeglab_dataset_signature(sourceEEG);
            clear sourceEEG;

            runValue = [];
            if isfield(info, 'run'), runValue = info.run; end

            sourceRecords{localIndex} = struct( ...
                'subject', info.subject, ...
                'condition', info.condition, ...
                'session', info.session, ...
                'run', runValue, ...
                'data', dataSignature);

            % Compatibility with Step14 caches created by the older script.
            file = fullfile(info.filepath, info.filename);
            legacySources(localIndex) = string(file) + "|" + string(dataSignature);
        end

        % Baseline settings do not alter the cached complex TF decomposition.
        tfParameters = erspParameters;
        names = string(tfParameters(1:2:end));
        omit = ismember(lower(names), ["baseline", "basenorm", "trialbase"]);
        tfParameters(repelem(omit, 2)) = [];

        icaSignature = hipexo.ica_identity_signature(ALLEEG(eegIndices(1)));

        definition = struct( ...
            'sources', {sourceRecords}, ...
            'parameters', {tfParameters}, ...
            'ica', icaSignature);

        signature = hipexo.content_signature(definition);

        legacyDefinition = struct( ...
            'sources', legacySources, ...
            'parameters', {tfParameters}, ...
            'ica', icaSignature);

        legacySignature = hipexo.content_signature(legacyDefinition);

        fileBase = hipexo.tf_cache_file_base(STUDY, infoIndices(1));
        provenanceFile = [fileBase '_HipExo_TF_cache.mat'];
        tfFile = [fileBase '.icatimef'];

        reusable = false;

        if ~forceRecompute && isfile(provenanceFile) && isfile(tfFile)
            try
                saved = load(provenanceFile, 'cacheInfo');

                reusable = isfield(saved, 'cacheInfo') && ...
                    isfield(saved.cacheInfo, 'signature') && ...
                    isfield(saved.cacheInfo, 'components') && ...
                    any(string(saved.cacheInfo.signature) == ...
                        [string(signature), string(legacySignature)]) && ...
                    all(ismember(referenceComponents, saved.cacheInfo.components));
            catch
                reusable = false;
            end
        end

        if reusable

            cacheInfo = saved.cacheInfo;
            cacheInfo.signature = signature;

            if ~isfield(cacheInfo, 'trialInfo') || ...
                    ~isequaln(cacheInfo.trialInfo, trialInfo)

                trialinfo = trialInfo; %#ok<NASGU>
                save(tfFile, 'trialinfo', '-append');
                cacheInfo.trialInfo = trialInfo;
            end

            % Migrate old provenance to the path-independent signature.
            save(provenanceFile, 'cacheInfo');

        else

            % Limit EEGLAB's internal parfor to 2 workers; reuse this pool.
            activePool = gcp('nocreate');
            if ~isempty(activePool) && activePool.NumWorkers ~= 2
                delete(activePool);
                activePool = [];
            end
            if isempty(activePool)
                parpool('Processes', 2);
            end

            std_ersp( ...
                ALLEEG(eegIndices), ...
                'components', referenceComponents, ...
                'recompute', 'on', ...
                'fileout', fileBase, ...
                'trialinfo', trialInfo, ...
                erspParameters{:});

            cacheInfo = struct( ...
                'signature', signature, ...
                'components', referenceComponents, ...
                'trialInfo', trialInfo);

            save(provenanceFile, 'cacheInfo');
        end

        records(end + 1) = struct( ...
            'unit', uniqueKeys(keyIndex), ...
            'signature', signature, ...
            'components', referenceComponents); %#ok<AGROW>

        if reusable
            status = 'REUSE';
        else
            status = 'RECOMPUTE';
        end

        fprintf('%s: TF cache %s (%d ICs)\n', ...
            char(uniqueKeys(keyIndex)), status, numel(referenceComponents));
    end
end

function parameters = set_parameter_local(parameters, name, value)

    names = string(parameters(1:2:end));
    match = find(strcmpi(names, string(name)), 1);

    assert(~isempty(match), ...
        'ERSP parameter %s is missing.', name);

    parameters{2 * match} = value;
end
