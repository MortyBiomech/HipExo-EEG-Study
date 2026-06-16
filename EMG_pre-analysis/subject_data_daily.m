%% ========================================================================
%% Subject Data Preprocessing Script (XDF to MAT) 
%% ========================================================================
clc;
clear;

% 1. Configure paths
addpath(genpath('D:\Morteza\MyProjects\X1Dnsys_EEG\Code'))
addpath(genpath('D:\Morteza\MyProjects\X1Dnsys_EEG\Code\EMG_pre-analysis'));
addpath('D:\Morteza\Toolboxes\EEGLAB\eeglab2026.0.0\plugins\xdfimport1.2');

data_path = 'D:\Morteza\MyProjects\X1Dnsys_EEG\Pilots\PilotTest2\Sub-P2_3\day2\data\';
save_path = 'D:\Morteza\MyProjects\X1Dnsys_EEG\Pilots\PilotTest2\Sub-P2_3\day2\processed_EMG\';

if ~exist(save_path, 'dir')
    mkdir(save_path);
end

% 2. Subject and Session Settings
subject = 'Pilot2_3_day2';

% Path to one subject's session folders
subjectDir = data_path;   

% List only sub-directories, dropping '.' and '..'
d = dir(subjectDir);
folderNames = {d([d.isdir]).name};
folderNames(ismember(folderNames, {'.','..'})) = [];

% Pre-allocate the ordered cell array (8 conditions)
conditions = cell(1, 8);

% First condition is always NoExoPre
conditions{1} = folderNames{contains(folderNames, 'NoExoPre')};

% Middle six: find Exo1 ... Exo6 by their number
for k = 1:6
    hit = folderNames(contains(folderNames, sprintf('Exo%d', k)));
    conditions{k+1} = hit{1};
end

% Last condition is always NoExoPost
conditions{8} = folderNames{contains(folderNames, 'NoExoPost')};
num_sessions = length(conditions);

% Force plate (GRF) channel definition
Left_leg_indx  = [2 3 6 7];     
Right_leg_indx = [1 4 5 8];    


%% ========================================================================
%% 3. Start batch extraction and save data
%% ========================================================================
fprintf('Starting data preprocessing for subject %s...\n', subject);

for s = 1:num_sessions
    %%
    current_session = conditions{s};
    fprintf('\n========================================================\n');
    fprintf('Processing [%d/%d]: %s\n', s, num_sessions, current_session);
    
    % --- 3.1 Assemble file path and load XDF ---
    filename = ['sub-', subject, '_', current_session, '_task-Default_run-001_eeg.xdf'];
    filepath = fullfile(data_path, [current_session], 'eeg');
    full_file_path = fullfile(filepath, filename);
    
    if ~exist(full_file_path, 'file')
        warning('File not found: %s, skipping this session.', full_file_path);
        continue;
    end
    
    fprintf('>> Loading XDF file...\n');
    [streams, ~] = load_xdf(full_file_path);
    
    %% --- 3.2 Extract GRF gait events ---
    grf_idx = find(strcmp(cellfun(@(x) x.info.name, streams, 'UniformOutput', false), 'GRF'));
    if isempty(grf_idx)
        warning('GRF data stream not found, skipping gait event extraction.');
        continue;
    end
    GRF = streams{grf_idx};
    
    fprintf('>> Calculating gait event thresholds...\n');
    
    % Introduce Try-Catch error handling to prevent specific Sessions 
    % (e.g., Exo4_aqua) from crashing the entire loop due to errors
    try
        [best_on, best_off] = optimize_thresholds(GRF, Right_leg_indx, Left_leg_indx);
    catch ME
        warning('\n⚠️ Automatic threshold optimization failed (%s)!\nData waveform might be abnormal. Attempting to force processing using default empirical thresholds (On:0.06, Off:0.05)...\n', current_session);
        % Use commonly optimal empirical values as Fallback
        best_on = 0.06;
        best_off = 0.05;
    end
    
    fprintf('>> Extracting heel strike and toe-off events (On: %.3f, Off: %.3f)...\n', best_on, best_off);
    
    % Use Try-Catch again to prevent the script from crashing if forced extraction also fails
    try
        [HS_R, TO_R, HS_L, TO_L] = detect_gait_events(GRF, Right_leg_indx, Left_leg_indx, ...
                                    'ThresholdOn',  best_on, ...
                                    'ThresholdOff', best_off);
    catch ME2
        warning('\n❌ Forced extraction of gait events completely failed! Skipping saving for %s.\nIt is recommended to plot the GRF for this condition separately to check for data corruption.\n', current_session);
        continue; % Abandon this set of data and continue to the next session
    end
                            
    % --- 3.3 Save as .mat file ---
    % Save streams and the 4 extracted gait events together for use by the main EMG dashboard program
    save_filename = fullfile(save_path, sprintf('Data_%s.mat', current_session));
    fprintf('>> Saving to: %s\n', save_filename);
    save(save_filename, 'streams', 'HS_R', 'TO_R', 'HS_L', 'TO_L', '-v7.3');
    
    fprintf('>> %s preprocessing complete!\n', current_session);
end

fprintf('\n🎉 All 8 sessions data preprocessing loop finished! You can now run the main EMG dashboard program.\n');