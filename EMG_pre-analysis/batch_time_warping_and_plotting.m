%% EMG Time-Warping, Outlier Annotation and Multi-Condition Plotting
clc;
clear;

%% 1. Configuration Setup
run('config_paths.m');
run([current_subject, '_infos.m']); 

input_pipeline = 'eeglab_emg_prep'; 
output_pipeline = 'eeglab_emg_warp'; 

subj_in_dir  = fullfile(bids_root, 'derivatives', input_pipeline, ['sub-', bids_subject_id]); 
plot_save_dir = fullfile(bids_root, 'derivatives', output_pipeline, ['sub-', bids_subject_id], 'figures');
if ~exist(plot_save_dir, 'dir'), mkdir(plot_save_dir); end

eeglab nogui;

%% 2. Process Sessions and Prepare Data Cache
d = dir(fullfile(subj_in_dir, 'ses-*'));
session_folders = {d([d.isdir]).name};
num_sessions = length(session_folders);

target_sequence = {'HS_R', 'TO_L', 'HS_L', 'TO_R', 'HS_R'};
num_anchors = length(target_sequence);

all_sessions_data = cell(1, num_sessions);
master_chan_labels = {}; 

%% 3. Main Loop: Annotation, Time-Warping & Plotting
for s = 1:num_sessions
    current_session = session_folders{s};
    fprintf('\n========================================================\n');
    fprintf('Processing Session [%d/%d]: %s...\n', s, num_sessions, current_session);
    
    session_emg_dir = fullfile(subj_in_dir, current_session, 'emg');
    set_files = dir(fullfile(session_emg_dir, '*_desc-Epoched_emg.set'));
    
    if isempty(set_files)
        warning('No Epoched .set file found. Skipping.');
        continue;
    end
    
    filename = set_files(1).name;
    EEG = pop_loadset('filename', filename, 'filepath', session_emg_dir);
    num_epochs = EEG.trials;
    
    % Prepare save directory early for intermediate saving
    save_dir = fullfile(bids_root, 'derivatives', output_pipeline, ['sub-', bids_subject_id], current_session, 'emg');
    if ~exist(save_dir, 'dir'), mkdir(save_dir); end
    
    %% --- Step 3.1: Structural Check (Annotate badepoch) ---
    fprintf('>> Identifying structurally incomplete epochs across %d epochs...\n', num_epochs);
    timevals_frames = nan(num_epochs, num_anchors);
    badepoch = zeros(num_epochs, 1);
    
    for e = 1:num_epochs
        ev_types = strtrim(string(EEG.epoch(e).eventtype)); 
        ev_lats  = cell2mat(EEG.epoch(e).eventlatency); 
        
        ev_frames_relative = round((ev_lats - EEG.times(1)) / (1000/EEG.srate)) + 1;
        
        try
            idx_1 = find(strcmp(ev_types, 'HS_R') & ev_lats >= -10 & ev_lats <= 10, 1);
            timevals_frames(e, 1) = ev_frames_relative(idx_1);
            
            idx_2 = find(strcmp(ev_types, 'TO_L') & ev_lats > 0, 1);
            timevals_frames(e, 2) = ev_frames_relative(idx_2);
            
            idx_3 = find(strcmp(ev_types, 'HS_L') & ev_lats > ev_lats(idx_2), 1);
            timevals_frames(e, 3) = ev_frames_relative(idx_3);
            
            idx_4 = find(strcmp(ev_types, 'TO_R') & ev_lats > ev_lats(idx_3), 1);
            timevals_frames(e, 4) = ev_frames_relative(idx_4);
            
            idx_5 = find(strcmp(ev_types, 'HS_R') & ev_lats > ev_lats(idx_4), 1);
            timevals_frames(e, 5) = ev_frames_relative(idx_5);
            
            if any(isnan(timevals_frames(e, :))) || any(diff(timevals_frames(e, :)) <= 0)
                badepoch(e) = 1;
            end
        catch
            badepoch(e) = 1; 
        end
    end
    fprintf('   - Found %d structurally bad epochs.\n', sum(badepoch));
    
    %% --- Step 3.2: Best Practice Outlier Rejection (Annotate isoutlier) ---
    fprintf('>> Performing Outlier Rejection (Peak > 3SD)...\n');
    isoutlier = badepoch; % Rule 1: badepoch implies isoutlier=1
    
    % Calculate peak amplitude over time for all channels and all epochs
    % squeeze(max(data,[],2)) returns [channels x epochs]
    epoch_peaks = squeeze(max(EEG.data, [], 2)); 
    
    for ch = 1:EEG.nbchan
        % Only use structurally SOUND epochs to calculate the mean and std threshold
        valid_peaks_for_stats = epoch_peaks(ch, badepoch == 0);
        
        if isempty(valid_peaks_for_stats)
            continue; 
        end
        
        mean_peak = mean(valid_peaks_for_stats);
        std_peak  = std(valid_peaks_for_stats);
        upper_bound = mean_peak + 3 * std_peak;
        
        % Mark outliers for this channel across ALL epochs
        ch_outliers = epoch_peaks(ch, :) > upper_bound;
        isoutlier(ch_outliers) = 1;
    end
    fprintf('   - Total %d epochs marked as isoutlier=1.\n', sum(isoutlier));
    
    %% --- Step 3.3: Inject Flags into Structure & Save Annotated Dataset ---
    for e = 1:num_epochs
        EEG.epoch(e).badepoch = badepoch(e);
        EEG.epoch(e).isoutlier = isoutlier(e);
    end
    
    EEG = eeg_checkset(EEG);
    save_filename_annotated = strrep(filename, '_desc-Epoched_emg.set', '_desc-FlaggedEpoched_emg.set');
    EEG = pop_saveset(EEG, 'filename', save_filename_annotated, 'filepath', save_dir);
    fprintf('>> [SAVE 1] Saved annotated dataset with QC flags to: %s\n', save_filename_annotated);
    
    %% --- Step 3.4: Filter isoutlier == 0 and Perform Time-Warping ---
    clean_idx = find(isoutlier == 0);
    num_valid = length(clean_idx);
    
    if num_valid < 2
        warning('Not enough clean cycles for timewarping. Skipping session.');
        continue;
    end
    
    % Extract time frames only for clean epochs
    timevals_frames_clean = timevals_frames(clean_idx, :);
    
    % Use EEGLAB's native pop_select to safely extract clean epochs.
    % This perfectly syncs EEG.data, EEG.epoch, and EEG.event without throwing eeg_checkset errors!
    EEG_clean = pop_select(EEG, 'trial', clean_idx);
    
    warpvals_frames = round(median(timevals_frames_clean, 1));
    warpvals_frames = warpvals_frames - warpvals_frames(1) + 1; 
    target_length = warpvals_frames(end);
    
    warped_data = zeros(EEG_clean.nbchan, target_length, num_valid);
    
    fprintf('>> Applying EEGLAB timewarp() function on %d clean epochs...\n', num_valid);
    for e = 1:num_valid
        ev_in = timevals_frames_clean(e, :);
        start_frame = ev_in(1);
        end_frame   = ev_in(end);
        epoch_raw   = EEG_clean.data(:, start_frame:end_frame, e);
        
        ev_in = ev_in - ev_in(1) + 1;
        warpmat = timewarp(ev_in, warpvals_frames);
        warped_data(:, :, e) = epoch_raw * warpmat'; 
    end
    
    %% --- Step 3.5: Update and Save Timewarped Dataset ---
    EEG_clean.data = warped_data;
    EEG_clean.times = linspace(0, 100, target_length); 
    EEG_clean.pnts = target_length;
    EEG_clean.event = []; % Clear absolute time events as they are meaningless post-warp
    
    EEG_clean = eeg_checkset(EEG_clean);
    save_filename_warped = strrep(filename, '_desc-Epoched_emg.set', '_desc-Timewarped_emg.set');
    EEG_clean = pop_saveset(EEG_clean, 'filename', save_filename_warped, 'filepath', save_dir);
    fprintf('>> [SAVE 2] Saved clean Time-Warped dataset to: %s\n', save_filename_warped);
    
    %% --- Step 3.6: Cache Data for Multi-Condition Plotting ---
    all_sessions_data{s}.session_name = current_session;
    all_sessions_data{s}.labels = {EEG_clean.chanlocs.labels};
    all_sessions_data{s}.mean_data = mean(warped_data, 3, 'omitnan');
    all_sessions_data{s}.std_data = std(warped_data, 0, 3, 'omitnan');
    all_sessions_data{s}.times = EEG_clean.times; 
    all_sessions_data{s}.valid = true;
    
    master_chan_labels = unique([master_chan_labels, all_sessions_data{s}.labels], 'stable');
end

%% 4. Multi-Condition Plotting (All Sessions per Muscle into 1 Figure)
fprintf('\n========================================================\n');
fprintf('Generating Multi-Condition Comparison Plots...\n');

num_master_channels = length(master_chan_labels);
colors = lines(num_sessions); 

for ch = 1:num_master_channels
    muscle_name = master_chan_labels{ch};
    
    figure('Name', sprintf('Muscle Activation: %s', muscle_name), 'Position', [100, 100, 900, 600], 'Visible', 'off');
    hold on;
    
    legend_handles = [];
    legend_labels = {};
    
    for s = 1:num_sessions
        if isempty(all_sessions_data{s}) || ~all_sessions_data{s}.valid
            continue;
        end
        
        ch_idx = find(strcmp(all_sessions_data{s}.labels, muscle_name));
        if isempty(ch_idx)
            continue;
        end
        
        x_axis = all_sessions_data{s}.times;
        mean_profile = all_sessions_data{s}.mean_data(ch_idx, :);
        std_profile = all_sessions_data{s}.std_data(ch_idx, :);
        
        fill_x = [x_axis, fliplr(x_axis)];
        fill_y = [mean_profile + std_profile, fliplr(max(0, mean_profile - std_profile))];
        patch(fill_x, fill_y, colors(s, :), 'EdgeColor', 'none', 'FaceAlpha', 0.1);
        
        h_line = plot(x_axis, mean_profile, 'Color', colors(s, :), 'LineWidth', 2);
        
        legend_handles(end+1) = h_line;
        legend_labels{end+1} = all_sessions_data{s}.session_name;
    end
    
    xlim([0 100]);
    xlabel('Gait Cycle (%)', 'FontSize', 12, 'FontWeight', 'bold');
    ylabel('EMG Amplitude (\muV)', 'FontSize', 12, 'FontWeight', 'bold');
    title(sprintf('Multi-Condition Comparison: %s', strrep(muscle_name, '_', '\_')), 'FontSize', 14, 'FontWeight', 'bold');
    
    if ~isempty(legend_handles)
        legend(legend_handles, legend_labels, 'Location', 'northeastoutside', 'Interpreter', 'none');
    end
    grid on; box on;
    
    safe_muscle_name = strrep(muscle_name, ' ', '_');
    fig_filename = sprintf('Comparison_Muscle_%s.png', safe_muscle_name);
    saveas(gcf, fullfile(plot_save_dir, fig_filename));
    fprintf('>> Saved multi-condition plot for %s\n', muscle_name);
    
    hold off;
    close(gcf);
end

fprintf('\n========================================================\n');
fprintf('Pipeline finished! All plots saved in: %s\n', plot_save_dir);