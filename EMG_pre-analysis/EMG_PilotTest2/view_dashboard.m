%% Quick View Saved EMG Dashboard
clc;
clear;

% 1. Load Configurations to get the correct paths
run('config_paths.m');

% 2. Define the exact path to the saved UI data
ui_data_filename = fullfile(save_path, sprintf('%s_%s_DashboardData.mat', subject_id, experiment_day));

% 3. Check if file exists, load, and launch
if exist(ui_data_filename, 'file')
    fprintf('>> Loading pre-processed dashboard data from:\n   %s\n', ui_data_filename);
    load(ui_data_filename);
    
    fprintf('>> Launching dashboard...\n');
    launch_emg_dashboard(order_sessions, session_data_cell, session_edges_cell, target_muscle_names);
else
    error('Dashboard data not found! Please run EMG_pre_ana_V3.m first to generate the data.');
end