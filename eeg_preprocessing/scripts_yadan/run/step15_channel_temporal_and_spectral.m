function step15_channel_temporal_and_spectral()
% GOAL
%   Compare conditions at each scalp channel using gait-related potential
%   and power spectral density plots for each subject.
%
% INPUT
%   Step 10: 01_RHS_epoch_manifest.csv and its completed epoched datasets.
%   Preprocessed channel EEG stored in EEG.data in each Step 10 dataset.
%   Signal Processing Toolbox: dpss and pmtm.
%
% APPROACH
%   Reuse each run only when its actual channel data and method match.
%   Apply the pre-RHS baseline to potentials; compute PSD in original time.
%   Combine runs by epoch count and redraw only changed or missing figures.
%
% OUTPUT
%   output_data/10_channel_time_frequency/<subject>/*_temporal_spectral.png
%   output_data/10_channel_time_frequency/<subject>/<subject>_channel_results.mat
%   Per-run results in the existing run_results folder for incremental reuse.
%
% USED BY
%   Channel-level condition comparison and thesis figures.

%% Settings and paths

scriptsRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(scriptsRoot, '-begin');
addpath(fullfile(scriptsRoot, 'config'), '-begin');
P = project_paths();
cfg10 = config_step10_rhs_timewarp();

cfg.forceRecompute = false;
cfg.cyclePercent = 0:100;             % Plotting grid, not a QC threshold.
cfg.timeBaselineWindowMs = [-1000 0]; % Existing pre-RHS baseline window.
cfg.frequencyRangeHz = [0 60];        % Display range only.
cfg.timeHalfBandwidth = 4;            % MATLAB pmtm default.
cfg.inputToMicrovolt = 1;             % EEGLAB data assumed to be in microvolts.
cfg.psdInDecibels = true;

assert(exist('pmtm', 'file') == 2 && exist('dpss', 'file') == 2, ...
    'Signal Processing Toolbox (pmtm and dpss) is required.');
eeglab('nogui');

manifestFile = fullfile(P.outputFolder, cfg10.rhsRootFolderName, cfg10.manifestFileName);
opts = detectImportOptions(manifestFile, 'TextType', 'string');
opts = setvartype(opts, {'Subject', 'ConditionCode', 'ConditionDisplay', ...
    'Status', 'OutputSet'}, 'string');
M = readtable(manifestFile, opts);
M = M((startsWith(M.Status, "completed") | startsWith(M.Status, "reused")) & ...
    M.TimewarpAccepted > 0, :);
M = sortrows(M, {'SubjectOrder', 'ConditionOrder', 'RunNumber'});
subjects = unique(M.Subject, 'stable');
subjects = subjects(hipexo.subject_is_selected(subjects));
M = M(ismember(M.Subject, subjects), :);
assert(~isempty(M), 'No completed Step 10 datasets for the selected subjects.');
assert(all(isfinite(M.RunNumber) & M.RunNumber >= 1 & ...
    M.RunNumber == round(M.RunNumber)), 'Invalid physical run number.');
keys = M.Subject + "|" + M.ConditionCode + "|" + string(M.RunNumber);
assert(numel(unique(lower(M.OutputSet))) == height(M) && ...
    numel(unique(keys)) == height(M), 'Duplicate datasets or subject/condition/run entries.');

conditionOrder = unique([string(cfg10.conditionOrder(:)); M.ConditionCode], 'stable');
palette = [0 0 0; 0 90 200; 230 140 0; 210 35 35; ...
    0 145 75; 125 55 180; 0 165 190; 100 100 100] / 255;
colors = palette(mod(0:numel(conditionOrder)-1, size(palette, 1)) + 1, :);
outputRoot = fullfile(P.outputFolder, '10_channel_time_frequency');

% Display settings do not invalidate run calculations.
method = struct('cyclePercent', cfg.cyclePercent, ...
    'timeBaselineWindowMs', cfg.timeBaselineWindowMs, ...
    'timeHalfBandwidth', cfg.timeHalfBandwidth, ...
    'inputToMicrovolt', cfg.inputToMicrovolt, 'analysisVersion', "time_baseline_v1");

%% Analyze each subject

for s = 1:numel(subjects)
    T = M(M.Subject == subjects(s), :);
    subjectFolder = fullfile(outputRoot, char(subjects(s)));
    cacheFolder = fullfile(subjectFolder, 'run_results');
    if ~isfolder(cacheFolder), mkdir(cacheFolder); end
    resultFile = fullfile(subjectFolder, char(subjects(s) + "_channel_results.mat"));
    previousR = [];
    previousPlotSignature = "";
    if isfile(resultFile)
        try
            saved = load(resultFile, 'R');
            previousR = saved.R;
            previousPlotSignature = string(previousR.plotSignature);
        catch
            % A missing/unreadable subject summary does not invalidate run caches.
            previousR = [];
        end
    end

    R = struct('subject', subjects(s), 'settings', cfg, 'method', method);
    R.inputs = T(:, {'OutputSet', 'ConditionCode', 'ConditionDisplay', ...
        'RunNumber', 'TimewarpAccepted'});
    R.inputs.FileSignature = strings(height(T), 1);
    R.conditionCodes = conditionOrder(ismember(conditionOrder, T.ConditionCode));
    nConditions = numel(R.conditionCodes);
    R.conditionLabels = strings(nConditions, 1);
    R.epochCounts = zeros(1, nConditions);
    R.runCounts = zeros(1, nConditions);
    R.runResults = cell(height(T), 1);
    reference = [];
    computedRuns = 0;

    for r = 1:height(T)
        inputSet = char(T.OutputSet(r));
        assert(isfile(inputSet), 'Missing Step 10 dataset: %s', inputSet);
        [setFolder, setName, setExt] = fileparts(inputSet);
        EEG = pop_loadset('filename', [setName setExt], 'filepath', setFolder);
        assert(string(EEG.subject) == subjects(s) && ...
            string(EEG.condition) == T.ConditionCode(r) && ...
            EEG.trials == T.TimewarpAccepted(r), ...
            'Dataset identity/epoch count does not match the manifest: %s', inputSet);
        assert(isequal(double(EEG.etc.rhs_epoching.run_number), double(T.RunNumber(r))), ...
            'Physical run does not match the manifest: %s', inputSet);

        % Hash actual numerical input. File names, dates, ICA and processing
        % history cannot prove whether EEG.data is unchanged.
        [R.inputs.FileSignature(r), info] = channel_input_signature_local(EEG);
        runIdentity = struct('subject', subjects(s), 'condition', T.ConditionCode(r), ...
            'run', T.RunNumber(r), 'epochCount', T.TimewarpAccepted(r), ...
            'sourceSignature', R.inputs.FileSignature(r), 'method', method);
        signature = hipexo.content_signature(runIdentity);
        runFile = fullfile(cacheFolder, sprintf('%s_%s_run-%02d_channel_run.mat', ...
            char(subjects(s)), char(T.ConditionCode(r)), T.RunNumber(r)));

        runResult = [];
        if ~cfg.forceRecompute && isfile(runFile)
            try
                cached = load(runFile, 'runResult');
                candidate = cached.runResult;
                if string(candidate.signature) == signature && ...
                        candidate.epochCount == EEG.trials && isequaln(candidate.info, info) && ...
                        isequal(size(candidate.meanPotentialUv), [EEG.nbchan, numel(cfg.cyclePercent)]) && ...
                        isequal(size(candidate.meanPsdUv2PerHz), [EEG.nbchan, numel(info.frequencyHz)])
                    runResult = candidate;
                end
            catch
                % Recompute only this run if its cache is unreadable/incomplete.
            end
        end
        if isempty(runResult)
            [timeSum, psdSum] = analyze_dataset_local(EEG, cfg, info);
            runResult = struct('signature', signature, 'identity', runIdentity, ...
                'info', info, 'epochCount', EEG.trials, ...
                'meanPotentialUv', timeSum / EEG.trials, ...
                'meanPsdUv2PerHz', psdSum / EEG.trials);
            save(runFile, 'runResult', '-v7');
            computedRuns = computedRuns + 1;
        end
        clear EEG timeSum psdSum cached candidate

        if isempty(reference)
            reference = info;
            R.channelLabels = info.channelLabels;
            R.cyclePercent = cfg.cyclePercent;
            R.frequencyHz = info.frequencyHz;
            R.epochTimeMs = info.epochTimeMs;
            R.samplingRateHz = info.samplingRateHz;
            R.psdHalfBandwidthHz = cfg.timeHalfBandwidth / ...
                (numel(info.epochTimeMs) / info.samplingRateHz);
            R.meanPotentialUv = zeros([size(runResult.meanPotentialUv), nConditions]);
            R.meanPsdUv2PerHz = zeros([size(runResult.meanPsdUv2PerHz), nConditions]);
        else
            assert(isequaln(info, reference), ...
                'Runs must have matching channel order, epoch times and sampling rates.');
        end
        R.runResults{r} = runResult;
        c = find(R.conditionCodes == T.ConditionCode(r), 1);
        R.conditionLabels(c) = T.ConditionDisplay(r);
        R.meanPotentialUv(:, :, c) = R.meanPotentialUv(:, :, c) + ...
            runResult.meanPotentialUv * runResult.epochCount;
        R.meanPsdUv2PerHz(:, :, c) = R.meanPsdUv2PerHz(:, :, c) + ...
            runResult.meanPsdUv2PerHz * runResult.epochCount;
        R.epochCounts(c) = R.epochCounts(c) + runResult.epochCount;
        R.runCounts(c) = R.runCounts(c) + 1;
    end
    for c = 1:nConditions
        R.meanPotentialUv(:, :, c) = R.meanPotentialUv(:, :, c) / R.epochCounts(c);
        R.meanPsdUv2PerHz(:, :, c) = R.meanPsdUv2PerHz(:, :, c) / R.epochCounts(c);
    end
    R.signalDescription = 'Preprocessed channel EEG from Step 10 EEG.data';
    R.timeDescription = sprintf(['Signed potential; per-epoch channel mean baseline ' ...
        'from %g to %g ms relative to RHS; then linear RHS-to-RHS normalization ' ...
        'and epoch-weighted averaging.'], cfg.timeBaselineWindowMs);
    R.psdDescription = ['Adaptive multitaper PSD of full unwarped Step 10 epochs ' ...
        'after per-epoch mean removal; linear averaging weighted by epoch count. ' ...
        'Run means and epoch counts are retained. Overlapping epochs are not ' ...
        'independent statistical samples.'];

    % Describe what is drawn, excluding file paths and unrelated metadata.
    [~, colorIndex] = ismember(R.conditionCodes, conditionOrder);
    subjectColors = colors(colorIndex, :);
    displayDefinition = struct('subject', R.subject, 'channelLabels', R.channelLabels, ...
        'cyclePercent', R.cyclePercent, 'frequencyHz', R.frequencyHz, ...
        'conditionCodes', R.conditionCodes, 'conditionLabels', R.conditionLabels, ...
        'meanPotentialUv', R.meanPotentialUv, 'meanPsdUv2PerHz', R.meanPsdUv2PerHz, ...
        'epochCounts', R.epochCounts, 'frequencyRangeHz', cfg.frequencyRangeHz, ...
        'psdInDecibels', cfg.psdInDecibels, 'colors', subjectColors);
    R.plotSignature = hipexo.content_signature(displayDefinition);
    plot_subject_local(R, subjectFolder, subjectColors, ...
        cfg.forceRecompute || previousPlotSignature ~= R.plotSignature);
    % Save once after plotting succeeds; leave an identical summary untouched.
    if cfg.forceRecompute || ~isequaln(previousR, R)
        save(resultFile, 'R', '-v7');
    end
    fprintf('%s: calculated %d runs, reused %d runs.\n', ...
        char(subjects(s)), computedRuns, height(T) - computedRuns);
end
fprintf('Channel analysis finished:\n%s\n', outputRoot);
end

%% Identify the actual channel input

function [signature, info] = channel_input_signature_local(EEG)
    meta = EEG.etc.rhs_epoching;
    assert(~meta.signal_timewarped && isequal(string(meta.timewarp_event_order(:)), ...
        ["RHS"; "LTO"; "LHS"; "RTO"; "RHS"]), 'Unexpected Step 10 epoch/timewarp format.');
    assert(isequal([size(EEG.data, 1), size(EEG.data, 2), size(EEG.data, 3)], ...
        double([EEG.nbchan, EEG.pnts, EEG.trials])), 'EEG.data dimensions do not match its header.');
    info.channelLabels = string({EEG.chanlocs.labels})';
    info.epochTimeMs = double(EEG.times(:));
    info.samplingRateHz = double(EEG.srate);
    assert(numel(info.channelLabels) == EEG.nbchan && ...
        numel(info.epochTimeMs) == EEG.pnts && all(isfinite(info.epochTimeMs)) && ...
        all(diff(info.epochTimeMs) > 0) && isfinite(info.samplingRateHz) && ...
        info.samplingRateHz > 0, 'Invalid channel labels, epoch times or sampling rate.');
    latencies = double(EEG.timewarp.latencies);
    assert(isequal(size(latencies), [EEG.trials, 5]) && all(isfinite(latencies(:))) && ...
        all(diff(latencies, 1, 2) > 0, 'all') && ...
        all(latencies(:, 1) >= info.epochTimeMs(1)) && ...
        all(latencies(:, end) <= info.epochTimeMs(end)), 'Invalid Step 10 gait-event latencies.');
    nfft = 2^nextpow2(EEG.pnts);
    info.frequencyHz = (0:nfft/2)' * info.samplingRateHz / nfft;

    % Hash one epoch at a time to avoid copying the whole dataset to double.
    digest = java.security.MessageDigest.getInstance('SHA-256');
    for tr = 1:EEG.trials
        x = double(EEG.data(:, :, tr));
        assert(isreal(x) && all(isfinite(x(:))), ...
            'Non-finite or complex channel data in epoch %d.', tr);
        x(x == 0) = 0; % +0 and -0 represent the same numerical input.
        digest.update(typecast(x(:), 'int8'));
    end
    bytes = typecast(digest.digest(), 'uint8');
    dataHash = lower(reshape(dec2hex(bytes, 2).', 1, []));
    signature = hipexo.content_signature(struct('dataSHA256', dataHash, ...
        'dataSize', double([EEG.nbchan, EEG.pnts, EEG.trials]), ...
        'channelLabels', info.channelLabels, 'epochTimeMs', info.epochTimeMs, ...
        'samplingRateHz', info.samplingRateHz, 'gaitLatenciesMs', latencies));
end

%% Analyze one run

function [timeSum, psdSum] = analyze_dataset_local(EEG, cfg, info)
    baselineMask = info.epochTimeMs >= cfg.timeBaselineWindowMs(1) & ...
        info.epochTimeMs <= cfg.timeBaselineWindowMs(2);
    assert(any(baselineMask) && info.epochTimeMs(1) <= cfg.timeBaselineWindowMs(1) && ...
        info.epochTimeMs(end) >= cfg.timeBaselineWindowMs(2), ...
        'Step 10 epoch does not cover the requested time-domain baseline.');
    latencies = double(EEG.timewarp.latencies);
    nfft = 2^nextpow2(EEG.pnts);
    [tapers, eigenvalues] = dpss(EEG.pnts, cfg.timeHalfBandwidth);
    timeSum = zeros(EEG.nbchan, numel(cfg.cyclePercent));
    psdSum = zeros(EEG.nbchan, numel(info.frequencyHz));

    for tr = 1:EEG.trials
        x = double(EEG.data(:, :, tr)) * cfg.inputToMicrovolt;
        % Per-epoch pre-RHS baseline, followed by linear RHS-to-RHS alignment.
        xTime = x - mean(x(:, baselineMask), 2);
        queryMs = latencies(tr, 1) + cfg.cyclePercent / 100 * ...
            (latencies(tr, end) - latencies(tr, 1));
        cycle = interp1(info.epochTimeMs, xTime', queryMs(:), 'linear');
        timeSum = timeSum + cycle';

        % Absolute PSD in original time; remove only each epoch's DC offset.
        x = x - mean(x, 2);
        pxx = pmtm(x', tapers, eigenvalues, nfft, EEG.srate, 'onesided', 'adapt');
        assert(all(isfinite(pxx(:))), 'Non-finite PSD estimate in epoch %d.', tr);
        psdSum = psdSum + pxx';
    end
end

%% Plot conditions at each channel

function plot_subject_local(R, subjectFolder, colors, overwrite)
    legendLabels = R.conditionLabels + " (n=" + string(R.epochCounts(:)) + ")";
    channelNames = regexprep(R.channelLabels, '[^A-Za-z0-9_-]', '_');
    assert(numel(unique(lower(channelNames))) == numel(channelNames), ...
        'Channel labels would produce duplicate figure filenames.');

    for ch = 1:numel(R.channelLabels)
        pngFile = fullfile(subjectFolder, sprintf('%s_%s_temporal_spectral.png', ...
            char(R.subject), char(channelNames(ch))));
        if ~overwrite && isfile(pngFile), continue; end
        fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1250 500]);
        closeFigure = onCleanup(@() close(fig));
        layout = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
        axTime = nexttile(layout);
        hold(axTime, 'on');
        axPsd = nexttile(layout);
        hold(axPsd, 'on');
        handles = gobjects(numel(R.conditionCodes), 1);

        for c = 1:numel(R.conditionCodes)
            handles(c) = plot(axTime, R.cyclePercent, R.meanPotentialUv(ch, :, c), ...
                'Color', colors(c, :), 'LineStyle', '-', 'LineWidth', 1.8);
            y = R.meanPsdUv2PerHz(ch, :, c);
            if R.settings.psdInDecibels, y = 10 * log10(max(y, realmin('double'))); end
            plot(axPsd, R.frequencyHz, y, ...
                'Color', colors(c, :), 'LineStyle', '-', 'LineWidth', 1.8);
        end
        yline(axTime, 0, ':', 'Color', [0.6 0.6 0.6], 'HandleVisibility', 'off');
        xlim(axTime, [0 100]);
        xticks(axTime, 0:20:100);
        xlabel(axTime, 'Gait cycle (%)');
        ylabel(axTime, 'Amplitude (\muV)');
        title(axTime, 'Gait-related potential');
        xlim(axPsd, R.settings.frequencyRangeHz);
        xlabel(axPsd, 'Frequency (Hz)');
        if R.settings.psdInDecibels
            ylabel(axPsd, 'PSD (dB re 1 \muV^2/Hz)');
        else
            ylabel(axPsd, 'PSD (\muV^2/Hz)');
        end
        title(axPsd, 'Power spectral density');
        set([axTime axPsd], 'FontSize', 11, 'Box', 'off', 'XGrid', 'on', 'YGrid', 'on');
        title(layout, char(R.subject + " | " + R.channelLabels(ch)), 'Interpreter', 'none');
        lgd = legend(axTime, handles, cellstr(legendLabels), 'Interpreter', 'none', ...
            'NumColumns', 4, 'Box', 'off');
        lgd.Layout.Tile = 'south';
        exportgraphics(fig, pngFile, 'Resolution', 200);
        clear closeFigure
    end
end
