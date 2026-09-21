% 2. 定义 8 组 Session 名称
order_sessions = {'NoExoPre', 'Exo1_sport', 'Exo2_aquaplus', 'ExoOff', ...
                  'Exo3_eco', 'Exo4_aqua', 'Exo5_boost', 'NoExoPost'};
num_sessions = length(order_sessions);

% 3. 创建 "储物柜"，用来存放 8 个 session 处理完的数据
session_data_cell  = cell(1, num_sessions);
session_edges_cell = cell(1, num_sessions);
global_muscle_names = {}; % 用于保存供 UI 显示的肌肉通道名称

%% ========================================================================
%% 核心大循环：遍历并处理每一组 Session
%% ========================================================================

    dict_data_names = {
        'Delsys_S3_EMG'; 'Delsys_S4_EMG'; 'Delsys_S1_EMG'; 'Delsys_S5_EMG';
        'Delsys_S6_EMG'; 'Delsys_S0_EMG'; 'Delsys_S7_EMG'; 'Delsys_S8_EMG';
        'Delsys_S9_EMG'; 'Delsys_S10_EMG'; 'Delsys_S11_EMG'; 'Delsys_S12_EMG';
        'Delsys_S13_EMG'; 'Delsys_S14_EMG'; 'Delsys_S15_EMG'; 'Delsys_S2_EMG';
        'Delsys_S16_EMG'; 'Delsys_S17_EMG'; 'Delsys_S18_EMG'
    };

    dict_muscle_names = {
        'Tibialis anterior R'; 'Soleus R'; 'Gastrocnemius cap. mediale R'; 'Vastus medialis R';
        'Rectus femoris R'; 'Biceps femoris R'; 'Glutaeus maximus R'; 'Tibialis anterior L';
        'Soleus L'; 'Gastrocnemius cap. mediale L'; 'Vastus medialis L'; 'Rectus femoris L';
        'Biceps femoris L'; 'Glutaeus maximus L'; 'Trapezius R'; 'Trapezius L';
        'SCM R'; 'SCM L'; 'Zygomaticus'
    };
    
for s = 1:num_sessions
    current_session = order_sessions{s};
    fprintf('\n========================================================\n');
    fprintf('正在处理 Session %d/8: %s...\n', s, current_session);
    
    % ---------------------------------------------------------------------
    % 【步骤 A】：在此处加载当前 Session 的数据
    % 你需要确保加载后的工作区中包含：
    % 1. streams (LSL 数据流，包含 EMG 数据)
    % 2. HS_R, TO_L, HS_L, TO_R (步态事件结构体，包含 .timestamps)
    % ---------------------------------------------------------------------
    processed_dir = 'C:\2026SSArbeit\data\PilotTest2\Sub-P2_1\day2\processed_EMG\';
    data_file = fullfile(processed_dir, sprintf('Data_%s.mat', current_session));
    
    % ⭐ 新增的容错跳过机制 ⭐
    if ~exist(data_file, 'file')
        warning('未找到预处理文件: %s。\n该组数据可能在预处理时损坏被跳过。', sprintf('Data_%s.mat', current_session));
        % 将这组数据在储物柜中标记为空，供 UI 识别
        session_data_cell{s}  = []; 
        session_edges_cell{s} = [];
        continue; % 直接跳过当前循环，去处理下一组数据
    end
    
    fprintf('>> 正在快速加载内存数据: %s\n', data_file);
    load(data_file);
    % ---------------------------------------------------------------------
    
    % 检查必需变量是否存在 (防止未加载成功直接报错)
    if ~exist('streams', 'var') || ~exist('HS_R', 'var')
        warning('未找到 Session %s 的必需变量 (streams 或 HS_R)，请检查加载代码！跳过此组...', current_session);
        continue;
    end
                            
    % 获取步态事件的绝对时间戳
    t_rhs = HS_R.timestamps;
    t_lto = TO_L.timestamps;
    t_lhs = HS_L.timestamps;
    t_rto = TO_R.timestamps;

 
    % ---------------------------------------------------------------------
    % 【步骤 B】：筛选 EMG 通道与匹配完整步态周期
    % ---------------------------------------------------------------------
    emg_indices = [];
    for i = 1:length(streams)
        if strcmp(streams{i}.info.type, 'EMG') 
            emg_indices = [emg_indices, i];
        end
    end
    
    total_emg_channels = 0;
    for m = 1:length(emg_indices)
        idx = emg_indices(m);
        total_emg_channels = total_emg_channels + size(streams{idx}.time_series, 1);
    end
    
    % 匹配包含 5 个关键时间点的完整步态周期
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
    
    fs_emg = streams{emg_indices(1)}.info.effective_srate; % 通常是 2148 Hz
    durations_time = diff(valid_cycles_time, 1, 2); 
    durations_samples = round(durations_time * fs_emg);
    num_cycles = size(valid_cycles_time, 1);
    
    % 剔除首尾各 20 步 (保证数据稳定性)
    cycle_start = 21;
    cycle_end = num_cycles - 20;
    if num_cycles > 40
        selected_samples = durations_samples(cycle_start:cycle_end, :);
        median_durs = round(median(selected_samples, 1));
        fprintf('>> 使用第 %d 到 %d 步 (共 %d 步) 计算中位数模板。\n', ...
            cycle_start, cycle_end, size(selected_samples,1));
        valid_cycles_time = valid_cycles_time(cycle_start:cycle_end, :);
        num_cycles = num_cycles - 40;
    else
        warning('步数不足 40 步 (仅 %d 步)，使用所有步数计算中位数。', num_cycles);
        median_durs = round(median(durations_samples, 1));
    end
    
    total_target_length = sum(median_durs);
    
    % 计算事件分割线在 0-100% 轴上的百分比位置
    phase_edges_percent = cumsum(median_durs) / total_target_length * 100;
    
    % ---------------------------------------------------------------------
    % 【步骤 C】：EEGLAB Time-Warping 提取并规整 EMG 包络线
    % ---------------------------------------------------------------------
    fprintf('>> 开始进行 EMG 信号处理与 Time-Warping...\n');
    all_warped_emg = zeros(num_cycles, total_target_length, total_emg_channels);
    muscle_names = cell(1, total_emg_channels);
    
    global_ch_idx = 1; 
    newlatency = [1, ...
                  1 + median_durs(1), ...
                  1 + sum(median_durs(1:2)), ...
                  1 + sum(median_durs(1:3)), ...
                  total_target_length];
                  
    
    for m = 1:length(emg_indices)
        idx = emg_indices(m);
        raw_sensor_name = streams{idx}.info.name; 
        
        % ⭐️ 新增的翻译逻辑：在字典中寻找对应的肌肉名字
        match_idx = find(strcmp(map_data_names, raw_sensor_name));
        if ~isempty(match_idx)
            % 如果在字典里找到了，就用真实的解剖学肌肉名
            biological_name = map_muscle_names{match_idx(1)};
        else
            % 如果没找到 (比如突然多了一个未知的传感器)，就保留原名防止报错
            biological_name = raw_sensor_name;
        end
        
        num_local_channels = size(streams{idx}.time_series, 1);
        emg_time = streams{idx}.time_stamps;
        
        for ch = 1:num_local_channels
            if num_local_channels > 1
                current_muscle_name = sprintf('%s_Ch%d', biological_name, ch);
            else
                current_muscle_name = biological_name;
            end
            
            % 将翻译好的名字存入列表中，最终传给 UI
            muscle_names{global_ch_idx} = current_muscle_name;
            
            % ... (下方继续保留你原来的 butter 滤波和 timewarp 代码即可)
            raw_emg = double(streams{idx}.time_series(ch, :));
            
            % 预处理: 带通 -> 整流 -> 低通
            [b_bp, a_bp] = butter(4, [20, 400] / (fs_emg/2), 'bandpass');
            emg_filt = filtfilt(b_bp, a_bp, raw_emg);
            emg_rect = abs(emg_filt);
            [b_lp, a_lp] = butter(4, 6 / (fs_emg/2), 'low');
            emg_env = filtfilt(b_lp, a_lp, emg_rect);
            
            % 使用 EEGLAB 进行时间扭曲
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
    
    % ---------------------------------------------------------------------
    % 【步骤 D】：将当前 Session 的结果存入储物柜
    % ---------------------------------------------------------------------
    session_data_cell{s}  = all_warped_emg; 
    session_edges_cell{s} = phase_edges_percent; 
    
    if isempty(global_muscle_names)
        global_muscle_names = muscle_names;
    end
    
    fprintf('>> Session %s 数据已成功存入内存。\n', current_session);
    
    % 可选：为了防止内存过载，清理当次循环用到的大型原始变量
    clear streams HS_R TO_L HS_L TO_R; 
end

%% ========================================================================
%% 启动交互式仪表盘！
%% ========================================================================
fprintf('\n所有 8 组数据处理完成，正在启动仪表盘...\n');
launch_emg_dashboard(order_sessions, session_data_cell, session_edges_cell, global_muscle_names);