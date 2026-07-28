%% configure file

% 1. Base Paths (Modify these for your local machine)
project_root = 'C:\2026SSArbeit\HipExo-EEG-Study';
eeglab_path  = 'C:\egglab_task\eeglab2025.1.0\plugins\xdfimport1.2';
data_root    = 'C:\2026SSArbeit\data\PilotTest2';

% 2. Subject & Experiment Information
current_subject = 'subject_2';
subject_folder  = 'Sub-P2_2'; % Example:Sub-P2_1, Sub-P2_2, Sub-P2_3, etc. 
subject_id      = 'Pilot2_2'; % Example:Pilot2_1, Pilot2_2, Pilot2_3, etc. 
experiment_day  = 'day1'; % Enter day1, day2, etc., here
run_id          = '001';  % Enter 001, 002, etc., here

% 3.1 Verify whether the `experiment_day` folder exists
check_day_path = fullfile(data_root, subject_folder, experiment_day);
if ~exist(check_day_path, 'dir')
    error('❌ Configuration Error: Directory "%s" not found. Please check and enter a valid experiment_day (e.g., day1, day2).', experiment_day);
end

%  construct data_path
data_path = fullfile(check_day_path, 'data', filesep);

% 3.2 Verify whether the run_id exists in the data for the current day
search_pattern = fullfile(data_path, '**', sprintf('*run-%s_eeg.xdf', run_id));
found_runs = dir(search_pattern);

if isempty(found_runs)
    error('❌ Configuration Error: No files containing "run-%s" were found in the directory %s. Please check and enter a valid run count.', experiment_day, run_id);
end

% 4.Generate Full Paths
addpath(genpath(project_root));
addpath(genpath(fullfile(project_root, 'EMG_pre-analysis')));
addpath(eeglab_path);

% Construct the full save path dynamically
save_path = fullfile(data_root, subject_folder, experiment_day, 'processed_EMG', filesep);

if ~exist(save_path, 'dir')
    mkdir(save_path);
end
disp('>> Configuration loaded and validated successfully!');