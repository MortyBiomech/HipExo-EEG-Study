function step13_rhs_roi_cluster_qc()
% QC the Step 12 ROI-specific clusters before Step 14 ERSP.
% Step 12 already performs repeated-clustering selection. Step 13 only
% verifies the selected cluster and generates anatomy/scalp/spectrum figures
% for manual KEEP/EXCLUDE review.

%% SETTINGS AND PATHS
scriptsRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(scriptsRoot, '-begin');
addpath(fullfile(scriptsRoot, 'config'), '-begin');

P = project_paths();
cfg = config_step12_14_clustering_roi_ersp();
K = double(cfg.clustering.numberOfClusters);
N = double(cfg.clustering.numberOfRepetitions);
freqRange = double(cfg.roiClusterQC.frequencyRangeHz(:)');

rhsRoot = fullfile(P.outputFolder, cfg.clustering.rhsRootFolderName);
runRoot = fullfile(rhsRoot, cfg.clustering.outputFolderName, ...
    sprintf('K%02d_N%05d', K, N));
roiRoot = fullfile(runRoot, cfg.clustering.roiStudyFolderName);
qcRoot = fullfile(runRoot, cfg.roiClusterQC.qcFolderName);
figRoot = fullfile(qcRoot, 'figures');
ensure_folder_local(qcRoot);
ensure_folder_local(figRoot);

summaryPath = fullfile(runRoot, 'ROI_repeated_clustering_summary.csv');
membershipPath = fullfile(runRoot, 'ROI_repeated_clustering_membership_all.csv');
roiDefinitionPath = fullfile(runRoot, 'ROI_definition_used.csv');
runInfoPath = fullfile(runRoot, 'ROI_repeated_clustering_run_info.mat');

requiredFiles = {summaryPath, membershipPath, roiDefinitionPath, runInfoPath};
for i = 1:numel(requiredFiles)
    assert(isfile(requiredFiles{i}), 'Required Step 12 file is missing:\n%s', requiredFiles{i});
end

%% LOAD STEP 12 OUTPUTS
summaryTable = readtable(summaryPath, 'Delimiter', ',', 'ReadVariableNames', true, ...
    'TextType', 'string', 'VariableNamingRule', 'preserve');
membershipAll = readtable(membershipPath, 'Delimiter', ',', 'ReadVariableNames', true, ...
    'TextType', 'string', 'VariableNamingRule', 'preserve');
roiDefinitions = readtable(roiDefinitionPath, 'Delimiter', ',', 'ReadVariableNames', true, ...
    'TextType', 'string', 'VariableNamingRule', 'preserve');

assert_columns_local(summaryTable, {'ROIID','OriginalClusterID','ROIName', ...
    'MNI_X','MNI_Y','MNI_Z','SelectedClusterIndex','BestSolutionNumber', ...
    'K','Repetitions','StudyPath'}, 'Step 12 summary');
assert_columns_local(membershipAll, {'ROIID','OriginalClusterID','ROIName', ...
    'DatasetIndex','Subject','ICASession','PhysicalRun','Condition','IC'}, ...
    'Step 12 membership');
assert_columns_local(roiDefinitions, {'ROIID','OriginalClusterID','ROIName', ...
    'MNI_X','MNI_Y','MNI_Z','Enabled'}, 'ROI definition');

summaryTable.ROIID = strtrim(string(summaryTable.ROIID));
summaryTable.OriginalClusterID = strtrim(string(summaryTable.OriginalClusterID));
summaryTable.ROIName = strtrim(string(summaryTable.ROIName));
membershipAll.ROIID = strtrim(string(membershipAll.ROIID));
membershipAll.OriginalClusterID = strtrim(string(membershipAll.OriginalClusterID));
membershipAll.ROIName = strtrim(string(membershipAll.ROIName));
membershipAll.Subject = strtrim(string(membershipAll.Subject));
roiDefinitions.ROIID = strtrim(string(roiDefinitions.ROIID));
roiDefinitions.OriginalClusterID = strtrim(string(roiDefinitions.OriginalClusterID));
roiDefinitions.ROIName = strtrim(string(roiDefinitions.ROIName));

enabledROIs = roiDefinitions(logical_column_local(roiDefinitions.Enabled), :);
configuredROIs = cfg.roi.table;
configuredROIs.ROIID = strtrim(string(configuredROIs.ROIID));
configuredROIs.OriginalClusterID = strtrim(string(configuredROIs.OriginalClusterID));
configuredROIs.ROIName = strtrim(string(configuredROIs.ROIName));
configuredROIs = configuredROIs(logical_column_local(configuredROIs.Enabled), :);

assert(height(enabledROIs) == height(summaryTable), ...
    'Step 12 summary and enabled ROI count do not match.');
assert(all(double(summaryTable.K) == K) && all(double(summaryTable.Repetitions) == N), ...
    'Step 12 summary K/repetition values do not match the current config.');
assert(isequal(sort(enabledROIs.ROIID), sort(summaryTable.ROIID)), ...
    'Step 12 summary ROI IDs do not match ROI_definition_used.csv.');
assert(isequal(sort(enabledROIs.ROIID), sort(configuredROIs.ROIID)), ...
    'Stored ROI definitions do not match the current config.');

for i = 1:height(enabledROIs)
    id = enabledROIs.ROIID(i);
    j = find(configuredROIs.ROIID == id);
    assert(numel(j) == 1, 'Could not uniquely match configured ROI %s.', char(id));
    storedXYZ = double(enabledROIs{i, {'MNI_X','MNI_Y','MNI_Z'}});
    configXYZ = double(configuredROIs{j, {'MNI_X','MNI_Y','MNI_Z'}});
    assert(max(abs(storedXYZ-configXYZ)) < 1e-9 && ...
        enabledROIs.OriginalClusterID(i) == configuredROIs.OriginalClusterID(j) && ...
        enabledROIs.ROIName(i) == configuredROIs.ROIName(j), ...
        'Stored and configured ROI definitions differ for %s.', char(id));
end

loadedRun = load(runInfoPath, 'runInfo');
assert(isfield(loadedRun, 'runInfo'), 'Step 12 run-info MAT has no runInfo variable.');
runInfo = loadedRun.runInfo;
assert(isfield(runInfo, 'source_signature') && ...
    isfield(runInfo, 'K') && double(runInfo.K) == K && ...
    isfield(runInfo, 'repetitions') && double(runInfo.repetitions) == N, ...
    'Step 12 run-info does not match the current clustering settings.');
assert(isfield(runInfo, 'clustering_weights') && ...
    isequaln(runInfo.clustering_weights, cfg.clustering.weights), ...
    'Step 12 clustering weights do not match the current config.');
assert(isfield(runInfo, 'frequency_range_hz') && ...
    isequal(double(runInfo.frequency_range_hz(:)'), freqRange), ...
    'Step 12 clustering frequency range does not match the current config.');

%% START EEGLAB
assert(exist('eeglab', 'file') == 2, 'EEGLAB was not found.');
eeglab('nogui');
assert(exist('std_specplot', 'file') == 2 && exist('topoplot', 'file') == 2, ...
    'Required EEGLAB plotting functions are missing.');

%% QC EACH ROI
qcTable = table();
sharedALLEEG = [];

for roiIndex = 1:height(enabledROIs)
    roiID = enabledROIs.ROIID(roiIndex);
    originalClusterID = enabledROIs.OriginalClusterID(roiIndex);
    roiName = enabledROIs.ROIName(roiIndex);
    roiXYZ = double(enabledROIs{roiIndex, {'MNI_X','MNI_Y','MNI_Z'}});
    safeLabel = safe_name_local(roiID + "_" + roiName);

    summaryRow = summaryTable(summaryTable.ROIID == roiID, :);
    assert(height(summaryRow) == 1, 'Expected one Step 12 summary row for %s.', char(roiID));
    assert(summaryRow.OriginalClusterID == originalClusterID && ...
        summaryRow.ROIName == roiName && ...
        max(abs(double(summaryRow{1, {'MNI_X','MNI_Y','MNI_Z'}})-roiXYZ)) < 1e-9, ...
        'Step 12 summary identity differs for %s.', char(roiID));

    roiStudyPath = resolve_study_path_local(summaryRow.StudyPath, roiRoot, safeLabel, K);

    if roiIndex == 1
        [STUDYroi, sharedALLEEG] = hipexo.load_study_with_headers(roiStudyPath, P.outputFolder);
    else
        [STUDYroi, ~] = hipexo.load_study_with_headers(roiStudyPath, P.outputFolder, sharedALLEEG);
    end
    ALLEEGroi = sharedALLEEG;

    meta = verify_roi_metadata_local(STUDYroi, roiID, originalClusterID, roiName, ...
        roiXYZ, K, N, string(runInfo.source_signature));
    selectedCluster = double(meta.selected_cluster);
    assert(selectedCluster == double(summaryRow.SelectedClusterIndex) && ...
        double(meta.best_solution) == double(summaryRow.BestSolutionNumber), ...
        'Selected solution/cluster differs across Step 12 outputs for %s.', char(roiID));
    assert(ismember(selectedCluster, regular_cluster_indices_local(STUDYroi.cluster, K, roiID)), ...
        'Selected cluster is Parent/Outlier or invalid for %s.', char(roiID));

    roiMembers = membershipAll(membershipAll.ROIID == roiID, :);
    assert(~isempty(roiMembers), 'No Step 12 membership rows found for %s.', char(roiID));
    assert(all(roiMembers.OriginalClusterID == originalClusterID) && ...
        all(roiMembers.ROIName == roiName), 'Membership identity differs for %s.', char(roiID));
    roiMembers.ICAComponentUnit = component_key_local(roiMembers);

    actualMembers = hipexo.cluster_membership(STUDYroi, selectedCluster);
    studyPairs = unique(string(actualMembers.DatasetIndex) + "|IC" + string(actualMembers.IC));
    csvPairs = unique(string(double(roiMembers.DatasetIndex)) + "|IC" + string(double(roiMembers.IC)));
    assert(isequal(sort(studyPairs), sort(csvPairs)), ...
        'Membership CSV does not match the selected STUDY cluster for %s.', char(roiID));

    [~, ia] = unique(roiMembers.ICAComponentUnit, 'stable');
    uniqueMembers = sortrows(roiMembers(ia, :), {'Subject','IC'});
    nComp = height(uniqueMembers);

    positions = nan(nComp, 3);
    rv = nan(nComp, 1);
    scalpMaps = cell(nComp, 1);
    scalpChanlocs = cell(nComp, 1);
    channelLabels = cell(nComp, 1);

    for c = 1:nComp
        ds = double(uniqueMembers.DatasetIndex(c));
        ic = double(uniqueMembers.IC(c));
        assert(ds >= 1 && ds <= numel(ALLEEGroi), 'Invalid dataset index %d.', ds);
        EEG = ALLEEGroi(ds);
        assert(ic >= 1 && ic <= size(EEG.icawinv,2) && ...
            isfield(EEG, 'dipfit') && isfield(EEG.dipfit, 'model') && ...
            ic <= numel(EEG.dipfit.model), 'Invalid/missing IC or DIPFIT model.');

        model = EEG.dipfit.model(ic);
        positions(c,:) = primary_dipole_xyz_local(model);
        rv(c) = dipole_rv_local(model);
        scalpMaps{c} = double(EEG.icawinv(:,ic));
        scalpChanlocs{c} = EEG.chanlocs;
        channelLabels{c} = string({EEG.chanlocs.labels});
    end

    assert(all(isfinite(positions), 'all') && all(isfinite(rv)), ...
        'Selected cluster contains invalid dipole position/RV for %s.', char(roiID));

    centroid = mean(positions, 1);
    centroidToTarget = norm(centroid - roiXYZ);
    meanRV = mean(rv);

    studySubjects = strtrim(string({STUDYroi.datasetinfo.subject}));
    studySubjects = unique(studySubjects(strlength(studySubjects) > 0), 'stable');
    memberSubjects = strtrim(string(uniqueMembers.Subject));
    subjectCount = numel(unique(memberSubjects(strlength(memberSubjects) > 0)));
    subjectCoverage = subjectCount / max(numel(studySubjects), 1);

    [alignedMaps, meanMap, scalpStatus] = align_scalp_maps_local(scalpMaps, channelLabels);
    assert(scalpStatus == "OK", 'Scalp maps are incompatible for %s: %s', ...
        char(roiID), char(scalpStatus));

    memberFig = fullfile(figRoot, char(safeLabel + "_member_scalp_maps.png"));
    spectrumFig = fullfile(figRoot, char(safeLabel + "_cluster_spectrum_3_45Hz.png"));
    dipoleFig = fullfile(figRoot, char(safeLabel + "_dipole_coordinate_qc.png"));

    memberStatus = make_member_scalp_plot_local(alignedMaps, meanMap, scalpChanlocs, ...
        uniqueMembers, rv, roiID + " | " + roiName, memberFig);
    spectrumStatus = make_cluster_spectrum_plot_local(STUDYroi, ALLEEGroi, ...
        selectedCluster, roiID + " | " + roiName, freqRange, spectrumFig);
    dipoleStatus = make_dipole_plot_local(positions, uniqueMembers.Subject, roiXYZ, ...
        centroid, roiID + " | " + roiName, dipoleFig);

    assert(memberStatus == "OK", 'Member scalp-map QC figure failed for %s: %s', ...
        char(roiID), char(memberStatus));
    assert(spectrumStatus == "OK", 'Spectrum QC figure failed for %s: %s', ...
        char(roiID), char(spectrumStatus));
    assert(dipoleStatus == "OK", 'Dipole QC figure failed for %s: %s', ...
        char(roiID), char(dipoleStatus));

    row = table(roiID, originalClusterID, roiName, ...
        roiXYZ(1), roiXYZ(2), roiXYZ(3), centroidToTarget, meanRV, ...
        subjectCount, subjectCoverage, nComp, ...
        double(meta.best_solution), selectedCluster, ...
        string(memberFig), string(spectrumFig), string(dipoleFig), string(roiStudyPath), ...
        "PENDING", "PENDING", "PENDING", "PENDING", "", ...
        'VariableNames', {'ROIID','OriginalClusterID','ROIName', ...
        'TargetMNI_X','TargetMNI_Y','TargetMNI_Z','CentroidToTarget_mm','MeanDipoleRV', ...
        'SubjectCount','SubjectCoverageFraction','UniqueICAComponentCount', ...
        'BestSolutionNumber','SelectedClusterIndex', ...
        'MemberScalpFigure','SpectrumFigure','DipoleFigure','ROIStudyPath', ...
        'ClusterAnatomyQC','ClusterScalpQC','ClusterSpectrumQC', ...
        'ClusterDecision','ClusterDecisionNotes'});

    row.ClusterReviewIdentity = hipexo.roi_review_identity( ...
        STUDYroi, ALLEEGroi, selectedCluster, enabledROIs(roiIndex,:), cfg.roiClusterQC);

    if isempty(qcTable)
        qcTable = row;
    else
        qcTable = [qcTable; row]; %#ok<AGROW>
    end
end

%% PRESERVE MANUAL REVIEW AND WRITE ONE WORKBOOK
workbookPath = fullfile(qcRoot, cfg.roiClusterQC.reviewWorkbookName);
reviewColumns = ["ClusterAnatomyQC","ClusterScalpQC", ...
    "ClusterSpectrumQC","ClusterDecision","ClusterDecisionNotes"];

if isfile(workbookPath)
    old = readtable(workbookPath, 'Sheet', cfg.roiClusterQC.reviewSheetName, ...
        'TextType', 'string', 'VariableNamingRule', 'preserve');
    oldNames = string(old.Properties.VariableNames);
    requiredOld = ["ROIID","ClusterReviewIdentity",reviewColumns];
    if all(ismember(requiredOld, oldNames))
        oldKeys = string(old.ROIID) + "|" + string(old.ClusterReviewIdentity);
        newKeys = qcTable.ROIID + "|" + qcTable.ClusterReviewIdentity;
        [matched, loc] = ismember(newKeys, oldKeys);
        for c = reviewColumns
            qcTable.(char(c))(matched) = string(old.(char(c))(loc(matched)));
        end
    end
end

reviewOrder = {'ROIID','OriginalClusterID','ROIName', ...
    'TargetMNI_X','TargetMNI_Y','TargetMNI_Z', ...
    'CentroidToTarget_mm','MeanDipoleRV', ...
    'SubjectCount','SubjectCoverageFraction','UniqueICAComponentCount', ...
    'BestSolutionNumber','SelectedClusterIndex', ...
    'MemberScalpFigure','SpectrumFigure','DipoleFigure','ROIStudyPath', ...
    'ClusterAnatomyQC','ClusterScalpQC','ClusterSpectrumQC','ClusterDecision', ...
    'ClusterDecisionNotes','ClusterReviewIdentity'};
reviewTable = qcTable(:, reviewOrder);

tmpWorkbook = fullfile(qcRoot, 'RHS_ROI_cluster_QC_review_tmp.xlsx');
if isfile(tmpWorkbook), delete(tmpWorkbook); end
writetable(reviewTable, tmpWorkbook, 'Sheet', cfg.roiClusterQC.reviewSheetName);
[ok,msg] = movefile(tmpWorkbook, workbookPath, 'f');
assert(ok, 'Could not replace QC workbook: %s', msg);

close all force;
fprintf('Step 13 completed: %s\n', workbookPath);
end

%% LOCAL FUNCTIONS
function assert_columns_local(T, required, label)
missing = setdiff(string(required), string(T.Properties.VariableNames));
assert(isempty(missing), '%s is missing column(s): %s', label, strjoin(missing, ', '));
end

function mask = logical_column_local(v)
if islogical(v), mask = v; return; end
if isnumeric(v)
    assert(all(isfinite(v(:))) && all(ismember(double(v(:)),[0 1])), ...
        'Enabled must contain only 0/1.');
    mask = logical(v); return;
end
s = lower(strtrim(string(v)));
trueMask = ismember(s,["true","1","yes","y"]);
falseMask = ismember(s,["false","0","no","n"]);
assert(all(trueMask | falseMask), 'Enabled contains an unrecognized value.');
mask = trueMask;
end

function ensure_folder_local(folderPath)
if ~isfolder(folderPath)
    [ok,msg] = mkdir(folderPath);
    assert(ok, 'Could not create folder %s: %s', folderPath, msg);
end
end

function output = safe_name_local(input)
output = regexprep(string(input), '[^A-Za-z0-9_-]+', '_');
output = regexprep(output, '_+', '_');
output = strip(output, 'both', '_');
assert(strlength(output) > 0, 'Invalid ROI filename label.');
end

function pathOut = resolve_study_path_local(recordedPath, roiRoot, safeLabel, K)
recordedPath = strtrim(string(recordedPath));
if strlength(recordedPath) > 0 && isfile(recordedPath)
    pathOut = char(recordedPath); return;
end
expected = fullfile(roiRoot, char(safeLabel), ...
    sprintf('HipExo_RHS_%s_K%02d.study', char(safeLabel), K));
assert(isfile(expected), 'ROI STUDY not found.\nRecorded: %s\nExpected: %s', ...
    char(recordedPath), expected);
pathOut = expected;
end

function meta = verify_roi_metadata_local(STUDY, roiID, originalID, roiName, xyz, K, N, sourceSig)
assert(isfield(STUDY,'etc') && isfield(STUDY.etc,'rhs_roi_clustering'), ...
    'ROI STUDY has no Step 12 provenance.');
meta = STUDY.etc.rhs_roi_clustering;
required = {'roi_id','original_exploratory_cluster_id','roi_name','roi_mni', ...
    'K','repetitions','best_solution','selected_cluster','source_signature'};
assert(all(isfield(meta,required)), 'ROI STUDY provenance is incomplete.');
assert(string(meta.roi_id)==roiID && string(meta.original_exploratory_cluster_id)==originalID && ...
    string(meta.roi_name)==roiName && max(abs(double(meta.roi_mni(:)')-xyz)) < 1e-9 && ...
    double(meta.K)==K && double(meta.repetitions)==N && ...
    string(meta.source_signature)==sourceSig, 'ROI STUDY provenance does not match Step 12.');
end

function regular = regular_cluster_indices_local(clusters, K, label)
n = numel(clusters);
if n == K+2
    regular = 3:n;
elseif n == K+1
    regular = 2:n;
else
    error('%s has %d cluster entries; expected %d or %d.', char(string(label)), n, K+1, K+2);
end
end

function keys = component_key_local(members)
keys = string(members.Subject) + "|session" + string(double(members.ICASession)) + ...
    "|IC" + string(double(members.IC));
end

function xyz = primary_dipole_xyz_local(model)
xyz = [NaN NaN NaN];
if ~isfield(model,'posxyz') || isempty(model.posxyz), return; end
p = double(model.posxyz);
if size(p,2) ~= 3, return; end
% BeMoBIL/DIPFIT may store a dummy second dipole at [0 0 0].
if size(p,1)==2 && all(p(2,:)==0), p(2,:)=[]; end
xyz = mean(p,1,'omitnan');
end

function value = dipole_rv_local(model)
value = NaN;
if ~isfield(model,'rv') || isempty(model.rv), return; end
v = double(model.rv(:));
v = v(isfinite(v));
if ~isempty(v), value = mean(v); end
end

function [aligned, meanMap, status] = align_scalp_maps_local(maps, labelSets)
n = numel(maps);
aligned = [];
meanMap = [];
status = "OK";
if n == 0, status = "NO_MAPS"; return; end

refLabels = string(labelSets{1}(:));
X = nan(numel(refLabels), n);
for i = 1:n
    labels = string(labelSets{i}(:));
    x = double(maps{i}(:));
    if ~isequal(labels, refLabels) || numel(x) ~= numel(refLabels) || any(~isfinite(x))
        status = "INCOMPATIBLE_CHANNELS_OR_MAP"; return;
    end
    x = x - mean(x);
    scale = sqrt(mean(x.^2));
    if ~isfinite(scale) || scale == 0
        status = "ZERO_OR_INVALID_MAP"; return;
    end
    X(:,i) = x / scale;
end

ref = X(:,1);
for iter = 1:3
    for i = 1:n
        if dot(X(:,i), ref) < 0, X(:,i) = -X(:,i); end
    end
    ref = mean(X,2);
    scale = sqrt(mean(ref.^2));
    if scale > 0, ref = ref / scale; end
end
aligned = X;
meanMap = mean(X,2);
end

function status = make_member_scalp_plot_local( ...
        maps, meanMap, chanlocs, members, rv, titleText, outputPath)
status = "OK";
fig = [];

try
    n = size(maps, 2);
    nPlots = n + 1;
    cols = min(4, ceil(sqrt(nPlots)));
    rows = ceil(nPlots / cols);

    figWidth = 340 * cols;
    figHeight = 300 * rows + 100;
    fig = figure('Visible','off','Color','w', ...
        'Position',[50 50 figWidth figHeight]);

    % Reserve a dedicated strip for the main title so member titles never
    % overlap with it. Manual axes also avoid topoplot/tiledlayout conflicts.
    leftMargin = 0.04;
    rightMargin = 0.04;
    bottomMargin = 0.05;
    topMargin = 0.13;
    horizontalGap = 0.03;
    verticalGap = 0.08;

    axWidth = (1 - leftMargin - rightMargin - ...
        (cols - 1) * horizontalGap) / cols;
    axHeight = (1 - topMargin - bottomMargin - ...
        (rows - 1) * verticalGap) / rows;

    annotation(fig, 'textbox', [0.02 0.945 0.96 0.045], ...
        'String', char(titleText + " - member scalp-map QC"), ...
        'HorizontalAlignment','center', ...
        'VerticalAlignment','middle', ...
        'EdgeColor','none', ...
        'Interpreter','none', ...
        'FontSize',16, ...
        'FontWeight','bold');

    % Mean scalp map
    plotIndex = 1;
    rowIndex = floor((plotIndex - 1) / cols);
    colIndex = mod(plotIndex - 1, cols);
    x = leftMargin + colIndex * (axWidth + horizontalGap);
    y = 1 - topMargin - (rowIndex + 1) * axHeight - rowIndex * verticalGap;

    ax = axes(fig, 'Position', [x y axWidth axHeight]);
    topoplot(meanMap, chanlocs{1}, 'electrodes','off','style','map');
    title(ax, 'Polarity-aligned mean', ...
        'Interpreter','none','FontSize',10,'FontWeight','bold');

    % Member scalp maps
    for i = 1:n
        plotIndex = i + 1;
        rowIndex = floor((plotIndex - 1) / cols);
        colIndex = mod(plotIndex - 1, cols);
        x = leftMargin + colIndex * (axWidth + horizontalGap);
        y = 1 - topMargin - (rowIndex + 1) * axHeight - rowIndex * verticalGap;

        ax = axes(fig, 'Position', [x y axWidth axHeight]);
        topoplot(maps(:,i), chanlocs{i}, 'electrodes','off','style','map');

        subjectText = erase(char(members.Subject(i)), 'sub-');
        title(ax, sprintf('%s IC%d | RV %.1f%%', ...
            subjectText, double(members.IC(i)), 100 * rv(i)), ...
            'Interpreter','none','FontSize',9.5,'FontWeight','bold');
    end

    exportgraphics(fig, outputPath, 'Resolution',220);
    close(fig);

catch ME
    status = "FAILED: " + string(ME.message);
    if ~isempty(fig) && isgraphics(fig), close(fig); end
end
end

function status = make_cluster_spectrum_plot_local( ...
        STUDY, ALLEEG, clusterIndex, titleText, freqRange, outputPath)
status = "OK";
newFigures = [];

try
    figuresBefore = findall(groot, 'Type', 'figure');

    std_specplot(STUDY, ALLEEG, ...
        'clusters', clusterIndex, ...
        'freqrange', freqRange, ...
        'plotsubjects', 'off', ...
        'plotmode', 'condensed');

    figuresAfter = findall(groot, 'Type', 'figure');
    newFigures = figuresAfter(~ismember(figuresAfter, figuresBefore));
    assert(~isempty(newFigures), 'std_specplot did not create a figure.');

    fig = newFigures(1);
    set(fig, ...
        'Visible', 'off', ...
        'Color', 'w', ...
        'Position', [50 50 1500 780]);
    figure(fig);

    % EEGLAB adds a long repeated title above every condition panel.
    % The ROI/cluster name is already shown once in the overall title,
    % so remove all individual subplot titles to avoid overlap.
    axesList = findall(fig, 'Type', 'axes');
    for k = 1:numel(axesList)
        title(axesList(k), '');
        axesList(k).FontSize = 10;
    end

    sgtitle(fig, ...
        char(titleText + " - cluster spectrum QC"), ...
        'Interpreter', 'none', ...
        'FontSize', 16, ...
        'FontWeight', 'bold');

    exportgraphics(fig, outputPath, 'Resolution', 220);

    for f = newFigures'
        if isgraphics(f), close(f); end
    end

catch ME
    status = "FAILED: " + string(ME.message);
    for f = newFigures'
        if isgraphics(f), close(f); end
    end
end
end

function status = make_dipole_plot_local( ...
        positions, subjects, target, centroid, titleText, outputPath)
status = "OK";
fig = [];

try
    assert(all(isfinite(positions),'all') && ...
        all(isfinite(target)) && all(isfinite(centroid)), ...
        'Dipole coordinates are incomplete.');

    subjects = string(subjects(:));
    uniqueSubjects = unique(subjects, 'stable');
    colors = lines(max(2, numel(uniqueSubjects)));

    pairs = [1 2; 1 3; 2 3];
    viewNames = ["Axial (X-Y)", "Coronal (X-Z)", "Sagittal (Y-Z)"];
    xLabels = ["X (mm)", "X (mm)", "Y (mm)"];
    yLabels = ["Y (mm)", "Z (mm)", "Z (mm)"];

    fig = figure('Visible','off','Color','w','Position',[50 50 1350 540]);

    % Manual axes give predictable spacing and avoid tiled-layout warnings.
    left = [0.07 0.375 0.68];
    width = 0.25;
    bottom = 0.13;
    height = 0.72;

    for v = 1:3
        ax = axes(fig, 'Position', [left(v) bottom width height]);
        hold(ax, 'on');

        for s = 1:numel(uniqueSubjects)
            m = subjects == uniqueSubjects(s);
            scatter(ax, ...
                positions(m,pairs(v,1)), ...
                positions(m,pairs(v,2)), ...
                65, colors(s,:), 'filled');
        end

        scatter(ax, ...
            centroid(pairs(v,1)), centroid(pairs(v,2)), ...
            110, 'k', 'd', 'filled');
        plot(ax, ...
            target(pairs(v,1)), target(pairs(v,2)), ...
            'rx', 'MarkerSize',14, 'LineWidth',2);

        title(ax, viewNames(v), 'FontSize',11, 'FontWeight','bold');
        xlabel(ax, xLabels(v));
        ylabel(ax, yLabels(v));
        axis(ax, 'equal');
        grid(ax, 'on');
        box(ax, 'on');
        set(ax, 'FontSize',10);
    end

    annotation(fig, 'textbox', [0.02 0.935 0.96 0.05], ...
        'String', char(titleText + " - dipole-coordinate QC"), ...
        'HorizontalAlignment','center', ...
        'VerticalAlignment','middle', ...
        'EdgeColor','none', ...
        'Interpreter','none', ...
        'FontSize',15, ...
        'FontWeight','bold');

    exportgraphics(fig, outputPath, 'Resolution',220);
    close(fig);

catch ME
    status = "FAILED: " + string(ME.message);
    if ~isempty(fig) && isgraphics(fig), close(fig); end
end
end
