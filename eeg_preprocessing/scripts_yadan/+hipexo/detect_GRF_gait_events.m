function [eventTable, diagnostics, qcFigure] = detect_grf_gait_events( ...
        grfData, grfTimeStamps, intervalStartLSLTime, intervalEndLSLTime, varargin)
% DETECT_GRF_GAIT_EVENTS Detect gait events with the laboratory GRF method.
% Uses four sensors per side, a fourth-order zero-phase low-pass filter,
% shared peak-based hysteresis thresholds and same-type event spacing.
% GRF remains in its recorded units. LSL event times are original samples.
%
% Options:
%   RightChannels             [1 4 5 8], indices among the eight force channels
%   LeftChannels              [2 3 6 7]
%   LowpassHz                 15
%   ThresholdOn               0.03 of the shared maximum filtered GRF
%   ThresholdOff              0.01 of the shared maximum filtered GRF
%   OptimizeThresholds        true: laboratory grid search per interval
%   ThresholdOnValues         0.01:0.005:0.06
%   ThresholdOffValues        0.01:0.005:0.06, restricted to Off < On
%   MinInterval               0.60 s between events of the same type
%   MaximumEventGRFFraction    0.15 of that side's maximum filtered GRF
%   Plot                      true
%   FigureVisible             'on'
%
% TO uses the last in-contact sample. Artificial interval-boundary events
% are omitted. Other observed events remain available for cycle-level QC.

p = inputParser;
addParameter(p, 'RightChannels', [1 4 5 8]);
addParameter(p, 'LeftChannels', [2 3 6 7]);
addParameter(p, 'LowpassHz', 15);
addParameter(p, 'ThresholdOn', 0.03);
addParameter(p, 'ThresholdOff', 0.01);
addParameter(p, 'OptimizeThresholds', true, @(x) islogical(x) && isscalar(x));
addParameter(p, 'ThresholdOnValues', 0.01:0.005:0.06);
addParameter(p, 'ThresholdOffValues', 0.01:0.005:0.06);
addParameter(p, 'MinInterval', 0.60);
addParameter(p, 'MaximumEventGRFFraction', 0.15);
addParameter(p, 'Plot', true);
addParameter(p, 'FigureVisible', 'on');
parse(p, varargin{:});
opt = p.Results;

%% Validate data and settings

grfData = double(grfData);
grfTimeStamps = double(grfTimeStamps(:));
if size(grfData, 2) ~= numel(grfTimeStamps) && ...
        size(grfData, 1) == numel(grfTimeStamps)
    grfData = grfData';
end
if size(grfData, 2) ~= numel(grfTimeStamps) || ...
        ~ismember(size(grfData, 1), [8 9])
    error('Expected eight force channels, an optional ninth counter, and matching timestamps.');
end
if numel(grfTimeStamps) < 2 || any(~isfinite(grfTimeStamps)) || ...
        any(diff(grfTimeStamps) <= 0)
    error('GRF timestamps must be finite and strictly increasing.');
end
validateattributes(intervalStartLSLTime, {'numeric'}, {'scalar', 'real', 'finite'});
validateattributes(intervalEndLSLTime, {'numeric'}, {'scalar', 'real', 'finite'});
if intervalEndLSLTime <= intervalStartLSLTime
    error('The walking interval must have StartLSLTime < EndLSLTime.');
end
validateattributes(opt.LowpassHz, {'numeric'}, {'scalar', 'real', 'finite', 'positive'});
validateattributes(opt.ThresholdOn, {'numeric'}, {'scalar', 'real', 'finite', 'positive', '<', 1});
validateattributes(opt.ThresholdOff, {'numeric'}, {'scalar', 'real', 'finite', 'nonnegative'});
validateattributes(opt.MinInterval, {'numeric'}, {'scalar', 'real', 'finite', 'nonnegative'});
validateattributes(opt.MaximumEventGRFFraction, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive', '<=', 1});
if opt.ThresholdOff >= opt.ThresholdOn
    error('ThresholdOff must be smaller than ThresholdOn.');
end
rightChannels = double(opt.RightChannels(:)');
leftChannels = double(opt.LeftChannels(:)');
validateattributes(rightChannels, {'double'}, {'vector', 'nonempty', 'integer', '>=', 1, '<=', 8});
validateattributes(leftChannels, {'double'}, {'vector', 'nonempty', 'integer', '>=', 1, '<=', 8});
allChannels = [rightChannels, leftChannels];
if numel(unique(allChannels)) ~= numel(allChannels)
    error('Force channel assignments must not repeat or overlap.');
end

%% Select the accepted interval and filter each side

firstSample = find(grfTimeStamps >= intervalStartLSLTime, 1, 'first');
lastSample = find(grfTimeStamps <= intervalEndLSLTime, 1, 'last');
if isempty(firstSample) || isempty(lastSample) || lastSample <= firstSample
    error('The accepted walking interval does not overlap the GRF stream.');
end
samples = firstSample:lastSample;
t = grfTimeStamps(samples);
fs = 1 / median(diff(t));
if ~isfinite(fs) || fs <= 2 * opt.LowpassHz
    error('Measured GRF rate must exceed twice the low-pass frequency.');
end
forceData = grfData(allChannels, samples);
if any(~isfinite(forceData(:)))
    error('The selected force channels contain non-finite samples.');
end
rightRaw = sum(grfData(rightChannels, samples), 1)';
leftRaw = sum(grfData(leftChannels, samples), 1)';
if exist('butter', 'file') ~= 2 || exist('filtfilt', 'file') ~= 2
    error('The laboratory GRF method requires butter and filtfilt (Signal Processing Toolbox).');
end
[b, a] = butter(4, opt.LowpassHz / (fs / 2), 'low');
rightFiltered = filtfilt(b, a, rightRaw);
leftFiltered = filtfilt(b, a, leftRaw);
sharedPeak = max([rightFiltered; leftFiltered]);
if sharedPeak <= 0
    error('No positive filtered GRF maximum was found.');
end
minIntervalSamples = round(opt.MinInterval * fs);

%% Select relative thresholds for this accepted interval

detectCandidate = @(on, off) detect_both_sides( ...
    rightFiltered, leftFiltered, t, firstSample, ...
    on * sharedPeak, off * sharedPeak, minIntervalSamples, opt.MaximumEventGRFFraction);
if opt.OptimizeThresholds
    [onFraction, offFraction, thresholdSearch] = hipexo.optimize_grf_thresholds( ...
        detectCandidate, opt.ThresholdOnValues, opt.ThresholdOffValues);
    selectionMethod = "lab_V1_pareto_min_right_stance_SD";
else
    onFraction = opt.ThresholdOn;
    offFraction = opt.ThresholdOff;
    thresholdSearch = table(onFraction, offFraction, true, 'VariableNames', ...
        {'ThresholdOn', 'ThresholdOff', 'Selected'});
    selectionMethod = "fixed";
end
thresholdOn = onFraction * sharedPeak;
thresholdOff = offFraction * sharedPeak;

%% Detect each event type independently

[rightEvents, leftEvents, rightDetection, leftDetection] = ...
    detectCandidate(onFraction, offFraction);

eventTable = [ ...
    event_rows("RHS", "Right", rightEvents.hsSegmentSamples, t, firstSample); ...
    event_rows("RTO", "Right", rightEvents.toSegmentSamples, t, firstSample); ...
    event_rows("LHS", "Left", leftEvents.hsSegmentSamples, t, firstSample); ...
    event_rows("LTO", "Left", leftEvents.toSegmentSamples, t, firstSample)];
eventTable = sortrows(eventTable, 'LSLTime');

%% Diagnostics used by the existing GRF QC figures

[alternation, firstHS, lastHS] = hs_alternation( ...
    rightEvents.hsTimeStamps, leftEvents.hsTimeStamps);
diagnostics = struct;
diagnostics.method = "lab_hysteresis";
diagnostics.thresholdSelectionMethod = selectionMethod;
diagnostics.thresholdOnFraction = onFraction;
diagnostics.thresholdOffFraction = offFraction;
diagnostics.thresholdSearch = thresholdSearch;
diagnostics.measuredSrate = fs;
diagnostics.filterMethod = "4th_order_zero_phase_Butterworth";
diagnostics.lowpassHz = opt.LowpassHz;
diagnostics.rightChannels = rightChannels;
diagnostics.leftChannels = leftChannels;
diagnostics.intervalStartLSLTime = t(1);
diagnostics.intervalEndLSLTime = t(end);
diagnostics.startGRFSample = firstSample;
diagnostics.endGRFSample = lastSample;
diagnostics.baselineMethod = "none";
diagnostics.rightBaseline = 0;
diagnostics.leftBaseline = 0;
diagnostics.thresholdReference = "shared_maximum";
diagnostics.sharedPeak = sharedPeak;
diagnostics.rightPeak = max(rightFiltered);
diagnostics.leftPeak = max(leftFiltered);
diagnostics.rightThresholdOn = thresholdOn;
diagnostics.leftThresholdOn = thresholdOn;
diagnostics.rightThresholdOff = thresholdOff;
diagnostics.leftThresholdOff = thresholdOff;
diagnostics.minIntervalSec = opt.MinInterval;
diagnostics.minIntervalSamples = minIntervalSamples;
diagnostics.maximumEventGRFFraction = opt.MaximumEventGRFFraction;
diagnostics.toSampleConvention = "last_in_contact";
diagnostics.rightDetection = rightDetection;
diagnostics.leftDetection = leftDetection;
diagnostics.nRHS = numel(rightEvents.hsTimeStamps);
diagnostics.nRTO = numel(rightEvents.toTimeStamps);
diagnostics.nLHS = numel(leftEvents.hsTimeStamps);
diagnostics.nLTO = numel(leftEvents.toTimeStamps);
diagnostics.medianRightStrideSec = safe_median(diff(rightEvents.hsTimeStamps));
diagnostics.medianLeftStrideSec = safe_median(diff(leftEvents.hsTimeStamps));
diagnostics.alternationFraction = alternation;
diagnostics.firstHeelStrike = firstHS;
diagnostics.lastHeelStrike = lastHS;
diagnostics.segmentTimeStamps = t;
diagnostics.rightRaw = rightRaw;
diagnostics.leftRaw = leftRaw;
diagnostics.rightFiltered = rightFiltered;
diagnostics.leftFiltered = leftFiltered;

qcFigure = gobjects(0);
if opt.Plot
    qcFigure = create_qc_figure(t, rightFiltered, leftFiltered, ...
        thresholdOn, thresholdOff, rightEvents, leftEvents, opt.FigureVisible);
end
end

function [right, left, rightCounts, leftCounts] = detect_both_sides( ...
        rightSignal, leftSignal, t, firstSample, on, off, minInterval, maxEventFraction)

[right, rightCounts] = detect_one_side( ...
    rightSignal, t, firstSample, on, off, minInterval, maxEventFraction);
[left, leftCounts] = detect_one_side( ...
    leftSignal, t, firstSample, on, off, minInterval, maxEventFraction);
end

function [events, counts] = detect_one_side( ...
        signal, t, firstSample, thresholdOn, thresholdOff, minInterval, maxEventFraction)

contact = false(size(signal));
state = false;
for k = 1:numel(signal)
    if ~state && signal(k) > thresholdOn
        state = true;
    elseif state && signal(k) < thresholdOff
        state = false;
    end
    contact(k) = state;
end
edges = diff([false; contact; false]);
hs = find(edges == 1);
to = find(edges == -1) - 1;
% The crop boundaries do not establish an observed landing or departure.
hs = hs(hs > 1);
to = to(to < numel(signal));
counts.candidateHS = numel(hs);
counts.candidateTO = numel(to);
maxEventGRF = maxEventFraction * max(signal);
validHS = signal(hs) < maxEventGRF;
validTO = signal(to) < maxEventGRF;
counts.amplitudeRejectedHS = sum(~validHS);
counts.amplitudeRejectedTO = sum(~validTO);
hs = hs(validHS);
to = to(validTO);
[hs, counts.intervalRejectedHS] = remove_close_events(hs, minInterval);
[to, counts.intervalRejectedTO] = remove_close_events(to, minInterval);
% Preserve observed edges; event order and missing partners are checked by QC.
events.hsSegmentSamples = hs;
events.toSegmentSamples = to;
events.hsGRFSamples = firstSample + hs - 1;
events.toGRFSamples = firstSample + to - 1;
events.hsTimeStamps = t(hs);
events.toTimeStamps = t(to);
end

function [events, rejected] = remove_close_events(events, minInterval)

keep = true(size(events));
lastKept = 1;
for k = 2:numel(events)
    if events(k) - events(lastKept) < minInterval
        keep(k) = false;
    else
        lastKept = k;
    end
end
rejected = sum(~keep);
events = events(keep);
end

function rows = event_rows(eventType, side, samples, t, firstSample)

n = numel(samples);
rows = table(repmat(eventType, n, 1), repmat(side, n, 1), ...
    double(samples(:)), double(firstSample + samples(:) - 1), ...
    t(samples), t(samples) - t(1), 'VariableNames', ...
    {'EventType', 'Side', 'SegmentSample', 'GRFSample', ...
     'LSLTime', 'TimeFromSegmentStartSec'});
end

function value = safe_median(x)

if isempty(x)
    value = NaN;
else
    value = median(x);
end
end

function [fraction, firstHS, lastHS] = hs_alternation(right, left)

t = [right; left];
sides = [repmat("Right", numel(right), 1); repmat("Left", numel(left), 1)];
[~, order] = sort(t);
sides = sides(order);
fraction = NaN;
firstHS = "";
lastHS = "";
if ~isempty(sides)
    firstHS = sides(1);
    lastHS = sides(end);
end
if numel(sides) > 1
    fraction = mean(sides(2:end) ~= sides(1:end-1));
end
end

function fig = create_qc_figure(t, right, left, on, off, rightEvents, leftEvents, visibility)

t = t - t(1);
fig = figure('Color', 'w', 'Name', 'GRF gait-event detection QC', ...
    'NumberTitle', 'off', 'Visible', char(string(visibility)), ...
    'Position', [50 50 1500 900]);
layout = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
axR = nexttile(layout, 1);
plot_side(axR, t, right, rightEvents, on, off, [0.00 0.45 0.74]);
ylabel(axR, 'Right GRF');
title(axR, 'Right: RHS and RTO');
axL = nexttile(layout, 2);
plot_side(axL, t, left, leftEvents, on, off, [0.80 0.15 0.55]);
ylabel(axL, 'Left GRF');
title(axL, 'Left: LHS and LTO');
axBoth = nexttile(layout, 3);
plot(axBoth, t, right, 'Color', [0.00 0.45 0.74]);
hold(axBoth, 'on');
plot(axBoth, t, left, 'Color', [0.80 0.15 0.55]);
plot(axBoth, t(rightEvents.hsSegmentSamples), right(rightEvents.hsSegmentSamples), 'gv');
plot(axBoth, t(leftEvents.hsSegmentSamples), left(leftEvents.hsSegmentSamples), 'go');
ylabel(axBoth, 'GRF (recorded units)');
xlabel(axBoth, 'Time from accepted interval start (s)');
title(axBoth, 'Both sides: heel-strike alternation');
legend(axBoth, {'Right GRF', 'Left GRF', 'RHS', 'LHS'}, 'Location', 'eastoutside');
grid(axBoth, 'on');
linkaxes([axR, axL, axBoth], 'x');
end

function plot_side(ax, t, signal, events, on, off, color)

plot(ax, t, signal, 'Color', color, 'LineWidth', 1);
hold(ax, 'on');
yline(ax, on, '--', 'On');
yline(ax, off, ':', 'Off');
plot(ax, t(events.hsSegmentSamples), signal(events.hsSegmentSamples), 'gv', ...
    'MarkerFaceColor', 'g', 'MarkerSize', 5);
plot(ax, t(events.toSegmentSamples), signal(events.toSegmentSamples), '^', ...
    'Color', [0.95 0.55 0], 'MarkerFaceColor', [0.95 0.55 0], 'MarkerSize', 5);
grid(ax, 'on');
end
