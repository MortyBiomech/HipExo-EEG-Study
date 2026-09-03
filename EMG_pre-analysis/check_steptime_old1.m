% Extract Step, Stance, and Swing Times (Right Leg) from saved gait_events.mat files and plot
clc;
clear;
close all;

%% 1. Load Configurations
run('config_paths.m');
run([current_subject, '_infos.m']); 

%% 2. Session Order
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

%% 3. Initialize Data Storage
% Preallocate arrays for Means and SDs of all 3 features
mean_step_time   = NaN(num_sessions, 1); std_step_time   = NaN(num_sessions, 1);
mean_stance_time = NaN(num_sessions, 1); std_stance_time = NaN(num_sessions, 1);
mean_swing_time  = NaN(num_sessions, 1); std_swing_time  = NaN(num_sessions, 1);

valid_conditions = cell(num_sessions, 1);

% Data loading path configuration, matching the save path of the original script
load_dir = fullfile('C:\2026SSArbeit\data\PilotTest2', subject_folder, experiment_day, 'processed_EMG');

%% 4. Data Processing Loop
fprintf('Starting Gait Temporal Parameters Calculation for subject %s...\n', subject_id);

for s = 1:num_sessions
    current_session = order_sessions{s};
    valid_conditions{s} = current_session; 
    
    % Skip missing sessions
    if contains(current_session, 'Missing')
        fprintf('Skipping missing session: %s\n', current_session);
        continue;
    end
    
    % Construct filename and load
    file_name = fullfile(load_dir, sprintf('%s_run-%s_gait_events.mat', current_session, run_id));
    
    if ~exist(file_name, 'file')
        warning('File not found: %s', file_name);
        continue;
    end
    
    % Load the all_events variable
    load(file_name, 'all_events');
    
    % Extract right leg HS and TO times from the all_events structure
    hs_r_times = [all_events(strcmp({all_events.type}, 'HS_R')).time];
    to_r_times = [all_events(strcmp({all_events.type}, 'TO_R')).time];
    
    % Local temporary vectors for the current session's cycles
    step_vec   = [];
    stance_vec = [];
    swing_vec  = [];
    
    % Loop through consecutive HS points to calculate parameters per stride cycle
    for k = 1:(length(hs_r_times)-1)
        curr_hs = hs_r_times(k);
        next_hs = hs_r_times(k+1);
        
        % Find a valid TO_R that occurs between these two consecutive HS_R points
        to_idx = find(to_r_times > curr_hs & to_r_times < next_hs, 1);
        
        if ~isempty(to_idx)
            curr_to = to_r_times(to_idx);
            
            step_vec(end+1)   = next_hs - curr_hs;   % Full Stride/Step Time
            stance_vec(end+1) = curr_to - curr_hs;   % Stance Duration (s)
            swing_vec(end+1)  = next_hs - curr_to;   % Swing Duration (s)
        end
    end
    
    % Calculate and store descriptive statistics
    if ~isempty(step_vec)
        mean_step_time(s)   = mean(step_vec);   std_step_time(s)   = std(step_vec);
        mean_stance_time(s) = mean(stance_vec); std_stance_time(s) = std(stance_vec);
        mean_swing_time(s)  = mean(swing_vec);  std_swing_time(s)  = std(swing_vec);
        
        fprintf('Session %s: Step=%.3fs, Stance=%.3fs, Swing=%.3fs\n', ...
            current_session, mean_step_time(s), mean_stance_time(s), mean_swing_time(s));
    else
        warning('Not enough synchronized gait events in session %s.', current_session);
    end
end

%% 5. Plot Vertical Scatter Error Bar Chart
% Clean up labels to improve readability
conditions_plotorder = {'NoExoPre', 'aquaplus', 'aqua', 'transparent', 'eco', 'sport', 'boost', 'NoExoPost'};
clean_labels = cell(num_sessions, 1);
for i = 1:num_sessions
    clean_labels{i} = conditions_plotorder{i};
end

figure('Name', 'Gait Temporal Parameters Across Conditions', 'Position', [150, 150, 1000, 600], 'Color', 'w');
hold on;

% Define plotting aesthetics
mrk_size = 8;
lw = 1.5;
cap_size = 6;
x_base = 1:num_sessions;

% Plot Error Bars for each parameter with distinctive markers
% Full Step Time (Circle Marker, Blue/Cyan theme)
h_step = errorbar(x_base, mean_step_time, std_step_time, 'o', ...
    'MarkerSize', mrk_size, 'MarkerEdgeColor', 'k', 'MarkerFaceColor', [0.2 0.6 1.0], ...
    'LineWidth', lw, 'CapSize', cap_size, 'Color', [0.2 0.6 1.0]);

% Stance Phase Time (Diamond Marker, Orange/Amber theme)
h_stance = errorbar(x_base, mean_stance_time, std_stance_time, 'd', ...
    'MarkerSize', mrk_size, 'MarkerEdgeColor', 'k', 'MarkerFaceColor', [1.0 0.6 0.2], ...
    'LineWidth', lw, 'CapSize', cap_size, 'Color', [1.0 0.6 0.2]);

% Swing Phase Time (Square Marker, Green theme)
h_swing = errorbar(x_base, mean_swing_time, std_swing_time, 's', ...
    'MarkerSize', mrk_size, 'MarkerEdgeColor', 'k', 'MarkerFaceColor', [0.2 0.7 0.2], ...
    'LineWidth', lw, 'CapSize', cap_size, 'Color', [0.2 0.7 0.2]);

% Axes and formatting settings
ax = gca;
ax.XTick = 1:num_sessions;
ax.XTickLabel = clean_labels;
ax.XTickLabelRotation = 45; 
ax.FontSize = 11;
ax.LineWidth = 1.2;

% Add grid lines in both directions
grid on;
ax.GridLineStyle = '--';
ax.GridAlpha = 0.4;

% Axis labels and titles
xlabel('Condition', 'FontSize', 14, 'FontWeight', 'bold');
ylabel('Time (s)', 'FontSize', 14, 'FontWeight', 'bold');
title(sprintf('Gait Temporal Parameters Comparison - Subject: %s', bids_subject_id), 'FontSize', 16);

% Setup legend
legend([h_step, h_stance, h_swing], ...
    {'Full Step Time', 'Stance Phase Time', 'Swing Phase Time'}, ...
    'Location', 'best', 'FontSize', 11);

% Limit X-axis display range
xlim([0.5, num_sessions + 0.5]);


% Adaptive Y-axis range based on all data points
all_min = min([mean_step_time - std_step_time; mean_stance_time - std_stance_time; mean_swing_time - std_swing_time]);
all_max = max([mean_step_time + std_step_time; mean_stance_time + std_stance_time; mean_swing_time + std_swing_time]);
ylim([0, 1.2]);

hold off;
fprintf('\nPlot generation complete!\n');