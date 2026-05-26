function check_sampling_regularity(timestamps, label)
% CHECK_SAMPLING_REGULARITY  Diagnose timing regularity of a recorded signal.
%
% Inputs:
%   timestamps  – timestamp vector (seconds), as recorded by LSL or your DAQ
%   label       – string label for the stream (e.g. 'GRF', 'EEG', 'EMG')

    if nargin < 2, label = 'Signal'; end

    dt      = diff(timestamps);
    dt_mean = mean(dt);
    dt_std  = std(dt);
    fs_nom  = 1 / dt_mean;
    gap_idx = find(dt > 2 * dt_mean);

    %% --- Print diagnostics -------------------------------------------------
    fprintf('\n=== %s ===\n', label);
    fprintf('  Samples       : %d\n',       numel(timestamps));
    fprintf('  Duration      : %.3f s\n',   timestamps(end) - timestamps(1));
    fprintf('  Nominal fs    : %.4f Hz\n',  fs_nom);
    fprintf('  dt mean       : %.6f s\n',   dt_mean);
    fprintf('  dt std        : %.6f s  (%.4f%% of mean)\n', dt_std, 100*dt_std/dt_mean);
    fprintf('  dt min/max    : %.6f / %.6f s\n', min(dt), max(dt));
    fprintf('  Gaps (>2*dt)  : %d\n',       numel(gap_idx));

    if ~isempty(gap_idx)
        fprintf('  Gap locations:\n');
        for k = 1:min(numel(gap_idx), 10)
            fprintf('    sample %d: dt = %.4f s (~%.1f missing)\n', ...
                gap_idx(k), dt(gap_idx(k)), dt(gap_idx(k))/dt_mean - 1);
        end
    end

    %% --- Verdict -----------------------------------------------------------
    fprintf('\n  Verdict: ');
    if dt_std/dt_mean < 0.001 && isempty(gap_idx)
        fprintf('UNIFORM — safe to treat fs as constant (%.4f Hz).\n', fs_nom);
    elseif dt_std/dt_mean < 0.01 && isempty(gap_idx)
        fprintf('MINOR JITTER — fs ~ %.4f Hz; use timestamps for time measures.\n', fs_nom);
    else
        fprintf('IRREGULAR — do NOT assume constant fs. Use timestamps directly.\n');
    end

    %% --- Plots -------------------------------------------------------------
    figure('Name', sprintf('Sampling regularity: %s', label), 'Color', 'w');

    % --- Subplot 1: dt histogram ---
    subplot(2,1,1);
    histogram(dt * 1000, 300, 'FaceColor', [0.2 0.5 0.8], 'EdgeColor', 'none');
    xline(dt_mean*1000, 'r--', sprintf('Mean = %.4f ms', dt_mean*1000), ...
        'LineWidth', 1.5, 'LabelHorizontalAlignment', 'left');
    xlabel('dt (ms)'); ylabel('Count');
    title(sprintf('%s — inter-sample interval distribution', label));
    grid on;

    % --- Subplot 2: cumulative drift (1 point per second — memory safe) ---
    subplot(2,1,2);
    samp_per_sec = round(fs_nom);
    n_sec        = floor(numel(dt) / samp_per_sec);
    t_sec        = (1:n_sec)';
    drift_ms     = arrayfun(@(k) ...
        sum(dt(1:k*samp_per_sec))*1000 - k*samp_per_sec*dt_mean*1000, t_sec);
    plot(t_sec, drift_ms, 'k', 'LineWidth', 1.5);
    yline(0, 'r--', 'LineWidth', 1);
    xlabel('Time (s)'); ylabel('Cumulative drift (ms)');
    title('Drift from ideal uniform grid');
    grid on;
end