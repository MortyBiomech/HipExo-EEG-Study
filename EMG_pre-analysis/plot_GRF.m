%% Script to Visualize Total GRF Data Extracted by START/END Markers (Summed Sensors)
clc;
clear;

%% 1. Configure paths
addpath(genpath('C:\2026SSArbeit\HipExo-EEG-Study\EMG_pre-analysis'));
addpath('C:\egglab_task\eeglab2025.1.0\plugins\xdfimport1.2');

data_path = 'C:\2026SSArbeit\data\PilotTest2\Sub-P2_3\day2\data\';
subject_id = 'Pilot2_3';
experiment_day = 'day2';
subject_full_id = sprintf('%s_%s', subject_id, experiment_day);

%% 2. Read session folders
d = dir(data_path);
folderNames = {d([d.isdir]).name};
folderNames(ismember(folderNames, {'.','..'})) = [];

conditions = cell(1, 8);
conditions{1} = folderNames{contains(folderNames, 'NoExoPre')};
for k = 1:6
    hit = folderNames(contains(folderNames, sprintf('Exo%d', k)));
    conditions{k+1} = hit{1};
end
conditions{8} = folderNames{contains(folderNames, 'NoExoPost')};

num_sessions = length(conditions);

% Force plate (GRF) channel definition
Left_leg_indx  = [2 3 6 7];     
Right_leg_indx = [1 4 5 8];    

%% 3. Extract and Plot Data
fprintf('Starting Visual Check for subject %s...\n', subject_id);

for s = 1:num_sessions
    current_session = conditions{s};
    fprintf('Plotting [%d/%d]: %s... ', s, num_sessions, current_session);
    
    filename = ['sub-', subject_id, '_', experiment_day,'_',current_session, '_task-Default_run-001_eeg.xdf'];
    full_file_path = fullfile(data_path, current_session, 'eeg', filename);
    
    if ~exist(full_file_path, 'file')
        fprintf('File not found. Skipping.\n');
        continue;
    end
    
    % Load XDF streams quietly
    [streams, ~] = load_xdf(full_file_path);
    
    grf_idx = find(strcmp(cellfun(@(x) x.info.name, streams, 'UniformOutput', false), 'GRF'));
    marker_idx = find(strcmp(cellfun(@(x) x.info.name, streams, 'UniformOutput', false), 'GRF_Markers'));
    
    if isempty(grf_idx) || isempty(marker_idx)
        fprintf('Missing GRF or Marker streams. Skipping.\n');
        continue;
    end
    
    GRF = streams{grf_idx};
    GRF_Marker_Stream = streams{marker_idx};
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
    % MODIFIED: Sum all 4 sensor channels for each leg to get Total GRF
    % GRF.time_series(indx, valid_idx) returns a 4xN matrix. 
    % sum(..., 1) adds them row by row, resulting in a 1xN vector.
    % =========================================================================
    plot_right_grf_total = sum(GRF.time_series(Right_leg_indx, valid_idx), 1);
    plot_left_grf_total  = sum(GRF.time_series(Left_leg_indx, valid_idx), 1);
    
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