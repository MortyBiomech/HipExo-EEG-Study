% Goal:
% 1. Load the frozen Yes-only EEGLAB STUDY.
% 2. Verify that the STUDY contains 21 datasets and 62 selected ICs.
% 3. Precompute component scalp maps only.
% 4. Build a spatial preclustering feature matrix using:
%       - scalp map: 10 PCs, polarity-invariant, weight 1
%       - equivalent dipole location: weight 3
%       - final PCA dimension: 10
% 5. Run reproducible k-means candidate solutions for K = 5, 6, 7, and 8.
% 6. Save every clustered STUDY and export membership/summary CSV files.
% 7. Leave the K = 6 solution loaded and optionally open pop_clustedit.
%
% Important:
% - Spectrum is NOT used as a clustering feature in this script.
% - Previously generated .icaspec files are not deleted or modified.
% - This script does not remove ICs and never calls pop_subcomp.
% - It does not overwrite the original Yes-only STUDY.
% - It only uses ICs already stored in STUDY.datasetinfo(k).comps.
% - Every dataset keeps its own independent ICA decomposition.
%
% Input:
%   output_data/9_group-STUDY/HipExo_manual_IC_Yes_only.study
%
% Main output:
%   output_data/9_group-STUDY/
%       HipExo_manual_IC_Yes_only_spatial_preclustered.study
%
% Candidate clustering outputs:
%   output_data/9_group-STUDY/spatial_clustering_k05/
%   output_data/9_group-STUDY/spatial_clustering_k06/
%   output_data/9_group-STUDY/spatial_clustering_k07/
%   output_data/9_group-STUDY/spatial_clustering_k08/
%
% Run:
%   run_yes_only_IC_spatial_clustering
%
% Recommended interpretation:
% - Treat K = 6 as the primary coarse spatial solution.
% - Compare K = 5, 6, 7, and 8 before manually reassigning components.
% - Use individual-IC spectra later as quality control, not as a distance
%   feature in this spatial clustering run.
% - Do not interpret automatic cluster names as final anatomy.

clear;
clc;
close all;

%% ========================================================================
%  LOAD CENTRAL PATHS
%  ========================================================================

scriptFolder = fileparts(mfilename('fullpath'));

run(fullfile(scriptFolder, 'paths.m'));

if ~exist(outputFolder, 'dir')
    error('Output folder does not exist:\n%s', outputFolder);
end

%% ========================================================================
%  USER SETTINGS
%  ========================================================================

studyFolder = fullfile(outputFolder, '9_group-STUDY');

inputStudyFilename = 'HipExo_manual_IC_Yes_only.study';

preclusteredStudyFilename = ...
    'HipExo_manual_IC_Yes_only_spatial_preclustered.study';

% Candidate K values. Clustering itself is fast once preclustering is done.
clusterCounts = [5 6 7 8];

% The solution left in the MATLAB workspace and opened for visual review.
primaryClusterCount = 6;

% Recompute component scalp-map measure files.
% First complete spatial run: true
% Later reruns using unchanged datasets/parameters: false
recomputeMeasures = true;

% Spatial PCA/weight settings.
scalpPCs          = 10;
scalpWeight       = 1;

dipoleWeight      = 3;

finalPCs          = 10;

% Components farther than this many SD from their nearest centroid are
% moved to the outlier cluster. Set Inf to disable automatic outliers.
outlierSD = 3;

% Reproducible k-means initialization.
randomSeed = 20260714;

% Expected frozen Yes-only STUDY content.
expectedDatasetCount = 21;
expectedSelectedICCount = 62;

% Open pop_clustedit for the primary K solution after completion.
openClusterEditorAtEnd = true;

%% ========================================================================
%  INITIALIZE EEGLAB
%  ========================================================================

if ~exist('pop_loadstudy', 'file')
    eeglab nogui;
end

try
    pop_editoptions( ...
        'option_saveversion6', 0, ...
        'option_single', 0, ...
        'option_memmapdata', 0, ...
        'option_savetwofiles', 1, ...
        'option_storedisk', 1);
catch ME
    warning('Could not set all EEGLAB memory/save options: %s', ME.message);
end

inputStudyPath = fullfile(studyFolder, inputStudyFilename);

if exist(inputStudyPath, 'file') ~= 2
    error('Input STUDY was not found:\n%s', inputStudyPath);
end

%% ========================================================================
%  LOAD YES-ONLY STUDY
%  ========================================================================

fprintf('\n============================================================\n');
fprintf('YES-ONLY IC PRECLUSTERING / CLUSTERING STARTED\n');
fprintf('============================================================\n');
fprintf('Running script:\n%s\n', mfilename('fullpath'));
fprintf('Input STUDY:\n%s\n', inputStudyPath);
fprintf('Candidate K values: %s\n', num2str(clusterCounts));
fprintf('Primary K: %d\n', primaryClusterCount);
fprintf('============================================================\n\n');

[STUDY, ALLEEG] = pop_loadstudy( ...
    'filename', inputStudyFilename, ...
    'filepath', studyFolder);

[STUDY, ALLEEG] = std_checkset(STUDY, ALLEEG);

%% ========================================================================
%  VERIFY STUDY CONTENT
%  ========================================================================

nDatasets = numel(STUDY.datasetinfo);

if nDatasets ~= expectedDatasetCount
    error(['Unexpected dataset count.\n' ...
        'Expected: %d\nFound: %d'], ...
        expectedDatasetCount, nDatasets);
end

selectedICCounts = zeros(nDatasets, 1);

for d = 1:nDatasets

    comps = STUDY.datasetinfo(d).comps;

    if isempty(comps)
        error(['STUDY.datasetinfo(%d).comps is empty.\n' ...
            'An empty comps field means all components, which violates ' ...
            'the Yes-only rule.'], d);
    end

    comps = double(comps(:))';

    if any(comps < 1 | comps ~= round(comps))
        error('Dataset %d contains invalid component indices.', d);
    end

    if d > numel(ALLEEG)
        error('ALLEEG has fewer datasets than STUDY.datasetinfo.');
    end

    nICs = size(ALLEEG(d).icaweights, 1);

    if isempty(ALLEEG(d).icaweights) || isempty(ALLEEG(d).icasphere)
        error('Dataset %d has no valid ICA decomposition.', d);
    end

    if any(comps > nICs)
        error(['Selected IC index exceeds the ICA dimension in dataset %d.\n' ...
            'Selected: %s\nNumber of ICs: %d'], ...
            d, num2str(comps), nICs);
    end

    selectedICCounts(d) = numel(comps);

end

totalSelectedICs = sum(selectedICCounts);

if totalSelectedICs ~= expectedSelectedICCount
    error(['Unexpected total selected IC count.\n' ...
        'Expected: %d\nFound: %d'], ...
        expectedSelectedICCount, totalSelectedICs);
end

fprintf('Datasets verified: %d\n', nDatasets);
fprintf('Selected Yes ICs verified: %d\n\n', totalSelectedICs);

%% ========================================================================
%  BUILD A FULL CONDITION-BASED DESIGN FOR IC CLUSTERING
%  ========================================================================

% The STUDY created from continuous datasets may contain an empty/default
% design even though STUDY.datasetinfo is complete. Rebuild design 1
% explicitly from all dataset condition labels and all subjects.
%
% This does not merge datasets or ICA decompositions. Each dataset remains
% an independent entry in STUDY.datasetinfo / ALLEEG; the design only tells
% EEGLAB which datasets belong to the clustering analysis.

allConditionValues = cell(1, nDatasets);
allSubjectValues   = cell(1, nDatasets);

for d = 1:nDatasets
    allConditionValues{d} = char(string( ...
        STUDY.datasetinfo(d).condition));
    allSubjectValues{d} = char(string( ...
        STUDY.datasetinfo(d).subject));
end

allConditionValues = unique(allConditionValues, 'stable');
allSubjectValues   = unique(allSubjectValues, 'stable');

if any(cellfun(@isempty, allConditionValues))
    error(['At least one STUDY dataset has an empty condition label. ' ...
        'A complete condition-based design cannot be created.']);
end

if any(cellfun(@isempty, allSubjectValues))
    error(['At least one STUDY dataset has an empty subject label. ' ...
        'A complete condition-based design cannot be created.']);
end

designIndex = 1;

STUDY = std_makedesign( ...
    STUDY, ...
    ALLEEG, ...
    designIndex, ...
    'name', 'All conditions - Yes IC clustering', ...
    'delfiles', 'off', ...
    'defaultdesign', 'off', ...
    'variable1', 'condition', ...
    'values1', allConditionValues, ...
    'vartype1', 'categorical', ...
    'subjselect', allSubjectValues);

[STUDY, ALLEEG] = std_checkset(STUDY, ALLEEG);

% std_preclust checks the ParentCluster membership, not merely the presence
% of STUDY.datasetinfo. Verify the exact structure it will use.
if ~isfield(STUDY, 'cluster') || isempty(STUDY.cluster) || ...
        ~isfield(STUDY.cluster(1), 'sets') || ...
        isempty(STUDY.cluster(1).sets)

    error(['The rebuilt STUDY design did not create a valid ' ...
        'ParentCluster membership list.']);
end

parentDatasetIndices = double(STUDY.cluster(1).sets(:));
parentDatasetIndices = unique(parentDatasetIndices( ...
    isfinite(parentDatasetIndices) & parentDatasetIndices > 0))';

missingFromParentCluster = setdiff(1:nDatasets, parentDatasetIndices);

if ~isempty(missingFromParentCluster)
    error(['The rebuilt design still excludes datasets from the ' ...
        'ParentCluster.\nMissing dataset indices: %s'], ...
        num2str(missingFromParentCluster));
end

parentComponents = double(STUDY.cluster(1).comps(:));
parentComponents = parentComponents( ...
    isfinite(parentComponents) & parentComponents > 0);

if numel(parentComponents) ~= expectedSelectedICCount
    error(['ParentCluster component count mismatch after rebuilding ' ...
        'the design.\nExpected: %d\nFound: %d'], ...
        expectedSelectedICCount, ...
        numel(parentComponents));
end

fprintf('Clustering design rebuilt: %d (%s)\n', ...
    designIndex, STUDY.design(designIndex).name);
fprintf('Design conditions included: %d\n', ...
    numel(allConditionValues));
fprintf('Design subjects included: %d\n', ...
    numel(allSubjectValues));
fprintf('ParentCluster covers all %d datasets and %d selected ICs.\n\n', ...
    nDatasets, numel(parentComponents));

%% ========================================================================
%  VERIFY DIPFIT INFORMATION FOR EVERY SELECTED IC
%  ========================================================================

dipoleProblems = strings(0, 1);

for d = 1:nDatasets

    selectedComps = double(STUDY.datasetinfo(d).comps(:))';

    if ~isfield(ALLEEG(d), 'dipfit') || ...
            ~isfield(ALLEEG(d).dipfit, 'model') || ...
            isempty(ALLEEG(d).dipfit.model)

        dipoleProblems(end+1, 1) = sprintf( ...
            'Dataset %d (%s): missing DIPFIT model.', ...
            d, ALLEEG(d).setname); %#ok<SAGROW>

        continue;
    end

    nModels = numel(ALLEEG(d).dipfit.model);

    for comp = selectedComps

        if comp > nModels
            dipoleProblems(end+1, 1) = sprintf( ...
                'Dataset %d (%s), IC %d: model index missing.', ...
                d, ALLEEG(d).setname, comp); %#ok<SAGROW>
            continue;
        end

        model = ALLEEG(d).dipfit.model(comp);

        if ~isfield(model, 'posxyz') || isempty(model.posxyz) || ...
                any(~isfinite(model.posxyz(:)))

            dipoleProblems(end+1, 1) = sprintf( ...
                'Dataset %d (%s), IC %d: invalid posxyz.', ...
                d, ALLEEG(d).setname, comp); %#ok<SAGROW>
        end

    end

end

if ~isempty(dipoleProblems)
    error('Selected ICs have invalid DIPFIT information:\n%s', ...
        strjoin(cellstr(dipoleProblems), newline));
end

fprintf('DIPFIT positions verified for all selected ICs.\n\n');

%% ========================================================================
%  PRECOMPUTE SCALP MAPS
%  ========================================================================

if recomputeMeasures
    recomputeFlag = 'on';
else
    recomputeFlag = 'off';
end

fprintf('============================================================\n');
fprintf('PRECOMPUTING COMPONENT SCALP MAPS\n');
fprintf('============================================================\n');
fprintf('Measure: scalp maps only\n');
fprintf('Spectrum is not computed or used by this script.\n');
fprintf('Only preselected Yes ICs are processed.\n');
fprintf('Recompute: %s\n', recomputeFlag);
fprintf('============================================================\n\n');

[STUDY, ALLEEG] = std_precomp( ...
    STUDY, ...
    ALLEEG, ...
    'components', ...
    'design', designIndex, ...
    'allcomps', 'off', ...
    'recompute', recomputeFlag, ...
    'rmicacomps', 'off', ...
    'scalp', 'on');

[STUDY, ALLEEG] = std_checkset(STUDY, ALLEEG);

%% ========================================================================
%  BUILD SPATIAL PRECLUSTERING MATRIX
%  ========================================================================

fprintf('\n============================================================\n');
fprintf('BUILDING SPATIAL PRECLUSTERING FEATURE MATRIX\n');
fprintf('============================================================\n');
fprintf('Scalp map: %d PCs, absolute/polarity-invariant, weight %.2f\n', ...
    scalpPCs, scalpWeight);
fprintf('Dipole location weight: %.2f\n', dipoleWeight);
fprintf('Final PCA dimensions: %d\n', finalPCs);
fprintf('Spectrum feature: disabled\n');
fprintf('============================================================\n\n');

[STUDY, ALLEEG] = std_preclust( ...
    STUDY, ...
    ALLEEG, ...
    1, ...
    { ...
        'scalp', ...
        'npca', scalpPCs, ...
        'norm', 1, ...
        'weight', scalpWeight, ...
        'abso', 1 ...
    }, ...
    { ...
        'dipoles', ...
        'norm', 1, ...
        'weight', dipoleWeight ...
    }, ...
    { ...
        'finaldim', ...
        'npca', finalPCs ...
    });

[STUDY, ALLEEG] = std_checkset(STUDY, ALLEEG);

% Record the exact spatial clustering choices.
if ~isfield(STUDY, 'etc') || isempty(STUDY.etc)
    STUDY.etc = struct();
end

STUDY.etc.yes_only_ic_spatial_clustering = struct();
STUDY.etc.yes_only_ic_spatial_clustering.created_on = ...
    char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
STUDY.etc.yes_only_ic_spatial_clustering.input_study = ...
    inputStudyPath;
STUDY.etc.yes_only_ic_spatial_clustering.selected_ic_count = ...
    totalSelectedICs;
STUDY.etc.yes_only_ic_spatial_clustering.features = ...
    {'scalp', 'dipoles'};
STUDY.etc.yes_only_ic_spatial_clustering.spectrum_used = false;
STUDY.etc.yes_only_ic_spatial_clustering.scalp_pcs = scalpPCs;
STUDY.etc.yes_only_ic_spatial_clustering.scalp_weight = ...
    scalpWeight;
STUDY.etc.yes_only_ic_spatial_clustering.scalp_absolute = true;
STUDY.etc.yes_only_ic_spatial_clustering.dipole_weight = ...
    dipoleWeight;
STUDY.etc.yes_only_ic_spatial_clustering.final_pcs = finalPCs;
STUDY.etc.yes_only_ic_spatial_clustering.random_seed = ...
    randomSeed;
STUDY.etc.yes_only_ic_spatial_clustering.outlier_sd = ...
    outlierSD;
STUDY.etc.yes_only_ic_spatial_clustering.candidate_cluster_counts = ...
    clusterCounts;
STUDY.etc.yes_only_ic_spatial_clustering.primary_cluster_count = ...
    primaryClusterCount;

[STUDY, ALLEEG] = pop_savestudy( ...
    STUDY, ...
    ALLEEG, ...
    'filename', preclusteredStudyFilename, ...
    'filepath', studyFolder);

preclusteredStudyPath = fullfile( ...
    studyFolder, ...
    preclusteredStudyFilename);

fprintf('\nSpatially preclustered STUDY saved:\n%s\n', ...
    preclusteredStudyPath);

% Frozen base copied before any K-specific clustering.
BASESTUDY = STUDY;

%% ========================================================================
%  RUN CANDIDATE K-MEANS SOLUTIONS
%  ========================================================================

if ~ismember(primaryClusterCount, clusterCounts)
    error('primaryClusterCount must be included in clusterCounts.');
end

primaryStudy = [];
primaryStudyFolder = '';
primaryStudyFilename = '';

for kIndex = 1:numel(clusterCounts)

    kValue = clusterCounts(kIndex);

    fprintf('\n\n============================================================\n');
    fprintf('RUNNING K-MEANS CLUSTERING: K = %d\n', kValue);
    fprintf('============================================================\n');

    rng(randomSeed + kValue, 'twister');

    STUDY_k = BASESTUDY;

    STUDY_k = pop_clust( ...
        STUDY_k, ...
        ALLEEG, ...
        'algorithm', 'kmeanscluster', ...
        'clus_num', kValue, ...
        'outliers', outlierSD, ...
        'save', 'off');

    if ~isfield(STUDY_k, 'etc') || isempty(STUDY_k.etc)
        STUDY_k.etc = struct();
    end

    STUDY_k.etc.yes_only_ic_spatial_clustering.cluster_count = kValue;
    STUDY_k.etc.yes_only_ic_spatial_clustering.clustered_on = ...
        char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    STUDY_k.etc.yes_only_ic_spatial_clustering.algorithm = ...
        'kmeanscluster';
    STUDY_k.etc.yes_only_ic_spatial_clustering.kmeans_seed = ...
        randomSeed + kValue;

    kFolder = fullfile( ...
        studyFolder, ...
        sprintf('spatial_clustering_k%02d', kValue));

    if ~exist(kFolder, 'dir')
        mkdir(kFolder);
    end

    kStudyFilename = sprintf( ...
        'HipExo_manual_IC_Yes_only_spatial_clustered_k%02d.study', ...
        kValue);

    [STUDY_k, ALLEEG] = pop_savestudy( ...
        STUDY_k, ...
        ALLEEG, ...
        'filename', kStudyFilename, ...
        'filepath', kFolder);

    [membershipTable, clusterSummaryTable] = ...
        build_cluster_export_tables_local(STUDY_k);

    membershipFile = fullfile( ...
        kFolder, ...
        sprintf('HipExo_IC_spatial_cluster_membership_k%02d.csv', ...
            kValue));

    clusterSummaryFile = fullfile( ...
        kFolder, ...
        sprintf('HipExo_IC_spatial_cluster_summary_k%02d.csv', ...
            kValue));

    writetable(membershipTable, membershipFile);
    writetable(clusterSummaryTable, clusterSummaryFile);

    fprintf('Clustered STUDY saved:\n%s\n', ...
        fullfile(kFolder, kStudyFilename));
    fprintf('Membership CSV:\n%s\n', membershipFile);
    fprintf('Cluster summary CSV:\n%s\n', clusterSummaryFile);

    disp(clusterSummaryTable);

    if kValue == primaryClusterCount
        primaryStudy = STUDY_k;
        primaryStudyFolder = kFolder;
        primaryStudyFilename = kStudyFilename;
    end

end

%% ========================================================================
%  LEAVE PRIMARY SOLUTION IN WORKSPACE
%  ========================================================================

STUDY = primaryStudy;

fprintf('\n\n============================================================\n');
fprintf('SPATIAL CLUSTERING COMPLETED\n');
fprintf('============================================================\n');
fprintf('Primary K solution loaded in STUDY: K = %d\n', ...
    primaryClusterCount);
fprintf('Primary STUDY:\n%s\n', ...
    fullfile(primaryStudyFolder, primaryStudyFilename));
fprintf('Candidate solutions created: %s\n', num2str(clusterCounts));
fprintf('No IC was removed.\n');
fprintf('Spectrum was not used as a clustering feature.\n');
fprintf('Original Yes-only STUDY was not overwritten.\n');
fprintf('============================================================\n\n');

if openClusterEditorAtEnd

    try
        STUDY = pop_clustedit(STUDY, ALLEEG);
    catch ME
        warning(['Clustering finished, but pop_clustedit could not be ' ...
            'opened automatically:\n%s\n\n' ...
            'Load the primary STUDY and run:\n' ...
            'STUDY = pop_clustedit(STUDY, ALLEEG);'], ...
            ME.message);
    end

end

%% ========================================================================
%  LOCAL FUNCTIONS
%  ========================================================================

function [membershipTable, summaryTable] = ...
        build_cluster_export_tables_local(STUDY)

    clusterIndexColumn = [];
    clusterNameColumn = strings(0, 1);
    isOutlierColumn = false(0, 1);
    datasetIndexColumn = [];
    subjectColumn = strings(0, 1);
    conditionColumn = strings(0, 1);
    sessionColumn = strings(0, 1);
    datasetFilenameColumn = strings(0, 1);
    componentColumn = [];

    % Cluster 1 is ParentCluster and contains all selected components.
    for c = 2:numel(STUDY.cluster)

        [setVector, compVector] = flatten_cluster_members_local( ...
            STUDY.cluster(c).sets, ...
            STUDY.cluster(c).comps);

        clusterName = string(STUDY.cluster(c).name);
        isOutlier = contains(lower(clusterName), 'outlier');

        for m = 1:numel(setVector)

            datasetIndex = setVector(m);
            componentIndex = compVector(m);

            if datasetIndex < 1 || ...
                    datasetIndex > numel(STUDY.datasetinfo)
                continue;
            end

            info = STUDY.datasetinfo(datasetIndex);

            clusterIndexColumn(end+1, 1) = c; %#ok<AGROW>
            clusterNameColumn(end+1, 1) = clusterName; %#ok<AGROW>
            isOutlierColumn(end+1, 1) = isOutlier; %#ok<AGROW>
            datasetIndexColumn(end+1, 1) = datasetIndex; %#ok<AGROW>
            subjectColumn(end+1, 1) = ...
                scalar_to_string_local(info.subject); %#ok<AGROW>
            conditionColumn(end+1, 1) = ...
                scalar_to_string_local(info.condition); %#ok<AGROW>
            sessionColumn(end+1, 1) = ...
                scalar_to_string_local(info.session); %#ok<AGROW>
            datasetFilenameColumn(end+1, 1) = ...
                scalar_to_string_local(info.filename); %#ok<AGROW>
            componentColumn(end+1, 1) = componentIndex; %#ok<AGROW>

        end

    end

    membershipTable = table( ...
        clusterIndexColumn, ...
        clusterNameColumn, ...
        isOutlierColumn, ...
        datasetIndexColumn, ...
        subjectColumn, ...
        conditionColumn, ...
        sessionColumn, ...
        datasetFilenameColumn, ...
        componentColumn, ...
        'VariableNames', { ...
            'ClusterIndex', ...
            'ClusterName', ...
            'IsOutlierCluster', ...
            'DatasetIndex', ...
            'Subject', ...
            'Condition', ...
            'Session', ...
            'DatasetFilename', ...
            'IC' ...
        });

    if ~isempty(membershipTable)
        membershipTable = sortrows( ...
            membershipTable, ...
            {'ClusterIndex', 'Subject', 'DatasetIndex', 'IC'});
    end

    uniqueClusterIndices = unique( ...
        membershipTable.ClusterIndex, ...
        'stable');

    summaryClusterIndex = zeros(numel(uniqueClusterIndices), 1);
    summaryClusterName = strings(numel(uniqueClusterIndices), 1);
    summaryIsOutlier = false(numel(uniqueClusterIndices), 1);
    summaryComponentCount = zeros(numel(uniqueClusterIndices), 1);
    summaryDatasetCount = zeros(numel(uniqueClusterIndices), 1);
    summarySubjectCount = zeros(numel(uniqueClusterIndices), 1);
    summaryDuplicateSubject = false(numel(uniqueClusterIndices), 1);
    summarySubjectComposition = strings(numel(uniqueClusterIndices), 1);

    for i = 1:numel(uniqueClusterIndices)

        clusterIndex = uniqueClusterIndices(i);
        rows = membershipTable.ClusterIndex == clusterIndex;

        clusterSubjects = membershipTable.Subject(rows);
        uniqueSubjects = unique(clusterSubjects);

        subjectCountsText = strings(numel(uniqueSubjects), 1);
        hasDuplicateSubject = false;

        for j = 1:numel(uniqueSubjects)

            subjectCount = sum(clusterSubjects == uniqueSubjects(j));

            subjectCountsText(j) = ...
                uniqueSubjects(j) + ":" + string(subjectCount);

            if subjectCount > 1
                hasDuplicateSubject = true;
            end

        end

        summaryClusterIndex(i) = clusterIndex;
        summaryClusterName(i) = ...
            membershipTable.ClusterName(find(rows, 1, 'first'));
        summaryIsOutlier(i) = ...
            membershipTable.IsOutlierCluster(find(rows, 1, 'first'));
        summaryComponentCount(i) = sum(rows);
        summaryDatasetCount(i) = numel(unique( ...
            membershipTable.DatasetIndex(rows)));
        summarySubjectCount(i) = numel(uniqueSubjects);
        summaryDuplicateSubject(i) = hasDuplicateSubject;
        summarySubjectComposition(i) = ...
            strjoin(subjectCountsText, '; ');

    end

    summaryTable = table( ...
        summaryClusterIndex, ...
        summaryClusterName, ...
        summaryIsOutlier, ...
        summaryComponentCount, ...
        summaryDatasetCount, ...
        summarySubjectCount, ...
        summaryDuplicateSubject, ...
        summarySubjectComposition, ...
        'VariableNames', { ...
            'ClusterIndex', ...
            'ClusterName', ...
            'IsOutlierCluster', ...
            'ComponentCount', ...
            'DatasetCount', ...
            'UniqueSubjectCount', ...
            'ContainsMultipleICsFromSameSubject', ...
            'SubjectComposition' ...
        });

end


function [setVector, compVector] = ...
        flatten_cluster_members_local(setsValue, compsValue)

    setVector = [];
    compVector = [];

    if isnumeric(setsValue) && isnumeric(compsValue)

        setsFlat = double(setsValue(:));
        compsFlat = double(compsValue(:));

        n = min(numel(setsFlat), numel(compsFlat));

        setsFlat = setsFlat(1:n);
        compsFlat = compsFlat(1:n);

        valid = ...
            isfinite(setsFlat) & setsFlat > 0 & ...
            isfinite(compsFlat) & compsFlat > 0;

        setVector = setsFlat(valid);
        compVector = compsFlat(valid);
        return;

    end

    if iscell(setsValue) && iscell(compsValue)

        nCells = min(numel(setsValue), numel(compsValue));

        for i = 1:nCells

            currentSets = double(setsValue{i}(:));
            currentComps = double(compsValue{i}(:));

            if isempty(currentSets) || isempty(currentComps)
                continue;
            end

            if isscalar(currentSets) && numel(currentComps) > 1
                currentSets = repmat( ...
                    currentSets, ...
                    size(currentComps));
            end

            if isscalar(currentComps) && numel(currentSets) > 1
                currentComps = repmat( ...
                    currentComps, ...
                    size(currentSets));
            end

            n = min(numel(currentSets), numel(currentComps));

            currentSets = currentSets(1:n);
            currentComps = currentComps(1:n);

            valid = ...
                isfinite(currentSets) & currentSets > 0 & ...
                isfinite(currentComps) & currentComps > 0;

            setVector = [ ...
                setVector; ...
                currentSets(valid) ...
            ]; %#ok<AGROW>

            compVector = [ ...
                compVector; ...
                currentComps(valid) ...
            ]; %#ok<AGROW>

        end

        return;

    end

    error('Unsupported STUDY.cluster sets/comps data type.');

end


function output = scalar_to_string_local(value)

    if isempty(value)
        output = "";
        return;
    end

    if iscell(value)
        value = value{1};
    end

    output = string(value);

    if numel(output) > 1
        output = strjoin(output, '|');
    end

    if ismissing(output)
        output = "";
    end

end
