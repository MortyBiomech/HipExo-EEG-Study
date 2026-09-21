%%
% 1. Select EMG Signals and Calculate the Number of Channels.

emg_indices = [];
for i = 1:length(streams)
    if strcmp(streams{i}.info.type, 'EMG') 
        % Channels correspond to EMG signals
        emg_indices = [emg_indices, i];
    end
end

% Total number of EMG signal channels
total_emg_channels = 0;

for m = 1:length(emg_indices)
    idx = emg_indices(m);
    total_emg_channels = total_emg_channels + size(streams{idx}.time_series, 1);
end

% Obtain the LSL timestamp for gait events. hs = heel strike, to = toe off
t_rhs = HS_R.timestamps;
t_lto = TO_L.timestamps;
t_lhs = HS_L.timestamps;
t_rto = TO_R.timestamps;

% Matching a Complete Gait Cycle: Comprising 5 Key Time Points
valid_cycles_time = [];
for i = 1:length(t_rhs)-1
    start_t = t_rhs(i);
    end_t   = t_rhs(i+1);
    
    curr_lto = t_lto(t_lto > start_t & t_lto < end_t);
    curr_lhs = t_lhs(t_lhs > start_t & t_lhs < end_t);
    curr_rto = t_rto(t_rto > start_t & t_rto < end_t);
    
    if ~isempty(curr_lto) && ~isempty(curr_lhs) && ~isempty(curr_rto)
        %  [RHS_start, LTO, LHS, RTO, RHS_end]
        valid_cycles_time = [valid_cycles_time; start_t, curr_lto(1), curr_lhs(1), curr_rto(1), end_t];
    end
end

% Calculate Median Inter-event Duration (excluding first and last 20 cycles)
fs_emg = streams{emg_indices(1)}.info.effective_srate; % 2148 Hz
durations_time = diff(valid_cycles_time, 1, 2); 
durations_samples = round(durations_time * fs_emg);
num_cycles = size(valid_cycles_time, 1);

% Exclude first 20 and last 20 gait cycles
cycle_start = 21;
cycle_end = num_cycles - 20;

if num_cycles > 40
    % Use only middle cycles
    selected_samples = durations_samples(cycle_start:cycle_end, :);
    median_durs = round(median(selected_samples, 1));
    fprintf('Using cycles %d to %d (total %d cycles) for median calculation.\n', ...
        cycle_start, cycle_end, size(selected_samples,1));
else
    % Not enough cycles, fallback to all cycles
    warning('Only %d cycles available (<40). Using all cycles for median calculation.', num_cycles);
    median_durs = round(median(durations_samples, 1));
end

total_target_length = sum(median_durs);

fprintf('Median lengths (sample sizes) of each sub-stage (RHS-LTO, LTO-LHS, LHS-RTO, RTO-RHS): [%d, %d, %d, %d]\n', ...
    median_durs(1), median_durs(2), median_durs(3), median_durs(4));
fprintf('Total length of the normalized gait cycle: %d sample points\n', total_target_length);

num_cycles = num_cycles - 40;

% Initialize the result matrix.
all_warped_emg = zeros(num_cycles, total_target_length, total_emg_channels);
muscle_names = cell(1, total_emg_channels);

%%
% number of sensors 1 to 19
sensor_numbers = (1:19)';

data_names = {
    'Delays_S3_EMG';   % 1
    'Delays_S4_EMG';   % 2
    'Delays_S1_EMG';   % 3
    'Delays_S5_EMG';   % 4
    'Delays_S6_EMG';   % 5
    'Delays_S0_EMG';   % 6
    'Delays_S7_EMG';   % 7
    'Delays_S8_EMG';   % 8
    'Delays_S9_EMG';   % 9
    'Delays_S10_EMG';  % 10
    'Delays_S11_EMG';  % 11
    'Delays_S12_EMG';  % 12
    'Delays_S13_EMG';  % 13
    'Delays_S14_EMG';  % 14
    'Delays_S15_EMG';  % 15
    'Delays_S2_EMG';   % 16
    'Delays_S16_EMG';  % 17
    'Delays_S17_EMG';  % 18
    'Delays_S18_EMG'   % 19
};

% name of the muscles
muscle_name = cell(19,1);
%  right leg 1-7
muscle_name{1} = 'Tibialis anterior R';
muscle_name{2} = 'Soleus R';
muscle_name{3} = 'Gastrocnemius cap. mediale R';
muscle_name{4} = 'Vastus medialis R';
muscle_name{5} = 'Rectus femoris R';
muscle_name{6} = 'Biceps femoris R';
muscle_name{7} = 'Glutaeus maximus R';
% left leg 8-14 
muscle_name{8} = 'Tibialis anterior L';
muscle_name{9} = 'Soleus L';
muscle_name{10} = 'Gastrocnemius cap. mediale L';
muscle_name{11} = 'Vastus medialis L';
muscle_name{12} = 'Rectus femoris L';
muscle_name{13} = 'Biceps femoris L';
muscle_name{14} = 'Glutaeus maximus L';
% neck 15
muscle_name{15} = 'Trapezius R';
% neck 16 
muscle_name{16} = 'Trapezius L';
% neck 17
muscle_name{17} = 'SCM R';
% neck 18 
muscle_name{18} = 'SCM L';
% face 19
muscle_name{19} = 'Zygomaticus';

% Table
T = table(sensor_numbers, data_names, muscle_name, ...
    'VariableNames', {'Sensor_Number', 'Data_Name', 'Muscle_Name'});

% disp(T);

%%
% 2. EEGLAB Segmented Time-Warping
global_ch_idx = 1; 

% Pre-calculate the target frames for timewarp to avoid redundant calculations in the loop
% Ensuring it starts at 1 and ends at total_target_length
newlatency = [1, ...
              1 + median_durs(1), ...
              1 + sum(median_durs(1:2)), ...
              1 + sum(median_durs(1:3)), ...
              total_target_length];

for m = 1:length(emg_indices)
    idx = emg_indices(m);
    sensor_name = streams{idx}.info.name;  
    num_local_channels = size(streams{idx}.time_series, 1);
    emg_time = streams{idx}.time_stamps;
    
    for ch = 1:num_local_channels
        if num_local_channels > 1
            current_muscle_name = sprintf('%s_Ch%d', sensor_name, ch);
        else
            current_muscle_name = sensor_name;
        end
        muscle_names{global_ch_idx} = current_muscle_name;
        raw_emg = double(streams{idx}.time_series(ch, :)); 
        
        % Preprocessing (Band-pass -> Rectification -> Low-pass)
        [b_bp, a_bp] = butter(4, [20, 400] / (fs_emg/2), 'bandpass');
        emg_filt = filtfilt(b_bp, a_bp, raw_emg);
        emg_rect = abs(emg_filt);
        [b_lp, a_lp] = butter(4, 6 / (fs_emg/2), 'low');
        emg_env = filtfilt(b_lp, a_lp, emg_rect);
        
        % Organize and Warp the Gait Phases using EEGLAB's timewarp
        for c = 1:num_cycles
            t_rhs_start = valid_cycles_time(c, 1);
            t_lto       = valid_cycles_time(c, 2);
            t_lhs       = valid_cycles_time(c, 3);
            t_rto       = valid_cycles_time(c, 4);
            t_rhs_end   = valid_cycles_time(c, 5);
            
            idx_start = find(emg_time >= t_rhs_start, 1, 'first');
            idx_end   = find(emg_time <= t_rhs_end, 1, 'last');
            
            if ~isempty(idx_start) && ~isempty(idx_end) && idx_end > idx_start
                % Extract the raw envelope for the entire cycle (Row Vector)
                raw_cycle_data = emg_env(idx_start:idx_end); 
                
                % Define original event frames (must start at 1)
                evlatency = [1, ...
                             find(emg_time >= t_lto, 1, 'first') - idx_start + 1, ...
                             find(emg_time >= t_lhs, 1, 'first') - idx_start + 1, ...
                             find(emg_time >= t_rto, 1, 'first') - idx_start + 1, ...
                             idx_end - idx_start + 1];
                             
                % Generate the transformation matrix
                warpmat = timewarp(evlatency, newlatency);
                
                % Matrix multiplication: Warp the entire cycle in one shot
                cycle_warped_signal = (warpmat * raw_cycle_data')';
                
                % Store it in the matrix
                if length(cycle_warped_signal) == total_target_length
                    all_warped_emg(c, :, global_ch_idx) = cycle_warped_signal;
                end
            end
        end
        fprintf('Formatting complete: %s\n', current_muscle_name);
        global_ch_idx = global_ch_idx + 1;
    end
end

%%
% 3. Plot the EMG activations per muscle over the gait cycle
gait_percent = linspace(0, 100, total_target_length);
phase_edges_percent = cumsum(median_durs) / total_target_length * 100;
event_labels = {'LTO', 'LHS', 'RTO'};

fprintf('\nStarting to generate the muscle activation map...\n');

sensor2muscle = containers.Map();
for i = 1:height(T)
    sensor2muscle(num2str(T.Sensor_Number(i))) = T.Muscle_Name{i};
end

function [sensor_num_str, ch_suffix] = extract_sensor_info(signal_name)
 
    tokens = regexp(signal_name, 'S(\d+)_EMG(_Ch\d+)?', 'tokens');
    if ~isempty(tokens)
        sensor_num_str = tokens{1}{1};
        if length(tokens{1}) > 1 && ~isempty(tokens{1}{2})
            ch_suffix = tokens{1}{2};
        else
            ch_suffix = '';
        end
    else
        sensor_num_str = '';
        ch_suffix = '';
    end
end

plots_per_figure = 6;
num_figures = ceil(total_emg_channels / plots_per_figure);

for fig = 1:num_figures
    figure('Name', sprintf('EMG Activations - Part %d', fig), 'Color', 'w', 'Position', [100, 100, 1600, 900]);
    
    start_idx = (fig-1)*plots_per_figure + 1;
    end_idx = min(fig*plots_per_figure, total_emg_channels);
    
    plot_pos = 1;
    for m = start_idx:end_idx
        subplot(2, 3, plot_pos);
        hold on;
        
        mean_profile = mean(all_warped_emg(:, :, m), 1);
        std_profile  = std(all_warped_emg(:, :, m), 0, 1);
        
        fill([gait_percent, fliplr(gait_percent)], ...
             [mean_profile + std_profile, fliplr(mean_profile - std_profile)], ...
             [0.8 0.8 1], 'EdgeColor', 'none', 'FaceAlpha', 0.5);
        plot(gait_percent, mean_profile, 'b', 'LineWidth', 2);
        
        for ed = 1:3
            xline(phase_edges_percent(ed), '--r', event_labels{ed}, ...
                'LabelVerticalAlignment', 'top', 'LabelHorizontalAlignment', 'center');
        end
        
        raw_name = muscle_names{m};
        [sensor_num, ch_suffix] = extract_sensor_info(raw_name);
        if isKey(sensor2muscle, sensor_num)
            muscle_title = sensor2muscle(sensor_num);
            if ~isempty(ch_suffix)
                muscle_title = [muscle_title, ch_suffix]; 
            end
        else
            muscle_title = strrep(raw_name, '_', '\_');  
        end
        title(muscle_title);
        
        xlabel('Gait Cycle (%)');
        ylabel('EMG Amplitude (uV)');
        xlim([0 100]);
        grid on;
        
        plot_pos = plot_pos + 1;
    end
end
fprintf('All drawings are complete!\n');