%% Script to Visualize Total GRF Data Extracted by START/END Markers (Summed Sensors)
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

%% 3. Extract and Plot Data
fprintf('Starting Visual Check for subject %s_%s...\n', subject_id, experiment_day);

for s = 1:num_sessions
    current_session = order_sessions{s};
    fprintf('Plotting [%d/%d]: %s... ', s, num_sessions, current_session);
    
    if ~strcmp(subject_id, 'Pilot2_2')
        filename = ['sub-', subject_id, '_', experiment_day,'_',current_session, '_task-Default_run-', run_id,'_eeg.xdf'];
        full_file_path = fullfile(data_path, current_session, 'eeg', filename);
    else
        filename = ['sub-', subject_id, '_', current_session, '_task-Default_run-', run_id,'_eeg.xdf'];
        full_file_path = fullfile(data_path, current_session, 'eeg', filename);
    end

    if ~exist(full_file_path, 'file')
        fprintf('File not found. Skipping.\n');
        continue;
    end
    
    % Load XDF streams
    [streams, ~] = load_xdf(full_file_path);
    
    % Use more robust name matching
    grf_idx = find(strcmp(cellfun(@(x) x.info.name, streams, 'UniformOutput', false), 'GRF'));
    marker_idx = find(contains(cellfun(@(x) x.info.name, streams, 'UniformOutput', false), 'GRF_Marker', 'IgnoreCase', true));
    
    if isempty(grf_idx) || isempty(marker_idx)
        fprintf('Missing GRF or Marker streams. Skipping.\n');
        continue;
    end
    
    % ---------------------------------------------------------
    % Fix 1: Ensure only the first matched stream is extracted to prevent array indexing errors
    % ---------------------------------------------------------
    GRF = streams{grf_idx(1)};
    
    % ---------------------------------------------------------
    % Fix 2: Defensive check to prevent crashes from "empty" data streams (Header without Payload)
    % ---------------------------------------------------------
    if isempty(GRF.time_series) || size(GRF.time_series, 1) == 0
        fprintf('\n  ⚠️ Warning: GRF stream metadata found, but data payload is empty (0 points). Skipping.\n');
        continue;
    end
    
    GRF_Marker_Stream = streams{marker_idx(1)};
    marker_labels = GRF_Marker_Stream.time_series;
    
    if iscell(marker_labels) && ~isempty(marker_labels) && iscell(marker_labels{1})
        marker_labels = cellfun(@(x) x{1}, marker_labels, 'UniformOutput', false);
    end
    
    % Find valid START and END markers (ignoring 'standing')
    idx_start = find(contains(marker_labels, 'START_') & ~contains(marker_labels, 'standing'), 1);
    idx_end   = find(contains(marker_labels, 'END_') & ~contains(marker_labels, 'standing'), 1);
    
    if ~isempty(idx_start) && ~isempty(idx_end)
        start_time = GRF_Marker_Stream.time_stamps(idx_start);
        end_time   = GRF_Marker_Stream.time_stamps(idx_end);
        fprintf('Found [%s] to [%s]\n', marker_labels{idx_start}, marker_labels{idx_end});
    else
        fprintf('No valid walking markers found. Using full duration.\n');
        start_time = GRF.time_stamps(1);
        end_time   = GRF.time_stamps(end);
    end
    
    % Subset the GRF data
    valid_idx = GRF.time_stamps >= start_time & GRF.time_stamps <= end_time;
    plot_time = GRF.time_stamps(valid_idx);
    
    % =========================================================================
    % Fix 3: Dynamic channel safety check to prevent index out of bounds
    % =========================================================================
    % Get the actual number of channels (rows) in the current GRF data stream
    num_grf_channels = size(GRF.time_series, 1);
    
    % Filter indices: Remove invalid indices that are greater than the actual number of channels
    safe_Right_leg_indx = Right_leg_indx(Right_leg_indx <= num_grf_channels);
    safe_Left_leg_indx  = Left_leg_indx(Left_leg_indx <= num_grf_channels);
    
    % If missing channels are detected, print a warning message in the console to alert the operator
    if length(safe_Right_leg_indx) < length(Right_leg_indx) || length(safe_Left_leg_indx) < length(Left_leg_indx)
        fprintf('  ⚠️ Warning: Expected 8 GRF channels, but found %d. Adjusted indices to prevent crash.\n', num_grf_channels);
    end
    
    % Perform summation using the safe indices
    plot_right_grf_total = sum(GRF.time_series(safe_Right_leg_indx, valid_idx), 1);
    plot_left_grf_total  = sum(GRF.time_series(safe_Left_leg_indx, valid_idx), 1);
    % =========================================================================
    
    % Create a new individual figure for this session
    figure('Name', sprintf('Total GRF Data - %s', current_session), 'NumberTitle', 'off');
    
    % Plot the summed total forces
    plot(plot_time, plot_right_grf_total, 'b', 'LineWidth', 0.8);
    hold on;
    plot(plot_time, plot_left_grf_total, 'r', 'LineWidth', 0.8);
    
    % Add visual start/end vertical lines for extra clarity
    xline(start_time, 'k--', 'LineWidth', 1.5);
    xline(end_time, 'k--', 'LineWidth', 1.5);
    
    title(sprintf('Total Walking Phase GRF: %s', current_session), 'Interpreter', 'none');
    xlabel('Time (s)');
    ylabel('Total Amplitude (Summed Sensors)');
    grid on;
    
    % Add legend to every figure
    legend('Right Leg Total GRF', 'Left Leg Total GRF', 'Location', 'best');
end

fprintf('Visual check plotting complete. 8 figures should be open.\n');