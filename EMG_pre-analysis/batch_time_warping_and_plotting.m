% addpath('C:\Program Files\MATLAB\R2025a\toolbox\eeglab2023.1\plugins\xdfimport1.2');
% 
% eeglab nogui;
% 
% cd("C:\2026SSArbeit\Data831\trial831newGRF")
% streams= load_xdf('sub-P001_ses-S001_task-Default_run-001_trial831newGRF.xdf');

% cd("C:\2026SSArbeit\data\PilotTest2\Sub-P2_3\day2\data\ses-Exo3_sport\eeg")
% streams_2= load_xdf('sub-Pilot2_3_day2_ses-Exo3_sport_task-Default_run-001_eeg.xdf');
%streams = load_xdf('sub-Pilot2_3_day2_ses-Exo1_eco_task-Default_run-001_eeg.xdf', 'streamtype', 'EMG');

% %%
%  for k = 1:length(streams)
%     info = streams{k}.info;
%     name = string(info.name);
%     type = string(info.type);
%     srate = str2double(info.nominal_srate);
%     nchan = str2double(info.channel_count);
% 
%     fprintf('#%d  name=%s | type=%s | srate=%g | nchan=%d\n', k, name, type, srate, nchan);
%  end
% %%

%% GRF-guided EMG gait-cycle pipeline for the 6-sensor test recording
% Requires: load_xdf (xdfimport / EEGLAB plugin) and Signal Processing Toolbox.
% Output: gait_events.mat, time-warped EMG results (.mat), and PNG/PDF figures.
% The script intentionally works directly from the XDF; BIDS/BDF and EEGLAB are
% not required here.

clear; clc;

%% ---------------- USER SETTINGS: edit this section only ----------------
xdfFile = 'C:\\2026SSArbeit\\Data831\\trial831newGRF\\sub-P001_ses-S001_task-Default_run-001_trial831newGRF.xdf';
outDir  = fileparts(xdfFile);
addpath('C:\2026SSArbeit\HipExo-EEG-Study\EMG_pre-analysis');
addpath('C:\2026SSArbeit\HipExo-EEG-Study\stage1_per_condition\gait-event-detection');

% Existing GRF layout retained from get_4_gait_events.m.  Confirm it once by
% checking the validation figure.  Indices refer to the 9 channels in GRF.
grfRightChannels = [1 4 5 8];
grfLeftChannels  = [2 3 6 7];

% [] = analyze the whole recording.  Set [start end] in LSL seconds to exclude
% standing / setup periods, e.g. [577872.5 578115.2].
analysisWindowLSL = [];

% The IDs are read from the EMG stream metadata (serial_number_dec).  Fill the
% six values below after the first run prints the metadata table.  Until then,
% the script uses the listed stream-column fallback, so it still runs, but you
% MUST verify its left/right assignment before interpreting the figure.
sensorMap = table( ...
    ["88545"; "88592"; "88667"; "88519"; "88658"; "88659"], ...       % serial_number_dec / unique ID
    [1; 2; 3; 4; 5; 6], ...                  % temporary fallback column
    ["GastMed_R"; "Soleus_R"; "TibAnt_R"; ...
     "GastMed_L"; "Soleus_L"; "TibAnt_L"], ...
    'VariableNames', {'SensorID','FallbackColumn','Muscle'});

% Processing settings.  The actual rate is read from timestamps (about 1259 Hz
% in this test), not assumed to be 2148 Hz.
bandpassHz       = [20 450];
envelopeLowpassHz = 8;
normaliseToPercent = true;   % each muscle scaled to its valid-cycle maximum
showValidationFigures = true;
%% ------------------------------------------------------------------------

assert(exist(xdfFile, 'file') == 2, 'XDF file not found: %s', xdfFile);
assert(exist('load_xdf', 'file') == 2, ...
    'load_xdf is not on the MATLAB path. Start EEGLAB/xdfimport first.');
assert(exist('optimize_thresholds_V1', 'file') == 2 && exist('detect_gait_events', 'file') == 2, ...
    ['optimize_thresholds_V1.m and detect_gait_events.m must be on the MATLAB path. ' ...
     'Put them in the same folder as this script or run addpath first.']);
if ~exist(outDir, 'dir'), mkdir(outDir); end

[~, baseName] = fileparts(xdfFile);
fprintf('Loading XDF: %s\n', xdfFile);
[streams, ~] = load_xdf(xdfFile);

streamNames = cellfun(@(s) char(s.info.name), streams, 'UniformOutput', false);
streamTypes = cellfun(@(s) char(s.info.type), streams, 'UniformOutput', false);
grfIndex = find(strcmpi(streamNames, 'GRF') | strcmpi(streamTypes, 'Force'), 1);
emgIndex = find(strcmpi(streamNames, 'Delsys_EMG') | strcmpi(streamTypes, 'EMG'), 1);
assert(~isempty(grfIndex), 'No GRF / Force stream was found.');
assert(~isempty(emgIndex), 'No Delsys_EMG / EMG stream was found.');
GRF = streams{grfIndex}; EMG = streams{emgIndex};

% load_xdf usually stores data as channels x samples; correct the orientation
% defensively in case a recorder exported samples x channels.
grfData = double(GRF.time_series);
grfT = double(GRF.time_stamps(:)');
if size(grfData,2) ~= numel(grfT)
    grfData = grfData.';
end
emgData = double(EMG.time_series);
emgT = double(EMG.time_stamps(:)');
if size(emgData,2) ~= numel(emgT), emgData = emgData.'; end
assert(size(emgData,1) == 6, 'Expected 6 EMG channels, found %d.', size(emgData,1));
assert(size(grfData,1) >= max([grfRightChannels grfLeftChannels]), 'GRF channel indices exceed available channels.');

% Read metadata and bind every desired muscle to an actual EMG data column.
emgMeta = getEmgMetadata(EMG, size(emgData,1));
disp('EMG metadata found in this XDF:'); disp(emgMeta);
sensorMap.Column = zeros(height(sensorMap),1);
for k = 1:height(sensorMap)
    id = string(sensorMap.SensorID(k));
    hit = [];
    if strlength(id) > 0
        hit = find(emgMeta.SensorID == id, 1);
    end
    if isempty(hit)
        hit = sensorMap.FallbackColumn(k);
        warning('Using fallback EMG column %d for %s. Replace SensorID in sensorMap after checking the printed table.', hit, sensorMap.Muscle(k));
    end
    sensorMap.Column(k) = hit;
end
assert(numel(unique(sensorMap.Column)) == 6 && all(sensorMap.Column >= 1 & sensorMap.Column <= 6), ...
    'Each of the six muscles must map to one distinct EMG column (1..6).');

%% 1. Detect HS / TO from GRF with the established project functions
% This deliberately mirrors get_4_gait_events.m so event definitions match
% those used in your previous analysis.
if isempty(analysisWindowLSL)
    use = true(size(grfT));
else
    use = grfT >= analysisWindowLSL(1) & grfT <= analysisWindowLSL(2);
end
assert(nnz(use) > 20, 'The selected GRF analysis window contains too few samples.');
GRF_cropped = GRF;
GRF_cropped.time_stamps = GRF.time_stamps(use);
GRF_cropped.time_series = grfData(:,use);

fprintf('Optimising GRF thresholds in the selected walking window...\n');
[best_on, best_off] = optimize_thresholds_V1(GRF_cropped, grfRightChannels, grfLeftChannels);
[HS_R, TO_R, HS_L, TO_L] = detect_gait_events(GRF_cropped, grfRightChannels, grfLeftChannels, ...
    'ThresholdOn', best_on, 'ThresholdOff', best_off, ...
    'Plot', showValidationFigures, 'Verbose', true);
all_events = makeAllEvents(HS_R, TO_R, HS_L, TO_L, grfT(find(use,1)), grfT(find(use,1,'last')));
eventFile = fullfile(outDir, baseName + "_gait_events.mat");
save(eventFile, 'all_events', 'HS_R', 'TO_R', 'HS_L', 'TO_L', 'grfRightChannels', 'grfLeftChannels', 'best_on', 'best_off');
fprintf('Saved %d gait events: %s\n', numel(all_events), eventFile);

%% 2. Build continuous EEGLAB EMG dataset and inject GRF events
eeglab nogui;

fsEMG = 1 / median(diff(emgT));

EEG = eeg_emptyset;
EEG.data   = emgData;
EEG.nbchan = size(emgData,1);
EEG.pnts   = size(emgData,2);
EEG.trials = 1;
EEG.srate  = fsEMG;
EEG.xmin   = 0;
EEG.xmax   = (EEG.pnts - 1) / EEG.srate;
EEG.times  = (0:EEG.pnts-1) / EEG.srate * 1000;
EEG.setname = [baseName '_continuous_EMG'];
EEG.subject = 'P001';

for ch = 1:EEG.nbchan
    EEG.chanlocs(ch).labels = char(sensorMap.Muscle(ch));
end

% all_events uses LSL timestamps; retain only events covered by EMG.
emgStart = emgT(1);
emgEnd   = emgT(end);

EEG.event = [];
eventCount = 0;

for k = 1:numel(all_events)
    eventTime = all_events(k).time;

    if eventTime < emgStart || eventTime > emgEnd
        continue;
    end

    eventCount = eventCount + 1;
    EEG.event(eventCount).type = all_events(k).type;
    EEG.event(eventCount).latency = (eventTime - emgStart) * EEG.srate + 1;
    EEG.event(eventCount).urevent = eventCount;
end

EEG = eeg_checkset(EEG, 'eventconsistency');

%% Remove unwanted boundary events
EEG = pop_selectevent(EEG, ...
    'type', {'HS_R', 'TO_L', 'HS_L', 'TO_R'}, ...
    'deleteevents', 'on');

EEG = eeg_checkset(EEG, 'eventconsistency');

%% 3. EMG preprocessing
EEG = pop_eegfiltnew(EEG, 'locutoff', 20, 'hicutoff', 450);

EEG.data = abs(EEG.data);              % full-wave rectification
EEG = pop_eegfiltnew(EEG, 'hicutoff', 8); % linear envelope
EEG.data(EEG.data < 0) = 0;

EEG.etc.is_envelope = true;
EEG = eeg_checkset(EEG);

%% 4. Dynamic epoching around HS_R
targetEvent = 'HS_R';

eventTypes = string({EEG.event.type});
rhsLatency = [EEG.event(strcmp(eventTypes, targetEvent)).latency];

assert(numel(rhsLatency) >= 2, ...
    'Less than two HS_R events remain inside the EMG recording.');

rhsIntervals = diff(rhsLatency) / EEG.srate;
maxRhsToNextRhs = max(rhsIntervals);

epochWindow = [-0.6, maxRhsToNextRhs + 0.6];

fprintf('Epoch window: [%.3f, %.3f] s\n', ...
    epochWindow(1), epochWindow(2));

EEG = pop_epoch(EEG, {targetEvent}, epochWindow, ...
    'newname', 'HS_R epochs', ...
    'epochinfo', 'yes');

EEG = eeg_checkset(EEG);
EEG.setname = [EEG.subject '_Epoched_EMG'];
EEG = eeg_checkset(EEG);

%% Step 3.1: make_timewarp (Latency Check & Event Finding)
targetSequence = {'HS_R', 'TO_L', 'HS_L', 'TO_R', 'HS_R'};

fprintf('>> Running make_timewarp function for event extraction...\n');
timewarpInfo = make_timewarp(EEG, targetSequence, ...
    'baselineLatency', 0, ...
    'maxSTDForAbsolute', 3, ...
    'maxSTDForRelative', 3);

timewarpInfo.warpto = median(timewarpInfo.latencies);

eventPct = 100 * ...
    (timewarpInfo.warpto - timewarpInfo.warpto(1)) / ...
    (timewarpInfo.warpto(end) - timewarpInfo.warpto(1));

eventNames = targetSequence;
eventTable = table(string(targetSequence(:)), ...
    timewarpInfo.warpto(:), eventPct(:), ...
    'VariableNames', {'Event','MedianLatency_ms','GaitCycle_pct'});
disp(eventTable);

EEG.timewarp = timewarpInfo;
EEG.timewarp.medianlatency = median(timewarpInfo.latencies(:,3));

% Remove epochs with a missing event or latency beyond 3 SD.
goodEpochs = sort([timewarpInfo.epochs]);

EEG = eeg_checkset(EEG);
badEpochsLatency = setdiff(1:length(EEG.epoch), goodEpochs);

EEG.etc.badepochs = badEpochsLatency;

fprintf('   - make_timewarp identified %d bad epochs ', ...
    numel(badEpochsLatency));
fprintf('(missing events or latency > 3 SD).\n');

if ~isempty(badEpochsLatency)
    EEG = pop_select(EEG, 'notrial', badEpochsLatency);
end

EEG = eeg_checkset(EEG);

if EEG.trials < 2
    error('Fewer than two epochs remain after temporal-outlier rejection.');
end

fprintf('Time-warping: %d valid epochs retained; %d rejected.\n', ...
    EEG.trials, numel(badEpochsLatency));

%% Step 3.2: Amplitude Outlier Rejection (Intra-cycle Peak > 3 SD)
fprintf('>> Performing Amplitude Outlier Rejection ');
fprintf('(Intra-cycle Peak > 3 SD)...\n');

% At this point timewarpInfo.latencies contains only the epochs accepted by
% make_timewarp, in the same order as the retained EEG epochs.
cleanLatencies = timewarpInfo.latencies;

assert(size(cleanLatencies,1) == EEG.trials, ...
    ['Mismatch after temporal rejection: EEG contains %d epochs, but ' ...
     'timewarpInfo.latencies contains %d rows.'], ...
    EEG.trials, size(cleanLatencies,1));

timevalsFrames = round((cleanLatencies - EEG.times(1)) ./ ...
    (1000/EEG.srate)) + 1;

intraCyclePeaks = zeros(EEG.nbchan, EEG.trials);

for e = 1:EEG.trials
    startFrame = timevalsFrames(e,1); % first HS_R
    endFrame   = timevalsFrames(e,5); % next HS_R

    assert(startFrame >= 1 && endFrame <= EEG.pnts && endFrame > startFrame, ...
        'Invalid first/last HS_R frames in epoch %d.', e);

    pureCycleData = EEG.data(:,startFrame:endFrame,e);
    intraCyclePeaks(:,e) = max(pureCycleData,[],2);
end

isAmplitudeOutlier = false(1,EEG.trials);
amplitudeThresholds = zeros(EEG.nbchan,1);
amplitudeOutlierByChannel = false(EEG.nbchan,EEG.trials);

for ch = 1:EEG.nbchan
    meanPeak = mean(intraCyclePeaks(ch,:));
    stdPeak  = std(intraCyclePeaks(ch,:));
    amplitudeThresholds(ch) = meanPeak + 3*stdPeak;

    amplitudeOutlierByChannel(ch,:) = ...
        intraCyclePeaks(ch,:) > amplitudeThresholds(ch);
    isAmplitudeOutlier = isAmplitudeOutlier | ...
        amplitudeOutlierByChannel(ch,:);

    fprintf('   - %-12s threshold = %.4f; flagged cycles = %d\n', ...
        EEG.chanlocs(ch).labels, amplitudeThresholds(ch), ...
        sum(amplitudeOutlierByChannel(ch,:)));
end

badEpochsAmplitude = find(isAmplitudeOutlier);
fprintf('   - Total %d epochs marked as amplitude outliers.\n', ...
    numel(badEpochsAmplitude));

% Annotate the pre-rejection epochs, as in the reference script.
for e = 1:EEG.trials
    EEG.epoch(e).isoutlier_amp = isAmplitudeOutlier(e);
end
EEG.etc.badepochs_amplitude = badEpochsAmplitude;

% Remove amplitude outliers and synchronously update all time-warp rows.
if any(isAmplitudeOutlier)
    EEG = pop_select(EEG, 'notrial', badEpochsAmplitude);
    timewarpInfo.latencies = ...
        timewarpInfo.latencies(~isAmplitudeOutlier,:);

    if isfield(timewarpInfo,'epochs') && ...
            numel(timewarpInfo.epochs) == numel(isAmplitudeOutlier)
        timewarpInfo.epochs = ...
            timewarpInfo.epochs(~isAmplitudeOutlier);
    end
end

if EEG.trials < 2
    error('Fewer than two epochs remain after amplitude-outlier rejection.');
end

EEG.timewarp = timewarpInfo;
EEG.timewarp.medianlatency = median(timewarpInfo.latencies(:,3));
EEG = eeg_checkset(EEG);

fprintf('   - %d completely clean epochs remain.\n', EEG.trials);

%% Step 3.3: Physical five-event time-warp: first HS_R -> last HS_R
% make_timewarp only calculates event latencies and target latencies. It does
% not automatically modify EEG.data. The following block performs the actual
% data transformation used in batch_time_warping_and_plotting.m.
cleanLatencies = timewarpInfo.latencies;  % good epochs x 5 events, milliseconds

assert(size(cleanLatencies,1) == EEG.trials, ...
    ['Mismatch between retained EEG epochs and timewarp latency rows. ' ...
     'Expected %d rows, found %d.'], EEG.trials, size(cleanLatencies,1));

timevalsFrames = round((cleanLatencies - EEG.times(1)) ./ (1000/EEG.srate)) + 1;
warpvalsFrames = round((timewarpInfo.warpto - EEG.times(1)) ./ (1000/EEG.srate)) + 1;

% Make the first HS_R target frame equal to 1. The last target HS_R defines
% the length of exactly one complete gait cycle.
warpvalsFrames = warpvalsFrames - warpvalsFrames(1) + 1;
targetLength = warpvalsFrames(end);

assert(all(diff(warpvalsFrames) > 0), ...
    'Median target gait-event order is not strictly increasing.');

warpedData = nan(EEG.nbchan, targetLength, EEG.trials, 'like', EEG.data);

for e = 1:EEG.trials
    evIn = timevalsFrames(e,:);
    startFrame = evIn(1);
    endFrame   = evIn(end);

    assert(startFrame >= 1 && endFrame <= EEG.pnts && endFrame > startFrame, ...
        'Invalid time-warp frames in retained epoch %d.', e);
    assert(all(diff(evIn) > 0), ...
        'Gait events are not strictly ordered in retained epoch %d.', e);

    epochRaw = EEG.data(:, startFrame:endFrame, e);
    evIn = evIn - startFrame + 1;

    warpMatrix = timewarp(evIn, warpvalsFrames);
    warpedData(:,:,e) = epochRaw * warpMatrix';
end

% Replace the long [-0.6, max+0.6] epoch by the physical HS_R-to-HS_R data.
EEG.data   = warpedData;
EEG.pnts   = targetLength;
EEG.times  = linspace(0,100,targetLength);
EEG.xmin   = 0;
EEG.xmax   = 1;
EEG.event  = [];
EEG.epoch  = [];
EEG.setname = [EEG.subject '_FiveEvent_Timewarped_EMG'];
EEG = eeg_checkset(EEG);

fprintf('Physical time-warp complete: %d channels x %d points x %d cycles.\n', ...
    size(warpedData,1), size(warpedData,2), size(warpedData,3));
disp(table(string(eventNames(:)), timewarpInfo.warpto(:), eventPct(:), ...
    'VariableNames', {'Event','MedianLatency_ms','GaitCycle_pct'}));

% Keep only the three ipsilateral muscles in each gait-cycle set.
rightRows = find(endsWith(sensorMap.Muscle, '_R'));
leftRows  = find(endsWith(sensorMap.Muscle, '_L'));
rightCols = sensorMap.Column(rightRows); leftCols = sensorMap.Column(leftRows);
profilesR = warpedData(rightCols,:,:); profilesL = warpedData(leftCols,:,:);

if normaliseToPercent
    % Use one scale factor per muscle for BOTH individual grey cycles and
    % their mean/SD, so every line in a subplot has the same y-axis scale.
    scaleR = max(reshape(profilesR,3,[]),[],2);
    scaleL = max(reshape(profilesL,3,[]),[],2);
    scaleR(scaleR == 0) = 1;
    scaleL(scaleL == 0) = 1;

    plotProfilesR = 100 * profilesR ./ reshape(scaleR,[3 1 1]);
    plotProfilesL = 100 * profilesL ./ reshape(scaleL,[3 1 1]);
    yLabel = 'Linear envelope (% of valid-cycle maximum)';
else
    plotProfilesR = profilesR;
    plotProfilesL = profilesL;
    yLabel = 'Linear envelope (microvolts)';
end

meanR = mean(plotProfilesR,3,'omitnan');
stdR  = std(plotProfilesR,0,3,'omitnan');
meanL = mean(plotProfilesL,3,'omitnan');
stdL  = std(plotProfilesL,0,3,'omitnan');

gaitPct = EEG.times;
resultFile = fullfile(outDir, baseName + "_emg_timewarped.mat");
save(resultFile, 'sensorMap','emgMeta','fsEMG','bandpassHz','envelopeLowpassHz', ...
    'EEG','emgT','all_events','best_on','best_off','timewarpInfo', ...
    'badEpochsLatency','badEpochsAmplitude','isAmplitudeOutlier', ...
    'intraCyclePeaks','amplitudeThresholds','amplitudeOutlierByChannel', ...
    'warpedData','profilesR','profilesL','plotProfilesR','plotProfilesL', ...
    'meanR','stdR','meanL','stdL', ...
    'gaitPct','eventPct','eventNames','-v7.3');

%% 4. Final six-muscle gait curves: right (top) and left (bottom)
fig = figure('Color','w','Position',[80 80 1300 760], 'Name','Six EMG gait curves');
tiledlayout(2,3,'TileSpacing','compact','Padding','compact');
plotProfileRow(plotProfilesR,meanR,stdR,sensorMap.Muscle(rightRows), ...
    gaitPct,'Right',yLabel,eventPct,eventNames);
plotProfileRow(plotProfilesL,meanL,stdL,sensorMap.Muscle(leftRows), ...
    gaitPct,'Left',yLabel,eventPct,eventNames);
sgtitle(sprintf('%s | EMG fs = %.2f Hz | five-event time-warped HS_R-to-HS_R cycles', baseName, fsEMG),'Interpreter','none');
exportgraphics(fig, fullfile(outDir, baseName + "_six_EMG_gait_curves.png"), 'Resolution', 300);
exportgraphics(fig, fullfile(outDir, baseName + "_six_EMG_gait_curves.pdf"), 'ContentType','vector');
fprintf('Saved time-warped data and six-muscle gait curves in: %s\n', outDir);

%% Local functions
function meta = getEmgMetadata(emgStream, nChannels)
    ids = strings(nChannels,1); labels = strings(nChannels,1);
    try
        ch = emgStream.info.desc.channels.channel;
        if iscell(ch), ch = [ch{:}]; end
        for ii = 1:min(nChannels,numel(ch))
            if isfield(ch(ii),'serial_number_dec'), ids(ii) = string(ch(ii).serial_number_dec); end
            if isfield(ch(ii),'label'), labels(ii) = string(ch(ii).label); end
        end
    catch
        warning('Could not parse EMG channel metadata; using columns only.');
    end
    meta = table((1:nChannels)',ids,labels,'VariableNames',{'Column','SensorID','StreamLabel'});
end

function events = makeAllEvents(hsr,tor,hsl,tol,t0,t1)
    % detect_gait_events returns structs, not raw numeric timestamp vectors.
    events = struct('type',{'START','END'},'time',{t0,t1});
    types = {'HS_R','TO_R','HS_L','TO_L'}; eventStructs = {hsr,tor,hsl,tol};
    for kk = 1:4
        timestamps = eventStructs{kk}.timestamps(:)';
        for ii = 1:numel(timestamps)
            events(end+1) = struct('type',types{kk},'time',timestamps(ii)); %#ok<AGROW>
        end
    end
    [~,ix] = sort([events.time]); events = events(ix);
end

function plotProfileRow(allCycles,mu,sd,names,x,side,yLab,eventPct,eventNames)
    for ii = 1:3
        nexttile; hold on; grid on;

        % Each column is one completely cleaned, time-warped gait cycle.
        cycleMatrix = reshape(allCycles(ii,:,:), ...
            size(allCycles,2), size(allCycles,3));
        hCycles = plot(x,cycleMatrix,'Color',[0.78 0.78 0.78], ...
            'LineWidth',0.45,'HandleVisibility','off');

        % Light variability band, drawn above cycles but below the mean.
        lo = max(0,mu(ii,:)-sd(ii,:)); hi = mu(ii,:)+sd(ii,:);
        fill([x fliplr(x)],[lo fliplr(hi)],[0.25 0.55 0.90], ...
            'FaceAlpha',.12,'EdgeColor','none','HandleVisibility','off');
        hMean = plot(x,mu(ii,:),'Color',[0 0.25 0.75], ...
            'LineWidth',2.6,'DisplayName','Mean');

        % Show a compact legend once per row.
        if ii == 1 && ~isempty(hCycles)
            set(hCycles(1),'HandleVisibility','on','DisplayName','Individual cycles');
            legend([hCycles(1),hMean],{'Individual cycles','Mean'}, ...
                'Location','best','Box','off');
        end

        for ev = 2:(numel(eventPct)-1)
            xline(eventPct(ev), ':k', strrep(eventNames{ev},'_','\_'), ...
                'LabelVerticalAlignment','bottom', 'HandleVisibility','off');
        end
        xlim([0 100]);
        xticks(0:20:100);
        xlabel('Gait cycle (%)'); ylabel(yLab); title(strrep(names(ii),'_',' '));
        if ii == 1, text(.02,.94,[side ' gait cycles'], 'Units','normalized','FontWeight','bold'); end
    end
end
