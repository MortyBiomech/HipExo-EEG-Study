%% configure file

% 1. Base Paths (Modify these for your local machine)
project_root = 'C:\2026SSArbeit\HipExo-EEG-Study';
eeglab_path  = 'C:\egglab_task\eeglab2025.1.0\plugins\xdfimport1.2';
data_root    = 'C:\2026SSArbeit\data\PilotTest2';

% 2. Subject & Experiment Information
subject_folder = 'Sub-P2_3';
subject_id     = 'Pilot2_3';
experiment_day = 'day2';
run_id = '001';

% 3. Automatically Generate Full Paths
addpath(genpath(project_root));
addpath(genpath(fullfile(project_root, 'EMG_pre-analysis')));
addpath(eeglab_path);

% Construct the full data and save paths dynamically
data_path = fullfile(data_root, subject_folder, experiment_day, 'data', filesep);
save_path = fullfile(data_root, subject_folder, experiment_day, 'processed_EMG', filesep);

if ~exist(save_path, 'dir')
    mkdir(save_path);
end