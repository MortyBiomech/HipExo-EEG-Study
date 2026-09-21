%% Central configuration for EMG/EEG processing

% 1. Fixed paths for this computer
project_root = 'C:\2026SSArbeit\HipExo-EEG-Study';
eeglab_path  = 'C:\egglab_task\eeglab2025.1.0\plugins\xdfimport1.2';
data_parent  = 'C:\2026SSArbeit\data';
bids_root    = fullfile(data_parent, 'HipExo-EEG-Study_BIDS');

% 2. Experiment and participant selection
% naming_mode:
%   'pilot'  -> automatically creates PilotTest3 / Sub-P3_1 / Pilot3_1
%   'custom' -> use the explicitly entered formal-experiment names below
naming_mode = 'pilot';

% ---- Pilot mode: normally edit only these two values ----
pilot_test_number = 3;
participant_number = 4;

% ---- Custom/formal mode: used only when naming_mode = 'custom' ----
custom_dataset_folder = 'FormalExperiment';
custom_subject_code   = 'S1_1';
custom_subject_id     = 'Subject1_1';

% Sensor-map selector, independent of the data-folder name. This expects
% subject_P3_1_infos.m containing the table variable subject_P3_1.
% Keep this value for later participants if they use the same sensor IDs and
% muscle placement; change it only when the physical sensor map changes.

current_subject = sprintf( ...
    'subject_P%d_%d', ...
    pilot_test_number, participant_number);

% current_subject = sprintf( ...
%     'subject_S%d_%d', ...
%     pilot_test_number, participant_number);

experiment_day = 'day1';
run_id = '001';

switch lower(naming_mode)
    case 'pilot'
        validateattributes(pilot_test_number, {'numeric'}, ...
            {'scalar','integer','positive'});
        validateattributes(participant_number, {'numeric'}, ...
            {'scalar','integer','positive'});

        dataset_folder = sprintf('PilotTest%d', pilot_test_number);
        subject_code = sprintf('P%d_%d', ...
            pilot_test_number, participant_number);
        subject_id = sprintf('Pilot%d_%d', ...
            pilot_test_number, participant_number);

    case 'custom'
        dataset_folder = custom_dataset_folder;
        subject_code = custom_subject_code;
        subject_id = custom_subject_id;

    otherwise
        error('naming_mode must be either ''pilot'' or ''custom''.');
end

% 3. Automatically generated paths and identifiers
data_root = fullfile(data_parent, dataset_folder);
subject_folder = ['Sub-' char(subject_code)];
% BIDS subject labels may contain letters and numbers only.
bids_subject_id = regexprep(char(subject_id), '[^A-Za-z0-9]', '');

% 3.1 Verify whether the `experiment_day` folder exists
check_day_path = fullfile(data_root, subject_folder, experiment_day);
if ~exist(check_day_path, 'dir')
    error(['❌ Configuration Error: Directory "%s" was not found. ' ...
        'Check naming_mode, experiment number, participant number and day.'], ...
        check_day_path);
end

% Construct the input data path.
data_path = fullfile(check_day_path, 'data');
if ~exist(data_path, 'dir')
    error('❌ Configuration Error: Data directory "%s" was not found.', ...
        data_path);
end

% 3.2 Verify whether the run_id exists in the data for the current day
search_pattern = fullfile(data_path, '**', ...
    sprintf('*run-%s*_eeg.xdf', run_id));
found_runs = dir(search_pattern);

if isempty(found_runs)
    error(['❌ Configuration Error: No XDF file for run-%s was found ' ...
        'below "%s".'], run_id, data_path);
end

% 4. MATLAB paths
addpath(genpath(project_root));
addpath(genpath(fullfile(project_root, 'EMG_pre-analysis')));
addpath(eeglab_path);

% 5. Output path
save_path = fullfile(check_day_path, 'processed_EMG');

if ~exist(save_path, 'dir')
    mkdir(save_path);
end

fprintf(['>> Configuration loaded successfully:\n' ...
    '   naming mode : %s\n' ...
    '   data root   : %s\n' ...
    '   subject     : %s (%s)\n' ...
    '   day / run   : %s / %s\n' ...
    '   sensor map  : %s_infos.m\n'], ...
    naming_mode, data_root, subject_folder, subject_id, ...
    experiment_day, run_id, current_subject);
