% Goal:
% 1. Read manual_IC_selection_final_v2.xlsx.
% 2. Load each original *_preprocessed_and_ICA.set file.
% 3. Write the manual Yes / Review / No IC decisions into EEG.etc.
% 4. Save a NEW *_ICA_manual_selection.set copy without removing any IC.
% 5. Create an EEGLAB STUDY in which only ICs marked "Yes" are designated
%    for component clustering.
%
% Important:
% - This script NEVER calls pop_subcomp.
% - This script NEVER overwrites *_preprocessed_and_ICA.set.
% - EEG.data and the ICA decomposition are not intentionally changed.
% - "No" means "do not use for cortical IC clustering"; it does not mean
%   "remove this IC from continuous EEG".
% - If a session has zero Yes ICs, that dataset is NOT added to the
%   Yes-only STUDY. In EEGLAB, an empty STUDY.datasetinfo(k).comps field
%   means "use all components", not "use no components".
% - A source dataset is accepted only when its import-table ICAQCStatus
%   passes the configured gate. Warning-status rows require an explicit
%   numeric approval in ICAQCManualApproval.
% - Existing manual-selection copies are reused only when their decisions,
%   source path, and source .set/.fdt signature still match.
%
% Expected input:
%   manual_IC_selection_final_v2.xlsx
%   Sheet: Manual_IC_Selection
%
% Main outputs:
%   output_data\8_manual-IC-selection\<session>\
%       <session>_ICA_manual_selection.set
%
%   output_data\8_manual-IC-selection\
%       manual_IC_selection_application_log.csv
%
%   output_data\9_group-STUDY\
%       HipExo_manual_IC_Yes_only.study
%       HipExo_manual_IC_Yes_only_dataset_manifest.csv
%
% Recommended run order:
%   1) bemobil_run_AMICA_only.m
%   2) check_AMICA_quality.m
%   3) complete manual_IC_selection_final_v2.xlsx
%   4) this script
%
% The script is table-driven and uses paths.m / bemobil_config_.m.

clear;
clc;
close all;

set(0, 'DefaultFigureVisible', 'off');
set(groot, 'DefaultFigureVisible', 'off');

%% ========================================================================
%  LOAD CENTRAL PATHS AND BEMOBIL CONFIGURATION
%  ========================================================================

scriptFolder = fileparts(mfilename('fullpath'));

run(fullfile(scriptFolder, 'paths.m'));
run(fullfile(scriptFolder, 'bemobil_config_.m'));

if ~exist(outputFolder, 'dir')
    error('Output folder does not exist:\n%s', outputFolder);
end

if ~exist(mappingFile, 'file')
    warning(['bemobil_import_table.csv was not found:\n%s\n' ...
        'The script can still run, but it cannot use/update the import table.'], ...
        mappingFile);
end

%% ========================================================================
%  USER SETTINGS
%  ========================================================================

manualICWorkbookName = 'manual_IC_selection_final_v2.xlsx';
manualICSheetName    = 'Manual_IC_Selection';

% Frozen final-table integrity checks. These values correspond to the
% completed manual review workbook used for the main analysis.
expectedManualSessionCount = 22;
expectedManualICRowCount   = 186;

% Use exactly one workbook path. This avoids accidentally reading an older
% copy from the script folder or the current MATLAB working directory.
manualICTableFile = string(fullfile( ...
    outputFolder, ...
    manualICWorkbookName));

if exist(manualICTableFile, 'file') ~= 2
    error(['Could not find the manual IC workbook:\n%s\n\n' ...
        'Place manual_IC_selection_final_v2.xlsx directly inside ' ...
        'output_data before rerunning.'], ...
        manualICTableFile);
end

manualSelectionRoot = fullfile(outputFolder, '8_manual-IC-selection');
studyOutputFolder   = fullfile(outputFolder, '9_group-STUDY');

studyName     = 'HipExo manual IC Yes-only';
studyTask     = 'Hip exoskeleton gait EEG';
studyFilename = 'HipExo_manual_IC_Yes_only.study';

% false:
%   Existing valid *_ICA_manual_selection.set files are reused.
% true:
%   Existing manual-selection copies are regenerated from the untouched
%   *_preprocessed_and_ICA.set source files.
force_recompute_manual_selection_sets = false;

% If an existing manual-selection copy lacks the new source signature or
% otherwise fails reuse verification, rebuild that derived copy from the
% untouched source instead of failing the whole batch.
recompute_stale_manual_selection_sets_automatically = true;

% Update new ManualICSelection* columns in bemobil_import_table.csv.
update_import_table = true;

% Mark ExpertICReviewStatus as completed for matched rows.
update_expert_review_status = true;

% Strict source gates. Keep these enabled for the frozen/final analysis.
require_passed_ica_qc = true;
accepted_ica_qc_statuses = ["passed_ica_quality_basic_checks"];

% A warning-status source can be used only after an explicit per-session
% approval is recorded as 1 in this import-table column. If the column is
% absent, warning rows remain blocked.
allow_warning_ica_qc_with_explicit_approval = true;
ica_qc_warning_status = "warning_ica_quality_needs_review";
ica_qc_approval_column = 'ICAQCManualApproval';

% Verify that the AMICA provenance signature stored inside the source EEG
% agrees with AMICAInputSignature in bemobil_import_table.csv whenever the
% table contains a non-empty expected signature.
require_source_amica_provenance_match = true;

% Create the Yes-only STUDY after all manual-selection copies pass checks.
create_yes_only_study = true;

% Group label stored in EEG and STUDY metadata.
studyGroupLabel = 'PilotTest2';

%% ========================================================================
%  CREATE OUTPUT FOLDERS
%  ========================================================================

if ~exist(manualSelectionRoot, 'dir')
    mkdir(manualSelectionRoot);
end

if ~exist(studyOutputFolder, 'dir')
    mkdir(studyOutputFolder);
end

%% ========================================================================
%  INITIALIZE EEGLAB
%  ========================================================================

if ~exist('pop_loadset', 'file')
    eeglab nogui;
end

% Use disk-backed STUDY handling and two-file EEGLAB datasets when possible.
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

hide_all_figures_local();

%% ========================================================================
%  READ THE MANUAL IC SELECTION WORKBOOK
%  ========================================================================

fprintf('\n============================================================\n');
fprintf('MANUAL IC SELECTION APPLICATION STARTED\n');
fprintf('============================================================\n');
fprintf('Running script:\n%s\n', mfilename('fullpath'));
fprintf('Manual IC workbook:\n%s\n', manualICTableFile);
fprintf('Sheet: %s\n', manualICSheetName);

workbookInfo = dir(manualICTableFile);
if ~isempty(workbookInfo)
    fprintf('Workbook size: %d bytes\n', workbookInfo.bytes);
    fprintf('Workbook modified: %s\n', workbookInfo.date);
end

fprintf('============================================================\n\n');

% Do not use readtable here. Some XLSX writers omit or retain inconsistent
% worksheet/Table range metadata, and MATLAB may then auto-detect only part
% of the sheet. Read the five required columns from explicit cell ranges.
try
    subjectCells = readcell( ...
        manualICTableFile, ...
        'Sheet', manualICSheetName, ...
        'Range', 'A2:A187');

    sessionCells = readcell( ...
        manualICTableFile, ...
        'Sheet', manualICSheetName, ...
        'Range', 'B2:B187');

    datasetCells = readcell( ...
        manualICTableFile, ...
        'Sheet', manualICSheetName, ...
        'Range', 'C2:C187');

    icCells = readcell( ...
        manualICTableFile, ...
        'Sheet', manualICSheetName, ...
        'Range', 'D2:D187');

    decisionCells = readcell( ...
        manualICTableFile, ...
        'Sheet', manualICSheetName, ...
        'Range', 'S2:S187');

    manualTable = table( ...
        subjectCells, ...
        sessionCells, ...
        datasetCells, ...
        icCells, ...
        decisionCells, ...
        'VariableNames', { ...
            'Subject', ...
            'Session', ...
            'Dataset/File', ...
            'IC', ...
            'Include for clustering?' ...
        });

catch ME
    error('Could not read the manual IC workbook with explicit ranges:\n%s', ...
        ME.message);
end

requiredManualColumns = { ...
    'Subject', ...
    'Session', ...
    'Dataset/File', ...
    'IC', ...
    'Include for clustering?' ...
};

for c = 1:numel(requiredManualColumns)
    if ~ismember(requiredManualColumns{c}, manualTable.Properties.VariableNames)
        error('Manual IC table is missing required column: %s', ...
            requiredManualColumns{c});
    end
end

manualTable.Subject = normalize_string_column_local(manualTable.Subject);
manualTable.Session = normalize_string_column_local(manualTable.Session);
manualTable.("Dataset/File") = ...
    normalize_string_column_local(manualTable.("Dataset/File"));
manualTable.("Include for clustering?") = ...
    normalize_selection_status_local( ...
        manualTable.("Include for clustering?"));

manualTable.IC = normalize_numeric_vector_local(manualTable.IC);

% Remove fully empty rows only.
validManualRows = ...
    strlength(strtrim(manualTable.Session)) > 0 & ...
    ~isnan(manualTable.IC);

manualTable = manualTable(validManualRows, :);

if isempty(manualTable)
    error('The Manual_IC_Selection sheet contains no usable rows.');
end

% Validate IC indices.
if any(manualTable.IC < 1 | manualTable.IC ~= round(manualTable.IC))
    error('The IC column contains non-positive or non-integer IC indices.');
end

% Validate decisions.
allowedStatuses = ["Yes", "Review", "No"];
badStatusMask = ~ismember(manualTable.("Include for clustering?"), allowedStatuses);

if any(badStatusMask)
    badValues = unique(manualTable.("Include for clustering?")(badStatusMask));
    error('Unsupported Include for clustering? value(s): %s', ...
        strjoin(cellstr(badValues), ', '));
end

% Reject contradictory duplicate Session + IC decisions.
manualKey = manualTable.Session + "|" + string(manualTable.IC);
[uniqueKeys, ~, keyGroup] = unique(manualKey, 'stable');

for g = 1:numel(uniqueKeys)
    groupStatuses = unique( ...
        manualTable.("Include for clustering?")(keyGroup == g));

    if numel(groupStatuses) > 1
        error(['Conflicting decisions exist for the same Session + IC:\n' ...
            '%s\nStatuses: %s'], ...
            uniqueKeys(g), strjoin(cellstr(groupStatuses), ', '));
    end
end

% Remove exact duplicate Session + IC rows after conflict checking.
[~, firstKeyRow] = unique(manualKey, 'stable');
manualTable = manualTable(sort(firstKeyRow), :);

[sessionList, firstSessionRow] = unique(manualTable.Session, 'stable');
sessionSubjects = manualTable.Subject(firstSessionRow);

fprintf('Unique sessions in manual IC table: %d\n', numel(sessionList));
fprintf('Recorded candidate IC rows: %d\n\n', height(manualTable));

if numel(sessionList) ~= expectedManualSessionCount || ...
        height(manualTable) ~= expectedManualICRowCount

    error([ ...
        'The workbook is incomplete or is not the frozen final version.\n' ...
        'Expected: %d sessions and %d IC rows.\n' ...
        'Found:    %d sessions and %d IC rows.\n\n' ...
        'Replace the workbook at:\n%s\n' ...
        'with the complete manual_IC_selection_final_v2.xlsx before rerunning.'], ...
        expectedManualSessionCount, ...
        expectedManualICRowCount, ...
        numel(sessionList), ...
        height(manualTable), ...
        manualICTableFile);

end

%% ========================================================================
%  READ THE IMPORT TABLE WHEN AVAILABLE
%  ========================================================================

sourceMap = table();

if exist(mappingFile, 'file') == 2

    optsImport = detectImportOptions( ...
        mappingFile, ...
        'FileType', 'text', ...
        'Delimiter', ',', ...
        'VariableNamingRule', 'preserve');

    sourceMap = readtable(mappingFile, optsImport);

    if ismember('PreprocessedICASetPath', sourceMap.Properties.VariableNames)
        sourceMap.PreprocessedICASetPath = ...
            normalize_string_column_local(sourceMap.PreprocessedICASetPath);
    end

    if ismember('ProcessingSubjectFolder', sourceMap.Properties.VariableNames)
        sourceMap.ProcessingSubjectFolder = ...
            normalize_string_column_local(sourceMap.ProcessingSubjectFolder);
    end

    fprintf('Loaded import table:\n%s\n', mappingFile);
    fprintf('Import-table rows: %d\n\n', height(sourceMap));

end

%% ========================================================================
%  PREALLOCATE APPLICATION LOG
%  ========================================================================

nSessions = numel(sessionList);

logSession             = strings(nSessions, 1);
logSubject             = strings(nSessions, 1);
logCondition           = strings(nSessions, 1);
logSubjectSessionIndex = nan(nSessions, 1);
logSourceSetPath       = strings(nSessions, 1);
logSourceSetSignature  = strings(nSessions, 1);
logICAQCStatus         = strings(nSessions, 1);
logOutputSetPath       = strings(nSessions, 1);
logYesICs              = strings(nSessions, 1);
logReviewICs           = strings(nSessions, 1);
logNoICs               = strings(nSessions, 1);
logUnlistedICs         = strings(nSessions, 1);
logYesCount            = zeros(nSessions, 1);
logReviewCount         = zeros(nSessions, 1);
logNoCount             = zeros(nSessions, 1);
logTotalICs            = nan(nSessions, 1);
logIncludeInStudy      = zeros(nSessions, 1);
logStatus              = strings(nSessions, 1);
logNotes               = strings(nSessions, 1);

yesICsBySession = cell(nSessions, 1);

% Session numbering must start at 1 separately for each subject.
subjectSessionCounter = containers.Map( ...
    'KeyType', 'char', ...
    'ValueType', 'double');

%% ========================================================================
%  APPLY MANUAL SELECTION TO EACH ORIGINAL ICA DATASET
%  ========================================================================

for s = 1:nSessions

    hide_all_figures_local();

    sessionLabel = sessionList(s);
    sessionRows = manualTable.Session == sessionLabel;

    subjectValues = unique(manualTable.Subject(sessionRows));
    datasetFiles  = unique(manualTable.("Dataset/File")(sessionRows));

    if numel(subjectValues) ~= 1
        error('Session %s has multiple Subject values.', sessionLabel);
    end

    if numel(datasetFiles) ~= 1
        error('Session %s has multiple Dataset/File values.', sessionLabel);
    end

    subjectLabel = subjectValues(1);
    datasetFile  = datasetFiles(1);
    conditionLabel = extract_condition_label_local(sessionLabel);

    subjectKey = char(subjectLabel);

    if ~isKey(subjectSessionCounter, subjectKey)
        subjectSessionCounter(subjectKey) = 0;
    end

    subjectSessionCounter(subjectKey) = ...
        subjectSessionCounter(subjectKey) + 1;

    subjectSessionIndex = subjectSessionCounter(subjectKey);

    decisions = manualTable.("Include for clustering?")(sessionRows);
    sessionICs = manualTable.IC(sessionRows);

    yesICs = sort(unique(sessionICs(decisions == "Yes")))';
    reviewICs = sort(unique(sessionICs(decisions == "Review")))';
    noICs = sort(unique(sessionICs(decisions == "No")))';

    recordedICs = sort(unique([yesICs reviewICs noICs]));

    if ~isempty(intersect(yesICs, reviewICs)) || ...
            ~isempty(intersect(yesICs, noICs)) || ...
            ~isempty(intersect(reviewICs, noICs))
        error('Overlapping Yes / Review / No IC lists in session %s.', ...
            sessionLabel);
    end

    logSession(s) = sessionLabel;
    logSubject(s) = subjectLabel;
    logCondition(s) = conditionLabel;
    logSubjectSessionIndex(s) = subjectSessionIndex;
    logYesICs(s) = numeric_vector_to_string_local(yesICs);
    logReviewICs(s) = numeric_vector_to_string_local(reviewICs);
    logNoICs(s) = numeric_vector_to_string_local(noICs);
    logYesCount(s) = numel(yesICs);
    logReviewCount(s) = numel(reviewICs);
    logNoCount(s) = numel(noICs);
    logIncludeInStudy(s) = double(~isempty(yesICs));
    yesICsBySession{s} = yesICs;

    fprintf('\n\n============================================================\n');
    fprintf('SESSION %d / %d\n', s, nSessions);
    fprintf('Session: %s\n', sessionLabel);
    fprintf('Subject: %s\n', subjectLabel);
    fprintf('Condition: %s\n', conditionLabel);
    fprintf('Dataset/File: %s\n', datasetFile);
    fprintf('Yes ICs: %s\n', numeric_vector_to_string_local(yesICs));
    fprintf('Review ICs: %s\n', numeric_vector_to_string_local(reviewICs));
    fprintf('No ICs: %s\n', numeric_vector_to_string_local(noICs));
    fprintf('============================================================\n');

    try

        sourceSetPath = resolve_preprocessed_ica_set_local( ...
            sourceMap, ...
            outputFolder, ...
            bemobil_config, ...
            sessionLabel, ...
            datasetFile);

        logSourceSetPath(s) = sourceSetPath;

        sourceRows = find_source_map_rows_local( ...
            sourceMap, ...
            sessionLabel, ...
            sourceSetPath);

        sourceICAQCStatus = verify_source_ica_qc_gate_local( ...
            sourceMap, ...
            sourceRows, ...
            sessionLabel, ...
            require_passed_ica_qc, ...
            accepted_ica_qc_statuses, ...
            allow_warning_ica_qc_with_explicit_approval, ...
            ica_qc_warning_status, ...
            ica_qc_approval_column);

        logICAQCStatus(s) = sourceICAQCStatus;

        sourceSetSignature = file_signature_local(sourceSetPath);
        logSourceSetSignature(s) = sourceSetSignature;

        fprintf('Resolved untouched source dataset:\n%s\n', sourceSetPath);
        fprintf('Source ICA QC status: %s\n', sourceICAQCStatus);
        fprintf('Source signature: %s\n', sourceSetSignature);

        % EEGLAB pop_* functions still expect character vectors in several
        % argument-serialization paths. Convert the string path before
        % fileparts so filename and filepath are both char vectors.
        [sourceSetFolder, sourceSetName, sourceSetExt] = ...
            fileparts(char(sourceSetPath));

        EEG = pop_loadset( ...
            'filename', [sourceSetName sourceSetExt], ...
            'filepath', sourceSetFolder);

        EEG = eeg_checkset(EEG);

        if require_source_amica_provenance_match
            verify_source_amica_provenance_local( ...
                EEG, ...
                sourceMap, ...
                sourceRows, ...
                sessionLabel);
        end

        if isempty(EEG.icaweights) || isempty(EEG.icasphere)
            error('The source dataset does not contain a valid ICA decomposition.');
        end

        nICs = size(EEG.icaweights, 1);
        logTotalICs(s) = nICs;

        if any(recordedICs > nICs)
            invalidICs = recordedICs(recordedICs > nICs);
            error('Manual table contains IC indices above nICs=%d: %s', ...
                nICs, numeric_vector_to_string_local(invalidICs));
        end

        unlistedICs = setdiff(1:nICs, recordedICs);
        logUnlistedICs(s) = numeric_vector_to_string_local(unlistedICs);

        % Preserve previous metadata before assigning STUDY metadata.
        originalSetname = string(EEG.setname);
        originalSubject = string(EEG.subject);
        originalCondition = string(EEG.condition);
        originalSession = EEG.session;

        selectionInfo = struct();
        selectionInfo.version = 'manual_IC_selection_final_v2';
        selectionInfo.table_file = char(manualICTableFile);
        selectionInfo.table_sheet = manualICSheetName;
        selectionInfo.applied_on = char(datetime( ...
            'now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
        selectionInfo.source_set_path = char(sourceSetPath);
        selectionInfo.source_set_signature = char(sourceSetSignature);
        selectionInfo.source_ica_qc_status = char(sourceICAQCStatus);
        selectionInfo.source_setname = char(originalSetname);
        selectionInfo.source_subject = char(originalSubject);
        selectionInfo.source_condition = char(originalCondition);
        selectionInfo.source_session = originalSession;
        selectionInfo.yes_ic = yesICs;
        selectionInfo.review_ic = reviewICs;
        selectionInfo.no_ic = noICs;
        selectionInfo.recorded_candidate_ic = recordedICs;
        selectionInfo.unlisted_ic = unlistedICs;
        selectionInfo.main_clustering_rule = 'Yes only';
        selectionInfo.components_removed = false;
        selectionInfo.signal_data_changed = false;

        if ~isfield(EEG, 'etc') || isempty(EEG.etc)
            EEG.etc = struct();
        end

        EEG.etc.manual_ic_selection = selectionInfo;

        % Metadata required for an interpretable STUDY.
        EEG.subject = char(subjectLabel);
        EEG.condition = char(conditionLabel);
        EEG.session = subjectSessionIndex;
        EEG.group = studyGroupLabel;
        EEG.setname = char(sessionLabel + "_ICA_manual_selection");

        EEG = eeg_checkset(EEG);

        outputSessionFolder = fullfile( ...
            manualSelectionRoot, ...
            char(sessionLabel));

        if ~exist(outputSessionFolder, 'dir')
            mkdir(outputSessionFolder);
        end

        outputSetFile = char(sessionLabel + "_ICA_manual_selection.set");
        outputSetPath = string(fullfile( ...
            outputSessionFolder, ...
            outputSetFile));

        reuseExistingManualSet = false;

        if exist(outputSetPath, 'file') == 2 && ...
                ~force_recompute_manual_selection_sets

            try
                verify_existing_manual_set_local( ...
                    outputSetPath, ...
                    yesICs, ...
                    reviewICs, ...
                    noICs, ...
                    manualICTableFile, ...
                    sourceSetPath, ...
                    sourceSetSignature, ...
                    sourceICAQCStatus);

                reuseExistingManualSet = true;

                fprintf(['Existing manual-selection copy matches the current ' ...
                    'table and source signature. Reusing:\n%s\n'], ...
                    outputSetPath);

            catch reuseME
                if recompute_stale_manual_selection_sets_automatically
                    warning(['Existing manual-selection copy is stale or ' ...
                        'unverifiable and will be rebuilt:\n%s\nReason: %s'], ...
                        outputSetPath, reuseME.message);
                else
                    rethrow(reuseME);
                end
            end
        end

        if ~reuseExistingManualSet

            EEG = pop_saveset( ...
                EEG, ...
                'filename', outputSetFile, ...
                'filepath', outputSessionFolder);

            if exist(outputSetPath, 'file') ~= 2
                error('pop_saveset returned, but output .set was not found.');
            end

            fprintf('Saved manual-selection copy:\n%s\n', outputSetPath);

        end

        logOutputSetPath(s) = outputSetPath;
        logStatus(s) = "completed";

        if isempty(yesICs)
            logNotes(s) = ...
                "Manual selection saved. Excluded from Yes-only STUDY because this session has zero Yes ICs.";
        else
            logNotes(s) = ...
                "Manual selection saved. Eligible for Yes-only STUDY.";
        end

        clear EEG;

    catch ME

        logStatus(s) = "failed";
        logNotes(s) = string(getReport(ME, 'extended', ...
            'hyperlinks', 'off'));

        warning('Session %s failed:\n%s', ...
            sessionLabel, ME.message);

        clear EEG;

    end

end

%% ========================================================================
%  WRITE APPLICATION LOG
%  ========================================================================

applicationLog = table( ...
    logSession, ...
    logSubject, ...
    logCondition, ...
    logSubjectSessionIndex, ...
    logSourceSetPath, ...
    logSourceSetSignature, ...
    logICAQCStatus, ...
    logOutputSetPath, ...
    logYesICs, ...
    logReviewICs, ...
    logNoICs, ...
    logUnlistedICs, ...
    logYesCount, ...
    logReviewCount, ...
    logNoCount, ...
    logTotalICs, ...
    logIncludeInStudy, ...
    logStatus, ...
    logNotes, ...
    'VariableNames', { ...
        'Session', ...
        'Subject', ...
        'Condition', ...
        'SubjectSessionIndex', ...
        'SourcePreprocessedICASetPath', ...
        'SourcePreprocessedICASetSignature', ...
        'SourceICAQCStatus', ...
        'ManualSelectionSetPath', ...
        'YesICs', ...
        'ReviewICs', ...
        'NoICs', ...
        'UnlistedICs', ...
        'YesCount', ...
        'ReviewCount', ...
        'NoCount', ...
        'TotalICs', ...
        'IncludeInYesOnlyStudy', ...
        'Status', ...
        'Notes' ...
    });

applicationLogFile = fullfile( ...
    manualSelectionRoot, ...
    'manual_IC_selection_application_log.csv');

writetable(applicationLog, applicationLogFile);

fprintf('\nApplication log saved to:\n%s\n', applicationLogFile);

failedSessions = applicationLog.Status ~= "completed";

if any(failedSessions)

    fprintf('\nFAILED SESSIONS:\n');
    disp(applicationLog(failedSessions, { ...
        'Session', ...
        'SourcePreprocessedICASetPath', ...
        'Status', ...
        'Notes' ...
    }));

    error(['One or more sessions failed. The STUDY was not created.\n' ...
        'Fix the failures and rerun this script.']);

end

%% ========================================================================
%  UPDATE BEMOBIL IMPORT TABLE
%  ========================================================================

if update_import_table && ~isempty(sourceMap)

    sourceMap = ensure_string_column_local( ...
        sourceMap, 'ManualICSelectionStatus');
    sourceMap = ensure_string_column_local( ...
        sourceMap, 'ManualICSelectionDate');
    sourceMap = ensure_string_column_local( ...
        sourceMap, 'ManualICSelectionTablePath');
    sourceMap = ensure_string_column_local( ...
        sourceMap, 'ManualICSelectionSetPath');
    sourceMap = ensure_string_column_local( ...
        sourceMap, 'ManualICSelectionRule');
    sourceMap = ensure_string_column_local( ...
        sourceMap, 'ManualICSelectionSourceSignature');
    sourceMap = ensure_string_column_local( ...
        sourceMap, 'ManualICSelectionSourceICAQCStatus');
    sourceMap = ensure_numeric_nan_column_local( ...
        sourceMap, 'ManualICSelectionYesCount');
    sourceMap = ensure_numeric_nan_column_local( ...
        sourceMap, 'ManualICSelectionReviewCount');
    sourceMap = ensure_numeric_nan_column_local( ...
        sourceMap, 'ManualICSelectionNoCount');

    if update_expert_review_status
        sourceMap = ensure_string_column_local( ...
            sourceMap, 'ExpertICReviewStatus');
    end

    selectionDate = string(datetime( ...
        'now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

    for s = 1:nSessions

        sourceRows = find_source_map_rows_local( ...
            sourceMap, ...
            applicationLog.Session(s), ...
            applicationLog.SourcePreprocessedICASetPath(s));

        if isempty(sourceRows)
            warning(['No matching bemobil_import_table.csv row was found ' ...
                'for session %s.'], applicationLog.Session(s));
            continue;
        end

        sourceMap.ManualICSelectionStatus(sourceRows) = "completed";
        sourceMap.ManualICSelectionDate(sourceRows) = selectionDate;
        sourceMap.ManualICSelectionTablePath(sourceRows) = ...
            string(manualICTableFile);
        sourceMap.ManualICSelectionSetPath(sourceRows) = ...
            applicationLog.ManualSelectionSetPath(s);
        sourceMap.ManualICSelectionRule(sourceRows) = ...
            "Yes only for main cortical IC clustering";
        sourceMap.ManualICSelectionSourceSignature(sourceRows) = ...
            applicationLog.SourcePreprocessedICASetSignature(s);
        sourceMap.ManualICSelectionSourceICAQCStatus(sourceRows) = ...
            applicationLog.SourceICAQCStatus(s);
        sourceMap.ManualICSelectionYesCount(sourceRows) = ...
            applicationLog.YesCount(s);
        sourceMap.ManualICSelectionReviewCount(sourceRows) = ...
            applicationLog.ReviewCount(s);
        sourceMap.ManualICSelectionNoCount(sourceRows) = ...
            applicationLog.NoCount(s);

        if update_expert_review_status
            sourceMap.ExpertICReviewStatus(sourceRows) = ...
                "completed_manual_cortical_IC_review";
        end

    end

    writetable(sourceMap, mappingFile);

    fprintf('\nImport table updated:\n%s\n', mappingFile);

end

%% ========================================================================
%  CREATE YES-ONLY EEGLAB STUDY
%  ========================================================================

if create_yes_only_study

    studyRows = find( ...
        applicationLog.Status == "completed" & ...
        applicationLog.YesCount > 0);

    skippedZeroYesRows = find( ...
        applicationLog.Status == "completed" & ...
        applicationLog.YesCount == 0);

    if ~isempty(skippedZeroYesRows)

        fprintf('\nSessions excluded from the Yes-only STUDY because YesCount = 0:\n');
        disp(applicationLog(skippedZeroYesRows, { ...
            'Session', ...
            'Subject', ...
            'YesCount', ...
            'ReviewCount', ...
            'NoCount' ...
        }));

    end

    if isempty(studyRows)
        error('No session contains a Yes IC. Cannot create a Yes-only STUDY.');
    end

    STUDY = [];
    ALLEEG = [];

    commands = cell(1, numel(studyRows));

    for k = 1:numel(studyRows)

        rowIdx = studyRows(k);
        selectedYesICs = yesICsBySession{rowIdx};

        if isempty(selectedYesICs)
            error(['Internal safety failure: empty Yes list reached the ' ...
                'STUDY command builder.']);
        end

        commands{k} = { ...
            'index', k, ...
            'load', char(applicationLog.ManualSelectionSetPath(rowIdx)), ...
            'subject', char(applicationLog.Subject(rowIdx)), ...
            'session', applicationLog.SubjectSessionIndex(rowIdx), ...
            'condition', char(applicationLog.Condition(rowIdx)), ...
            'group', studyGroupLabel, ...
            'comps', selectedYesICs ...
        };

    end

    studyNotes = sprintf([ ...
        'Created from %s. ' ...
        'Only ICs marked Yes are designated for clustering. ' ...
        'Review and No ICs remain in each dataset but are not designated ' ...
        'for the main clustering. No pop_subcomp operation was performed.'], ...
        manualICWorkbookName);

    [STUDY, ALLEEG] = std_editset( ...
        STUDY, ...
        ALLEEG, ...
        'name', studyName, ...
        'task', studyTask, ...
        'notes', studyNotes, ...
        'filename', studyFilename, ...
        'filepath', studyOutputFolder, ...
        'commands', commands, ...
        'updatedat', 'off', ...
        'rmclust', 'on', ...
        'savedat', 'off');

    [STUDY, ALLEEG] = std_checkset(STUDY, ALLEEG);

    % Verify that std_editset/std_checkset retained every Yes-only component
    % list. An empty comps field would mean "all components", so it is a
    % hard failure here.
    for k = 1:numel(studyRows)

        rowIdx = studyRows(k);
        expectedYesICs = yesICsBySession{rowIdx};

        if k > numel(STUDY.datasetinfo)
            error('STUDY has fewer datasetinfo entries than expected.');
        end

        actualComps = STUDY.datasetinfo(k).comps;

        if isempty(actualComps)
            error(['STUDY.datasetinfo(%d).comps is empty. In EEGLAB this ' ...
                'means all components, which violates the Yes-only rule.'], k);
        end

        if ~isequal(sort(actualComps(:))', sort(expectedYesICs(:))')
            error(['STUDY component mismatch for dataset %d (%s).\n' ...
                'Expected: %s\nActual: %s'], ...
                k, ...
                applicationLog.Session(rowIdx), ...
                numeric_vector_to_string_local(expectedYesICs), ...
                numeric_vector_to_string_local(actualComps));
        end

    end

    if ~isfield(STUDY, 'etc') || isempty(STUDY.etc)
        STUDY.etc = struct();
    end

    STUDY.etc.manual_ic_selection = struct();
    STUDY.etc.manual_ic_selection.version = ...
        'manual_IC_selection_final_v2';
    STUDY.etc.manual_ic_selection.table_file = ...
        char(manualICTableFile);
    STUDY.etc.manual_ic_selection.table_sheet = ...
        manualICSheetName;
    STUDY.etc.manual_ic_selection.main_clustering_rule = ...
        'Yes only';
    STUDY.etc.manual_ic_selection.created_on = ...
        char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    STUDY.etc.manual_ic_selection.total_yes_components = ...
        sum(applicationLog.YesCount(studyRows));
    STUDY.etc.manual_ic_selection.sessions_included = ...
        numel(studyRows);
    STUDY.etc.manual_ic_selection.sessions_excluded_zero_yes = ...
        numel(skippedZeroYesRows);

    [STUDY, ALLEEG] = pop_savestudy( ...
        STUDY, ...
        ALLEEG, ...
        'filename', studyFilename, ...
        'filepath', studyOutputFolder);

    studyManifest = applicationLog(studyRows, { ...
        'Session', ...
        'Subject', ...
        'Condition', ...
        'SubjectSessionIndex', ...
        'ManualSelectionSetPath', ...
        'YesICs', ...
        'YesCount', ...
        'ReviewCount', ...
        'NoCount', ...
        'TotalICs' ...
    });

    studyManifest.DatasetIndex = (1:height(studyManifest))';
    studyManifest = movevars( ...
        studyManifest, ...
        'DatasetIndex', ...
        'Before', 'Session');

    studyManifestFile = fullfile( ...
        studyOutputFolder, ...
        'HipExo_manual_IC_Yes_only_dataset_manifest.csv');

    writetable(studyManifest, studyManifestFile);

    fprintf('\n============================================================\n');
    fprintf('YES-ONLY STUDY CREATED SUCCESSFULLY\n');
    fprintf('============================================================\n');
    fprintf('STUDY file:\n%s\n', ...
        fullfile(studyOutputFolder, studyFilename));
    fprintf('STUDY manifest:\n%s\n', studyManifestFile);
    fprintf('Datasets included: %d\n', numel(studyRows));
    fprintf('Sessions excluded because YesCount = 0: %d\n', ...
        numel(skippedZeroYesRows));
    fprintf('Total Yes ICs designated for clustering: %d\n', ...
        sum(applicationLog.YesCount(studyRows)));
    fprintf('============================================================\n');

end

%% ========================================================================
%  FINAL MESSAGE
%  ========================================================================

fprintf('\nDone.\n');
fprintf(['No IC was removed and pop_subcomp was never called.\n' ...
    'The original *_preprocessed_and_ICA.set files were not overwritten.\n']);

%% ========================================================================
%  LOCAL HELPER FUNCTIONS
%  ========================================================================

function filePath = find_first_existing_file_local(candidates)

    filePath = "";

    for k = 1:numel(candidates)

        candidate = string(candidates{k});

        if strlength(candidate) > 0 && exist(candidate, 'file') == 2
            filePath = candidate;
            return;
        end

    end

end


function x = normalize_string_column_local(x)

    x = string(x);
    x(ismissing(x)) = "";
    x = strtrim(x);

end


function x = normalize_selection_status_local(x)

    x = lower(normalize_string_column_local(x));

    out = strings(size(x));

    out(x == "yes") = "Yes";
    out(x == "review") = "Review";
    out(x == "no") = "No";

    unknownMask = ~ismember(x, ["yes", "review", "no"]);
    out(unknownMask) = string(x(unknownMask));

    x = out;

end


function x = normalize_numeric_vector_local(x)

    if isnumeric(x)
        x = double(x);
    elseif islogical(x)
        x = double(x);
    else
        x = str2double(string(x));
    end

end


function conditionLabel = extract_condition_label_local(sessionLabel)

    sessionLabel = string(sessionLabel);

    token = regexp( ...
        char(sessionLabel), ...
        'ses(.+)$', ...
        'tokens', ...
        'once');

    if isempty(token)
        conditionLabel = sessionLabel;
    else
        conditionLabel = string(token{1});
    end

end


function setPath = resolve_preprocessed_ica_set_local( ...
    sourceMap, outputFolder, bemobil_config, sessionLabel, datasetFile)

    sessionLabel = string(sessionLabel);
    datasetFile = string(datasetFile);

    preferredCandidates = strings(0, 1);
    fallbackCandidates = strings(0, 1);

    % First preference: exact paths already recorded in bemobil_import_table.csv.
    if ~isempty(sourceMap) && ...
            ismember('PreprocessedICASetPath', ...
                sourceMap.Properties.VariableNames)

        mappedPaths = normalize_string_column_local( ...
            sourceMap.PreprocessedICASetPath);

        mappedNames = strings(size(mappedPaths));

        for k = 1:numel(mappedPaths)
            [~, n, e] = fileparts(normalize_path_for_fileparts_local(mappedPaths(k)));
            mappedNames(k) = string(n) + string(e);
        end

        mappedMask = ...
            strlength(mappedPaths) > 0 & ...
            strcmpi(mappedNames, datasetFile);

        % When session metadata are available, do not accept a same-named
        % dataset from a different session.
        sessionMask = source_map_session_mask_local( ...
            sourceMap, sessionLabel);

        if any(mappedMask & sessionMask)
            mappedMask = mappedMask & sessionMask;
        end

        preferredCandidates = [ ...
            preferredCandidates; ...
            mappedPaths(mappedMask) ...
        ];

    end

    parentFolder = fullfile( ...
        outputFolder, ...
        bemobil_config.single_subject_analysis_folder);

    expectedSessionPath = string(fullfile( ...
        parentFolder, ...
        sessionLabel, ...
        datasetFile));

    expectedFlatPath = string(fullfile( ...
        parentFolder, ...
        datasetFile));

    preferredCandidates = [ ...
        preferredCandidates; ...
        expectedSessionPath; ...
        expectedFlatPath ...
    ];

    % Last fallback: recursive search under output_data.
    recursiveMatches = dir(fullfile( ...
        outputFolder, ...
        '**', ...
        char(datasetFile)));

    for k = 1:numel(recursiveMatches)

        if ~recursiveMatches(k).isdir
            fallbackCandidates(end+1, 1) = string(fullfile( ...
                recursiveMatches(k).folder, ...
                recursiveMatches(k).name)); %#ok<AGROW>
        end

    end

    preferredCandidates = unique( ...
        preferredCandidates(strlength(preferredCandidates) > 0), ...
        'stable');

    fallbackCandidates = unique( ...
        fallbackCandidates(strlength(fallbackCandidates) > 0), ...
        'stable');

    existingPreferred = strings(0, 1);

    for k = 1:numel(preferredCandidates)
        if exist(preferredCandidates(k), 'file') == 2
            existingPreferred(end+1, 1) = ...
                preferredCandidates(k); %#ok<AGROW>
        end
    end

    existingPreferred = unique(existingPreferred, 'stable');

    if numel(existingPreferred) == 1
        setPath = existingPreferred(1);
        return;
    elseif numel(existingPreferred) > 1
        error(['Multiple preferred source files were found for %s.\n' ...
            'Refusing to select the first file:\n%s'], ...
            datasetFile, ...
            strjoin(cellstr(existingPreferred), newline));
    end

    existingFallback = strings(0, 1);

    for k = 1:numel(fallbackCandidates)

        if exist(fallbackCandidates(k), 'file') == 2
            existingFallback(end+1, 1) = ...
                fallbackCandidates(k); %#ok<AGROW>
        end

    end

    existingFallback = unique(existingFallback, 'stable');

    if isempty(existingFallback)

        error(['Could not find the source preprocessed_and_ICA dataset.\n' ...
            'Session: %s\nDataset/File: %s'], ...
            sessionLabel, datasetFile);

    elseif numel(existingFallback) == 1

        setPath = existingFallback(1);

    else

        error(['Multiple fallback source files were found for %s.\n' ...
            'Refusing to guess:\n%s'], ...
            datasetFile, ...
            strjoin(cellstr(existingFallback), newline));

    end

end


function verify_existing_manual_set_local( ...
    setPath, yesICs, reviewICs, noICs, manualICTableFile, ...
    sourceSetPath, sourceSetSignature, sourceICAQCStatus)

    % Keep every pop_loadset option as a character vector. Passing a
    % MATLAB string scalar can load the data successfully but later fail
    % when EEGLAB calls vararg2str to build the history command.
    [folder, name, ext] = fileparts(char(setPath));

    EEG_info = pop_loadset( ...
        'filename', [name ext], ...
        'filepath', folder, ...
        'loadmode', 'info');

    if ~isfield(EEG_info, 'etc') || ...
            ~isfield(EEG_info.etc, 'manual_ic_selection')

        error(['Existing output does not contain manual_ic_selection ' ...
            'metadata:\n%s\nSet force_recompute_manual_selection_sets = true.'], ...
            setPath);

    end

    info = EEG_info.etc.manual_ic_selection;

    requiredFields = { ...
        'yes_ic', ...
        'review_ic', ...
        'no_ic', ...
        'table_file', ...
        'source_set_path', ...
        'source_set_signature', ...
        'source_ica_qc_status'};

    for k = 1:numel(requiredFields)
        if ~isfield(info, requiredFields{k})
            error(['Existing output has incomplete manual selection metadata:\n' ...
                '%s\nSet force_recompute_manual_selection_sets = true.'], ...
                setPath);
        end
    end

    sameYes = isequal(sort(info.yes_ic(:))', sort(yesICs(:))');
    sameReview = isequal(sort(info.review_ic(:))', sort(reviewICs(:))');
    sameNo = isequal(sort(info.no_ic(:))', sort(noICs(:))');

    [~, existingTableName, existingTableExt] = fileparts(info.table_file);
    [~, currentTableName, currentTableExt] = fileparts(manualICTableFile);

    sameTableName = strcmpi( ...
        string(existingTableName) + string(existingTableExt), ...
        string(currentTableName) + string(currentTableExt));

    sameSourcePath = strcmpi( ...
        normalize_path_for_fileparts_local(info.source_set_path), ...
        normalize_path_for_fileparts_local(sourceSetPath));

    sameSourceSignature = strcmp( ...
        string(info.source_set_signature), ...
        string(sourceSetSignature));

    sameSourceICAQCStatus = strcmp( ...
        string(info.source_ica_qc_status), ...
        string(sourceICAQCStatus));

    if ~(sameYes && sameReview && sameNo && sameTableName && ...
            sameSourcePath && sameSourceSignature && ...
            sameSourceICAQCStatus)
        error(['Existing output does not match the current decisions, ' ...
            'source dataset, source signature, or ICA QC state:\n' ...
            '%s\nSet force_recompute_manual_selection_sets = true.'], ...
            setPath);
    end

end


function rows = find_source_map_rows_local( ...
    sourceMap, sessionLabel, sourceSetPath)

    rows = [];

    if isempty(sourceMap)
        return;
    end

    sessionLabel = string(sessionLabel);
    sourceSetPath = string(sourceSetPath);

    if ismember('PreprocessedICASetPath', ...
            sourceMap.Properties.VariableNames)

        tablePaths = normalize_string_column_local( ...
            sourceMap.PreprocessedICASetPath);

        rows = find(strcmpi(tablePaths, sourceSetPath));

    end

    if isempty(rows) && ...
            ismember('ProcessingSubjectFolder', ...
                sourceMap.Properties.VariableNames)

        rows = find(strcmpi( ...
            normalize_string_column_local( ...
                sourceMap.ProcessingSubjectFolder), ...
            sessionLabel));

    end

    if isempty(rows) && ...
            ismember('PreprocessedICASetPath', ...
                sourceMap.Properties.VariableNames)

        [~, sourceName, sourceExt] = fileparts(normalize_path_for_fileparts_local(sourceSetPath));
        sourceFilename = string(sourceName) + string(sourceExt);

        tablePaths = normalize_string_column_local( ...
            sourceMap.PreprocessedICASetPath);

        tableNames = strings(size(tablePaths));

        for k = 1:numel(tablePaths)
            [~, n, e] = fileparts(normalize_path_for_fileparts_local(tablePaths(k)));
            tableNames(k) = string(n) + string(e);
        end

        filenameMask = strcmpi(tableNames, sourceFilename);
        sessionMask = source_map_session_mask_local( ...
            sourceMap, sessionLabel);

        if any(filenameMask & sessionMask)
            filenameMask = filenameMask & sessionMask;
        end

        rows = find(filenameMask);

    end

end


function sessionMask = source_map_session_mask_local( ...
    sourceMap, sessionLabel)

    sessionMask = false(height(sourceMap), 1);
    sessionLabel = string(sessionLabel);

    if ismember('ProcessingSubjectFolder', ...
            sourceMap.Properties.VariableNames)

        values = normalize_string_column_local( ...
            sourceMap.ProcessingSubjectFolder);
        sessionMask = sessionMask | strcmpi(values, sessionLabel);
    end

    if ismember('ProcessingSubjectLabel', ...
            sourceMap.Properties.VariableNames)

        values = normalize_string_column_local( ...
            sourceMap.ProcessingSubjectLabel);
        sessionMask = sessionMask | ...
            strcmpi(values, erase(sessionLabel, "sub-"));
    end

    if ismember('BidsSession', sourceMap.Properties.VariableNames)

        values = normalize_string_column_local(sourceMap.BidsSession);
        sessionMask = sessionMask | ...
            strcmpi(values, sessionLabel) | ...
            strcmpi("sub-" + values, sessionLabel);
    end

end


function status = verify_source_ica_qc_gate_local( ...
    sourceMap, sourceRows, sessionLabel, requirePassedQC, ...
    acceptedStatuses, allowWarningWithApproval, warningStatus, ...
    approvalColumn)

    if ~requirePassedQC
        status = "not_required";
        return;
    end

    if isempty(sourceMap)
        error(['ICA QC gating is enabled, but bemobil_import_table.csv ' ...
            'is unavailable. Session: %s'], sessionLabel);
    end

    if isempty(sourceRows)
        error(['No unique import-table row could be matched to the source ' ...
            'preprocessed_and_ICA dataset. Session: %s'], sessionLabel);
    end

    if ~ismember('ICAQCStatus', sourceMap.Properties.VariableNames)
        error(['ICA QC gating is enabled, but ICAQCStatus is absent from ' ...
            'bemobil_import_table.csv. Session: %s'], sessionLabel);
    end

    statuses = normalize_string_column_local( ...
        sourceMap.ICAQCStatus(sourceRows));
    statuses = unique(statuses(strlength(statuses) > 0));

    if numel(statuses) ~= 1
        error(['Expected exactly one non-empty ICAQCStatus for session %s, ' ...
            'but found: %s'], ...
            sessionLabel, strjoin(cellstr(statuses), ', '));
    end

    status = statuses(1);

    if ismember(status, string(acceptedStatuses))
        return;
    end

    if allowWarningWithApproval && status == string(warningStatus)

        if ~ismember(approvalColumn, sourceMap.Properties.VariableNames)
            error(['Session %s has warning ICA QC status, but explicit ' ...
                'approval column %s is absent.'], ...
                sessionLabel, approvalColumn);
        end

        approval = normalize_numeric_vector_local( ...
            sourceMap.(approvalColumn)(sourceRows));

        if ~isempty(approval) && all(approval == 1)
            status = status + "_explicitly_approved";
            return;
        end

        error(['Session %s has warning ICA QC status and is not explicitly ' ...
            'approved in %s.'], sessionLabel, approvalColumn);
    end

    error('Session %s is blocked by ICA QC status: %s', ...
        sessionLabel, status);

end


function verify_source_amica_provenance_local( ...
    EEG, sourceMap, sourceRows, sessionLabel)

    if isempty(sourceMap) || isempty(sourceRows) || ...
            ~ismember('AMICAInputSignature', ...
                sourceMap.Properties.VariableNames)

        error(['AMICA provenance checking is enabled, but a mapped ' ...
            'AMICAInputSignature is unavailable. Session: %s'], ...
            sessionLabel);
    end

    expected = normalize_string_column_local( ...
        sourceMap.AMICAInputSignature(sourceRows));
    expected = unique(expected(strlength(expected) > 0));

    if numel(expected) ~= 1
        error(['Expected one non-empty AMICAInputSignature for session %s, ' ...
            'but found %d.'], sessionLabel, numel(expected));
    end

    hasStoredSignature = ...
        isfield(EEG, 'etc') && ...
        isfield(EEG.etc, 'amica_input_signature') && ...
        strlength(string(EEG.etc.amica_input_signature)) > 0;

    if ~hasStoredSignature
        error(['The source dataset has no EEG.etc.amica_input_signature. ' ...
            'Rerun AMICA with the provenance-aware wrapper. Session: %s'], ...
            sessionLabel);
    end

    if string(EEG.etc.amica_input_signature) ~= expected(1)
        error(['The source dataset AMICA signature does not match the ' ...
            'current import table. Session: %s'], sessionLabel);
    end

end


function signature = file_signature_local(filePath)

    filePath = string(filePath);

    if exist(filePath, 'file') ~= 2
        error('Cannot create a signature for a missing file: %s', filePath);
    end

    info = dir(filePath);
    signature = string(info.bytes) + "|" + ...
        compose('%.15g', info.datenum);

    [folder, name, ext] = fileparts(char(filePath));

    if strcmpi(ext, '.set')
        fdtPath = fullfile(folder, [name '.fdt']);

        if exist(fdtPath, 'file') == 2
            fdtInfo = dir(fdtPath);
            signature = signature + "|fdt=" + ...
                string(fdtInfo.bytes) + "|" + ...
                compose('%.15g', fdtInfo.datenum);
        else
            signature = signature + "|fdt=embedded_or_missing";
        end
    end

end


function T = ensure_string_column_local(T, columnName)

    if ~ismember(columnName, T.Properties.VariableNames)

        T.(columnName) = strings(height(T), 1);

    else

        if ~isstring(T.(columnName))
            T.(columnName) = string(T.(columnName));
        end

        T.(columnName)(ismissing(T.(columnName))) = "";

    end

end


function T = ensure_numeric_nan_column_local(T, columnName)

    if ~ismember(columnName, T.Properties.VariableNames)

        T.(columnName) = nan(height(T), 1);

    else

        if isnumeric(T.(columnName))
            T.(columnName) = double(T.(columnName));
        elseif islogical(T.(columnName))
            T.(columnName) = double(T.(columnName));
        else
            T.(columnName) = str2double(string(T.(columnName)));
        end

    end

end


function textValue = numeric_vector_to_string_local(x)

    if isempty(x)
        textValue = "";
        return;
    end

    x = double(x(:))';
    textValue = strjoin(string(x), ' ');

end


function normalizedPath = normalize_path_for_fileparts_local(pathValue)

    normalizedPath = string(pathValue);

    % A CSV produced on Windows may still contain backslashes when read on
    % macOS. Convert them only for filename parsing; do not alter the path
    % used by exist/load operations.
    normalizedPath = replace(normalizedPath, '\', '/');

end


function hide_all_figures_local()

    try
        set(0, 'DefaultFigureVisible', 'off');
        set(groot, 'DefaultFigureVisible', 'off');
    catch
    end

    try
        close all force;
    catch
        try
            close all;
        catch
        end
    end

end
