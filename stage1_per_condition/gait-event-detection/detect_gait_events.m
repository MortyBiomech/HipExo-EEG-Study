function [HS_R, TO_R, HS_L, TO_L] = detect_gait_events(GRF, Right_leg_indx, Left_leg_indx, varargin)
% DETECT_GAIT_EVENTS  Detect heel strikes and toe-offs from treadmill GRF.
%
% Inputs:
%   GRF             – GRF stream struct as loaded by load_xdf
%   Right_leg_indx  – channel indices for right leg  (e.g. [1 4 5 8])
%   Left_leg_indx   – channel indices for left leg   (e.g. [2 3 6 7])
%
% Optional name-value pairs:
%   'ThresholdOn'   – contact onset  threshold as fraction of max GRF [default: 0.03]
%   'ThresholdOff'  – contact offset threshold as fraction of max GRF [default: 0.01]
%   'MinInterval'   – minimum time between same-type events in seconds [default: 0.6]
%   'MarkerCh'      – index of marker channel for walking period [default: 9]
%   'Plot'          – true/false [default: true]
%
% Outputs:
%   HS_R, TO_R, HS_L, TO_L – structs with fields:
%       .samples    – sample indices (relative to walking period start)
%       .timestamps – LSL timestamps (use these to epoch EEG/EMG)

    %% --- Parse inputs ---------------------------------------------------
    p = inputParser;
    addRequired(p,  'GRF');
    addRequired(p,  'Right_leg_indx');
    addRequired(p,  'Left_leg_indx');
    addParameter(p, 'ThresholdOn',  0.03);
    addParameter(p, 'ThresholdOff', 0.01);
    addParameter(p, 'MinInterval',  0.6);
    addParameter(p, 'MarkerCh',     9);
    addParameter(p, 'Plot',         true);
    addParameter(p, 'Verbose',      true);
    parse(p, GRF, Right_leg_indx, Left_leg_indx, varargin{:});
    opt = p.Results;

    %% --- Extract signals ------------------------------------------------
    fs         = GRF.info.effective_srate;
    timestamps = GRF.time_stamps;
    % marker     = GRF.time_series(opt.MarkerCh, :);             %%%%%%%% uncomment when GRF has 9 channels

    % --- Crop to walking period using marker channel ---
    % idx_start = find(marker ==  1, 1, 'first');                %%%%%%%% uncomment when GRF has 9 channels
    % idx_end   = find(marker == -1, 1, 'first');                %%%%%%%% uncomment when GRF has 9 channels
    % idx_start = 6540;
    % idx_end   = 44330;

    if isempty(idx_start) || isempty(idx_end)
        warning('Marker channel has no START/END markers. Using full recording.');
        idx_start = 1;
        idx_end   = size(GRF.time_series, 2);
    end

    if opt.Verbose
        fprintf('\n=== Gait Event Detection ===\n');
        fprintf('  fs (effective)  : %.4f Hz\n',  fs);
        fprintf('  Walking period  : %.2f s → %.2f s (%.1f s)\n', ...
            timestamps(idx_start), timestamps(idx_end), ...
            timestamps(idx_end) - timestamps(idx_start));
    end

    % --- Sum corner sensors per leg, crop to walking period ---
    GRF_R      = sum(double(GRF.time_series(Right_leg_indx, idx_start:idx_end)), 1)';
    GRF_L      = sum(double(GRF.time_series(Left_leg_indx,  idx_start:idx_end)), 1)';
    timestamps = timestamps(idx_start:idx_end);

    % --- low-pass filter ---
    fc     = 15;                                    % cutoff Hz
    [b, a] = butter(4, fc / (fs/2), 'low');         % 4th order Butterworth
    GRF_R  = filtfilt(b, a, GRF_R);                 % zero-phase
    GRF_L  = filtfilt(b, a, GRF_L);

    % --- Compute thresholds from walking period signal ---
    GRF_max       = max([GRF_R; GRF_L]);
    threshold_on  = opt.ThresholdOn  * GRF_max;
    threshold_off = opt.ThresholdOff * GRF_max;
    min_interval  = round(opt.MinInterval * fs);

    if opt.Verbose
        fprintf('  Threshold on    : %.1f  (%.0f%% of max)\n', threshold_on,  opt.ThresholdOn  * 100);
        fprintf('  Threshold off   : %.1f  (%.0f%% of max)\n', threshold_off, opt.ThresholdOff * 100);
        fprintf('  Min interval    : %.0f samples (%.0f ms)\n', min_interval, opt.MinInterval * 1000);
    end

    %% --- Detect events --------------------------------------------------
    [HS_R, TO_R] = detect_leg(GRF_R, timestamps, threshold_on, threshold_off, min_interval, 'Right', opt.Verbose);
    [HS_L, TO_L] = detect_leg(GRF_L, timestamps, threshold_on, threshold_off, min_interval, 'Left', opt.Verbose);

    %% --- Plot -----------------------------------------------------------
    if opt.Plot
        t = timestamps - timestamps(1);

        figure('Name', 'Gait Event Detection', 'Color', 'w');

        subplot(3,1,1); hold on;
        plot(t, GRF_R, 'b', 'LineWidth', 1);
        yline(threshold_on,  '--k', 'On',  'LabelHorizontalAlignment', 'left');
        yline(threshold_off, '--g', 'Off', 'LabelHorizontalAlignment', 'left');
        plot(t(HS_R.samples), GRF_R(HS_R.samples), 'gv', 'MarkerFaceColor', 'g', 'MarkerSize', 7);
        plot(t(TO_R.samples), GRF_R(TO_R.samples), 'r^', 'MarkerFaceColor', 'r', 'MarkerSize', 7);
        legend('GRF right', 'Threshold on', 'Threshold off', 'Heel Strike', 'Toe Off', 'Location', 'best');
        ylabel('GRF'); title('Right Leg'); grid on;

        subplot(3,1,2); hold on;
        plot(t, GRF_L, 'r', 'LineWidth', 1);
        yline(threshold_on,  '--k', 'On',  'LabelHorizontalAlignment', 'left');
        yline(threshold_off, '--g', 'Off', 'LabelHorizontalAlignment', 'left');
        plot(t(HS_L.samples), GRF_L(HS_L.samples), 'gv', 'MarkerFaceColor', 'g', 'MarkerSize', 7);
        plot(t(TO_L.samples), GRF_L(TO_L.samples), 'r^', 'MarkerFaceColor', 'r', 'MarkerSize', 7);
        legend('GRF left', 'Threshold on', 'Threshold off', 'Heel Strike', 'Toe Off', 'Location', 'best');
        ylabel('GRF'); title('Left Leg'); grid on;

        subplot(3,1,3); hold on;
        plot(t, GRF_R, 'b', 'LineWidth', 1);
        plot(t, GRF_L, 'r', 'LineWidth', 1);
        plot(t(HS_R.samples), GRF_R(HS_R.samples), 'o', 'Color', 'g', 'MarkerFaceColor', 'g', 'MarkerSize', 7);
        plot(t(TO_R.samples), GRF_R(TO_R.samples), 'o', 'Color', 'r', 'MarkerFaceColor', 'r', 'MarkerSize', 7);
        plot(t(HS_L.samples), GRF_L(HS_L.samples), 'o', 'Color', 'g', 'MarkerFaceColor', 'w', 'MarkerSize', 7);
        plot(t(TO_L.samples), GRF_L(TO_L.samples), 'o', 'Color', 'r', 'MarkerFaceColor', 'w', 'MarkerSize', 7);
        legend('GRF right', 'GRF left', 'HS right', 'TO right', 'HS left', 'TO left', 'Location', 'best');
        ylabel('GRF'); xlabel('Time (s)'); title('Both Legs'); grid on;
    end
end

% =========================================================================
function [HS, TO] = detect_leg(GRF, timestamps, threshold_on, threshold_off, min_interval, label, verbose)
    
    % --- Hysteresis binarisation ---
    contact = false(size(GRF));
    state   = false;
    for k   = 1:numel(GRF)
        if ~state && GRF(k) > threshold_on
            state = true;
        elseif state && GRF(k) < threshold_off
            state = false;
        end
        contact(k) = state;
    end

    % --- Extract edges ---
    d  = diff([0; contact(:); 0]);
    hs = find(d ==  1);
    to = find(d == -1) - 1;

    % --- Remove events where GRF is too high at detection point ---
    % Real HS/TO occur near zero, not during elevated GRF
    max_event_grf = 0.15 * max(GRF);   % 15% of peak — adjust if needed
    
    valid_hs = GRF(hs) < max_event_grf;
    valid_to = GRF(to) < max_event_grf;
    
    if any(~valid_hs) 
        if verbose
            fprintf('  %s: removed %d HS with GRF > %.1f at detection point\n', ...
                label, sum(~valid_hs), max_event_grf);
        end
    end
    if any(~valid_to)
        if verbose
            fprintf('  %s: removed %d TO with GRF > %.1f at detection point\n', ...
                label, sum(~valid_to), max_event_grf);
        end
    end
    
    hs = hs(valid_hs);
    to = to(valid_to);

    % --- Remove events too close together ---
    hs = remove_close_events(hs, min_interval);
    to = remove_close_events(to, min_interval);

    % --- Ensure alternating HS/TO starting with HS ---
    if ~isempty(to) && ~isempty(hs) && to(1) < hs(1)
        to(1) = [];
    end
    n  = min(numel(hs), numel(to));
    hs = hs(1:n);
    to = to(1:n);

    HS.samples    = hs;
    HS.timestamps = timestamps(hs)';
    TO.samples    = to;
    TO.timestamps = timestamps(to)';

    if verbose
        fprintf('  %s: %d heel strikes, %d toe-offs detected\n', label, n, n);
    end
end

% =========================================================================
function events = remove_close_events(events, min_interval)
    if numel(events) < 2, return; end
    keep = true(size(events));
    for k = 2:numel(events)
        if keep(k) && (events(k) - events(find(keep(1:k-1), 1, 'last'))) < min_interval
            keep(k) = false;
        end
    end
    events = events(keep);
end