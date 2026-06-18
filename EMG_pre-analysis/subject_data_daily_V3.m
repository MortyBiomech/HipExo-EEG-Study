%% Subject Data Preprocessing Script (XDF to MAT) 
clc;
clear;

%% 1. Load Configurations
% Run the external config file to load paths and subject variables
run('config_paths.m');

%% 2. Read data under different conditions

% Path to one subject's session folders (loaded from config)
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

%% 3. Start batch extraction and save data

% Combine subject_id and experiment_day for the display log
subject_full_id = sprintf('%s_%s', subject_id, experiment_day);
fprintf('Starting data preprocessing for subject %s...\n', subject_full_id);

for s = 1:num_sessions
    %%
    current_session = conditions{s};
    fprintf('\n========================================================\n');
    fprintf('Processing [%d/%d]: %s\n', s, num_sessions, current_session);
    
    % Assemble file path and load XDF dynamically using config variables
    % Format matches: sub-Pilot2_3_day2_ses-Exo1_eco_task-Default_run-001_eeg.xdf
    % (Assuming 'current_session' variable contains the 'ses-Exo1_eco' string)
    filename = sprintf('sub-%s_%s_%s_task-Default_run-001_eeg.xdf', subject_id, experiment_day, current_session);
    
    filepath = fullfile(data_path, current_session, 'eeg');
    full_file_path = fullfile(filepath, filename);
    
    if ~exist(full_file_path, 'file')
        warning('File not found: %s, skipping this session.', full_file_path);
        continue;
    end
    
    fprintf('>> Loading XDF file...\n');
    [streams, ~] = load_xdf(full_file_path);
    
    % Extract GRF data stream
    grf_idx = find(strcmp(cellfun(@(x) x.info.name, streams, 'UniformOutput', false), 'GRF'));
    if isempty(grf_idx)
        warning('GRF data stream not found, skipping gait event extraction.');
        continue;
    end
    GRF = streams{grf_idx};

    % Check for GRF_Markers stream to determine stable walking phase
    marker_idx = find(strcmp(cellfun(@(x) x.info.name, streams, 'UniformOutput', false), 'GRF_Markers'));
    has_marker = ~isempty(marker_idx);

    switch has_marker
        case true
            fprintf('>> GRF_Markers found. Extracting stable walking timestamps automatically...\n');
            GRF_Marker_Stream = streams{marker_idx};
            marker_labels = GRF_Marker_Stream.time_series;

            % Handle nested cells if xdfimport formats strings that way
            if iscell(marker_labels) && ~isempty(marker_labels) && iscell(marker_labels{1})
                marker_labels = cellfun(@(x) x{1}, marker_labels, 'UniformOutput', false);
            end

            % Find indices for actual walking phase (Must contain START/END, but exclude 'standing')
            idx_start = find(contains(marker_labels, 'START_') & ~contains(marker_labels, 'standing'), 1);
            idx_end   = find(contains(marker_labels, 'END_') & ~contains(marker_labels, 'standing'), 1);

            if ~isempty(idx_start) && ~isempty(idx_end)
                start_time = GRF_Marker_Stream.time_stamps(idx_start);
                end_time   = GRF_Marker_Stream.time_stamps(idx_end);
                fprintf('>> Found walking markers: [%s] at %.3fs, [%s] at %.3fs\n', ...
                    marker_labels{idx_start}, start_time, marker_labels{idx_end}, end_time);
            else
                % Fallback if specific strings are not matched
                warning('Specific walking START/END markers not found. Falling back to full marker duration.');
                start_time = GRF_Marker_Stream.time_stamps(1);
                end_time   = GRF_Marker_Stream.time_stamps(end);
            end

        case false
            fprintf('>> No GRF_Markers found. Manual timestamp input required.\n');
            
            Total_Right_GRF = sum(GRF.time_series(Right_leg_indx, :), 1);
            Total_Left_GRF  = sum(GRF.time_series(Left_leg_indx, :), 1);
         
            % Plot the GRF data for visual inspection by the operator
            f = figure('Name', sprintf('GRF Data - %s', current_session), 'NumberTitle', 'off');
            plot(GRF.time_stamps, Total_Right_GRF, 'LineWidth', 1.2);
            hold on;
            plot(GRF.time_stamps, Total_Left_GRF, 'LineWidth', 1.2);
            title(sprintf('Select Stable Walking Phase for %s', current_session));
            xlabel('Time (s)');
            ylabel('GRF Amplitude');
            legend('Right Leg GRF', 'Left Leg GRF');
            grid on;

            % Prompt operator for manual timestamp input
            disp('Please inspect the figure and determine the stable walking phase.');
            start_time = input('Enter stable walking START timestamp (in seconds): ');
            end_time   = input('Enter stable walking END timestamp (in seconds): ');

            % Close the figure after receiving input
            if ishandle(f)
                close(f);
            end
    end

    % Subset the GRF data to only include the stable walking phase
    valid_idx = GRF.time_stamps >= start_time & GRF.time_stamps <= end_time;
    GRF_stable = GRF;
    GRF_stable.time_stamps = GRF.time_stamps(valid_idx);
    GRF_stable.time_series = GRF.time_series(:, valid_idx);
    
    fprintf('>> Calculating gait event thresholds on stable phase...\n');
    [best_on, best_off] = optimize_thresholds(GRF_stable, Right_leg_indx, Left_leg_indx);
    
    fprintf('>> Extracting heel strike and toe-off events (On: %.3f, Off: %.3f)...\n', best_on, best_off);
    [HS_R, TO_R, HS_L, TO_L] = detect_gait_events(GRF_stable, Right_leg_indx, Left_leg_indx, ...
                                'ThresholdOn',  best_on, ...
                                'ThresholdOff', best_off);
                            
    % Save as .mat file 
    % Save streams and the 4 extracted gait events together for use by the main EMG dashboard program
    save_filename = fullfile(save_path, sprintf('Data_%s.mat', current_session));
    fprintf('>> Saving to: %s\n', save_filename);
    save(save_filename, 'streams', 'HS_R', 'TO_R', 'HS_L', 'TO_L', '-v7.3');
    
    fprintf('>> %s preprocessing complete!\n', current_session);
end

fprintf('\n All 8 sessions data preprocessing loop finished! You can now run the main EMG dashboard program.\n');