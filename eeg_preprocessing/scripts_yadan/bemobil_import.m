% Goal:
% Import all selected EEG-containing XDF files listed in:
%   output_data/bemobil_import_table.csv
%
% It reads one row per XDF file from the import table.
%
% Naming rule:
%   Raw:
%       Sub-P2_1 / day2 / data / ses-Exo1_sport / eeg / xxx.xdf
%
%   BeMoBIL/BIDS:
%       sub-01 / ses-Pilot2p1day2sesExo1Sport / eeg / ...
%
% Important:
%   First run:
%       1) check_eeg_streams.m
%       2) import_table.m
%       3) Check output_data/bemobil_import_table.csv manually
%       4) Run this script
%
% Recommended first test:
%   In bemobil_import_table.csv, keep only one row with DoImport = 1,
%   for example ses-Exo1_sport. Set all other rows to DoImport = 0.
%   After one file succeeds, enable more rows.

clear; clc;

%% Load central paths

run(fullfile(fileparts(mfilename('fullpath')), 'paths.m'));

studyFolder = outputFolder;
bidsFolder  = fullfile(studyFolder, '1_BIDS-data');
setFolder   = fullfile(studyFolder, '2_raw-EEGLAB');

if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

if ~exist(bidsFolder, 'dir')
    mkdir(bidsFolder);
end

if ~exist(setFolder, 'dir')
    mkdir(setFolder);
end

if ~exist(importTableFile, 'file')
    error('Import table not found:\n%s\nRun import_table.m first.', importTableFile);
end

%% Initialize EEGLAB

if ~exist('ALLCOM', 'var')
    eeglab;
end

%% Initialize FieldTrip

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

%% Read import table

% Use detectImportOptions instead of plain readtable.
% This is safer for CSV files that contain Windows paths.
optsImport = detectImportOptions(importTableFile, ...
    'FileType', 'text', ...
    'Delimiter', ',', ...
    'VariableNamingRule', 'preserve');

importTable = readtable(importTableFile, optsImport);

% Convert string-like columns explicitly where needed.
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

% Normalize important numeric columns.
importTable.DoImport = to_numeric_column(importTable.DoImport);
importTable.BidsSubject = to_numeric_column(importTable.BidsSubject);

rowsToImport = find(importTable.DoImport == 1);

fprintf('\n============================================================\n');
fprintf('BEMOBIL TABLE IMPORT SETTINGS\n');
fprintf('============================================================\n');

fprintf('Import table:\n%s\n', importTableFile);
fprintf('Total rows in table: %d\n', height(importTable));
fprintf('Rows enabled for import: %d\n', numel(rowsToImport));
fprintf('BIDS target folder:\n%s\n', bidsFolder);
fprintf('EEGLAB set folder:\n%s\n', setFolder);

if isempty(rowsToImport)
    error('No rows have DoImport = 1. Check bemobil_import_table.csv.');
end

%% General metadata shared across all modalities

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

%% EEG metadata

eegInfo = [];

eegInfo.coordsystem.EEGCoordinateSystem             = 'n/a';
eegInfo.coordsystem.EEGCoordinateUnits              = 'n/a';
eegInfo.coordsystem.EEGCoordinateSystemDescription  = 'n/a';
eegInfo.eeg.SamplingFrequency                       = 500;

%% Participant metadata

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

%% Import XDF files to BIDS

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

    fprintf('\n------------------------------------------------------------\n');
    fprintf('Importing row %d/%d from table row %d\n', n, numel(rowsToImport), rowIdx);
    fprintf('XDF file:\n%s\n', xdfPath);
    fprintf('BIDS subject: sub-%02d\n', bidsSubject);
    fprintf('BIDS session: ses-%s\n', bidsSession);
    fprintf('Task: %s\n', taskLabel);
    fprintf('EEG stream: %s\n', eegStreamName);

    if ~exist(xdfPath, 'file')
        warning('XDF file not found. Skipping:\n%s', xdfPath);

        importLog = [importLog; make_log_row(rowIdx, xdfPath, bidsSubject, ...
                    string(bidsSession), string(taskLabel), false, ...
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

        % Do not use config.run for the first stable test.
        % Your file name already contains run-001.
        % Some BeMoBIL versions may not use or expect config.run.
        %
        % If later you confirm that your BeMoBIL version supports config.run,
        % you can enable this block again:
        %
        % if ismember('RunNumber', importTable.Properties.VariableNames)
        %     runLabel = string(row.RunNumber);
        %     if strlength(runLabel) > 0 && runLabel ~= "<missing>"
        %         runNum = str2double(runLabel);
        %         if ~isnan(runNum)
        %             config.run = runNum;
        %         end
        %     end
        % end

        bemobil_xdf2bids(config, ...
            'general_metadata', generalInfo, ...
            'participant_metadata', subjectInfo, ...
            'eeg_metadata', eegInfo);

        importLog = [importLog; make_log_row(rowIdx, xdfPath, bidsSubject, ...
                    string(bidsSession), string(taskLabel), true, "OK")];

    catch ME

        warning('Import failed for table row %d:\n%s', rowIdx, ME.message);

        importLog = [importLog; make_log_row(rowIdx, xdfPath, bidsSubject, ...
                    string(bidsSession), string(taskLabel), false, ...
                    string(ME.message))];

    end

    fclose all;

end

%% Save import log

logFile = fullfile(outputFolder, 'bemobil_xdf2bids_import_log.csv');
writetable(importLog, logFile);

fprintf('\n============================================================\n');
fprintf('XDF TO BIDS IMPORT FINISHED\n');
fprintf('============================================================\n');

fprintf('Import log saved to:\n%s\n', logFile);

fprintf('\nSuccessful imports: %d\n', sum(importLog.Success == true));
fprintf('Failed imports: %d\n', sum(importLog.Success == false));

%% Convert BIDS EEG files to EEGLAB .set/.fdt

fprintf('\n============================================================\n');
fprintf('STARTING BIDS TO EEGLAB SET CONVERSION\n');
fprintf('============================================================\n');

successfulRows = importLog.Success == true;

if ~any(successfulRows)

    warning('No successful BIDS imports. Skipping bemobil_bids2set.');

else

    successLog = importLog(successfulRows, :);
    uniqueSuccessSubjects = unique(successLog.BidsSubject);

    for s = 1:numel(uniqueSuccessSubjects)

        subj = uniqueSuccessSubjects(s);
        subjRows = successLog.BidsSubject == subj;
        sessionNames = unique(successLog.BidsSession(subjRows), 'stable');

        fprintf('\n------------------------------------------------------------\n');
        fprintf('Converting subject %d to EEGLAB set\n', subj);
        fprintf('Sessions:\n');
        disp(sessionNames);

        try
            config = [];

            config.bids_target_folder = bidsFolder;
            config.bids_folder        = bidsFolder;
            config.set_folder         = setFolder;

            config.subject            = subj;
            config.session_names      = cellstr(sessionNames);

            % EEG-only import.
            config.other_data_types   = {};

            bemobil_bids2set(config);

        catch ME

            warning('bemobil_bids2set failed for subject %d:\n%s', subj, ME.message);

        end

        fclose all;

    end

end

fprintf('\n============================================================\n');
fprintf('ALL DONE\n');
fprintf('============================================================\n');

fprintf('\nBIDS folder:\n%s\n', bidsFolder);
fprintf('EEGLAB set folder:\n%s\n', setFolder);

%% Helper functions

function y = to_numeric_column(x)

    if isnumeric(x)
        y = x;
    elseif islogical(x)
        y = double(x);
    else
        y = str2double(string(x));
    end

end

function logRow = make_log_row(rowIdx, xdfPath, bidsSubject, bidsSession, taskLabel, successFlag, messageText)

    logRow = table( ...
        rowIdx, ...
        string(xdfPath), ...
        bidsSubject, ...
        string(bidsSession), ...
        string(taskLabel), ...
        logical(successFlag), ...
        string(messageText), ...
        'VariableNames', {'TableRow', 'XdfPath', 'BidsSubject', ...
                          'BidsSession', 'Task', 'Success', 'Message'} ...
    );

end