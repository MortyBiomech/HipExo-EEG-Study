% GOAL
%   Build the run-separated RHS EEGLAB STUDY used by ROI clustering and
%   time-warped ERSP analysis.
%
% INPUT
%   9_RHS-ERSP-run-separated/01_RHS_epoch_manifest.csv
%   Run-separated RHS epoched datasets from Step 10.
%
% APPROACH
%   1. Read all completed datasets from the Step 10 manifest.
%   2. Verify dataset identity, shared ICA metadata, selected ICs, DIPFIT,
%      condition/run metadata, and timewarp matrices.
%   3. Build one EEGLAB STUDY while preserving one shared ICA identity per
%      subject and the physical run number for each dataset.
%   4. Verify STUDY.datasetinfo.comps against the manifest.
%
% OUTPUT
%   9_RHS-ERSP-run-separated/02_RHS-epoched-STUDY/*
%
% USED BY
%   step12_run_rhs_roi_repeated_clustering.m

clear;
clc;


% SETTINGS AND PATHS

runFolder = fileparts(mfilename('fullpath'));
scriptsRoot = fileparts(runFolder);

addpath(scriptsRoot, '-begin');
addpath(fullfile(scriptsRoot, 'config'), '-begin');

P = project_paths();
cfg = config_step11_rhs_epoched_study();

processingVersion = cfg.processingVersion;

studyName = cfg.studyName;
studyFilename = cfg.studyFilename;
groupLabel = cfg.groupLabel;

sharedICASession = cfg.sharedICASession;
forceRebuild = cfg.forceRebuild;

conditionOrder = cfg.conditionOrder;

outputFolder = P.outputFolder;
eeglabFolder = P.eeglabFolder;

% START EEGLAB

if exist('eeglab', 'file') ~= 2

    error( ...
        'EEGLAB was not found after running project_paths.m.');

end


[ALLEEG, EEG, CURRENTSET, ALLCOM] = ...
    eeglab('nogui'); %#ok<ASGLU>


% Keep large STUDY datasets on disk as much as possible.
pop_editoptions( ...
    'option_storedisk', 1);


% INPUT / OUTPUT PATHS

rhsRoot = fullfile( ...
    outputFolder, ...
    cfg.rhsRootFolderName);


epochedSetRoot = fullfile( ...
    rhsRoot, ...
    cfg.epochedSetFolderName);


manifestFile = fullfile( ...
    rhsRoot, ...
    cfg.manifestFileName);


studyFolder = fullfile( ...
    rhsRoot, ...
    cfg.studyFolderName);


studyPath = fullfile( ...
    studyFolder, ...
    studyFilename);


if exist(manifestFile, 'file') ~= 2

    error( ...
        'Manifest was not found:\n%s', ...
        manifestFile);

end


if exist(epochedSetRoot, 'dir') ~= 7

    error( ...
        'Epoched dataset folder was not found:\n%s', ...
        epochedSetRoot);

end


if exist(studyFolder, 'dir') ~= 7

    mkdir(studyFolder);

end


% EXISTING STUDY PROTECTION

if exist(studyPath, 'file') == 2

    if ~forceRebuild

        error([ ...
            'The STUDY already exists:\n%s\n\n' ...
            'If you intentionally want to rebuild it, set:\n' ...
            '    forceRebuild = true;'], ...
            studyPath);

    end


    fprintf('Replacing existing STUDY: %s\n', studyPath);

    delete(studyPath);

end


% READ RHS EPOCH MANIFEST
%
% IMPORTANT:
% Explicit CSV parsing + BOM cleaning.
% Build a stable subject-order index from the current manifest.


% ------------------------------------------------
% Force comma-separated parsing.
% ------------------------------------------------

opts = detectImportOptions( ...
    manifestFile, ...
    'Delimiter', ',');


opts.VariableNamingRule = ...
    'preserve';


% Read text columns consistently.
manifest = readtable( ...
    manifestFile, ...
    opts);


%% ------------------------------------------------
% Clean header names
% ------------------------------------------------

variableNames = ...
    string(manifest.Properties.VariableNames);

variableNames = ...
    strtrim(variableNames);


% UTF-8 BOM
for k = 1:numel(variableNames)

    thisName = char(variableNames(k));

    % Normal Unicode BOM
    thisName(thisName == char(65279)) = [];

    % Possible decoded UTF-8 BOM
    thisName = strrep( ...
        thisName, ...
        'ï»¿', ...
        '');

    variableNames(k) = ...
        string(strtrim(thisName));

end


manifest.Properties.VariableNames = ...
    cellstr(variableNames);


if width(manifest) <= 1

    error([ ...
        'The CSV was not parsed correctly.\n' ...
        'Only %d column was detected.\n' ...
        'Expected comma-separated columns.\n\n' ...
        'Manifest:\n%s'], ...
        width(manifest), ...
        manifestFile);

end


% REQUIRED CORE FIELDS
%
% SubjectOrder and ConditionOrder are NOT mandatory here because
% they can be reconstructed if necessary.

requiredCoreFields = { ...
    'Subject', ...
    'DatasetLabel', ...
    'ConditionCode', ...
    'RunNumber', ...
    'OutputSet', ...
    'TimewarpAccepted', ...
    'YesICCount', ...
    'YesICs', ...
    'Status'};


missingFields = strings(0, 1);


for k = 1:numel(requiredCoreFields)

    if ~ismember( ...
            requiredCoreFields{k}, ...
            manifest.Properties.VariableNames)

        missingFields(end + 1, 1) = ...
            string(requiredCoreFields{k}); %#ok<AGROW>

    end

end


if ~isempty(missingFields)

    error([ ...
        'Manifest is missing required core field(s):\n' ...
        '  %s\n\n' ...
        'Actual columns MATLAB read:\n' ...
        '  %s\n\n' ...
        'Manifest:\n%s'], ...
        char(strjoin(missingFields, ', ')), ...
        char(strjoin( ...
            string(manifest.Properties.VariableNames), ...
            ', ')), ...
        manifestFile);

end


% NORMALIZE TEXT COLUMNS

manifest.Subject = ...
    string(manifest.Subject);

manifest.DatasetLabel = ...
    string(manifest.DatasetLabel);

manifest.ConditionCode = ...
    string(manifest.ConditionCode);

manifest.OutputSet = ...
    string(manifest.OutputSet);

manifest.YesICs = ...
    string(manifest.YesICs);

manifest.Status = ...
    string(manifest.Status);


if ismember( ...
        'ProcessingVersion', ...
        manifest.Properties.VariableNames)

    manifest.ProcessingVersion = ...
        string(manifest.ProcessingVersion);

end


% RECONSTRUCT SubjectOrder IF NECESSARY

if ~ismember( ...
        'SubjectOrder', ...
        manifest.Properties.VariableNames)

    warning([ ...
        'SubjectOrder was not available after CSV parsing. ' ...
        'Reconstructing it dynamically from the manifest.']);

    subjectListForOrder = unique( ...
        manifest.Subject, ...
        'stable');

    SubjectOrder = nan(height(manifest), 1);

    for s = 1:numel(subjectListForOrder)
        SubjectOrder(manifest.Subject == subjectListForOrder(s)) = s;
    end

    if any(~isfinite(SubjectOrder))
        error('Could not reconstruct SubjectOrder from the manifest.');
    end

    manifest = addvars( ...
        manifest, ...
        SubjectOrder, ...
        'Before', 1, ...
        'NewVariableNames', ...
        'SubjectOrder');

end


% RECONSTRUCT ConditionOrder IF NECESSARY

if ~ismember( ...
        'ConditionOrder', ...
        manifest.Properties.VariableNames)

    warning([ ...
        'ConditionOrder was not available after CSV parsing. ' ...
        'Reconstructing it from conditionOrder.']);


    ConditionOrder = ...
        nan(height(manifest), 1);


    for c = 1:numel(conditionOrder)

        mask = ...
            manifest.ConditionCode == ...
            conditionOrder(c);

        ConditionOrder(mask) = c;

    end


    if any(~isfinite(ConditionOrder))

        badConditions = unique( ...
            manifest.ConditionCode( ...
                ~isfinite(ConditionOrder)));

        error( ...
            'Unknown condition(s): %s', ...
            char(strjoin( ...
                badConditions, ...
                ', ')));

    end


    manifest = addvars( ...
        manifest, ...
        ConditionOrder, ...
        'After', ...
        'SubjectOrder', ...
        'NewVariableNames', ...
        'ConditionOrder');

end




% KEEP ONLY SUCCESSFUL FINAL OUTPUTS

statusText = ...
    string(manifest.Status);


keepMask = ...
    startsWith(statusText, "completed") | ...
    startsWith(statusText, "reused");


manifest = ...
    manifest(keepMask, :);


manifest = sortrows( ...
    manifest, ...
    {'SubjectOrder', ...
     'ConditionOrder', ...
     'RunNumber'});


fprintf('Successful run-separated datasets: %d\n', height(manifest));


if isempty(manifest)

    error([ ...
        'The RHS epoch manifest contains no successful datasets. ' ...
        'Run Step 11 successfully before creating the STUDY.']);

end


% DERIVE SUBJECT / YES-IC STRUCTURE FROM CURRENT MANIFEST

subjectSpecs = subject_specs_from_rhs_manifest_local(manifest);

for s = 1:numel(subjectSpecs)

    spec = subjectSpecs(s);
    rows = manifest.Subject == spec.subject;

    observedConditionRuns = ...
        manifest.ConditionCode(rows) + "|" + ...
        string(manifest.RunNumber(rows));

    if numel(unique(observedConditionRuns)) ~= numel(observedConditionRuns)
        error([ ...
            'Duplicate condition/run datasets were found for %s. ' ...
            'Each physical condition/run may appear only once.'], ...
            char(spec.subject));
    end

    observedConditions = unique(manifest.ConditionCode(rows), 'stable');
    protocolMissing = setdiff(conditionOrder, observedConditions, 'stable');

    if ~isempty(protocolMissing)
        fprintf('  protocol conditions not present in current data: %s\n', ...
            char(strjoin(protocolMissing, ', ')));
    end

end


% RESOLVE INPUT .SET PATHS

nDatasets = ...
    height(manifest);


setPaths = ...
    strings(nDatasets, 1);


for i = 1:nDatasets

    setPaths(i) = ...
        resolve_set_path_local( ...
            manifest.OutputSet(i), ...
            manifest.DatasetLabel(i), ...
            epochedSetRoot);


    if exist(char(setPaths(i)), 'file') ~= 2

        error( ...
            'Dataset not found:\n%s', ...
            char(setPaths(i)));

    end

end


if numel(unique(lower(setPaths))) ~= ...
        nDatasets

    error( ...
        'Duplicate .set paths were found.');

end


% PREFLIGHT CHECK EACH EPOCHED DATASET

fprintf('Preflight checking %d epoched datasets.\n', nDatasets);


EEGinfo = ...
    cell(nDatasets, 1);


sourceBytes = ...
    zeros(nDatasets, 1);

sourceDateNum = ...
    zeros(nDatasets, 1);


for i = 1:nDatasets

    subject = ...
        string(manifest.Subject(i));

    condition = ...
        string(manifest.ConditionCode(i));

    physicalRun = ...
        double(manifest.RunNumber(i));


    specIndex = ...
        find_subject_spec_local( ...
            subjectSpecs, ...
            subject);


    spec = ...
        subjectSpecs(specIndex);

    fprintf('  %d/%d: %s | %s | run %d\n', ...
        i, nDatasets, char(subject), char(condition), physicalRun);


    EEGtmp = pop_loadset( ...
        'filename', ...
        char(setPaths(i)), ...
        'loadmode', ...
        'info');


    validate_epoched_dataset_local( ...
        EEGtmp, ...
        subject, ...
        condition, ...
        physicalRun, ...
        spec.yesICs);


    EEGinfo{i} = ...
        EEGtmp;


    fileInfo = ...
        dir(char(setPaths(i)));


    sourceBytes(i) = ...
        fileInfo.bytes;

    sourceDateNum(i) = ...
        fileInfo.datenum;

end


% VERIFY SHARED SUBJECT-LEVEL ICA
%
% All run-separated datasets belonging to one subject MUST have
% identical ICA weights/sphere/channel indices.


for s = 1:numel(subjectSpecs)

    spec = ...
        subjectSpecs(s);


    rows = find( ...
        manifest.Subject == spec.subject);


    referenceIndex = ...
        rows(1);


    EEGref = ...
        EEGinfo{referenceIndex};



    for j = 2:numel(rows)

        currentIndex = ...
            rows(j);


        assert_same_ica_local( ...
            EEGref, ...
            EEGinfo{currentIndex}, ...
            spec.yesICs, ...
            spec.subject, ...
            setPaths(referenceIndex), ...
            setPaths(currentIndex));

    end


    fprintf('  Shared ICA verified: %s (%d datasets).\n', ...
        char(spec.subject), numel(rows));

end


% BUILD std_editset COMMANDS
%
% session = shared ICA identity
% run     = physical experiment run
% comps   = fixed final Yes ICs


commands = ...
    cell(1, nDatasets);


for i = 1:nDatasets

    subject = ...
        string(manifest.Subject(i));

    condition = ...
        string(manifest.ConditionCode(i));

    physicalRun = ...
        double(manifest.RunNumber(i));


    specIndex = ...
        find_subject_spec_local( ...
            subjectSpecs, ...
            subject);


    yesICs = ...
        subjectSpecs(specIndex).yesICs;


    commands{i} = { ...
        'index', i, ...
        'load', char(setPaths(i)), ...
        'subject', char(subject), ...
        'condition', char(condition), ...
        'session', sharedICASession, ...
        'run', physicalRun, ...
        'group', groupLabel, ...
        'comps', yesICs};

end


STUDY = [];
ALLEEG = [];


studyNotes = [ ...
    'RHS gait-cycle run-separated epoched STUDY. ' ...
    'All run-separated datasets belonging to the same participant ' ...
    'inherit one subject-level AMICA decomposition. ' ...
    'Session denotes ICA decomposition identity. ' ...
    'Run denotes physical experimental run. ' ...
    'Only final manually accepted Yes ICs are selected for clustering. ' ...
    'No ERSP has been precomputed at this stage.'];


[STUDY, ALLEEG] = std_editset( ...
    STUDY, ...
    ALLEEG, ...
    'name', studyName, ...
    'task', ...
        'Hip-exoskeleton walking RHS gait-cycle analysis', ...
    'filename', studyFilename, ...
    'filepath', studyFolder, ...
    'notes', studyNotes, ...
    'commands', commands, ...
    'updatedat', 'off', ...
    'savedat', 'off');


% MAKE ALLEEG METADATA CONSISTENT IN MEMORY
%
% No source .set is saved here.

for i = 1:nDatasets

    subject = ...
        string(manifest.Subject(i));

    condition = ...
        string(manifest.ConditionCode(i));

    physicalRun = ...
        double(manifest.RunNumber(i));


    ALLEEG(i).subject = ...
        char(subject);

    ALLEEG(i).condition = ...
        char(condition);

    ALLEEG(i).session = ...
        sharedICASession;

    ALLEEG(i).run = ...
        physicalRun;

    ALLEEG(i).group = ...
        groupLabel;

end


% STUDY CONSISTENCY CHECK

[STUDY, ALLEEG] = ...
    std_checkset( ...
        STUDY, ...
        ALLEEG);


% VERIFY FINAL STUDY STRUCTURE

verify_study_local( ...
    STUDY, ...
    manifest, ...
    subjectSpecs, ...
    sharedICASession, ...
    groupLabel);


% REPRODUCIBILITY METADATA

if ~isfield(STUDY, 'etc') || ...
        isempty(STUDY.etc)

    STUDY.etc = struct();

end


buildInfo = struct();


buildInfo.version = ...
    char(processingVersion);


buildInfo.created_on = ...
    char(datetime( ...
        'now', ...
        'Format', ...
        'yyyy-MM-dd HH:mm:ss'));


buildInfo.source_manifest = ...
    manifestFile;


buildInfo.total_datasets = ...
    nDatasets;


buildInfo.shared_ica_session = ...
    sharedICASession;


buildInfo.session_definition = ...
    ['session = shared subject-level ICA decomposition identity; ' ...
     'not physical experimental run'];


buildInfo.physical_run_field = ...
    'STUDY.datasetinfo.run';


buildInfo.subjects = ...
    cellstr(string({subjectSpecs.subject}));


buildInfo.yes_ic_lists = ...
    arrayfun( ...
        @(spec) double(spec.yesICs(:)'), ...
        subjectSpecs, ...
        'UniformOutput', false);


buildInfo.source_set_files_modified = ...
    false;


buildInfo.signal_timewarped = ...
    false;


buildInfo.ersp_precomputed = ...
    false;


buildInfo.next_step = ...
    'six_fixed_ROI_repeated_clustering';


STUDY.etc.rhs_epoched_study = ...
    buildInfo;


% SAVE STUDY


STUDY = pop_savestudy( ...
    STUDY, ...
    ALLEEG, ...
    'filename', ...
    studyFilename, ...
    'filepath', ...
    studyFolder);


if exist(studyPath, 'file') ~= 2

    error( ...
        'STUDY file was not created:\n%s', ...
        studyPath);

end


% VERIFY SOURCE .SET FILES WERE NOT MODIFIED

for i = 1:nDatasets

    afterInfo = ...
        dir(char(setPaths(i)));


    if afterInfo.bytes ~= sourceBytes(i) || ...
            afterInfo.datenum ~= sourceDateNum(i)

        error([ ...
            'A source .set file unexpectedly changed:\n%s'], ...
            char(setPaths(i)));

    end

end


% RELOAD SAVED STUDY AND VERIFY


[STUDYcheck, ALLEEGcheck] = ...
    pop_loadstudy( ...
        'filename', ...
        studyFilename, ...
        'filepath', ...
        studyFolder); %#ok<ASGLU>


verify_study_local( ...
    STUDYcheck, ...
    manifest, ...
    subjectSpecs, ...
    sharedICASession, ...
    groupLabel);


% FINAL REPORT

fprintf('RHS epoched STUDY created: %s | datasets=%d | subjects=%d\n', ...
    studyPath, ...
    numel(STUDYcheck.datasetinfo), ...
    numel(unique(string({STUDYcheck.datasetinfo.subject}))));


% LOCAL FUNCTIONS


function subjectSpecs = subject_specs_from_rhs_manifest_local(manifest)

    requiredColumns = { ...
        'Subject', ...
        'DatasetLabel', ...
        'ConditionCode', ...
        'RunNumber', ...
        'YesICCount', ...
        'YesICs'};

    for c = 1:numel(requiredColumns)
        if ~ismember(requiredColumns{c}, manifest.Properties.VariableNames)
            error('RHS manifest is missing required column: %s', ...
                requiredColumns{c});
        end
    end

    subjects = unique(string(manifest.Subject), 'stable');
    subjects = subjects(strlength(strtrim(subjects)) > 0);

    if isempty(subjects)
        error('RHS manifest contains no valid Subject values.');
    end

    subjectSpecs = repmat(struct( ...
        'subject', "", ...
        'datasetLabel', "", ...
        'yesICs', []), ...
        numel(subjects), 1);

    for s = 1:numel(subjects)

        subject = subjects(s);
        rows = find(string(manifest.Subject) == subject);

        datasetLabels = unique( ...
            strtrim(string(manifest.DatasetLabel(rows))), ...
            'stable');
        datasetLabels = datasetLabels(strlength(datasetLabels) > 0);

        if numel(datasetLabels) ~= 1
            error([ ...
                '%s must map to exactly one shared-ICA DatasetLabel in ' ...
                'the RHS manifest; found %d.'], ...
                char(subject), numel(datasetLabels));
        end

        referenceYes = [];

        for r = rows(:)'

            yesICs = parse_ic_list_local(manifest.YesICs(r));
            reportedCount = scalar_numeric_local(manifest.YesICCount(r));

            if ~isfinite(reportedCount) || reportedCount < 1 || ...
                    reportedCount ~= round(reportedCount)
                error('%s has an invalid YesICCount in manifest row %d.', ...
                    char(subject), r);
            end

            if numel(yesICs) ~= reportedCount
                error([ ...
                    '%s manifest row %d reports YesICCount=%d but ' ...
                    'contains %d Yes IC indices.'], ...
                    char(subject), r, reportedCount, numel(yesICs));
            end

            if isempty(referenceYes)
                referenceYes = yesICs(:)';
            elseif ~isequal(sort(referenceYes), sort(yesICs(:)'))
                error([ ...
                    'Yes-IC lists differ across run-separated datasets ' ...
                    'for %s. Shared-ICA analysis requires one identical ' ...
                    'current list per subject.'], ...
                    char(subject));
            end

            runNumber = scalar_numeric_local(manifest.RunNumber(r));
            if ~isfinite(runNumber) || runNumber < 1 || ...
                    runNumber ~= round(runNumber)
                error('%s has invalid run number in manifest row %d.', ...
                    char(subject), r);
            end
        end

        subjectSpecs(s).subject = subject;
        subjectSpecs(s).datasetLabel = datasetLabels(1);
        subjectSpecs(s).yesICs = referenceYes;
    end
end


function icList = parse_ic_list_local(value)

    textValue = strtrim(string(value));

    if ismissing(textValue) || strlength(textValue) == 0
        icList = zeros(1, 0);
        return;
    end

    textValue = regexprep(textValue, '[,;\[\]\(\)]', ' ');
    tokens = regexp(char(textValue), '[-+]?\d+', 'match');

    if isempty(tokens)
        icList = zeros(1, 0);
        return;
    end

    icList = str2double(tokens);
    icList = icList(:)';

    if any(~isfinite(icList) | icList < 1 | ...
            icList ~= round(icList))
        error('Invalid IC list in RHS manifest: %s', textValue);
    end

    if numel(unique(icList)) ~= numel(icList)
        error('Duplicate IC index in RHS manifest: %s', textValue);
    end
end


function setPath = resolve_set_path_local( ...
        manifestPath, ...
        datasetLabel, ...
        epochedSetRoot)


    manifestPath = ...
        string(manifestPath);


    % First use exact path recorded by epoch manifest.
    if strlength(manifestPath) > 0 && ...
            exist(char(manifestPath), 'file') == 2

        setPath = ...
            manifestPath;

        return;

    end


    % Fallback using current project output root.
    [~, stem, ext] = ...
        fileparts(char(manifestPath));


    if isempty(ext)

        ext = '.set';

    end


    if isempty(stem)

        error([ ...
            'OutputSet is empty in manifest for dataset %s.'], ...
            char(datasetLabel));

    end


    candidate = fullfile( ...
        epochedSetRoot, ...
        char(datasetLabel), ...
        [stem ext]);


    if exist(candidate, 'file') ~= 2

        error([ ...
            'Could not resolve dataset path.\n\n' ...
            'Manifest path:\n%s\n\n' ...
            'Fallback path:\n%s'], ...
            char(manifestPath), ...
            candidate);

    end


    setPath = ...
        string(candidate);

end


function specIndex = find_subject_spec_local( ...
        subjectSpecs, ...
        subject)


    subjects = ...
        string({subjectSpecs.subject});


    specIndex = ...
        find(subjects == string(subject));


    if numel(specIndex) ~= 1

        error( ...
            'Could not uniquely identify subject: %s', ...
            char(string(subject)));

    end

end


function validate_epoched_dataset_local( ...
        EEG, ...
        expectedSubject, ...
        expectedCondition, ...
        expectedRun, ...
        expectedYesICs)


    %% ------------------------------------------------------------
    % Epoch structure
    % ------------------------------------------------------------

    if EEG.trials < 2

        error( ...
            'Expected epoched data with >1 trial.');

    end


    %% ------------------------------------------------------------
    % Sampling rate
    % ------------------------------------------------------------

    if abs(double(EEG.srate) - 500) > 1e-6

        error( ...
            'Expected 500 Hz, found %.12g Hz.', ...
            EEG.srate);

    end


    %% ------------------------------------------------------------
    % Subject
    % ------------------------------------------------------------

    if ~strcmpi( ...
            strtrim(string(EEG.subject)), ...
            string(expectedSubject))

        error( ...
            'Unexpected EEG.subject: %s', ...
            char(string(EEG.subject)));

    end


    %% ------------------------------------------------------------
    % Condition
    % ------------------------------------------------------------

    if ~strcmpi( ...
            strtrim(string(EEG.condition)), ...
            string(expectedCondition))

        error( ...
            'Unexpected EEG.condition: %s', ...
            char(string(EEG.condition)));

    end


    %% ------------------------------------------------------------
    % ICA
    % ------------------------------------------------------------

    if isempty(EEG.icaweights) || ...
            isempty(EEG.icasphere)

        error( ...
            'ICA decomposition is missing.');

    end


    nICs = ...
        size(EEG.icaweights, 1);


    if any(expectedYesICs < 1) || ...
            any(expectedYesICs > nICs)

        error([ ...
            'At least one selected Yes IC is outside ' ...
            'the valid range 1:%d.'], ...
            nICs);

    end


    %% ------------------------------------------------------------
    % DIPFIT
    % ------------------------------------------------------------

    if ~isfield(EEG, 'dipfit') || ...
            ~isfield(EEG.dipfit, 'model') || ...
            numel(EEG.dipfit.model) < nICs

        error( ...
            'DIPFIT model is missing/incomplete.');

    end


    %% ------------------------------------------------------------
    % Yes IC provenance from RHS epoching
    % ------------------------------------------------------------

    if ~isfield(EEG, 'etc') || ...
            ~isfield(EEG.etc, 'rhs_epoching') || ...
            ~isfield(EEG.etc.rhs_epoching, 'original_yes_ic')

        error('EEG.etc.rhs_epoching.original_yes_ic is missing.');

    end

    storedYes = ...
        double(EEG.etc.rhs_epoching.original_yes_ic(:))';

    if ~isequal( ...
            sort(storedYes), ...
            sort(double(expectedYesICs(:))'))

        error([ ...
            'The Yes IC list stored in the RHS dataset does not match ' ...
            'the current RHS epoch manifest.']);

    end


    %% ------------------------------------------------------------
    % Selected IC dipoles
    % ------------------------------------------------------------

    for ic = expectedYesICs(:)'

        model = ...
            EEG.dipfit.model(ic);


        if ~isfield(model, 'posxyz') || ...
                isempty(model.posxyz) || ...
                any(~isfinite( ...
                    double(model.posxyz(:))))

            error( ...
                'Selected IC %d has no valid DIPFIT coordinate.', ...
                ic);

        end

    end


    %% ------------------------------------------------------------
    % RHS epoch metadata
    % ------------------------------------------------------------

    if ~isfield(EEG.etc, 'rhs_epoching')

        error( ...
            'EEG.etc.rhs_epoching is missing.');

    end


    if ~isfield( ...
            EEG.etc.rhs_epoching, ...
            'run_number')

        error( ...
            'EEG.etc.rhs_epoching.run_number is missing.');

    end


    storedRun = ...
        double( ...
            EEG.etc.rhs_epoching.run_number);


    if storedRun ~= double(expectedRun)

        error( ...
            'Run mismatch: expected %d, found %.12g.', ...
            expectedRun, ...
            storedRun);

    end


    %% ------------------------------------------------------------
    % Timewarp
    % ------------------------------------------------------------

    if ~isfield(EEG, 'timewarp') || ...
            ~isfield( ...
                EEG.timewarp, ...
                'latencies') || ...
            ~isfield( ...
                EEG.timewarp, ...
                'warpto')

        error( ...
            'EEG.timewarp is missing/incomplete.');

    end


    latencyMatrix = ...
        double(EEG.timewarp.latencies);


    if size(latencyMatrix, 1) ~= EEG.trials

        error([ ...
            'Timewarp rows (%d) do not match EEG.trials (%d).'], ...
            size(latencyMatrix, 1), ...
            EEG.trials);

    end


    if size(latencyMatrix, 2) ~= 5

        error( ...
            'Expected five gait landmarks per epoch.');

    end


    if numel(EEG.timewarp.warpto) ~= 5

        error( ...
            'Expected five EEG.timewarp.warpto values.');

    end


    if any(~isfinite(latencyMatrix(:)))

        error( ...
            'EEG.timewarp.latencies contains NaN/Inf.');

    end


    latencyDiff = ...
        diff(latencyMatrix, 1, 2);


    if any(latencyDiff(:) <= 0)

        error([ ...
            'One or more epochs violate ' ...
            'RHS-LTO-LHS-RTO-nextRHS order.']);

    end

end


function assert_same_ica_local( ...
        EEGref, ...
        EEGtest, ...
        selectedICs, ...
        subject, ...
        referenceFile, ...
        testFile)


    tolerance = 1e-10;


    assert_numeric_equal_local( ...
        EEGref.icaweights, ...
        EEGtest.icaweights, ...
        tolerance, ...
        'icaweights', ...
        subject, ...
        referenceFile, ...
        testFile);


    assert_numeric_equal_local( ...
        EEGref.icasphere, ...
        EEGtest.icasphere, ...
        tolerance, ...
        'icasphere', ...
        subject, ...
        referenceFile, ...
        testFile);


    if ~isequal( ...
            double(EEGref.icachansind(:)), ...
            double(EEGtest.icachansind(:)))

        error([ ...
            'icachansind differs between datasets for %s.\n\n' ...
            'Reference:\n%s\n\n' ...
            'Test:\n%s'], ...
            char(subject), ...
            char(referenceFile), ...
            char(testFile));

    end


    for ic = selectedICs(:)'

        refPos = ...
            double( ...
                EEGref.dipfit.model(ic).posxyz);

        testPos = ...
            double( ...
                EEGtest.dipfit.model(ic).posxyz);


        if ~isequaln(refPos, testPos)

            error([ ...
                'DIPFIT coordinate differs for IC %d of %s.\n\n' ...
                'Reference:\n%s\n\n' ...
                'Test:\n%s'], ...
                ic, ...
                char(subject), ...
                char(referenceFile), ...
                char(testFile));

        end

    end

end


function assert_numeric_equal_local( ...
        A, ...
        B, ...
        tolerance, ...
        fieldName, ...
        subject, ...
        referenceFile, ...
        testFile)


    if ~isequal(size(A), size(B))

        error([ ...
            '%s dimensions differ for %s.\n\n' ...
            'Reference:\n%s\n\n' ...
            'Test:\n%s'], ...
            fieldName, ...
            char(subject), ...
            char(referenceFile), ...
            char(testFile));

    end


    A = double(A);
    B = double(B);


    difference = ...
        max(abs(A(:) - B(:)));


    if isempty(difference)

        difference = 0;

    end


    if ~isfinite(difference) || ...
            difference > tolerance

        error([ ...
            '%s differs between run-separated datasets for %s.\n' ...
            'Maximum absolute difference = %.16g\n\n' ...
            'Reference:\n%s\n\n' ...
            'Test:\n%s'], ...
            fieldName, ...
            char(subject), ...
            difference, ...
            char(referenceFile), ...
            char(testFile));

    end

end


function verify_study_local( ...
        STUDY, ...
        manifest, ...
        subjectSpecs, ...
        sharedICASession, ...
        groupLabel)


    nDatasets = ...
        height(manifest);


    if ~isfield(STUDY, 'datasetinfo')

        error( ...
            'STUDY.datasetinfo is missing.');

    end


    if numel(STUDY.datasetinfo) ~= ...
            nDatasets

        error( ...
            'STUDY contains %d datasets; expected %d.', ...
            numel(STUDY.datasetinfo), ...
            nDatasets);

    end


    for i = 1:nDatasets

        info = ...
            STUDY.datasetinfo(i);


        expectedSubject = ...
            string(manifest.Subject(i));


        expectedCondition = ...
            string(manifest.ConditionCode(i));


        expectedRun = ...
            double(manifest.RunNumber(i));


        specIndex = ...
            find_subject_spec_local( ...
                subjectSpecs, ...
                expectedSubject);


        expectedComps = ...
            subjectSpecs(specIndex).yesICs;


        %% Subject

        if string(info.subject) ~= ...
                expectedSubject

            error( ...
                'Dataset %d has wrong subject.', ...
                i);

        end


        %% Condition

        if string(info.condition) ~= ...
                expectedCondition

            error( ...
                'Dataset %d has wrong condition.', ...
                i);

        end


        %% Shared ICA session

        if isempty(info.session) || ...
                double(info.session) ~= ...
                sharedICASession

            error( ...
                'Dataset %d does not use ICA session %d.', ...
                i, ...
                sharedICASession);

        end


        %% Physical run

        if ~isfield(info, 'run') || ...
                isempty(info.run) || ...
                double(info.run) ~= expectedRun

            error( ...
                'Dataset %d has incorrect physical run.', ...
                i);

        end


        %% Group

        if ~strcmpi( ...
                string(info.group), ...
                string(groupLabel))

            error( ...
                'Dataset %d has incorrect group.', ...
                i);

        end


        %% Component selection

        if ~isfield(info, 'comps') || ...
                isempty(info.comps)

            error( ...
                'Dataset %d has empty comps.', ...
                i);

        end


        observedComps = ...
            double(info.comps(:))';


        if ~isequal( ...
                sort(observedComps), ...
                sort(double(expectedComps(:))'))

            error([ ...
                'Dataset %d comps do not match ' ...
                'the current manifest-derived Yes IC list.'], ...
                i);

        end

    end


    %% ------------------------------------------------------------
    % One ICA session per subject
    % ------------------------------------------------------------

    for s = 1:numel(subjectSpecs)

        subject = ...
            subjectSpecs(s).subject;


        rows = find( ...
            string({STUDY.datasetinfo.subject}) == ...
            subject);


        sessions = ...
            double([ ...
                STUDY.datasetinfo(rows).session]);


        if numel(unique(sessions)) ~= 1 || ...
                unique(sessions) ~= ...
                sharedICASession

            error( ...
                '%s does not have one shared ICA session.', ...
                char(subject));

        end


        for r = rows

            observed = ...
                double( ...
                    STUDY.datasetinfo(r).comps(:))';


            expected = ...
                double( ...
                    subjectSpecs(s).yesICs(:))';


            if ~isequal( ...
                    sort(observed), ...
                    sort(expected))

                error( ...
                    '%s has inconsistent selected ICs.', ...
                    char(subject));

            end

        end

    end


    if ~isfield(STUDY, 'cluster') || ...
            isempty(STUDY.cluster)

        error([ ...
            'The STUDY parent component cluster ' ...
            'was not created.']);

    end

end


function value = scalar_numeric_local(raw)


    value = NaN;


    if isempty(raw)

        return;

    end


    if isnumeric(raw) && ...
            isscalar(raw)

        value = ...
            double(raw);

        return;

    end


    parsed = ...
        str2double(string(raw));


    if isscalar(parsed) && ...
            isfinite(parsed)

        value = ...
            parsed;

    end

end
