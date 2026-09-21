%% Script to Visualize Global Timeline for BOTH EMG and EEG Streams
clc;
clear;
close all;

%% 1. Load Configurations
run('config_paths.m');
run('subject_3_infos.m');

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

%% 3. Data Extraction (Targeting BOTH EMG and EEG)
% Arrays for EMG
plot_names_emg = {}; plot_starts_emg = []; plot_ends_emg = []; plot_durations_emg = [];
% Arrays for EEG
plot_names_eeg = {}; plot_starts_eeg = []; plot_ends_eeg = []; plot_durations_eeg = [];

fprintf('Scanning XDF files to extract timeline information for EMG and EEG...\n');

for s = 1:num_sessions
    current_session = order_sessions{s};
    
    if contains(current_session, 'Missing')
        continue;
    end
    
    session_eeg_dir = fullfile(data_path, current_session, 'eeg');
    xdf_files = dir(fullfile(session_eeg_dir, '*.xdf'));
    
    if isempty(xdf_files)
        continue;
    end
    
    expected_filename = sprintf('sub-%s_%s_%s_task-Default_run-%s_eeg.xdf', ...
                                subject_id, experiment_day, current_session, run_id);
    
    full_file_path = fullfile(session_eeg_dir, expected_filename);
    
    % Check if the specific concatenated file exists to prevent `load_xdf` from throwing an error due to a missing file
    if ~exist(full_file_path, 'file')
        warning('Expected XDF file not found: %s. Skipping.', full_file_path);
        continue;
    end
    
    fprintf('>> Loading target XDF file: %s...\n', expected_filename);
    
    try
        streams_raw = load_xdf(full_file_path);
        
        found_emg = false;
        found_eeg = false;
        
        for k = 1:length(streams_raw)
            stream_type = streams_raw{k}.info.type;
            
            % 提取第一个 EMG 流
            if strcmp(stream_type, 'EMG') && ~found_emg
                t_start = str2double(streams_raw{k}.info.first_timestamp);
                t_end   = str2double(streams_raw{k}.info.last_timestamp);
                
                plot_names_emg{end+1} = strrep(current_session, '_', '\_'); 
                plot_starts_emg(end+1) = t_start; 
                plot_ends_emg(end+1) = t_end; 
                plot_durations_emg(end+1) = t_end - t_start; 
                
                fprintf('  [EMG] %s: Start=%.2f, End=%.2f, Dur=%.2fs\n', current_session, t_start, t_end, t_end - t_start);
                found_emg = true;
            end
            
            % 提取 EEG 流
            if strcmp(stream_type, 'EEG') && ~found_eeg
                t_start = str2double(streams_raw{k}.info.first_timestamp);
                t_end   = str2double(streams_raw{k}.info.last_timestamp);
                
                plot_names_eeg{end+1} = strrep(current_session, '_', '\_'); 
                plot_starts_eeg(end+1) = t_start; 
                plot_ends_eeg(end+1) = t_end; 
                plot_durations_eeg(end+1) = t_end - t_start; 
                
                fprintf('  [EEG] %s: Start=%.2f, End=%.2f, Dur=%.2fs\n', current_session, t_start, t_end, t_end - t_start);
                found_eeg = true;
            end
            
            % 如果两个都找到了，就可以提前结束当前文件的循环
            if found_emg && found_eeg
                break;
            end
        end
        fprintf('---------------------------------------------------\n');
    catch ME
        fprintf('Error reading %s: %s\n', current_session, ME.message);
    end
end

%% 4. Plotting Function Definition (Anonymous function for cleaner code)
% 这是一个内部的小函数，用来画统一风格的甘特图
plot_timeline = @(names, starts, ends, durations, title_str, fig_name, pos, color_map) ...
    create_gantt_chart(names, starts, ends, durations, title_str, fig_name, pos, color_map);

%% 5. Generate Figures
if ~isempty(plot_starts_emg)
    create_gantt_chart(plot_names_emg, plot_starts_emg, plot_ends_emg, plot_durations_emg, ...
        'Absolute LSL Timeline: EMG Recordings', 'Global Timeline - EMG', [50, 100, 1200, 600], lines(length(plot_names_emg)));
else
    disp('No EMG data found.');
end

if ~isempty(plot_starts_eeg)
    create_gantt_chart(plot_names_eeg, plot_starts_eeg, plot_ends_eeg, plot_durations_eeg, ...
        'Absolute LSL Timeline: EEG Recordings', 'Global Timeline - EEG', [100, 150, 1200, 600], parula(length(plot_names_eeg)+2));
else
    disp('No EEG data found.');
end

fprintf('\nBoth timelines generated successfully! Please check the popping figures.\n');

% =========================================================================
% Helper Function for Plotting
% =========================================================================
function create_gantt_chart(plot_names, plot_starts, plot_ends, plot_durations, title_str, fig_name, pos, colors)
    figure('Name', fig_name, 'Position', pos, 'Color', 'w');
    hold on;
    
    num_sessions = length(plot_names);
    
    for i = 1:num_sessions
        y_pos = num_sessions - i + 1; 
        
        % 时间条
        plot([plot_starts(i), plot_ends(i)], [y_pos, y_pos], '-', 'LineWidth', 18, 'Color', colors(i,:));
        
        % 时长标注 (中间上方)
        mid_pt = plot_starts(i) + plot_durations(i) / 2;
        text(mid_pt, y_pos + 0.35, sprintf('%.1f sec', plot_durations(i)), ...
            'HorizontalAlignment', 'center', 'Color', 'k', 'FontWeight', 'bold', 'FontSize', 10);
        
        % 起点标注 (左下方)
        text(plot_starts(i), y_pos - 0.35, sprintf('%.1f', plot_starts(i)), ...
            'HorizontalAlignment', 'center', 'Color', [0.8 0 0], 'FontSize', 9);
            
        % 终点标注 (右下方)
        text(plot_ends(i), y_pos - 0.35, sprintf('%.1f', plot_ends(i)), ...
            'HorizontalAlignment', 'center', 'Color', [0 0 0.8], 'FontSize', 9);
    end
    
    yticks(1:num_sessions);
    yticklabels(flip(plot_names)); 
    ylim([0, num_sessions + 1]);
    
    margin = (max(plot_ends) - min(plot_starts)) * 0.05;
    xlim([min(plot_starts) - margin, max(plot_ends) + margin]);
    
    title(title_str, 'FontSize', 16, 'FontWeight', 'bold');
    xlabel('Absolute LSL Time (Seconds)', 'FontSize', 12, 'FontWeight', 'bold');
    grid on;
    
    text(min(plot_starts) - margin*0.8, num_sessions + 0.6, 'Red Text: first\_timestamp', 'Color', [0.8 0 0]);
    text(min(plot_starts) - margin*0.8, num_sessions + 0.2, 'Blue Text: last\_timestamp', 'Color', [0 0 0.8]);
end