% Goal:
% Import selected EEG-containing XDF files and create usable raw EEGLAB .set files.
%
% workflow:
%   1) Read bemobil_import_table.csv
%   2) Clean stale BIDS/raw outputs for sessions that will be imported
%   3) XDF -> BIDS
%   4) BIDS -> raw EEGLAB .set, session by session
%   5) Audit raw .set files per BidsSubject + BidsSession
%   6) Automatically repair sessions that only have *_old.set files
%      - old rec files are loaded
%      - near-500 Hz files are resampled to exactly 500 Hz using pop_resample
%      - clearly abnormal files are skipped
%      - valid rec files are merged into a current non-old session-level *_EEG.set
%   7) Audit again
%   8) Write raw set status/path back into bemobil_import_table.csv
%
% Important:
%   This script is NOT subject-specific.
%   It works for all subjects/sessions with DoImport = 1.
%
% Key design:
%   - BIDS2SET is run session-by-session.
%     One bad session will not stop the whole subject.


clear; clc;

%% ========================================================================
%  SETTINGS
%  ========================================================================

% Delete old BIDS session folders for sessions that are imported in this run.
% This is important when a previously bad run is now DoImport = 0.
% Otherwise stale BIDS run files may still remain and break BIDS2SET.
cleanBidsSessionsBeforeImport = true;

% Delete old raw EEGLAB files for sessions that are imported in this run.
% This prevents stale *_old.set / broken intermediate files from previous attempts.
cleanRawSetsBeforeBids2Set = true;

% Move previous session outputs into a temporary backup before cleanup.
% They are restored automatically if any enabled run or BIDS2SET conversion fails.
preservePreviousOutputsOnFailure = true;

% Raw EEG target sampling rate.
% Raw EEGLAB output is kept at 500 Hz here.
% Real downsampling to 250 Hz happens later during BeMoBIL preprocessing.
targetRawSrate = 500;

% Maximum allowed deviation from targetRawSrate for automatic old-set repair.
%
% Important:
% This script does NOT perform metadata-only sampling-rate normalization anymore.
% Old files within this tolerance are truly resampled to targetRawSrate using pop_resample.
% Files outside this tolerance are treated as unsafe and skipped.
%
% Example:
%   499.242 Hz -> accepted and pop_resampled to 500 Hz
%   498.000 Hz -> accepted and pop_resampled to 500 Hz
%   478.000 Hz -> skipped
%   16.000 Hz  -> skipped
srateToleranceHz = 2;

% Minimum valid run duration for raw EEG.
% Your runs are usually around 5-6 minutes.
minDurationSec = 120;

%% ========================================================================
%  LOAD CENTRAL PATHS
%  ========================================================================

run(fullfile(fileparts(mfilename('fullpath')), 'paths.m'));

studyFolder = outputFolder;
bidsFolder  = fullfile(studyFolder, '1_BIDS-data');
setFolder   = fullfile(studyFolder, '2_raw-EEGLAB');

if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

cd(outputFolder);

if ~exist(bidsFolder, 'dir')
    mkdir(bidsFolder);
end

if ~exist(setFolder, 'dir')
    mkdir(setFolder);
end

if ~exist(importTableFile, 'file')
    error('Import table not found:\n%s\nRun import_table.m first.', importTableFile);
end

%% ========================================================================
%  INITIALIZE EEGLAB
%  ========================================================================

if ~exist('ALLCOM', 'var')
    eeglab;
end

%% ========================================================================
%  INITIALIZE FIELDTRIP
%  ========================================================================

global ft_default
ft_default.toolbox.signal = 'matlab';
ft_default.toolbox.stats  = 'matlab';
ft_default.toolbox.image  = 'matlab';

ft_defaults;

fprintf('Using ft_defaults from:\n%s\n', which('ft_defaults'));
fprintf('Using load_xdf from:\n%s\n', which('load_xdf'));

if isempty(which('load_xdf'))
    error('load_xdf was not found. Please check FieldTrip external/xdf path.');
end

%% ========================================================================
%  READ IMPORT TABLE
%  ========================================================================

optsImport = detectImportOptions(importTableFile, ...
    'FileType', 'text', ...
    'Delimiter', ',', ...
    'VariableNamingRule', 'preserve');

importTable = readtable(importTableFile, optsImport);

if ismember('XdfPath', importTable.Properties.VariableNames)
    importTable.XdfPath = string(importTable.XdfPath);
end

if ismember('BidsSession', importTable.Properties.VariableNames)
    importTable.BidsSession = string(importTable.BidsSession);
end

if ismember('Task', importTable.Properties.VariableNames)
    importTable.Task = string(importTable.Task);
end

if ismember('EEGStreamName', importTable.Properties.VariableNames)
    importTable.EEGStreamName = string(importTable.EEGStreamName);
end

importTable.DoImport = to_numeric_column(importTable.DoImport);
importTable.BidsSubject = to_numeric_column(importTable.BidsSubject);

if ismember('RunNumber', importTable.Properties.VariableNames)
    importTable.RunNumber = to_numeric_column(importTable.RunNumber);
else
    importTable.RunNumber = nan(height(importTable), 1);
end

rowsToImport = find(importTable.DoImport == 1);

fprintf('\n============================================================\n');
fprintf('BEMOBIL IMPORT WITH RAW SET AUDIT/REPAIR\n');
fprintf('============================================================\n');

fprintf('Import table:\n%s\n', importTableFile);
fprintf('Total rows in table: %d\n', height(importTable));
fprintf('Rows enabled for import: %d\n', numel(rowsToImport));
fprintf('BIDS target folder:\n%s\n', bidsFolder);
fprintf('EEGLAB set folder:\n%s\n', setFolder);

if isempty(rowsToImport)
    error('No rows have DoImport = 1. Check bemobil_import_table.csv.');
end

% Complete preflight before deleting any existing BIDS/raw output.
preflight_enabled_import_rows(importTable, rowsToImport);

%% ========================================================================
%  CLEAN STALE OUTPUTS FOR ENABLED SESSIONS
%  ========================================================================

enabledPairs = unique(importTable(rowsToImport, {'BidsSubject', 'BidsSession'}), 'rows', 'stable');

backupRoot = fullfile(outputFolder, 'import_backups', ...
    char(datetime('now', 'Format', 'yyyyMMdd_HHmmssSSS')));

if preservePreviousOutputsOnFailure && ...
        (cleanBidsSessionsBeforeImport || cleanRawSetsBeforeBids2Set)
    mkdir(backupRoot);
end

fprintf('\n============================================================\n');
fprintf('CLEANING STALE OUTPUTS FOR ENABLED SESSIONS\n');
fprintf('============================================================\n');

fprintf('Unique enabled subject-session pairs: %d\n', height(enabledPairs));

for i = 1:height(enabledPairs)

    subj = enabledPairs.BidsSubject(i);
    sessionName = string(enabledPairs.BidsSession(i));

    fprintf('\n------------------------------------------------------------\n');
    fprintf('Subject: %d\n', subj);
    fprintf('Session: %s\n', sessionName);

    if preservePreviousOutputsOnFailure
        backup_session_outputs(bidsFolder, setFolder, backupRoot, subj, sessionName, ...
            cleanBidsSessionsBeforeImport, cleanRawSetsBeforeBids2Set);
    end

    if cleanBidsSessionsBeforeImport
        clean_bids_session_folder(bidsFolder, subj, sessionName);
    else
        fprintf('BIDS cleanup disabled.\n');
    end

    if cleanRawSetsBeforeBids2Set
        clean_raw_session_sets(setFolder, subj, sessionName);
    else
        fprintf('Raw set cleanup disabled.\n');
    end

end

%% ========================================================================
%  GENERAL METADATA SHARED ACROSS ALL MODALITIES
%  ========================================================================

generalInfo = [];

generalInfo.dataset_description.Name                = 'HipExo EEG PilotTest2';
generalInfo.dataset_description.BIDSVersion         = '1.8.0';
generalInfo.dataset_description.License             = 'n/a';
generalInfo.dataset_description.Authors             = {"Yadan Deng"};
generalInfo.dataset_description.Acknowledgements    = 'n/a';
generalInfo.dataset_description.Funding             = {"n/a"};
generalInfo.dataset_description.ReferencesAndLinks  = {"n/a"};
generalInfo.dataset_description.DatasetDOI          = 'n/a';

generalInfo.InstitutionName                         = 'TU Darmstadt';
generalInfo.InstitutionalDepartmentName             = 'n/a';
generalInfo.InstitutionAddress                      = 'Darmstadt, Germany';
generalInfo.TaskDescription                         = 'EEG recording during exoskeleton walking task';

%% ========================================================================
%  EEG METADATA
%  ========================================================================

eegInfo = [];

eegInfo.coordsystem.EEGCoordinateSystem             = 'n/a';
eegInfo.coordsystem.EEGCoordinateUnits              = 'n/a';
eegInfo.coordsystem.EEGCoordinateSystemDescription  = 'n/a';
eegInfo.eeg.SamplingFrequency                       = targetRawSrate;

%% ========================================================================
%  PARTICIPANT METADATA
%  ========================================================================

subjectInfo = [];

subjectInfo.fields.nr.Description            = 'numerical ID of the participant';
subjectInfo.fields.age.Description           = 'age of the participant';
subjectInfo.fields.age.Unit                  = 'years';
subjectInfo.fields.sex.Description           = 'sex of the participant';
subjectInfo.fields.sex.Levels.M              = 'male';
subjectInfo.fields.sex.Levels.F              = 'female';
subjectInfo.fields.handedness.Description    = 'handedness of the participant';
subjectInfo.fields.handedness.Levels.R       = 'right-handed';
subjectInfo.fields.handedness.Levels.L       = 'left-handed';

subjectInfo.cols = {'nr', 'age', 'sex', 'handedness'};

uniqueSubjects = unique(importTable.BidsSubject(rowsToImport));
subjectData = cell(numel(uniqueSubjects), 4);

for k = 1:numel(uniqueSubjects)
    subjectData{k, 1} = uniqueSubjects(k);
    subjectData{k, 2} = 'n/a';
    subjectData{k, 3} = 'n/a';
    subjectData{k, 4} = 'n/a';
end

subjectInfo.data = subjectData;

%% ========================================================================
%  PART 1: XDF -> BIDS
%  ========================================================================

importLog = table();

fprintf('\n============================================================\n');
fprintf('STARTING XDF TO BIDS IMPORT\n');
fprintf('============================================================\n');

for n = 1:numel(rowsToImport)

    rowIdx = rowsToImport(n);
    row = importTable(rowIdx, :);

    xdfPath       = char(row.XdfPath);
    bidsSubject   = row.BidsSubject;
    bidsSession   = char(row.BidsSession);
    taskLabel     = char(row.Task);
    eegStreamName = char(row.EEGStreamName);
    runNum        = row.RunNumber;

    fprintf('\n------------------------------------------------------------\n');
    fprintf('Importing row %d/%d from table row %d\n', n, numel(rowsToImport), rowIdx);
    fprintf('XDF file:\n%s\n', xdfPath);
    fprintf('BIDS subject: sub-%02d\n', bidsSubject);
    fprintf('BIDS session: ses-%s\n', bidsSession);
    fprintf('Task: %s\n', taskLabel);
    fprintf('EEG stream: %s\n', eegStreamName);

    if ~isnan(runNum)
        fprintf('Run: run-%03d\n', runNum);
    else
        fprintf('Run: n/a\n');
    end

    if ~exist(xdfPath, 'file')

        warning('XDF file not found. Skipping:\n%s', xdfPath);

        importLog = [importLog; make_import_log_row(rowIdx, xdfPath, bidsSubject, ...
                    string(bidsSession), string(taskLabel), runNum, false, ...
                    "XDF file not found")];

        continue;

    end

    try

        config = [];

        config.bids_target_folder = bidsFolder;
        config.filename           = xdfPath;
        config.eeg.chanloc        = [];

        config.task               = taskLabel;
        config.subject            = bidsSubject;
        config.session            = bidsSession;
        config.overwrite          = 'on';

        config.eeg.stream_name    = eegStreamName;

        if ~isnan(runNum)
            config.run = runNum;
        end

        bemobil_xdf2bids(config, ...
            'general_metadata', generalInfo, ...
            'participant_metadata', subjectInfo, ...
            'eeg_metadata', eegInfo);

        importLog = [importLog; make_import_log_row(rowIdx, xdfPath, bidsSubject, ...
                    string(bidsSession), string(taskLabel), runNum, true, ...
                    "OK")];

    catch ME

        warning('Import failed for table row %d:\n%s', rowIdx, ME.message);

        fprintf('\nFULL ERROR REPORT:\n');
        fprintf('%s\n', getReport(ME, 'extended', 'hyperlinks', 'on'));

        importLog = [importLog; make_import_log_row(rowIdx, xdfPath, bidsSubject, ...
                    string(bidsSession), string(taskLabel), runNum, false, ...
                    string(ME.message))];

    end

    fclose all;

end

%% Save XDF -> BIDS import log

logFile = fullfile(outputFolder, 'bemobil_xdf2bids_import_log.csv');
writetable(importLog, logFile);

fprintf('\n============================================================\n');
fprintf('XDF TO BIDS IMPORT FINISHED\n');
fprintf('============================================================\n');

fprintf('Import log saved to:\n%s\n', logFile);

fprintf('\nSuccessful imports: %d\n', sum(importLog.Success == true));
fprintf('Failed imports: %d\n', sum(importLog.Success == false));

%% ========================================================================
%  PART 2: BIDS -> RAW EEGLAB .SET
%  ========================================================================

fprintf('\n============================================================\n');
fprintf('STARTING BIDS TO EEGLAB SET CONVERSION\n');
fprintf('============================================================\n');

successfulRows = importLog.Success == true;
bids2setLog = table();
sessionCoverage = build_session_import_coverage(importTable, rowsToImport, importLog);

sessionCoverageFile = fullfile(outputFolder, 'bemobil_session_import_coverage.csv');
writetable(sessionCoverage, sessionCoverageFile);

fprintf('\nSession import coverage:\n');
disp(sessionCoverage);
fprintf('Session import coverage saved to:\n%s\n', sessionCoverageFile);

if preservePreviousOutputsOnFailure
    incompleteRows = find(~sessionCoverage.SessionImportComplete);
    for q = 1:numel(incompleteRows)
        restore_session_outputs(bidsFolder, setFolder, backupRoot, ...
            sessionCoverage.BidsSubject(incompleteRows(q)), ...
            sessionCoverage.BidsSession(incompleteRows(q)));
    end
end

if ~any(successfulRows)

    warning('No successful BIDS imports. Skipping bemobil_bids2set.');

else

    sessionPairs = sessionCoverage(sessionCoverage.SessionImportComplete, ...
        {'BidsSubject', 'BidsSession'});

    incompleteCoverage = sessionCoverage(~sessionCoverage.SessionImportComplete, :);

    for q = 1:height(incompleteCoverage)
        bids2setLog = [bids2setLog; make_bids2set_log_row( ...
            incompleteCoverage.BidsSubject(q), ...
            incompleteCoverage.BidsSession(q), false, ...
            "Skipped: not all enabled runs completed XDF-to-BIDS import. Missing runs: " + ...
            incompleteCoverage.MissingRunNumbers(q))];
    end

    fprintf('\nBIDS2SET will run session-by-session.\n');
    fprintf('Complete subject-session pairs to convert: %d\n', height(sessionPairs));

    for p = 1:height(sessionPairs)

        subj = sessionPairs.BidsSubject(p);
        sessionName = string(sessionPairs.BidsSession(p));

        fprintf('\n------------------------------------------------------------\n');
        fprintf('Converting subject %d session %s to EEGLAB set\n', subj, sessionName);

        try

            config = [];

            config.bids_target_folder = bidsFolder;
            config.bids_folder        = bidsFolder;
            config.set_folder         = setFolder;

            config.subject            = subj;
            config.session_names      = cellstr(sessionName);

            config.overwrite          = 'on';

            % Keep raw EEG at 500 Hz level here.
            % Later preprocessing will resample to 250 Hz.
            config.resample_freq      = targetRawSrate;

            % EEG-only import.
            config.other_data_types   = {};

            bemobil_bids2set(config);

            coverageRow = find(sessionCoverage.BidsSubject == subj & ...
                sessionCoverage.BidsSession == sessionName, 1, 'first');
            [rawOutputOK, rawOutputMessage] = validate_raw_session_output( ...
                setFolder, subj, sessionName, ...
                sessionCoverage.ExpectedRunCount(coverageRow));
            if ~rawOutputOK
                error('BIDS2SET output validation failed: %s', rawOutputMessage);
            end

            bids2setLog = [bids2setLog; make_bids2set_log_row( ...
                subj, sessionName, true, "OK")];

            if preservePreviousOutputsOnFailure
                discard_session_backup(backupRoot, subj, sessionName);
            end

        catch ME

            warning('bemobil_bids2set failed for subject %d session %s:\n%s', ...
                subj, sessionName, ME.message);

            fprintf('\nFULL BIDS2SET ERROR REPORT:\n');
            fprintf('%s\n', getReport(ME, 'extended', 'hyperlinks', 'on'));

            bids2setLog = [bids2setLog; make_bids2set_log_row( ...
                subj, sessionName, false, string(ME.message))];

            if preservePreviousOutputsOnFailure
                restore_session_outputs(bidsFolder, setFolder, backupRoot, subj, sessionName);
            end

        end

        fclose all;

    end

end

%% Save BIDS2SET log

bids2setLogFile = fullfile(outputFolder, 'bemobil_bids2set_log.csv');

if ~isempty(bids2setLog)

    writetable(bids2setLog, bids2setLogFile);

    fprintf('\n============================================================\n');
    fprintf('BIDS TO EEGLAB SET CONVERSION FINISHED\n');
    fprintf('============================================================\n');

    fprintf('BIDS2SET log saved to:\n%s\n', bids2setLogFile);

    fprintf('\nSuccessful BIDS2SET sessions: %d\n', sum(bids2setLog.Success == true));
    fprintf('Failed BIDS2SET sessions: %d\n', sum(bids2setLog.Success == false));

end

%% ========================================================================
%  PART 3: RAW SET AUDIT BEFORE REPAIR
%  ========================================================================

fprintf('\n============================================================\n');
fprintf('AUDITING RAW EEGLAB SET FILES BEFORE REPAIR\n');
fprintf('============================================================\n');

auditBeforeFile = fullfile(outputFolder, 'raw_set_audit_before_repair.csv');

auditBefore = audit_raw_set_files(importTable, sessionCoverage, bidsFolder, setFolder, auditBeforeFile);

print_audit_summary(auditBefore, 'BEFORE REPAIR');

%% ========================================================================
%  PART 4: REPAIR ONLY-OLD RAW SET SESSIONS
%  ========================================================================

fprintf('\n============================================================\n');
fprintf('REPAIRING ONLY-OLD RAW SET SESSIONS\n');
fprintf('============================================================\n');

repairLogFile = fullfile(outputFolder, 'repair_only_old_raw_sets_log.csv');

repairLog = repair_only_old_raw_sets( ...
    auditBefore, ...
    setFolder, ...
    repairLogFile, ...
    targetRawSrate, ...
    srateToleranceHz, ...
    minDurationSec);

if ~isempty(repairLog)

    fprintf('\nRepair log saved to:\n%s\n', repairLogFile);
    disp(repairLog);

end

%% ========================================================================
%  PART 5: RAW SET AUDIT AFTER REPAIR
%  ========================================================================

fprintf('\n============================================================\n');
fprintf('AUDITING RAW EEGLAB SET FILES AFTER REPAIR\n');
fprintf('============================================================\n');

auditAfterFile = fullfile(outputFolder, 'raw_set_audit.csv');

auditAfter = audit_raw_set_files(importTable, sessionCoverage, bidsFolder, setFolder, auditAfterFile);

print_audit_summary(auditAfter, 'AFTER REPAIR');

%% ========================================================================
%  PART 6: WRITE RAW SET STATUS BACK TO IMPORT TABLE
%  ========================================================================

fprintf('\n============================================================\n');
fprintf('WRITING RAW SET STATUS BACK TO IMPORT TABLE\n');
fprintf('============================================================\n');

importTable = write_raw_status_to_import_table(importTable, auditAfter);

writetable(importTable, importTableFile);

fprintf('Updated import table saved to:\n%s\n', importTableFile);

%% ========================================================================
%  FINAL REPORT
%  ========================================================================

fprintf('\n============================================================\n');
fprintf('ALL DONE\n');
fprintf('============================================================\n');

fprintf('\nBIDS folder:\n%s\n', bidsFolder);
fprintf('\nEEGLAB set folder:\n%s\n', setFolder);
fprintf('\nRaw set audit before repair:\n%s\n', auditBeforeFile);
fprintf('\nRaw set audit after repair:\n%s\n', auditAfterFile);
fprintf('\nImport table updated:\n%s\n', importTableFile);

problemRows = contains(auditAfter.Status, "PROBLEM");

if any(problemRows)

    fprintf('\nWARNING: Some sessions still have raw set problems.\n');
    fprintf('Check raw_set_audit.csv before running preprocessing.\n');

    disp(auditAfter(problemRows, {'BidsSubject', 'BidsSession', 'Status', 'Recommendation'}));

else

    fprintf('\nAll imported subject-session pairs have usable raw .set files.\n');

end

fprintf('\nDone.\n');

%% ========================================================================
%  HELPER FUNCTIONS
%  ========================================================================

function y = to_numeric_column(x)

    if isnumeric(x)
        y = double(x);
    elseif islogical(x)
        y = double(x);
    else
        y = str2double(string(x));
    end

end

function logRow = make_import_log_row(rowIdx, xdfPath, bidsSubject, bidsSession, taskLabel, runNum, successFlag, messageText)

    logRow = table( ...
        rowIdx, ...
        string(xdfPath), ...
        bidsSubject, ...
        string(bidsSession), ...
        string(taskLabel), ...
        runNum, ...
        logical(successFlag), ...
        string(messageText), ...
        'VariableNames', {'TableRow', 'XdfPath', 'BidsSubject', ...
                          'BidsSession', 'Task', 'RunNumber', ...
                          'Success', 'Message'} ...
    );

end

function logRow = make_bids2set_log_row(bidsSubject, bidsSession, successFlag, messageText)

    logRow = table( ...
        bidsSubject, ...
        string(bidsSession), ...
        logical(successFlag), ...
        string(messageText), ...
        'VariableNames', {'BidsSubject', 'BidsSession', ...
                          'Success', 'Message'} ...
    );

end

function preflight_enabled_import_rows(T, rowsToImport)

    required = {'XdfPath', 'BidsSubject', 'BidsSession', 'Task', ...
                'RunNumber', 'EEGStreamName', 'DoImport'};

    for i = 1:numel(required)
        if ~ismember(required{i}, T.Properties.VariableNames)
            error('Import preflight failed: required column "%s" is missing.', required{i});
        end
    end

    missingFiles = strings(0, 1);
    for i = 1:numel(rowsToImport)
        p = string(T.XdfPath(rowsToImport(i)));
        if strlength(strtrim(p)) == 0 || exist(char(p), 'file') ~= 2
            missingFiles(end+1, 1) = p;
        end
    end

    if ~isempty(missingFiles)
        disp(missingFiles);
        error('Import preflight failed: one or more enabled XDF files do not exist. No existing output was deleted.');
    end

    streamNames = string(T.EEGStreamName(rowsToImport));
    badStreamRows = rowsToImport(streamNames ~= "LiveAmpSN-102108-1139");
    if ~isempty(badStreamRows)
        disp(T(badStreamRows, {'XdfPath', 'EEGStreamName', 'BidsSubject', 'BidsSession'}));
        error('Import preflight failed: an enabled row does not use the configured LiveAmp EEG stream.');
    end

    runText = string(T.RunNumber(rowsToImport));
    runText(ismissing(runText)) = "";
    keys = string(T.BidsSubject(rowsToImport)) + "|" + ...
           string(T.BidsSession(rowsToImport)) + "|" + ...
           string(T.Task(rowsToImport)) + "|" + runText;

    [~, ~, groupIndex] = unique(keys, 'stable');
    counts = accumarray(groupIndex, 1);
    duplicateGroups = find(counts > 1);

    if ~isempty(duplicateGroups)
        duplicateMask = ismember(groupIndex, duplicateGroups);
        disp(T(rowsToImport(duplicateMask), ...
            {'XdfPath', 'BidsSubject', 'BidsSession', 'Task', 'RunNumber'}));
        error('Import preflight failed: duplicate enabled BIDS run keys exist. No existing output was deleted.');
    end

    fprintf('Import preflight passed for %d enabled XDF rows.\n', numel(rowsToImport));

end

function coverage = build_session_import_coverage(T, rowsToImport, importLog)

    pairs = unique(T(rowsToImport, {'BidsSubject', 'BidsSession'}), 'rows', 'stable');

    BidsSubject = pairs.BidsSubject;
    BidsSession = string(pairs.BidsSession);
    ExpectedRunCount = zeros(height(pairs), 1);
    SuccessfulRunCount = zeros(height(pairs), 1);
    ExpectedRunNumbers = strings(height(pairs), 1);
    SuccessfulRunNumbers = strings(height(pairs), 1);
    MissingRunNumbers = strings(height(pairs), 1);
    SessionImportComplete = false(height(pairs), 1);

    successfulTableRows = importLog.TableRow(importLog.Success);

    for i = 1:height(pairs)
        sessionRows = rowsToImport( ...
            T.BidsSubject(rowsToImport) == pairs.BidsSubject(i) & ...
            string(T.BidsSession(rowsToImport)) == string(pairs.BidsSession(i)));

        successfulRows = sessionRows(ismember(sessionRows, successfulTableRows));
        missingRows = setdiff(sessionRows, successfulRows, 'stable');

        ExpectedRunCount(i) = numel(sessionRows);
        SuccessfulRunCount(i) = numel(successfulRows);
        ExpectedRunNumbers(i) = format_run_labels(T.RunNumber(sessionRows));
        SuccessfulRunNumbers(i) = format_run_labels(T.RunNumber(successfulRows));
        MissingRunNumbers(i) = format_run_labels(T.RunNumber(missingRows));
        SessionImportComplete(i) = ...
            ExpectedRunCount(i) > 0 && SuccessfulRunCount(i) == ExpectedRunCount(i);
    end

    coverage = table(BidsSubject, BidsSession, ExpectedRunCount, ...
        SuccessfulRunCount, ExpectedRunNumbers, SuccessfulRunNumbers, ...
        MissingRunNumbers, SessionImportComplete);

end

function txt = format_run_labels(runValues)

    if isempty(runValues)
        txt = "";
        return;
    end

    runValues = double(runValues);
    labels = strings(numel(runValues), 1);
    for i = 1:numel(runValues)
        if isnan(runValues(i))
            labels(i) = "no-run-label";
        else
            labels(i) = sprintf('%03d', runValues(i));
        end
    end
    txt = join(labels, ";");

end

function [ok, message] = validate_raw_session_output(setFolder, subj, sessionName, expectedRunCount)

    ok = false;
    message = "no_current_raw_set_found";
    rawSubFolders = unique({sprintf('sub-%d', subj), sprintf('sub-%02d', subj)}, 'stable');

    for i = 1:numel(rawSubFolders)
        rawFolder = fullfile(setFolder, rawSubFolders{i});
        if ~exist(rawFolder, 'dir')
            continue;
        end

        prefix = sprintf('%s_%s_EEG', rawSubFolders{i}, sessionName);
        sessionFile = fullfile(rawFolder, [prefix '.set']);
        recFiles = dir(fullfile(rawFolder, [prefix '_rec*.set']));
        recFiles = recFiles(~contains({recFiles.name}, '_old.set', 'IgnoreCase', true));

        if expectedRunCount > 1
            candidate = sessionFile;
            if exist(candidate, 'file') ~= 2
                message = "multiple_runs_expected_but_merged_session_set_missing";
                continue;
            end
        elseif exist(sessionFile, 'file') == 2
            candidate = sessionFile;
        elseif numel(recFiles) == 1
            candidate = fullfile(recFiles(1).folder, recFiles(1).name);
        else
            continue;
        end

        try
            [folder, base, ext] = fileparts(candidate);
            EEG = pop_loadset('filename', [base ext], 'filepath', folder);
            EEG = eeg_checkset(EEG);
            if EEG.nbchan <= 10 || EEG.pnts <= 0 || EEG.srate <= 0
                message = "raw_set_loaded_but_has_invalid_dimensions";
                continue;
            end
            ok = true;
            message = "OK";
            return;
        catch ME
            message = "raw_set_load_failed: " + string(ME.message);
        end
    end

end

function clean_bids_session_folder(bidsFolder, subj, sessionName)

    bidsSubFolder = sprintf('sub-%02d', subj);
    sessionFolder = fullfile(bidsFolder, bidsSubFolder, ['ses-' char(sessionName)]);

    if exist(sessionFolder, 'dir')

        fprintf('Deleting stale BIDS session folder:\n%s\n', sessionFolder);
        rmdir(sessionFolder, 's');

    else

        fprintf('No stale BIDS session folder found:\n%s\n', sessionFolder);

    end

end

function clean_raw_session_sets(setFolder, subj, sessionName)

    rawSubFolders = {sprintf('sub-%d', subj), sprintf('sub-%02d', subj)};

    for i = 1:numel(rawSubFolders)

        rawSubFolder = rawSubFolders{i};
        rawFolder = fullfile(setFolder, rawSubFolder);

        if ~exist(rawFolder, 'dir')
            continue;
        end

        prefix = sprintf('%s_%s_EEG', rawSubFolder, sessionName);

        setFiles = dir(fullfile(rawFolder, [prefix '*.set']));
        fdtFiles = dir(fullfile(rawFolder, [prefix '*.fdt']));

        allFiles = [setFiles; fdtFiles];

        if isempty(allFiles)

            fprintf('No stale raw set files found in:\n%s\n', rawFolder);

        else

            fprintf('Deleting stale raw set files in:\n%s\n', rawFolder);

            for k = 1:numel(allFiles)

                filePath = fullfile(allFiles(k).folder, allFiles(k).name);
                fprintf('  deleting %s\n', allFiles(k).name);
                delete(filePath);

            end

        end

    end

end

function backup_session_outputs(bidsFolder, setFolder, backupRoot, subj, sessionName, backupBids, backupRaw)

    if ~exist(backupRoot, 'dir')
        mkdir(backupRoot);
    end

    if backupBids
        bidsSubFolder = sprintf('sub-%02d', subj);
        sourceSession = fullfile(bidsFolder, bidsSubFolder, ['ses-' char(sessionName)]);
        backupSession = fullfile(backupRoot, 'BIDS', bidsSubFolder, ['ses-' char(sessionName)]);

        if exist(sourceSession, 'dir')
            mkdir(fileparts(backupSession));
            movefile(sourceSession, backupSession, 'f');
            fprintf('Previous BIDS session moved to safety backup:\n%s\n', backupSession);
        end
    end

    if backupRaw
        rawSubFolders = unique({sprintf('sub-%d', subj), sprintf('sub-%02d', subj)}, 'stable');
        for i = 1:numel(rawSubFolders)
            rawSubFolder = rawSubFolders{i};
            rawFolder = fullfile(setFolder, rawSubFolder);
            if ~exist(rawFolder, 'dir')
                continue;
            end

            prefix = sprintf('%s_%s_EEG', rawSubFolder, sessionName);
            files = [dir(fullfile(rawFolder, [prefix '*.set'])); ...
                     dir(fullfile(rawFolder, [prefix '*.fdt']))];
            if isempty(files)
                continue;
            end

            backupFolder = fullfile(backupRoot, 'RAW', rawSubFolder);
            mkdir(backupFolder);
            for k = 1:numel(files)
                movefile(fullfile(files(k).folder, files(k).name), ...
                    fullfile(backupFolder, files(k).name), 'f');
            end
            fprintf('Previous raw session files moved to safety backup:\n%s\n', backupFolder);
        end
    end

end

function restore_session_outputs(bidsFolder, setFolder, backupRoot, subj, sessionName)

    fprintf('Restoring previous outputs for subject %d session %s.\n', subj, sessionName);

    clean_bids_session_folder(bidsFolder, subj, sessionName);
    clean_raw_session_sets(setFolder, subj, sessionName);

    bidsSubFolder = sprintf('sub-%02d', subj);
    backupSession = fullfile(backupRoot, 'BIDS', bidsSubFolder, ['ses-' char(sessionName)]);
    targetSession = fullfile(bidsFolder, bidsSubFolder, ['ses-' char(sessionName)]);
    if exist(backupSession, 'dir')
        mkdir(fileparts(targetSession));
        movefile(backupSession, targetSession, 'f');
    end

    rawSubFolders = unique({sprintf('sub-%d', subj), sprintf('sub-%02d', subj)}, 'stable');
    for i = 1:numel(rawSubFolders)
        backupFolder = fullfile(backupRoot, 'RAW', rawSubFolders{i});
        if ~exist(backupFolder, 'dir')
            continue;
        end

        prefix = sprintf('%s_%s_EEG', rawSubFolders{i}, sessionName);
        files = [dir(fullfile(backupFolder, [prefix '*.set'])); ...
                 dir(fullfile(backupFolder, [prefix '*.fdt']))];
        if isempty(files)
            continue;
        end

        targetFolder = fullfile(setFolder, rawSubFolders{i});
        mkdir(targetFolder);
        for k = 1:numel(files)
            movefile(fullfile(files(k).folder, files(k).name), ...
                fullfile(targetFolder, files(k).name), 'f');
        end
    end

end

function discard_session_backup(backupRoot, subj, sessionName)

    bidsSubFolder = sprintf('sub-%02d', subj);
    backupSession = fullfile(backupRoot, 'BIDS', bidsSubFolder, ['ses-' char(sessionName)]);
    if exist(backupSession, 'dir')
        rmdir(backupSession, 's');
    end

    rawSubFolders = unique({sprintf('sub-%d', subj), sprintf('sub-%02d', subj)}, 'stable');
    for i = 1:numel(rawSubFolders)
        backupFolder = fullfile(backupRoot, 'RAW', rawSubFolders{i});
        if ~exist(backupFolder, 'dir')
            continue;
        end
        prefix = sprintf('%s_%s_EEG', rawSubFolders{i}, sessionName);
        files = [dir(fullfile(backupFolder, [prefix '*.set'])); ...
                 dir(fullfile(backupFolder, [prefix '*.fdt']))];
        for k = 1:numel(files)
            delete(fullfile(files(k).folder, files(k).name));
        end
    end

end

function auditTable = audit_raw_set_files(importTable, sessionCoverage, bidsFolder, setFolder, auditFile)

    T = importTable;

    T.DoImport = to_numeric_column(T.DoImport);
    T.BidsSubject = to_numeric_column(T.BidsSubject);
    T.BidsSession = string(T.BidsSession);

    if ismember('RunNumber', T.Properties.VariableNames)
        T.RunNumber = to_numeric_column(T.RunNumber);
    else
        T.RunNumber = nan(height(T), 1);
    end

    rows = find(T.DoImport == 1);

    if isempty(rows)
        error('No rows with DoImport = 1 found in import table.');
    end

    S = T(rows, {'BidsSubject', 'BidsSession'});
    S = unique(S, 'rows', 'stable');

    BidsSubject = [];
    BidsSession = strings(0, 1);
    RawSubjectFolder = strings(0, 1);
    RawFolder = strings(0, 1);
    BidsRunFiles = [];
    ImportTableRows = strings(0, 1);
    ImportRunNumbers = strings(0, 1);

    CurrentSessionSet = strings(0, 1);
    CurrentRecSets = strings(0, 1);
    OldSets = strings(0, 1);
    AllMatchingSets = strings(0, 1);
    SelectedRawSetPath = strings(0, 1);
    SelectedRawSetSignature = strings(0, 1);

    Status = strings(0, 1);
    Recommendation = strings(0, 1);
    ExpectedRunCount = [];
    SuccessfulRunCount = [];
    MissingRunNumbers = strings(0, 1);
    SessionImportComplete = false(0, 1);

    fprintf('\nRaw set folder:\n%s\n', setFolder);
    fprintf('BIDS folder:\n%s\n', bidsFolder);
    fprintf('Unique imported subject-session pairs: %d\n', height(S));

    for i = 1:height(S)

        subj = S.BidsSubject(i);
        sessionName = string(S.BidsSession(i));

        fprintf('\n------------------------------------------------------------\n');
        fprintf('Auditing %d / %d\n', i, height(S));
        fprintf('Subject: sub-%d\n', subj);
        fprintf('Session: %s\n', sessionName);

        tableRows = find(T.DoImport == 1 & ...
                         T.BidsSubject == subj & ...
                         T.BidsSession == sessionName);

        tableRowsText = join(string(tableRows), "; ");

        runNums = T.RunNumber(tableRows);
        runNums = runNums(~isnan(runNums));

        if isempty(runNums)
            runText = "";
        else
            runText = join(string(unique(runNums, 'stable')), "; ");
        end

        bidsSubFolder = sprintf('sub-%02d', subj);
        bidsSessionFolder = fullfile(bidsFolder, bidsSubFolder, ['ses-' char(sessionName)], 'eeg');

        bidsRuns = dir(fullfile(bidsSessionFolder, '*_eeg.vhdr'));
        nBidsRuns = numel(bidsRuns);

        rawSubFolder1 = sprintf('sub-%d', subj);
        rawSubFolder2 = sprintf('sub-%02d', subj);

        rawFolder1 = fullfile(setFolder, rawSubFolder1);
        rawFolder2 = fullfile(setFolder, rawSubFolder2);

        candidateFolders = {rawFolder1, rawFolder2};
        candidateLabels = {rawSubFolder1, rawSubFolder2};
        hasMatchingFiles = false(1, 2);
        for cf = 1:2
            if exist(candidateFolders{cf}, 'dir')
                candidatePrefix = sprintf('%s_%s_EEG', candidateLabels{cf}, sessionName);
                hasMatchingFiles(cf) = ~isempty(dir(fullfile(candidateFolders{cf}, [candidatePrefix '*.set'])));
            end
        end
        if strcmp(candidateFolders{1}, candidateFolders{2})
            hasMatchingFiles(2) = false;
        end

        multipleRawFolders = sum(hasMatchingFiles) > 1;
        selectedFolderIndex = find(hasMatchingFiles, 1, 'first');
        if isempty(selectedFolderIndex)
            selectedFolderIndex = 1;
        end
        rawFolder = candidateFolders{selectedFolderIndex};
        rawSubFolderUsed = candidateLabels{selectedFolderIndex};

        prefix = sprintf('%s_%s_EEG', rawSubFolderUsed, sessionName);

        sessionSetPattern = [prefix '.set'];
        recSetPattern     = [prefix '_rec*.set'];
        allSetPattern     = [prefix '*.set'];

        sessionSet = dir(fullfile(rawFolder, sessionSetPattern));
        recSetsAll = dir(fullfile(rawFolder, recSetPattern));
        allSets = dir(fullfile(rawFolder, allSetPattern));

        oldSetsFound = allSets(false);
        currentAllSets = allSets(false);

        for k = 1:numel(allSets)

            isOld = ~isempty(regexpi(allSets(k).name, '_old\.set$', 'once'));

            if isOld
                oldSetsFound(end+1) = allSets(k);
            else
                currentAllSets(end+1) = allSets(k);
            end

        end

        currentRecSets = recSetsAll(false);

        for k = 1:numel(recSetsAll)

            isOld = ~isempty(regexpi(recSetsAll(k).name, '_old\.set$', 'once'));

            if ~isOld
                currentRecSets(end+1) = recSetsAll(k);
            end

        end

        sessionSetText = files_to_text(sessionSet);
        currentRecText = files_to_text(currentRecSets);
        oldSetText     = files_to_text(oldSetsFound);
        allSetText     = files_to_text(allSets);

        selectedPath = "";

        coverageRow = find(sessionCoverage.BidsSubject == subj & ...
            sessionCoverage.BidsSession == sessionName, 1, 'first');

        if isempty(coverageRow)
            expectedRunCount = numel(tableRows);
            successfulRunCount = 0;
            missingRunNumbers = runText;
            sessionImportComplete = false;
        else
            expectedRunCount = sessionCoverage.ExpectedRunCount(coverageRow);
            successfulRunCount = sessionCoverage.SuccessfulRunCount(coverageRow);
            missingRunNumbers = sessionCoverage.MissingRunNumbers(coverageRow);
            sessionImportComplete = sessionCoverage.SessionImportComplete(coverageRow);
        end

        if multipleRawFolders

            thisStatus = "PROBLEM_duplicate_raw_subject_folders";
            thisRecommendation = "Matching session files exist in both sub-N and sub-0N raw folders. Resolve the duplicate folders before preprocessing.";

        elseif ~sessionImportComplete

            thisStatus = "PROBLEM_partial_session_missing_runs";
            thisRecommendation = "Do not preprocess. Not all enabled XDF runs were imported successfully. Missing runs: " + missingRunNumbers;

        elseif nBidsRuns ~= expectedRunCount

            thisStatus = "PROBLEM_bids_run_count_mismatch";
            thisRecommendation = sprintf('Do not preprocess. Expected %d BIDS run files but found %d.', expectedRunCount, nBidsRuns);

        elseif ~isempty(sessionSet)

            thisStatus = "OK_session_level_EEG_set";
            thisRecommendation = "Use *_EEG.set for preprocessing. This usually means runs were merged into one session-level set.";
            selectedPath = string(fullfile(sessionSet(1).folder, sessionSet(1).name));

        elseif isempty(sessionSet) && numel(currentRecSets) == 1 && expectedRunCount == 1

            thisStatus = "OK_single_recording_rec_set";
            thisRecommendation = "Use the non-old *_EEG_rec*.set for preprocessing. This usually means only one valid recording is available for this session.";
            selectedPath = string(fullfile(currentRecSets(1).folder, currentRecSets(1).name));

        elseif isempty(sessionSet) && numel(currentRecSets) == 1 && expectedRunCount > 1

            thisStatus = "PROBLEM_expected_multiple_runs_but_only_one_rec_set";
            thisRecommendation = sprintf(['Do not preprocess. Expected %d runs, but only one current recording-level ' ...
                '.set exists and no merged session-level *_EEG.set was found.'], expectedRunCount);

        elseif isempty(sessionSet) && numel(currentRecSets) > 1

            thisStatus = "PROBLEM_multiple_current_rec_sets_no_session_set";
            thisRecommendation = "Multiple current rec sets exist but no merged *_EEG.set. Check BIDS2SET conversion or merge valid rec files manually.";

        elseif isempty(sessionSet) && isempty(currentRecSets) && ~isempty(oldSetsFound)

            thisStatus = "PROBLEM_only_old_sets";
            thisRecommendation = "Only *_old.set files exist. This script will try pop_resample recovery for near-500 Hz old rec files.";

        else

            thisStatus = "PROBLEM_no_raw_set";
            thisRecommendation = "No matching raw .set file found. BIDS2SET did not create a usable raw EEGLAB set.";

        end

        fprintf('BIDS run files: %d\n', nBidsRuns);
        fprintf('Status: %s\n', thisStatus);

        BidsSubject(end+1, 1) = subj;
        BidsSession(end+1, 1) = sessionName;
        RawSubjectFolder(end+1, 1) = string(rawSubFolderUsed);
        RawFolder(end+1, 1) = string(rawFolder);
        BidsRunFiles(end+1, 1) = nBidsRuns;
        ImportTableRows(end+1, 1) = tableRowsText;
        ImportRunNumbers(end+1, 1) = runText;

        CurrentSessionSet(end+1, 1) = sessionSetText;
        CurrentRecSets(end+1, 1) = currentRecText;
        OldSets(end+1, 1) = oldSetText;
        AllMatchingSets(end+1, 1) = allSetText;
        SelectedRawSetPath(end+1, 1) = selectedPath;

        Status(end+1, 1) = thisStatus;
        Recommendation(end+1, 1) = thisRecommendation;
        ExpectedRunCount(end+1, 1) = expectedRunCount;
        SuccessfulRunCount(end+1, 1) = successfulRunCount;
        MissingRunNumbers(end+1, 1) = missingRunNumbers;
        SessionImportComplete(end+1, 1) = sessionImportComplete;
        SelectedRawSetSignature(end+1, 1) = compute_file_signature(selectedPath);

    end

    auditTable = table( ...
        BidsSubject, ...
        BidsSession, ...
        RawSubjectFolder, ...
        RawFolder, ...
        BidsRunFiles, ...
        ImportTableRows, ...
        ImportRunNumbers, ...
        CurrentSessionSet, ...
        CurrentRecSets, ...
        OldSets, ...
        AllMatchingSets, ...
        SelectedRawSetPath, ...
        Status, ...
        Recommendation, ...
        ExpectedRunCount, ...
        SuccessfulRunCount, ...
        MissingRunNumbers, ...
        SessionImportComplete, ...
        SelectedRawSetSignature);

    writetable(auditTable, auditFile);

    fprintf('\nRaw set audit saved to:\n%s\n', auditFile);

end

function repairLog = repair_only_old_raw_sets(auditTable, setFolder, repairLogFile, targetSrate, srateToleranceHz, minDurationSec)

    problemRows = find(auditTable.Status == "PROBLEM_only_old_sets");

    repairLog = table();

    fprintf('Only-old sessions found: %d\n', numel(problemRows));

    if isempty(problemRows)
        fprintf('No only-old raw set sessions. Nothing to repair.\n');
        return;
    end

    for i = 1:numel(problemRows)

        rowIdx = problemRows(i);

        subj = auditTable.BidsSubject(rowIdx);
        sessionName = string(auditTable.BidsSession(rowIdx));
        rawSubFolder = string(auditTable.RawSubjectFolder(rowIdx));
        rawFolder = string(auditTable.RawFolder(rowIdx));
        expectedRunCount = double(auditTable.ExpectedRunCount(rowIdx));

        if ~isfinite(expectedRunCount) || expectedRunCount < 1 || ...
                expectedRunCount ~= round(expectedRunCount)
            warning('Invalid expected run count in raw-set audit. Skipping automatic repair.');
            repairLog = [repairLog; make_repair_log_row(subj, sessionName, false, ...
                "invalid_expected_run_count", "", "")];
            continue;
        end

        fprintf('\n------------------------------------------------------------\n');
        fprintf('Repairing only-old session %d / %d\n', i, numel(problemRows));
        fprintf('Subject: %s\n', rawSubFolder);
        fprintf('Session: %s\n', sessionName);
        fprintf('Raw folder:\n%s\n', rawFolder);
        fprintf('Target raw sampling rate: %.2f Hz\n', targetSrate);
        fprintf('Srate tolerance: %.6f Hz\n', srateToleranceHz);
        fprintf('Minimum duration: %.2f sec\n', minDurationSec);
        fprintf('Expected run count: %d\n', expectedRunCount);

        if ~exist(rawFolder, 'dir')

            warning('Raw folder does not exist. Skipping.');

            repairLog = [repairLog; make_repair_log_row(subj, sessionName, false, ...
                "raw_folder_not_found", "", "")];

            continue;

        end

        prefix = sprintf('%s_%s_EEG', rawSubFolder, sessionName);

        oldRecPattern = [prefix '_rec*_old.set'];
        oldRecFiles = dir(fullfile(rawFolder, oldRecPattern));

        oldSessionPattern = [prefix '_old.set'];
        oldSessionFiles = dir(fullfile(rawFolder, oldSessionPattern));

        try

            STUDY = [];
            CURRENTSTUDY = 0;
            ALLEEG = [];
            CURRENTSET = [];
            EEG = [];

            skippedFiles = strings(0, 1);
            validRecNums = [];
            validSourceFiles = strings(0, 1);
            validSetCount = 0;

            if ~isempty(oldRecFiles)

                recNums = nan(numel(oldRecFiles), 1);

                for k = 1:numel(oldRecFiles)

                    tok = regexp(oldRecFiles(k).name, ...
                        '_rec(?<rec>\d+)_old\.set$', ...
                        'names', 'once');

                    if ~isempty(tok)
                        recNums(k) = str2double(tok.rec);
                    end

                end

                [~, order] = sort(recNums);
                oldRecFiles = oldRecFiles(order);
                recNums = recNums(order);

                fprintf('Old rec files found:\n');

                for k = 1:numel(oldRecFiles)
                    fprintf('  rec%d: %s\n', recNums(k), oldRecFiles(k).name);
                end

                for k = 1:numel(oldRecFiles)

                    EEG = pop_loadset( ...
                        'filename', oldRecFiles(k).name, ...
                        'filepath', char(rawFolder));

                    EEG = eeg_checkset(EEG);

                    fprintf('\nLoaded rec%d before resampling repair:\n', recNums(k));
                    fprintf('  file     = %s\n', oldRecFiles(k).name);
                    fprintf('  channels = %d\n', EEG.nbchan);
                    fprintf('  srate    = %.10f Hz\n', EEG.srate);
                    fprintf('  samples  = %d\n', EEG.pnts);
                    fprintf('  duration = %.6f sec\n', (EEG.pnts - 1) / double(EEG.srate));
                    fprintf('  events   = %d\n', numel(EEG.event));

                    [useThisEEG, EEG, skipReason] = repair_raw_eeg_by_resampling( ...
                        EEG, targetSrate, srateToleranceHz, minDurationSec);

                    if ~useThisEEG

                        fprintf('  SKIP rec%d: %s\n', recNums(k), skipReason);

                        skippedFiles(end+1, 1) = string(oldRecFiles(k).name) + " [" + string(skipReason) + "]";

                        continue;

                    end

                    fprintf('Loaded rec%d after resampling repair:\n', recNums(k));
                    fprintf('  channels = %d\n', EEG.nbchan);
                    fprintf('  srate    = %.10f Hz\n', EEG.srate);
                    fprintf('  samples  = %d\n', EEG.pnts);
                    fprintf('  duration = %.6f sec\n', (EEG.pnts - 1) / double(EEG.srate));
                    fprintf('  events   = %d\n', numel(EEG.event));

                    validSetCount = validSetCount + 1;
                    validRecNums(validSetCount, 1) = recNums(k);
                    validSourceFiles(validSetCount, 1) = string(oldRecFiles(k).name);

                    [ALLEEG, EEG, CURRENTSET] = eeg_store(ALLEEG, EEG, validSetCount);

                end

                if validSetCount == 0

                    warning('No valid old rec files could be repaired for this session.');

                    repairLog = [repairLog; make_repair_log_row(subj, sessionName, false, ...
                        "no_valid_old_rec_files_after_metadata_check", "", join(skippedFiles, "; "))];

                    continue;

                elseif validSetCount ~= expectedRunCount

                    warning(['Recovered old recording count does not match the expected run count. ' ...
                        'No current .set will be created. Expected %d, recovered %d.'], ...
                        expectedRunCount, validSetCount);

                    mismatchMessage = sprintf( ...
                        'recovered_recording_count_mismatch_expected_%d_got_%d', ...
                        expectedRunCount, validSetCount);

                    repairLog = [repairLog; make_repair_log_row(subj, sessionName, false, ...
                        string(mismatchMessage), "", join(skippedFiles, "; "))];

                    continue;

                elseif validSetCount == 1

                    EEG = ALLEEG(1);
                    EEG = eeg_checkset(EEG);

                    outputFilename = sprintf('%s_%s_EEG_rec%d.set', ...
                        rawSubFolder, sessionName, validRecNums(1));

                    fprintf('\nOnly one valid old rec file. Saving recovered current rec file:\n%s\n', ...
                        outputFilename);

                else

                    fprintf('\nMultiple valid old rec files. Merging into session-level EEG.set...\n');

                    EEG = pop_mergeset(ALLEEG, 1:validSetCount, 0);
                    EEG = eeg_checkset(EEG);

                    outputFilename = sprintf('%s_%s_EEG.set', rawSubFolder, sessionName);

                    fprintf('Saving recovered merged session file:\n%s\n', outputFilename);

                end

                EEG.etc.recovered_from_only_old_raw_sets = true;
                EEG.etc.recovered_datetime = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
                EEG.etc.recovered_source_old_files = validSourceFiles;
                EEG.etc.recovered_skipped_old_files = skippedFiles;
                EEG.etc.recovered_metadata_only_srate_normalization = false;
                EEG.etc.recovered_target_srate = targetSrate;
                EEG.etc.recovered_resample_method = "pop_resample";
                EEG.etc.recovered_srate_tolerance_hz = srateToleranceHz;
                EEG.etc.recovered_min_duration_sec = minDurationSec;
                EEG.etc.recovered_expected_run_count = expectedRunCount;
                EEG.etc.recovered_recording_count = validSetCount;

                pop_saveset(EEG, ...
                    'filename', outputFilename, ...
                    'filepath', char(rawFolder));

                outputPath = fullfile(rawFolder, outputFilename);

                if exist(outputPath, 'file')

                    fprintf('SUCCESS: recovered file created:\n%s\n', outputPath);

                    repairLog = [repairLog; make_repair_log_row(subj, sessionName, true, ...
                        "recovered_from_old_rec_files_pop_resampled", string(outputPath), join(skippedFiles, "; "))];

                else

                    warning('pop_saveset finished, but recovered output file was not found.');

                    repairLog = [repairLog; make_repair_log_row(subj, sessionName, false, ...
                        "save_finished_but_output_not_found", string(outputPath), join(skippedFiles, "; "))];

                end

            elseif ~isempty(oldSessionFiles)

                fprintf('Only old session-level file found. Loading and saving current session-level file.\n');

                oldFile = oldSessionFiles(1);

                EEG = pop_loadset( ...
                    'filename', oldFile.name, ...
                    'filepath', char(rawFolder));

                EEG = eeg_checkset(EEG);

                fprintf('\nLoaded old session-level file before resampling repair:\n');
                fprintf('  file     = %s\n', oldFile.name);
                fprintf('  channels = %d\n', EEG.nbchan);
                fprintf('  srate    = %.10f Hz\n', EEG.srate);
                fprintf('  samples  = %d\n', EEG.pnts);
                fprintf('  duration = %.6f sec\n', (EEG.pnts - 1) / double(EEG.srate));
                fprintf('  events   = %d\n', numel(EEG.event));

                [useThisEEG, EEG, skipReason] = repair_raw_eeg_by_resampling( ...
                    EEG, targetSrate, srateToleranceHz, minDurationSec);

                if ~useThisEEG

                    warning('Old session-level file is not valid for resampling repair: %s', skipReason);

                    repairLog = [repairLog; make_repair_log_row(subj, sessionName, false, ...
                        "old_session_file_failed_resample_check", "", string(oldFile.name) + " [" + string(skipReason) + "]")];

                    continue;

                end

                outputFilename = sprintf('%s_%s_EEG.set', rawSubFolder, sessionName);

                EEG.etc.recovered_from_only_old_raw_sets = true;
                EEG.etc.recovered_datetime = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
                EEG.etc.recovered_source_old_files = string(oldFile.name);
                EEG.etc.recovered_skipped_old_files = strings(0, 1);
                EEG.etc.recovered_metadata_only_srate_normalization = false;
                EEG.etc.recovered_target_srate = targetSrate;
                EEG.etc.recovered_resample_method = "pop_resample";
                EEG.etc.recovered_srate_tolerance_hz = srateToleranceHz;
                EEG.etc.recovered_min_duration_sec = minDurationSec;

                pop_saveset(EEG, ...
                    'filename', outputFilename, ...
                    'filepath', char(rawFolder));

                outputPath = fullfile(rawFolder, outputFilename);

                if exist(outputPath, 'file')

                    fprintf('SUCCESS: recovered file created:\n%s\n', outputPath);

                    repairLog = [repairLog; make_repair_log_row(subj, sessionName, true, ...
                        "recovered_from_old_session_file_pop_resampled", string(outputPath), "")];

                else

                    repairLog = [repairLog; make_repair_log_row(subj, sessionName, false, ...
                        "save_finished_but_output_not_found", string(outputPath), "")];

                end

            else

                warning('No old rec or old session files found, although audit said only-old.');

                repairLog = [repairLog; make_repair_log_row(subj, sessionName, false, ...
                    "no_old_files_found", "", "")];

            end

        catch ME

            warning('Repair failed for subject %d session %s:\n%s', subj, sessionName, ME.message);

            fprintf('\nFULL REPAIR ERROR REPORT:\n');
            fprintf('%s\n', getReport(ME, 'extended', 'hyperlinks', 'on'));

            repairLog = [repairLog; make_repair_log_row(subj, sessionName, false, ...
                string(ME.message), "", "")];

        end

        fclose all;

    end

    if ~isempty(repairLog)
        writetable(repairLog, repairLogFile);
    end

end

function [useThisEEG, EEG, reason] = repair_raw_eeg_by_resampling(EEG, targetSrate, srateToleranceHz, minDurationSec)

    useThisEEG = false;
    reason = "";

    if isempty(EEG)

        reason = "empty_EEG";
        return;

    end

    if ~isfield(EEG, 'srate') || isempty(EEG.srate) || isnan(double(EEG.srate)) || double(EEG.srate) <= 0

        reason = "invalid_EEG_srate";
        return;

    end

    if ~isfield(EEG, 'pnts') || isempty(EEG.pnts) || EEG.pnts <= 0

        reason = "invalid_EEG_sample_count";
        return;

    end

    if ~isfield(EEG, 'nbchan') || isempty(EEG.nbchan) || EEG.nbchan <= 10

        reason = "invalid_EEG_channel_count";
        return;

    end

    if ~exist('pop_resample', 'file')

        reason = "pop_resample_not_found";
        return;

    end

    oldSrate = double(EEG.srate);
    oldPnts = double(EEG.pnts);
    oldXmin = double(EEG.xmin);
    oldXmax = double(EEG.xmax);
    oldDurationSec = (oldPnts - 1) / oldSrate;

    srateDiff = abs(oldSrate - targetSrate);

    if srateDiff > srateToleranceHz

        reason = sprintf('srate_too_far_from_target_old_%.10f_target_%.2f_tolerance_%.3f', ...
            oldSrate, targetSrate, srateToleranceHz);
        return;

    end

    if oldDurationSec < minDurationSec

        reason = sprintf('duration_too_short_%.6f_sec', oldDurationSec);
        return;

    end

    EEG.etc.repair_original_srate = oldSrate;
    EEG.etc.repair_original_pnts = oldPnts;
    EEG.etc.repair_original_xmin = oldXmin;
    EEG.etc.repair_original_xmax = oldXmax;
    EEG.etc.repair_original_duration_sec = oldDurationSec;
    EEG.etc.repair_target_srate = targetSrate;
    EEG.etc.repair_srate_tolerance_hz = srateToleranceHz;

    if srateDiff < 1e-9

        fprintf('  EEG.srate is already %.10f Hz. No resampling needed.\n', oldSrate);

        EEG.etc.repair_resampled_to_target_srate = false;
        EEG.etc.repair_resample_method = "none_already_target_srate";

        EEG = eeg_checkset(EEG);

    else

        fprintf('  EEG.srate %.10f Hz is within %.3f Hz of target %.2f Hz.\n', ...
            oldSrate, srateToleranceHz, targetSrate);
        fprintf('  Resampling with pop_resample. This changes the sample grid; it is NOT metadata-only.\n');

        EEG = pop_resample(EEG, targetSrate);
        EEG = eeg_checkset(EEG);

        EEG.etc.repair_resampled_to_target_srate = true;
        EEG.etc.repair_resample_method = "pop_resample";

    end

    newSrate = double(EEG.srate);
    newPnts = double(EEG.pnts);
    newDurationSec = (newPnts - 1) / newSrate;

    EEG.etc.repair_new_srate = newSrate;
    EEG.etc.repair_new_pnts = newPnts;
    EEG.etc.repair_new_xmin = double(EEG.xmin);
    EEG.etc.repair_new_xmax = double(EEG.xmax);
    EEG.etc.repair_new_duration_sec = newDurationSec;
    EEG.etc.repair_duration_difference_sec = newDurationSec - oldDurationSec;

    if abs(newSrate - targetSrate) > 1e-6

        reason = sprintf('resample_failed_new_srate_%.10f_target_%.2f', newSrate, targetSrate);
        return;

    end

    if newDurationSec < minDurationSec

        reason = sprintf('resampled_duration_too_short_%.6f_sec', newDurationSec);
        return;

    end

    fprintf('  Repair result:\n');
    fprintf('    old srate    = %.10f Hz\n', oldSrate);
    fprintf('    new srate    = %.10f Hz\n', newSrate);
    fprintf('    old samples  = %.0f\n', oldPnts);
    fprintf('    new samples  = %.0f\n', newPnts);
    fprintf('    old duration = %.6f sec\n', oldDurationSec);
    fprintf('    new duration = %.6f sec\n', newDurationSec);
    fprintf('    duration diff = %.9f sec\n', newDurationSec - oldDurationSec);

    useThisEEG = true;

    if srateDiff < 1e-9
        reason = "OK_already_target_srate";
    else
        reason = "OK_pop_resampled";
    end

end

function logRow = make_repair_log_row(subj, sessionName, successFlag, messageText, outputPath, skippedFiles)

    logRow = table( ...
        subj, ...
        string(sessionName), ...
        logical(successFlag), ...
        string(messageText), ...
        string(outputPath), ...
        string(skippedFiles), ...
        'VariableNames', {'BidsSubject', 'BidsSession', 'Success', ...
                          'Message', 'OutputPath', 'SkippedOldFiles'} ...
    );

end

function importTable = write_raw_status_to_import_table(importTable, auditTable)

    importTable = ensure_string_column(importTable, 'RawSetStatus');
    importTable = ensure_string_column(importTable, 'RawSetPath');
    importTable = ensure_string_column(importTable, 'RawSetRecommendation');
    importTable = ensure_numeric_optional_column(importTable, 'RecommendedDoPreprocess');
    importTable = ensure_string_column(importTable, 'RawSetSignature');
    importTable = ensure_numeric_optional_column(importTable, 'RawSetChanged');
    importTable = ensure_string_column(importTable, 'RawImportDate');

    importTable.RawSetSignature(ismissing(importTable.RawSetSignature)) = "";
    importTable.RawImportDate(ismissing(importTable.RawImportDate)) = "";

    previousSignature = importTable.RawSetSignature;

    importTable.DoImport = to_numeric_column(importTable.DoImport);
    importTable.BidsSubject = to_numeric_column(importTable.BidsSubject);
    importTable.BidsSession = string(importTable.BidsSession);
    if ismember('DoPreprocess', importTable.Properties.VariableNames)
        importTable.DoPreprocess = to_numeric_column(importTable.DoPreprocess);
    end

    importTable.RawSetStatus(:) = "";
    importTable.RawSetPath(:) = "";
    importTable.RawSetRecommendation(:) = "";
    importTable.RecommendedDoPreprocess(:) = 0;
    importTable.RawSetChanged(:) = 0;

    for i = 1:height(auditTable)

        subj = auditTable.BidsSubject(i);
        sessionName = string(auditTable.BidsSession(i));

        rows = find(importTable.DoImport == 1 & ...
                    importTable.BidsSubject == subj & ...
                    importTable.BidsSession == sessionName);

        if isempty(rows)
            continue;
        end

        importTable.RawSetStatus(rows) = auditTable.Status(i);
        importTable.RawSetPath(rows) = auditTable.SelectedRawSetPath(i);
        importTable.RawSetRecommendation(rows) = auditTable.Recommendation(i);
        importTable.RawSetSignature(rows) = auditTable.SelectedRawSetSignature(i);
        importTable.RawImportDate(rows) = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

        signatureChanged = any(previousSignature(rows) ~= ...
            auditTable.SelectedRawSetSignature(i));
        rawNotUsable = ~startsWith(auditTable.Status(i), "OK_");

        if signatureChanged || rawNotUsable
            importTable = invalidate_downstream_columns(importTable, rows);
            importTable.RawSetChanged(rows) = 1;
        end

        if startsWith(auditTable.Status(i), "OK_")
            importTable.RecommendedDoPreprocess(rows(1)) = 1;
            if signatureChanged && ismember('DoPreprocess', importTable.Properties.VariableNames)
                importTable.DoPreprocess(rows) = 0;
                importTable.DoPreprocess(rows(1)) = 1;
            end
        else
            importTable.RecommendedDoPreprocess(rows) = 0;
            if ismember('DoPreprocess', importTable.Properties.VariableNames)
                importTable.DoPreprocess(rows) = 0;
            end
        end

    end

end

function signature = compute_file_signature(filePath)

    signature = "";
    filePath = string(filePath);

    if strlength(strtrim(filePath)) == 0 || exist(char(filePath), 'file') ~= 2
        return;
    end

    info = dir(char(filePath));
    signature = string(info.bytes) + "|" + compose('%.15g', info.datenum);

    [folder, base, ext] = fileparts(char(filePath));
    if strcmpi(ext, '.set')
        fdtInfo = dir(fullfile(folder, [base '.fdt']));
        if ~isempty(fdtInfo)
            signature = signature + "|fdt=" + string(fdtInfo.bytes) + ...
                "|" + compose('%.15g', fdtInfo.datenum);
        end
    end

end

function T = invalidate_downstream_columns(T, rows)

    prefixes = { ...
        'DoPreprocess', 'ProcessingSubject', 'ImportedSetPath', ...
        'PreprocessedSetPath', 'Preprocessing', 'DoQC', ...
        'DoAMICA', 'AMICA', 'DipfittedSetPath', ...
        'PreprocessedICASetPath', 'CleanedICASetPath', ...
        'DoICAQC', 'ICAQC', 'AnalysisReady' ...
    };

    names = T.Properties.VariableNames;

    for c = 1:numel(names)
        name = names{c};
        shouldClear = false;
        for p = 1:numel(prefixes)
            if startsWith(name, prefixes{p})
                shouldClear = true;
                break;
            end
        end

        if ~shouldClear
            continue;
        end

        x = T.(name);
        if isstring(x)
            x(rows,:) = "";
        elseif isnumeric(x)
            x(rows,:) = NaN;
        elseif islogical(x)
            x(rows,:) = false;
        elseif isdatetime(x)
            x(rows,:) = NaT;
        elseif iscell(x)
            x(rows,:) = {[]};
        end
        T.(name) = x;
    end

end

function T = ensure_string_column(T, columnName)

    if ~ismember(columnName, T.Properties.VariableNames)
        T.(columnName) = strings(height(T), 1);
    else
        if ~isstring(T.(columnName))
            T.(columnName) = string(T.(columnName));
        end
    end

    T.(columnName)(ismissing(T.(columnName))) = "";

end

function T = ensure_numeric_optional_column(T, columnName)

    if ~ismember(columnName, T.Properties.VariableNames)
        T.(columnName) = zeros(height(T), 1);
    else
        T.(columnName) = to_numeric_column(T.(columnName));
    end

end

function txt = files_to_text(files)

    if isempty(files)
        txt = "";
        return;
    end

    names = strings(numel(files), 1);

    for i = 1:numel(files)
        names(i) = string(files(i).name);
    end

    txt = join(names, "; ");

end

function print_audit_summary(auditTable, labelText)

    fprintf('\n============================================================\n');
    fprintf('RAW SET AUDIT SUMMARY: %s\n', labelText);
    fprintf('============================================================\n');

    uniqueStatus = unique(auditTable.Status, 'stable');

    for i = 1:numel(uniqueStatus)
        thisStatus = uniqueStatus(i);
        n = sum(auditTable.Status == thisStatus);
        fprintf('  %-60s %d\n', thisStatus, n);
    end

    problemRows = contains(auditTable.Status, "PROBLEM");

    fprintf('\nProblem sessions:\n');

    if any(problemRows)
        disp(auditTable(problemRows, {'BidsSubject', 'BidsSession', 'BidsRunFiles', 'Status', 'Recommendation'}));
    else
        fprintf('  None.\n');
    end

end
