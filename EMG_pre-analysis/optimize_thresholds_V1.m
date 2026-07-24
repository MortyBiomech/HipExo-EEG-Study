function [on, off] = optimize_thresholds_V1(GRF, Right_leg_indx, Left_leg_indx)

    on_values  = 0.01:0.005:0.06;
    off_values = 0.01:0.005:0.06;

    results = [];

    for on = on_values
        for off = off_values
            if off >= on, continue; end

            try
                [HS_R, TO_R, HS_L, TO_L] = detect_gait_events(GRF, ...
                    Right_leg_indx, Left_leg_indx, ...
                    'ThresholdOn',  on,  ...
                    'ThresholdOff', off, ...
                    'Plot',         false, ...
                    'Verbose',      false);

                if numel(HS_R.samples) < 2 || numel(HS_L.samples) < 2 || ...
                   numel(TO_R.samples) < 2 || numel(TO_L.samples) < 2
                    continue;
                end

                % Calculate intervals using a robust pairing method to avoid dimensionality errors caused by mismatched array lengths
                stance_R = compute_intervals(HS_R.timestamps, TO_R.timestamps);
                stance_L = compute_intervals(HS_L.timestamps, TO_L.timestamps);
                swing_R  = compute_intervals(TO_R.timestamps, HS_R.timestamps);
                swing_L  = compute_intervals(TO_L.timestamps, HS_L.timestamps);
                
                DS1      = compute_intervals(HS_R.timestamps, TO_L.timestamps);
                DS2      = compute_intervals(HS_L.timestamps, TO_R.timestamps);
                DS       = [DS1; DS2];

                % Ensure that a valid time interval has been calculated
                if numel(DS) < 2 || isempty(stance_R) || isempty(stance_L) || isempty(swing_R) || isempty(swing_L)
                    continue; 
                end

                sd_stance_R = std(stance_R);
                sd_stance_L = std(stance_L);
                sd_swing_R  = std(swing_R);
                sd_swing_L  = std(swing_L);
                sd_DS       = std(DS);

                fprintf('on=%.3f off=%.3f | SD: stR=%5.1f stL=%5.1f swR=%5.1f swL=%5.1f DS=%5.1f ms\n', ...
                    on, off, sd_stance_R, sd_stance_L, sd_swing_R, sd_swing_L, sd_DS);

                results(end+1, :) = [on, off, ...
                    sd_stance_R, sd_stance_L, ...
                    sd_swing_R,  sd_swing_L,  sd_DS];

            catch ME
                % If debugging is required, you can uncomment the line below to view the specific error message
                % disp(ME.message);
                continue;
            end
        end
    end

    if isempty(results)
        error('No valid threshold combination found. The extracted data phase might be too noisy or too short.');
    end

    %% --- Pareto front ------------------------------------------------------
    % A combination is Pareto-optimal if no other combination is better
    % on ALL five SDs simultaneously
    sd_cols   = 3:7;   % columns containing the five SDs
    n         = size(results, 1);
    is_pareto = true(n, 1);

    for i = 1:n
        for j = 1:n
            if i == j, continue; end
            % j dominates i if it is <= on all SDs and < on at least one
            if all(results(j, sd_cols) <= results(i, sd_cols)) && ...
               any(results(j, sd_cols) <  results(i, sd_cols))
                is_pareto(i) = false;
                break;
            end
        end
    end

    pareto = results(is_pareto, :);
    pareto = sortrows(pareto, 3);   % sort Pareto front by sd_stance_R for display

    fprintf('\n=== Pareto-optimal combinations (%d found) ===\n', size(pareto,1));
    fprintf('  On     Off   | SD_StanceR  SD_StanceL  SD_SwingR  SD_SwingL  SD_DS\n');
    fprintf('  -----------------------------------------------------------------------\n');
    for k = 1:size(pareto, 1)
        fprintf('  %.3f  %.3f  |  %6.1f ms   %6.1f ms   %6.1f ms  %6.1f ms  %6.1f ms\n', ...
            pareto(k,1), pareto(k,2), ...
            pareto(k,3), pareto(k,4), pareto(k,5), pareto(k,6), pareto(k,7));
    end

    [on, off] = deal(pareto(1,1), pareto(1,2));
end

% =========================================================================
function intervals = compute_intervals(start_events, end_events)
% Iterate through each timestamp in `start_events` and find the first timestamp in `end_events` that immediately follows it
% The result is automatically multiplied by 1000 to convert it to milliseconds (ms)
    intervals = nan(numel(start_events), 1);
    for k = 1:numel(start_events)
        idx = find(end_events > start_events(k), 1, 'first');
        if ~isempty(idx)
            intervals(k) = (end_events(idx) - start_events(k)) * 1000;
        end
    end
    intervals = intervals(~isnan(intervals));
end