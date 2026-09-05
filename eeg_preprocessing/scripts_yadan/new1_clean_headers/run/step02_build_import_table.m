% GOAL
%   Build the run-level BeMoBIL import-control table from the structural XDF
%   EEG/GRF audit generated in Step 01.
%
% INPUT
%   output_data/xdf_file_stream_summary.csv
%   output_data/xdf_stream_detail_table.csv
%
% APPROACH
%   1. Keep every XDF containing a real EEG stream visible in the table.
%   2. Resolve XDF paths against the current raw-data root.
%   3. Select the usable EEG/GRF stream metadata for each recording.
%   4. Apply the configured run, backup-file, non-walking, EEG, and GRF gates.
%   5. Preserve a manual DoImport decision only when source identity is unchanged.
%
% OUTPUT
%   output_data/bemobil_import_table.csv
%
% USED BY
%   Step 03 GRF/EEG subject processing and later EEG import/preprocessing.

clear;
clc;

%% Load paths and Step 01-02 configuration

scriptsRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(scriptsRoot, '-begin');
addpath(fullfile(scriptsRoot, 'config'), '-begin');

P = project_paths();
cfg = config_step01_02_xdf_import();

summaryFile = P.summaryFile;
detailFile = P.detailFile;
importTableFile = P.importTableFile;
rawDataFolder = P.rawDataFolder;

if ~isfile(summaryFile)
    error( ...
        'Step 01 summary table not found:\n%s\nRun step01_check_xdf_streams.m first.', ...
        summaryFile);
end

if ~isfile(detailFile)
    error( ...
        'Step 01 stream-detail table not found:\n%s\nRun step01_check_xdf_streams.m first.', ...
        detailFile);
end

%% Read CSV tables

optsSummary = detectImportOptions(summaryFile, ...
    'FileType', 'text', ...
    'Delimiter', ',', ...
    'VariableNamingRule', 'preserve');

optsDetail = detectImportOptions(detailFile, ...
    'FileType', 'text', ...
    'Delimiter', ',', ...
    'VariableNamingRule', 'preserve');

fileSummary  = readtable(summaryFile, optsSummary);
streamDetail = readtable(detailFile, optsDetail);

fprintf('Loaded file summary table: %d rows\n', height(fileSummary));
fprintf('Loaded stream detail table: %d rows\n', height(streamDetail));

fprintf('\nFile summary column names:\n');
disp(fileSummary.Properties.VariableNames');

fprintf('\nStream detail column names:\n');
disp(streamDetail.Properties.VariableNames');

%% Make sure required columns exist

requiredSummaryColumns = {'FileIndex', 'FileName', 'FullPath', ...
                          'HasRealEEG', 'HasUsableEEG', ...
                          'FileEEGQualityStatus', 'FileEEGQualityReason', ...
                          'HasGRFStream', 'HasUsableGRF', ...
                          'FileGRFQualityStatus', 'FileGRFQualityReason'};

requiredDetailColumns = {'FileIndex', 'FileName', 'FullPath', 'StreamIndex', ...
                         'StreamName', 'StreamType', 'NominalSrate', ...
                         'ChannelCount', 'IsRealEEG', 'IsUsableEEG', ...
                         'IsGRFCandidate', 'IsUsableGRF', ...
                         'NDataSamples', 'NTimeStamps', 'DurationSec', ...
                         'EffectiveSrate', 'MaxDtSec', ...
                         'EEGQualityStatus', 'EEGQualityReason', ...
                         'GRFQualityStatus', 'GRFQualityReason'};

check_required_columns(fileSummary, requiredSummaryColumns, 'file summary table');
check_required_columns(streamDetail, requiredDetailColumns, 'stream detail table');

%% Convert important columns

fileSummary.FileIndex = to_numeric_column(fileSummary.FileIndex);
streamDetail.FileIndex = to_numeric_column(streamDetail.FileIndex);
streamDetail.StreamIndex = to_numeric_column(streamDetail.StreamIndex);

fileSummary.HasRealEEG   = to_logical_column(fileSummary.HasRealEEG);
fileSummary.HasUsableEEG = to_logical_column(fileSummary.HasUsableEEG);
fileSummary.HasGRFStream = to_logical_column(fileSummary.HasGRFStream);
fileSummary.HasUsableGRF = to_logical_column(fileSummary.HasUsableGRF);
streamDetail.IsRealEEG   = to_logical_column(streamDetail.IsRealEEG);
streamDetail.IsUsableEEG = to_logical_column(streamDetail.IsUsableEEG);
streamDetail.IsGRFCandidate = to_logical_column(streamDetail.IsGRFCandidate);
streamDetail.IsUsableGRF = to_logical_column(streamDetail.IsUsableGRF);

%% Convert text columns

fileSummary.FileName = string(fileSummary.FileName);
fileSummary.FullPath = string(fileSummary.FullPath);
fileSummary.FileEEGQualityStatus = string(fileSummary.FileEEGQualityStatus);
fileSummary.FileEEGQualityReason = string(fileSummary.FileEEGQualityReason);
fileSummary.FileGRFQualityStatus = string(fileSummary.FileGRFQualityStatus);
fileSummary.FileGRFQualityReason = string(fileSummary.FileGRFQualityReason);

streamDetail.FileName = string(streamDetail.FileName);
streamDetail.FullPath = string(streamDetail.FullPath);
streamDetail.StreamName = string(streamDetail.StreamName);
streamDetail.StreamType = string(streamDetail.StreamType);
streamDetail.NominalSrate = string(streamDetail.NominalSrate);
streamDetail.ChannelCount = string(streamDetail.ChannelCount);

streamDetail.EEGQualityStatus = string(streamDetail.EEGQualityStatus);
streamDetail.EEGQualityReason = string(streamDetail.EEGQualityReason);
streamDetail.GRFQualityStatus = string(streamDetail.GRFQualityStatus);
streamDetail.GRFQualityReason = string(streamDetail.GRFQualityReason);

%% Prepare output arrays

DoImport          = [];
XdfPath           = strings(0, 1);
FileName          = strings(0, 1);
RawSubjectFolder  = strings(0, 1);
RawDayFolder      = strings(0, 1);
RawSessionFolder  = strings(0, 1);
BidsSubject       = [];
BidsSession       = strings(0, 1);
Task              = strings(0, 1);
RunNumber         = strings(0, 1);
ExtraTag          = strings(0, 1);
EEGStreamName     = strings(0, 1);
NominalSrate      = strings(0, 1);
ChannelCount      = strings(0, 1);

HasUsableEEG      = [];
SelectedStreamIndex = [];
EEGQualityStatus  = strings(0, 1);
EEGQualityReason  = strings(0, 1);
DurationSec       = [];
EffectiveSrate    = [];
MaxDtSec          = [];
NDataSamples      = [];
NTimeStamps       = [];

HasGRFStream      = [];
HasUsableGRF      = [];
SelectedGRFStreamIndex = [];
GRFStreamName     = strings(0, 1);
GRFNominalSrate   = strings(0, 1);
GRFChannelCount   = strings(0, 1);
GRFQualityStatus  = strings(0, 1);
GRFQualityReason  = strings(0, 1);
GRFDurationSec    = [];
GRFEffectiveSrate = [];
GRFMaxDtSec       = [];
GRFNDataSamples   = [];
GRFNTimeStamps    = [];

%% Build import table from files with real EEG streams

eegRows = find(fileSummary.HasRealEEG);

fprintf('\nFound %d files with real EEG streams in summary table.\n', numel(eegRows));

if isempty(eegRows)
    error([ ...
        'The XDF QC summary contains zero files with real EEG.' newline ...
        'No import table was written.' newline newline ...
        'Correct rawDataFolder in project_paths.m and rerun ' ...
        'step01_check_xdf_streams.m before running this script.']);
end

nRebasedXdfPaths = 0;

for k = 1:numel(eegRows)

    r = eegRows(k);

    thisFileIndex = fileSummary.FileIndex(r);
    thisFileName  = string(fileSummary.FileName(r));
    thisFullPath  = string(fileSummary.FullPath(r));
    thisHasUsableEEG = logical(fileSummary.HasUsableEEG(r));
    thisHasGRFStream = logical(fileSummary.HasGRFStream(r));
    thisHasUsableGRF = logical(fileSummary.HasUsableGRF(r));
    thisFileGRFQualityStatus = ...
        string(fileSummary.FileGRFQualityStatus(r));
    thisFileGRFQualityReason = ...
        string(fileSummary.FileGRFQualityReason(r));

    xdfPathChar = char(thisFullPath);

    %% Parse raw folder information from full path

    % Example path:
    % E:\...\raw_data_PilotTest2\Sub-P2_1\day2\data\ses-Exo1_sport\eeg\xxx.xdf

    pathTok = regexp(xdfPathChar, ...
        '[\\/](?<rawSubject>Sub-P\d+_\d+)[\\/](?<rawDay>day\d+)[\\/]data[\\/](?<rawSession>ses-[^\\/]+)[\\/]eeg[\\/]', ...
        'names', 'once');

    if isempty(pathTok)
        error(['Could not parse a real-EEG XDF path:\n%s\n' ...
            'No import table was written. Fix the path schema or update the path regexp explicitly.'], ...
            xdfPathChar);
    end

    rawSubject = string(pathTok.rawSubject);
    rawDay     = string(pathTok.rawDay);
    rawSession = string(pathTok.rawSession);

    %% Resolve the XDF below the current raw-data root

    resolvedXdfPath = hipexo.resolve_current_xdf_path( ...
        thisFullPath, ...
        rawDataFolder, ...
        rawSubject, ...
        rawDay, ...
        rawSession, ...
        thisFileName);

    if resolvedXdfPath ~= thisFullPath
        nRebasedXdfPaths = nRebasedXdfPaths + 1;
    end

    %% Parse pilot number and subject number from Sub-P2_1

    subjTok = regexp(char(rawSubject), ...
        'Sub-P(?<pilot>\d+)_(?<subject>\d+)', ...
        'names', 'once');

    if isempty(subjTok)
        error('Could not parse subject folder for a real-EEG XDF: %s', rawSubject);
    end

    pilotNumber = subjTok.pilot;
    subjectNumber = str2double(subjTok.subject);

    if isnan(subjectNumber)
        error('Invalid subject number for a real-EEG XDF: %s', rawSubject);
    end

    %% Create BIDS subject and session labels

    % Use the parsed subject number as the BIDS subject ID:
    %   Sub-P2_1 -> subject 1
    %   Sub-P2_3 -> subject 3
    bidsSubject = subjectNumber;

    % Put raw source information into session label:
    %   Sub-P2_1 + day2 + ses-Exo1_sport
    %   -> Pilot2p1day2sesExo1Sport
    %
    % RunNumber is stored separately and passed to bemobil_xdf2bids as config.run.
    pilotLabel = "Pilot" + string(pilotNumber) + "p" + string(subjectNumber);
    sessionLabel = pilotLabel + rawDay + hipexo.make_bids_label(rawSession);

    %% Parse task from file name

    taskTok = regexp(char(thisFileName), ...
        '_task-(?<task>[A-Za-z0-9]+)', ...
        'names', 'once');

    if isempty(taskTok)
        taskLabel = "Default";
    else
        taskLabel = string(taskTok.task);
    end

    %% Parse run number from file name

    runTok = regexp(char(thisFileName), ...
        '_run-(?<run>\d+)', ...
        'names', 'once');

    if isempty(runTok)
        runLabel = "";
    else
        runLabel = string(runTok.run);
    end

    %% Find selected EEG stream for this file

    usableStreamRows = find(streamDetail.FileIndex == thisFileIndex & ...
                            streamDetail.IsRealEEG & ...
                            streamDetail.IsUsableEEG);

    realStreamRows = find(streamDetail.FileIndex == thisFileIndex & ...
                          streamDetail.IsRealEEG);

    exactUsableRows = usableStreamRows( ...
        streamDetail.StreamName(usableStreamRows) == cfg.eeg.streamName);

    if ~isempty(exactUsableRows)
        selectedStreamRow = exactUsableRows(1);
    elseif ~isempty(usableStreamRows)
        selectedStreamRow = usableStreamRows(1);
    elseif ~isempty(realStreamRows)
        selectedStreamRow = realStreamRows(1);
    else
        warning('No real EEG stream found in detail table. Skipping:\n%s', thisFullPath);
        continue;
    end

    eegStream = string(streamDetail.StreamName(selectedStreamRow));
    srate     = string(streamDetail.NominalSrate(selectedStreamRow));
    nChan     = string(streamDetail.ChannelCount(selectedStreamRow));

    selectedStreamIndex = streamDetail.StreamIndex(selectedStreamRow);

    if ismember('DurationSec', streamDetail.Properties.VariableNames)
        thisDurationSec = to_scalar_double(streamDetail.DurationSec(selectedStreamRow));
    else
        thisDurationSec = NaN;
    end

    if ismember('EffectiveSrate', streamDetail.Properties.VariableNames)
        thisEffectiveSrate = to_scalar_double(streamDetail.EffectiveSrate(selectedStreamRow));
    else
        thisEffectiveSrate = NaN;
    end

    if ismember('MaxDtSec', streamDetail.Properties.VariableNames)
        thisMaxDtSec = to_scalar_double(streamDetail.MaxDtSec(selectedStreamRow));
    else
        thisMaxDtSec = NaN;
    end

    if ismember('NDataSamples', streamDetail.Properties.VariableNames)
        thisNDataSamples = to_scalar_double(streamDetail.NDataSamples(selectedStreamRow));
    else
        thisNDataSamples = NaN;
    end

    if ismember('NTimeStamps', streamDetail.Properties.VariableNames)
        thisNTimeStamps = to_scalar_double(streamDetail.NTimeStamps(selectedStreamRow));
    else
        thisNTimeStamps = NaN;
    end

    thisQualityStatus = string(streamDetail.EEGQualityStatus(selectedStreamRow));
    thisQualityReason = string(streamDetail.EEGQualityReason(selectedStreamRow));

    if strlength(thisQualityStatus) == 0
        if thisHasUsableEEG
            thisQualityStatus = "OK";
            thisQualityReason = "usable_eeg_stream_found";
        else
            thisQualityStatus = "BAD_unknown";
            thisQualityReason = "no_usable_eeg_stream_found";
        end
    end

    %% Find the GRF stream in the same XDF

    grfStreamRows = find( ...
        streamDetail.FileIndex == thisFileIndex & ...
        streamDetail.IsGRFCandidate);

    selectedGRFStreamIndex = NaN;
    grfStream = "";
    grfNominalSrate = "";
    grfChannelCount = "";
    thisGRFDurationSec = NaN;
    thisGRFEffectiveSrate = NaN;
    thisGRFMaxDtSec = NaN;
    thisGRFNDataSamples = NaN;
    thisGRFNTimeStamps = NaN;
    thisGRFQualityStatus = thisFileGRFQualityStatus;
    thisGRFQualityReason = thisFileGRFQualityReason;

    if ~isempty(grfStreamRows)

        exactGRFRows = grfStreamRows( ...
            strcmpi(streamDetail.StreamName(grfStreamRows), cfg.grf.streamName));

        if ~isempty(exactGRFRows)
            selectedGRFRow = exactGRFRows(1);
        else
            selectedGRFRow = grfStreamRows(1);
        end

        selectedGRFStreamIndex = ...
            streamDetail.StreamIndex(selectedGRFRow);

        grfStream = ...
            string(streamDetail.StreamName(selectedGRFRow));

        grfNominalSrate = ...
            string(streamDetail.NominalSrate(selectedGRFRow));

        grfChannelCount = ...
            string(streamDetail.ChannelCount(selectedGRFRow));

        thisGRFDurationSec = ...
            to_scalar_double(streamDetail.DurationSec(selectedGRFRow));

        thisGRFEffectiveSrate = ...
            to_scalar_double(streamDetail.EffectiveSrate(selectedGRFRow));

        thisGRFMaxDtSec = ...
            to_scalar_double(streamDetail.MaxDtSec(selectedGRFRow));

        thisGRFNDataSamples = ...
            to_scalar_double(streamDetail.NDataSamples(selectedGRFRow));

        thisGRFNTimeStamps = ...
            to_scalar_double(streamDetail.NTimeStamps(selectedGRFRow));

        % Use stream-level status when exactly one GRF candidate is present.
        % Multiple candidates retain the file-level multiple-stream status.
        if numel(grfStreamRows) == 1
            thisGRFQualityStatus = ...
                string(streamDetail.GRFQualityStatus(selectedGRFRow));

            thisGRFQualityReason = ...
                string(streamDetail.GRFQualityReason(selectedGRFRow));
        end
    end

    if strlength(thisGRFQualityStatus) == 0

        if thisHasUsableGRF
            thisGRFQualityStatus = "OK";
            thisGRFQualityReason = "usable_GRF_stream_found";

        elseif thisHasGRFStream
            thisGRFQualityStatus = "BAD_unknown";
            thisGRFQualityReason = "GRF_stream_failed_for_an_unknown_reason";

        else
            thisGRFQualityStatus = "NO_GRF";
            thisGRFQualityReason = "no_GRF_candidate_stream_found";
        end
    end

    %% Decide whether to import by default

    % Keep backup XDF files visible in the table but disable them by default.
    % Match only filename suffixes such as _old.xdf, _old1.xdf, _old2.xdf.
    isOldFile = ~isempty(regexpi( ...
        char(thisFileName), ...
        char(cfg.import.oldFileRegex), ...
        'once'));

    runNumberValue = str2double(runLabel);

    isAllowedRun = isfinite(runNumberValue) && ...
        ismember(runNumberValue, cfg.import.allowedRunNumbers);

    isNonWalking = any(contains( ...
        lower(resolvedXdfPath), ...
        lower(cfg.import.nonWalkingPathWords)));

    if isOldFile

        doImportFlag = 0;

        if strlength(thisQualityStatus) > 0
            extraTag = "old_file_default_skip;" + thisQualityStatus;
        else
            extraTag = "old_file_default_skip";
        end

    elseif ~isAllowedRun

        doImportFlag = 0;

        if strlength(thisQualityStatus) > 0
            extraTag = "run_not_001_or_002_default_skip;" + ...
                thisQualityStatus;
        else
            extraTag = "run_not_001_or_002_default_skip";
        end

    elseif isNonWalking

        doImportFlag = 0;
        extraTag = "non_walking_or_calibration_default_skip";

    elseif eegStream ~= cfg.eeg.streamName

        doImportFlag = 0;
        extraTag = "unexpected_eeg_stream_default_skip;" + thisQualityStatus;

    elseif ~thisHasUsableEEG

        doImportFlag = 0;
        extraTag = "failed_eeg_gate;" + thisQualityStatus;

    elseif ~thisHasGRFStream

        doImportFlag = 0;
        extraTag = "failed_grf_gate;NO_GRF";

    elseif ~thisHasUsableGRF

        doImportFlag = 0;
        extraTag = "failed_grf_gate;" + thisGRFQualityStatus;

    else

        doImportFlag = 1;

        if startsWith(thisQualityStatus, "WARNING")
            extraTag = thisQualityStatus;
        else
            extraTag = "";
        end
    end

    %% Append one row

    DoImport(end+1, 1)            = doImportFlag;
    XdfPath(end+1, 1)             = resolvedXdfPath;
    FileName(end+1, 1)            = thisFileName;
    RawSubjectFolder(end+1, 1)    = rawSubject;
    RawDayFolder(end+1, 1)        = rawDay;
    RawSessionFolder(end+1, 1)    = rawSession;
    BidsSubject(end+1, 1)         = bidsSubject;
    BidsSession(end+1, 1)         = sessionLabel;
    Task(end+1, 1)                = taskLabel;
    RunNumber(end+1, 1)           = runLabel;
    ExtraTag(end+1, 1)            = extraTag;
    EEGStreamName(end+1, 1)       = eegStream;
    NominalSrate(end+1, 1)        = srate;
    ChannelCount(end+1, 1)        = nChan;

    HasUsableEEG(end+1, 1)        = thisHasUsableEEG;
    SelectedStreamIndex(end+1, 1) = selectedStreamIndex;
    EEGQualityStatus(end+1, 1)    = thisQualityStatus;
    EEGQualityReason(end+1, 1)    = thisQualityReason;
    DurationSec(end+1, 1)         = thisDurationSec;
    EffectiveSrate(end+1, 1)      = thisEffectiveSrate;
    MaxDtSec(end+1, 1)            = thisMaxDtSec;
    NDataSamples(end+1, 1)        = thisNDataSamples;
    NTimeStamps(end+1, 1)         = thisNTimeStamps;

    HasGRFStream(end+1, 1)        = thisHasGRFStream;
    HasUsableGRF(end+1, 1)        = thisHasUsableGRF;
    SelectedGRFStreamIndex(end+1, 1) = selectedGRFStreamIndex;
    GRFStreamName(end+1, 1)       = grfStream;
    GRFNominalSrate(end+1, 1)     = grfNominalSrate;
    GRFChannelCount(end+1, 1)     = grfChannelCount;
    GRFQualityStatus(end+1, 1)    = thisGRFQualityStatus;
    GRFQualityReason(end+1, 1)    = thisGRFQualityReason;
    GRFDurationSec(end+1, 1)      = thisGRFDurationSec;
    GRFEffectiveSrate(end+1, 1)   = thisGRFEffectiveSrate;
    GRFMaxDtSec(end+1, 1)         = thisGRFMaxDtSec;
    GRFNDataSamples(end+1, 1)     = thisGRFNDataSamples;
    GRFNTimeStamps(end+1, 1)      = thisGRFNTimeStamps;

end

%% Create and save import table

importTable = table( ...
    DoImport, ...
    XdfPath, ...
    FileName, ...
    RawSubjectFolder, ...
    RawDayFolder, ...
    RawSessionFolder, ...
    BidsSubject, ...
    BidsSession, ...
    Task, ...
    RunNumber, ...
    ExtraTag, ...
    EEGStreamName, ...
    NominalSrate, ...
    ChannelCount, ...
    HasUsableEEG, ...
    SelectedStreamIndex, ...
    EEGQualityStatus, ...
    EEGQualityReason, ...
    DurationSec, ...
    EffectiveSrate, ...
    MaxDtSec, ...
    NDataSamples, ...
    NTimeStamps, ...
    HasGRFStream, ...
    HasUsableGRF, ...
    SelectedGRFStreamIndex, ...
    GRFStreamName, ...
    GRFNominalSrate, ...
    GRFChannelCount, ...
    GRFQualityStatus, ...
    GRFQualityReason, ...
    GRFDurationSec, ...
    GRFEffectiveSrate, ...
    GRFMaxDtSec, ...
    GRFNDataSamples, ...
    GRFNTimeStamps);

% Keep the QC-derived recommendation separate from the editable DoImport flag.
importTable.RecommendedDoImport = importTable.DoImport;

% Preserve the user-editable DoImport decision when the source signature is unchanged.
importTable = preserve_existing_columns(importTable, importTableFile);

% Duplicate BIDS run keys are invalid when multiple matching rows are enabled.
% Disabled backup rows may share the same key.
importTable = disable_duplicate_bids_keys(importTable);

writetable(importTable, importTableFile);

%% Final report

fprintf('\n============================================================\n');
fprintf('IMPORT TABLE CREATED\n');
fprintf('============================================================\n');

fprintf('Saved to:\n%s\n', importTableFile);

fprintf('\nTotal real-EEG rows in import table: %d\n', height(importTable));
fprintf('Rows with DoImport = 1: %d\n', sum(importTable.DoImport == 1));
fprintf('Rows with DoImport = 0: %d\n', sum(importTable.DoImport == 0));
fprintf('Rows with usable EEG: %d\n', sum(importTable.HasUsableEEG == 1));
fprintf('Rows with usable GRF: %d\n', sum(importTable.HasUsableGRF == 1));

fprintf('Rows passing both stream gates: %d\n', ...
    sum(importTable.HasUsableEEG == 1 & ...
        importTable.HasUsableGRF == 1));

fprintf('XDF paths rebased to current rawDataFolder: %d\n', ...
    nRebasedXdfPaths);

fprintf('Allowed XDF runs: %s\n', ...
    strjoin(compose('run-%03d', cfg.import.allowedRunNumbers), ', '));

fprintf('\nDoImport = 0 reasons:\n');

skipRows = importTable.DoImport == 0;

if any(skipRows)

    skipStatus = importTable.ExtraTag(skipRows);
    uniqueStatus = unique(skipStatus, 'stable');

    for k = 1:numel(uniqueStatus)
        thisStatus = uniqueStatus(k);
        n = sum(skipStatus == thisStatus);

        fprintf('  %-40s %d\n', thisStatus, n);
    end

    fprintf('\nSkipped XDF rows:\n');

    disp(importTable(skipRows, { ...
        'FileName', ...
        'BidsSubject', ...
        'BidsSession', ...
        'RunNumber', ...
        'ExtraTag', ...
        'EEGQualityStatus', ...
        'EEGQualityReason', ...
        'HasGRFStream', ...
        'HasUsableGRF', ...
        'GRFQualityStatus', ...
        'GRFQualityReason', ...
        'DurationSec', ...
        'EffectiveSrate', ...
        'MaxDtSec', ...
        'NDataSamples', ...
        'NTimeStamps', ...
        'GRFDurationSec', ...
        'GRFEffectiveSrate', ...
        'GRFNDataSamples', ...
        'GRFNTimeStamps'}));

else

    fprintf('  None.\n');

end

fprintf('\nPreview:\n');
disp(importTable(1:min(10, height(importTable)), :));

fprintf('\nDone.\n');

%% Helper functions

function check_required_columns(T, requiredColumns, tableName)

    for i = 1:numel(requiredColumns)

        if ~ismember(requiredColumns{i}, T.Properties.VariableNames)

            error( ...
                'Required column "%s" not found in %s.', ...
                requiredColumns{i}, ...
                tableName);

        end

    end

end

function y = to_numeric_column(x)

    if isnumeric(x)

        y = double(x);

    elseif islogical(x)

        y = double(x);

    else

        y = str2double(string(x));

    end

end

function y = to_logical_column(x)

    if islogical(x)

        y = x;
        return;

    end

    if isnumeric(x)

        y = x ~= 0;
        return;

    end

    x = lower(strtrim(string(x)));

    y = ...
        x == "true" | ...
        x == "1" | ...
        x == "yes";

end

function y = to_scalar_double(x)

    if isnumeric(x)

        y = double(x);

    elseif islogical(x)

        y = double(x);

    else

        y = str2double(string(x));

    end

    if numel(y) > 1
        y = y(1);
    end

end

function T = disable_duplicate_bids_keys(T)

    % Only enabled rows can overwrite one another during XDF -> BIDS import.
    % A disabled backup XDF may share the same parsed BIDS key.
    T.DoImport = to_numeric_column(T.DoImport);

    if ismember('RecommendedDoImport', T.Properties.VariableNames)
        T.RecommendedDoImport = ...
            to_numeric_column(T.RecommendedDoImport);
    end

    enabledRows = find(T.DoImport == 1);

    if numel(enabledRows) < 2
        return;
    end

    runText = string(T.RunNumber(enabledRows));
    runText(ismissing(runText)) = "";

    keys = ...
        string(T.BidsSubject(enabledRows)) + "|" + ...
        string(T.BidsSession(enabledRows)) + "|" + ...
        string(T.Task(enabledRows)) + "|" + ...
        runText;

    [uniqueKeys, ~, groupIndex] = unique(keys, 'stable');

    counts = accumarray(groupIndex, 1);
    duplicateGroups = find(counts > 1);

    if isempty(duplicateGroups)
        return;
    end

    warning([ ...
        'Duplicate ENABLED BIDS subject/session/task/run keys found. ' ...
        'Only the conflicting enabled rows were set to DoImport = 0.']);

    for k = 1:numel(duplicateGroups)

        rows = ...
            enabledRows( ...
                groupIndex == duplicateGroups(k));

        T.DoImport(rows) = 0;

        if ismember( ...
                'RecommendedDoImport', ...
                T.Properties.VariableNames)

            T.RecommendedDoImport(rows) = 0;

        end

        T.EEGQualityStatus(rows) = ...
            "BAD_duplicate_enabled_bids_key";

        T.EEGQualityReason(rows) = ...
            "multiple_enabled_XDF_files_map_to_the_same_BIDS_subject_session_task_run";

        T.ExtraTag(rows) = ...
            "duplicate_enabled_bids_key_default_skip";

        fprintf( ...
            'Duplicate enabled key: %s\n', ...
            uniqueKeys(duplicateGroups(k)));

        disp(T(rows, { ...
            'FileName', ...
            'XdfPath', ...
            'BidsSubject', ...
            'BidsSession', ...
            'Task', ...
            'RunNumber', ...
            'DoImport'}));

    end

end

function newT = preserve_existing_columns(newT, tableFile)

    if ~exist(tableFile, 'file')
        return;
    end

    try

        opts = detectImportOptions( ...
            tableFile, ...
            'FileType', 'text', ...
            'Delimiter', ',', ...
            'VariableNamingRule', 'preserve');

        opts = setvartype( ...
            opts, ...
            opts.VariableNames, ...
            'string');

        oldT = readtable(tableFile, opts);

    catch ME

        warning( ...
            'Could not read the previous import table. Existing manual columns were not preserved: %s', ...
            ME.message);

        return;

    end

    if ~ismember('XdfPath', oldT.Properties.VariableNames)

        warning( ...
            'Previous import table has no XdfPath column. Existing columns were not preserved.');

        return;

    end

    oldT.XdfPath = string(oldT.XdfPath);
    newT.XdfPath = string(newT.XdfPath);

    columnsToPreserve = {'DoImport'};

    if ismember('DoImport', oldT.Properties.VariableNames)
        oldT.DoImport = to_numeric_column(oldT.DoImport);
    end

    for c = 1:numel(columnsToPreserve)

        name = columnsToPreserve{c};

        if ~ismember(name, oldT.Properties.VariableNames)
            continue;
        end

        if ~ismember(name, newT.Properties.VariableNames)

            newT.(name) = ...
                make_missing_column_like( ...
                    oldT.(name), ...
                    height(newT));

        end

    end

    preservedRows = 0;
    invalidatedRows = 0;

    for r = 1:height(newT)

        oldRow = find( ...
            oldT.XdfPath == newT.XdfPath(r), ...
            1, ...
            'first');

        % Use the raw-folder and filename identity when absolute paths differ.
        if isempty(oldRow)

            portableKeyFields = { ...
                'FileName', ...
                'RawSubjectFolder', ...
                'RawDayFolder', ...
                'RawSessionFolder'};

            if all(ismember( ...
                    portableKeyFields, ...
                    oldT.Properties.VariableNames)) && ...
                    all(ismember( ...
                        portableKeyFields, ...
                        newT.Properties.VariableNames))

                candidateOldRows = true(height(oldT), 1);

                for keyIndex = 1:numel(portableKeyFields)

                    keyName = portableKeyFields{keyIndex};

                    candidateOldRows = ...
                        candidateOldRows & ...
                        string(oldT.(keyName)) == ...
                        string(newT.(keyName)(r));

                end

                matchingOldRows = find(candidateOldRows);

                if numel(matchingOldRows) == 1
                    oldRow = matchingOldRows;
                end

            end

        end

        if isempty(oldRow)
            continue;
        end

        if source_signature_matches( ...
                oldT, ...
                oldRow, ...
                newT, ...
                r)

            for c = 1:numel(columnsToPreserve)

                name = columnsToPreserve{c};

                if ismember(name, oldT.Properties.VariableNames)

                    if strcmp(name, 'DoImport')

                        % A QC-rejected row cannot be enabled manually.
                        if newT.RecommendedDoImport(r) ~= 1
                            continue;
                        end

                        % Duplicate-disable states are not preserved as manual
                        % DoImport decisions.
                        if was_auto_disabled_duplicate(oldT, oldRow)
                            continue;
                        end

                    end

                    newT.(name)(r,:) = ...
                        oldT.(name)(oldRow,:);

                end

            end

            preservedRows = preservedRows + 1;

        else

            invalidatedRows = invalidatedRows + 1;

        end

    end

    fprintf( ...
        'Preserved DoImport for %d unchanged XDF rows.\n', ...
        preservedRows);

    fprintf( ...
        'Did not preserve DoImport for %d changed XDF rows.\n', ...
        invalidatedRows);

end

function tf = was_auto_disabled_duplicate(T, row)

    tf = false;

    if ismember('ExtraTag', T.Properties.VariableNames)

        tag = string(T.ExtraTag(row));
        tag(ismissing(tag)) = "";

        if contains( ...
                tag, ...
                "duplicate_bids_key_default_skip") || ...
                contains( ...
                    tag, ...
                    "duplicate_enabled_bids_key_default_skip")

            tf = true;
            return;

        end

    end

    if ismember('EEGQualityStatus', T.Properties.VariableNames)

        status = string(T.EEGQualityStatus(row));
        status(ismissing(status)) = "";

        if status == "BAD_duplicate_bids_key" || ...
                status == "BAD_duplicate_enabled_bids_key"

            tf = true;

        end

    end

end

function tf = source_signature_matches( ...
        oldT, ...
        oldRow, ...
        newT, ...
        newRow)

    tf = true;

    % Include both EEG and GRF source signatures. A missing or replaced GRF
    % stream invalidates a manual DoImport decision even when the EEG metrics match.
    fields = { ...
        'BidsSubject', ...
        'BidsSession', ...
        'Task', ...
        'RunNumber', ...
        'NDataSamples', ...
        'NTimeStamps', ...
        'DurationSec', ...
        'EffectiveSrate', ...
        'HasGRFStream', ...
        'HasUsableGRF', ...
        'GRFQualityStatus', ...
        'GRFNDataSamples', ...
        'GRFNTimeStamps', ...
        'GRFDurationSec', ...
        'GRFEffectiveSrate'};

    for i = 1:numel(fields)

        name = fields{i};

        if ~ismember( ...
                name, ...
                oldT.Properties.VariableNames) || ...
                ~ismember( ...
                    name, ...
                    newT.Properties.VariableNames)

            tf = false;
            return;

        end

        a = string(oldT.(name)(oldRow));
        b = string(newT.(name)(newRow));

        if strcmp(name, 'RunNumber')

            % Compare RunNumber numerically so equivalent formatting such as
            % 1/2 and 001/002 does not invalidate otherwise unchanged rows.
            av = str2double(a);
            bv = str2double(b);

            if isfinite(av) && isfinite(bv)

                if av ~= bv
                    tf = false;
                    return;
                end

            elseif ~isequaln(a, b)

                tf = false;
                return;

            end

        elseif ismember(name, { ...
                'DurationSec', ...
                'EffectiveSrate', ...
                'GRFDurationSec', ...
                'GRFEffectiveSrate'})

            av = str2double(a);
            bv = str2double(b);

            if ~( ...
                    isfinite(av) && ...
                    isfinite(bv) && ...
                    abs(av - bv) <= 1e-6)

                tf = false;
                return;

            end

        elseif ~isequaln(a, b)

            tf = false;
            return;

        end

    end

end

function out = make_missing_column_like(example, nRows)

    if isstring(example)

        out = strings( ...
            nRows, ...
            size(example, 2));

    elseif islogical(example)

        out = false( ...
            nRows, ...
            size(example, 2));

    elseif isnumeric(example)

        out = nan( ...
            nRows, ...
            size(example, 2));

    elseif isdatetime(example)

        out = NaT( ...
            nRows, ...
            size(example, 2));

    elseif iscell(example)

        out = cell( ...
            nRows, ...
            size(example, 2));

    elseif iscategorical(example)

        out = repmat( ...
            categorical(missing), ...
            nRows, ...
            size(example, 2));

    else

        out = strings( ...
            nRows, ...
            size(example, 2));

    end

end