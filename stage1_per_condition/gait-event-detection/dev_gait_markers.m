clc
clear

%% Change these paths with respect to your system
addpath(genpath('D:\Morteza\MyProjects\X1Dnsys_EEG'))
addpath(genpath('D:\Morteza\LSL\xdf-Matlab-master'))

addpath('D:\Morteza\Toolboxes\Fieldtrip\fieldtrip-20231127')
addpath('D:\Morteza\Toolboxes\Fieldtrip\fieldtrip-20231127\fileio')

data_path = 'D:\Morteza\MyProjects\X1Dnsys_EEG\Pilots\PilotTest2\Sub-P2_1\day2\sub-Pilot2_1_day2\';


%% sub-Pilot2_1_day2 order of sessions
order_sessions = {'NoExoPre', 'Exo1_sport', 'Exo2_aquaplus', 'ExoOff', ...
    'Exo3_eco', 'Exo4_aqua', 'Exo5_boost', 'NoExoPost'};


%% load .xdf files
cd(data_path)

subject     = 'Pilot2_1_day2';
filename    = ['sub-', subject, '_ses-', order_sessions{1}, ...
               '_task-Default', '_run-001_eeg.xdf'];
filepath   = [data_path, 'ses-', order_sessions{1}, '\eeg\'];

[streams, ~]  = load_xdf(fullfile(filepath, filename));
grf_idx       = find(strcmp(cellfun(@(s) s.info.name, streams, ...
                    'UniformOutput', false), 'GRF'));
GRF           = streams{grf_idx};

Left_leg_indx = [2 3 6 7];     % Right leg channels
Right_leg_indx = [1 4 5 8];    % Left leg channels


% --- Plot a few seconds of the GRF stream --------------------------------
figure('Name', 'GRF right and left leg'); hold on;

GRF_Right = sum(GRF.time_series(Right_leg_indx, :), 1);
GRF_Left = sum(GRF.time_series(Left_leg_indx, :), 1);

plot(GRF.time_stamps, GRF_Right, 'Color', 'b', 'LineWidth', 2);
plot(GRF.time_stamps, GRF_Left, 'Color', 'r', 'LineWidth', 2);
legend({'Right Leg', 'Left Leg'})

% --- check the sampling rate of the GRF stream ---------------------------
% check_sampling_regularity(GRF_time, 'GRF')


[best_on, best_off]      = optimize_thresholds(GRF, Right_leg_indx, Left_leg_indx);
[HS_R, TO_R, HS_L, TO_L] = detect_gait_events(GRF, Right_leg_indx, Left_leg_indx, ...
                            'ThresholdOn',  best_on, ...
                            'ThresholdOff', best_off);
% sanity check for gait event detection
plot_gait_histograms(HS_R, TO_R, HS_L, TO_L);