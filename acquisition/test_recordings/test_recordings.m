clc
clear


%% load the .xdf file
filepath = 'D:\Morteza\MyProjects\X1Dnsys_EEG\Pilots\PilotTest2\Sub-P2_2\day1\data\ses-Exo3_aqua\eeg';
filename = 'sub-Pilot2_2_ses-Exo3_aqua_task-Default_run-001_eeg.xdf';
name = fullfile(filepath, filename);

streams = load_xdf(name);



%% find GRF streams
s_names = cellfun(@(x) x.info.name, streams, 'UniformOutput', false);
grf_indx = find(strcmp(s_names, 'GRF'));

GRF_timeseries = streams{grf_indx}.time_series;
GRF_timestamps = streams{grf_indx}.time_stamps;


%% find GRF streams
grf_indx = find(strcmp(s_names, 'GRF_Markers'));

GRF_Markers_timeseries = streams{grf_indx}.time_series;
GRF_Markers_timestamps = streams{grf_indx}.time_stamps;