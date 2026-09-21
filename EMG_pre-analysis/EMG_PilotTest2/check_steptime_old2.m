% Extract Step Time (Right Leg) from saved gait_events.mat files and plot[cite: 2]
clc;
clear;

%% 1. Load Configurations[cite: 2]
run('config_paths.m');
run([current_subject, '_infos.m']); 

%% 2. Session Order[cite: 2]
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
order_sessions{8} = folderNames{contains(folderNames, 'NoExoPost')}; %[cite: 1]
num_sessions = length(order_sessions);

%% 3. Initialize Data Storage[cite: 2]
mean_step_time = NaN(num_sessions, 1);
std_step_time = NaN(num_sessions, 1);
valid_conditions = cell(num_sessions, 1);

% Data loading path configuration, matching the save path of the original script[cite: 2]
load_dir = fullfile('C:\2026SSArbeit\data\PilotTest2', subject_folder, experiment_day, 'processed_EMG');

%% 4. Data Processing Loop[cite: 2]
fprintf('Starting Step Time Calculation for subject %s...\n', subject_id);

for s = 1:num_sessions
    current_session = order_sessions{s};
    valid_conditions{s} = current_session; 
    
    % Skip missing sessions[cite: 2]  
    if contains(current_session, 'Missing')
        fprintf('Skipping missing session: %s\n', current_session);
        continue;
    end
    
    % Construct filename and load[cite: 2]
    file_name = fullfile(load_dir, sprintf('%s_run-%s_gait_events.mat', current_session, run_id));
    
    if ~exist(file_name, 'file')
        warning('File not found: %s', file_name);
        continue;
    end
    
    % Load the all_events variable[cite: 2]
    load(file_name, 'all_events');
    
    % Extract right leg HS times from the all_events structure[cite: 2]
    is_hs_r = strcmp({all_events.type}, 'HS_R');
    hs_r_times = [all_events(is_hs_r).time];
    
    % Calculate Step Time[cite: 2]
    if length(hs_r_times) >= 2
        step_times = diff(hs_r_times);
        
        mean_step_time(s) = mean(step_times);
        std_step_time(s) = std(step_times);
        fprintf('Session %s: Mean = %.3fs, SD = %.3fs\n', current_session, mean_step_time(s), std_step_time(s));
    else
        warning('Not enough HS_R events in session %s to calculate step time.', current_session);
    end
end

%% 5. Plot Vertical Scatter Error Bar Chart (X-axis: Condition, Y-axis: Step Time)[cite: 2]
% Clean up labels to improve readability[cite: 2]
conditions_plotorder = {'NoExoPre', 'aquaplus', 'aqua', 'transparent', 'eco', 'sport', 'boost', 'NoExoPost'};
clean_labels = cell(num_sessions, 1);
for i = 1:num_sessions
    label = conditions_plotorder{i};
    clean_labels{i} = label;
end

figure('Name', 'Step Time Across Conditions', 'Position', [150, 150, 900, 500], 'Color', 'w');

% Use standard vertical errorbar (X-axis coordinates are 1:num_sessions)[cite: 2]
h = errorbar(1:num_sessions, mean_step_time, std_step_time, 'o', ...
    'MarkerSize', 8, 'MarkerEdgeColor', 'k', 'MarkerFaceColor', [0.2 0.6 1], ...
    'LineWidth', 1.5, 'CapSize', 8, 'Color', 'k');

% Axes and formatting settings[cite: 2]
ax = gca;
ax.XTick = 1:num_sessions;
ax.XTickLabel = clean_labels;
% Rotate X-axis labels if they are too long and overlap[cite: 2]
ax.XTickLabelRotation = 45; 
ax.FontSize = 11;
ax.LineWidth = 1.2;

% Add grid lines, mainly in the Y-axis direction, to easily compare heights across different conditions[cite: 2]
grid on;
ax.GridLineStyle = '--';
ax.GridAlpha = 0.4;

% Swapped axis labels[cite: 2]
xlabel('Condition', 'FontSize', 14, 'FontWeight', 'bold');
ylabel('Step time right leg (s)', 'FontSize', 14, 'FontWeight', 'bold');
title(sprintf('Step Time Comparison - Subject: %s', bids_subject_id), 'FontSize', 16);

% Limit X-axis display range to leave aesthetic margins on both sides[cite: 2]
xlim([0.5, num_sessions + 0.5]);

% Adaptive Y-axis range[cite: 2]
y_min = min(mean_step_time - std_step_time) - 0.1;
y_max = max(mean_step_time + std_step_time) + 0.2;
ylim([y_min, y_max]);

fprintf('\nPlot generation complete!\n');