%% EMG Dashboard Preprocessing and Visualization Script
clc;
clear;

%% 1. Load Configurations & Dictionary Mapping
% Run the external config file to load paths and subject variables
run('config_paths.m');

% Run the external subject info file to load sensor and muscle mappings
run('subject_3_infos.m');

% Extract the mapping arrays directly from the loaded table 'subject_3'
dict_data_names   = subject_3.SignalName;
dict_muscle_names = subject_3.MuscleName;

%% 2. Dynamic Session Order Setup
% Dynamically parse folder names to get the exact 8 conditions
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
        order_sessions{k+1} = sprintf('Exo%d_Missing', k); % Fallback
    end
end
order_sessions{8} = folderNames{contains(folderNames, 'NoExoPost')};
num_sessions = length(order_sessions);

% Create cell arrays to store the processed data for all 8 sessions
session_data_cell  = cell(1, num_sessions);
session_edges_cell = cell(1, num_sessions);
global_muscle_names = {}; % To store muscle channel names for the UI display

%% 3. Main Loop: Iterate and process each Session
for s = 1:num_sessions
    current_session = order_sessions{s};
    fprintf('\n========================================================\n');
    fprintf('Processing Session %d/%d: %s...\n', s, num_sessions, current_session);
    
    % Load the data for the current session from the saved path
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
        warning('Required variables not found in Session %s. Skipping...', current_session);
        continue;
    end
                            
    % Get absolute timestamps of gait events
    t_rhs = HS_R.timestamps;
    t_lto = TO_L.timestamps;
    t_lhs = HS_L.timestamps;
    t_rto = TO_R.timestamps;

    % Filter EMG channels
    emg_indices = [];
    for i = 1:length(streams)
        if strcmp(streams{i}.info.type, 'EMG') 
            emg_indices = [emg_indices, i];
        end
    end
    
    total_emg_channels = 0;
    for m = 1:length(emg_indices)
        total_emg_channels = total_emg_channels + size(streams{emg_indices(m)}.time_series, 1);
    end
    
    % Match complete gait cycles containing 5 key time points
    valid_cycles_time = [];
    for i = 1:length(t_rhs)-1
        start_t = t_rhs(i);
        end_t   = t_rhs(i+1);
        
        curr_lto = t_lto(t_lto > start_t & t_lto < end_t);
        curr_lhs = t_lhs(t_lhs > start_t & t_lhs < end_t);
        curr_rto = t_rto(t_rto > start_t & t_rto < end_t);
        
        if ~isempty(curr_lto) && ~isempty(curr_lhs) && ~isempty(curr_rto)
            valid_cycles_time = [valid_cycles_time; start_t, curr_lto(1), curr_lhs(1), curr_rto(1), end_t];
        end
    end
    
    fs_emg = streams{emg_indices(1)}.info.effective_srate; 
    durations_time = diff(valid_cycles_time, 1, 2); 
    durations_samples = round(durations_time * fs_emg);
    num_cycles = size(valid_cycles_time, 1);
    
    % Calculate median template using ALL available steps
    median_durs = round(median(durations_samples, 1));
    fprintf('>> Using all %d steps to calculate the median template.\n', num_cycles);
    
    total_target_length = sum(median_durs);
    phase_edges_percent = cumsum(median_durs) / total_target_length * 100;
    
    % EEGLAB Time-Warping to extract and normalize EMG envelopes
    fprintf('>> Starting EMG signal processing and Time-Warping...\n');
    all_warped_emg = zeros(num_cycles, total_target_length, total_emg_channels);
    
    if isempty(global_muscle_names)
        global_muscle_names = cell(1, total_emg_channels);
    end
    
    global_ch_idx = 1; 
    newlatency = [1, 1 + median_durs(1), 1 + sum(median_durs(1:2)), 1 + sum(median_durs(1:3)), total_target_length];
                  
    for m = 1:length(emg_indices)
        idx = emg_indices(m);
        raw_sensor_name = streams{idx}.info.name; 
        
        % Translate logic: Find corresponding muscle name in the dictionary
        match_idx = find(strcmp(dict_data_names, raw_sensor_name));
        if ~isempty(match_idx)
            biological_name = dict_muscle_names{match_idx(1)};
        else
            biological_name = raw_sensor_name; % Fallback to raw name if missing
        end
        
        num_local_channels = size(streams{idx}.time_series, 1);
        emg_time = streams{idx}.time_stamps;
        
        for ch = 1:num_local_channels
            % Handles dual-channel format automatically (e.g., SCM R_Ch1, SCM R_Ch2)
            if num_local_channels > 1
                current_muscle_name = sprintf('%s_Ch%d', biological_name, ch);
            else
                current_muscle_name = biological_name;
            end
            
            % Store translated names for the first session setup
            if isempty(global_muscle_names{global_ch_idx})
                global_muscle_names{global_ch_idx} = current_muscle_name;
            end
            
            % Preprocessing: Bandpass -> Rectification -> Lowpass
            raw_emg = double(streams{idx}.time_series(ch, :));
            [b_bp, a_bp] = butter(4, [20, 400] / (fs_emg/2), 'bandpass');
            emg_filt = filtfilt(b_bp, a_bp, raw_emg);
            emg_rect = abs(emg_filt);
            [b_lp, a_lp] = butter(4, 6 / (fs_emg/2), 'low');
            emg_env = filtfilt(b_lp, a_lp, emg_rect);
            
            % Time-warping
            for c = 1:num_cycles
                t_rhs_start = valid_cycles_time(c, 1);
                t_lto       = valid_cycles_time(c, 2);
                t_lhs       = valid_cycles_time(c, 3);
                t_rto       = valid_cycles_time(c, 4);
                t_rhs_end   = valid_cycles_time(c, 5);
                
                idx_start = find(emg_time >= t_rhs_start, 1, 'first');
                idx_end   = find(emg_time <= t_rhs_end, 1, 'last');
                
                if ~isempty(idx_start) && ~isempty(idx_end) && idx_end > idx_start
                    raw_cycle_data = emg_env(idx_start:idx_end); 
                    
                    evlatency = [1, ...
                                 find(emg_time >= t_lto, 1, 'first') - idx_start + 1, ...
                                 find(emg_time >= t_lhs, 1, 'first') - idx_start + 1, ...
                                 find(emg_time >= t_rto, 1, 'first') - idx_start + 1, ...
                                 idx_end - idx_start + 1];
                                 
                    warpmat = timewarp(evlatency, newlatency);
                    cycle_warped_signal = (warpmat * raw_cycle_data')';
                    
                    if length(cycle_warped_signal) == total_target_length
                        all_warped_emg(c, :, global_ch_idx) = cycle_warped_signal;
                    end
                end
            end
            global_ch_idx = global_ch_idx + 1;
        end
    end
    
    session_data_cell{s}  = all_warped_emg; 
    session_edges_cell{s} = phase_edges_percent; 
end

%% 4. Reorder Channels Dynamically for UI Display
if ~isempty(global_muscle_names)
    fprintf('\n>> Reordering channels dynamically for bilateral comparison...\n');
    
    % Define the target anatomical layout template (Total 22 channels)
    target_order_names = { ...
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
    
    % Dynamically find corresponding channel indices matching the layout template
    new_order = zeros(1, length(target_order_names));
    for t = 1:length(target_order_names)
        idx = find(strcmp(global_muscle_names, target_order_names{t}), 1);
        if ~isempty(idx)
            new_order(t) = idx;
        end
    end
    
    % Discard zero entries in case some muscle data streams are completely missing
    new_order(new_order == 0) = [];
    
    % Apply reordering to names and the data matrix channels
    global_muscle_names = global_muscle_names(new_order);
    
    for s = 1:num_sessions
        if ~isempty(session_data_cell{s})
            session_data_cell{s} = session_data_cell{s}(:, :, new_order);
        end
    end
    fprintf('>> Channel reordering complete. Paired channels are adjacent.\n');
end

%% 5. Save UI Data and Launch the interactive dashboard
% Combine subject_id and experiment_day for the filename
ui_data_filename = fullfile(save_path, sprintf('%s_%s_DashboardData.mat', subject_id, experiment_day));

fprintf('\n>> Saving dashboard data to: %s\n', ui_data_filename);
% Save only the 4 essential variables needed for the UI
save(ui_data_filename, 'order_sessions', 'session_data_cell', 'session_edges_cell', 'global_muscle_names', '-v7.3');

fprintf('\nAll %d sessions processed successfully. Launching the dashboard...\n', num_sessions);
launch_emg_dashboard(order_sessions, session_data_cell, session_edges_cell, global_muscle_names);

