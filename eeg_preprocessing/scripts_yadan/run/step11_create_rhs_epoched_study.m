function step11_create_rhs_epoched_study()
% GOAL
%   Build the run-separated RHS EEGLAB STUDY used by ROI clustering and
%   time-warped ERSP analysis.
%
% INPUT
%   9_RHS-ERSP-run-separated/01_RHS_epoch_manifest.csv
%   Run-separated RHS epoched datasets from Step 10.
%   Current manual IC review workbook from Step 09.
%
% APPROACH
%   1. Read completed datasets and current manually accepted ICs.
%   2. Check ICA identity, selected dipoles, run metadata and timewarp once.
%   3. Reuse the current STUDY when its inputs and dataset entries match.
%   4. Otherwise build, verify and save the STUDY once.
%
% OUTPUT
%   9_RHS-ERSP-run-separated/02_RHS-epoched-STUDY/*
%
% USED BY
%   step12_rhs_roi_repeated_clustering.m

clc;

% SETTINGS AND PATHS

scriptsRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(scriptsRoot, '-begin');
addpath(fullfile(scriptsRoot, 'config'), '-begin');
P = project_paths();
cfg = config_step11_rhs_epoched_study();

rhsRoot = fullfile(P.outputFolder, cfg.rhsRootFolderName);
epochedSetRoot = fullfile(rhsRoot, cfg.epochedSetFolderName);
manifestFile = fullfile(rhsRoot, cfg.manifestFileName);
studyFolder = fullfile(rhsRoot, cfg.studyFolderName);
studyPath = fullfile(studyFolder, cfg.studyFilename);
assert(isfile(manifestFile), 'Manifest was not found: %s', manifestFile);

% READ STEP 10 MANIFEST

manifest = readtable(manifestFile, 'FileType', 'text', 'Delimiter', ',', ...
    'TextType', 'string', 'VariableNamingRule', 'preserve');
required = {'SubjectOrder', 'ConditionOrder', 'Subject', 'DatasetLabel', ...
    'ConditionCode', 'RunNumber', 'OutputSet', 'TimewarpAccepted', 'Status'};
missingFields = setdiff(required, manifest.Properties.VariableNames);
assert(isempty(missingFields), 'Manifest is missing: %s', ...
    strjoin(missingFields, ', '));

for field = {'Subject', 'DatasetLabel', 'ConditionCode', 'OutputSet', 'Status'}
    manifest.(field{1}) = string(manifest.(field{1}));
end
keep = startsWith(manifest.Status, "completed") | ...
    startsWith(manifest.Status, "reused");
manifest = manifest(keep, :);
assert(~isempty(manifest), 'No successful Step 10 datasets were found.');

for field = {'SubjectOrder', 'ConditionOrder', 'RunNumber', 'TimewarpAccepted'}
    manifest.(field{1}) = numeric_column_local(manifest.(field{1}));
end
manifest = sortrows(manifest, {'SubjectOrder', 'ConditionOrder', 'RunNumber'});

% READ CURRENT MANUAL SELECTIONS

reviewConfig = config_step05_09_eeg_preprocessing_ica(P);
[manifest, subjectSpecs] = current_manual_selection_local(manifest, ...
    fullfile(P.outputFolder, reviewConfig.manualICReview.workbookName), ...
    reviewConfig.manualICReview.sheetName);
assert(all(isfinite(manifest.SubjectOrder)) && ...
    all(isfinite(manifest.ConditionOrder)), 'Invalid subject/condition order.');
assert(all(isfinite(manifest.RunNumber) & manifest.RunNumber >= 1 & ...
    manifest.RunNumber == round(manifest.RunNumber)), 'Invalid run number.');
assert(all(isfinite(manifest.TimewarpAccepted) & manifest.TimewarpAccepted >= 1 & ...
    manifest.TimewarpAccepted == round(manifest.TimewarpAccepted)), ...
    'Invalid TimewarpAccepted count.');
[~, subjectIndex] = ismember(manifest.Subject, string({subjectSpecs.subject}));
nDatasets = height(manifest);

datasetKeys = manifest.Subject + "|" + manifest.ConditionCode + "|" + ...
    string(manifest.RunNumber);
assert(numel(unique(datasetKeys)) == nDatasets, ...
    'Duplicate subject/condition/run datasets were found.');

% RESOLVE INPUT .SET PATHS

setPaths = strings(nDatasets, 1);
for i = 1:nDatasets
    setPaths(i) = resolve_set_path_local(manifest.OutputSet(i), ...
        manifest.DatasetLabel(i), epochedSetRoot);
end
assert(numel(unique(lower(setPaths))) == nDatasets, ...
    'Duplicate .set paths were found.');

% START EEGLAB

assert(exist('eeglab', 'file') == 2, 'EEGLAB was not found.');
eeglab('nogui');
restoreRMS = suspend_ica_rms_local(); %#ok<NASGU>
pop_editoptions('option_storedisk', 1);

% CHECK EACH EPOCHED DATASET

% ICA signatures already cover weights, sphere and ICA channel order.
% Read each continuous source header only once during this Step 11 run.
sourceICACache = containers.Map('KeyType', 'char', 'ValueType', 'char');
referenceDipoles = cell(numel(subjectSpecs), 1);
manifest.SourceDatasetSignature = strings(nDatasets, 1);

for i = 1:nDatasets
    s = subjectIndex(i);
    spec = subjectSpecs(s);
    EEG = pop_loadset('filename', char(setPaths(i)), 'loadmode', 'info');
    dipoles = validate_epoched_dataset_local(EEG, manifest(i, :), ...
        spec, sourceICACache);

    if isempty(referenceDipoles{s})
        referenceDipoles{s} = dipoles;
    else
        assert(isequaln(referenceDipoles{s}, dipoles), ...
            'Selected DIPFIT coordinates differ across runs for %s: %s', ...
            char(spec.subject), char(setPaths(i)));
    end
    manifest.SourceDatasetSignature(i) = ...
        hipexo.eeglab_dataset_signature(setPaths(i));
end
clear EEG sourceICACache referenceDipoles;

% REUSE OR REBUILD EXISTING STUDY

% Preserve the previous signature format so this cleanup alone does not
% invalidate a matching STUDY. Paths remain relevant because STUDY stores them.
fields = {'Subject', 'DatasetLabel', 'ConditionCode', 'RunNumber', 'YesICs', ...
    'SourceDatasetSignature', 'ReviewICAIdentity'};
inputSignature = hipexo.content_signature(struct( ...
    'datasets', table2struct(manifest(:, fields)), 'paths', string(setPaths), ...
    'shared_ica_session', cfg.sharedICASession, 'group', cfg.groupLabel));

if ~cfg.forceRebuild && isfile(studyPath) && existing_study_is_current_local( ...
        studyPath, inputSignature, manifest, subjectSpecs, subjectIndex, cfg, setPaths)
    fprintf('No STUDY rebuild was required.\n');
    return;
end

% BUILD STUDY COMMANDS
% session = shared ICA identity; run = physical experimental run.

commands = cell(1, nDatasets);
for i = 1:nDatasets
    commands{i} = {'index', i, 'load', char(setPaths(i)), ...
        'subject', char(manifest.Subject(i)), ...
        'condition', char(manifest.ConditionCode(i)), ...
        'session', cfg.sharedICASession, 'run', manifest.RunNumber(i), ...
        'group', cfg.groupLabel, 'comps', subjectSpecs(subjectIndex(i)).yesICs};
end

% std_editset calls std_checkset internally. Supplying a filename here
% would also save early; save once below after our final verification.
[STUDY, ALLEEG] = std_editset([], [], 'name', cfg.studyName, ...
    'task', 'Hip-exoskeleton walking RHS gait-cycle analysis', ...
    'notes', ['Run-separated RHS epochs; one shared ICA session per subject; ' ...
        'physical run numbers; current manual Yes ICs; no ERSP precomputation.'], ...
    'commands', commands, 'updatedat', 'off', 'savedat', 'off');

% VERIFY FINAL STUDY STRUCTURE

verify_study_local(STUDY, manifest, subjectSpecs, subjectIndex, cfg, setPaths);

% REPRODUCIBILITY METADATA

buildInfo.version = char(cfg.processingVersion);
buildInfo.created_on = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
buildInfo.source_manifest = manifestFile;
buildInfo.input_signature = char(inputSignature);
buildInfo.total_datasets = nDatasets;
buildInfo.shared_ica_session = cfg.sharedICASession;
buildInfo.session_definition = ...
    'session = shared subject-level ICA decomposition identity; not physical experimental run';
buildInfo.physical_run_field = 'STUDY.datasetinfo.run';
buildInfo.subjects = cellstr(string({subjectSpecs.subject}));
buildInfo.yes_ic_lists = reshape({subjectSpecs.yesICs}, [], 1);
buildInfo.source_set_files_modified = false;
buildInfo.signal_timewarped = false;
buildInfo.ersp_precomputed = false;
buildInfo.next_step = 'six_fixed_ROI_repeated_clustering';
if ~isfield(STUDY, 'etc') || isempty(STUDY.etc), STUDY.etc = struct(); end
STUDY.etc.rhs_epoched_study = buildInfo;

% SAVE STUDY

if ~isfolder(studyFolder), mkdir(studyFolder); end
pop_savestudy(STUDY, ALLEEG, ...
    'filename', cfg.studyFilename, 'filepath', studyFolder);
assert(isfile(studyPath), 'STUDY file was not created: %s', studyPath);
fprintf('STUDY saved: %s (%d datasets, %d subjects).\n', ...
    studyPath, nDatasets, numel(subjectSpecs));

%% END OF STEP
end

% STEP-LOCAL FUNCTIONS

function values = numeric_column_local(values)
    if isnumeric(values) || islogical(values)
        values = double(values(:));
    else
        values = str2double(string(values(:)));
    end
end

function [M, specs] = current_manual_selection_local(M, workbook, sheet)
% Read each subject's Yes ICs once; keep numeric indices for all later use.
    R = readtable(workbook, 'Sheet', sheet, 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    required = {'Subject', 'Session', 'Dataset/File', 'IC', ...
        'ManualFinalDecision', 'ICAIdentity'};
    assert(all(ismember(required, R.Properties.VariableNames)), ...
        'Manual IC review lacks current ICA identity columns. Run Step09.');
    decision = upper(strtrim(string(R.ManualFinalDecision)));
    decision(ismissing(decision)) = "";
    assert(all(ismember(decision, ["", "YES", "NO", "REVIEW"])), ...
        'Unsupported manual IC decision.');
    R = R(decision == "YES", :);

    subjects = unique(M.Subject, 'stable');
    specs = repmat(struct('subject', "", 'yesICs', [], ...
        'reviewIdentity', "", 'reviewDatasetFile', ""), numel(subjects), 1);
    M.YesICs = strings(height(M), 1);
    M.ReviewICAIdentity = strings(height(M), 1);
    keepRows = false(height(M), 1);
    keepSubjects = false(numel(subjects), 1);

    for s = 1:numel(subjects)
        rows = M.Subject == subjects(s);
        selected = R(string(R.Subject) == subjects(s), :);
        if isempty(selected), continue; end

        labels = unique(strtrim(M.DatasetLabel(rows)));
        assert(~ismissing(subjects(s)) && strlength(strtrim(subjects(s))) > 0 && ...
            numel(labels) == 1 && ~ismissing(labels) && strlength(labels) > 0, ...
            'Each subject must have one valid shared-ICA DatasetLabel.');
        dataset = unique(string(selected.("Dataset/File")));
        session = unique(string(selected.Session));
        identity = unique(string(selected.ICAIdentity));
        assert(numel(dataset) == 1 && numel(session) == 1 && numel(identity) == 1 && ...
            ~ismissing(identity) && strlength(identity) > 0, ...
            'Subject %s has ambiguous or unidentified manual selections.', char(subjects(s)));
        ics = sort(numeric_column_local(selected.IC))';
        assert(all(isfinite(ics) & ics >= 1 & ics == round(ics)) && ...
            numel(unique(ics)) == numel(ics), ...
            'Invalid or duplicate manually selected ICs for %s.', char(subjects(s)));

        specs(s).subject = subjects(s);
        specs(s).yesICs = ics;
        specs(s).reviewIdentity = identity;
        specs(s).reviewDatasetFile = dataset;
        % These two manifest fields retain the existing reuse signature.
        M.YesICs(rows) = strjoin(string(ics), ' ');
        M.ReviewICAIdentity(rows) = identity;
        keepRows(rows) = true;
        keepSubjects(s) = true;
    end
    M = M(keepRows, :);
    specs = specs(keepSubjects);
    assert(~isempty(M), 'No subject has a current manual Yes selection for clustering.');
end

function setPath = resolve_set_path_local(manifestPath, datasetLabel, epochedSetRoot)
    if ~ismissing(manifestPath) && strlength(manifestPath) > 0 && isfile(manifestPath)
        setPath = manifestPath;
        return;
    end
    assert(~ismissing(manifestPath) && strlength(manifestPath) > 0, ...
        'OutputSet is empty for %s.', char(datasetLabel));
    % Retain the fallback for a project moved to another folder.
    [~, stem, ext] = fileparts(char(manifestPath));
    if isempty(ext), ext = '.set'; end
    setPath = string(fullfile(epochedSetRoot, char(datasetLabel), [stem ext]));
    assert(isfile(setPath), 'Dataset not found:\n%s\nFallback:\n%s', ...
        char(manifestPath), char(setPath));
end

function dipoles = validate_epoched_dataset_local(EEG, row, spec, sourceICACache)
    assert(EEG.trials == row.TimewarpAccepted, ...
        'Epoch count mismatch for %s: expected %d, found %d.', ...
        char(spec.subject), row.TimewarpAccepted, EEG.trials);
    assert(strcmpi(strtrim(string(EEG.subject)), row.Subject) && ...
        strcmpi(strtrim(string(EEG.condition)), row.ConditionCode), ...
        'Subject/condition mismatch: %s', char(row.OutputSet));
    assert(isfield(EEG, 'etc') && isfield(EEG.etc, 'rhs_epoching') && ...
        isfield(EEG.etc.rhs_epoching, 'source_set_path') && ...
        isfield(EEG.etc.rhs_epoching, 'run_number'), ...
        'Step10 source/run metadata are missing: %s', char(row.OutputSet));
    epochInfo = EEG.etc.rhs_epoching;
    assert(isequal(double(epochInfo.run_number), row.RunNumber), ...
        'Physical run mismatch: %s', char(row.OutputSet));

    % Continuous source, current review and every epoch must share one ICA.
    sourceSetPath = string(epochInfo.source_set_path);
    [sourceFolder, sourceName, sourceExtension] = fileparts(char(sourceSetPath));
    assert(strcmpi(string(sourceName) + string(sourceExtension), spec.reviewDatasetFile), ...
        'Manual review belongs to a different continuous source dataset: %s', ...
        char(spec.subject));
    sourceKey = char(sourceSetPath);
    if isKey(sourceICACache, sourceKey)
        sourceIdentity = string(sourceICACache(sourceKey));
    else
        assert(isfile(sourceSetPath), 'Continuous source dataset was not found: %s', sourceKey);
        source = pop_loadset('filename', [sourceName sourceExtension], ...
            'filepath', sourceFolder, 'loadmode', 'info');
        sourceIdentity = string(hipexo.ica_identity_signature(source));
        sourceICACache(sourceKey) = char(sourceIdentity);
    end
    assert(sourceIdentity == spec.reviewIdentity, ...
        ['Current manual selections do not match the continuous source ICA for %s.\n' ...
         'Update Step09 against the current Step08-approved dataset.'], char(spec.subject));
    epochIdentity = string(hipexo.ica_identity_signature(EEG));
    assert(epochIdentity == spec.reviewIdentity, ...
        ['Epoch ICA does not match the reviewed source ICA for %s:\n%s\n' ...
         'The review matches the source. Repair the Step10 ICA metadata for this subject; ' ...
         'do not redo the manual review.'], char(spec.subject), char(row.OutputSet));

    % The signature check above also validates the ICA matrix structure.
    nICs = size(EEG.icaweights, 1);
    assert(all(spec.yesICs <= nICs), 'Selected IC index exceeds %d for %s.', ...
        nICs, char(spec.subject));
    assert(isfield(EEG, 'dipfit') && isfield(EEG.dipfit, 'model') && ...
        numel(EEG.dipfit.model) >= nICs, 'DIPFIT model is missing/incomplete: %s', ...
        char(row.OutputSet));
    dipoles = cell(1, numel(spec.yesICs));
    for k = 1:numel(spec.yesICs)
        ic = spec.yesICs(k);
        model = EEG.dipfit.model(ic);
        assert(isfield(model, 'posxyz') && ~isempty(model.posxyz) && ...
            all(isfinite(double(model.posxyz(:)))), ...
            'Selected IC %d has no valid DIPFIT coordinate: %s', ic, char(row.OutputSet));
        dipoles{k} = double(model.posxyz);
    end

    % Five protocol landmarks: RHS, LTO, LHS, RTO, next RHS.
    assert(isfield(EEG, 'timewarp') && isfield(EEG.timewarp, 'latencies') && ...
        isfield(EEG.timewarp, 'warpto'), 'Timewarp metadata are missing: %s', char(row.OutputSet));
    latencies = double(EEG.timewarp.latencies);
    warpto = double(EEG.timewarp.warpto(:));
    assert(isequal(size(latencies), [EEG.trials, 5]) && numel(warpto) == 5, ...
        'Timewarp must contain five landmarks per epoch: %s', char(row.OutputSet));
    intervals = diff(latencies, 1, 2);
    assert(all(isfinite(latencies(:))) && all(intervals(:) > 0) && ...
        all(isfinite(warpto)) && all(diff(warpto) > 0), ...
        'Invalid RHS-LTO-LHS-RTO-nextRHS timewarp order: %s', char(row.OutputSet));
end

function canReuse = existing_study_is_current_local(studyPath, inputSignature, ...
        manifest, specs, subjectIndex, cfg, setPaths)
    canReuse = false;
    try
        % Retain short-name loading for long Windows project paths.
        [folder, name, ext] = fileparts(studyPath);
        originalFolder = pwd;
        restoreFolder = onCleanup(@() cd(originalFolder));
        cd(folder);
        saved = load([name ext], '-mat', 'STUDY');
        clear restoreFolder;
        if ~strcmp(string(saved.STUDY.etc.rhs_epoched_study.input_signature), ...
                string(inputSignature))
            return;
        end
        verify_study_local(saved.STUDY, manifest, specs, subjectIndex, cfg, setPaths);
        canReuse = true;
    catch ME
        fprintf('Existing STUDY cannot be reused: %s\n', ME.message);
    end
end

function verify_study_local(STUDY, manifest, specs, subjectIndex, cfg, setPaths)
    assert(isfield(STUDY, 'datasetinfo') && ...
        numel(STUDY.datasetinfo) == height(manifest), 'STUDY dataset count is incorrect.');
    for i = 1:height(manifest)
        info = STUDY.datasetinfo(i);
        assert(strcmp(string(info.subject), manifest.Subject(i)) && ...
            strcmp(string(info.condition), manifest.ConditionCode(i)), ...
            'STUDY dataset %d has an incorrect subject/condition.', i);
        assert(isequal(double(info.session), double(cfg.sharedICASession)) && ...
            isequal(double(info.run), manifest.RunNumber(i)) && ...
            strcmpi(string(info.group), string(cfg.groupLabel)), ...
            'STUDY dataset %d has an incorrect ICA session, physical run or group.', i);
        assert(isequal(sort(double(info.comps(:)')), specs(subjectIndex(i)).yesICs), ...
            'STUDY dataset %d does not match the current manual Yes ICs.', i);
        observedPath = string(fullfile(info.filepath, info.filename));
        assert(strcmpi(observedPath, setPaths(i)), ...
            'STUDY dataset %d points to a different .set file.', i);
    end
    assert(isfield(STUDY, 'cluster') && ~isempty(STUDY.cluster), ...
        'The STUDY parent component cluster was not created.');
end

function restoreRMS = suspend_ica_rms_local()
% Keep the reviewed ICA weights unchanged during EEGLAB load/check operations.
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
