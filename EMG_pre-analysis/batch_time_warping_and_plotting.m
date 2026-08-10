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
all_sessions_data = cell(1, num_sessions);
master_chan_labels = {}; 

%% 3. Main Loop: Annotation, Time-Warping & Plotting
for s = 1:num_sessions
    current_session = session_folders{s};
    fprintf('\n========================================================\n');
    fprintf('Processing Session [%d/%d]: %s...\n', s, num_sessions, current_session);
    
    session_emg_dir = fullfile(subj_in_dir, current_session, 'emg');
    search_pattern = sprintf('*run-%s*_desc-Epoched_emg.set', run_id);
    set_files = dir(fullfile(session_emg_dir, search_pattern));
    
    if isempty(set_files)
        warning('No Epoched .set file found for run-%s in %s. Skipping.', run_id, current_session);
        continue;
    end
    
    filename = set_files(1).name;
    fprintf('  --> Loading file: %s\n', filename);
    EEG = pop_loadset('filename', filename, 'filepath', session_emg_dir);
    
    save_dir = fullfile(bids_root, 'derivatives', output_pipeline, ['sub-', bids_subject_id], current_session, 'emg');
    if ~exist(save_dir, 'dir'), mkdir(save_dir); end
    
    %% Step 3.1: make_timewarp (Latency Check & Event Finding)
    fprintf('>> Running make_timewarp function for event extraction...\n');
    
    % Automatically find 5 key points and mark Latency Outliers
    timewarp_info = make_timewarp(EEG, target_sequence, 'baselineLatency', 0, ...
        'maxSTDForAbsolute', 3, 'maxSTDForRelative', 3);
        
    timewarp_info.warpto = median(timewarp_info.latencies); 

    event_pct = 100 * ...
    (timewarp_info.warpto - timewarp_info.warpto(1)) / ...
    (timewarp_info.warpto(end) - timewarp_info.warpto(1));

    event_table = table( ...
        string(target_sequence(:)), ...
        timewarp_info.warpto(:), ...
        event_pct(:), ...
        'VariableNames', ...
    {'Event', 'MedianLatency_ms', 'GaitCycle_pct'});

    disp(event_table);


    EEG.timewarp = timewarp_info; 
    median_latency = median(timewarp_info.latencies(:,3)); % Warping to the median latency of my 5 events 
    EEG.timewarp.medianlatency = median_latency; 
    
    % Remove bad epochs with missing events or latency > 3SD
    goodepochs = sort([timewarp_info.epochs]); 
    EEG = eeg_checkset(EEG); 
    badepochs_latency = setdiff(1:length(EEG.epoch), goodepochs); 
    EEG.etc.badepochs = badepochs_latency; 
    
    fprintf('   - make_timewarp identified %d bad epochs (missing events or latency > 3SD).\n', length(badepochs_latency));
    
    % Safely remove bad epochs
    if ~isempty(badepochs_latency)
        EEG = pop_select(EEG, 'notrial', badepochs_latency);
    end
    
    if EEG.trials < 2
        warning('Not enough clean cycles. Skipping session.');
        continue;
    end
    
    %% Step 3.2: Best Practice Amplitude Outlier Rejection (Intra-cycle Peak) 
    fprintf('>> Performing Amplitude Outlier Rejection (Intra-cycle Peak > 3SD)...\n');
    isoutlier_amp = false(1, EEG.trials);
    
    % Get the millisecond time points calculated by make_timewarp and convert them to frames within the current EEG
    clean_timewarp_latencies = EEG.timewarp.latencies; 
    timevals_frames_clean = round((clean_timewarp_latencies - EEG.times(1)) / (1000/EEG.srate)) + 1;
    
    % For each Epoch, calculate the peak only within its start and end key points (from the 1st RHS to the 5th RHS)
    intra_cycle_peaks = zeros(EEG.nbchan, EEG.trials);
    for e = 1:EEG.trials
        start_frame = timevals_frames_clean(e, 1); % 1st RHS
        end_frame   = timevals_frames_clean(e, 5); % 5th RHS (Next RHS)
        
        % Extract the pure data segment strictly belonging to the current gait cycle [channels x pure time segment]
        pure_epoch_data = EEG.data(:, start_frame:end_frame, e);
        
        % Find the maximum peak ONLY within this pure interval, completely isolating interference from neighboring cycles
        intra_cycle_peaks(:, e) = max(pure_epoch_data, [], 2);
    end
    
    for ch = 1:EEG.nbchan
        mean_peak = mean(intra_cycle_peaks(ch, :));
        std_peak  = std(intra_cycle_peaks(ch, :));
        upper_bound = mean_peak + 3 * std_peak; % Threshold = μpeak​ + 3 * σpeak​
        
        isoutlier_amp(intra_cycle_peaks(ch, :) > upper_bound) = true;
    end
    fprintf('   - Total %d epochs marked as amplitude outliers (Intra-cycle).\n', sum(isoutlier_amp));
    
    % Write the amplitude outlier flags into the structure
    for e = 1:EEG.trials
        EEG.epoch(e).isoutlier_amp = isoutlier_amp(e);
    end
    EEG.etc.badepochs_amplitude = find(isoutlier_amp);
    
    % Remove epochs with amplitude outliers and update the timewarp matrix synchronously!
    if any(isoutlier_amp)
        EEG = pop_select(EEG, 'notrial', find(isoutlier_amp));
        EEG.timewarp.latencies = EEG.timewarp.latencies(~isoutlier_amp, :);
        EEG.timewarp.epochs = EEG.timewarp.epochs(~isoutlier_amp);
    end
    
    if EEG.trials < 2
        warning('Not enough clean cycles. Skipping session.');
        continue;
    end
    
    %% Step 3.3: Physical Data Matrix Time-Warping 
    % Conversion from ms to frames, because the time extracted by make_timewarp is in milliseconds (ms).
    clean_timewarp_latencies = EEG.timewarp.latencies; 
    % frame = (time(ms) - start_time) / (ms_per_sample_point) + 1
    timevals_frames_clean = round((clean_timewarp_latencies - EEG.times(1)) / (1000/EEG.srate)) + 1; % Epoch * events
   
    warpvals_frames = round((EEG.timewarp.warpto - EEG.times(1)) / (1000/EEG.srate)) + 1;
    % warpto(1) -> frame 1
    warpvals_frames = warpvals_frames - warpvals_frames(1) + 1; 
    % Up to the final target sampling point.
    target_length = max(warpvals_frames);
    
    warped_data = zeros(EEG.nbchan, target_length, EEG.trials); % channels * time * gait cycles
    
    fprintf('>> Applying physical matrix timewarp on %d completely clean epochs...\n', EEG.trials);
    for e = 1:EEG.trials
        ev_in = timevals_frames_clean(e, :); % e row and all columns, e epoch and all events
        % timewarp() only warps the interval between the first event and the last event.
        start_frame = ev_in(1);
        end_frame   = ev_in(end);

        epoch_raw   = EEG.data(:, start_frame:end_frame, e); % 22 channels * 1 gait cycle * e epoch
        
        % Renumber events
        ev_in = ev_in - ev_in(1) + 1; % Events alignment

        warpmat = timewarp(ev_in, warpvals_frames); % Construct a mapping matrix from the actual timeline to the target timeline.
        warped_data(:, :, e) = epoch_raw * warpmat'; % Xwarped​=Xraw​WT（matrix multiplication），X_raw = raw gait cycle data， W = time-warp interpolation / mapping matrix， X_warped = time-normalized data
    end
    
    %% Step 3.4: Update and Save Timewarped Dataset
    EEG.data = warped_data;
    EEG.times = linspace(0, 100, target_length); 
    EEG.pnts = target_length;
    EEG.event = []; 
    
    EEG = eeg_checkset(EEG);
    save_filename_warped = strrep(filename, '_desc-Epoched_emg.set', '_desc-Timewarped_emg.set');
    EEG = pop_saveset(EEG, 'filename', save_filename_warped, 'filepath', save_dir);
    fprintf('>> [SAVE] Saved completely clean Time-Warped dataset to: %s\n', save_filename_warped);
    
    %% Step 3.5: Cache Data for Plotting
    all_sessions_data{s}.session_name = current_session;
    all_sessions_data{s}.labels = {EEG.chanlocs.labels};
    all_sessions_data{s}.mean_data = mean(warped_data, 3, 'omitnan');
    all_sessions_data{s}.std_data = std(warped_data, 0, 3, 'omitnan');
    all_sessions_data{s}.times = EEG.times; 
    all_sessions_data{s}.valid = true;
    
    master_chan_labels = unique([master_chan_labels, all_sessions_data{s}.labels], 'stable');
end

%% 4. Multi-Condition Plotting (Custom Ordered & Styled)
fprintf('\n========================================================\n');
fprintf('Generating Multi-Condition Comparison Plots (Custom Styles)...\n');

num_master_channels = length(master_chan_labels);

% Core configuration: Define strict plotting order, keyword matching, RGB colors, and line styles
% RGB values range from [0~1], carefully adjusted for contrast based on your requirements
cond_order = {
    'NoExoPre',    [0.0, 0.0, 0.0],   '-';   % Black, Solid
    'NoExoPost',   [0.0, 0.0, 0.0],   '--';  % Black, Dashed
    'aquaplus',    [0.6, 0.0, 0.0],   '-';   % Dark Red, Solid
    'aqua',        [1.0, 0.4, 0.4],   '-';   % Light Red, Solid
    'transparent', [0.1, 0.7, 0.1],   '-';   % Green, Solid
    'eco',         [0.6, 0.8, 1.0],   '-';   % Very Light Blue, Solid
    'sport',       [0.0, 0.4, 0.8],   '-';   % Medium Blue, Solid
    'boost',       [0.0, 0.0, 0.6],   '-'    % Dark Blue, Solid
};

for ch = 1:num_master_channels
    muscle_name = master_chan_labels{ch};
    
    % Widen the figure to accommodate the longer legend on the right
    figure('Name', sprintf('Muscle Activation: %s', muscle_name), 'Position', [100, 100, 1000, 600], 'Visible', 'off');
    hold on;
    
    legend_handles = [];
    legend_labels = {};
    
    % Loop through and plot strictly according to the 8 orders defined in cond_order
    for c = 1:size(cond_order, 1)
        target_key = cond_order{c, 1};
        color_val  = cond_order{c, 2};
        line_style = cond_order{c, 3};
        
        % Search for folders containing the current keyword across all processed sessions
        matched_s = 0;
        for s = 1:num_sessions
            if isempty(all_sessions_data{s}) || ~all_sessions_data{s}.valid
                continue;
            end
            
            % Use endsWith matching, ignoring case (e.g., matching 'ses-Exo1eco')
            if endsWith(all_sessions_data{s}.session_name, target_key, 'IgnoreCase', true)
                matched_s = s;
                break;
            end
        end
        
        % If the current subject is missing data for a certain condition, skip it directly without breaking the legend structure
        if matched_s == 0
            continue; 
        end
        
        % Check if the session contains the current muscle channel
        ch_idx = find(strcmp(all_sessions_data{matched_s}.labels, muscle_name));
        if isempty(ch_idx)
            continue;
        end
        
        x_axis = all_sessions_data{matched_s}.times;
        mean_profile = all_sessions_data{matched_s}.mean_data(ch_idx, :);
        std_profile = all_sessions_data{matched_s}.std_data(ch_idx, :);
        
        % Plot the ± STD semi-transparent shaded band (FaceAlpha set to 0.1 to prevent the 8 colors from blocking each other)
        fill_x = [x_axis, fliplr(x_axis)];
        fill_y = [mean_profile + std_profile, fliplr(max(0, mean_profile - std_profile))];
        patch(fill_x, fill_y, color_val, 'EdgeColor', 'none', 'FaceAlpha', 0.1);
        
        % Plot the mean line for the current condition (applying the configured color and line style)
        h_line = plot(x_axis, mean_profile, 'Color', color_val, 'LineStyle', line_style, 'LineWidth', 2.5);
        
        legend_handles(end+1) = h_line;
        legend_labels{end+1} = all_sessions_data{matched_s}.session_name; 
    end
    
    % Figure decoration and layout
    xlim([0 100]);
    xlabel('Gait Cycle (%)', 'FontSize', 12, 'FontWeight', 'bold');
    ylabel('EMG Amplitude (\muV)', 'FontSize', 12, 'FontWeight', 'bold');
    title(sprintf('Multi-Condition Comparison: %s', strrep(muscle_name, '_', '\_')), 'FontSize', 14, 'FontWeight', 'bold');
    
    % Generate the legend outside on the right side of the figure, sorted by the set order
    if ~isempty(legend_handles)
        legend(legend_handles, legend_labels, 'Location', 'northeastoutside', 'Interpreter', 'none', 'FontSize', 10);
    end
    grid on; box on;
    
    safe_muscle_name = strrep(muscle_name, ' ', '_');
    fig_filename = sprintf('sub-%s_run-%s_desc-Comparison_Muscle-%s.png', bids_subject_id, run_id, safe_muscle_name);
    saveas(gcf, fullfile(plot_save_dir, fig_filename));
    fprintf('>> Saved styled multi-condition plot for %s\n', muscle_name);
    
    hold off;
    close(gcf);
end

fprintf('\n========================================================\n');
fprintf('Pipeline finished! All plots saved in: %s\n', plot_save_dir);