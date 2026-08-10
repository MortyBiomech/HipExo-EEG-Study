% =========================================================================
% Extract Step/Stance/Swing Time (s) for both left and right legs from gait_events.mat and plot them on the same chart
% =========================================================================
clc;
clear;

%% 1. Load Configurations
% Depends on the existing configuration file[cite: 2, 3]
run('config_paths.m');
run([current_subject, '_infos.m']); 

%% 2. Reconstruct Session Order
d = dir(data_path);
folderNames = {d([d.isdir]).name};
folderNames(ismember(folderNames, {'.','..'})) = [];
order_sessions = cell(1, 8);
order_sessions{1} = folderNames{contains(folderNames, 'NoExoPre')};
for k = 1:6
    hit = folderNames(contains(folderNames, sprintf('Exo%d', k)));
    if ~isempty(hit)
        order_sessions{k+1} = hit{1};
    else
        order_sessions{k+1} = sprintf('Exo%d_Missing', k); 
    end
end
order_sessions{8} = folderNames{contains(folderNames, 'NoExoPost')}; 
num_sessions = length(order_sessions);

%% 3. Initialize Data Storage (Mean and standard deviation for 6 metrics)
mean_step_R = NaN(num_sessions, 1); std_step_R = NaN(num_sessions, 1);
mean_stance_R = NaN(num_sessions, 1); std_stance_R = NaN(num_sessions, 1);
mean_swing_R = NaN(num_sessions, 1); std_swing_R = NaN(num_sessions, 1);

mean_step_L = NaN(num_sessions, 1); std_step_L = NaN(num_sessions, 1);
mean_stance_L = NaN(num_sessions, 1); std_stance_L = NaN(num_sessions, 1);
mean_swing_L = NaN(num_sessions, 1); std_swing_L = NaN(num_sessions, 1);

valid_conditions = cell(num_sessions, 1);

% Data loading path configuration
load_dir = fullfile('C:\2026SSArbeit\data\PilotTest2', subject_folder, experiment_day, 'processed_EMG');

%% 4. Data Processing Loop
fprintf('Starting Temporal Parameters Extraction for subject %s...\n', subject_id);

for s = 1:num_sessions
    current_session = order_sessions{s};
    valid_conditions{s} = current_session; 
    
    if contains(current_session, 'Missing')
        continue;
    end
    
    file_name = fullfile(load_dir, sprintf('%s_run-%s_gait_events.mat', current_session, run_id));
    if ~exist(file_name, 'file')
        continue;
    end
    
    load(file_name, 'all_events');
    
    % --- Extract Right Leg Parameters ---
    hs_r_times = [all_events(strcmp({all_events.type}, 'HS_R')).time];
    to_r_times = [all_events(strcmp({all_events.type}, 'TO_R')).time];
    step_r = []; stance_r = []; swing_r = [];
    
    for k = 1:(length(hs_r_times)-1)
        curr_hs = hs_r_times(k);
        next_hs = hs_r_times(k+1);
        to_idx = find(to_r_times > curr_hs & to_r_times < next_hs, 1);
        
        if ~isempty(to_idx)
            curr_to = to_r_times(to_idx);
            step_r(end+1) = next_hs - curr_hs;       % Full Step time
            stance_r(end+1) = curr_to - curr_hs;     % Stance phase time
            swing_r(end+1) = next_hs - curr_to;      % Swing phase time
        end
    end
    
    if ~isempty(step_r)
        mean_step_R(s) = mean(step_r); std_step_R(s) = std(step_r);
        mean_stance_R(s) = mean(stance_r); std_stance_R(s) = std(stance_r);
        mean_swing_R(s) = mean(swing_r); std_swing_R(s) = std(swing_r);
    end
    
    % --- Extract Left Leg Parameters ---
    hs_l_times = [all_events(strcmp({all_events.type}, 'HS_L')).time];
    to_l_times = [all_events(strcmp({all_events.type}, 'TO_L')).time];
    step_l = []; stance_l = []; swing_l = [];
    
    for k = 1:(length(hs_l_times)-1)
        curr_hs = hs_l_times(k);
        next_hs = hs_l_times(k+1);
        to_idx = find(to_l_times > curr_hs & to_l_times < next_hs, 1);
        
        if ~isempty(to_idx)
            curr_to = to_l_times(to_idx);
            step_l(end+1) = next_hs - curr_hs;
            stance_l(end+1) = curr_to - curr_hs;
            swing_l(end+1) = next_hs - curr_to;
        end
    end
    
    if ~isempty(step_l)
        mean_step_L(s) = mean(step_l); std_step_L(s) = std(step_l);
        mean_stance_L(s) = mean(stance_l); std_stance_L(s) = std(stance_l);
        mean_swing_L(s) = mean(swing_l); std_swing_L(s) = std(swing_l);
    end
end

%% 5. Comprehensive Plotting
% Clean up labels to improve readability
conditions_plotorder = {'NoExoPre', 'aquaplus', 'aqua', 'transparent', 'eco', 'sport', 'boost', 'NoExoPost'};
clean_labels = cell(num_sessions, 1);
for i = 1:num_sessions
    label = conditions_plotorder{i};
    clean_labels{i} = label;
end

figure('Name', 'Gait Temporal Parameters Overview', 'Position', [100, 100, 1100, 650], 'Color', 'w');
hold on; grid on;

% Set axes properties
ax = gca;
ax.GridLineStyle = '--';
ax.GridAlpha = 0.5;
ax.FontSize = 11;
ax.LineWidth = 1.2;

% Set left and right offsets (Core implementation: Left leg offsets left, Right leg offsets right)
offset_L = -0.12; 
offset_R =  0.12;
x_base = 1:num_sessions;

% Define plot properties
mrk_size = 8;
lw = 1.5;
cap_size = 5;

% Plot Left Leg - Unified blue color scheme
c_L = [0.2, 0.5, 0.9];
errorbar(x_base + offset_L, mean_step_L, std_step_L, 'o', 'MarkerSize', mrk_size, ...
    'MarkerEdgeColor', 'k', 'MarkerFaceColor', c_L, 'LineWidth', lw, 'CapSize', cap_size, 'Color', c_L);
errorbar(x_base + offset_L, mean_stance_L, std_stance_L, 'd', 'MarkerSize', mrk_size, ...
    'MarkerEdgeColor', 'k', 'MarkerFaceColor', c_L, 'LineWidth', lw, 'CapSize', cap_size, 'Color', c_L);
errorbar(x_base + offset_L, mean_swing_L, std_swing_L, 's', 'MarkerSize', mrk_size, ...
    'MarkerEdgeColor', 'k', 'MarkerFaceColor', c_L, 'LineWidth', lw, 'CapSize', cap_size, 'Color', c_L);

% Plot Right Leg - Unified red color scheme
c_R = [0.9, 0.3, 0.3];
errorbar(x_base + offset_R, mean_step_R, std_step_R, 'o', 'MarkerSize', mrk_size, ...
    'MarkerEdgeColor', 'k', 'MarkerFaceColor', c_R, 'LineWidth', lw, 'CapSize', cap_size, 'Color', c_R);
errorbar(x_base + offset_R, mean_stance_R, std_stance_R, 'd', 'MarkerSize', mrk_size, ...
    'MarkerEdgeColor', 'k', 'MarkerFaceColor', c_R, 'LineWidth', lw, 'CapSize', cap_size, 'Color', c_R);
errorbar(x_base + offset_R, mean_swing_R, std_swing_R, 's', 'MarkerSize', mrk_size, ...
    'MarkerEdgeColor', 'k', 'MarkerFaceColor', c_R, 'LineWidth', lw, 'CapSize', cap_size, 'Color', c_R);

% Set axes labels and limits
ax.XTick = x_base;
ax.XTickLabel = clean_labels;
ax.XTickLabelRotation = 30; 
xlim([0.5, num_sessions + 0.5]);
y_min = 0;
y_max = 1.2;
ylim([y_min, y_max]);

xlabel('Conditions', 'FontSize', 14, 'FontWeight', 'bold');
ylabel('Time (s)', 'FontSize', 14, 'FontWeight', 'bold');
title(sprintf('Comprehensive Temporal Parameters Overview - Subject: %s', bids_subject_id), 'FontSize', 16);

% Custom Legend - Generate dummy plots to accurately reflect the hand-drawn sketch's intent
h1 = plot(NaN, NaN, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 8);
h2 = plot(NaN, NaN, 'kd', 'MarkerFaceColor', 'k', 'MarkerSize', 8);
h3 = plot(NaN, NaN, 'ks', 'MarkerFaceColor', 'k', 'MarkerSize', 8);
h4 = plot(NaN, NaN, 's', 'MarkerEdgeColor', 'w', 'MarkerFaceColor', c_L, 'MarkerSize', 10);
h5 = plot(NaN, NaN, 's', 'MarkerEdgeColor', 'w', 'MarkerFaceColor', c_R, 'MarkerSize', 10);

legend([h1, h2, h3, h4, h5], ...
    {'Full Step Time', 'Stance Phase Time', 'Swing Phase Time', 'Left Leg (Offset Left)', 'Right Leg (Offset Right)'}, ...
    'Location', 'best', 'FontSize', 11, 'NumColumns', 2);

hold off;
fprintf('\nComprehensive plot generation complete!\n');