% GOAL
%   Build a continuous subject-level EEGLAB STUDY for manual ROI
%   determination using the ICs marked Yes in the current review workbook.
% INPUT
%   output_data/manual_IC_selection_final.xlsx
%   subject_level_EEG_table.csv
%   Step 08 ICA-QC-approved preprocessed_and_ICA datasets.
% APPROACH
%   1. Read the current manual IC decisions.
%   2. Resolve one continuous preprocessed_and_ICA dataset per subject.
%   3. Verify ICA QC, AMICA provenance, and selected IC indices.
%   4. Build a STUDY whose datasetinfo.comps contains each subject's Yes ICs.
% OUTPUT
%   output_data/ROI_determination/HipExo_manual_IC_Yes_only.study
%   output_data/ROI_determination/ROI_determination_dataset_manifest.csv
% USED BY
%   Manual ROI determination in EEGLAB.

clear;
clc;
close all;

%% Paths

roiScriptFolder = fileparts(mfilename('fullpath'));
scriptsRoot = fileparts(roiScriptFolder);

addpath(scriptsRoot, '-begin');
addpath(fullfile(scriptsRoot, 'config'), '-begin');

P = project_paths();
bemobil_config = config_step05_09_eeg_preprocessing_ica(P);

outputFolder = P.outputFolder;
mappingFile = P.subjectLevelEEGTableFile;

manualICWorkbook = fullfile( ...
    outputFolder, ...
    bemobil_config.manualICReview.workbookName);

manualICSheetName = bemobil_config.manualICReview.sheetName;

studyOutputFolder = fullfile(outputFolder, 'ROI_determination');
studyName = 'HipExo_manual_IC_Yes_only';
studyFilename = [studyName '.study'];
studyManifestFile = fullfile( ...
    studyOutputFolder, ...
    'ROI_determination_dataset_manifest.csv');

if ~exist(studyOutputFolder, 'dir')
    mkdir(studyOutputFolder);
end

%% Read current Yes-IC selections

subjectSpecs = load_manual_subject_specs_local( ...
    manualICWorkbook, ...
    manualICSheetName, ...
    mappingFile);

fprintf('\n============================================================\n');
fprintf('ROI DETERMINATION STUDY\n');
fprintf('============================================================\n');
fprintf('Manual IC workbook:\n%s\n', manualICWorkbook);
fprintf('Datasets with at least one Yes IC: %d\n', numel(subjectSpecs));
fprintf('============================================================\n\n');

%% Initialize EEGLAB

if exist('eeglab', 'file') ~= 2
    error('EEGLAB is not available on the MATLAB path.');
end

if exist('pop_loadset', 'file') ~= 2
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

%% Verify datasets and build STUDY commands

nDatasets = numel(subjectSpecs);
commands = cell(1, nDatasets);

DatasetIndex = (1:nDatasets)';
Subject = strings(nDatasets, 1);
Session = strings(nDatasets, 1);
SourceSetPath = strings(nDatasets, 1);
YesICs = strings(nDatasets, 1);
YesCount = zeros(nDatasets, 1);

for d = 1:nDatasets

    spec = subjectSpecs(d);
    setPath = char(spec.sourceSet);

    [setFolder, setName, setExt] = fileparts(setPath);

    EEGinfo = pop_loadset( ...
        'filename', [setName setExt], ...
        'filepath', setFolder, ...
        'loadmode', 'info');

    verify_source_local( ...
        EEGinfo, ...
        spec.subject, ...
        spec.yesICs, ...
        spec.amicaInputSignature);

    commands{d} = { ...
        'index', d, ...
        'load', setPath, ...
        'subject', char(spec.subject), ...
        'session', 1, ...
        'condition', 'AllConditions', ...
        'comps', spec.yesICs ...
    };

    Subject(d) = spec.subject;
    Session(d) = spec.session;
    SourceSetPath(d) = spec.sourceSet;
    YesICs(d) = strjoin(string(spec.yesICs), ' ');
    YesCount(d) = numel(spec.yesICs);

    fprintf('%s | Yes ICs: %s\n', ...
        spec.subject, YesICs(d));
end

%% Build STUDY

STUDY = [];
ALLEEG = [];

studyNotes = [ ...
    'Continuous subject-level STUDY for ROI determination. ' ...
    'Only ICs marked Yes are designated in STUDY.datasetinfo.comps. ' ...
    'No ICA component is removed from the source datasets.'];

[STUDY, ALLEEG] = std_editset( ...
    STUDY, ...
    ALLEEG, ...
    'name', studyName, ...
    'task', 'HipExo EEG ROI determination', ...
    'notes', studyNotes, ...
    'filename', studyFilename, ...
    'filepath', studyOutputFolder, ...
    'commands', commands, ...
    'updatedat', 'off', ...
    'rmclust', 'on', ...
    'savedat', 'off');

[STUDY, ALLEEG] = std_checkset(STUDY, ALLEEG);

if numel(STUDY.datasetinfo) ~= nDatasets
    error('STUDY dataset count does not match the current input datasets.');
end

for d = 1:nDatasets

    expectedYes = subjectSpecs(d).yesICs;
    actualYes = double(STUDY.datasetinfo(d).comps(:))';

    if isempty(actualYes)
        error(['STUDY.datasetinfo(%d).comps is empty. ' ...
            'EEGLAB would interpret this as all components.'], d);
    end

    if ~isequal(sort(actualYes), sort(double(expectedYes(:))'))
        error('STUDY component list mismatch for %s.', ...
            subjectSpecs(d).subject);
    end
end

if ~isfield(STUDY, 'etc') || isempty(STUDY.etc)
    STUDY.etc = struct();
end

STUDY.etc.roi_determination = struct();
STUDY.etc.roi_determination.created_on = char(datetime( ...
    'now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
STUDY.etc.roi_determination.manual_ic_review_file = manualICWorkbook;
STUDY.etc.roi_determination.dataset_count = nDatasets;
STUDY.etc.roi_determination.subject_count = ...
    numel(unique(Subject));
STUDY.etc.roi_determination.total_yes_ic_count = sum(YesCount);

[STUDY, ALLEEG] = pop_savestudy( ...
    STUDY, ...
    ALLEEG, ...
    'filename', studyFilename, ...
    'filepath', studyOutputFolder);

%% Save manifest

roiManifest = table( ...
    DatasetIndex, ...
    Subject, ...
    Session, ...
    SourceSetPath, ...
    YesICs, ...
    YesCount);

writetable(roiManifest, studyManifestFile);

fprintf('\n============================================================\n');
fprintf('ROI DETERMINATION STUDY CREATED\n');
fprintf('============================================================\n');
fprintf('STUDY:\n%s\n', fullfile(studyOutputFolder, studyFilename));
fprintf('Manifest:\n%s\n', studyManifestFile);
fprintf('Datasets: %d\n', nDatasets);
fprintf('Subjects: %d\n', numel(unique(Subject)));
fprintf('Total Yes ICs: %d\n', sum(YesCount));
fprintf('============================================================\n');

%% Local functions

function subjectSpecs = load_manual_subject_specs_local( ...
        workbookFile, sheetName, mappingFile)

    if exist(workbookFile, 'file') ~= 2
        error('Manual IC review workbook was not found:\n%s', workbookFile);
    end

    if exist(mappingFile, 'file') ~= 2
        error('Subject-level processing table was not found:\n%s', ...
            mappingFile);
    end

    workbookCells = readcell(workbookFile, 'Sheet', sheetName);

    if isempty(workbookCells) || size(workbookCells, 1) < 2
        error('The manual IC review sheet is empty.');
    end

    headers = strtrim(string(workbookCells(1, :)));

    subjectColumn = find(strcmpi(headers, 'Subject'), 1, 'first');
    sessionColumn = find(strcmpi(headers, 'Session'), 1, 'first');
    datasetColumn = find(strcmpi(headers, 'Dataset/File'), 1, 'first');
    icColumn = find(strcmpi(headers, 'IC'), 1, 'first');
    decisionColumn = find(strcmpi( ...
        headers, 'ManualFinalDecision'), 1, 'first');

    if isempty(decisionColumn)
        decisionColumn = find(strcmpi( ...
            headers, 'Include for clustering?'), 1, 'first');
    end

    if isempty(subjectColumn) || isempty(sessionColumn) || ...
            isempty(datasetColumn) || isempty(icColumn) || ...
            isempty(decisionColumn)
        error([ ...
            'Manual IC review sheet must contain Subject, Session, ' ...
            'Dataset/File, IC, and ManualFinalDecision.']);
    end

    data = workbookCells(2:end, :);

    subject = normalize_text_local(data(:, subjectColumn));
    session = normalize_text_local(data(:, sessionColumn));
    datasetFile = normalize_text_local(data(:, datasetColumn));
    ic = normalize_numeric_local(data(:, icColumn));
    decision = normalize_text_local(data(:, decisionColumn));

    validRows = strlength(subject) > 0 & ...
        strlength(session) > 0 & ...
        strlength(datasetFile) > 0 & ...
        isfinite(ic);

    subject = subject(validRows);
    session = session(validRows);
    datasetFile = datasetFile(validRows);
    ic = ic(validRows);
    decision = decision(validRows);

    if any(ic < 1 | ic ~= round(ic))
        error('The manual IC review sheet contains an invalid IC index.');
    end

    decisionLower = lower(strtrim(decision));
    allowed = ["", "yes", "review", "no"];

    if any(~ismember(decisionLower, allowed))
        bad = unique(decision(~ismember(decisionLower, allowed)));
        error('Unsupported ManualFinalDecision value(s): %s', ...
            strjoin(cellstr(bad), ', '));
    end

    datasetKey = lower(subject) + "|" + ...
        lower(session) + "|" + lower(datasetFile);

    [uniqueKeys, firstRows, groups] = unique(datasetKey, 'stable');

    opts = detectImportOptions( ...
        mappingFile, ...
        'FileType', 'text', ...
        'Delimiter', ',', ...
        'VariableNamingRule', 'preserve');

    sourceMap = readtable(mappingFile, opts);

    requiredMapColumns = { ...
        'PreprocessedICASetPath', ...
        'ICAQCStatus', ...
        'AMICAInputSignature'};

    for c = 1:numel(requiredMapColumns)
        if ~ismember(requiredMapColumns{c}, ...
                sourceMap.Properties.VariableNames)
            error('Subject-level processing table is missing: %s', ...
                requiredMapColumns{c});
        end
    end

    sourceMap.PreprocessedICASetPath = normalize_text_local( ...
        sourceMap.PreprocessedICASetPath);
    sourceMap.ICAQCStatus = normalize_text_local(sourceMap.ICAQCStatus);
    sourceMap.AMICAInputSignature = normalize_text_local( ...
        sourceMap.AMICAInputSignature);

    if ismember('BidsSession', sourceMap.Properties.VariableNames)
        sourceMap.BidsSession = normalize_text_local(sourceMap.BidsSession);
    end

    mappedFileNames = strings(height(sourceMap), 1);

    for row = 1:height(sourceMap)
        [~, n, e] = fileparts(char(replace( ...
            sourceMap.PreprocessedICASetPath(row), '\', '/')));
        mappedFileNames(row) = string(n) + string(e);
    end

    specs = repmat(struct( ...
        'subject', "", ...
        'session', "", ...
        'yesICs', [], ...
        'sourceSet', "", ...
        'amicaInputSignature', ""), ...
        numel(uniqueKeys), 1);

    keep = false(numel(uniqueKeys), 1);

    for g = 1:numel(uniqueKeys)

        rows = groups == g;
        row0 = firstRows(g);
        yesICs = sort(unique(ic(rows & decisionLower == "yes")))';

        if isempty(yesICs)
            continue;
        end

        fileMask = strcmpi(mappedFileNames, datasetFile(row0));

        if ismember('BidsSession', sourceMap.Properties.VariableNames)
            sessionMask = strcmpi(sourceMap.BidsSession, session(row0));
            if any(fileMask & sessionMask)
                fileMask = fileMask & sessionMask;
            end
        end

        matchedRows = find(fileMask);

        if numel(matchedRows) ~= 1
            error('Expected one processing-table row for %s; found %d.', ...
                datasetFile(row0), numel(matchedRows));
        end

        mapRow = matchedRows(1);

        if ~strcmpi(sourceMap.ICAQCStatus(mapRow), ...
                'passed_ica_quality_basic_checks')
            error('Dataset is blocked by ICA QC status "%s": %s', ...
                sourceMap.ICAQCStatus(mapRow), datasetFile(row0));
        end

        sourceSet = sourceMap.PreprocessedICASetPath(mapRow);

        if exist(sourceSet, 'file') ~= 2
            error('preprocessed_and_ICA dataset not found:\n%s', sourceSet);
        end

        specs(g).subject = subject(row0);
        specs(g).session = session(row0);
        specs(g).yesICs = yesICs;
        specs(g).sourceSet = sourceSet;
        specs(g).amicaInputSignature = ...
            sourceMap.AMICAInputSignature(mapRow);
        keep(g) = true;
    end

    subjectSpecs = specs(keep);

    if isempty(subjectSpecs)
        error('No dataset contains at least one IC marked Yes.');
    end

    subjectKeys = lower(string({subjectSpecs.subject}))';

    if numel(unique(subjectKeys)) ~= numel(subjectKeys)
        error('More than one continuous ICA dataset was selected per subject.');
    end
end


function verify_source_local(EEG, expectedSubject, yesICs, expectedSignature)

    if EEG.trials ~= 1
        error('ROI determination requires continuous datasets.');
    end

    if ~strcmpi(string(EEG.subject), string(expectedSubject))
        error('Unexpected EEG.subject: %s', char(string(EEG.subject)));
    end

    if isempty(EEG.icaweights) || isempty(EEG.icasphere)
        error('Dataset has no usable ICA decomposition.');
    end

    nIC = size(EEG.icaweights, 1);

    if any(yesICs < 1 | yesICs > nIC)
        error('Yes IC index is outside 1:%d for %s.', nIC, expectedSubject);
    end

    if ~isfield(EEG, 'etc') || ...
            ~isfield(EEG.etc, 'amica_input_signature')
        error('EEG.etc.amica_input_signature is missing.');
    end

    if string(EEG.etc.amica_input_signature) ~= string(expectedSignature)
        error('AMICA provenance mismatch for %s.', expectedSubject);
    end
end


function x = normalize_text_local(x)

    if iscell(x)
        out = strings(numel(x), 1);
        for k = 1:numel(x)
            raw = x{k};
            if isempty(raw)
                out(k) = "";
            elseif ischar(raw) || isstring(raw)
                out(k) = string(raw);
            elseif isnumeric(raw) || islogical(raw)
                if isscalar(raw) && isfinite(double(raw))
                    out(k) = string(raw);
                end
            end
        end
        x = out;
    else
        x = string(x(:));
    end

    x(ismissing(x)) = "";
    x = strtrim(x(:));

    blankLike = strcmpi(x, "NaN") | ...
        strcmpi(x, "<missing>") | ...
        strcmpi(x, "missing");

    x(blankLike) = "";
end


function x = normalize_numeric_local(x)

    if isnumeric(x) || islogical(x)
        x = double(x(:));
        return;
    end

    if iscell(x)
        out = nan(numel(x), 1);
        for k = 1:numel(x)
            raw = x{k};
            if isempty(raw)
                continue;
            elseif isnumeric(raw) || islogical(raw)
                if isscalar(raw)
                    out(k) = double(raw);
                end
            else
                out(k) = str2double(string(raw));
            end
        end
        x = out;
    else
        x = str2double(string(x(:)));
    end
end
