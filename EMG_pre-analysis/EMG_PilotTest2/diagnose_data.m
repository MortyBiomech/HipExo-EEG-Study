% Extract Step, Stance, and Swing Times from GRF (.mat) and BIDS EEG (.tsv)
% Includes interactive prompt to verify absolute timestamps against raw XDF and BDF data.
clc;
clear;

%% 1. Load Configurations
run('config_paths.m');
run([current_subject, '_infos.m']); 

% Ensure EEGLAB is in path for pop_biosig
try eeglab nogui; catch; end

% order of subject_3
muscle_list = {
    'Tibialis anterior R'; 'Soleus R'; 'Gastrocnemius cap. mediale R'; 
    'Vastus medialis R'; 'Rectus femoris R'; 'Biceps femoris R'; 'Glutaeus maximus R';
    'Tibialis anterior L'; 'Soleus L'; 'Gastrocnemius cap. mediale L'; 
    'Vastus medialis L'; 'Rectus femoris L'; 'Biceps femoris L'; 'Glutaeus maximus L';
    'Trapezius R'; 'Trapezius L'; 'SCM R'; 'SCM L'; 'Zygomaticus'
};

bids_labels = {
    'Tib_ant_R', 'Soleus_R', 'Gast_med_R', 'Vastus_med_R', 'Rect_fem_R', 'Biceps_fem_R', 'Glut_max_R', ...
    'Tib_ant_L', 'Soleus_L', 'Gast_med_L', 'Vastus_med_L', 'Rect_fem_L', 'Biceps_fem_L', 'Glut_max_L', ...
    'Trapezius_R', 'Trapezius_L', 'SCM_R', 'SCM_L', 'Zygomaticus'
};

% Force plate (GRF) channel definition
Left_leg_indx  = [2 3 6 7];     
Right_leg_indx = [1 4 5 8];

%% 2. Session Order
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

%% 3. Initialize Data Storage
grf_mean_step = NaN(num_sessions, 1); grf_std_step = NaN(num_sessions, 1);
grf_mean_stance = NaN(num_sessions, 1); grf_std_stance = NaN(num_sessions, 1);
grf_mean_swing = NaN(num_sessions, 1); grf_std_swing = NaN(num_sessions, 1);

tsv_mean_step = NaN(num_sessions, 1); tsv_std_step = NaN(num_sessions, 1);
tsv_mean_stance = NaN(num_sessions, 1); tsv_std_stance = NaN(num_sessions, 1);
tsv_mean_swing = NaN(num_sessions, 1); tsv_std_swing = NaN(num_sessions, 1);

valid_conditions = cell(num_sessions, 1);

mat_load_dir = fullfile('C:\2026SSArbeit\data\PilotTest2', subject_folder, experiment_day, 'processed_EMG');
bids_subj_dir = fullfile(bids_root, ['sub-', bids_subject_id]);

hs_r_label = 'HS_R';
to_r_label = 'TO_R';

%% 4. Data Processing & Interactive Verification Loop
fprintf('Starting Comprehensive Gait Parameters Extraction & Verification...\n');

for s = 1:num_sessions
    current_session = order_sessions{s};
    valid_conditions{s} = current_session; 
    
    if contains(current_session, 'Missing')
        continue;
    end
    
    fprintf('\n========================================================\n');
    fprintf('Processing Session [%d/%d]: %s\n', s, num_sessions, current_session);
    
    %% --- 4.1 Process GRF Mat Files ---
    mat_file_name = fullfile(mat_load_dir, sprintf('%s_run-%s_gait_events.mat', current_session, run_id));
    grf_hs_times = []; 
    grf_to_times = [];
    
    if exist(mat_file_name, 'file')
        load(mat_file_name, 'all_events');
        grf_hs_times = [all_events(strcmp({all_events.type}, hs_r_label)).time];
        grf_to_times = [all_events(strcmp({all_events.type}, to_r_label)).time];
        
        stride_vec = diff(grf_hs_times); 
        stance_vec = []; 
        swing_vec = [];
        for k = 1:(length(grf_hs_times)-1)
            curr_hs = grf_hs_times(k);
            to_idx = find(grf_to_times > curr_hs & grf_to_times < grf_hs_times(k+1), 1);
            if ~isempty(to_idx)
                stance_vec(end+1) = grf_to_times(to_idx) - curr_hs; % stance phase TO_R(i) - HS_R(i)
                swing_vec(end+1)  = grf_hs_times(k+1) - grf_to_times(to_idx); % swing phase HS_R(i+1) - HS_R(i)
             end
        end
        if ~isempty(stride_vec)
            grf_mean_step(s) = mean(stride_vec); 
            grf_std_step(s) = std(stride_vec);

            grf_mean_stance(s) = mean(stance_vec); 
            grf_std_stance(s) = std(stance_vec);

            grf_mean_swing(s) = mean(swing_vec); 
            grf_std_swing(s) = std(swing_vec);
        end
    end
    
    %% --- 4.2 Process BIDS TSV Files ---
    bids_session_folder = strrep(current_session, '_', ''); 
    if ~startsWith(bids_session_folder, 'ses-'), bids_session_folder = ['ses-', bids_session_folder]; 
    end
    
    tsv_dir = fullfile(bids_subj_dir, bids_session_folder, 'emg');
    bdf_dir_info = dir(fullfile(tsv_dir, sprintf('*run-%s*_emg.bdf', run_id)));
    tsv_hs_times = []; 
    tsv_to_times = [];
    
    if ~isempty(bdf_dir_info)
        bdf_file_path = fullfile(tsv_dir, bdf_dir_info(1).name);
        tsv_file_name = fullfile(tsv_dir, strrep(bdf_dir_info(1).name, '_emg.bdf', '_events.tsv'));
        
        if exist(tsv_file_name, 'file')
            opts = detectImportOptions(tsv_file_name, 'FileType', 'text', 'Delimiter', '\t');
            events_tbl = readtable(tsv_file_name, opts);
            tsv_labels = strtrim(string(events_tbl.trial_type));
            
            tsv_hs_times = events_tbl.onset(strcmp(tsv_labels, hs_r_label));
            tsv_to_times = events_tbl.onset(strcmp(tsv_labels, to_r_label));
            
            stride_vec = diff(tsv_hs_times); 
            stance_vec = []; 
            swing_vec = [];
            for k = 1:(length(tsv_hs_times)-1)
                curr_hs = tsv_hs_times(k);
                to_idx = find(tsv_to_times > curr_hs & tsv_to_times < tsv_hs_times(k+1), 1);
                if ~isempty(to_idx)
                    stance_vec(end+1) = tsv_to_times(to_idx) - curr_hs;
                    swing_vec(end+1)  = tsv_hs_times(k+1) - tsv_to_times(to_idx);
                end
            end
            if ~isempty(stride_vec)
                tsv_mean_step(s) = mean(stride_vec); 
                tsv_std_step(s) = std(stride_vec);

                tsv_mean_stance(s) = mean(stance_vec);
                tsv_std_stance(s) = std(stance_vec);

                tsv_mean_swing(s) = mean(swing_vec);
                tsv_std_swing(s) = std(swing_vec);
            end
        end
    end
    
    %% --- Interactive Timestamp Checking & Specific Muscle Plotting ---
    max_events = min(length(grf_hs_times), length(tsv_hs_times));
    if max_events > 0
        fprintf('\n[Interactive Check] Session %s has %d HS_R events available.\n', current_session, max_events);
        idx_start = input(sprintf('Enter start event index (1 to %d) [Enter 0 to skip plot]: ', max_events));
        
        if ~isempty(idx_start) && idx_start > 0 && idx_start <= max_events
            idx_end = input(sprintf('Enter end event index (%d to %d): ', idx_start, max_events));
            if isempty(idx_end) || idx_end < idx_start || idx_end > max_events
                idx_end = idx_start; 
            end
            
            % 1. select target muscle
            target_muscle = input('Enter muscle name to plot (Press Enter for ''Soleus R''): ', 's');
            if isempty(strtrim(target_muscle))
                target_muscle = 'Soleus R'; 
            end
            
            ch_idx = find(strcmpi(muscle_list, target_muscle));
            if isempty(ch_idx)
                warning('Muscle "%s" not found in the list. Defaulting to Soleus R (Index 2).', target_muscle);
                ch_idx = 2; 
                target_muscle = 'Soleus R';
            end
            target_bids_label = bids_labels{ch_idx};
            
            % 2. Print Absolute Timestamps
            fprintf('\n--- Absolute Timestamps (Event %d to %d) ---\n', idx_start, idx_end);
            for idx = idx_start:idx_end
                fprintf('Event %03d | GRF(.mat): %.4fs | TSV(.tsv): %.4fs | Offset: %.4fs\n', ...
                    idx, grf_hs_times(idx), tsv_hs_times(idx), grf_hs_times(idx) - tsv_hs_times(idx));
            end
            
            % 3. Load Raw Files
            fprintf('\n>> Loading Raw Data for visualization (Muscle: %s)...\n', target_muscle);
            
            % --- Load XDF (GRF & EMG Data) ---
            xdf_dir = fullfile(data_path, current_session, 'eeg');           
            xdf_search_pattern = sprintf('*run-%s*.xdf', run_id);
            xdf_files = dir(fullfile(xdf_dir, xdf_search_pattern));
            Fz_R_total = []; Fz_L_total = []; xdf_grf_times = [];
            xdf_emg_data = []; 
            xdf_emg_times = [];
            
            if ~isempty(xdf_files)
                [streams, ~] = load_xdf(fullfile(xdf_dir, xdf_files(1).name));
                
                % find GRF stream
                grf_stream_idx = find(strcmp(cellfun(@(x) x.info.name, streams, 'UniformOutput', false), 'GRF'));
                if ~isempty(grf_stream_idx)
                    grf_stream = streams{grf_stream_idx(1)};
                    xdf_grf_times = grf_stream.time_stamps;
                    try
                        Fz_R_total = sum(abs(grf_stream.time_series(Right_leg_indx, :)), 1);
                        Fz_L_total = sum(abs(grf_stream.time_series(Left_leg_indx, :)), 1);
                    catch
                        warning('GRF channel index exceeds data dimensions.');
                    end
                end
                
                % find EMG stream from xdf 
                expected_stream_day1 = data_names_day1{ch_idx};
                expected_stream_day2 = data_names_day2{ch_idx};
                
                target_emg_stream_idx = [];
                for st_idx = 1:length(streams)
                    s_name = streams{st_idx}.info.name;
                    % Match sensor names for Day 1 or Day 2
                    if strcmpi(s_name, expected_stream_day1) || strcmpi(s_name, expected_stream_day2)
                        target_emg_stream_idx = st_idx;
                        break;
                    end
                    % if strcmpi(experiment_day, 'day2')
                    %     expected_stream = data_names_day2{ch_idx};
                    % else
                    %     expected_stream = data_names_day1{ch_idx};
                    % end
                end
                
                if ~isempty(target_emg_stream_idx)
                    emg_stream = streams{target_emg_stream_idx};
                    xdf_emg_times = emg_stream.time_stamps;
                    % In the independent sensor stream, the EMG amplitude data is fixed to row 1
                    xdf_emg_data = emg_stream.time_series(1, :);
                else
                    warning('No matching XDF EMG stream found for "%s". (Looked for: %s)', target_muscle, expected_stream_day2);
                end
            end
            
            % --- Load BDF (EMG Data) ---
            bdf_data_raw = []; bdf_times = [];
            if ~isempty(bdf_dir_info)
                EEG = pop_biosig(bdf_file_path);
                bdf_ch = ch_idx; 
                if ~isempty(EEG.chanlocs)
                    match_idx = find(strcmpi({EEG.chanlocs.labels}, target_bids_label));
                    if ~isempty(match_idx), bdf_ch = match_idx(1); end
                end
                try
                    bdf_data_raw = EEG.data(bdf_ch, :); 
                    bdf_times = (0:EEG.pnts-1) / EEG.srate; 
                catch
                    warning('Channel index %d exceeds the number of channels in BDF data.', bdf_ch);
                end
            end
            
            % 4. Plot Figure 3 (Three Subplots)
            fig3 = figure('Name', sprintf('Raw Alignment Check: %s (Events %d-%d) - %s', current_session, idx_start, idx_end, target_muscle), ...
                   'Position', [50, 50, 1300, 900], 'Color', 'w');
               
            win_start_xdf = grf_hs_times(idx_start) - 0.5;
            win_end_xdf   = grf_hs_times(idx_end) + 1.5;
            win_start_bdf = tsv_hs_times(idx_start) - 0.5;
            win_end_bdf   = tsv_hs_times(idx_end) + 1.5;
            
            % Retrieve valid events within the current time window (XDF/MAT LSL time)
            valid_hs_xdf = grf_hs_times(grf_hs_times >= win_start_xdf & grf_hs_times <= win_end_xdf);
            valid_to_xdf = grf_to_times(grf_to_times >= win_start_xdf & grf_to_times <= win_end_xdf);
            
            % === Subplot 1: XDF Raw (GRF) ===
            subplot(3, 1, 1); hold on;
            if ~isempty(Fz_R_total) && ~isempty(Fz_L_total)
                plot(xdf_grf_times, Fz_L_total, 'Color', [0.7 0.7 0.7], 'LineWidth', 1, 'DisplayName', 'Left Leg GRF');
                plot(xdf_grf_times, Fz_R_total, 'k', 'LineWidth', 1.5, 'DisplayName', 'Right Leg GRF');
            end
            for i = 1:length(valid_hs_xdf), xline(valid_hs_xdf(i), 'b', 'HS_R', 'LineWidth', 1.5, 'HandleVisibility', 'off'); end
            for i = 1:length(valid_to_xdf), xline(valid_to_xdf(i), 'r--', 'TO_R', 'LineWidth', 1.5, 'HandleVisibility', 'off'); end
            
            xlim([win_start_xdf, win_end_xdf]);
            title('XDF Stream (GRF) & Extracted Events (.mat) - LSL Time', 'FontSize', 12, 'FontWeight', 'bold');
            ylabel('Force (N)', 'FontWeight', 'bold'); 
            legend('Location', 'best'); 
            grid on; 
            hold off;
            
            % === Subplot 2: XDF Raw (EMG) ===
            subplot(3, 1, 2); hold on;
            if ~isempty(xdf_emg_data)
                plot(xdf_emg_times, xdf_emg_data, 'k', 'LineWidth', 1, 'DisplayName', sprintf('XDF EMG: %s', target_muscle));
            end
            % LSL-based event timeline
            for i = 1:length(valid_hs_xdf), xline(valid_hs_xdf(i), 'b', 'HS_R', 'LineWidth', 1.5, 'HandleVisibility', 'off'); end
            for i = 1:length(valid_to_xdf), xline(valid_to_xdf(i), 'r--', 'TO_R', 'LineWidth', 1.5, 'HandleVisibility', 'off'); end
            
            xlim([win_start_xdf, win_end_xdf]);
            title(sprintf('XDF Stream (%s EMG) & Extracted Events (.mat) - LSL Time', target_muscle), 'FontSize', 12, 'FontWeight', 'bold');
            ylabel('Amplitude (mV)', 'FontWeight', 'bold'); 
            legend('Location', 'best'); 
            grid on; 
            hold off;
            
            % === Subplot 3: BDF Raw (EMG) ===
            subplot(3, 1, 3); hold on;
            if ~isempty(bdf_data_raw)
                plot(bdf_times, bdf_data_raw, 'k', 'LineWidth', 1, 'DisplayName', sprintf('BDF EMG: %s', target_bids_label)); 
            end
            
            % uses a BIDS TSV event timeline
            valid_hs_bdf = tsv_hs_times(tsv_hs_times >= win_start_bdf & tsv_hs_times <= win_end_bdf);
            valid_to_bdf = tsv_to_times(tsv_to_times >= win_start_bdf & tsv_to_times <= win_end_bdf);
            for i = 1:length(valid_hs_bdf), xline(valid_hs_bdf(i), 'b', 'HS_R', 'LineWidth', 1.5, 'HandleVisibility', 'off'); end
            for i = 1:length(valid_to_bdf), xline(valid_to_bdf(i), 'r--', 'TO_R', 'LineWidth', 1.5, 'HandleVisibility', 'off'); end
            
            xlim([win_start_bdf, win_end_bdf]);
            title(sprintf('BDF Stream (%s) & BIDS Events (.tsv) - Record Time', target_bids_label), 'FontSize', 12, 'FontWeight', 'bold'); 
            ylabel('Amplitude (\muV)', 'FontWeight', 'bold'); 
            xlabel('Relative Record Time (s)', 'FontWeight', 'bold'); 
            legend('Location', 'best'); 
            grid on; 
            hold off;
            
            disp('>> Visually verify Figure 3. Press Enter to close and proceed to next session...');
            pause;
            if ishandle(fig3), close(fig3); end
        end
    end
end

%% 5. Plotting Configurations (Figures 1 & 2)
conditions_plotorder = {'NoExoPre', 'aquaplus', 'aqua', 'transparent', 'eco', 'sport', 'boost', 'NoExoPost'};
clean_labels = cell(num_sessions, 1);
for i = 1:num_sessions, clean_labels{i} = conditions_plotorder{i}; end
mrk_size = 8; lw = 1.5; cap_size = 6; x_base = 1:num_sessions;

%% --- FIGURE 1: GRF-Derived Parameters ---
figure('Name', 'GRF Gait Parameters Across Conditions', 'Position', [100, 150, 950, 550], 'Color', 'w');
hold on;
grid on;
h1_step = errorbar(x_base, grf_mean_step, grf_std_step, 'o', 'MarkerEdgeColor', 'k', 'MarkerFaceColor', [0.2 0.6 1.0], 'LineWidth', lw, 'Color', [0.2 0.6 1.0]);
h1_stance = errorbar(x_base, grf_mean_stance, grf_std_stance, 'd', 'MarkerEdgeColor', 'k', 'MarkerFaceColor', [1.0 0.6 0.2], 'LineWidth', lw, 'Color', [1.0 0.6 0.2]);
h1_swing = errorbar(x_base, grf_mean_swing, grf_std_swing, 's', 'MarkerEdgeColor', 'k', 'MarkerFaceColor', [0.2 0.7 0.2], 'LineWidth', lw, 'Color', [0.2 0.7 0.2]);
ax1 = gca; 
ax1.XTick = 1:num_sessions; 
ax1.XTickLabel = clean_labels; 
ax1.XTickLabelRotation = 45; 
ax1.GridLineStyle = '--';
xlabel('Condition', 'FontWeight', 'bold'); ylabel('Time (s)', 'FontWeight', 'bold');
title(sprintf('Gait Temporal Parameters (Source: GRF .mat) - Subject: %s', bids_subject_id));
legend([h1_step, h1_stance, h1_swing], {'Step Time', 'Stance Phase', 'Swing Phase'}); 
xlim([0.5, num_sessions + 0.5]); 
hold off;

%% --- FIGURE 2: BIDS TSV-Derived Parameters ---
figure('Name', 'BIDS EEG Gait Parameters Across Conditions', 'Position', [1100, 150, 950, 550], 'Color', 'w');
hold on; 
grid on;
h2_step = errorbar(x_base, tsv_mean_step, tsv_std_step, 'o', 'MarkerEdgeColor', 'k', 'MarkerFaceColor', [0.2 0.6 1.0], 'LineWidth', lw, 'Color', [0.2 0.6 1.0]);
h2_stance = errorbar(x_base, tsv_mean_stance, tsv_std_stance, 'd', 'MarkerEdgeColor', 'k', 'MarkerFaceColor', [1.0 0.6 0.2], 'LineWidth', lw, 'Color', [1.0 0.6 0.2]);
h2_swing = errorbar(x_base, tsv_mean_swing, tsv_std_swing, 's', 'MarkerEdgeColor', 'k', 'MarkerFaceColor', [0.2 0.7 0.2], 'LineWidth', lw, 'Color', [0.2 0.7 0.2]);
ax2 = gca; 
ax2.XTick = 1:num_sessions; 
ax2.XTickLabel = clean_labels; 
ax2.XTickLabelRotation = 45; 
ax2.GridLineStyle = '--';
xlabel('Condition', 'FontWeight', 'bold'); ylabel('Time (s)', 'FontWeight', 'bold');
title(sprintf('Gait Temporal Parameters (Source: BIDS TSV) - Subject: %s', bids_subject_id));
legend([h2_step, h2_stance, h2_swing], {'Step Time', 'Stance Phase', 'Swing Phase'}); 
xlim([0.5, num_sessions + 0.5]); 
hold off;

fprintf('\nAll processing complete!\n');