%% Batch EMG Preprocessing Script 
clc;
clear;

%% 1. Load Configurations & Mapping Dictionary
run('config_paths.m');
run('subject_3_infos.m');
% Extract mapping dictionary
dict_data_names   = strtrim(subject_3.SignalName_2);
dict_muscle_names = strtrim(subject_3.MuscleName);

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
session_data_cell  = cell(1, num_sessions);
session_edges_cell = cell(1, num_sessions);


%% 3. Construct a "reference channel template" based on the dictionary (ensuring it always consists of 22 channels). 
expected_labels = {};
expected_stream_names = {};
for i = 1:length(dict_data_names)
    stream_name = dict_data_names{i};
    muscle = dict_muscle_names{i};
    
    if strcmp(stream_name, 'None')
        continue; % Skip placeholder
    end
    
    % If it is a dual-channel sensor, split it into two channels.
    if contains(stream_name, 'DuoSensor') || contains(stream_name, 'S16') || contains(stream_name, 'S17') || contains(stream_name, 'S18')
        expected_labels{end+1} = [muscle, '_CH1'];
        expected_stream_names{end+1} = stream_name; % The first channel of the corresponding stream
        expected_labels{end+1} = [muscle, '_CH2'];
        expected_stream_names{end+1} = stream_name; % The second channel of the corresponding stream
    else
        expected_labels{end+1} = muscle;
        expected_stream_names{end+1} = stream_name; % The first channel of the corresponding stream
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
    
    % 3.1 Dynamically construct the accurate path to the XDF file.
    session_eeg_dir = fullfile(data_path, current_session, 'eeg');
    xdf_files = dir(fullfile(session_eeg_dir, '*.xdf'));
    
    if isempty(xdf_files)
        warning('No XDF file found. Skipping.');
        continue;
    end
    
    % Get the first file in alphabetical order.
    file_names = {xdf_files.name};            
    [~, sort_idx] = sort(file_names);         
    full_file_path = fullfile(session_eeg_dir, xdf_files(sort_idx(1)).name);
    fprintf('>> Loading XDF file...\n');
    
    % 3.2 Load XDF file
    streams_raw = load_xdf(full_file_path);
    
    % Scan tream 
    emg_streams = {};
    marker_stream = [];
    for k = 1:length(streams_raw)
        stype = streams_raw{k}.info.type;
        sname = streams_raw{k}.info.name;
        if strcmp(stype, 'EMG')
            emg_streams{end+1} = streams_raw{k};
        elseif contains(sname, 'GRF_Marker', 'IgnoreCase', true) 
            marker_stream = streams_raw{k};
        end
    end
    
    if isempty(emg_streams)
        warning('No EMG streams found. Skipping.');
        continue;
    end
    
    % 3.3 Resolving the dimensionality mismatch: finding the shortest data stream length.
    all_lengths = cellfun(@(x) size(x.time_series, 2), emg_streams);
    min_points = min(all_lengths);
    fprintf('>> Aligning data dimensions. Truncating to %d points.\n', min_points);
    
    % 3.4 Resolving the channel loss issue: Creating an all-zero reference matrix.
    raw_data_matrix = zeros(num_expected_chans, min_points);
    found_chans_count = 0;
    
    % Store the existing EMG data into emg streams.
    for k = 1:length(emg_streams)
        sname = emg_streams{k}.info.name;
        % Look for the lines in the expected table where this stream should be placed.
        target_rows = find(strcmp(expected_stream_names, sname));
        
        if ~isempty(target_rows)
            % If it is a single-channel sensor
            if isscalar(target_rows)
                raw_data_matrix(target_rows(1), :) = emg_streams{k}.time_series(1, 1:min_points);
                found_chans_count = found_chans_count + 1;
            % If it is a dual-channel sensor (DuoSensor)
            elseif length(target_rows) == 2
                raw_data_matrix(target_rows(1), :) = emg_streams{k}.time_series(1, 1:min_points);
                raw_data_matrix(target_rows(2), :) = emg_streams{k}.time_series(2, 1:min_points);
                found_chans_count = found_chans_count + 2;
            end
        end
    end
    
    fprintf('>> Filled %d/%d channels with real data. (Missing channels are set to 0).\n', found_chans_count, num_expected_chans);
    
    % 3.5 Construct the EEGLAB structure
    EEG = eeg_emptyset();
    EEG.setname = sprintf('%s_EMG', current_session);
    
    % Import the key data
    EEG.data   = raw_data_matrix;
    EEG.nbchan = num_expected_chans;
    EEG.pnts   = min_points;
    EEG.trials = 1;
    EEG.srate  = str2double(emg_streams{1}.info.nominal_srate);
    EEG.xmin   = 0;
    EEG.xmax   = (EEG.pnts - 1) / EEG.srate;
    
    % Write standard channel labels
    for i = 1:EEG.nbchan
        EEG.chanlocs(i).labels = expected_labels{i};
    end
    
    % 3.6 Import Marker Events
    EEG.event = [];
    if ~isempty(marker_stream)
        % Use the time axis of the first EMG channel as the reference.
        emg_time_stamps = emg_streams{1}.time_stamps(1:min_points);
        marker_names = marker_stream.time_series; 
        marker_times = marker_stream.time_stamps;
        event_count = 0;
        
        for i = 1:length(marker_times)
            [time_diff, closest_sample_idx] = min(abs(emg_time_stamps - marker_times(i)));
            if time_diff < 0.1 % Synchronization error < 0.1s
                event_count = event_count + 1;

                if iscell(marker_names), ev_type = marker_names{i};
                elseif isnumeric(marker_names), ev_type = num2str(marker_names(i));
                else, ev_type = marker_names(i); 
                end
                
                EEG.event(event_count).type = ev_type;
                EEG.event(event_count).latency = closest_sample_idx;
                EEG.event(event_count).urevent = event_count;
            end
        end
        fprintf('>> Inserted %d Marker events.\n', event_count);
    end
    
    % EEGLAB Verification and Integration
    EEG = eeg_checkset(EEG, 'eventconsistency');
    
    %% 4. EEGLAB EMG Data preprocessing
    fprintf('>> Applying 20-250 Hz bandpass filter...\n');
    EEG = pop_eegfiltnew(EEG, 'locutoff', 20, 'hicutoff', 250);
    
    fprintf('>> Computing linear envelope (Full-wave Rectification + 20Hz Low-pass)...\n');
    EEG.data = abs(EEG.data);
    EEG = pop_eegfiltnew(EEG, 'hicutoff', 10);
    
    % Error-proofing: Eliminate negligible negative values ​​and mark them.
    EEG.data(EEG.data < 0) = 0;
    EEG.etc.is_envelope = true;
    
    %% 5. Save the preprocessed .set file.
    save_dir = fullfile(data_root, subject_folder, experiment_day, 'processed_EMG');
    if ~exist(save_dir, 'dir'), mkdir(save_dir); end
    
    save_filename = sprintf('sub-%s_%s_%s_EMG_Envelope.set', subject_id, experiment_day, current_session);
    EEG = pop_saveset(EEG, 'filename', save_filename, 'filepath', save_dir);
    fprintf('>> Saved to: %s\n', save_filename);
end

fprintf('\n========================================================\n');
fprintf('Pipeline finished successfully!\n');