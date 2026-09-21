function [on, off, candidates] = optimize_grf_thresholds(detectCandidate, onValues, offValues)
% OPTIMIZE_GRF_THRESHOLDS Search the laboratory On/Off grid for one interval.
% detectCandidate(on, off) returns right/left event structs with
% hsTimeStamps and toTimeStamps. Signals are filtered once by the caller.
% Selection follows optimize_thresholds_V1: Pareto front of five interval
% SDs, then minimum right stance SD. Counts and exact cycle order are
% reported for review; they do not change the laboratory selection rule.
% Interval scores use the first later end event, as in the laboratory code.
% They are consistency scores and do not establish event accuracy.

validateattributes(onValues, {'numeric'}, ...
    {'vector', 'nonempty', 'real', 'finite', 'positive', '<', 1});
validateattributes(offValues, {'numeric'}, ...
    {'vector', 'nonempty', 'real', 'finite', 'nonnegative', '<', 1});
onValues = unique(double(onValues(:)'), 'stable');
offValues = unique(double(offValues(:)'), 'stable');

pairs = zeros(0, 2);
for on = onValues
    for off = offValues
        if off < on
            pairs(end + 1, :) = [on, off]; %#ok<AGROW>
        end
    end
end
if isempty(pairs)
    error('hipexo:NoThresholdPairs', 'The threshold grid must contain Off < On.');
end

n = size(pairs, 1);
counts = zeros(n, 6);
scores = nan(n, 5);
status = repmat("too_few_events", n, 1);
for k = 1:n
    % Execution errors must reach the caller with their original message.
    [right, left] = detectCandidate(pairs(k, 1), pairs(k, 2));
    rhs = right.hsTimeStamps(:);
    rto = right.toTimeStamps(:);
    lhs = left.hsTimeStamps(:);
    lto = left.toTimeStamps(:);
    [complete, invalid] = count_cycle_order(rhs, rto, lhs, lto);
    counts(k, :) = [numel(rhs), numel(rto), numel(lhs), numel(lto), complete, invalid];
    if any(counts(k, 1:4) < 2)
        continue;
    end
    stanceR = first_later_intervals(rhs, rto);
    stanceL = first_later_intervals(lhs, lto);
    swingR = first_later_intervals(rto, rhs);
    swingL = first_later_intervals(lto, lhs);
    doubleSupport = [first_later_intervals(rhs, lto); first_later_intervals(lhs, rto)];
    if numel(doubleSupport) < 2 || isempty(stanceR) || isempty(stanceL) || ...
            isempty(swingR) || isempty(swingL)
        status(k) = "too_few_intervals";
        continue;
    end
    scores(k, :) = [std(stanceR), std(stanceL), std(swingR), ...
        std(swingL), std(doubleSupport)];
    status(k) = "scored";
end

valid = all(isfinite(scores), 2);
pareto = valid;
validRows = find(valid)';
for i = validRows
    for j = validRows
        if all(scores(j, :) <= scores(i, :)) && any(scores(j, :) < scores(i, :))
            pareto(i) = false;
            break;
        end
    end
end
if ~any(pareto)
    error('hipexo:NoScorableThresholds', ...
        ['None of the %d threshold pairs produced enough events and intervals ' ...
         'for the laboratory SD score. Inspect the accepted GRF interval.'], n);
end
paretoRows = find(pareto);
[~, order] = sort(scores(paretoRows, 1), 'ascend');
selectedRow = paretoRows(order(1));
selected = false(n, 1);
selected(selectedRow) = true;
on = pairs(selectedRow, 1);
off = pairs(selectedRow, 2);

candidates = array2table([pairs, counts, scores], 'VariableNames', { ...
    'ThresholdOn', 'ThresholdOff', 'RHSCount', 'RTOCount', 'LHSCount', 'LTOCount', ...
    'CompleteOrderCycleCount', 'InvalidOrderCycleCount', ...
    'SDStanceRMs', 'SDStanceLMs', 'SDSwingRMs', 'SDSwingLMs', 'SDDoubleSupportMs'});
candidates.ValidForOptimization = valid;
candidates.IsPareto = pareto;
candidates.Selected = selected;
candidates.Status = status;
end

function intervals = first_later_intervals(startEvents, endEvents)

intervals = nan(numel(startEvents), 1);
for k = 1:numel(startEvents)
    idx = find(endEvents > startEvents(k), 1, 'first');
    if ~isempty(idx)
        intervals(k) = 1000 * (endEvents(idx) - startEvents(k));
    end
end
intervals = intervals(isfinite(intervals));
end

function [complete, invalid] = count_cycle_order(rhs, rto, lhs, lto)
% Count exact RHS-LTO-LHS-RTO-RHS sequences without duration/edge exclusion.

events = [rhs, ones(size(rhs)); rto, 4 * ones(size(rto)); ...
    lhs, 3 * ones(size(lhs)); lto, 2 * ones(size(lto))];
events = sortrows(events, 1);
rhsRows = find(events(:, 2) == 1);
complete = 0;
for k = 1:numel(rhsRows) - 1
    rows = rhsRows(k):rhsRows(k + 1);
    if isequal(events(rows, 2)', [1 2 3 4 1]) && all(diff(events(rows, 1)) > 0)
        complete = complete + 1;
    end
end
invalid = max(0, numel(rhsRows) - 1) - complete;
end
