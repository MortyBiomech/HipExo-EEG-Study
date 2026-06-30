% Scan all XDF files in PilotTest2.
% Goal:
% 1. List all XDF files.
% 2. Show all streams in each XDF file.
% 3. Detect which files contain real EEG.
% 4. Save summary tables to output_data:
%    - xdf_file_stream_summary.csv
%    - xdf_stream_detail_table.csv

clear; clc; close all;

%% Load central paths

run(fullfile(fileparts(mfilename('fullpath')), 'paths.m'));

if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

%% Initialize FieldTrip

ft_defaults;

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

%% Scan every XDF file

fileSummaryTable = table();
streamDetailTable = table();

eegFilePaths = {};
eegStreamNames = {};

%% Autosave settings

saveEveryNFiles = 5;

for i = 1:length(files)
    if mod(i, 5) == 0 || i == 1 || i == length(files)
        fprintf('Scanned %d/%d files: %s\n', i, length(files), files(i).name);
    end

    xdfPath = fullfile(files(i).folder, files(i).name);

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

            %% EEG detection
            % Real EEG should have:
            % 1. stream type = EEG
            % 2. sampling rate > 0
            % 3. channel count > 10
     

            srateNum = str2double(streamRates(s));
            chanNum  = str2double(streamChans(s));

            if strcmpi(streamTypes(s), "EEG") && srateNum > 0 && chanNum > 10
                isEEGCandidate(s) = true;
            end

        end

        hasEEG = any(isEEGCandidate);

        if hasEEG
            firstEEGIndex = find(isEEGCandidate, 1, 'first');

            eegFilePaths{end+1, 1} = xdfPath;
            eegStreamNames{end+1, 1} = char(streamNames(firstEEGIndex));
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

    %% Autosave progress

    if mod(i, saveEveryNFiles) == 0 || i == length(files)
        writetable(fileSummaryTable, summaryFile);
        writetable(streamDetailTable, detailFile);

        fprintf('Autosaved progress after %d/%d files.\n', i, length(files));
    end
   
end

%% Save summary tables

writetable(fileSummaryTable, summaryFile);
writetable(streamDetailTable, detailFile);


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
    fprintf('\nFound %d XDF files in:\n%s\n', length(files), rawDataFolder);
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