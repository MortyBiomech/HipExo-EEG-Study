% Scan all XDF files in PilotTest2.
%
% Goal:
% 1. List all XDF files.
% 2. Show all streams in each XDF file.
% 3. Detect which files contain real EEG streams.
% 4. Check whether the detected EEG streams are structurally usable.
% 5. Save summary tables to output_data:
%    - xdf_file_stream_summary.csv
%    - xdf_stream_detail_table.csv
%    - xdf_eeg_quality_audit.csv
%
% Important:
% This script only checks whether EEG streams are usable for import.
% It does NOT judge full EEG signal quality, artifacts, bad channels, ICA quality, etc.

clear; clc; close all;

%% Load central paths

run(fullfile(fileparts(mfilename('fullpath')), 'paths.m'));

if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

summaryFile = fullfile(outputFolder, 'xdf_file_stream_summary.csv');
detailFile  = fullfile(outputFolder, 'xdf_stream_detail_table.csv');
eegQualityFile = fullfile(outputFolder, 'xdf_eeg_quality_audit.csv');

%% EEG usability thresholds

expectedEEGStreamName = "LiveAmpSN-102108-1139";

minEEGChannels = 10;
minDurationSec = 120;       % 2 minutes. Your runs are usually around 5-6 minutes.
maxTimestampGapSec = 1.0;   % hard reject if timestamp gap is larger than 1 second

% Effective sampling rate must be close to nominal sampling rate.
% For 500 Hz, this allows about 495-505 Hz.
absoluteSrateToleranceHz = 5;
relativeSrateTolerance = 0.01;

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

%% Prepare output tables

fileSummaryTable = table();
streamDetailTable = table();
eegQualityTable = table();

eegFilePaths = {};
eegStreamNames = {};

%% Autosave settings

saveEveryNFiles = 5;

%% Scan every XDF file

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
        isUsableEEG = false(nStreams, 1);

        nDataSamples = nan(nStreams, 1);
        nTimeStamps = nan(nStreams, 1);
        durationSec = nan(nStreams, 1);
        effectiveSrate = nan(nStreams, 1);
        medianDtSec = nan(nStreams, 1);
        minDtSec = nan(nStreams, 1);
        maxDtSec = nan(nStreams, 1);
        srateAbsDiff = nan(nStreams, 1);
        srateRelDiff = nan(nStreams, 1);
        sampleTimestampMatch = false(nStreams, 1);

        eegQualityStatus = strings(nStreams, 1);
        eegQualityReason = strings(nStreams, 1);

        for s = 1:nStreams

            info = streams{s}.info;

            streamNames(s) = get_xdf_info_field(info, 'name');
            streamTypes(s) = get_xdf_info_field(info, 'type');
            streamRates(s) = get_xdf_info_field(info, 'nominal_srate');
            streamChans(s) = get_xdf_info_field(info, 'channel_count');

            srateNum = str2double(streamRates(s));
            chanNum  = str2double(streamChans(s));

            if isnan(srateNum)
                srateNum = NaN;
            end

            if isnan(chanNum)
                chanNum = NaN;
            end

            %% Basic data and timestamp information

            if isfield(streams{s}, 'time_stamps')
                ts = double(streams{s}.time_stamps);
            else
                ts = [];
            end

            if isfield(streams{s}, 'time_series')
                data = streams{s}.time_series;
            else
                data = [];
            end

            nTimeStamps(s) = numel(ts);
            nDataSamples(s) = estimate_sample_count(data, nTimeStamps(s));

            if nTimeStamps(s) > 1
                dt = diff(ts);
                durationSec(s) = ts(end) - ts(1);

                if durationSec(s) > 0
                    effectiveSrate(s) = (nTimeStamps(s) - 1) / durationSec(s);
                end

                medianDtSec(s) = median(dt);
                minDtSec(s) = min(dt);
                maxDtSec(s) = max(dt);
            end

            if ~isnan(nDataSamples(s)) && ~isnan(nTimeStamps(s))
                sampleTimestampMatch(s) = (nDataSamples(s) == nTimeStamps(s));
            end

            if ~isnan(srateNum) && ~isnan(effectiveSrate(s))
                srateAbsDiff(s) = abs(effectiveSrate(s) - srateNum);

                if srateNum > 0
                    srateRelDiff(s) = srateAbsDiff(s) / srateNum;
                end
            end

            %% EEG detection
            % Real EEG candidate:
            % 1. stream type = EEG
            % 2. nominal sampling rate > 0
            % 3. channel count > minEEGChannels

            if strcmpi(streamTypes(s), "EEG") && ...
                    ~isnan(srateNum) && srateNum > 0 && ...
                    ~isnan(chanNum) && chanNum > minEEGChannels

                isEEGCandidate(s) = true;
            end

            %% EEG usability check

            [isUsableEEG(s), eegQualityStatus(s), eegQualityReason(s)] = check_eeg_usability( ...
                isEEGCandidate(s), ...
                streamNames(s), ...
                expectedEEGStreamName, ...
                srateNum, ...
                chanNum, ...
                nDataSamples(s), ...
                nTimeStamps(s), ...
                durationSec(s), ...
                effectiveSrate(s), ...
                maxDtSec(s), ...
                sampleTimestampMatch(s), ...
                minDurationSec, ...
                maxTimestampGapSec, ...
                absoluteSrateToleranceHz, ...
                relativeSrateTolerance);

        end

        hasRealEEG = any(isEEGCandidate);
        hasUsableEEG = any(isUsableEEG);

        if hasUsableEEG
            firstUsableEEGIndex = find(isUsableEEG, 1, 'first');

            eegFilePaths{end+1, 1} = xdfPath;
            eegStreamNames{end+1, 1} = char(streamNames(firstUsableEEGIndex));

            fileEEGQualityStatus = "OK";
            fileEEGQualityReason = "at_least_one_usable_eeg_stream_found";

        elseif hasRealEEG
            firstEEGIndex = find(isEEGCandidate, 1, 'first');

            eegFilePaths{end+1, 1} = xdfPath;
            eegStreamNames{end+1, 1} = char(streamNames(firstEEGIndex));

            fileEEGQualityStatus = eegQualityStatus(firstEEGIndex);
            fileEEGQualityReason = eegQualityReason(firstEEGIndex);

        else
            fileEEGQualityStatus = "NO_EEG";
            fileEEGQualityReason = "no_real_eeg_stream_found";
        end

        %% File summary row

        fileRow = table( ...
            i, ...
            string(files(i).name), ...
            string(xdfPath), ...
            string(strjoin(cellstr(streamNames), ' | ')), ...
            hasRealEEG, ...
            hasUsableEEG, ...
            fileEEGQualityStatus, ...
            fileEEGQualityReason, ...
            'VariableNames', {'FileIndex', 'FileName', 'FullPath', 'AllStreams', ...
                              'HasRealEEG', 'HasUsableEEG', ...
                              'FileEEGQualityStatus', 'FileEEGQualityReason'} ...
        );

        fileSummaryTable = [fileSummaryTable; fileRow];

        %% Stream detail rows

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
                isUsableEEG(s), ...
                nDataSamples(s), ...
                nTimeStamps(s), ...
                durationSec(s), ...
                effectiveSrate(s), ...
                medianDtSec(s), ...
                minDtSec(s), ...
                maxDtSec(s), ...
                srateAbsDiff(s), ...
                srateRelDiff(s), ...
                sampleTimestampMatch(s), ...
                eegQualityStatus(s), ...
                eegQualityReason(s), ...
                'VariableNames', {'FileIndex', 'FileName', 'FullPath', 'StreamIndex', ...
                                  'StreamName', 'StreamType', 'NominalSrate', ...
                                  'ChannelCount', 'IsRealEEG', 'IsUsableEEG', ...
                                  'NDataSamples', 'NTimeStamps', 'DurationSec', ...
                                  'EffectiveSrate', 'MedianDtSec', 'MinDtSec', ...
                                  'MaxDtSec', 'SrateAbsDiff', 'SrateRelDiff', ...
                                  'SampleTimestampMatch', ...
                                  'EEGQualityStatus', 'EEGQualityReason'} ...
            );

            streamDetailTable = [streamDetailTable; streamRow];

            if isEEGCandidate(s)

                eegRow = streamRow;
                eegQualityTable = [eegQualityTable; eegRow];

            end

        end

    catch ME

        warning('Could not load this XDF file:\n%s\nError:\n%s', xdfPath, ME.message);

        fileRow = table( ...
            i, ...
            string(files(i).name), ...
            string(xdfPath), ...
            string("ERROR: " + ME.message), ...
            false, ...
            false, ...
            string("LOAD_ERROR"), ...
            string(ME.message), ...
            'VariableNames', {'FileIndex', 'FileName', 'FullPath', 'AllStreams', ...
                              'HasRealEEG', 'HasUsableEEG', ...
                              'FileEEGQualityStatus', 'FileEEGQualityReason'} ...
        );

        fileSummaryTable = [fileSummaryTable; fileRow];

    end

    %% Autosave progress

    if mod(i, saveEveryNFiles) == 0 || i == length(files)

        writetable(fileSummaryTable, summaryFile);
        writetable(streamDetailTable, detailFile);
        writetable(eegQualityTable, eegQualityFile);

        fprintf('Autosaved progress after %d/%d files.\n', i, length(files));

    end

end

%% Final save

writetable(fileSummaryTable, summaryFile);
writetable(streamDetailTable, detailFile);
writetable(eegQualityTable, eegQualityFile);

%% Final report

fprintf('\n============================================================\n');
fprintf('SCAN FINISHED\n');
fprintf('============================================================\n');

fprintf('\nSummary saved to:\n%s\n', summaryFile);
fprintf('\nDetailed stream table saved to:\n%s\n', detailFile);
fprintf('\nEEG quality audit saved to:\n%s\n', eegQualityFile);

fprintf('\nFound %d XDF files in:\n%s\n', length(files), rawDataFolder);

nRealEEGFiles = sum(fileSummaryTable.HasRealEEG);
nUsableEEGFiles = sum(fileSummaryTable.HasUsableEEG);

fprintf('\nFiles with real EEG streams: %d\n', nRealEEGFiles);
fprintf('Files with usable EEG streams: %d\n', nUsableEEGFiles);
fprintf('Files with real EEG but unusable EEG: %d\n', nRealEEGFiles - nUsableEEGFiles);

fprintf('\nEEG quality status summary:\n');

if ~isempty(eegQualityTable)

    uniqueStatus = unique(eegQualityTable.EEGQualityStatus, 'stable');

    for k = 1:numel(uniqueStatus)
        thisStatus = uniqueStatus(k);
        n = sum(eegQualityTable.EEGQualityStatus == thisStatus);
        fprintf('  %-40s %d\n', thisStatus, n);
    end

    badRows = eegQualityTable.IsUsableEEG == false;

    if any(badRows)
        fprintf('\nUnusable EEG streams:\n');
        disp(eegQualityTable(badRows, { ...
            'FileIndex', 'FileName', 'StreamName', ...
            'NominalSrate', 'EffectiveSrate', ...
            'DurationSec', 'MaxDtSec', ...
            'NDataSamples', 'NTimeStamps', ...
            'EEGQualityStatus', 'EEGQualityReason'}));
    else
        fprintf('\nNo unusable EEG streams detected.\n');
    end

else

    fprintf('No EEG candidate streams found.\n');

end

fprintf('\nDone.\n');

%% Helper functions

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

function nSamples = estimate_sample_count(data, nTimeStamps)

    nSamples = NaN;

    if isempty(data)
        nSamples = 0;
        return;
    end

    try

        dataSize = size(data);

        if isnumeric(data) || islogical(data)

            if isvector(data)
                nSamples = numel(data);
                return;
            end

            if numel(dataSize) >= 2

                dim1 = dataSize(1);
                dim2 = dataSize(2);

                if ~isnan(nTimeStamps) && nTimeStamps > 0

                    if dim2 == nTimeStamps
                        nSamples = dim2;
                    elseif dim1 == nTimeStamps
                        nSamples = dim1;
                    else
                        nSamples = max(dim1, dim2);
                    end

                else
                    nSamples = max(dim1, dim2);
                end

            else
                nSamples = numel(data);
            end

        elseif iscell(data)

            nSamples = numel(data);

        else

            nSamples = numel(data);

        end

    catch

        nSamples = NaN;

    end

end

function [usable, status, reason] = check_eeg_usability( ...
    isEEGCandidate, ...
    streamName, ...
    expectedEEGStreamName, ...
    nominalSrate, ...
    channelCount, ...
    nDataSamples, ...
    nTimeStamps, ...
    durationSec, ...
    effectiveSrate, ...
    maxDtSec, ...
    sampleTimestampMatch, ...
    minDurationSec, ...
    maxTimestampGapSec, ...
    absoluteSrateToleranceHz, ...
    relativeSrateTolerance)

    usable = false;
    status = "NOT_EEG";
    reason = "stream_is_not_a_real_eeg_candidate";

    if ~isEEGCandidate
        return;
    end

    status = "BAD_unknown";
    reason = "unknown_eeg_problem";

    if strlength(streamName) == 0
        status = "BAD_missing_stream_name";
        reason = "eeg_stream_name_is_empty";
        return;
    end

    if streamName ~= expectedEEGStreamName
        % Not a hard fail if everything else is good, but record as warning later.
        streamNameWarning = true;
    else
        streamNameWarning = false;
    end

    if isnan(nominalSrate) || nominalSrate <= 0
        status = "BAD_nominal_srate";
        reason = "nominal_sampling_rate_is_missing_or_invalid";
        return;
    end

    if isnan(channelCount) || channelCount <= 10
        status = "BAD_channel_count";
        reason = "channel_count_is_too_low_for_eeg";
        return;
    end

    if isnan(nDataSamples) || nDataSamples <= 0
        status = "BAD_no_data_samples";
        reason = "eeg_data_samples_are_empty";
        return;
    end

    if isnan(nTimeStamps) || nTimeStamps <= 0
        status = "BAD_no_timestamps";
        reason = "eeg_timestamps_are_empty";
        return;
    end

    if ~sampleTimestampMatch
        status = "BAD_sample_timestamp_mismatch";
        reason = "number_of_data_samples_does_not_match_number_of_timestamps";
        return;
    end

    if isnan(durationSec) || durationSec <= 0
        status = "BAD_duration";
        reason = "eeg_duration_is_missing_or_invalid";
        return;
    end

    if durationSec < minDurationSec
        status = "BAD_too_short";
        reason = "eeg_duration_is_shorter_than_minimum_required_duration";
        return;
    end

    if isnan(effectiveSrate) || effectiveSrate <= 0
        status = "BAD_effective_srate";
        reason = "effective_sampling_rate_is_missing_or_invalid";
        return;
    end

    allowedSrateDiff = max(absoluteSrateToleranceHz, nominalSrate * relativeSrateTolerance);
    actualSrateDiff = abs(effectiveSrate - nominalSrate);

    if actualSrateDiff > allowedSrateDiff
        status = "BAD_effective_srate";
        reason = "effective_sampling_rate_is_too_far_from_nominal_sampling_rate";
        return;
    end

    if isnan(maxDtSec) || maxDtSec <= 0
        status = "BAD_timestamp_gap";
        reason = "timestamp_gap_information_is_missing_or_invalid";
        return;
    end

    if maxDtSec > maxTimestampGapSec
        status = "BAD_large_timestamp_gap";
        reason = "maximum_timestamp_gap_is_too_large";
        return;
    end

    usable = true;

    if streamNameWarning
        status = "WARNING_unexpected_eeg_stream_name";
        reason = "eeg_stream_is_usable_but_name_is_not_the_expected_liveamp_stream";
    else
        status = "OK";
        reason = "eeg_stream_passed_basic_usability_checks";
    end

end