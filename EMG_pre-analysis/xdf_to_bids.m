%% Batch EMG Preprocessing Script - Phase 1: Alignment & BIDS Export
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
    [mode_len, ~] = mode(all_lengths);
    
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
            raw_time = emg_streams{k}.time_stamps;
            [unique_time, unique_idx] = unique(raw_time);
            
            for ch_offset = 1:length(target_rows)
                row_idx = target_rows(ch_offset);
                raw_data = emg_streams{k}.time_series(ch_offset, unique_idx);
                
                interp_data = interp1(unique_time, raw_data, majority_time_stamps, 'spline', 'extrap');
                raw_data_matrix(row_idx, :) = interp_data;
                found_chans_count = found_chans_count + 1;
            end
        end
    end
    
    fprintf('>> Filled %d/%d channels with interpolated data.\n', found_chans_count, num_expected_chans);
    
    % 3.3 Construct EEGLAB structure
    EEG = eeg_emptyset();
    EEG.setname = sprintf('%s_EMG_RAW', current_session);
    EEG.data   = raw_data_matrix;
    EEG.nbchan = num_expected_chans;
    EEG.pnts   = majority_points; 
    EEG.trials = 1;
    EEG.srate  = str2double(emg_streams{1}.info.nominal_srate);
    EEG.xmin   = 0;
    EEG.xmax   = (EEG.pnts - 1) / EEG.srate;
    
    for i = 1:EEG.nbchan
        EEG.chanlocs(i).labels = expected_labels{i};
    end
    
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
    fprintf('>> Loading calculated gait events (HS and TO) from %s\n', gait_events_file);
    
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
                end
            end
            fprintf('>> Successfully merged %d HS/TO events into EEG structure.\n', gait_event_count);
        end
    else
        warning('Gait events file %s not found. Run event extraction script first.', gait_events_file);
    end
    
    if ~isempty(EEG.event)
        EEG = eeg_checkset(EEG, 'eventconsistency');
    end
    
    %% 4. Save RAW .set file (BIDS Export 的前置准备)
    fprintf('>> Saving RAW .set file to disk...\n');
    
    save_dir = fullfile(data_root, subject_folder, experiment_day, 'processed_EMG');
    if ~exist(save_dir, 'dir'), mkdir(save_dir); end
    
    % 清理并提前将元数据注入 EEG 结构体，这样保存后 bids_export 能自动读取
    bids_subj = strrep(subject_id, '_', ''); 
    bids_ses = strrep(current_session, 'ses-', '');
    bids_ses = strrep(bids_ses, '_', ''); 
    
    EEG.subject = bids_subj;
    EEG.session = bids_ses;
    EEG.run     = str2double(run_id);
    EEG.data    = double(EEG.data);
    
    save_filename = sprintf('sub-%s_%s_%s_run-%s_EMG_Raw.set', subject_id, experiment_day, current_session, run_id);
    full_save_path = fullfile(save_dir, save_filename);
    
    % 执行保存
    EEG = pop_saveset(EEG, 'filename', save_filename, 'filepath', save_dir);
    fprintf('>> Saved RAW .set file to: %s\n', full_save_path);

   %% 5. BIDS Export (Phase 1: Raw Data Archive)
    fprintf('>> Exporting to BIDS format...\n');
    
    bids_root_dir = fullfile('C:', '2026SSArbeit', 'data', 'HipExo-EEG-Study_BIDS');
    if ~exist(bids_root_dir, 'dir'), mkdir(bids_root_dir); end
    
    tInfo = struct('TaskName', 'Default');
    
    % 【终极核心修复】：构建一个名为 export_info 的结构体，把路径赋给它的 'file' 字段
    export_info = struct();
    export_info(1).file = full_save_path;
    
    % 将 export_info 传给 bids_export
    bids_export(export_info, ...
        'targetdir', bids_root_dir, ...
        'tInfo', tInfo, ...
        'modality', 'eeg', ...  % 继续伪装成 eeg 绕过验证
        'README', 'EMG dataset preprocessed and time-aligned via cubic spline interpolation.');
        
      
  %% 6. BIDS 目录扁平化与彻底清洗重命名
    fprintf('>> Running ultimate BIDS flattening and cleaning...\n');
    
    % 6.0 纠正受试者文件夹名 (sub-001 -> sub-Pilot23)
    wrong_sub_dir = fullfile(bids_root_dir, 'sub-001');
    correct_sub_dir = fullfile(bids_root_dir, ['sub-', bids_subj]);
    if exist(wrong_sub_dir, 'dir')
        movefile(wrong_sub_dir, correct_sub_dir);
    end

    % 6.1 暴力揪出所有藏在深处的有效文件，统一转移到正确的目标 emg 目录
    % 目标正统路径：HipExo-EEG-Study_BIDS / sub-Pilot23 / emg (如果带 session 也可以按需调整)
    target_emg_dir = fullfile(correct_sub_dir, 'emg');
    if ~exist(target_emg_dir, 'dir')
        mkdir(target_emg_dir);
    end

    % 递归查找所有带有 _eeg 或 .set / .fdt / .json / .tsv 的数据文件
    all_data_files = [dir(fullfile(correct_sub_dir, '**', '*_eeg.*')); ...
                      dir(fullfile(correct_sub_dir, '**', '*.set')); ...
                      dir(fullfile(correct_sub_dir, '**', '*.fdt')); ...
                      dir(fullfile(correct_sub_dir, '**', '*.tsv')); ...
                      dir(fullfile(correct_sub_dir, '**', '*.json'))];

   for i = 1:length(all_data_files)
        f_name = all_data_files(i).name;
        f_folder = all_data_files(i).folder;
        
        % 排除根目录下的 dataset_description 等文件
        if contains(f_folder, 'sub-')
            src_path = fullfile(f_folder, f_name);
            
            % 清洗文件名
            new_name = strrep(f_name, '_eeg', '_emg');
            new_name = strrep(new_name, 'sub-001', ['sub-', bids_subj]);
            
            dest_path = fullfile(target_emg_dir, new_name);
            
            % 【关键修复】：只有当源路径和目标路径不同时，才执行移动或重命名
            if ~strcmp(src_path, dest_path)
                if exist(src_path, 'file')
                    movefile(src_path, dest_path);
                end
            elseif ~strcmp(f_name, new_name)
                % 如果已经在目标目录下，但名字需要改（比如 _eeg 改成 _emg），直接在原地改名
                movefile(src_path, fullfile(target_emg_dir, new_name));
            end
        end
    end

    % 6.2 清理所有多余的嵌套空文件夹 (把 eeg 文件夹以及多余的层级全部删掉)
    eeg_folders = dir(fullfile(correct_sub_dir, '**', 'eeg'));
    for k = 1:length(eeg_folders)
        if eeg_folders(k).isdir
            f_path = fullfile(eeg_folders(k).folder, eeg_folders(k).name);
            if exist(f_path, 'dir')
                rmdir(f_path, 's'); % 强制递归删除多余的 eeg 文件夹
            end
        end
    end
    
    % 清理可能残留的空 emg 子文件夹
    sub_emg_folders = dir(fullfile(target_emg_dir, '**', 'emg'));
    for k = 1:length(sub_emg_folders)
        if sub_emg_folders(k).isdir
            f_path = fullfile(sub_emg_folders(k).folder, sub_emg_folders(k).name);
            if ~strcmp(f_path, target_emg_dir) && exist(f_path, 'dir')
                rmdir(f_path, 's');
            end
        end
    end

    % 6.3 终极合规补齐：批量修改目标 emg 目录下的所有 _emg.json 文件
    json_files = dir(fullfile(target_emg_dir, '*_emg.json'));
    for j = 1:length(json_files)
        json_path = fullfile(target_emg_dir, json_files(j).name);
        try
            raw_json = fileread(json_path);
            json_data = jsondecode(raw_json);
            
            % 移除脑电残留
            if isfield(json_data, 'EEGReference'), json_data = rmfile(json_data, 'EEGReference'); end
            if isfield(json_data, 'EEGPlacementScheme'), json_data = rmfile(json_data, 'EEGPlacementScheme'); end
            if isfield(json_data, 'EEGChannelCount'), json_data = rmfile(json_data, 'EEGChannelCount'); end
            
            % 写入 EMG 必填项
            json_data.EMGPlacementScheme = 'Measured'; 
            json_data.Manufacturer = 'Delsys'; 
            json_data.PowerLineFrequency = 50; 
            
            new_json_str = jsonencode(json_data);
            fid = fopen(json_path, 'wt');
            if fid ~= -1
                fprintf(fid, '%s', new_json_str);
                fclose(fid);
            end
        catch ME
            warning('Failed to update JSON %s: %s', json_path, ME.message);
        end
    end
    
    fprintf('>> Flattening and compliance check finished for sub-%s!\n', bids_subj);
end

% fprintf('\n========================================================\n');
% fprintf('Phase 1 Pipeline finished successfully!\n');x