%% Batch EMG Preprocessing Script 
clc;
clear;

%% 1. Load Configurations & Mapping Dictionary
run('config_paths.m');
run([current_subject, '_infos.m']); 

% Extract the numeric suffix from experiment_day
day_num = strrep(experiment_day, 'day', '');
target_signal_col = ['SignalName_', day_num];

% Dynamically retrieve table variables
current_subj_table = eval(current_subject); 

if ismember(target_signal_col, current_subj_table.Properties.VariableNames)
    dict_data_names = strtrim(current_subj_table.(target_signal_col));
else
    fprintf('>> Column "%s" not found in table. Falling back to default "SignalName" column.\n', target_signal_col);
    dict_data_names = strtrim(current_subj_table.SignalName);
end

dict_muscle_names = strtrim(current_subj_table.MuscleName);

%% 2. Dynamic Session Order Setup
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

%% 3. Construct a "reference channel template"
expected_labels = {};
expected_stream_names = {};
for i = 1:length(dict_data_names)
    stream_name = dict_data_names{i};
    muscle = dict_muscle_names{i};
    
    if strcmp(stream_name, 'None')
        continue; 
    end
    
    if contains(stream_name, 'DuoSensor') || contains(stream_name, 'S16') || contains(stream_name, 'S17') || contains(stream_name, 'S18')
        expected_labels{end+1} = [muscle, '_CH1'];
        expected_stream_names{end+1} = stream_name; 
        expected_labels{end+1} = [muscle, '_CH2'];
        expected_stream_names{end+1} = stream_name; 
    else
        expected_labels{end+1} = muscle;
        expected_stream_names{end+1} = stream_name; 
    end
end
num_expected_chans = length(expected_labels);

eeglab nogui;

%% 3. Main Loop: Iterate and Process each Session
for s = 1:num_sessions
    current_session = order_sessions{s};
    
    if contains(current_session, 'Missing')
        continue;
    end
    
    fprintf('\n========================================================\n');
    fprintf('Processing Session [%d/%d]: %s...\n', s, num_sessions, current_session);
    
    session_eeg_dir = fullfile(data_path, current_session, 'eeg');
    xdf_files = dir(fullfile(session_eeg_dir, '*.xdf'));
    
    if isempty(xdf_files)
        warning('No XDF file found. Skipping.');
        continue;
    end
    
    if ~strcmp(subject_id, 'Pilot2_2')
        filename = ['sub-', subject_id, '_', experiment_day,'_',current_session, '_task-Default_run-', run_id,'_eeg.xdf'];
        full_file_path = fullfile(data_path, current_session, 'eeg', filename);
    else
        filename = ['sub-', subject_id, '_', current_session, '_task-Default_run-', run_id,'_eeg.xdf'];
        full_file_path = fullfile(data_path, current_session, 'eeg', filename);
    end
    
    % Check if the specific concatenated file exists to prevent `load_xdf` from throwing an error due to a missing file
    if ~exist(full_file_path, 'file')
        warning('Expected XDF file not found: %s. Skipping.', full_file_path);
        continue;
    end
    
    fprintf('>> Loading target XDF file: %s...\n', filename);
    
    streams_raw = load_xdf(full_file_path);
    
    % Extract Streams Safely
    grf_idx = find(strcmp(cellfun(@(x) x.info.name, streams_raw, 'UniformOutput', false), 'GRF'));
    marker_idx = find(contains(cellfun(@(x) x.info.name, streams_raw, 'UniformOutput', false), 'GRF_Marker', 'IgnoreCase', true));
    
    grf_stream = [];
    if ~isempty(grf_idx)
        grf_stream = streams_raw{grf_idx(1)}; 
    end
    
    marker_stream = [];
    if ~isempty(marker_idx)
        marker_stream = streams_raw{marker_idx(1)};
    end
    
    emg_streams = {};
    for k = 1:length(streams_raw)
        if strcmp(streams_raw{k}.info.type, 'EMG') && ~isempty(streams_raw{k}.time_stamps)
            emg_streams{end+1} = streams_raw{k};
        end
    end
    
    if isempty(emg_streams)
        warning('No EMG streams found. Skipping.');
        continue;
    end
    
    % 3.1 Resolving dimensionality mismatch via Interpolation onto Majority Timeline
    all_lengths = cellfun(@(x) size(x.time_series, 2), emg_streams);
    
    % Calculate the mode to determine the duration (in terms of time points) shared by the majority of EMG signals
    [mode_len, ~] = mode(all_lengths);
    
    % In a stream characterized by a "majority timestamp length," arbitrarily select one instance to serve as the session reference timeline (Reference Timeline)
    ref_idx = find(all_lengths == mode_len, 1);
    majority_time_stamps = emg_streams{ref_idx}.time_stamps;
    majority_points = mode_len;
    
    fprintf('>> Aligning data via interpolation. Using majority timeline (%d points).\n', majority_points);
    
    % 3.2 Interpolate and map to the expected channel matrix
    raw_data_matrix = zeros(num_expected_chans, majority_points);
    found_chans_count = 0;
    
    for k = 1:length(emg_streams)
        sname = emg_streams{k}.info.name;
        target_rows = find(strcmp(expected_stream_names, sname));
        
        if ~isempty(target_rows)
            % Extract the raw timestamp and data from the current stream
            raw_time = emg_streams{k}.time_stamps;
            
            % Handle potential duplicate timestamps in LSL data to ensure the `interp1` interpolation function operates correctly
            [unique_time, unique_idx] = unique(raw_time);
            
            % Iterate through the channels (single-channel or dual-channel) contained in the current stream
            for ch_offset = 1:length(target_rows)
                row_idx = target_rows(ch_offset);
                raw_data = emg_streams{k}.time_series(ch_offset, unique_idx);
                
                % Core: Independent interpolation onto the majority time axis (majority_time_stamps)
                % Use 'spline' to ensure smoothness, and 'extrap' to allow automatic extrapolation for filling gaps at the start and end
                interp_data = interp1(unique_time, raw_data, majority_time_stamps, 'spline', 'extrap');
                
                % Store in the final matrix
                raw_data_matrix(row_idx, :) = interp_data;
                found_chans_count = found_chans_count + 1;
            end
        end
    end
    
    fprintf('>> Filled %d/%d channels with interpolated data.\n', found_chans_count, num_expected_chans);
    
    % 3.3 Construct EEGLAB structure
    EEG = eeg_emptyset();
    EEG.setname = sprintf('%s_EMG', current_session);
    EEG.data   = raw_data_matrix;
    EEG.nbchan = num_expected_chans;
    EEG.pnts   = majority_points; % Use majority point length
    EEG.trials = 1;
    EEG.srate  = str2double(emg_streams{1}.info.nominal_srate);
    EEG.xmin   = 0;
    EEG.xmax   = (EEG.pnts - 1) / EEG.srate;
    
    for i = 1:EEG.nbchan
        EEG.chanlocs(i).labels = expected_labels{i};
    end
    
    % Since all signals have been perfectly aligned to majority_time_stamps,
    % we can simply use this timeline as the sole reference for synchronizing all subsequent events (Markers, GRF)
    emg_time_stamps = majority_time_stamps;

    % 3.4 Import Marker Events
    EEG.event = [];
    event_count = 0;
    
    % 3.5.1 Insert original global markers
    if ~isempty(marker_stream) && isfield(marker_stream, 'time_stamps') && ~isempty(marker_stream.time_stamps)
        marker_names = marker_stream.time_series; 
        marker_times = marker_stream.time_stamps;
        
        for i = 1:length(marker_times)
            [time_diff, closest_sample_idx] = min(abs(emg_time_stamps - marker_times(i)));
            
            if time_diff < 0.05 
                event_count = event_count + 1;
                if iscell(marker_names), ev_type = marker_names{i};
                elseif isnumeric(marker_names), ev_type = num2str(marker_names(i));
                else, ev_type = marker_names(i); 
                end

                if iscell(ev_type) && isscalar(ev_type), ev_type = ev_type{1}; end
                
                EEG.event(event_count).type = ev_type;
                EEG.event(event_count).latency = closest_sample_idx;
                EEG.event(event_count).urevent = event_count;
            end
        end
        fprintf('>> Inserted %d original XDF global events.\n', event_count);
    end
    
    % 3.5.2 Insert calculated gait events (HS and TO)
    save_dir_gait = fullfile('C:\2026SSArbeit\data\PilotTest2', subject_folder, experiment_day, 'processed_EMG');
    gait_events_file = fullfile(save_dir_gait, sprintf('%s_run-%s_gait_events.mat', current_session, run_id));
    fprintf('>> Inserted calculated gait events (HS and TO) from %s\n', gait_events_file);
    
    if exist(gait_events_file, 'file')
        gait_data = load(gait_events_file);
        
        if isfield(gait_data, 'all_events')
            calculated_events = gait_data.all_events;
            gait_event_count = 0;
            
            for i = 1:length(calculated_events)
                ev_type = calculated_events(i).type;
                if (contains(ev_type, 'START') || contains(ev_type, 'END')) && ~contains(ev_type, 'Manual')
                    continue; 
                end
                
                [time_diff, closest_sample_idx] = min(abs(emg_time_stamps - calculated_events(i).time));
                
                if time_diff < 0.05 
                    event_count = event_count + 1;
                    gait_event_count = gait_event_count + 1;
                    EEG.event(event_count).type = ev_type;
                    EEG.event(event_count).latency = closest_sample_idx;
                    EEG.event(event_count).urevent = event_count;
                else
                    % fprintf('Warning: Event %s dropped. Time diff: %.3f s\n', ev_type, time_diff);
                end
            end
            fprintf('>> Successfully merged %d HS/TO events into EEG structure.\n', gait_event_count);
        end
    else
        warning('Gait events file %s not found. Run event extraction script first.', gait_events_file);
    end
    
    % Check and sort events
    if ~isempty(EEG.event)
        EEG = eeg_checkset(EEG, 'eventconsistency');
    end
    
    %% 4. EEGLAB EMG Data preprocessing
    fprintf('>> Applying 20-250 Hz bandpass filter...\n');
    EEG = pop_eegfiltnew(EEG, 'locutoff', 20, 'hicutoff', 250);
    
    fprintf('>> Computing linear envelope (Full-wave Rectification + 10Hz Low-pass)...\n');
    EEG.data = abs(EEG.data);
    EEG = pop_eegfiltnew(EEG, 'hicutoff', 10);
    EEG.data(EEG.data < 0) = 0;
    EEG.etc.is_envelope = true;
    
    %% 5. Save the preprocessed .set file.
    save_dir = fullfile(data_root, subject_folder, experiment_day, 'processed_EMG');
    if ~exist(save_dir, 'dir'), mkdir(save_dir); end
    
    save_filename = sprintf('sub-%s_%s_%s_run-%s_EMG_Envelope.set', subject_id, experiment_day, current_session,run_id);
    EEG = pop_saveset(EEG, 'filename', save_filename, 'filepath', save_dir);
    fprintf('>> Saved to: %s\n', save_filename);
end

fprintf('\n========================================================\n');
fprintf('Pipeline finished successfully!\n');
