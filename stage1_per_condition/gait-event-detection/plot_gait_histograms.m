function plot_gait_histograms(HS_R, TO_R, HS_L, TO_L)
% PLOT_GAIT_HISTOGRAMS  Validate gait event detection via phase duration histograms.
%
% Inputs:
%   HS_R, TO_R, HS_L, TO_L – event structs from detect_gait_events

    %% --- Compute phase durations --------------------------------------------

    % Stance: HS to TO of same leg
    stance_R = TO_R.timestamps - HS_R.timestamps;
    stance_L = TO_L.timestamps - HS_L.timestamps;

    % Swing: TO to next HS of same leg
    swing_R  = HS_R.timestamps(2:end) - TO_R.timestamps(1:end-1);
    swing_L  = HS_L.timestamps(2:end) - TO_L.timestamps(1:end-1);

    % Double support: overlap when both feet are on the ground
    % DS1 (right loading): right HS → left TO  (left foot still on plate)
    % DS2 (left loading):  left HS → right TO  (right foot still on plate)
    DS1 = compute_double_support(HS_R.timestamps, TO_L.timestamps);
    DS2 = compute_double_support(HS_L.timestamps, TO_R.timestamps);
    double_support = [DS1; DS2];

    %% --- Print summary ------------------------------------------------------
    fprintf('\n=== Gait Phase Summary ===\n');
    fprintf('                    Mean ± SD        Min     Max\n');
    fprintf('  Stance R  : %5.0f ± %4.0f ms   %5.0f   %5.0f ms\n', ...
        stats_ms(stance_R));
    fprintf('  Stance L  : %5.0f ± %4.0f ms   %5.0f   %5.0f ms\n', ...
        stats_ms(stance_L));
    fprintf('  Swing  R  : %5.0f ± %4.0f ms   %5.0f   %5.0f ms\n', ...
        stats_ms(swing_R));
    fprintf('  Swing  L  : %5.0f ± %4.0f ms   %5.0f   %5.0f ms\n', ...
        stats_ms(swing_L));
    fprintf('  Dbl Supp  : %5.0f ± %4.0f ms   %5.0f   %5.0f ms\n', ...
        stats_ms(double_support));

    %% --- Plot histograms ----------------------------------------------------
    figure('Name', 'Gait Phase Histograms', 'Color', 'w');

    subplot(2,3,1);
    plot_hist(stance_R * 1000, 'Stance — Right', 'ms', [0.2 0.4 0.8]);
    set(gca, 'FontSize', 14)

    subplot(2,3,4);
    plot_hist(stance_L * 1000, 'Stance — Left', 'ms', [0.8 0.2 0.2]);
    set(gca, 'FontSize', 14)

    subplot(2,3,2);
    plot_hist(swing_R * 1000, 'Swing — Right', 'ms', [0.2 0.4 0.8]);
    set(gca, 'FontSize', 14)

    subplot(2,3,5);
    plot_hist(swing_L * 1000, 'Swing — Left', 'ms', [0.8 0.2 0.2]);
    set(gca, 'FontSize', 14)

    subplot(2,3,[3 6]);
    plot_hist(double_support * 1000, 'Double Support', 'ms', [0.4 0.7 0.4]);
    set(gca, 'FontSize', 14)
end

% =========================================================================
function DS = compute_double_support(HS_a, TO_b)
% For each HS in leg A, find the nearest TO in leg B that comes AFTER it.
% DS = TO_b - HS_a (both feet on ground during this window)
    DS = nan(numel(HS_a), 1);
    for k = 1:numel(HS_a)
        % Find first TO_b that occurs after HS_a(k)
        idx = find(TO_b > HS_a(k), 1, 'first');
        if ~isempty(idx)
            ds = TO_b(idx) - HS_a(k);
            % Sanity check: DS should be positive and shorter than a step
            if ds > 0 && ds < 0.4
                DS(k) = ds;
            end
        end
    end
    DS = DS(~isnan(DS));
end

% =========================================================================
function plot_hist(data, title_str, unit, color)
    histogram(data, 30, 'FaceColor', color, 'EdgeColor', 'none', 'FaceAlpha', 0.8);
    xline(mean(data), '--k', sprintf('%.0f %s', mean(data), unit), ...
        'LineWidth', 1.5, 'LabelHorizontalAlignment', 'left');
    title(title_str);
    xlabel(unit); ylabel('Count');
    grid on;
end

% =========================================================================
function out = stats_ms(x)
    out = [mean(x)*1000, std(x)*1000, min(x)*1000, max(x)*1000];
end