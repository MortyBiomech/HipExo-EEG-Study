%% Dynamic 22-channel EMG gait-cycle pipeline (subject_P3_1 and later)
% INPUT OPTIONS:
%   1) XDF: select the single 22-channel Delsys EMG stream, then map its
%      individual channels strictly by DEC SensorID. The 16 Avanti sensors
%      contribute one channel each and the 3 Duo sensors contribute two
%      channels each (22 EMG channels in total).
%   2) BDF: load the same 22 converted BIDS EMG channels and read HS/TO
%      from events.tsv.
%
% The two input blocks below are intentionally separate. Keep ONE block active
% and comment out the other. All later filtering, epoch rejection, time-warping
% and plotting steps are shared by both input modes.

clear; clc;

%% ---------------- USER SETTINGS: edit this section only ----------------
run('config_paths.m');

% Use a subject-specific mapping when it exists. For subject_P3_1 and later, the
% subject_P3_1 DEC-ID mapping is the fallback because the same physical sensors
% remain assigned to the same muscle order. Pair numbers are never used.

subjectInfoScript = [current_subject '_infos.m'];
if exist(subjectInfoScript, 'file') == 2
    run(subjectInfoScript);
    subjectInfo = eval(current_subject);
else
    warning('%s was not found; using subject_P3_1_infos.m DEC-ID mapping.', ...
        subjectInfoScript);
    run('subject_P3_1_infos.m');
    subjectInfo = subject_P3_1;
end
sensorMap = buildFullChannelMap(subjectInfo);
fprintf('Subject mapping: %d sensors -> %d EMG channels.\n', ...
    numel(unique(sensorMap.SensorID)), height(sensorMap));

% Sessions containing these keywords will never be processed
excludedSessionKeywords = ["calib"];

% Empty string = process every session found for run_id. Example: use
% "Exo3_sport" to process only the session whose path contains that text.

% P3_1 day1

% sessionFilter = "NoExoPre";
% sessionFilter = "Exo1_sport";
% sessionFilter = "Exo2_aqua";
% sessionFilter = "Exo3_transparent";
% sessionFilter = "Exo4_eco";
% sessionFilter = "Exo5_boost";
% sessionFilter = "Exo6_aquaplus";
% sessionFilter = "NoExoPost";

% day2

% sessionFilter = "NoExoPre";
% sessionFilter = "Exo1_eco";
% sessionFilter = "Exo2_aquaplus";
% sessionFilter = "Exo3_transparent";
% sessionFilter = "Exo4_boost";
% sessionFilter = "Exo5_aqua";
% sessionFilter = "Exo6_sport";
% sessionFilter = "NoExoPost";

% P3_2 day1

% sessionFilter = "NoExoPre";
% sessionFilter = "Exo1_aquaplus";
% sessionFilter = "Exo2_transparent";
% sessionFilter = "Exo3_sport";
% sessionFilter = "Exo4_eco";
% sessionFilter = "Exo5_aqua";
% sessionFilter = "Exo6_boost";
% sessionFilter = "NoExoPost";

% day2

% sessionFilter = "NoExoPre";
% sessionFilter = "Exo1_eco";
% sessionFilter = "Exo2_aqua";
% sessionFilter = "Exo3_transparent";
% sessionFilter = "Exo4_boost";
% sessionFilter = "Exo5_aquaplus";
% sessionFilter = "Exo6_sport";
% sessionFilter = "NoExoPost";

% P3_3 day1

% sessionFilter = "";
% sessionFilter = "NoExoPre";
% sessionFilter = "Exo1_sport";
% sessionFilter = "Exo2_eco";
% sessionFilter = "Exo3_aqua";
% sessionFilter = "Exo4_transparent";
% sessionFilter = "Exo5_boost";
% sessionFilter = "Exo6_aquaplus";
% sessionFilter = "NoExoPost";

% day2

% sessionFilter = "NoExoPre";
% sessionFilter = "Exo1_aquaplus";
% sessionFilter = "Exo2_transparent";
% sessionFilter = "Exo3_boost";
% sessionFilter = "Exo4_eco";
% sessionFilter = "Exo5_aqua";
% sessionFilter = "Exo6_sport";
% sessionFilter = "NoExoPost";

% P3_4 day1

% sessionFilter = "";
% sessionFilter = "NoExoPre";
% sessionFilter = "Exo1_sport";
% sessionFilter = "Exo2_aqua";
% sessionFilter = "Exo3_aquaplus";
% sessionFilter = "Exo4_boost";
% sessionFilter = "Exo5_eco";
% sessionFilter = "Exo6_transparent";
sessionFilter = "NoExoPost";

% day2

% sessionFilter = "NoExoPre";
% sessionFilter = "Exo1_aquaplus";
% sessionFilter = "Exo2_transparent";
% sessionFilter = "Exo3_boost";
% sessionFilter = "Exo4_eco";
% sessionFilter = "Exo5_aqua";
% sessionFilter = "Exo6_sport";
% sessionFilter = "NoExoPost";

% Existing GRF layout retained from get_4_gait_events.m.  Confirm it once by
% checking the validation figure.  Indices refer to the 9 channels in GRF.
grfRightChannels = [1 4 5 8];
grfLeftChannels  = [2 3 6 7];

% XDF only: [] uses the first complete Start_xxx/End_xxx pair from
% IMU_Markers after removing every marker that contains "standing".
% This Sensor-ID pipeline is intended for P3_1 and later recordings only.
% If the required stream or labels are missing, the whole GRF recording is
% analyzed. A manual [start end] uses LSL seconds.
analysisWindowLSL = [];

% Processing settings.  
bandpassHz       = [20 450];
envelopeLowpassHz = 8;
normaliseToPercent = true;   % each muscle scaled to its valid-cycle maximum
showValidationFigures = true;
showCleanEpochBrowser = true; % EEGLAB scroll plot after both rejection steps
saveCleanEpochSet = true;     % save clean epochs with gait events as .set
showOverlapEpochFigure = true; % continuous timeline with overlapping windows
overlapDisplayFirstEpoch = 1; % first retained epoch shown in overlap figure
overlapDisplayCount = 8;      % use Inf to display every retained epoch
%% ------------------------------------------------------------------------

%% INPUT BLOCK A - BDF/BIDS (COMMENT this whole block when using XDF)
% inputMode = "BDF";
% bdfSubjectDir = fullfile(bids_root, ['sub-' bids_subject_id]);
% inputFiles = dir(fullfile(bdfSubjectDir, 'ses-*', 'emg', ...
%     sprintf('*run-%s*_emg.bdf', run_id)));

%% INPUT BLOCK B - XDF (UNCOMMENT this block and comment BLOCK A for XDF)
inputMode = "XDF";
inputFiles = dir(fullfile(data_path, '**', ...
    sprintf('*run-%s_eeg.xdf', run_id)));

inputFiles = filterAndSortInputFiles( ...
    inputFiles, sessionFilter, excludedSessionKeywords);
assert(~isempty(inputFiles), ...
    'No %s files were found for run-%s and session filter "%s".', ...
    inputMode, run_id, sessionFilter);

eeglab nogui;
if inputMode == "BDF"
    assert(exist('pop_biosig', 'file') == 2, ...
        ['pop_biosig is not on the MATLAB path. Install/enable the ' ...
         'EEGLAB BIOSIG plugin before reading BDF files.']);
elseif inputMode == "XDF"
    assert(exist('load_xdf', 'file') == 2, ...
        'load_xdf is not on the MATLAB path. Start EEGLAB/xdfimport first.');
    assert(exist('optimize_thresholds_V1', 'file') == 2 && ...
           exist('detect_gait_events', 'file') == 2, ...
        ['optimize_thresholds_V1.m and detect_gait_events.m must be on the ' ...
         'MATLAB path.']);
else
    error('inputMode must be either "BDF" or "XDF".');
end

fprintf('Found %d %s recording(s) for processing.\n', ...
    numel(inputFiles), inputMode);

for fileIndex = 1:numel(inputFiles)
    sourceFile = fullfile(inputFiles(fileIndex).folder, inputFiles(fileIndex).name);
    [~, baseName] = fileparts(sourceFile);
    sessionFolder = getSessionFolder(sourceFile);

    if inputMode == "BDF"
        outDir = fullfile(bids_root, 'derivatives', 'test_emg_timewarp', ...
            ['sub-' bids_subject_id], sessionFolder, 'emg');
    else
        outDir = fullfile(save_path, sessionFolder);
    end
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    fprintf('\n========================================================\n');
    fprintf('Processing [%d/%d] %s: %s\n', ...
        fileIndex, numel(inputFiles), inputMode, sourceFile);

    if inputMode == "BDF"
        [EEG, emgMeta, sensorMap] = loadBdfInput(sourceFile, sensorMap);
        emgData = double(EEG.data);
        fsEMG = EEG.srate;
        emgT = (0:EEG.pnts-1) / fsEMG;
        all_events = eventsFromEEG(EEG);
        best_on = NaN;
        best_off = NaN;
    else
        [streams, ~] = load_xdf(sourceFile);
        [GRF, grfData, grfT] = getGrfStream(streams, ...
            grfRightChannels, grfLeftChannels);
        [emgData, emgT, emgMeta, sensorMap] = ...
            loadXdfEmgBySensorId(streams, sensorMap);
        fsEMG = 1 / median(diff(emgT));
    end
    assert(size(emgData,1) == 22 && height(sensorMap) == 22, ...
        'Expected 22 mapped EMG channels, but found %d.', size(emgData,1));
    fprintf('Input verification passed: 19 sensors / 22 EMG channels.\n');

%% 1. Detect HS / TO from XDF GRF, or retain BIDS events from BDF
% This deliberately mirrors get_4_gait_events.m so event definitions match
% those used in your previous analysis.
if inputMode == "XDF"
    if isempty(analysisWindowLSL)
        automaticWindow = getAutomaticWalkingWindow(streams);
        if isempty(automaticWindow)
            warning(['IMU_Markers does not contain a complete non-standing ' ...
                'Start_xxx/End_xxx pair. ' ...
                'The entire GRF recording will be analyzed.']);
            use = true(size(grfT));
        else
            use = grfT >= automaticWindow(1) & grfT <= automaticWindow(2);
            fprintf('Using automatic walking window: %.3f to %.3f LSL s.\n', ...
                automaticWindow(1), automaticWindow(2));
        end
    else
        assert(numel(analysisWindowLSL) == 2 && ...
            analysisWindowLSL(1) < analysisWindowLSL(2), ...
            'analysisWindowLSL must be [] or [start end].');
        use = grfT >= analysisWindowLSL(1) & grfT <= analysisWindowLSL(2);
    end
    assert(nnz(use) > 20, ...
        'The selected GRF analysis window contains too few samples.');
    GRF_cropped = GRF;
    GRF_cropped.time_stamps = GRF.time_stamps(use);
    GRF_cropped.time_series = grfData(:,use);

    fprintf('Optimising GRF thresholds in the selected walking window...\n');
    [best_on, best_off] = optimize_thresholds_V1( ...
        GRF_cropped, grfRightChannels, grfLeftChannels);
    [HS_R, TO_R, HS_L, TO_L] = detect_gait_events( ...
        GRF_cropped, grfRightChannels, grfLeftChannels, ...
        'ThresholdOn', best_on, 'ThresholdOff', best_off, ...
        'Plot', showValidationFigures, 'Verbose', true);
    all_events = makeAllEvents(HS_R, TO_R, HS_L, TO_L, ...
        grfT(find(use,1)), grfT(find(use,1,'last')));
    eventFile = fullfile(outDir, baseName + "_gait_events.mat");
    save(eventFile, 'all_events', 'HS_R', 'TO_R', 'HS_L', 'TO_L', ...
        'grfRightChannels', 'grfLeftChannels', 'best_on', 'best_off');
    fprintf('Saved %d gait events: %s\n', numel(all_events), eventFile);
else
    fprintf('Using %d events loaded from the BIDS events.tsv file.\n', ...
        numel(all_events));
end

%% 2. Build continuous EEGLAB EMG dataset and inject GRF events
if inputMode == "XDF"
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

    for ch = 1:EEG.nbchan
        EEG.chanlocs(ch).labels = char(sensorMap.Muscle(ch));
    end

    % XDF all_events uses absolute LSL timestamps.
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
        EEG.event(eventCount).latency = ...
            (eventTime - emgStart) * EEG.srate + 1;
        EEG.event(eventCount).urevent = eventCount;
    end
end

EEG.subject = bids_subject_id;
EEG = eeg_checkset(EEG, 'eventconsistency');

%% Remove unwanted boundary events
EEG = pop_selectevent(EEG, ...
    'type', {'HS_R', 'TO_L', 'HS_L', 'TO_R'}, ...
    'deleteevents', 'on');

EEG = eeg_checkset(EEG, 'eventconsistency');

%% 3. EMG preprocessing
EEG = pop_eegfiltnew(EEG, 'locutoff', bandpassHz(1), ...
    'hicutoff', bandpassHz(2));

EEG.data = abs(EEG.data);              % full-wave rectification
EEG = pop_eegfiltnew(EEG, 'hicutoff', envelopeLowpassHz); % linear envelope
EEG.data(EEG.data < 0) = 0;

EEG.etc.is_envelope = true;
EEG = eeg_checkset(EEG);

% Preserve the continuous filtered envelope and its events. pop_epoch later
% duplicates overlapping samples into separate trials, so this copy is needed
% to visualize the epoch windows on their true chronological timeline.
EEGContinuousEnvelope = EEG;

%% 4. Dynamic epoching around HS_R
targetEvent = 'HS_R';

eventTypes = string({EEG.event.type});
rhsLatency = [EEG.event(strcmp(eventTypes, targetEvent)).latency];

assert(numel(rhsLatency) >= 2, ...
    'Less than two HS_R events remain inside the EMG recording.');

rhsIntervals = diff(rhsLatency) / EEG.srate;
maxRhsToNextRhs = max(rhsIntervals);

epochWindow = [-0.6, maxRhsToNextRhs + 0.6];

% pop_epoch keeps only anchors whose complete epoch window is inside the data.
epochStartSampleContinuous = round(rhsLatency + epochWindow(1)*EEG.srate);
epochEndSampleContinuous   = round(rhsLatency + epochWindow(2)*EEG.srate);
completeEpochMask = epochStartSampleContinuous >= 1 & ...
                    epochEndSampleContinuous <= EEG.pnts;
epochAnchorLatencyContinuous = rhsLatency(completeEpochMask);

fprintf('Epoch window: [%.3f, %.3f] s\n', ...
    epochWindow(1), epochWindow(2));

EEG = pop_epoch(EEG, {targetEvent}, epochWindow, ...
    'newname', 'HS_R epochs', ...
    'epochinfo', 'yes');

EEG = eeg_checkset(EEG);
EEG.setname = [EEG.subject '_Epoched_EMG'];
EEG = eeg_checkset(EEG);

assert(numel(epochAnchorLatencyContinuous) == EEG.trials, ...
    ['Could not map epoched trials back to continuous HS_R anchors: ' ...
     '%d complete anchors versus %d EEGLAB epochs.'], ...
    numel(epochAnchorLatencyContinuous), EEG.trials);

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
epochAnchorAfterLatency = epochAnchorLatencyContinuous(goodEpochs);

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

%% Step 3.2: Amplitude Outlier Rejection (all 22 channels, peak > 3 SD)
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
cleanEpochAnchorContinuous = ...
    epochAnchorAfterLatency(~isAmplitudeOutlier);
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

%% Display/save cleaned epochs before physical time-warp removes the events
% This copy contains only epochs that passed BOTH latency and amplitude
% rejection. It still contains HS_R, TO_L, HS_L and TO_R in EEG.event.
EEGCleanEpoched = EEG;
EEGCleanEpoched.setname = [EEG.subject '_CleanEpoched_WithEvents'];
EEGCleanEpoched = eeg_checkset(EEGCleanEpoched, 'eventconsistency');

cleanEventTypes = string({EEGCleanEpoched.event.type});
fprintf('>> Clean epoched dataset contains %d epochs and %d events.\n', ...
    EEGCleanEpoched.trials, numel(EEGCleanEpoched.event));
uniqueEventTypes = unique(cleanEventTypes);
for k = 1:numel(uniqueEventTypes)
    fprintf('   - %-6s: %d events\n', uniqueEventTypes(k), ...
        sum(cleanEventTypes == uniqueEventTypes(k)));
end

if saveCleanEpochSet
    cleanEpochSetName = baseName + "_desc-CleanEpochedWithEvents_emg.set";
    EEGCleanEpoched = pop_saveset(EEGCleanEpoched, ...
        'filename', char(cleanEpochSetName), 'filepath', outDir);
    fprintf('>> Saved clean epochs with events: %s\n', ...
        fullfile(outDir,cleanEpochSetName));
end

if showCleanEpochBrowser
    % typerej=1: channel data; superpose=1: show existing epoch markings;
    % reject=0: visualization only--do not perform another rejection here.
    pop_eegplot(EEGCleanEpoched,1,1,0);
    drawnow;
end

if showOverlapEpochFigure
    plotOverlappingEpochWindows(EEGContinuousEnvelope, ...
        cleanEpochAnchorContinuous, epochWindow, ...
        overlapDisplayFirstEpoch, overlapDisplayCount, ...
        outDir, baseName);
end

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

% Preserve all 22 time-warped channels. The original 2 x 3 gait summary
% below still uses GastMed, Soleus and TibAnt from each leg.
rightRows = find(sensorMap.GaitPlotSide == "R");
leftRows  = find(sensorMap.GaitPlotSide == "L");
[~, rightOrder] = sort(sensorMap.GaitPlotOrder(rightRows));
[~, leftOrder] = sort(sensorMap.GaitPlotOrder(leftRows));
rightRows = rightRows(rightOrder);
leftRows = leftRows(leftOrder);
assert(numel(rightRows) == 3 && numel(leftRows) == 3, ...
    'The full channel map must identify three gait-summary muscles per side.');
rightCols = sensorMap.Column(rightRows); leftCols = sensorMap.Column(leftRows);
allProfiles = warpedData;
profilesR = allProfiles(rightCols,:,:);
profilesL = allProfiles(leftCols,:,:);

if normaliseToPercent
    % Use one scale factor per channel for BOTH individual grey cycles and
    % mean/SD. This includes all 22 channels, not only the gait-summary six.
    scaleAll = max(reshape(allProfiles,EEG.nbchan,[]),[],2);
    scaleAll(~isfinite(scaleAll) | scaleAll <= 0) = 1;
    plotAllProfiles = 100 * allProfiles ./ ...
        reshape(scaleAll,[EEG.nbchan 1 1]);
    yLabel = 'Linear envelope (% of valid-cycle maximum)';
else
    scaleAll = ones(EEG.nbchan,1);
    plotAllProfiles = allProfiles;
    yLabel = 'Linear envelope (native input units)';
end

plotProfilesR = plotAllProfiles(rightCols,:,:);
plotProfilesL = plotAllProfiles(leftCols,:,:);
meanAll = mean(plotAllProfiles,3,'omitnan');
stdAll  = std(plotAllProfiles,0,3,'omitnan');
meanR = mean(plotProfilesR,3,'omitnan');
stdR  = std(plotProfilesR,0,3,'omitnan');
meanL = mean(plotProfilesL,3,'omitnan');
stdL  = std(plotProfilesL,0,3,'omitnan');

gaitPct = EEG.times;
resultFile = fullfile(outDir, baseName + "_emg_timewarped.mat");
save(resultFile, 'sensorMap','emgMeta','fsEMG','bandpassHz','envelopeLowpassHz', ...
    'EEG','emgT','all_events','best_on','best_off','timewarpInfo', ...
    'epochWindow','epochAnchorLatencyContinuous','cleanEpochAnchorContinuous', ...
    'badEpochsLatency','badEpochsAmplitude','isAmplitudeOutlier', ...
    'intraCyclePeaks','amplitudeThresholds','amplitudeOutlierByChannel', ...
    'warpedData','allProfiles','plotAllProfiles','scaleAll','meanAll','stdAll', ...
    'profilesR','profilesL','plotProfilesR','plotProfilesL', ...
    'meanR','stdR','meanL','stdL', ...
    'gaitPct','eventPct','eventNames','-v7.3');

%% 4.1 Full 22-channel gait curves
figAll = plotAllChannelProfiles(plotAllProfiles,meanAll,stdAll, ...
    sensorMap.Muscle,gaitPct,yLabel,eventPct,eventNames,baseName,fsEMG);
exportgraphics(figAll, fullfile(outDir, ...
    baseName + "_all_22_EMG_gait_curves.png"), 'Resolution', 300);
exportgraphics(figAll, fullfile(outDir, ...
    baseName + "_all_22_EMG_gait_curves.pdf"), ...
    'ContentType','image','Resolution',300);

%% 4.2 Six-muscle gait summary: right (top) and left (bottom)
fig = figure('Color','w','Position',[80 80 1300 760], 'Name','Six EMG gait curves');
tiledlayout(2,3,'TileSpacing','compact','Padding','compact');
plotProfileRow(plotProfilesR,meanR,stdR,sensorMap.Muscle(rightRows), ...
    gaitPct,'Right',yLabel,eventPct,eventNames);
plotProfileRow(plotProfilesL,meanL,stdL,sensorMap.Muscle(leftRows), ...
    gaitPct,'Left',yLabel,eventPct,eventNames);
sgtitle(sprintf('%s | EMG fs = %.2f Hz | five-event time-warped HS_R-to-HS_R cycles', baseName, fsEMG),'Interpreter','none');

% Hide axes toolbars so they are not captured in exported images.
allAxes = findall(fig,'Type','axes');
for k = 1:numel(allAxes)
    try
        allAxes(k).Toolbar.Visible = 'off';
    catch
    end
end
drawnow;

exportgraphics(fig, fullfile(outDir, baseName + "_six_EMG_gait_curves.png"), 'Resolution', 300);
exportgraphics(fig, fullfile(outDir, baseName + "_six_EMG_gait_curves.pdf"), ...
    'ContentType','image','Resolution',300);
fprintf('Saved time-warped data and six-muscle gait curves in: %s\n', outDir);
fprintf('Saved the complete 22-channel gait-curve figure in: %s\n', outDir);

end % fileIndex loop

fprintf('\n========================================================\n');
fprintf('Finished processing %d %s recording(s).\n', ...
    numel(inputFiles), inputMode);

%% Local functions
function sensorMap = buildFullChannelMap(subjectInfo)
    requiredVariables = {'SensorID','MuscleName'};
    assert(all(ismember(requiredVariables, ...
        subjectInfo.Properties.VariableNames)), ...
        'The subject info table must contain SensorID and MuscleName.');

    nSensors = height(subjectInfo);
    assert(nSensors == 19, ...
        'Expected 19 Delsys sensor rows, but subject info contains %d.', ...
        nSensors);

    % Sensor placement order, SensorID order and MuscleName order are the
    % same in the subject-info table. Do not reorder rows by muscle name.
    musclesBySensor = strtrim(string(subjectInfo.MuscleName(:)));
    sensorIdsBySensor = strtrim(string(subjectInfo.SensorID(:)));
    assert(all(~ismissing(musclesBySensor) & strlength(musclesBySensor) > 0), ...
        'Every sensor row must contain a non-empty MuscleName.');
    assert(all(~ismissing(sensorIdsBySensor) & ...
        strlength(sensorIdsBySensor) > 0), ...
        'Every sensor row must contain a SensorID.');
    assert(all(isfinite(str2double(sensorIdsBySensor))), ...
        'Every SensorID must be a valid decimal number.');
    assert(numel(unique(sensorIdsBySensor)) == nSensors, ...
        'Each of the 19 sensors must have one unique DEC SensorID.');

    if ismember('SensorType', subjectInfo.Properties.VariableNames)
        sensorTypesBySensor = strtrim(string(subjectInfo.SensorType(:)));
    else
        % If SensorType is absent, use the established physical order:
        % rows 1-16 are Avanti and rows 17-19 are Duo sensors.
        sensorTypesBySensor = repmat("AvantiSensor", nSensors, 1);
        sensorTypesBySensor(17:19) = "DuoSensor";
    end

    % Preserve established short labels for the lower-limb channels. New or
    % changed names (for example the day1/day2 neck placements) are converted
    % automatically and are not required to appear in this optional list.
    knownMuscles = [
        "Tibialis anterior R";
        "Soleus R";
        "Gastrocnemius cap. mediale R";
        "Vastus medialis R";
        "Rectus femoris R";
        "Biceps femoris R";
        "Glutaeus maximus R";
        "Tibialis anterior L";
        "Soleus L";
        "Gastrocnemius cap. mediale L";
        "Vastus medialis L";
        "Rectus femoris L";
        "Biceps femoris L";
        "Glutaeus maximus L";
        "Trapezius R";
        "Trapezius L"
    ];
    knownShortNames = [
        "TibAnt_R";
        "Soleus_R";
        "GastMed_R";
        "VastMed_R";
        "RectFem_R";
        "BicepsFem_R";
        "GlutMax_R";
        "TibAnt_L";
        "Soleus_L";
        "GastMed_L";
        "VastMed_L";
        "RectFem_L";
        "BicepsFem_L";
        "GlutMax_L";
        "Trapezius_R";
        "Trapezius_L"
    ];

    shortNamesBySensor = strings(nSensors,1);
    for ii = 1:nSensors
        knownHit = find(strcmpi(knownMuscles, musclesBySensor(ii)), 1);
        if ~isempty(knownHit)
            shortNamesBySensor(ii) = knownShortNames(knownHit);
        else
            generatedName = regexprep(musclesBySensor(ii), ...
                '[^A-Za-z0-9]+', '_');
            generatedName = regexprep(generatedName, '^_+|_+$', '');
            if strlength(generatedName) == 0
                generatedName = "Sensor_" + ii;
            end
            shortNamesBySensor(ii) = generatedName;
        end
    end
    shortNamesBySensor = string(matlab.lang.makeUniqueStrings( ...
        cellstr(shortNamesBySensor)));
    shortNamesBySensor = shortNamesBySensor(:);

    isAvanti = strcmpi(sensorTypesBySensor, 'AvantiSensor');
    isDuo = strcmpi(sensorTypesBySensor, 'DuoSensor');
    assert(nnz(isAvanti) == 16 && nnz(isDuo) == 3 && ...
           all(isAvanti | isDuo), ...
        ['Expected exactly 16 AvantiSensor rows and 3 DuoSensor rows in ' ...
         'subject info.']);

    channelCountBySensor = ones(nSensors,1);
    channelCountBySensor(isDuo) = 2;
    totalChannels = sum(channelCountBySensor);
    assert(totalChannels == 22, ...
        'The 19-sensor mapping must expand to exactly 22 channels.');

    sensorIndex = zeros(totalChannels,1);
    sensorIds = strings(totalChannels,1);
    sensorTypes = strings(totalChannels,1);
    sensorChannels = zeros(totalChannels,1);
    channelNames = strings(totalChannels,1);
    sourceMuscles = strings(totalChannels,1);
    gaitPlotSide = strings(totalChannels,1);
    gaitPlotOrder = nan(totalChannels,1);

    gaitMuscles = [
        "Gastrocnemius cap. mediale R"; "Soleus R"; "Tibialis anterior R";
        "Gastrocnemius cap. mediale L"; "Soleus L"; "Tibialis anterior L"
    ];
    gaitSides = ["R"; "R"; "R"; "L"; "L"; "L"];
    gaitOrders = [1; 2; 3; 1; 2; 3];

    outputRow = 0;
    for sensorRow = 1:nSensors
        for channelWithinSensor = 1:channelCountBySensor(sensorRow)
            outputRow = outputRow + 1;
            sensorIndex(outputRow) = sensorRow;
            sensorIds(outputRow) = sensorIdsBySensor(sensorRow);
            sensorTypes(outputRow) = sensorTypesBySensor(sensorRow);
            sensorChannels(outputRow) = channelWithinSensor;
            sourceMuscles(outputRow) = musclesBySensor(sensorRow);

            channelName = shortNamesBySensor(sensorRow);
            if channelCountBySensor(sensorRow) == 2
                channelName = channelName + "_CH" + channelWithinSensor;
            end
            channelNames(outputRow) = channelName;

            gaitHit = find(strcmpi(gaitMuscles, ...
                musclesBySensor(sensorRow)), 1);
            if ~isempty(gaitHit)
                gaitPlotSide(outputRow) = gaitSides(gaitHit);
                gaitPlotOrder(outputRow) = gaitOrders(gaitHit);
            end
        end
    end

    sensorMap = table(sensorIndex, sensorIds, sensorTypes, sensorChannels, ...
        channelNames, sourceMuscles, gaitPlotSide, gaitPlotOrder, ...
        zeros(totalChannels,1), ...
        'VariableNames', {'SensorIndex','SensorID','SensorType', ...
        'SensorChannel','Muscle','SourceMuscle','GaitPlotSide', ...
        'GaitPlotOrder','Column'});
end

function files = filterAndSortInputFiles( ...
        files, sessionFilter, excludedSessionKeywords)

    if isempty(files)
        return;
    end

    % Default settings
    if nargin < 2 || isempty(sessionFilter)
        sessionFilter = "";
    end

    % "calib" can match calibration, calib, GRF_calibration, etc.
    if nargin < 3 || isempty(excludedSessionKeywords)
        excludedSessionKeywords = ["calib", "setup"];
    end

    sessionFilter = string(sessionFilter);
    excludedSessionKeywords = string(excludedSessionKeywords);

    paths = string(arrayfun(@(item) ...
        fullfile(item.folder, item.name), files, ...
        'UniformOutput', false));
    paths = paths(:);

    % Extract session folder names
    sessionNames = strings(numel(files), 1);
    for ii = 1:numel(files)
        sessionNames(ii) = string(getSessionFolder(paths(ii)));
    end

    %% Always remove calibration/setup sessions
    isExcluded = false(numel(files), 1);

    for kk = 1:numel(excludedSessionKeywords)
        keyword = excludedSessionKeywords(kk);

        if strlength(keyword) > 0
            isExcluded = isExcluded | contains( ...
                sessionNames, keyword, ...
                'IgnoreCase', true);
        end
    end

    if any(isExcluded)
        fprintf('Skipping %d excluded recording(s):\n', ...
            nnz(isExcluded));

        excludedIndices = find(isExcluded);
        for ii = 1:numel(excludedIndices)
            idx = excludedIndices(ii);
            fprintf('   - %s\n', paths(idx));
        end
    end

    files = files(~isExcluded);
    paths = paths(~isExcluded);
    sessionNames = sessionNames(~isExcluded);

    if isempty(files)
        return;
    end

    %% Apply optional positive session filter
    if strlength(sessionFilter) > 0
        keep = contains( ...
            sessionNames, sessionFilter, ...
            'IgnoreCase', true);

        files = files(keep);
        paths = paths(keep);
        sessionNames = sessionNames(keep);
    end

    if isempty(files)
        return;
    end

    %% Sort sessions
    orderKey = 50 * ones(numel(files), 1);

    for ii = 1:numel(files)
        sessionName = lower(sessionNames(ii));

        if contains(sessionName, 'noexopre')
            orderKey(ii) = 0;

        elseif contains(sessionName, 'noexopost')
            orderKey(ii) = 99;

        else
            token = regexp( ...
                char(sessionName), ...
                'exo(\d+)', ...
                'tokens', ...
                'once');

            if ~isempty(token)
                orderKey(ii) = 10 + str2double(token{1});
            end
        end
    end

    originalIndex = (1:numel(files))';

    sortingTable = table( ...
        orderKey, lower(paths), originalIndex, ...
        'VariableNames', ...
        {'OrderKey', 'Path', 'OriginalIndex'});

    sortingTable = sortrows( ...
        sortingTable, {'OrderKey', 'Path'});

    files = files(sortingTable.OriginalIndex);
end

function sessionFolder = getSessionFolder(filePath)
    pathParts = regexp(char(filePath), '[\\/]', 'split');
    hit = find(startsWith(string(pathParts), 'ses-', ...
        'IgnoreCase', true), 1, 'last');
    if isempty(hit)
        sessionFolder = 'ses-unknown';
    else
        sessionFolder = char(pathParts{hit});
    end
end

function [EEG, emgMeta, sensorMap] = loadBdfInput(sourceFile, sensorMap)
    fprintf('Loading BDF: %s\n', sourceFile);
    EEG = pop_biosig(sourceFile);
    EEG = eeg_checkset(EEG);

    rawLabels = strtrim(string({EEG.chanlocs.labels}));
    normalizedRaw = normalizeNames(rawLabels);
    sourceColumns = zeros(height(sensorMap),1);
    mappingSucceeded = true;
    for ii = 1:height(sensorMap)
        fullSourceLabel = sensorMap.SourceMuscle(ii);
        if strcmpi(sensorMap.SensorType(ii), 'DuoSensor')
            fullSourceLabel = fullSourceLabel + "_CH" + ...
                sensorMap.SensorChannel(ii);
        end
        aliases = normalizeNames([sensorMap.Muscle(ii),fullSourceLabel]);
        hit = find(ismember(normalizedRaw, aliases) & ...
            ~ismember(1:numel(rawLabels),sourceColumns(1:max(ii-1,1))'), 1);
        if isempty(hit)
            mappingSucceeded = false;
            break;
        end
        sourceColumns(ii) = hit;
    end

    if ~mappingSucceeded
        % BDF channel labels can be shortened by the EDF/BDF writer. The
        % conversion script writes channels in the expanded subject-table
        % order, so use that deterministic order only when label matching
        % cannot recover all 22 names.
        assert(EEG.nbchan >= height(sensorMap), ...
            ['Could not map BDF labels and the file contains only %d ' ...
             'channels; 22 are required. Available labels: %s'], ...
            EEG.nbchan, strjoin(rawLabels, ', '));
        warning(['BDF labels could not identify all 22 channels uniquely. ' ...
            'Using the first 22 channels in subject-info order.']);
        sourceColumns = (1:height(sensorMap))';
    end
    assert(numel(unique(sourceColumns)) == height(sensorMap), ...
        'BDF muscle aliases did not map to 22 distinct channels.');

    emgMeta = table(sourceColumns, string(sensorMap.SensorID), ...
        string(sensorMap.SensorType), sensorMap.SensorChannel, ...
        rawLabels(sourceColumns)', ...
        'VariableNames', {'SourceColumn','SensorID','SensorType', ...
        'SensorChannel','StreamLabel'});

    EEG = pop_select(EEG, 'channel', sourceColumns');
    sensorMap.SourceColumn = sourceColumns;
    sensorMap.Column = (1:height(sensorMap))';
    for ii = 1:EEG.nbchan
        EEG.chanlocs(ii).labels = char(sensorMap.Muscle(ii));
    end

    eventsFile = regexprep(sourceFile, '_emg\.bdf$', ...
        '_events.tsv', 'ignorecase');
    assert(exist(eventsFile, 'file') == 2, ...
        'BIDS events.tsv was not found: %s', eventsFile);
    fprintf('Reading BIDS events: %s\n', eventsFile);
    opts = detectImportOptions(eventsFile, 'FileType', 'text', ...
        'Delimiter', '\t');
    eventsTable = readtable(eventsFile, opts);
    assert(ismember('onset', eventsTable.Properties.VariableNames) && ...
           ismember('trial_type', eventsTable.Properties.VariableNames), ...
        'events.tsv must contain onset and trial_type columns.');

    onsetSeconds = numericTableColumn(eventsTable.onset);
    eventTypes = strtrim(string(eventsTable.trial_type));
    if ismember('duration', eventsTable.Properties.VariableNames)
        durationSeconds = numericTableColumn(eventsTable.duration);
    else
        durationSeconds = zeros(height(eventsTable),1);
    end

    EEG.event = [];
    eventCount = 0;
    recordingDuration = (EEG.pnts - 1) / EEG.srate;
    for ii = 1:height(eventsTable)
        if ~isfinite(onsetSeconds(ii)) || onsetSeconds(ii) < 0 || ...
                onsetSeconds(ii) > recordingDuration
            continue;
        end
        eventCount = eventCount + 1;
        EEG.event(eventCount).type = char(eventTypes(ii));
        EEG.event(eventCount).latency = onsetSeconds(ii) * EEG.srate + 1;
        EEG.event(eventCount).urevent = eventCount;
        if isfinite(durationSeconds(ii))
            EEG.event(eventCount).duration = ...
                durationSeconds(ii) * EEG.srate;
        end
    end
    EEG = eeg_checkset(EEG, 'eventconsistency');
    fprintf('Loaded all %d EMG channels and %d BIDS events.\n', ...
        EEG.nbchan, eventCount);
end

function values = numericTableColumn(column)
    if isnumeric(column)
        values = double(column);
    else
        values = str2double(string(column));
    end
    values = values(:);
end

function events = eventsFromEEG(EEG)
    events = struct('type', {}, 'time', {});
    for ii = 1:numel(EEG.event)
        events(ii).type = char(string(EEG.event(ii).type)); %#ok<AGROW>
        events(ii).time = (double(EEG.event(ii).latency) - 1) / EEG.srate;
    end
end

function [GRF, grfData, grfT] = getGrfStream(streams, ...
        grfRightChannels, grfLeftChannels)
    grfIndex = [];
    for ii = 1:numel(streams)
        streamName = getInfoText(streams{ii}.info, 'name');
        streamType = getInfoText(streams{ii}.info, 'type');
        if strcmpi(streamName, 'GRF') || strcmpi(streamType, 'Force')
            grfIndex = ii;
            break;
        end
    end
    assert(~isempty(grfIndex), 'No GRF / Force stream was found in XDF.');
    GRF = streams{grfIndex};
    grfT = double(GRF.time_stamps(:)');
    grfData = orientStreamData(GRF.time_series, numel(grfT));
    assert(size(grfData,1) >= ...
        max([grfRightChannels grfLeftChannels]), ...
        'GRF channel indices exceed available channels.');
end

function [emgData, emgT, emgMeta, sensorMap] = ...
        loadXdfEmgBySensorId(streams, sensorMap)
    % Subject 4 and later store all 22 EMG channels in ONE XDF stream.
    % Sensor IDs therefore belong to channel metadata, not to separate
    % streams. Pair information is intentionally never used.
    emgStreamIndices = zeros(0,1);
    emgStreamLabels = strings(0,1);
    emgChannelCounts = zeros(0,1);
    for ii = 1:numel(streams)
        if ~strcmpi(getInfoText(streams{ii}.info, 'type'), 'EMG') || ...
                isempty(streams{ii}.time_stamps)
            continue;
        end
        nSamples = numel(streams{ii}.time_stamps);
        candidateData = orientStreamData(streams{ii}.time_series, nSamples);
        emgStreamIndices(end+1,1) = ii; %#ok<AGROW>
        emgStreamLabels(end+1,1) = ...
            getInfoText(streams{ii}.info, 'name'); %#ok<AGROW>
        emgChannelCounts(end+1,1) = size(candidateData,1); %#ok<AGROW>
    end
    assert(~isempty(emgStreamIndices), ...
        'No non-empty EMG stream was found in XDF.');

    disp('EMG streams found in XDF:');
    disp(table(emgStreamIndices, emgChannelCounts, emgStreamLabels, ...
        'VariableNames', {'StreamIndex','ChannelCount','StreamLabel'}));

    targetStream = find(emgChannelCounts == height(sensorMap));
    assert(isscalar(targetStream), ...
        ['Expected exactly one XDF EMG stream containing %d channels, ' ...
         'but found %d.'], height(sensorMap), numel(targetStream));

    sourceStreamIndex = emgStreamIndices(targetStream);
    streamLabel = emgStreamLabels(targetStream);
    emgStream = streams{sourceStreamIndex};
    emgT = double(emgStream.time_stamps(:)');
    sourceData = orientStreamData(emgStream.time_series, numel(emgT));
    assert(numel(emgT) > 20, 'The XDF EMG stream is too short.');

    [channelIds, channelLabels] = extractChannelMetadata( ...
        emgStream, size(sourceData,1));

    disp('Channels found inside the selected XDF EMG stream:');
    disp(table((1:size(sourceData,1))', channelIds, channelLabels, ...
        'VariableNames', {'SourceColumn','SensorID','ChannelLabel'}));

    missingMetadata = find(strlength(channelIds) == 0);
    assert(isempty(missingMetadata), ...
        ['The following XDF EMG columns have no serial_number_dec value: %s. ' ...
         'Sensor mapping cannot be verified without channel-level DEC IDs.'], ...
        mat2str(missingMetadata(:)'));

    sourceColumns = zeros(height(sensorMap),1);
    uniqueSensorIds = unique(string(sensorMap.SensorID), 'stable');
    for sensorIndex = 1:numel(uniqueSensorIds)
        requiredId = uniqueSensorIds(sensorIndex);
        mapRows = find(string(sensorMap.SensorID) == requiredId);
        sourceHits = find(channelIds == requiredId);
        expectedChannels = numel(mapRows);
        assert(numel(sourceHits) == expectedChannels, ...
            ['DEC SensorID %s should occur in %d channel(s) for %s, ' ...
             'but it occurs in %d XDF channel(s). Pair information is ignored.'], ...
            requiredId, expectedChannels, ...
            sensorMap.SourceMuscle(mapRows(1)), numel(sourceHits));

        % sourceHits is in physical XDF channel order. SensorChannel 1/2
        % selects the first/second channel of each DuoSensor.
        for rowIndex = reshape(mapRows, 1, [])
            channelWithinSensor = sensorMap.SensorChannel(rowIndex);
            sourceColumns(rowIndex) = sourceHits(channelWithinSensor);
        end
    end

    assert(numel(unique(sourceColumns)) == height(sensorMap) && ...
           all(sourceColumns >= 1), ...
        'The 22 XDF source channels could not be mapped one-to-one.');

    % One stream means every channel already has the same timestamps. Only
    % reorder rows into the established muscle/channel order; no inter-stream
    % interpolation is necessary.
    emgData = double(sourceData(sourceColumns,:));
    assert(all(isfinite(emgData(:))), ...
        'The mapped XDF EMG data contain non-finite values.');

    sensorMap.SourceStream = repmat(sourceStreamIndex, height(sensorMap), 1);
    sensorMap.SourceColumn = sourceColumns;
    sensorMap.Column = (1:height(sensorMap))';
    emgMeta = table(sensorMap.SourceStream, sourceColumns, ...
        string(sensorMap.SensorID), string(sensorMap.SensorType), ...
        sensorMap.SensorChannel, repmat(streamLabel, height(sensorMap),1), ...
        channelLabels(sourceColumns), ...
        'VariableNames', {'SourceStream','SourceColumn','SensorID', ...
        'SensorType','SensorChannel','StreamLabel','ChannelLabel'});
end

function [sensorIds, channelLabels] = extractChannelMetadata(stream, nChannels)
    % Read the metadata entry belonging to every column of the combined
    % Delsys stream. Both channels of a DuoSensor must carry the same DEC ID.
    entries = {};
    try
        channelInfo = stream.info.desc.channels.channel;
        if iscell(channelInfo)
            entries = channelInfo(:);
        else
            entries = num2cell(channelInfo(:));
        end
    catch ME
        error('Could not read XDF EMG channel metadata: %s', ME.message);
    end
    assert(numel(entries) >= nChannels, ...
        ['XDF reports %d EMG data columns, but only %d channel metadata ' ...
         'entries were found.'], nChannels, numel(entries));

    sensorIds = strings(nChannels,1);
    channelLabels = strings(nChannels,1);
    for ii = 1:nChannels
        entry = entries{ii};
        while iscell(entry) && isscalar(entry)
            entry = entry{1};
        end

        sensorIds(ii) = getChannelFieldText(entry, 'serial_number_dec');
        for labelField = ["label", "name", "type"]
            value = getChannelFieldText(entry, labelField);
            if strlength(value) > 0
                channelLabels(ii) = value;
                break;
            end
        end
        if strlength(channelLabels(ii)) == 0
            channelLabels(ii) = "XDF_Channel_" + ii;
        end

        % Fallback for XDF versions with another cell/struct wrapping.
        if strlength(sensorIds(ii)) == 0
            try
                metadataText = jsonencode(entry);
                token = regexp(metadataText, ...
                    '"serial_number_dec"\s*:\s*"?(\d+)"?', ...
                    'tokens', 'once');
                if ~isempty(token), sensorIds(ii) = string(token{1}); end
            catch
            end
        end
    end
end

function value = getChannelFieldText(entry, fieldName)
    value = "";
    if ~isstruct(entry) || ~isfield(entry, fieldName), return; end
    rawValue = entry.(fieldName);
    while iscell(rawValue) && numel(rawValue) == 1
        rawValue = rawValue{1};
    end
    if isempty(rawValue) || isstruct(rawValue), return; end
    candidates = strtrim(string(rawValue));
    candidates = candidates(strlength(candidates) > 0);
    if ~isempty(candidates), value = candidates(1); end
end

function data = orientStreamData(rawData, nSamples)
    data = double(rawData);
    if size(data,2) == nSamples
        return;
    elseif size(data,1) == nSamples
        data = data.';
    else
        error('Stream data dimensions do not match its timestamp count.');
    end
end

function value = getInfoText(info, fieldName)
    value = "";
    if ~isfield(info, fieldName), return; end
    rawValue = info.(fieldName);
    while iscell(rawValue) && ~isempty(rawValue)
        rawValue = rawValue{1};
    end
    if isempty(rawValue), return; end
    textValue = string(rawValue);
    value = textValue(1);
end

function normalized = normalizeNames(names)
    normalized = regexprep(lower(string(names)), '[^a-z0-9]', '');
end

function automaticWindow = getAutomaticWalkingWindow(streams)
    automaticWindow = [];
    markerIndex = [];
    for ii = 1:numel(streams)
        streamName = getInfoText(streams{ii}.info, 'name');
        if strcmpi(strtrim(streamName), 'IMU_Markers')
            markerIndex = ii;
            break;
        end
    end
    if isempty(markerIndex), return; end

    markerStream = streams{markerIndex};
    markerLabels = flattenMarkerLabels(markerStream.time_series);
    markerTimes = double(markerStream.time_stamps(:));
    nMarkers = min(numel(markerLabels), numel(markerTimes));
    markerLabels = markerLabels(1:nMarkers);
    markerTimes = markerTimes(1:nMarkers);
    if nMarkers == 0, return; end

    [startIndex, endIndex] = findNonStandingMarkerPair( ...
        markerLabels, markerTimes);
    if isempty(startIndex) || isempty(endIndex), return; end

    automaticWindow = [markerTimes(startIndex), markerTimes(endIndex)];
    markerStreamName = getInfoText(markerStream.info, 'name');
    fprintf('Walking markers from %s: %s -> %s.\n', ...
        char(markerStreamName), char(markerLabels(startIndex)), ...
        char(markerLabels(endIndex)));
end

function labels = flattenMarkerLabels(timeSeries)
    labels = strings(numel(timeSeries),1);
    for ii = 1:numel(timeSeries)
        if iscell(timeSeries)
            value = timeSeries{ii};
        else
            value = timeSeries(ii);
        end
        while iscell(value) && ~isempty(value), value = value{1}; end
        textValue = string(value);
        if ~isempty(textValue), labels(ii) = textValue(1); end
    end
end

function [startIndex, endIndex] = findNonStandingMarkerPair(labels, times)
    startIndex = [];
    endIndex = [];

    %% 1. Standardize marker labels and timestamps
    labels = strtrim(string(labels(:)));
    times  = double(times(:));

    nMarkers = min(numel(labels), numel(times));
    labels = labels(1:nMarkers);
    times  = times(1:nMarkers);

    if nMarkers == 0
        return;
    end

    normalizedLabels = lower(labels);

    %% 2. Remove every marker containing "standing"
    isStanding = contains(normalizedLabels, "standing");

    %% 3. Support both marker naming formats
    % Format A:
    %   Start_boost / End_boost
    %
    % Format B:
    %   NoExoPre_walking_Start / NoExoPre_walking_End

    isStartMarker = ...
        startsWith(normalizedLabels, "start_") | ...
        endsWith(normalizedLabels, "_start");

    isEndMarker = ...
        startsWith(normalizedLabels, "end_") | ...
        endsWith(normalizedLabels, "_end");

    startCandidates = find(isStartMarker & ~isStanding);
    endCandidates   = find(isEndMarker   & ~isStanding);

    if isempty(startCandidates) || isempty(endCandidates)
        return;
    end

    %% 4. Extract the common part of each marker name
    % Start_boost                -> boost
    % End_boost                  -> boost
    % NoExoPre_walking_Start     -> noexopre_walking
    % NoExoPre_walking_End       -> noexopre_walking

    startKeys = regexprep( ...
        normalizedLabels(startCandidates), ...
        '^start_|_start$', '');

    endKeys = regexprep( ...
        normalizedLabels(endCandidates), ...
        '^end_|_end$', '');

    %% 5. Search from the latest Start marker backwards
    % This ensures that the last complete pair is selected.
    [~, startOrder] = sort(times(startCandidates), 'descend');

    startCandidates = startCandidates(startOrder);
    startKeys       = startKeys(startOrder);

    for ii = 1:numel(startCandidates)
        candidateStart = startCandidates(ii);
        startKey = startKeys(ii);

        % The End marker must:
        % 1. Have the same name/key
        % 2. Occur after the Start marker
        matchingEnds = endCandidates( ...
            endKeys == startKey & ...
            times(endCandidates) > times(candidateStart));

        if isempty(matchingEnds)
            continue;
        end

        % Select the first matching End after this Start
        [~, firstEnd] = min(times(matchingEnds));

        startIndex = candidateStart;
        endIndex   = matchingEnds(firstEnd);
        return;
    end
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

function fig = plotAllChannelProfiles(allCycles,mu,sd,names,x,yLab, ...
        eventPct,eventNames,baseName,fsEMG)
    nChannels = size(allCycles,1);
    nColumns = 4;
    nRows = ceil(nChannels/nColumns);
    fig = figure('Color','w','Position',[30 30 1800 1450], ...
        'Name',sprintf('All %d EMG gait curves',nChannels));
    layout = tiledlayout(fig,nRows,nColumns, ...
        'TileSpacing','compact','Padding','compact');

    for ii = 1:nChannels
        ax = nexttile(layout); hold(ax,'on'); grid(ax,'on');
        cycleMatrix = reshape(allCycles(ii,:,:), ...
            size(allCycles,2),size(allCycles,3));
        hCycles = plot(ax,x,cycleMatrix,'Color',[0.72 0.72 0.72], ...
            'LineWidth',0.30,'HandleVisibility','off');

        lo = max(0,mu(ii,:)-sd(ii,:));
        hi = mu(ii,:)+sd(ii,:);
        hSD = fill(ax,[x fliplr(x)],[lo fliplr(hi)], ...
            [0.25 0.55 0.90],'FaceAlpha',.20,'EdgeColor','none', ...
            'DisplayName','Mean +/- SD');
        hMean = plot(ax,x,mu(ii,:),'Color',[0 0.25 0.75], ...
            'LineWidth',1.8,'DisplayName','Mean');

        for ev = 2:(numel(eventPct)-1)
            xline(ax,eventPct(ev),':k','HandleVisibility','off');
        end
        xlim(ax,[0 100]);
        xticks(ax,0:20:100);
        title(ax,strrep(names(ii),'_',' '),'Interpreter','none');

        if ii == 1 && ~isempty(hCycles)
            set(hCycles(1),'HandleVisibility','on', ...
                'DisplayName','Individual cycles');
            legend(ax,[hCycles(1),hSD,hMean], ...
                {'Individual cycles','Mean +/- SD','Mean'}, ...
                'Location','best','Box','off');
        end
    end

    xlabel(layout,'Gait cycle (%)');
    ylabel(layout,yLab);
    title(layout,sprintf(['%s | all %d EMG channels | fs = %.2f Hz | ' ...
        '%s'],baseName,nChannels,fsEMG,strjoin(eventNames,' -> ')), ...
        'Interpreter','none');

    allAxes = findall(fig,'Type','axes');
    for ii = 1:numel(allAxes)
        try
            allAxes(ii).Toolbar.Visible = 'off';
        catch
        end
    end
    drawnow;
end

function plotProfileRow(allCycles,mu,sd,names,x,side,yLab,eventPct,eventNames)
    for ii = 1:3
        nexttile; hold on; grid on;

        % Each column is one completely cleaned, time-warped gait cycle.
        cycleMatrix = reshape(allCycles(ii,:,:), ...
            size(allCycles,2), size(allCycles,3));
        hCycles = plot(x,cycleMatrix,'Color',[0.68 0.68 0.68], ...
            'LineWidth',0.35,'HandleVisibility','off');

        % Draw mean +/- SD above the grey cycles. A translucent fill plus
        % boundary lines keeps the band visible without hiding the cycles.
        lo = max(0,mu(ii,:)-sd(ii,:));
        hi = mu(ii,:)+sd(ii,:);
        hSD = fill([x fliplr(x)],[lo fliplr(hi)],[0.25 0.55 0.90], ...
            'FaceAlpha',.22,'EdgeColor','none', ...
            'DisplayName','Mean +/- SD');
        plot(x,lo,'--','Color',[0.25 0.55 0.90], ...
            'LineWidth',0.70,'HandleVisibility','off');
        plot(x,hi,'--','Color',[0.25 0.55 0.90], ...
            'LineWidth',0.70,'HandleVisibility','off');

        hMean = plot(x,mu(ii,:),'Color',[0 0.25 0.75], ...
            'LineWidth',2.6,'DisplayName','Mean');

        % Show a compact legend once per row.
        if ii == 1 && ~isempty(hCycles)
            set(hCycles(1),'HandleVisibility','on','DisplayName','Individual cycles');
            legend([hCycles(1),hSD,hMean], ...
                {'Individual cycles','Mean +/- SD','Mean'}, ...
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

function fig = plotOverlappingEpochWindows(EEGContinuous,anchorLatency, ...
        epochWindow,firstEpoch,displayCount,outDir,baseName)
    % Display retained epochs on the original continuous time axis. Unlike
    % pop_eegplot on epoched data, samples shared by neighbouring epochs are
    % drawn only once and transparent epoch windows visibly overlap.

    nEpochs = numel(anchorLatency);
    if nEpochs == 0
        warning('No clean epoch anchors are available for overlap plotting.');
        fig = gobjects(0);
        return;
    end

    firstEpoch = max(1,min(nEpochs,round(firstEpoch)));
    if isinf(displayCount)
        lastEpoch = nEpochs;
    else
        displayCount = max(1,round(displayCount));
        lastEpoch = min(nEpochs,firstEpoch + displayCount - 1);
    end
    shownEpochs = firstEpoch:lastEpoch;

    fs = EEGContinuous.srate;
    epochStarts = round(anchorLatency(shownEpochs) + epochWindow(1)*fs);
    epochEnds   = round(anchorLatency(shownEpochs) + epochWindow(2)*fs);
    epochStarts = max(1,epochStarts);
    epochEnds   = min(EEGContinuous.pnts,epochEnds);

    displayStart = min(epochStarts);
    displayEnd   = max(epochEnds);
    sampleRange  = displayStart:displayEnd;
    timeSeconds  = (sampleRange - 1) / fs;

    continuousData = double(EEGContinuous.data(:,sampleRange));
    nChannels = size(continuousData,1);

    % Scale each envelope independently only for this stacked diagnostic
    % view. The quantitative time-warped results remain unchanged.
    channelScale = max(continuousData,[],2);
    channelScale(~isfinite(channelScale) | channelScale <= 0) = 1;
    normalizedData = continuousData ./ channelScale;
    channelSpacing = 1.35;
    offsets = (nChannels-1:-1:0)' * channelSpacing;
    stackedData = normalizedData + offsets;
    yBottom = -0.12;
    yTop = offsets(1) + 1.18;

    fig = figure('Color','w','Position',[60 80 1500 760], ...
        'Name','Clean overlapping epochs on continuous timeline');
    ax = axes(fig); hold(ax,'on'); grid(ax,'on');

    % Transparent windows accumulate colour where epochs truly overlap.
    hWindow = gobjects(1);
    for jj = 1:numel(shownEpochs)
        xStart = (epochStarts(jj)-1)/fs;
        xEnd   = (epochEnds(jj)-1)/fs;
        hPatch = patch(ax,[xStart xEnd xEnd xStart], ...
            [yBottom yBottom yTop yTop],[1.00 0.86 0.20], ...
            'FaceAlpha',0.10,'EdgeColor',[0.45 0.45 0.45], ...
            'LineStyle','--','LineWidth',0.55,'HandleVisibility','off');
        if jj == 1
            hWindow = hPatch;
            set(hWindow,'HandleVisibility','on','DisplayName','Clean epoch window');
        end
        text(ax,(xStart+xEnd)/2,yTop-0.02,sprintf('E%d',shownEpochs(jj)), ...
            'HorizontalAlignment','center','VerticalAlignment','top', ...
            'FontSize',8,'Color',[0.30 0.30 0.30], ...
            'Clipping','on');
    end

    plot(ax,timeSeconds,stackedData','Color',[0.05 0.12 0.55], ...
        'LineWidth',0.75,'HandleVisibility','off');

    % Draw gait events at their original continuous latency, but only when
    % they fall inside at least one of the displayed clean epoch windows.
    eventOrder  = {'HS_R','TO_L','HS_L','TO_R'};
    eventColors = [0.00 0.65 0.10; ...
                   0.90 0.00 0.90; ...
                   0.95 0.15 0.10; ...
                   0.00 0.75 0.85];
    eventHandles = gobjects(1,numel(eventOrder));
    allEventTypes = string({EEGContinuous.event.type});
    allEventLatency = [EEGContinuous.event.latency];
    insideDisplayedEpoch = false(size(allEventLatency));
    for jj = 1:numel(shownEpochs)
        insideDisplayedEpoch = insideDisplayedEpoch | ...
            (allEventLatency >= epochStarts(jj) & ...
             allEventLatency <= epochEnds(jj));
    end

    for ev = 1:numel(eventOrder)
        useEvent = allEventTypes == eventOrder{ev} & insideDisplayedEpoch;
        eventLatency = allEventLatency(useEvent);
        for kk = 1:numel(eventLatency)
            eventTime = (eventLatency(kk)-1)/fs;
            hLine = xline(ax,eventTime,'-', ...
                'Color',eventColors(ev,:),'LineWidth',0.85, ...
                'HandleVisibility','off');
            if kk == 1
                eventHandles(ev) = hLine;
                set(eventHandles(ev),'HandleVisibility','on', ...
                    'DisplayName',eventOrder{ev});
            end
            text(ax,eventTime,yTop-0.32,eventOrder{ev}, ...
                'Rotation',90,'HorizontalAlignment','right', ...
                'VerticalAlignment','middle','FontSize',7, ...
                'Color',eventColors(ev,:),'Clipping','on');
        end
    end

    labels = strings(nChannels,1);
    for ch = 1:nChannels
        labels(ch) = string(EEGContinuous.chanlocs(ch).labels);
    end
    yticks(ax,flipud(offsets + 0.45));
    yticklabels(ax,flipud(strrep(labels,'_',' ')));
    ylim(ax,[yBottom yTop]);
    xlim(ax,[timeSeconds(1) timeSeconds(end)]);
    xlabel(ax,'Time from EMG recording start (s)');
    ylabel(ax,'Individually scaled linear envelopes');
    title(ax,sprintf(['%s | clean epochs %d-%d on the original continuous ' ...
        'timeline (darker yellow = overlap)'], ...
        baseName,firstEpoch,lastEpoch),'Interpreter','none');

    validEvent = isgraphics(eventHandles);
    legend(ax,[hWindow eventHandles(validEvent)], ...
        [{'Clean epoch window'},eventOrder(validEvent)], ...
        'Location','eastoutside','Box','off');

    try
        ax.Toolbar.Visible = 'off';
    catch
    end
    drawnow;

    overlapFile = fullfile(outDir,baseName + ...
        "_clean_epochs_overlapping_timeline.png");
    exportgraphics(fig,overlapFile,'Resolution',300);
    fprintf('>> Saved overlapping clean-epoch timeline: %s\n',overlapFile);
end