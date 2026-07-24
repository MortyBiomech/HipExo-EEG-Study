%% Script to Check EMG Dimensions and Time Points across all Sessions
clc;
clear;

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

%% 3. Initialize Arrays for the Table
Session_Name     = strings(num_sessions, 1);
EMG_Streams      = zeros(num_sessions, 1);
Total_Channels   = zeros(num_sessions, 1);
Min_Time_Points  = zeros(num_sessions, 1);
Max_Time_Points  = zeros(num_sessions, 1);
Dimension        = strings(num_sessions, 1);
Status           = strings(num_sessions, 1);

% To store details for the deep-dive report and full stream details
mismatch_details = cell(num_sessions, 1);
all_streams_details = cell(num_sessions, 1); % 新增：用于存储所有EMG信号的具体长度

fprintf('Scanning XDF files for subject %s to extract EMG dimensions...\n', subject_id);
fprintf('This might take a minute as it loads the headers of all sessions.\n\n');

%% 4. Loop through Sessions
for s = 1:num_sessions
    current_session = order_sessions{s};
    Session_Name(s) = string(current_session);
    
    if contains(current_session, 'Missing')
        Status(s) = "Missing Folder";
        Dimension(s) = "N/A";
        continue;
    end
    
    % Locate XDF file
    session_eeg_dir = fullfile(data_path, current_session, 'eeg');
    
    % 利用 config_paths.m 中的变量动态拼接预期文件名
    expected_filename = sprintf('sub-%s_%s_%s_task-Default_run-%s_eeg.xdf', ...
                                subject_id, experiment_day, current_session, run_id);

    full_file_path = fullfile(session_eeg_dir, expected_filename);
    
    % Check if the specific file exists
    if ~exist(full_file_path, 'file')
        warning('Expected XDF file not found: %s. Skipping.', full_file_path);
        Status(s) = "File Not Found";
        Dimension(s) = "N/A";
        continue;
    end
    
    fprintf('>> Loading target XDF file: %s...\n', expected_filename);
    
    try
        % Load XDF streams 
        streams_raw = load_xdf(full_file_path);
        
        % Filter for EMG streams
        emg_lengths = [];
        emg_names   = {};
        emg_chans   = 0;
        stream_count = 0;
        
        for k = 1:length(streams_raw)
            if strcmp(streams_raw{k}.info.type, 'EMG')
                stream_count = stream_count + 1;
                n_chans  = size(streams_raw{k}.time_series, 1);
                n_points = size(streams_raw{k}.time_series, 2);
                
                emg_names{end+1}   = streams_raw{k}.info.name; 
                emg_lengths(end+1) = n_points; 
                emg_chans = emg_chans + n_chans;
            end
        end
        
        EMG_Streams(s) = stream_count;
        
        if stream_count > 0
            Total_Channels(s)  = emg_chans;
            Min_Time_Points(s) = min(emg_lengths);
            Max_Time_Points(s) = max(emg_lengths);
            
            Dimension(s) = sprintf('[%d x %d]', emg_chans, min(emg_lengths));
            
            % 新增：记录该 Session 内所有 EMG 信号的详细信息
            all_streams_details{s} = struct('names', {emg_names}, 'lengths', {emg_lengths});
            
            if min(emg_lengths) == max(emg_lengths)
                Status(s) = "OK (Lengths match)";
            else
                Status(s) = "Warning: Length mismatch";
                
                % Store details for the mismatch report
                [mode_val, mode_freq] = mode(emg_lengths);
                
                if mode_freq > 1
                    target_length = mode_val;
                else
                    target_length = max(emg_lengths); 
                end
                
                bad_idx = find(emg_lengths ~= target_length);
                
                report = struct();
                report.target_length = target_length;
                report.bad_names = emg_names(bad_idx);
                report.bad_lengths = emg_lengths(bad_idx);
                report.diffs = emg_lengths(bad_idx) - target_length;
                
                mismatch_details{s} = report;
            end
        else
            Status(s) = "No EMG Streams";
            Dimension(s) = "N/A";
        end
        
    catch ME
        Status(s) = "Error loading file";
        Dimension(s) = "N/A";
    end
end

%% 5. Create and Display the Summary Table
EMG_Dimension_Table = table(Session_Name, Status, EMG_Streams, Total_Channels, ...
                            Min_Time_Points, Max_Time_Points, Dimension);

disp('========================================================================================');
disp('                              EMG DATA DIMENSION SUMMARY                                ');
disp('========================================================================================');
disp(EMG_Dimension_Table);
disp('========================================================================================');

%% 6. Detailed Report of All EMG Streams per Session (新增部分)
disp(' ');
disp('========================================================================================');
disp('                          📋 DETAILED EMG STREAMS REPORT 📋                           ');
disp('========================================================================================');
for s = 1:num_sessions
    if EMG_Streams(s) > 0
        fprintf('>>> Session: %s\n', Session_Name(s));
        fprintf('    [Session Summary] Min Points: %d | Max Points: %d\n', Min_Time_Points(s), Max_Time_Points(s));
        fprintf('    [Individual Streams]:\n');
        
        details = all_streams_details{s};
        for i = 1:length(details.names)
            % 格式化输出，对齐显示流名称和对应的点数
            fprintf('      - %-30s : %d points\n', details.names{i}, details.lengths(i));
        end
        fprintf('----------------------------------------------------------------------------------------\n');
    end
end

%% 7. Print Detailed Diagnostic Reports for Mismatched Sessions
has_mismatches = false;
for s = 1:num_sessions
    if Status(s) == "Warning: Length mismatch" && ~isempty(mismatch_details{s})
        if ~has_mismatches
            disp(' ');
            disp('========================================================================================');
            disp('                          🔍 DETAILED MISMATCH DIAGNOSTICS 🔍                           ');
            disp('========================================================================================');
            has_mismatches = true;
        end
        
        rep = mismatch_details{s};
        fprintf('>>> Session: %s\n', Session_Name(s));
        fprintf('    Majority of EMG streams have %d time points.\n', rep.target_length);
        fprintf('    The following streams deviate from this standard:\n');
        
        for i = 1:length(rep.bad_names)
            if rep.diffs(i) > 0
                diff_str = sprintf('+%d points (longer)', rep.diffs(i));
            else
                diff_str = sprintf('%d points (shorter)', rep.diffs(i));
            end
            
            fprintf('      - Stream Name:  %s\n', rep.bad_names{i});
            fprintf('        Time Points:  %d  [%s]\n', rep.bad_lengths(i), diff_str);
        end
        fprintf('----------------------------------------------------------------------------------------\n');
    end
end

if ~has_mismatches
    fprintf('\n✨ Excellent! All found EMG streams match in length perfectly across all sessions.\n');
end