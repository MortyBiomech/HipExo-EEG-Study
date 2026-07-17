% Goal:
% 1. Load the saved automatic K=6 spatial clustering STUDY.
% 2. Verify the exported membership CSV against the STUDY.
% 3. Create a member-level QC table for all 62 Yes ICs.
% 4. Export one QC image per IC:
%       - individual scalp map
%       - individual 3-30 Hz spectrum
%       - ICLabel, RV, dipole coordinates, and cluster information
% 5. Create an editable cluster-level review template.
%
% Important:
% - This script does NOT change cluster membership.
% - It does NOT remove ICs.
% - It does NOT call pop_subcomp.
% - It does NOT overwrite the automatic K=6 .study file.
% - ReviewerDecision, TargetCluster, and ReviewNotes are intentionally left
%   blank for manual review.
%
% Required input files:
%   output_data/9_group-STUDY/spatial_clustering_k06/
%       HipExo_manual_IC_Yes_only_spatial_clustered_k06.study
%       HipExo_IC_spatial_cluster_membership_k06.csv
%       HipExo_IC_spatial_cluster_summary_k06.csv
%
% Main outputs:
%   output_data/10_cluster-member-QC/k06/
%       HipExo_K06_member_QC_review.csv
%       HipExo_K06_cluster_review.csv
%       README_K06_member_QC.txt
%       Cls_02/
%           ... one PNG per IC
%       ...
%       Cls_07/
%
% Run:
%   review_k06_cluster_members_v2

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

kValue = 6;

studyFolder = fullfile( ...
    outputFolder, ...
    '9_group-STUDY', ...
    sprintf('spatial_clustering_k%02d', kValue));

studyFilename = sprintf( ...
    'HipExo_manual_IC_Yes_only_spatial_clustered_k%02d.study', ...
    kValue);

membershipFilename = sprintf( ...
    'HipExo_IC_spatial_cluster_membership_k%02d.csv', ...
    kValue);

summaryFilename = sprintf( ...
    'HipExo_IC_spatial_cluster_summary_k%02d.csv', ...
    kValue);

qcRoot = fullfile( ...
    outputFolder, ...
    '10_cluster-member-QC', ...
    sprintf('k%02d', kValue));

memberQCFile = fullfile( ...
    qcRoot, ...
    sprintf('HipExo_K%02d_member_QC_review.csv', kValue));

clusterReviewFile = fullfile( ...
    qcRoot, ...
    sprintf('HipExo_K%02d_cluster_review.csv', kValue));

readmeFile = fullfile( ...
    qcRoot, ...
    sprintf('README_K%02d_member_QC.txt', kValue));

% Spectrum displayed in each member QC image.
spectrumRangeHz = [3 30];

% PNG export resolution.
pngResolution = 180;

% Recreate PNG files that already exist.
overwriteExistingPNGs = false;

% Expected frozen K=6 content.
expectedDatasetCount = 21;
expectedMemberCount = 62;
expectedClusterIndices = 2:7;

%% ========================================================================
%  INITIALIZE EEGLAB
%  ========================================================================

if ~exist('pop_loadstudy', 'file')
    eeglab nogui;
end

studyPath = fullfile(studyFolder, studyFilename);
membershipPath = fullfile(studyFolder, membershipFilename);
summaryPath = fullfile(studyFolder, summaryFilename);

requiredFiles = string({studyPath, membershipPath, summaryPath});

for i = 1:numel(requiredFiles)
    if exist(requiredFiles(i), 'file') ~= 2
        error('Required input file was not found:\n%s', requiredFiles(i));
    end
end

if ~exist(qcRoot, 'dir')
    mkdir(qcRoot);
end

%% ========================================================================
%  LOAD K=6 STUDY AND CSV EXPORTS
%  ========================================================================

fprintf('\n============================================================\n');
fprintf('K=6 MEMBER-LEVEL QC STARTED\n');
fprintf('============================================================\n');
fprintf('STUDY:\n%s\n', studyPath);
fprintf('Membership CSV:\n%s\n', membershipPath);
fprintf('QC output:\n%s\n', qcRoot);
fprintf('============================================================\n\n');

[STUDY, ALLEEG] = pop_loadstudy( ...
    'filename', studyFilename, ...
    'filepath', studyFolder);

[STUDY, ALLEEG] = std_checkset(STUDY, ALLEEG);

membership = readtable( ...
    membershipPath, ...
    'TextType', 'string');

clusterSummary = readtable( ...
    summaryPath, ...
    'TextType', 'string');

requiredMembershipColumns = [ ...
    "ClusterIndex", ...
    "ClusterName", ...
    "IsOutlierCluster", ...
    "DatasetIndex", ...
    "Subject", ...
    "Condition", ...
    "Session", ...
    "DatasetFilename", ...
    "IC"];

missingColumns = setdiff( ...
    requiredMembershipColumns, ...
    string(membership.Properties.VariableNames));

if ~isempty(missingColumns)
    error('Membership CSV is missing columns: %s', ...
        strjoin(missingColumns, ', '));
end

membership = sortrows( ...
    membership, ...
    {'ClusterIndex', 'DatasetIndex', 'IC'});

%% ========================================================================
%  VERIFY SAVED RESULT
%  ========================================================================

if numel(STUDY.datasetinfo) ~= expectedDatasetCount
    error('Expected %d STUDY datasets, but found %d.', ...
        expectedDatasetCount, numel(STUDY.datasetinfo));
end

if height(membership) ~= expectedMemberCount
    error('Expected %d membership rows, but found %d.', ...
        expectedMemberCount, height(membership));
end

foundClusterIndices = unique(double(membership.ClusterIndex))';

if ~isequal(foundClusterIndices, expectedClusterIndices)
    error('Unexpected cluster indices. Expected %s, found %s.', ...
        mat2str(expectedClusterIndices), ...
        mat2str(foundClusterIndices));
end

pairKeys = string(membership.DatasetIndex) + "_" + string(membership.IC);

if numel(unique(pairKeys)) ~= height(membership)
    error(['Membership CSV contains duplicate DatasetIndex + IC pairs. ' ...
        'Each selected IC must occur exactly once.']);
end

for r = 1:height(membership)

    clusterIndex = double(membership.ClusterIndex(r));
    datasetIndex = double(membership.DatasetIndex(r));
    componentIndex = double(membership.IC(r));

    if clusterIndex < 1 || clusterIndex > numel(STUDY.cluster)
        error('Row %d contains invalid ClusterIndex %d.', ...
            r, clusterIndex);
    end

    if datasetIndex < 1 || datasetIndex > numel(ALLEEG)
        error('Row %d contains invalid DatasetIndex %d.', ...
            r, datasetIndex);
    end

    nICs = size(ALLEEG(datasetIndex).icaweights, 1);

    if componentIndex < 1 || componentIndex > nICs
        error(['Row %d contains invalid IC %d for dataset %d ' ...
            '(available ICs: %d).'], ...
            r, componentIndex, datasetIndex, nICs);
    end

    clusterSets = double(STUDY.cluster(clusterIndex).sets(:));
    clusterComps = double(STUDY.cluster(clusterIndex).comps(:));

    validPairs = isfinite(clusterSets) & ...
        isfinite(clusterComps) & ...
        clusterSets > 0 & ...
        clusterComps > 0;

    isStoredMember = any( ...
        clusterSets(validPairs) == datasetIndex & ...
        clusterComps(validPairs) == componentIndex);

    if ~isStoredMember
        error(['CSV/STUDY mismatch at row %d: Dataset %d IC%d is not ' ...
            'stored in STUDY.cluster(%d).'], ...
            r, datasetIndex, componentIndex, clusterIndex);
    end

end

fprintf('Saved result verified:\n');
fprintf('  Datasets: %d\n', numel(STUDY.datasetinfo));
fprintf('  Cluster members: %d\n', height(membership));
fprintf('  Clusters: %s\n\n', mat2str(expectedClusterIndices));

%% ========================================================================
%  INITIALIZE MEMBER-LEVEL QC TABLE
%  ========================================================================

nMembers = height(membership);

manualSelectionStatus = strings(nMembers, 1);

brainProbability = nan(nMembers, 1);
muscleProbability = nan(nMembers, 1);
eyeProbability = nan(nMembers, 1);
heartProbability = nan(nMembers, 1);
lineNoiseProbability = nan(nMembers, 1);
channelNoiseProbability = nan(nMembers, 1);
otherProbability = nan(nMembers, 1);

rvPercent = nan(nMembers, 1);
dipoleX = nan(nMembers, 1);
dipoleY = nan(nMembers, 1);
dipoleZ = nan(nMembers, 1);

sameDatasetMultiplicity = zeros(nMembers, 1);
distanceToClusterMean = nan(nMembers, 1);

qcImageRelativePath = strings(nMembers, 1);
reviewPriority = strings(nMembers, 1);

reviewerDecision = strings(nMembers, 1);
targetCluster = strings(nMembers, 1);
reviewNotes = strings(nMembers, 1);

%% ========================================================================
%  EXTRACT MEMBER METADATA
%  ========================================================================

fprintf('Extracting ICLabel, DIPFIT, RV, and selection metadata...\n');

for r = 1:nMembers

    clusterIndex = double(membership.ClusterIndex(r));
    datasetIndex = double(membership.DatasetIndex(r));
    componentIndex = double(membership.IC(r));

    EEG = ALLEEG(datasetIndex);

    % --------------------------------------------------------------------
    % Manual Yes/Review/No selection status
    % --------------------------------------------------------------------

    manualSelectionStatus(r) = ...
        get_manual_selection_status_local(EEG, componentIndex);

    % --------------------------------------------------------------------
    % ICLabel probabilities
    % --------------------------------------------------------------------

    probabilities = get_iclabel_probabilities_local( ...
        EEG, ...
        componentIndex);

    brainProbability(r) = probabilities(1);
    muscleProbability(r) = probabilities(2);
    eyeProbability(r) = probabilities(3);
    heartProbability(r) = probabilities(4);
    lineNoiseProbability(r) = probabilities(5);
    channelNoiseProbability(r) = probabilities(6);
    otherProbability(r) = probabilities(7);

    % --------------------------------------------------------------------
    % DIPFIT position and residual variance
    % --------------------------------------------------------------------

    [position, rvValue] = get_dipole_metadata_local( ...
        EEG, ...
        componentIndex);

    dipoleX(r) = position(1);
    dipoleY(r) = position(2);
    dipoleZ(r) = position(3);
    rvPercent(r) = rvValue * 100;

    % --------------------------------------------------------------------
    % Number of ICs from this same dataset in this same cluster
    % --------------------------------------------------------------------

    sameDatasetMultiplicity(r) = sum( ...
        double(membership.ClusterIndex) == clusterIndex & ...
        double(membership.DatasetIndex) == datasetIndex);

end

%% ========================================================================
%  COMPUTE DISTANCE TO EACH CLUSTER'S MEAN DIPOLE POSITION
%  ========================================================================

for clusterIndex = expectedClusterIndices

    rows = find(double(membership.ClusterIndex) == clusterIndex);

    coordinates = [ ...
        dipoleX(rows), ...
        dipoleY(rows), ...
        dipoleZ(rows)];

    validCoordinates = all(isfinite(coordinates), 2);

    if ~any(validCoordinates)
        continue;
    end

    clusterMean = mean( ...
        coordinates(validCoordinates, :), ...
        1, ...
        'omitnan');

    distances = sqrt(sum( ...
        (coordinates - clusterMean).^2, ...
        2));

    distanceToClusterMean(rows) = distances;

end

%% ========================================================================
%  CREATE REVIEW-PRIORITY FLAGS
%  ========================================================================

for r = 1:nMembers

    flags = strings(0, 1);

    if sameDatasetMultiplicity(r) > 1
        flags(end+1, 1) = "same dataset contributes multiple ICs";
    end

    if isfinite(rvPercent(r)) && rvPercent(r) > 15
        flags(end+1, 1) = "RV > 15%";
    end

    if isfinite(brainProbability(r)) && brainProbability(r) < 80
        flags(end+1, 1) = "Brain < 80%";
    end

    if isempty(flags)
        reviewPriority(r) = "standard review";
    else
        reviewPriority(r) = strjoin(flags, "; ");
    end

end

%% ========================================================================
%  EXPORT ONE QC IMAGE PER IC
%  ========================================================================

fprintf('Creating one scalp-map/spectrum QC image per IC...\n');

for r = 1:nMembers

    clusterIndex = double(membership.ClusterIndex(r));
    datasetIndex = double(membership.DatasetIndex(r));
    componentIndex = double(membership.IC(r));

    EEG = ALLEEG(datasetIndex);

    clusterFolderName = sprintf('Cls_%02d', clusterIndex);
    clusterFolder = fullfile(qcRoot, clusterFolderName);

    if ~exist(clusterFolder, 'dir')
        mkdir(clusterFolder);
    end

    subjectLabel = sanitize_filename_local( ...
        char(membership.Subject(r)));

    conditionLabel = sanitize_filename_local( ...
        char(membership.Condition(r)));

    qcImageFilename = sprintf( ...
        'D%02d_%s_%s_IC%03d.png', ...
        datasetIndex, ...
        subjectLabel, ...
        conditionLabel, ...
        componentIndex);

    qcImagePath = fullfile(clusterFolder, qcImageFilename);

    qcImageRelativePath(r) = string(fullfile( ...
        clusterFolderName, ...
        qcImageFilename));

    if exist(qcImagePath, 'file') == 2 && ...
            ~overwriteExistingPNGs

        fprintf('  Reusing existing image %d/%d: %s\n', ...
            r, nMembers, qcImageFilename);
        continue;

    end

    fprintf('  Creating image %d/%d: %s\n', ...
        r, nMembers, qcImageFilename);

    create_member_qc_figure_local( ...
        EEG, ...
        componentIndex, ...
        clusterIndex, ...
        datasetIndex, ...
        membership.Subject(r), ...
        membership.Condition(r), ...
        manualSelectionStatus(r), ...
        [ ...
            brainProbability(r), ...
            muscleProbability(r), ...
            eyeProbability(r), ...
            heartProbability(r), ...
            lineNoiseProbability(r), ...
            channelNoiseProbability(r), ...
            otherProbability(r)], ...
        rvPercent(r), ...
        [dipoleX(r), dipoleY(r), dipoleZ(r)], ...
        distanceToClusterMean(r), ...
        sameDatasetMultiplicity(r), ...
        spectrumRangeHz, ...
        qcImagePath, ...
        pngResolution);

end

%% ========================================================================
%  WRITE MEMBER-LEVEL REVIEW TABLE
%  ========================================================================

memberQC = membership;

memberQC.ManualSelectionStatus = manualSelectionStatus;

memberQC.Brain_percent = brainProbability;
memberQC.Muscle_percent = muscleProbability;
memberQC.Eye_percent = eyeProbability;
memberQC.Heart_percent = heartProbability;
memberQC.LineNoise_percent = lineNoiseProbability;
memberQC.ChannelNoise_percent = channelNoiseProbability;
memberQC.Other_percent = otherProbability;

memberQC.RV_percent = rvPercent;
memberQC.DipoleX = dipoleX;
memberQC.DipoleY = dipoleY;
memberQC.DipoleZ = dipoleZ;
memberQC.DistanceToClusterMean = distanceToClusterMean;

memberQC.SameDatasetMultiplicityInCluster = ...
    sameDatasetMultiplicity;

memberQC.ReviewPriority = reviewPriority;
memberQC.QCImage = qcImageRelativePath;

memberQC.ReviewerDecision = reviewerDecision;
memberQC.TargetCluster = targetCluster;
memberQC.ReviewNotes = reviewNotes;

writetable(memberQC, memberQCFile);

%% ========================================================================
%  CREATE CLUSTER-LEVEL REVIEW TEMPLATE
%  ========================================================================

clusterReview = build_cluster_review_table_local( ...
    clusterSummary);

writetable(clusterReview, clusterReviewFile);

%% ========================================================================
%  WRITE README
%  ========================================================================

write_readme_local( ...
    readmeFile, ...
    studyPath, ...
    memberQCFile, ...
    clusterReviewFile, ...
    spectrumRangeHz);

%% ========================================================================
%  FINAL REPORT
%  ========================================================================

fprintf('\n============================================================\n');
fprintf('K=6 MEMBER-LEVEL QC COMPLETED\n');
fprintf('============================================================\n');
fprintf('Member review table:\n%s\n', memberQCFile);
fprintf('Cluster review table:\n%s\n', clusterReviewFile);
fprintf('QC image root:\n%s\n', qcRoot);
fprintf('README:\n%s\n', readmeFile);
fprintf('\nNo cluster membership was changed.\n');
fprintf('The automatic K=6 STUDY was not overwritten.\n');
fprintf('============================================================\n');

%% ========================================================================
%  LOCAL FUNCTIONS
%  ========================================================================

function status = get_manual_selection_status_local( ...
        EEG, ...
        componentIndex)

    status = "Unknown";

    if ~isfield(EEG, 'etc') || ...
            ~isfield(EEG.etc, 'manual_ic_selection')
        return;
    end

    info = EEG.etc.manual_ic_selection;

    if isfield(info, 'yes_ic') && ...
            ismember(componentIndex, double(info.yes_ic(:)))
        status = "Yes";
        return;
    end

    if isfield(info, 'review_ic') && ...
            ismember(componentIndex, double(info.review_ic(:)))
        status = "Review";
        return;
    end

    if isfield(info, 'no_ic') && ...
            ismember(componentIndex, double(info.no_ic(:)))
        status = "No";
        return;
    end

    status = "Unlisted";

end

function probabilitiesPercent = ...
        get_iclabel_probabilities_local( ...
            EEG, ...
            componentIndex)

    probabilitiesPercent = nan(1, 7);

    if ~isfield(EEG, 'etc') || ...
            ~isfield(EEG.etc, 'ic_classification') || ...
            ~isfield(EEG.etc.ic_classification, 'ICLabel') || ...
            ~isfield( ...
                EEG.etc.ic_classification.ICLabel, ...
                'classifications')

        return;
    end

    classifications = double( ...
        EEG.etc.ic_classification.ICLabel.classifications);

    if componentIndex > size(classifications, 1) || ...
            size(classifications, 2) < 7
        return;
    end

    probabilitiesPercent = ...
        classifications(componentIndex, 1:7) * 100;

end

function [position, rvValue] = ...
        get_dipole_metadata_local( ...
            EEG, ...
            componentIndex)

    position = nan(1, 3);
    rvValue = nan;

    if ~isfield(EEG, 'dipfit') || ...
            ~isfield(EEG.dipfit, 'model') || ...
            componentIndex > numel(EEG.dipfit.model)
        return;
    end

    model = EEG.dipfit.model(componentIndex);

    if isfield(model, 'posxyz') && ...
            ~isempty(model.posxyz)

        posxyz = double(model.posxyz);

        if size(posxyz, 2) == 3
            position = mean(posxyz, 1, 'omitnan');
        end

    end

    if isfield(model, 'rv') && ...
            ~isempty(model.rv)
        rvValue = double(model.rv(1));
    end

end

function create_member_qc_figure_local( ...
        EEG, ...
        componentIndex, ...
        clusterIndex, ...
        datasetIndex, ...
        subjectLabel, ...
        conditionLabel, ...
        manualStatus, ...
        probabilitiesPercent, ...
        rvPercent, ...
        dipolePosition, ...
        distanceToClusterMean, ...
        sameDatasetMultiplicity, ...
        spectrumRangeHz, ...
        outputPath, ...
        pngResolution)

    fig = figure( ...
        'Visible', 'off', ...
        'Color', 'w', ...
        'Position', [100 100 1300 650]);

    % Use ordinary subplot axes. topoplot changes axes position
    % internally, which causes repeated warnings inside tiledlayout.
    % --------------------------------------------------------------------
    % Scalp map
    % --------------------------------------------------------------------

    ax1 = subplot(1, 2, 1, 'Parent', fig);

    [map, channelLocations] = ...
        get_component_map_and_chanlocs_local( ...
            EEG, ...
            componentIndex);

    axes(ax1); %#ok<LAXES>

    topoplot( ...
        map, ...
        channelLocations, ...
        'electrodes', 'off', ...
        'numcontour', 6);

    axis(ax1, 'square');

    title(ax1, ...
        sprintf('Scalp map: IC%d', componentIndex), ...
        'Interpreter', 'none', ...
        'FontWeight', 'bold');

    % --------------------------------------------------------------------
    % Spectrum
    % --------------------------------------------------------------------

    ax2 = subplot(1, 2, 2, 'Parent', fig);

    activation = get_component_activation_local( ...
        EEG, ...
        componentIndex);

    [spectrumDb, frequencies] = spectopo( ...
        activation, ...
        0, ...
        EEG.srate, ...
        'plot', 'off');

    spectrumDb = double(spectrumDb(:));
    frequencies = double(frequencies(:));

    frequencyMask = ...
        frequencies >= spectrumRangeHz(1) & ...
        frequencies <= spectrumRangeHz(2);

    plot( ...
        ax2, ...
        frequencies(frequencyMask), ...
        spectrumDb(frequencyMask), ...
        'LineWidth', 1.2);

    grid(ax2, 'on');

    xlabel(ax2, 'Frequency (Hz)');
    ylabel(ax2, 'Power (dB)');

    xlim(ax2, spectrumRangeHz);

    title(ax2, ...
        sprintf('Individual spectrum: %.0f-%.0f Hz', ...
            spectrumRangeHz(1), spectrumRangeHz(2)), ...
        'FontWeight', 'bold');

    % --------------------------------------------------------------------
    % Figure-level information
    % --------------------------------------------------------------------

    probabilityText = sprintf([ ...
        'Brain %.1f%% | Muscle %.1f%% | Eye %.1f%% | ' ...
        'Heart %.1f%% | Line %.1f%% | Channel %.1f%% | Other %.1f%%'], ...
        probabilitiesPercent(1), ...
        probabilitiesPercent(2), ...
        probabilitiesPercent(3), ...
        probabilitiesPercent(4), ...
        probabilitiesPercent(5), ...
        probabilitiesPercent(6), ...
        probabilitiesPercent(7));

    metadataText = sprintf([ ...
        'Cls %d | Dataset %d | %s | %s | IC%d | Manual=%s\n' ...
        'RV %.2f%% | Dipole [%.1f %.1f %.1f] | ' ...
        'Distance to cluster mean %.1f | ' ...
        'Same-dataset multiplicity %d\n%s'], ...
        clusterIndex, ...
        datasetIndex, ...
        char(subjectLabel), ...
        char(conditionLabel), ...
        componentIndex, ...
        char(manualStatus), ...
        rvPercent, ...
        dipolePosition(1), ...
        dipolePosition(2), ...
        dipolePosition(3), ...
        distanceToClusterMean, ...
        sameDatasetMultiplicity, ...
        probabilityText);

    figure(fig);
    sgtitle( ...
        metadataText, ...
        'Interpreter', 'none', ...
        'FontSize', 11, ...
        'FontWeight', 'bold');

    exportgraphics( ...
        fig, ...
        outputPath, ...
        'Resolution', pngResolution);

    close(fig);

end

function [map, channelLocations] = ...
        get_component_map_and_chanlocs_local( ...
            EEG, ...
            componentIndex)

    if isempty(EEG.icawinv)
        error('Dataset %s has no ICA inverse weights.', EEG.setname);
    end

    map = double(EEG.icawinv(:, componentIndex));

    if isfield(EEG, 'icachansind') && ...
            ~isempty(EEG.icachansind) && ...
            numel(EEG.icachansind) == numel(map)

        channelLocations = EEG.chanlocs(EEG.icachansind);

    elseif numel(EEG.chanlocs) == numel(map)

        channelLocations = EEG.chanlocs;

    else

        error(['Cannot match IC scalp-map rows to channel locations for ' ...
            'dataset %s, IC%d.'], ...
            EEG.setname, componentIndex);

    end

end

function activation = ...
        get_component_activation_local( ...
            EEG, ...
            componentIndex)

    if isempty(EEG.icaweights) || isempty(EEG.icasphere)
        error('Dataset %s has no valid ICA decomposition.', EEG.setname);
    end

    nComponents = size(EEG.icaweights, 1);

    if componentIndex < 1 || componentIndex > nComponents
        error('IC%d exceeds the %d ICA components in dataset %s.', ...
            componentIndex, nComponents, EEG.setname);
    end

    % STUDY loading often leaves EEG.icaact empty. Calculate only the
    % requested IC directly from the stored decomposition instead of
    % depending on EEG.icaact:
    %
    % activation = icaweights * icasphere * ICA-channel data
    %
    % Reload the .set only when EEG.data is not currently numeric.
    if ~isnumeric(EEG.data) || isempty(EEG.data)

        if isempty(EEG.filename) || isempty(EEG.filepath)
            error(['Dataset %s has no numeric EEG.data and has no usable ' ...
                'filename/filepath for reloading.'], EEG.setname);
        end

        EEG = pop_loadset( ...
            'filename', EEG.filename, ...
            'filepath', EEG.filepath, ...
            'loadmode', 'all');

        if ~isnumeric(EEG.data) || isempty(EEG.data)
            error('Could not load numeric EEG.data for dataset %s.', ...
                EEG.setname);
        end

    end

    unmixingMatrix = double(EEG.icaweights) * double(EEG.icasphere);
    unmixingRow = unmixingMatrix(componentIndex, :);

    if isfield(EEG, 'icachansind') && ~isempty(EEG.icachansind)
        icaChannelIndices = double(EEG.icachansind(:))';
    else
        icaChannelIndices = 1:size(unmixingMatrix, 2);
    end

    if numel(icaChannelIndices) ~= size(unmixingMatrix, 2)
        error(['ICA channel mismatch in dataset %s: the unmixing matrix ' ...
            'expects %d channels, but icachansind contains %d.'], ...
            EEG.setname, size(unmixingMatrix, 2), ...
            numel(icaChannelIndices));
    end

    if any(icaChannelIndices < 1) || ...
            any(icaChannelIndices > size(EEG.data, 1))
        error('Invalid icachansind values in dataset %s.', EEG.setname);
    end

    componentData = reshape( ...
        EEG.data(icaChannelIndices, :, :), ...
        numel(icaChannelIndices), ...
        []);

    if isa(componentData, 'single')
        activation = single(unmixingRow) * componentData;
        activation = double(activation);
    else
        activation = unmixingRow * double(componentData);
    end

    activation = double(activation(:)');
    activation = activation(isfinite(activation));

    if isempty(activation)
        error('IC%d activation is empty in dataset %s.', ...
            componentIndex, EEG.setname);
    end

end

function safeName = sanitize_filename_local(inputText)

    safeName = regexprep( ...
        char(string(inputText)), ...
        '[^A-Za-z0-9_-]', ...
        '_');

    if isempty(safeName)
        safeName = 'unknown';
    end

end

function clusterReview = ...
        build_cluster_review_table_local(clusterSummary)

    clusterReview = clusterSummary;

    nClusters = height(clusterReview);

    preliminarySpatialLabel = strings(nClusters, 1);
    currentStatus = strings(nClusters, 1);
    keyIssue = strings(nClusters, 1);

    finalClusterName = strings(nClusters, 1);
    finalDecision = strings(nClusters, 1);
    reviewNotes = strings(nClusters, 1);

    for r = 1:nClusters

        clusterIndex = double(clusterReview.ClusterIndex(r));

        switch clusterIndex

            case 2
                preliminarySpatialLabel(r) = ...
                    "posterior midline / occipital";
                currentStatus(r) = ...
                    "Primary candidate";
                keyIssue(r) = ...
                    "One dataset contributes two ICs; inspect possible source splitting";

            case 3
                preliminarySpatialLabel(r) = ...
                    "central / centro-parietal";
                currentStatus(r) = ...
                    "Secondary candidate";
                keyIssue(r) = ...
                    "Small cluster and absent in Pilot2p2";

            case 4
                preliminarySpatialLabel(r) = ...
                    "frontal-midline";
                currentStatus(r) = ...
                    "Review";
                keyIssue(r) = ...
                    "Spatially dispersed and dominated by Pilot2p1";

            case 5
                preliminarySpatialLabel(r) = ...
                    "posterior parietal / centro-parietal";
                currentStatus(r) = ...
                    "Primary candidate";
                keyIssue(r) = ...
                    "Moderate dipole dispersion and repeated datasets";

            case 6
                preliminarySpatialLabel(r) = ...
                    "right posterior temporal / occipito-temporal";
                currentStatus(r) = ...
                    "Caution";
                keyIssue(r) = ...
                    "Peripheral-looking scalp map, limited coverage, absent in Pilot2p3";

            case 7
                preliminarySpatialLabel(r) = ...
                    "posterior / centro-parietal";
                currentStatus(r) = ...
                    "Subject-dominant";
                keyIssue(r) = ...
                    "14 of 15 ICs come from Pilot2p3";

            otherwise
                preliminarySpatialLabel(r) = "unreviewed";
                currentStatus(r) = "unreviewed";
                keyIssue(r) = "";
        end

    end

    clusterReview.PreliminarySpatialLabel = ...
        preliminarySpatialLabel;

    clusterReview.CurrentStatus = currentStatus;
    clusterReview.KeyIssue = keyIssue;

    clusterReview.FinalClusterName = finalClusterName;
    clusterReview.FinalDecision = finalDecision;
    clusterReview.ReviewNotes = reviewNotes;

end

function write_readme_local( ...
        readmeFile, ...
        studyPath, ...
        memberQCFile, ...
        clusterReviewFile, ...
        spectrumRangeHz)

    fileID = fopen(readmeFile, 'w');

    if fileID < 0
        error('Could not create README file:\n%s', readmeFile);
    end

    cleanupObject = onCleanup(@() fclose(fileID)); %#ok<NASGU>

    fprintf(fileID, 'K=6 member-level QC outputs\n');
    fprintf(fileID, '============================\n\n');

    fprintf(fileID, 'Automatic baseline STUDY:\n%s\n\n', studyPath);

    fprintf(fileID, 'Member-level review table:\n%s\n\n', ...
        memberQCFile);

    fprintf(fileID, 'Cluster-level review table:\n%s\n\n', ...
        clusterReviewFile);

    fprintf(fileID, ['Each PNG corresponds to exactly one IC and contains ' ...
        'its scalp map and %.0f-%.0f Hz spectrum.\n\n'], ...
        spectrumRangeHz(1), spectrumRangeHz(2));

    fprintf(fileID, ['Fill ReviewerDecision, TargetCluster, and ' ...
        'ReviewNotes only after inspecting the PNG and metadata.\n\n']);

    fprintf(fileID, 'Suggested ReviewerDecision values:\n');
    fprintf(fileID, '  Keep\n');
    fprintf(fileID, '  Reassign\n');
    fprintf(fileID, '  ClusterOutlier\n');
    fprintf(fileID, '  NeedsDiscussion\n\n');

    fprintf(fileID, ['TargetCluster is needed only when ' ...
        'ReviewerDecision = Reassign.\n\n']);

    fprintf(fileID, ['This QC step does not modify the .study file, ' ...
        'cluster membership, or EEG signals.\n']);

end
