%% EMG Dashboard Preprocessing and Visualization Script
clc;
clear;

%% 1. Load Configurations & Dictionary Mapping
run('config_paths.m');
run('subject_3_infos.m');

eeglab nogui;

% Extract mapping arrays directly and clean up any invisible trailing spaces
dict_data_names   = strtrim(subject_3.SignalName);
dict_muscle_names = strtrim(subject_3.MuscleName);

%% 2. Define Fixed Target Channel Layout (22 Exact Slots)
% This explicitly locks the exact anatomical UI order. R and L pairs are adjacent.
target_muscle_names = { ...
    'Tibialis anterior R',          'Tibialis anterior L', ...
    'Soleus R',                     'Soleus L', ...
    'Gastrocnemius cap. mediale R', 'Gastrocnemius cap. mediale L', ...
    'Vastus medialis R',            'Vastus medialis L', ...
    'Rectus femoris R',             'Rectus femoris L', ...
    'Biceps femoris R',             'Biceps femoris L', ...
    'Glutaeus maximus R',           'Glutaeus maximus L', ...
    'Trapezius R',                  'Trapezius L', ...
    'SCM R_Ch1',                    'SCM L_Ch1', ...
    'SCM R_Ch2',                    'SCM L_Ch2', ...
    'Zygomaticus_Ch1',              'Zygomaticus_Ch2' ...
};
total_target_channels = length(target_muscle_names);

%% 3. Dynamic Session Order Setup
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

session_data_cell  = cell(1, num_sessions);
session_edges_cell = cell(1, num_sessions);

%% 4. Main Loop: Iterate and process each Session
for s = 1:num_sessions
    current_session = order_sessions{s};
    fprintf('\n========================================================\n');
    fprintf('Processing Session %d/%d: %s...\n', s, num_sessions, current_session);
    
    data_file = fullfile(save_path, sprintf('Data_%s.mat', current_session));
    
    if ~exist(data_file, 'file')
        warning('Preprocessed file not found: %s. Skipping this session.', data_file);
        session_data_cell{s}  = []; 
        session_edges_cell{s} = [];
        continue; 
    end
    
    fprintf('>> Loading data into memory: %s\n', data_file);
    load(data_file, 'streams', 'HS_R', 'TO_R', 'HS_L', 'TO_L'); 
    
    if ~exist('streams', 'var') || ~exist('HS_R', 'var')
        continue;
    end
                            
    t_rhs = HS_R.timestamps; t_lto = TO_L.timestamps;
    t_lhs = HS_L.timestamps; t_rto = TO_R.timestamps;

    emg_indices = [];
    for i = 1:length(streams)
        if strcmp(streams{i}.info.type, 'EMG') 
            emg_indices = [emg_indices, i];
        end
    end
    
    valid_cycles_time = [];
    for i = 1:length(t_rhs)-1
        start_t = t_rhs(i); end_t = t_rhs(i+1);
        curr_lto = t_lto(t_lto > start_t & t_lto < end_t);
        curr_lhs = t_lhs(t_lhs > start_t & t_lhs < end_t);
        curr_rto = t_rto(t_rto > start_t & t_rto < end_t);
        
        if ~isempty(curr_lto) && ~isempty(curr_lhs) && ~isempty(curr_rto)
            valid_cycles_time = [valid_cycles_time; start_t, curr_lto(1), curr_lhs(1), curr_rto(1), end_t];
        end
    end
    
    fs_emg = streams{emg_indices(1)}.info.effective_srate; 
    durations_samples = round(diff(valid_cycles_time, 1, 2) * fs_emg);
    num_cycles = size(valid_cycles_time, 1);
    
    median_durs = round(median(durations_samples, 1));
    total_target_length = sum(median_durs);
    phase_edges_percent = cumsum(median_durs) / total_target_length * 100;
    
    fprintf('>> Starting EMG signal processing and Time-Warping...\n');
    
    % Initialize array with NaNs. If a channel is missing, it simply remains NaN.
    all_warped_emg = nan(num_cycles, total_target_length, total_target_channels);
    newlatency = [1, 1 + median_durs(1), 1 + sum(median_durs(1:2)), 1 + sum(median_durs(1:3)), total_target_length];
                  
    for m = 1:length(emg_indices)
        idx = emg_indices(m);
        raw_sensor_name = strtrim(streams{idx}.info.name); 
        
        match_idx = find(strcmp(dict_data_names, raw_sensor_name), 1);
        if isempty(match_idx)
            fprintf('Warning: Sensor "%s" not found in dictionary mapping. Skipping...\n', raw_sensor_name);
            continue;
        end
        
        biological_name = dict_muscle_names{match_idx};
        num_local_channels = size(streams{idx}.time_series, 1);
        emg_time = streams{idx}.time_stamps;
        raw_emg_matrix = double(streams{idx}.time_series);
        
        for ch = 1:num_local_channels
            if num_local_channels > 1
                current_muscle_name = sprintf('%s_Ch%d', biological_name, ch);
            else
                current_muscle_name = biological_name;
            end
            
            % Look up exact slot in the 22-channel layout array
            target_idx = find(strcmp(target_muscle_names, current_muscle_name), 1);
            if isempty(target_idx)
                fprintf('Warning: Target layout slot not found for "%s". Skipping...\n', current_muscle_name);
                continue;
            end
            
            raw_emg = raw_emg_matrix(ch, :);
            [b_bp, a_bp] = butter(4, [20, 400] / (fs_emg/2), 'bandpass');
            emg_filt = filtfilt(b_bp, a_bp, raw_emg);
            [b_lp, a_lp] = butter(4, 6 / (fs_emg/2), 'low');
            emg_env = filtfilt(b_lp, a_lp, abs(emg_filt));
            
            for c = 1:num_cycles
                idx_start = find(emg_time >= valid_cycles_time(c, 1), 1, 'first');
                idx_end   = find(emg_time <= valid_cycles_time(c, 5), 1, 'last');
                
                if ~isempty(idx_start) && ~isempty(idx_end) && idx_end > idx_start
                    raw_cycle_data = emg_env(idx_start:idx_end); 
                    evlatency = [1, ...
                                 find(emg_time >= valid_cycles_time(c, 2), 1, 'first') - idx_start + 1, ...
                                 find(emg_time >= valid_cycles_time(c, 3), 1, 'first') - idx_start + 1, ...
                                 find(emg_time >= valid_cycles_time(c, 4), 1, 'first') - idx_start + 1, ...
                                 idx_end - idx_start + 1];
                                 
                    warpmat = timewarp(evlatency, newlatency);
                    cycle_warped_signal = (warpmat * raw_cycle_data')';
                    
                    if length(cycle_warped_signal) == total_target_length
                        all_warped_emg(c, :, target_idx) = cycle_warped_signal;
                    end
                end
            end
        end
    end
    
    session_data_cell{s}  = all_warped_emg; 
    session_edges_cell{s} = phase_edges_percent; 
end

%% 5. Save UI Data and Launch the interactive dashboard
ui_data_filename = fullfile(save_path, sprintf('%s_%s_DashboardData.mat', subject_id, experiment_day));

fprintf('\n>> Saving dashboard data to: %s\n', ui_data_filename);
save(ui_data_filename, 'order_sessions', 'session_data_cell', 'session_edges_cell', 'target_muscle_names', '-v7.3');

fprintf('\nAll %d sessions processed successfully. Launching the dashboard...\n', num_sessions);
launch_emg_dashboard(order_sessions, session_data_cell, session_edges_cell, target_muscle_names);