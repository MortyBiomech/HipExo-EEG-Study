% Extract Step, Stance, and Swing Times from both GRF (.mat) and BIDS EEG (.tsv) and plot on separate figures
clc;
clear;

%% 1. Load Configurations
run('config_paths.m');
run([current_subject, '_infos.m']); 

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
% Arrays for Figure 1: GRF Data
grf_mean_step = NaN(num_sessions, 1); grf_std_step = NaN(num_sessions, 1);
grf_mean_stance = NaN(num_sessions, 1); grf_std_stance = NaN(num_sessions, 1);
grf_mean_swing = NaN(num_sessions, 1); grf_std_swing = NaN(num_sessions, 1);

% Arrays for Figure 2: BIDS TSV Data
tsv_mean_step = NaN(num_sessions, 1); tsv_std_step = NaN(num_sessions, 1);
tsv_mean_stance = NaN(num_sessions, 1); tsv_std_stance = NaN(num_sessions, 1);
tsv_mean_swing = NaN(num_sessions, 1); tsv_std_swing = NaN(num_sessions, 1);

valid_conditions = cell(num_sessions, 1);

% Paths setup
mat_load_dir = fullfile('C:\2026SSArbeit\data\PilotTest2', subject_folder, experiment_day, 'processed_EMG');
bids_subj_dir = fullfile(bids_root, ['sub-', bids_subject_id]);

% Defined event markers
hs_r_label = 'HS_R';
to_r_label = 'TO_R';

%% 4. Data Processing Loop
fprintf('Starting Comprehensive Gait Parameters Extraction for subject %s...\n', subject_id);

for s = 1:num_sessions
    current_session = order_sessions{s};
    valid_conditions{s} = current_session; 
    
    if contains(current_session, 'Missing')
        fprintf('Skipping missing session: %s\n', current_session);
        continue;
    end
    
    %% --- 4.1 Process GRF Mat Files (Figure 1 Source) ---
    mat_file_name = fullfile(mat_load_dir, sprintf('%s_run-%s_gait_events.mat', current_session, run_id));
    
    if exist(mat_file_name, 'file')
        load(mat_file_name, 'all_events');
        
        grf_hs_times = [all_events(strcmp({all_events.type}, hs_r_label)).time];
        grf_to_times = [all_events(strcmp({all_events.type}, to_r_label)).time];
        
        step_vec = []; stance_vec = []; swing_vec = [];
        for k = 1:(length(grf_hs_times)-1)
            curr_hs = grf_hs_times(k);
            next_hs = grf_hs_times(k+1);
            to_idx = find(grf_to_times > curr_hs & grf_to_times < next_hs, 1);
            if ~isempty(to_idx)
                curr_to = grf_to_times(to_idx);
                step_vec(end+1)   = next_hs - curr_hs;
                stance_vec(end+1) = curr_to - curr_hs;
                swing_vec(end+1)  = next_hs - curr_to;
            end
        end
        if ~isempty(step_vec)
            grf_mean_step(s) = mean(step_vec);     grf_std_step(s) = std(step_vec);
            grf_mean_stance(s) = mean(stance_vec); grf_std_stance(s) = std(stance_vec);
            grf_mean_swing(s) = mean(swing_vec);   grf_std_swing(s) = std(swing_vec);
        end
    else
        warning('Mat file not found: %s', mat_file_name);
    end
    
    %% --- 4.2 Process BIDS TSV Files (Figure 2 Source) ---
    % Standard BIDS naming convention mapping ses-ExoX to the folder structure
    bids_session_folder = strrep(current_session, '_', ''); 
    if ~startsWith(bids_session_folder, 'ses-')
        bids_session_folder = ['ses-', bids_session_folder];
    end
    
    tsv_dir = fullfile(bids_subj_dir, bids_session_folder, 'emg');
    % Find the BDF filename first to derive the correct standard tsv name
    bdf_dir_info = dir(fullfile(tsv_dir, sprintf('*run-%s*_emg.bdf', run_id)));
    
    if ~isempty(bdf_dir_info)
        tsv_filename = strrep(bdf_dir_info(1).name, '_emg.bdf', '_events.tsv');
        tsv_file_name = fullfile(tsv_dir, tsv_filename);
        
        if exist(tsv_file_name, 'file')
            opts = detectImportOptions(tsv_file_name, 'FileType', 'text', 'Delimiter', '\t');
            events_tbl = readtable(tsv_file_name, opts);
            
            tsv_labels = strtrim(string(events_tbl.trial_type));
            tsv_hs_times = events_tbl.onset(strcmp(tsv_labels, hs_r_label));
            tsv_to_times = events_tbl.onset(strcmp(tsv_labels, to_r_label));
            
            step_vec = []; stance_vec = []; swing_vec = [];
            for k = 1:(length(tsv_hs_times)-1)
                curr_hs = tsv_hs_times(k);
                next_hs = tsv_hs_times(k+1);
                to_idx = find(tsv_to_times > curr_hs & tsv_to_times < next_hs, 1);
                if ~isempty(to_idx)
                    curr_to = tsv_to_times(to_idx);
                    step_vec(end+1)   = next_hs - curr_hs;
                    stance_vec(end+1) = curr_to - curr_hs;
                    swing_vec(end+1)  = next_hs - curr_to;
                end
            end
            if ~isempty(step_vec)
                tsv_mean_step(s) = mean(step_vec);     tsv_std_step(s) = std(step_vec);
                tsv_mean_stance(s) = mean(stance_vec); tsv_std_stance(s) = std(stance_vec);
                tsv_mean_swing(s) = mean(swing_vec);   tsv_std_swing(s) = std(swing_vec);
                
                fprintf('Session %s [TSV extracted]: Step=%.3fs, Stance=%.3fs, Swing=%.3fs\n', ...
                    current_session, tsv_mean_step(s), tsv_mean_stance(s), tsv_mean_swing(s));
            end
        else
            warning('TSV file not found: %s', tsv_file_name);
        end
    else
        warning('No matching BDF/TSV directory structure found for %s', bids_session_folder);
    end
end

%% 5. Plotting Configurations
conditions_plotorder = {'NoExoPre', 'aquaplus', 'aqua', 'transparent', 'eco', 'sport', 'boost', 'NoExoPost'};
clean_labels = cell(num_sessions, 1);
for i = 1:num_sessions
    clean_labels{i} = conditions_plotorder{i};
end

mrk_size = 8; lw = 1.5; cap_size = 6; x_base = 1:num_sessions;

%% --- FIGURE 1: GRF-Derived Parameters ---
figure('Name', 'GRF Gait Parameters Across Conditions', 'Position', [100, 150, 950, 550], 'Color', 'w');
hold on; grid on;

h1_step = errorbar(x_base, grf_mean_step, grf_std_step, 'o', 'MarkerSize', mrk_size, ...
    'MarkerEdgeColor', 'k', 'MarkerFaceColor', [0.2 0.6 1.0], 'LineWidth', lw, 'CapSize', cap_size, 'Color', [0.2 0.6 1.0]);
h1_stance = errorbar(x_base, grf_mean_stance, grf_std_stance, 'd', 'MarkerSize', mrk_size, ...
    'MarkerEdgeColor', 'k', 'MarkerFaceColor', [1.0 0.6 0.2], 'LineWidth', lw, 'CapSize', cap_size, 'Color', [1.0 0.6 0.2]);
h1_swing = errorbar(x_base, grf_mean_swing, grf_std_swing, 's', 'MarkerSize', mrk_size, ...
    'MarkerEdgeColor', 'k', 'MarkerFaceColor', [0.2 0.7 0.2], 'LineWidth', lw, 'CapSize', cap_size, 'Color', [0.2 0.7 0.2]);

ax1 = gca; ax1.XTick = 1:num_sessions; ax1.XTickLabel = clean_labels; ax1.XTickLabelRotation = 45;
ax1.FontSize = 11; ax1.LineWidth = 1.2; ax1.GridLineStyle = '--'; ax1.GridAlpha = 0.4;
xlabel('Condition', 'FontSize', 14, 'FontWeight', 'bold'); ylabel('Time (s)', 'FontSize', 14, 'FontWeight', 'bold');
title(sprintf('Gait Temporal Parameters (Source: GRF .mat) - Subject: %s', bids_subject_id), 'FontSize', 14);
legend([h1_step, h1_stance, h1_swing], {'Full Step Time', 'Stance Phase Time', 'Swing Phase Time'}, 'Location', 'best');
xlim([0.5, num_sessions + 0.5]); 
all_max_1 = max([grf_mean_step + grf_std_step; grf_mean_stance + grf_std_stance; grf_mean_swing + grf_std_swing]);
ylim([0, 1.2]);
hold off;

%% --- FIGURE 2: BIDS TSV-Derived Parameters ---
figure('Name', 'BIDS EEG Gait Parameters Across Conditions', 'Position', [1100, 150, 950, 550], 'Color', 'w');
hold on; grid on;

h2_step = errorbar(x_base, tsv_mean_step, tsv_std_step, 'o', 'MarkerSize', mrk_size, ...
    'MarkerEdgeColor', 'k', 'MarkerFaceColor', [0.2 0.6 1.0], 'LineWidth', lw, 'CapSize', cap_size, 'Color', [0.2 0.6 1.0]);
h2_stance = errorbar(x_base, tsv_mean_stance, tsv_std_stance, 'd', 'MarkerSize', mrk_size, ...
    'MarkerEdgeColor', 'k', 'MarkerFaceColor', [1.0 0.6 0.2], 'LineWidth', lw, 'CapSize', cap_size, 'Color', [1.0 0.6 0.2]);
h2_swing = errorbar(x_base, tsv_mean_swing, tsv_std_swing, 's', 'MarkerSize', mrk_size, ...
    'MarkerEdgeColor', 'k', 'MarkerFaceColor', [0.2 0.7 0.2], 'LineWidth', lw, 'CapSize', cap_size, 'Color', [0.2 0.7 0.2]);

ax2 = gca; ax2.XTick = 1:num_sessions; ax2.XTickLabel = clean_labels; ax2.XTickLabelRotation = 45;
ax2.FontSize = 11; ax2.LineWidth = 1.2; ax2.GridLineStyle = '--'; ax2.GridAlpha = 0.4;
xlabel('Condition', 'FontSize', 14, 'FontWeight', 'bold'); ylabel('Time (s)', 'FontSize', 14, 'FontWeight', 'bold');
title(sprintf('Gait Temporal Parameters (Source: BIDS TSV) - Subject: %s', bids_subject_id), 'FontSize', 14);
legend([h2_step, h2_stance, h2_swing], {'Full Step Time', 'Stance Phase Time', 'Swing Phase Time'}, 'Location', 'best');
xlim([0.5, num_sessions + 0.5]);
all_max_2 = max([tsv_mean_step + tsv_std_step; tsv_mean_stance + tsv_std_stance; tsv_mean_swing + tsv_std_swing]);
ylim([0, 1.2]);
hold off;

fprintf('\nBoth plots generated successfully!\n');