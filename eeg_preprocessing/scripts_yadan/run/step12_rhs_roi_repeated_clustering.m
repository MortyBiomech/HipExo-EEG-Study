function step12_rhs_roi_repeated_clustering()
% Repeated shared-ICA clustering for fixed MNI ROIs.
% Keeps only the checks/reuse logic needed for correct Step 12 results.

%% SETTINGS AND PATHS
scriptsRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(scriptsRoot, '-begin');
addpath(fullfile(scriptsRoot, 'config'), '-begin');

P = project_paths();
cfg = config_step12_14_clustering_roi_ersp();

processingVersion = string(cfg.clustering.processingVersion);
K = double(cfg.clustering.numberOfClusters);
N = double(cfg.clustering.numberOfRepetitions);
outlierSigma = double(cfg.clustering.outlierSigma);
randomSeed = double(cfg.clustering.randomSeed);
forcePrecluster = logical(cfg.clustering.forceRecomputePrecluster);
forceSolutions = logical(cfg.clustering.forceRecomputeSolutions);
weights = cfg.clustering.weights;
frequencyRangeHz = double(cfg.clustering.frequencyRangeHz(:)');
timeWindowMs = double(cfg.clustering.timeWindowMs(:)');
qualityWeights = double(cfg.clustering.qualityMeasureWeights(:));
roiTable = cfg.roi.table;

assert(K >= 1 && K == round(K), 'numberOfClusters must be a positive integer.');
assert(N >= 1 && N == round(N), 'numberOfRepetitions must be a positive integer.');
assert(isfinite(outlierSigma) && outlierSigma > 0, 'outlierSigma must be positive.');
assert(numel(qualityWeights) == 6 && all(isfinite(qualityWeights)), ...
    'Exactly six finite ROI quality weights are required.');
assert(string(cfg.clustering.roiCandidatePolicy) == "nearest_centroid_per_solution", ...
    'Unsupported ROI candidate policy.');

requiredROIColumns = {'ROIID','OriginalClusterID','ROIName', ...
    'MNI_X','MNI_Y','MNI_Z','Enabled'};
assert(all(ismember(requiredROIColumns, roiTable.Properties.VariableNames)), ...
    'cfg.roi.table is missing required columns.');

roiTable.ROIID = strtrim(string(roiTable.ROIID));
roiTable.OriginalClusterID = strtrim(string(roiTable.OriginalClusterID));
roiTable.ROIName = strtrim(string(roiTable.ROIName));
assert(all(strlength(roiTable.ROIID) > 0) && ...
    numel(unique(roiTable.ROIID)) == height(roiTable), ...
    'ROIID values must be non-empty and unique.');
assert(all(strlength(roiTable.OriginalClusterID) > 0) && ...
    all(strlength(roiTable.ROIName) > 0), ...
    'ROI identity fields must be non-empty.');

fixedROIs = roiTable(logical(roiTable.Enabled), :);
assert(~isempty(fixedROIs), 'No ROI is enabled.');
assert(all(isfinite(fixedROIs{:, {'MNI_X','MNI_Y','MNI_Z'}}), 'all'), ...
    'At least one enabled ROI has invalid MNI coordinates.');

rhsRoot = fullfile(P.outputFolder, cfg.clustering.rhsRootFolderName);
inputStudyFolder = fullfile(rhsRoot, cfg.clustering.inputStudyFolderName);
inputStudyPath = fullfile(inputStudyFolder, cfg.clustering.inputStudyFilename);
assert(isfile(inputStudyPath), 'Input STUDY was not found:\n%s', inputStudyPath);

clusteringRoot = fullfile(rhsRoot, cfg.clustering.outputFolderName);
runRoot = fullfile(clusteringRoot, sprintf('K%02d_N%05d', K, N));
preclusterFolder = fullfile(runRoot, cfg.clustering.preclusterFolderName);
solutionFolder = fullfile(runRoot, cfg.clustering.solutionFolderName);
roiRoot = fullfile(runRoot, cfg.clustering.roiStudyFolderName);
ensure_folder_local(preclusterFolder);
ensure_folder_local(solutionFolder);
ensure_folder_local(roiRoot);

%% EEGLAB AND SHARED-ICA COMPATIBILITY
assert(exist('eeglab', 'file') == 2, 'EEGLAB was not found.');
eeglab('nogui');
restoreRMS = suspend_ica_rms_local(); %#ok<NASGU>
pop_editoptions('option_storedisk', 1);

compatInfo = hipexo.activate_shared_ica_compatibility(P.compatibilityFolder);
requiredFunctions = {'std_precomp','std_makedesign','bemobil_precluster', ...
    'bemobil_repeated_clustering','bemobil_dipoles','pop_savestudy'};
for k = 1:numel(requiredFunctions)
    assert(exist(requiredFunctions{k}, 'file') == 2, ...
        'Required function is missing: %s', requiredFunctions{k});
end

%% LOAD AND VERIFY STEP 11 STUDY
[STUDY, ALLEEG] = hipexo.load_study_with_headers( ...
    inputStudyPath, P.outputFolder);
expectedUniqueICs = verify_shared_ica_study_local(STUDY, ALLEEG);
sourceSignature = study_source_signature_local(STUDY);

%% PRECLUSTER
preclusterFilename = cfg.clustering.preclusterFilename;
preclusterPath = fullfile(preclusterFolder, preclusterFilename);
reusePrecluster = isfile(preclusterPath) && ~forcePrecluster;

if reusePrecluster
    try
        [BASESTUDY, BASEALLEEG] = hipexo.load_study_with_headers( ...
            preclusterPath, P.outputFolder);
        verify_precluster_reuse_local(BASESTUDY, sourceSignature, ...
            weights, frequencyRangeHz, timeWindowMs, expectedUniqueICs);
    catch ME
        fprintf('Precluster will be rebuilt: %s\n', ME.message);
        reusePrecluster = false;
    end
end

if ~reusePrecluster
    [STUDY, designIndex] = make_all_condition_design_local(STUDY, ALLEEG);

    [STUDY, ALLEEG] = std_precomp(STUDY, ALLEEG, ...
        'components', 'design', designIndex, ...
        'allcomps', 'off', 'recompute', 'on', 'rmicacomps', 'off', ...
        'scalp', 'on', 'spec', 'on', ...
        'specparams', {'freqrange', frequencyRangeHz, ...
            'specmode', 'fft', 'logtrials', 'off'});

    [STUDY, ALLEEG, ~] = bemobil_precluster( ...
        STUDY, ALLEEG, ALLEEG(1), weights, frequencyRangeHz, timeWindowMs);

    assert(isfield(STUDY, 'etc') && isfield(STUDY.etc, 'bemobil') && ...
        isfield(STUDY.etc.bemobil, 'clustering') && ...
        isfield(STUDY.etc.bemobil.clustering, 'preclustparams') && ...
        isfield(STUDY.etc, 'preclust') && ...
        isfield(STUDY.etc.preclust, 'preclustdata') && ...
        ~isempty(STUDY.etc.preclust.preclustdata), ...
        'Preclustering did not create the required feature data.');
    assert(size(STUDY.etc.preclust.preclustdata, 1) == expectedUniqueICs, ...
        'Precluster feature rows do not match the unique shared-ICA components.');

    [~, parentUniqueMembers] = hipexo.cluster_membership(STUDY, 1);
    assert(height(parentUniqueMembers) == expectedUniqueICs, ...
        'Precluster parent does not contain the expected shared ICA components.');

    if ~isfield(STUDY, 'etc') || isempty(STUDY.etc), STUDY.etc = struct(); end
    STUDY.etc.rhs_roi_precluster = struct( ...
        'version', char(processingVersion), ...
        'source_signature', char(sourceSignature), ...
        'clustering_weights', weights, ...
        'frequency_range_hz', frequencyRangeHz, ...
        'time_window_ms', timeWindowMs, ...
        'unique_ica_ic_units', expectedUniqueICs, ...
        'std_preclust_patch', compatInfo.stdPreclustPatch);

    [BASESTUDY, BASEALLEEG] = pop_savestudy(STUDY, ALLEEG, ...
        'filename', preclusterFilename, 'filepath', preclusterFolder);
end

preclusterSignature = hipexo.content_signature(struct( ...
    'source', sourceSignature, ...
    'features', BASESTUDY.etc.preclust.preclustdata, ...
    'sets', BASESTUDY.cluster(1).sets, ...
    'comps', BASESTUDY.cluster(1).comps, ...
    'weights', weights, ...
    'frequencyRangeHz', frequencyRangeHz, ...
    'timeWindowMs', timeWindowMs));

%% REPEATED CLUSTERING SOLUTION BANK
solutionBaseName = sprintf('HipExo_RHS_shared_repeated_K%02d_N%05d', K, N);
solutionPath = fullfile(solutionFolder, [solutionBaseName '.mat']);
reuseSolutions = isfile(solutionPath) && ~forceSolutions;

if reuseSolutions
    try
        loaded = load(solutionPath, 'clustering_solutions', 'solution_provenance');
        assert(isfield(loaded, 'clustering_solutions'), ...
            'Existing solution file contains no clustering_solutions.');
        assert(isfield(loaded, 'solution_provenance'), ...
            'Existing solution file contains no solution_provenance.');
        clustering_solutions = loaded.clustering_solutions;
        assert_complete_solution_bank_local(clustering_solutions, N, K);
        verify_solution_reuse_local(loaded.solution_provenance, ...
            sourceSignature, preclusterSignature, K, N, outlierSigma, randomSeed, ...
            weights, frequencyRangeHz);
    catch ME
        fprintf('Clustering solutions will be rebuilt: %s\n', ME.message);
        reuseSolutions = false;
    end
end

if ~reuseSolutions
    rng(randomSeed, 'twister');
    clustering_solutions = bemobil_repeated_clustering( ...
        BASESTUDY, BASEALLEEG, N, K, outlierSigma, ...
        BASESTUDY.etc.bemobil.clustering.preclustparams);
    assert_complete_solution_bank_local(clustering_solutions, N, K);

    solution_provenance = struct( ...
        'version', char(processingVersion), ...
        'source_signature', char(sourceSignature), ...
        'precluster_signature', char(preclusterSignature), ...
        'K', K, ...
        'repetitions', N, ...
        'outlier_sigma', outlierSigma, ...
        'random_seed', randomSeed, ...
        'clustering_weights', weights, ...
        'frequency_range_hz', frequencyRangeHz);
    save(solutionPath, 'clustering_solutions', 'solution_provenance', '-v7.3');
end

%% ROI EVALUATION
% BeMoBIL method: nearest cluster to each fixed ROI in every solution, then
% rank those candidates by six weighted quality measures.
solutionStatistics = solution_statistics_local( ...
    BASESTUDY, BASEALLEEG, clustering_solutions, N, K);

allSummary = table();
allMembership = table();

for roiIndex = 1:height(fixedROIs)
    roiID = string(fixedROIs.ROIID(roiIndex));
    originalClusterID = string(fixedROIs.OriginalClusterID(roiIndex));
    roiName = string(fixedROIs.ROIName(roiIndex));
    roiXYZ = double(fixedROIs{roiIndex, {'MNI_X','MNI_Y','MNI_Z'}});
    roiLabel = roiID + "_" + roiName;
    safeROILabel = safe_name_local(roiLabel);

    roiFolder = fullfile(roiRoot, char(safeROILabel));
    ensure_folder_local(roiFolder);
    roiStudyFilename = sprintf('HipExo_RHS_%s_K%02d.study', ...
        char(safeROILabel), K);
    roiStudyPath = fullfile(roiFolder, roiStudyFilename);
    evaluationPath = fullfile(roiFolder, ...
        char(safeROILabel + "_multivariate_evaluation.mat"));

    fprintf('ROI %d / %d: %s\n', roiIndex, height(fixedROIs), char(roiName));

    clusterMultivariateData = create_multivariate_data_local( ...
        solutionStatistics, roiXYZ, N);
    [rankedSolutions, qualityScores] = ...
        rank_solutions_local(clusterMultivariateData, qualityWeights);

    bestSolutionNumber = rankedSolutions(1);
    selectedClusterIndex = ...
        clusterMultivariateData.best_fitting_cluster(bestSolutionNumber);
    solutionField = sprintf('solution_%d', bestSolutionNumber);
    regularIndices = regular_cluster_indices_local( ...
        clustering_solutions.(solutionField), K, solutionField);
    assert(ismember(selectedClusterIndex, regularIndices), ...
        'ROI %s selected an invalid/outlier cluster.', char(roiName));

    save(evaluationPath, 'clusterMultivariateData', 'rankedSolutions', ...
        'qualityScores', 'bestSolutionNumber', 'selectedClusterIndex');

    STUDYroi = BASESTUDY;
    ROI_ALLEEG = BASEALLEEG;
    STUDYroi.cluster = clustering_solutions.(solutionField);
    STUDYroi = bemobil_dipoles(STUDYroi, ROI_ALLEEG);
    STUDYroi.cluster(selectedClusterIndex).name = char(safeROILabel);

    if ~isfield(STUDYroi, 'etc') || isempty(STUDYroi.etc), STUDYroi.etc = struct(); end
    STUDYroi.etc.rhs_roi_clustering = struct( ...
        'version', char(processingVersion), ...
        'roi_id', char(roiID), ...
        'original_exploratory_cluster_id', char(originalClusterID), ...
        'roi_name', char(roiName), ...
        'roi_provenance', cfg.roi.provenance, ...
        'roi_mni', roiXYZ, ...
        'K', K, ...
        'repetitions', N, ...
        'best_solution', bestSolutionNumber, ...
        'selected_cluster', selectedClusterIndex, ...
        'source_signature', char(sourceSignature));

    [STUDYroi, ROI_ALLEEG] = pop_savestudy(STUDYroi, ROI_ALLEEG, ...
        'filename', roiStudyFilename, 'filepath', roiFolder);

    members = hipexo.cluster_membership(STUDYroi, selectedClusterIndex);
    members.ROIID = repmat(roiID, height(members), 1);
    members.OriginalClusterID = repmat(originalClusterID, height(members), 1);
    members.ROIName = repmat(roiName, height(members), 1);
    members = members(:, {'ROIID','OriginalClusterID','ROIName', ...
        'DatasetIndex','Subject','ICASession','PhysicalRun','Condition','IC'});

    newSummaryRow = table( ...
        roiID, originalClusterID, roiName, ...
        roiXYZ(1), roiXYZ(2), roiXYZ(3), ...
        selectedClusterIndex, bestSolutionNumber, K, N, string(roiStudyPath), ...
        'VariableNames', {'ROIID','OriginalClusterID','ROIName', ...
        'MNI_X','MNI_Y','MNI_Z','SelectedClusterIndex', ...
        'BestSolutionNumber','K','Repetitions','StudyPath'});

    if isempty(allSummary), allSummary = newSummaryRow;
    else, allSummary = [allSummary; newSummaryRow]; %#ok<AGROW>
    end
    if isempty(allMembership), allMembership = members;
    else, allMembership = [allMembership; members]; %#ok<AGROW>
    end
end

%% SAVE STEP 12 OUTPUTS REQUIRED BY STEP 13
writetable(allSummary, fullfile(runRoot, 'ROI_repeated_clustering_summary.csv'));
writetable(allMembership, fullfile(runRoot, 'ROI_repeated_clustering_membership_all.csv'));
writetable(roiTable, fullfile(runRoot, 'ROI_definition_used.csv'));

runInfo = struct( ...
    'processing_version', char(processingVersion), ...
    'source_study', inputStudyPath, ...
    'source_signature', char(sourceSignature), ...
    'precluster_signature', char(preclusterSignature), ...
    'K', K, ...
    'repetitions', N, ...
    'outlier_sigma', outlierSigma, ...
    'random_seed', randomSeed, ...
    'clustering_weights', weights, ...
    'frequency_range_hz', frequencyRangeHz, ...
    'quality_measure_weights', qualityWeights(:)', ...
    'solution_bank', solutionPath, ...
    'std_preclust_patch', compatInfo.stdPreclustPatch);
save(fullfile(runRoot, 'ROI_repeated_clustering_run_info.mat'), 'runInfo');

fprintf('Step 12 completed: %s\n', runRoot);

close all force;

end

%% LOCAL FUNCTIONS

function restoreRMS = suspend_ica_rms_local()
% EEGLAB can otherwise rescale the same shared ICA differently per epoch set.
eeglab_options;
previousScale = option_scaleicarms;
restoreRMS = [];
if previousScale ~= 0
    restoreRMS = onCleanup(@() pop_editoptions('option_scaleicarms', previousScale));
    pop_editoptions('option_scaleicarms', 0);
    eeglab_options;
    assert(option_scaleicarms == 0, 'Could not disable automatic ICA RMS scaling.');
end
end

function ensure_folder_local(folderPath)
if ~isfolder(folderPath)
    [ok, message] = mkdir(folderPath);
    assert(ok, 'Could not create folder:\n%s\n%s', folderPath, message);
end
end

function [STUDY, designIndex] = make_all_condition_design_local(STUDY, ALLEEG)
subjects = unique(string({STUDY.datasetinfo.subject}), 'stable');
conditions = unique(string({STUDY.datasetinfo.condition}), 'stable');
designIndex = 1;
STUDY = std_makedesign(STUDY, ALLEEG, designIndex, ...
    'name', 'All RHS epoched data - IC clustering', ...
    'delfiles', 'off', 'defaultdesign', 'off', ...
    'variable1', 'condition', 'values1', cellstr(conditions), ...
    'vartype1', 'categorical', 'subjselect', cellstr(subjects));
end

function uniqueICAICCount = verify_shared_ica_study_local(STUDY, ALLEEG)
assert(~isempty(STUDY.datasetinfo) && numel(STUDY.datasetinfo) == numel(ALLEEG), ...
    'RHS STUDY/ALLEEG dataset counts do not match.');
subjects = strtrim(string({STUDY.datasetinfo.subject}));
assert(all(strlength(subjects) > 0), 'RHS STUDY contains an empty subject label.');

uniqueSubjects = unique(subjects, 'stable');
for subjectIndex = 1:numel(uniqueSubjects)
    subject = uniqueSubjects(subjectIndex);
    positions = find(subjects == subject);
    sessions = double([STUDY.datasetinfo(positions).session]);
    assert(all(isfinite(sessions)) && numel(unique(sessions)) == 1, ...
        '%s does not use one shared ICA session.', char(subject));

    referenceICs = [];
    referenceICA = "";
    referenceDipfit = "";
    for positionIndex = 1:numel(positions)
        p = positions(positionIndex);
        info = STUDY.datasetinfo(p);
        selectedICs = sort(double(info.comps(:)'));
        assert(~isempty(selectedICs) && all(isfinite(selectedICs)) && ...
            all(selectedICs >= 1 & selectedICs == round(selectedICs)) && ...
            numel(unique(selectedICs)) == numel(selectedICs), ...
            'Dataset %d has an invalid selected-IC list.', p);

        if isempty(referenceICs)
            referenceICs = selectedICs;
        else
            assert(isequal(selectedICs, referenceICs), ...
                '%s does not use one shared selected-IC list.', char(subject));
        end

        eegIndex = double(info.index);
        assert(eegIndex >= 1 && eegIndex <= numel(ALLEEG) && eegIndex == round(eegIndex), ...
            'Dataset %d has an invalid ALLEEG index.', p);
        EEG = ALLEEG(eegIndex);
        thisICA = string(hipexo.ica_identity_signature(EEG));
        if strlength(referenceICA) == 0
            referenceICA = thisICA;
        else
            assert(thisICA == referenceICA, ...
                '%s has different ICA decompositions across runs.', char(subject));
        end

        assert(isfield(EEG, 'dipfit') && isfield(EEG.dipfit, 'model'), ...
            '%s has no DIPFIT model.', char(subject));
        for ic = selectedICs
            assert(ic <= numel(EEG.dipfit.model), ...
                '%s IC %d has no DIPFIT model.', char(subject), ic);
            model = EEG.dipfit.model(ic);
            xyz = primary_dipole_xyz_local(model);
            rv = dipole_rv_local(model);
            assert(all(isfinite(xyz)) && isfinite(rv), ...
                '%s IC %d lacks a valid dipole position/RV.', char(subject), ic);
        end
        thisDipfit = string(hipexo.content_signature(EEG.dipfit.model(selectedICs)));
        if strlength(referenceDipfit) == 0
            referenceDipfit = thisDipfit;
        else
            assert(thisDipfit == referenceDipfit, ...
                '%s has different selected-IC DIPFIT models across runs.', char(subject));
        end
    end
end

[~, uniqueMembers] = hipexo.cluster_membership(STUDY, 1);
uniqueICAICCount = height(uniqueMembers);
assert(uniqueICAICCount > 0, 'RHS STUDY parent cluster is empty.');
end

function signature = study_source_signature_local(STUDY)
% Step 11 already hashes the full RHS datasets and accepted IC selections.
% Reuse that upstream scientific-input signature instead of loading every
% EEG sample again in Step 12 solely to hash the same inputs a second time.
assert(isfield(STUDY, 'etc') && isfield(STUDY.etc, 'rhs_epoched_study') && ...
    isfield(STUDY.etc.rhs_epoched_study, 'input_signature'), ...
    'Step 11 STUDY is missing its input signature. Re-run Step 11.');
signature = string(STUDY.etc.rhs_epoched_study.input_signature);
assert(isscalar(signature) && strlength(signature) > 0 && ...
    startsWith(signature, "content-sha256:"), ...
    'Step 11 input signature is invalid. Re-run Step 11.');
end

function verify_precluster_reuse_local(STUDY, sourceSignature, ...
        weights, frequencyRangeHz, timeWindowMs, expectedUniqueICs)
assert(isfield(STUDY, 'etc') && isfield(STUDY.etc, 'rhs_roi_precluster'), ...
    'Existing precluster has no Step 12 provenance.');
meta = STUDY.etc.rhs_roi_precluster;
required = {'source_signature','clustering_weights','frequency_range_hz', ...
    'time_window_ms','unique_ica_ic_units'};
assert(all(isfield(meta, required)), 'Existing precluster provenance is incomplete.');
assert(string(meta.source_signature) == string(sourceSignature), ...
    'Input RHS scientific content/identity changed.');
assert(isequaln(meta.clustering_weights, weights), 'Preclustering weights changed.');
assert(isequaln(double(meta.frequency_range_hz(:)'), frequencyRangeHz), ...
    'Preclustering frequency range changed.');
assert(isequaln(double(meta.time_window_ms(:)'), timeWindowMs), ...
    'Preclustering time window changed.');
assert(double(meta.unique_ica_ic_units) == expectedUniqueICs, ...
    'Selected shared ICA component count changed.');
assert(isfield(STUDY.etc, 'preclust') && ...
    isfield(STUDY.etc.preclust, 'preclustdata') && ...
    ~isempty(STUDY.etc.preclust.preclustdata), ...
    'Existing precluster is missing feature data.');
assert(size(STUDY.etc.preclust.preclustdata, 1) == expectedUniqueICs, ...
    'Existing precluster feature rows do not match the unique shared-ICA components.');
end

function verify_solution_reuse_local(provenance, sourceSignature, ...
        preclusterSignature, K, N, outlierSigma, randomSeed, weights, frequencyRangeHz)
required = {'source_signature','precluster_signature','K','repetitions', ...
    'outlier_sigma','random_seed','clustering_weights','frequency_range_hz'};
assert(all(isfield(provenance, required)), ...
    'Existing solution provenance is incomplete.');
assert(string(provenance.source_signature) == string(sourceSignature), ...
    'Solution bank used different RHS inputs.');
assert(string(provenance.precluster_signature) == string(preclusterSignature), ...
    'Solution bank used different precluster features/component mapping.');
assert(double(provenance.K) == K, 'Solution bank K does not match.');
assert(double(provenance.repetitions) == N, ...
    'Solution bank repetition count does not match.');
assert(double(provenance.outlier_sigma) == outlierSigma, ...
    'Solution bank outlier sigma does not match.');
assert(double(provenance.random_seed) == randomSeed, ...
    'Solution bank random seed does not match.');
assert(isequaln(provenance.clustering_weights, weights), ...
    'Solution bank clustering weights do not match.');
assert(isequal(double(provenance.frequency_range_hz(:)'), frequencyRangeHz), ...
    'Solution bank frequency range does not match.');
end

function assert_complete_solution_bank_local(solutions, N, K)
assert(isstruct(solutions) && isscalar(solutions), ...
    'clustering_solutions must be a scalar structure.');
for s = 1:N
    field = sprintf('solution_%d', s);
    assert(isfield(solutions, field), 'Solution bank is missing %s.', field);
    clusters = solutions.(field);
    regular = regular_cluster_indices_local(clusters, K, field);
    for c = regular
        assert(isfield(clusters(c), 'sets') && isfield(clusters(c), 'comps'), ...
            '%s cluster %d is missing sets/comps.', field, c);
    end
end
end

function regular = regular_cluster_indices_local(clusters, K, label)
% BeMoBIL/pop_clust layout: Parent, optional Outlier, then K regular clusters.
assert(isstruct(clusters) && ~isempty(clusters), ...
    '%s does not contain a cluster structure.', label);
n = numel(clusters);
if n == K + 2
    regular = 3:n;
elseif n == K + 1
    regular = 2:n;
else
    error('%s contains %d cluster entries; expected %d or %d.', ...
        label, n, K + 1, K + 2);
end
assert(numel(regular) == K, '%s does not contain exactly %d regular clusters.', label, K);
end

function statistics = solution_statistics_local(STUDY, ALLEEG, solutions, N, K)
statistics = cell(N, 1);
for s = 1:N
    field = sprintf('solution_%d', s);
    clusters = solutions.(field);
    regular = regular_cluster_indices_local(clusters, K, field);
    solutionStudy = STUDY;
    solutionStudy.cluster = clusters;

    S = struct('clusterIndices', regular, ...
        'centroid', nan(K, 3), ...
        'spread', nan(K, 1), ...
        'subjectCount', nan(K, 1), ...
        'icCount', nan(K, 1), ...
        'meanRV', nan(K, 1));

    for j = 1:K
        [~, uniqueMembers] = hipexo.cluster_membership(solutionStudy, regular(j));
        assert(~isempty(uniqueMembers), '%s contains an empty regular cluster.', field);
        [centroid, meanRV, positions] = cluster_source_statistics_local( ...
            ALLEEG, uniqueMembers);
        offsets = positions - centroid;
        S.centroid(j, :) = centroid;
        S.spread(j) = sum(offsets(:).^2);
        S.subjectCount(j) = numel(unique(uniqueMembers.Subject));
        S.icCount(j) = height(uniqueMembers);
        S.meanRV(j) = meanRV;
    end
    statistics{s} = S;
end
end

function clusterData = create_multivariate_data_local(statistics, roiXYZ, N)
bestCluster = zeros(N, 1);
bestDistance = zeros(N, 1);
bestXYZ = zeros(N, 3);
bestSpread = zeros(N, 1);
bestSubjectCount = zeros(N, 1);
bestICCount = zeros(N, 1);
bestMeanRV = zeros(N, 1);

for s = 1:N
    S = statistics{s};
    distances = vecnorm(S.centroid - roiXYZ, 2, 2);
    [bestDistance(s), j] = min(distances);
    assert(isfinite(bestDistance(s)), 'A clustering solution has no finite ROI candidate.');
    bestCluster(s) = S.clusterIndices(j);
    bestXYZ(s, :) = S.centroid(j, :);
    bestSpread(s) = S.spread(j);
    bestSubjectCount(s) = S.subjectCount(j);
    bestICCount(s) = S.icCount(j);
    bestMeanRV(s) = S.meanRV(j);
end

assert(all(bestSubjectCount > 0) && all(bestICCount > 0), ...
    'At least one ROI candidate has no subject/component representation.');

clusterData = struct();
clusterData.data = [ ...
    bestSubjectCount, ...
    bestICCount, ...
    bestICCount ./ bestSubjectCount, ...
    bestSpread ./ bestICCount, ...
    bestMeanRV, ...
    bestXYZ, ...
    bestDistance];
assert(all(isfinite(clusterData.data), 'all'), ...
    'ROI quality data contain non-finite values; ranking was not performed.');
clusterData.best_fitting_cluster = bestCluster;
clusterData.cluster_ROI_MNI = struct('x', roiXYZ(1), 'y', roiXYZ(2), 'z', roiXYZ(3));
end

function [ranked, scores] = rank_solutions_local(clusterData, weights)
data = double(clusterData.data);
assert(size(data, 2) == 9 && all(isfinite(data), 'all'), ...
    'ROI multivariate data must contain nine finite dimensions.');

centered = data - median(data, 1);
covarianceMatrix = cov(data);
inverseCovariance = pinv(covarianceMatrix);
mahalanobisDistance = sum((centered * inverseCovariance) .* centered, 2);
assert(all(isfinite(mahalanobisDistance)), ...
    'Mahalanobis distance calculation failed.');
% pinv/cov can produce tiny negative round-off values for a quadratic form.
mahalanobisDistance = max(mahalanobisDistance, 0);

measures = [data(:,1), data(:,3), data(:,4), data(:,5), ...
    data(:,9), mahalanobisDistance];
for c = 1:size(measures, 2)
    denominator = max(measures(:,c));
    if denominator > 0
        measures(:,c) = measures(:,c) ./ denominator;
    else
        measures(:,c) = 0;
    end
end

scores = measures * weights(:);
assert(all(isfinite(scores)), 'ROI quality scores contain non-finite values.');
[~, ranked] = sort(scores, 'descend');
end

function [centroid, meanRV, positions] = cluster_source_statistics_local(ALLEEG, uniqueMembers)
n = height(uniqueMembers);
assert(n > 0, 'Cluster has no unique ICA components.');
positions = nan(n, 3);
rvValues = nan(n, 1);
for r = 1:n
    datasetIndex = double(uniqueMembers.DatasetIndex(r));
    ic = double(uniqueMembers.IC(r));
    assert(datasetIndex >= 1 && datasetIndex <= numel(ALLEEG), ...
        'Invalid dataset index %d.', datasetIndex);
    assert(ic >= 1 && ic <= numel(ALLEEG(datasetIndex).dipfit.model), ...
        'Invalid IC %d in dataset %d.', ic, datasetIndex);
    model = ALLEEG(datasetIndex).dipfit.model(ic);
    positions(r, :) = primary_dipole_xyz_local(model);
    rvValues(r) = dipole_rv_local(model);
end
assert(all(isfinite(positions), 'all') && all(isfinite(rvValues)), ...
    'Cluster contains invalid dipole positions or RV values.');
centroid = mean(positions, 1);
meanRV = mean(rvValues);
end

function xyz = primary_dipole_xyz_local(model)
xyz = [NaN NaN NaN];
if ~isfield(model, 'posxyz') || isempty(model.posxyz), return; end
position = double(model.posxyz);
if size(position, 2) ~= 3, return; end
% Match bemobil_dipoles: DIPFIT can store a dummy second dipole at [0 0 0].
if size(position, 1) == 2 && all(position(2, :) == 0)
    position(2, :) = [];
end
xyz = mean(position, 1, 'omitnan');
end

function rv = dipole_rv_local(model)
rv = NaN;
if ~isfield(model, 'rv') || isempty(model.rv), return; end
values = double(model.rv(:));
values = values(isfinite(values));
if ~isempty(values), rv = mean(values); end
end

function outputName = safe_name_local(inputName)
outputName = regexprep(string(inputName), '[^a-zA-Z0-9_-]', '_');
outputName = regexprep(outputName, '_+', '_');
outputName = strip(outputName, 'both', '_');
assert(strlength(outputName) > 0, 'Invalid ROI name.');
end
