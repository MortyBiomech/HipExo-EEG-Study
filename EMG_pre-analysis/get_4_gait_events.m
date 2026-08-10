% Combining automatic interval segmentation with a custom gait detection algorithm.
clc;
clear;

%% 1. Load Configurations
run('config_paths.m');
run([current_subject, '_infos.m']); 

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

% Force plate (GRF) channel definition
Left_leg_indx  = [2 3 6 7];     
Right_leg_indx = [1 4 5 8];    

%% 3. Main Loop
fprintf('Starting GRF Gait Event Extraction for subject %s...\n', subject_id);

for s = 1:num_sessions
    current_session = order_sessions{s};
    
    if contains(current_session, 'Missing')
        continue;
    end
    
    fprintf('\n========================================================\n');
    fprintf('Processing [%d/%d]: %s\n', s, num_sessions, current_session);
    
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
    
    % Load XDF streams 
    [streams, ~] = load_xdf(full_file_path);
    
    grf_idx = find(strcmp(cellfun(@(x) x.info.name, streams, 'UniformOutput', false), 'GRF'));
    marker_idx = find(contains(cellfun(@(x) x.info.name, streams, 'UniformOutput', false), 'GRF_Marker', 'IgnoreCase', true));
    
    if isempty(grf_idx)
        warning('Missing GRF stream for %s. Skipping.', current_session);
        continue;
    end
    
    GRF = streams{grf_idx(1)};
    
    % 2. Handle cases where markers are missing and guide the system into manual mode
    if isempty(marker_idx)
        fprintf('>> No GRF_Marker stream found. Will default to manual selection.\n');
        marker_labels = {}; % Set to an empty set, which naturally triggers the subsequent manual selection fallback
    else
        GRF_Marker_Stream = streams{marker_idx(1)};
        marker_labels = GRF_Marker_Stream.time_series;
        
        if iscell(marker_labels) && ~isempty(marker_labels) && iscell(marker_labels{1})
            marker_labels = cellfun(@(x) x{1}, marker_labels, 'UniformOutput', false);
        end
    end
    
    %% 4. Define Walking Window (Auto via Markers or Manual)
    idx_start = find(contains(marker_labels, 'START_') & ~contains(marker_labels, 'standing'), 1);
    idx_end   = find(contains(marker_labels, 'END_') & ~contains(marker_labels, 'standing'), 1);
    
    auto_success = false;
    
    if ~isempty(idx_start) && ~isempty(idx_end)
        final_start = GRF_Marker_Stream.time_stamps(idx_start);
        final_end   = GRF_Marker_Stream.time_stamps(idx_end);
        start_label = marker_labels{idx_start};
        end_label   = marker_labels{idx_end};
        fprintf('>> Auto-detection successful. Using markers: [%s] to [%s]\n', start_label, end_label);
        auto_success = true;
    else
        fprintf('>> No valid START/END markers found. Manual selection required.\n');
    end
    
    % Manual Selection Fallback 
    if ~auto_success
        % Calculate quick Summed GRF for manual plotting
        t_all = GRF.time_stamps;
        Fz_R_total = sum(abs(GRF.time_series(Right_leg_indx, :)), 1);
        Fz_L_total = sum(abs(GRF.time_series(Left_leg_indx, :)), 1);
        
        h_fig = figure('Name', sprintf('Manual Selection - %s', current_session), 'Position', [50, 50, 1400, 700]);
        plot(t_all, Fz_L_total, 'b'); hold on;
        plot(t_all, Fz_R_total, 'r');
        xlabel('LSL Time (s)'); ylabel('Total Amplitude');
        title({'[MANUAL SELECTION]', ...
               '1. Use zoom/pan to find the stable walking start/end.', ...
               '2. Go to the Command Window and type the exact timestamps.'}, 'Color', 'red', 'FontSize', 12);
        grid on;
        
        disp('--- Manual Input Required ---');
        valid_input = false;
        while ~valid_input
            try
                user_start_str = input('Enter START timestamp (e.g., 577872.5) : ', 's');
                user_end_str   = input('Enter END timestamp   (e.g., 578115.2) : ', 's');
                final_start = str2double(user_start_str);
                final_end   = str2double(user_end_str);
                
                if ~isnan(final_start) && ~isnan(final_end) && final_start < final_end
                    valid_input = true;
                else
                    disp('Invalid input. Start must be < End and both must be numbers.');
                end
            catch
                disp('Invalid input format.');
            end
        end
        close(h_fig);
        
        start_label = 'Manual_Start';
        end_label   = 'Manual_End';
        fprintf('>> Proceeding with manual window: %.2f to %.2f\n', final_start, final_end);
    end
    
    %% 5. Crop GRF and detect gait events
    % Here, we crop the raw GRF structure based on final_start and final_end
    % so that your detect_gait_events function does not process invalid data
    valid_idx = GRF.time_stamps >= final_start & GRF.time_stamps <= final_end;
    
    GRF_cropped = GRF;
    GRF_cropped.time_stamps = GRF.time_stamps(valid_idx);
    GRF_cropped.time_series = GRF.time_series(:, valid_idx);
    
    fprintf('>> Calling optimize_thresholds and detect_gait_events...\n');
    % 5.1 Call threshold optimization function.
    [best_on, best_off] = optimize_thresholds_V1(GRF_cropped, Right_leg_indx, Left_leg_indx);
    
    % 5.2 Call event detection function (set `Plot` to `true` so can view the validation plot).
    [HS_R, TO_R, HS_L, TO_L] = detect_gait_events(GRF_cropped, Right_leg_indx, Left_leg_indx, ...
                                'ThresholdOn', best_on, ...
                                'ThresholdOff', best_off, ...
                                'Plot', true, 'Verbose', true);
                            
    % 5.3 Call the gait histogram function.
    plot_gait_histograms(HS_R, TO_R, HS_L, TO_L);
    
    % % --- Optional: Remove the first and last points to ensure a clean steady state ---
    % % Note: Function returns a struct containing .samples and .timestamps
    % if length(HS_L.timestamps) > 3
    %     HS_L.timestamps = HS_L.timestamps(2:end-1);
    %     TO_L.timestamps = TO_L.timestamps(2:end-1);
    % end
    % if length(HS_R.timestamps) > 3
    %     HS_R.timestamps = HS_R.timestamps(2:end-1);
    %     TO_R.timestamps = TO_R.timestamps(2:end-1);
    % end
    
    %% 6. Compile Events and Save into .mat
    % Package the output of function into the struct format we standardly use for EMG and EEG data.
    all_events = struct('type', {}, 'time', {});
    count = 0;
    
    count = count + 1; all_events(count).type = start_label; all_events(count).time = final_start;
    count = count + 1; all_events(count).type = end_label;   all_events(count).time = final_end;
    
    for i = 1:length(HS_L.timestamps)
        count=count+1; all_events(count).type = 'HS_L'; all_events(count).time = HS_L.timestamps(i);
    end
    for i = 1:length(TO_L.timestamps)
        count=count+1; all_events(count).type = 'TO_L'; all_events(count).time = TO_L.timestamps(i);
    end
    for i = 1:length(HS_R.timestamps)
        count=count+1; all_events(count).type = 'HS_R'; all_events(count).time = HS_R.timestamps(i);
    end
    for i = 1:length(TO_R.timestamps)
        count=count+1; all_events(count).type = 'TO_R'; all_events(count).time = TO_R.timestamps(i);
    end
    
    [~, sort_order] = sort([all_events.time]);
    all_events = all_events(sort_order);
    
    % DYNAMIC SAVE PATH
    save_dir = fullfile('C:\2026SSArbeit\data\PilotTest2', subject_folder, experiment_day, 'processed_EMG');
    
    if ~exist(save_dir, 'dir')
        mkdir(save_dir);
    end
    
    save_name = fullfile(save_dir, sprintf('%s_run-%s_gait_events.mat', current_session, run_id));
    save(save_name, 'all_events'); 
    fprintf('>> Saved %d combined events to: %s\n', length(all_events), save_name);
    
    % Wait for user to check your function's plots before closing and moving to next
    disp('Review your custom function plots. Press any key in the Command Window to continue...');
    pause; 
    close all; % Close the generated image and proceed to the next session
end

fprintf('\nAll sessions processed! Gait events saved in the processed_EMG folder.\n');
