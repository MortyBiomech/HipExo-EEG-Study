

%% Change these paths with respect to your system
addpath(genpath('D:\Morteza\MyProjects\X1Dnsys_EEG'))
addpath(genpath('D:\Morteza\LSL\xdf-Matlab-master'))

addpath('D:\Morteza\Toolboxes\Fieldtrip\fieldtrip-20231127')
addpath('D:\Morteza\Toolboxes\Fieldtrip\fieldtrip-20231127\fileio')

EEGLAB_path = 'D:\Morteza\Toolboxes\EEGLAB\eeglab2026.0.0';
data_path = 'D:\Morteza\MyProjects\X1Dnsys_EEG\Pilots\PilotTest2\Sub-P2_1\day2\sub-Pilot2_1_day2\';


%% sub-Pilot2_1_day2 order of sessions and data info
order_sessions = {'NoExoPre', 'Exo1_sport', 'Exo2_aquaplus', 'ExoOff', ...
    'Exo3_eco', 'Exo4_aqua', 'Exo5_boost', 'NoExoPost'};

subject     = 'Pilot2_1_day2';
filename    = ['sub-', subject, '_ses-', order_sessions{1}, ...
               '_task-Default', '_run-001_eeg.xdf'];
filepath   = [data_path, 'ses-', order_sessions{1}, '\eeg\'];


%% Add events to the EEG structure

% load EEGLAB first
this_path = pwd; 
cd(EEGLAB_path)
if ~exist('ALLCOM','var')
	eeglab;
end
cd(this_path)

% read the xdf file and store the EEG stream
EEG = pop_loadxdf(fullfile(filepath, filename), 'streamtype', 'EEG');

% Load raw streams to get exact EEG timestamps
streams = load_xdf(fullfile(filepath, filename));

% Find EEG stream
eeg_stream_idx = find(cellfun(@(s) strcmp(s.info.type, 'EEG'), streams));
eeg_timestamps = streams{eeg_stream_idx}.time_stamps;   % exact per-sample LSL timestamps

% Now convert GRF events to EEG sample indices
timestamp_to_sample = @(t) find(abs(eeg_timestamps - t) == min(abs(eeg_timestamps - t)), 1);

% Define event types and their timestamps
event_types      = {'RHS',          'RTO',          'LHS',          'LTO'         };
event_timestamps = {HS_R.timestamps, TO_R.timestamps, HS_L.timestamps, TO_L.timestamps};

n_existing = length(EEG.event);
counter    = 0;

for e = 1:4
    type   = event_types{e};
    tstamps = event_timestamps{e};
    for k = 1:numel(tstamps)
        samp = timestamp_to_sample(tstamps(k));

        % Skip if outside EEG range
        if isempty(samp) || samp < 1 || samp > EEG.pnts
            warning('Event %s at t=%.4f outside EEG range, skipping.', type, tstamps(k));
            continue;
        end

        counter = counter + 1;
        EEG.event(n_existing + counter).type     = type;
        EEG.event(n_existing + counter).latency  = samp;
        EEG.event(n_existing + counter).duration = 1;
    end
end

% Sort and check consistency
EEG = eeg_checkset(EEG, 'eventconsistency');

fprintf('\nGait events added to EEG:\n');
fprintf('  RHS : %d\n', numel(HS_R.timestamps));
fprintf('  RTO : %d\n', numel(TO_R.timestamps));
fprintf('  LHS : %d\n', numel(HS_L.timestamps));
fprintf('  LTO : %d\n', numel(TO_L.timestamps));







%%
% Recover EEG start in LSL clock
eeg_t0 = str2double(EEG.etc.info.first_timestamp);

% Convert GRF event LSL timestamps to EEG sample indices
% EEG.srate is the effective rate (499.9006 Hz)
timestamp_to_sample = @(t) round((t - eeg_t0) * EEG.srate) + 1;

% Build EEG events from gait events
event_data = [
    {'RHS', HS_R.timestamps};
    {'RTO', TO_R.timestamps};
    {'LHS', HS_L.timestamps};
    {'LTO', TO_L.timestamps};
];

n_existing = length(EEG.event);
counter    = 0;

for row = 1:size(event_data, 1)
    type       = event_data{row, 1};
    timestamps = event_data{row, 2};
    for k = 1:numel(timestamps)
        samp = timestamp_to_sample(timestamps(k));
        if samp < 1 || samp > EEG.pnts
            warning('Event %s at t=%.4f is outside EEG range, skipping.', type, timestamps(k));
            continue;
        end
        counter = counter + 1;
        EEG.event(n_existing + counter).type    = type;
        EEG.event(n_existing + counter).latency = samp;
    end
end

% Sort events by latency and check consistency
EEG = eeg_checkset(EEG, 'eventconsistency');

fprintf('\nGait events added to EEG:\n');
fprintf('  RHS : %d\n', numel(HS_R.timestamps));
fprintf('  RTO : %d\n', numel(TO_R.timestamps));
fprintf('  LHS : %d\n', numel(HS_L.timestamps));
fprintf('  LTO : %d\n', numel(TO_L.timestamps));