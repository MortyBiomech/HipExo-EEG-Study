function [ranges, audit, timeStamps] = check_eeg_segments(stream, cfg, xdfPath) %#ok<INUSD>
% Return inclusive source-sample ranges that pass the existing EEG timing QC.
% No minimum segment duration is imposed here.
% No samples are synthesized, interpolated or resampled.
%
% The timestamps returned by the normal XDF load are used directly.
% Actual timestamp discontinuities split the recording into blocks, and each
% block is checked independently with the existing sampling-rate and gap
% criteria.

ranges = zeros(0, 2);
timeStamps = double(stream.time_stamps(:)');

audit = struct( ...
    'status', "no_segment_passes_existing_QC", ...
    'retained_samples', 0, ...
    'retained_duration_sec', 0, ...
    'retained_lsl_ranges', zeros(0, 2), ...
    'retained_rates_hz', [], ...
    'longest_timing_valid_segment_sec', 0, ...
    'invalid_timing_samples', 0, ...
    'timing_mode', "default_XDF_timestamps_gap_split");

audit.time_origin_lsl = NaN;

if ~isempty(timeStamps)
    audit.time_origin_lsl = timeStamps(1);
end

nominalSrate = str2double( ...
    info_text_local(stream, 'nominal_srate'));

if ~isfinite(nominalSrate) || ...
        nominalSrate <= 0 || ...
        abs(nominalSrate - cfg.eeg.nominalSrateHz) > ...
            cfg.eeg.absoluteSrateToleranceHz

    audit.status = "invalid_nominal_rate";
    return;
end

data = stream.time_series;
n = numel(timeStamps);

if size(data, 2) ~= n && size(data, 1) == n
    data = data.';
end

if ~isnumeric(data) || ...
        size(data, 2) ~= n || ...
        n < 2

    audit.status = "invalid_data_or_timestamps";
    return;
end

dt = diff(timeStamps);

finitePositiveDt = ...
    dt(isfinite(dt) & dt > 0);

if isempty(finitePositiveDt)
    audit.status = "invalid_data_or_timestamps";
    return;
end

rateTolerance = max( ...
    cfg.eeg.absoluteSrateToleranceHz, ...
    nominalSrate * cfg.eeg.relativeSrateTolerance);

gapLimit = min( ...
    cfg.timestamp.maximumGapSec, ...
    max( ...
        cfg.timestamp.minimumRobustGapSec, ...
        cfg.timestamp.robustGapFactor * median(finitePositiveDt)));

% A retained sample must have an unambiguous monotonic timestamp position.
leftTime = timeStamps;
leftTime(~isfinite(leftTime)) = -Inf;

previousMax = [ ...
    -Inf, ...
    cummax(leftTime(1:end-1))];

rightTime = timeStamps;
rightTime(~isfinite(rightTime)) = Inf;

nextMin = [ ...
    fliplr(cummin(fliplr(rightTime(2:end)))), ...
    Inf];

orderedSample = ...
    isfinite(timeStamps) & ...
    timeStamps > previousMax & ...
    timeStamps < nextMin;

audit.invalid_timing_samples = ...
    sum(~orderedSample);

% Split only at discontinuities present in the normally loaded timestamps.
breakAfter = find( ...
    ~isfinite(dt) | ...
    dt <= 0 | ...
    dt > gapLimit | ...
    ~orderedSample(1:end-1) | ...
    ~orderedSample(2:end));

breakAfter = unique( ...
    breakAfter( ...
        breakAfter >= 1 & ...
        breakAfter < n));

starts = [1, breakAfter + 1];
stops = [breakAfter, n];

for k = 1:numel(starts)

    first = starts(k);
    last = stops(k);

    if last <= first || ...
            ~all(orderedSample(first:last))
        continue;
    end

    blockTime = ...
        timeStamps(first:last);

    blockDt = ...
        diff(blockTime);

    if isempty(blockDt) || ...
            any(~isfinite(blockDt)) || ...
            any(blockDt <= 0)
        continue;
    end

    duration = ...
        blockTime(end) - blockTime(1);

    if ~isfinite(duration) || duration <= 0
        continue;
    end

    rate = ...
        (last - first) / duration;

    blockGapLimit = min( ...
        cfg.timestamp.maximumGapSec, ...
        max( ...
            cfg.timestamp.minimumRobustGapSec, ...
            cfg.timestamp.robustGapFactor * median(blockDt)));

    timingOK = ...
        abs(rate - nominalSrate) <= rateTolerance && ...
        max(blockDt) <= blockGapLimit;

    dataOK = ...
        ~any(any(~isfinite(data(:, first:last))));

    if ~timingOK || ~dataOK
        continue;
    end

    ranges(end+1, :) = ...
        [first, last]; %#ok<AGROW>

    audit.retained_lsl_ranges(end+1, :) = ...
        timeStamps([first, last]);

    audit.retained_rates_hz(end+1, 1) = ...
        rate;

    audit.retained_samples = ...
        audit.retained_samples + ...
        last - first + 1;

    audit.retained_duration_sec = ...
        audit.retained_duration_sec + ...
        duration;

    audit.longest_timing_valid_segment_sec = ...
        max( ...
            audit.longest_timing_valid_segment_sec, ...
            duration);
end

if isempty(ranges)
    return;
end

if isequal(ranges, [1 n])
    audit.status = "whole_recording";
else
    audit.status = "retained_segments";
end

end

function value = info_text_local(stream, fieldName)

value = "";

if ~isfield(stream, 'info') || ...
        ~isfield(stream.info, fieldName)
    return;
end

raw = stream.info.(fieldName);

while iscell(raw) && ~isempty(raw)
    raw = raw{1};
end

if isempty(raw)
    return;
end

value = strtrim(string(raw));
value = value(1);

end
