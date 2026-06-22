% Scan all XDF files in PilotTest2.
% Goal:
% 1. List all XDF files.
% 2. Show all streams in each XDF file.
% 3. Detect which files contain real EEG.
% 4. Save summary tables to output_data.
% Check required toolbox: Statistics and Machine Learning Toolbox

clear; clc; close all;

%% Paths

projectFolder = '/Users/dydan/master_thesis/HipExo-EEG-Study/eeg_preprocessing';
% projectFolder = pwd;

eeglabFolder    = '/Users/dydan/master_thesis/eeglab2026.0.0';
bemobilFolder   = fullfile(projectFolder, 'BeMoBIL');
scriptsFolder   = fullfile(projectFolder, 'scripts_yadan');
fieldtripFolder = '/Users/dydan/master_thesis/fieldtrip-20260617';

rawDataFolder = '/Users/dydan/master_thesis/PilotTest2';
outputFolder  = fullfile(projectFolder, 'output_data');

if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

%% Add paths

addpath(eeglabFolder);
addpath(genpath(bemobilFolder));
addpath(scriptsFolder);

addpath(fieldtripFolder);
ft_defaults;

addpath(fullfile(fieldtripFolder, 'external', 'xdf'));

fprintf('Using ft_defaults from:\n%s\n', which('ft_defaults'));
fprintf('Using load_xdf from:\n%s\n', which('load_xdf'));

if isempty(which('load_xdf'))
    error('load_xdf was not found. Please check FieldTrip external/xdf path.');
end

%% Find all XDF files

files = dir(fullfile(rawDataFolder, '**', '*.xdf'));

fprintf('\nFound %d XDF files in:\n%s\n', length(files), rawDataFolder);

if isempty(files)
    error('No XDF files found. Please check rawDataFolder.');
end

for i = 1:length(files)
    fprintf('%3d: %s\n', i, fullfile(files(i).folder, files(i).name));
end

%% Scan every XDF file

fileSummaryTable = table();
streamDetailTable = table();

eegFilePaths = {};
eegStreamNames = {};

for i = 1:length(files)

    xdfPath = fullfile(files(i).folder, files(i).name);

    fprintf('\n============================================================\n');
    fprintf('Checking file %d/%d:\n%s\n', i, length(files), xdfPath);
    fprintf('============================================================\n');

    try
        streams = load_xdf(xdfPath);

        nStreams = numel(streams);

        streamNames = strings(nStreams, 1);
        streamTypes = strings(nStreams, 1);
        streamRates = strings(nStreams, 1);
        streamChans = strings(nStreams, 1);
        isEEGCandidate = false(nStreams, 1);

        for s = 1:nStreams

            info = streams{s}.info;

            streamNames(s) = get_xdf_info_field(info, 'name');
            streamTypes(s) = get_xdf_info_field(info, 'type');
            streamRates(s) = get_xdf_info_field(info, 'nominal_srate');
            streamChans(s) = get_xdf_info_field(info, 'channel_count');

            %% Accurate EEG detection
            % Real EEG should have:
            % 1. stream type = EEG
            % 2. sampling rate > 0
            % 3. channel count > 10
            %
            % This avoids wrongly detecting DeviceTrigger as EEG.

            srateNum = str2double(streamRates(s));
            chanNum  = str2double(streamChans(s));

            if strcmpi(streamTypes(s), "EEG") && srateNum > 0 && chanNum > 10
                isEEGCandidate(s) = true;
            end

        end

        disp('Streams in this file:');

        for s = 1:nStreams
            fprintf('  Stream %2d | name: %-40s | type: %-15s | srate: %-10s | channels: %-10s', ...
                s, streamNames(s), streamTypes(s), streamRates(s), streamChans(s));

            if isEEGCandidate(s)
                fprintf('  <-- real EEG');
            end

            fprintf('\n');
        end

        hasEEG = any(isEEGCandidate);

        if hasEEG
            firstEEGIndex = find(isEEGCandidate, 1, 'first');

            eegFilePaths{end+1, 1} = xdfPath;
            eegStreamNames{end+1, 1} = char(streamNames(firstEEGIndex));

            fprintf('\n>>> Real EEG found: %s\n', streamNames(firstEEGIndex));
        else
            fprintf('\n--- No real EEG found in this file.\n');
        end

        fileRow = table( ...
            i, ...
            string(files(i).name), ...
            string(xdfPath), ...
            string(strjoin(cellstr(streamNames), ' | ')), ...
            hasEEG, ...
            'VariableNames', {'FileIndex', 'FileName', 'FullPath', 'AllStreams', 'HasRealEEG'} ...
        );

        fileSummaryTable = [fileSummaryTable; fileRow];

        for s = 1:nStreams

            streamRow = table( ...
                i, ...
                string(files(i).name), ...
                string(xdfPath), ...
                s, ...
                streamNames(s), ...
                streamTypes(s), ...
                streamRates(s), ...
                streamChans(s), ...
                isEEGCandidate(s), ...
                'VariableNames', {'FileIndex', 'FileName', 'FullPath', 'StreamIndex', ...
                                  'StreamName', 'StreamType', 'NominalSrate', ...
                                  'ChannelCount', 'IsRealEEG'} ...
            );

            streamDetailTable = [streamDetailTable; streamRow];

        end

    catch ME

        warning('Could not load this XDF file: %s', ME.message);

        fileRow = table( ...
            i, ...
            string(files(i).name), ...
            string(xdfPath), ...
            string("ERROR: " + ME.message), ...
            false, ...
            'VariableNames', {'FileIndex', 'FileName', 'FullPath', 'AllStreams', 'HasRealEEG'} ...
        );

        fileSummaryTable = [fileSummaryTable; fileRow];

    end
    %% Save summary tables

    summaryFile = fullfile(outputFolder, 'xdf_file_stream_summary.csv');
    detailFile  = fullfile(outputFolder, 'xdf_stream_detail_table.csv');

    writetable(fileSummaryTable, summaryFile);
    writetable(streamDetailTable, detailFile);
end



fprintf('\n============================================================\n');
fprintf('SCAN FINISHED\n');
fprintf('============================================================\n');

fprintf('\nSummary saved to:\n%s\n', summaryFile);
fprintf('\nDetailed stream table saved to:\n%s\n', detailFile);

fprintf('\nFiles with real EEG:\n');

if isempty(eegFilePaths)
    fprintf('No EEG files found.\n');
    fprintf('Check xdf_stream_detail_table.csv manually.\n');
else
    for i = 1:length(eegFilePaths)
        fprintf('%3d: EEG stream = %-40s | file = %s\n', ...
            i, eegStreamNames{i}, eegFilePaths{i});
    end
end

%% Helper function

function value = get_xdf_info_field(info, fieldName)

    value = "";

    try
        if isfield(info, fieldName)
            rawValue = info.(fieldName);

            if iscell(rawValue)
                if ~isempty(rawValue)
                    value = string(rawValue{1});
                end
            elseif ischar(rawValue)
                value = string(rawValue);
            elseif isnumeric(rawValue)
                value = string(rawValue);
            elseif isstring(rawValue)
                value = rawValue;
            else
                value = string(rawValue);
            end
        end
    catch
        value = "";
    end

end