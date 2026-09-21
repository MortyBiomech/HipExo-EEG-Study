%% Compare gait-cycle EMG curves from every existing session
% The script reads subject/day/path settings from config_paths.m, then scans
% save_path/ses-* for existing *_emg_timewarped.mat files.
% Missing conditions are allowed; the script never assumes eight sessions.

clearvars;
close all;
clc;

%% ------------------------- USER SETTINGS -------------------------------
% Load the same subject and day that were used by the processing pipeline.
% This makes rootDir point to, for example:
% C:\2026SSArbeit\data\PilotTest2\Sub-P2_4\day2\processed_EMG
scriptDir = fileparts(mfilename('fullpath'));
configFile = fullfile(scriptDir, 'config_paths.m');
if exist(configFile, 'file') ~= 2
    configFile = which('config_paths.m');
end
assert(exist(configFile, 'file') == 2, ...
    'config_paths.m was not found beside this script or on the MATLAB path: %s', ...
    configFile);
run(configFile);
rootDir = save_path;

runFilter = "";                       % e.g. "run-001"; "" keeps every run
showStdBands = true;                  % mean +/- one standard deviation
makeOverviewFigure = true;            % one 22-panel comparison figure
makeIndividualFigures = true;         % one comparison figure per channel
showFigures = true;                   % false = save without opening windows
closeAfterSaving = false;              % true prevents many open windows

lineWidth = 2.2;
stdAlpha = 0.10;
outputDir = fullfile(rootDir, 'gait_cycle_session_comparison');
%% -----------------------------------------------------------------------

if ~exist(outputDir, 'dir'), mkdir(outputDir); end

resultFiles = dir(fullfile(rootDir, '**', '*_emg_timewarped.mat'));
if strlength(runFilter) > 0 && ~isempty(resultFiles)
    fullNames = string(arrayfun(@(f) fullfile(f.folder, f.name), ...
        resultFiles, 'UniformOutput', false));
    resultFiles = resultFiles(contains(fullNames, runFilter, ...
        'IgnoreCase', true));
end

assert(~isempty(resultFiles), ...
    ['No *_emg_timewarped.mat files were found below:\n%s\n' ...
     'Check current_subject, subject_folder and experiment_day in config_paths.m.'], ...
    rootDir);

sessionData = struct( ...
    'SessionName', {}, 'Condition', {}, 'StyleOrder', {}, ...
    'Color', {}, 'LineStyle', {}, 'File', {}, ...
    'Labels', {}, 'GaitPct', {}, 'Mean', {}, 'Std', {}, ...
    'IsNormalized', {});

fprintf('Scanning %d time-warped result file(s) below:\n%s\n', ...
    numel(resultFiles), rootDir);

for fileIndex = 1:numel(resultFiles)
    sourceFile = fullfile(resultFiles(fileIndex).folder, ...
        resultFiles(fileIndex).name);
    sessionName = getSessionName(sourceFile);
    [conditionName, colorValue, lineStyle, styleOrder, isKnown] = ...
        getSessionStyle(sessionName);

    if ~isKnown
        warning('Skipping unrecognized session "%s": %s', ...
            sessionName, sourceFile);
        continue;
    end

    inventory = whos('-file', sourceFile);
    availableVariables = {inventory.name};
    wantedVariables = intersect( ...
        {'sensorMap','gaitPct','meanAll','stdAll','plotAllProfiles','EEG'}, ...
        availableVariables, 'stable');
    loaded = load(sourceFile, wantedVariables{:});

    [labels, gaitPct, meanProfiles, stdProfiles, isNormalized] = ...
        readSessionProfiles(loaded, sourceFile);

    item = numel(sessionData) + 1;
    sessionData(item).SessionName = string(sessionName);
    sessionData(item).Condition = conditionName;
    sessionData(item).StyleOrder = styleOrder;
    sessionData(item).Color = colorValue;
    sessionData(item).LineStyle = lineStyle;
    sessionData(item).File = string(sourceFile);
    sessionData(item).Labels = labels;
    sessionData(item).GaitPct = gaitPct;
    sessionData(item).Mean = meanProfiles;
    sessionData(item).Std = stdProfiles;
    sessionData(item).IsNormalized = isNormalized;
end

assert(~isempty(sessionData), ...
    'No recognized sessions remained after reading the result files.');

% Always display and plot the conditions in the requested order, regardless
% of the order returned by dir(). Sessions that do not exist are simply absent.
sortMatrix = [[sessionData.StyleOrder]' (1:numel(sessionData))'];
[~, sortIndex] = sortrows(sortMatrix, [1 2]);
sessionData = sessionData(sortIndex);

fprintf('\nExisting sessions that will be plotted:\n');
disp(table((1:numel(sessionData))', ...
    string({sessionData.SessionName})', ...
    string({sessionData.Condition})', ...
    string({sessionData.File})', ...
    'VariableNames', {'PlotOrder','Session','Condition','ResultFile'}));

masterLabels = strings(0,1);
for sessionIndex = 1:numel(sessionData)
    currentLabels = sessionData(sessionIndex).Labels(:);
    for labelIndex = 1:numel(currentLabels)
        if ~any(strcmpi(masterLabels, currentLabels(labelIndex)))
            masterLabels(end+1,1) = currentLabels(labelIndex); %#ok<SAGROW>
        end
    end
end

assert(numel(masterLabels) == 22, ...
    ['Expected 22 unique EMG channel labels across the available sessions, ' ...
     'but found %d.'], numel(masterLabels));

normalizationFlags = [sessionData.IsNormalized];
if all(normalizationFlags)
    yAxisLabel = 'Linear envelope (% of valid-cycle maximum)';
elseif ~any(normalizationFlags)
    yAxisLabel = 'Linear envelope (stored units)';
else
    yAxisLabel = 'Linear envelope (mixed scaling)';
    warning(['Some sessions appear normalized and others do not. ' ...
        'Their amplitudes should not be compared directly.']);
end

visibility = 'off';
if showFigures, visibility = 'on'; end

%% One overview containing all 22 EMG channels
if makeOverviewFigure
    overview = figure('Color', 'w', 'Visible', visibility, ...
        'Position', [40 40 1850 1100], ...
        'Name', 'Existing-session EMG gait-cycle comparison');
    layout = tiledlayout(5, 5, 'TileSpacing', 'compact', ...
        'Padding', 'compact');

    legendHandles = gobjects(numel(sessionData),1);
    firstAxes = gobjects(1);

    for channelIndex = 1:numel(masterLabels)
        ax = nexttile(layout);
        hold(ax, 'on');
        if channelIndex == 1, firstAxes = ax; end

        for sessionIndex = 1:numel(sessionData)
            [x, meanCurve, ~, exists] = getChannelCurve( ...
                sessionData(sessionIndex), masterLabels(channelIndex));
            if ~exists, continue; end
            h = plot(ax, x, meanCurve, ...
                'Color', sessionData(sessionIndex).Color, ...
                'LineStyle', sessionData(sessionIndex).LineStyle, ...
                'LineWidth', lineWidth);
            if channelIndex == 1
                legendHandles(sessionIndex) = h;
            end
        end

        title(ax, masterLabels(channelIndex), 'Interpreter', 'none', ...
            'FontSize', 9);
        xlim(ax, [0 100]);
        grid(ax, 'on');
        box(ax, 'on');
        if channelIndex > 17, xlabel(ax, 'Gait cycle (%)'); end
        if mod(channelIndex-1,5) == 0, ylabel(ax, 'EMG'); end
    end

    validLegend = isgraphics(legendHandles);
    legendText = string({sessionData.SessionName});
    if any(validLegend)
        lgd = legend(firstAxes, legendHandles(validLegend), ...
            legendText(validLegend), 'Interpreter', 'none', ...
            'Location', 'eastoutside');
        lgd.Layout.Tile = 'east';
    end
    title(layout, 'Available-session EMG gait-cycle comparison');
    xlabel(layout, 'Gait cycle (%)');
    ylabel(layout, yAxisLabel);

    hideAxesToolbars(overview);
    exportgraphics(overview, fullfile(outputDir, ...
        'all_22_channels_session_comparison.png'), 'Resolution', 250);
    savefig(overview, fullfile(outputDir, ...
        'all_22_channels_session_comparison.fig'));
    if closeAfterSaving, close(overview); end
end

%% One detailed figure per channel, including standard-deviation bands
if makeIndividualFigures
    for channelIndex = 1:numel(masterLabels)
        channelLabel = masterLabels(channelIndex);
        fig = figure('Color', 'w', 'Visible', visibility, ...
            'Position', [100 100 1100 650], ...
            'Name', char(channelLabel));
        ax = axes(fig);
        hold(ax, 'on');

        legendHandles = gobjects(0);
        legendText = strings(0,1);
        for sessionIndex = 1:numel(sessionData)
            [x, meanCurve, stdCurve, exists] = getChannelCurve( ...
                sessionData(sessionIndex), channelLabel);
            if ~exists, continue; end

            if showStdBands
                upperCurve = meanCurve + stdCurve;
                lowerCurve = max(0, meanCurve - stdCurve);
                patch(ax, [x fliplr(x)], ...
                    [upperCurve fliplr(lowerCurve)], ...
                    sessionData(sessionIndex).Color, ...
                    'EdgeColor', 'none', 'FaceAlpha', stdAlpha, ...
                    'HandleVisibility', 'off');
            end

            h = plot(ax, x, meanCurve, ...
                'Color', sessionData(sessionIndex).Color, ...
                'LineStyle', sessionData(sessionIndex).LineStyle, ...
                'LineWidth', lineWidth);
            legendHandles(end+1,1) = h; %#ok<SAGROW>
            legendText(end+1,1) = sessionData(sessionIndex).SessionName; %#ok<SAGROW>
        end

        xlim(ax, [0 100]);
        xlabel(ax, 'Gait cycle (%)');
        ylabel(ax, yAxisLabel);
        title(ax, "Session comparison: " + channelLabel, ...
            'Interpreter', 'none');
        grid(ax, 'on');
        box(ax, 'on');
        if ~isempty(legendHandles)
            legend(ax, legendHandles, legendText, ...
                'Interpreter', 'none', 'Location', 'eastoutside');
        end

        hideAxesToolbars(fig);
        safeLabel = regexprep(char(channelLabel), '[^A-Za-z0-9_-]', '_');
        exportgraphics(fig, fullfile(outputDir, ...
            ['gait_cycle_' safeLabel '.png']), 'Resolution', 300);
        savefig(fig, fullfile(outputDir, ...
            ['gait_cycle_' safeLabel '.fig']));
        if closeAfterSaving, close(fig); end
    end
end

fprintf('\nFinished. Comparison figures were saved in:\n%s\n', outputDir);

%% ----------------------------- FUNCTIONS -------------------------------
function [labels, gaitPct, meanProfiles, stdProfiles, isNormalized] = ...
        readSessionProfiles(loaded, sourceFile)
    if isfield(loaded, 'sensorMap') && ...
            ismember('Muscle', loaded.sensorMap.Properties.VariableNames)
        labels = string(loaded.sensorMap.Muscle(:));
    elseif isfield(loaded, 'EEG') && isfield(loaded.EEG, 'chanlocs')
        labels = string({loaded.EEG.chanlocs.labels})';
    else
        error('No channel labels were found in: %s', sourceFile);
    end

    if isfield(loaded, 'meanAll')
        meanProfiles = double(loaded.meanAll);
        if isfield(loaded, 'stdAll')
            stdProfiles = double(loaded.stdAll);
        else
            stdProfiles = zeros(size(meanProfiles));
            warning('stdAll is missing; using zero-width SD bands: %s', ...
                sourceFile);
        end
    elseif isfield(loaded, 'plotAllProfiles')
        profiles = double(loaded.plotAllProfiles);
        meanProfiles = mean(profiles, 3, 'omitnan');
        stdProfiles = std(profiles, 0, 3, 'omitnan');
    else
        error(['Neither meanAll nor plotAllProfiles was found in: %s. ' ...
            'Use the *_emg_timewarped.mat output from the current pipeline.'], ...
            sourceFile);
    end

    if size(meanProfiles,1) ~= numel(labels) && ...
            size(meanProfiles,2) == numel(labels)
        meanProfiles = meanProfiles.';
        stdProfiles = stdProfiles.';
    end
    assert(size(meanProfiles,1) == numel(labels), ...
        'Channel labels and profile rows do not match in: %s', sourceFile);
    assert(isequal(size(meanProfiles), size(stdProfiles)), ...
        'meanAll and stdAll sizes do not match in: %s', sourceFile);

    if isfield(loaded, 'gaitPct')
        gaitPct = double(loaded.gaitPct(:)');
    else
        gaitPct = linspace(0, 100, size(meanProfiles,2));
    end
    assert(numel(gaitPct) == size(meanProfiles,2), ...
        'gaitPct length and profile length do not match in: %s', sourceFile);

    isNormalized = false;
    if isfield(loaded, 'plotAllProfiles')
        profiles = double(loaded.plotAllProfiles);
        peakByChannel = max(reshape(profiles, size(profiles,1), []), ...
            [], 2, 'omitnan');
        usable = isfinite(peakByChannel) & peakByChannel > 0;
        if any(usable)
            isNormalized = all(abs(peakByChannel(usable) - 100) < 1e-3);
        end
    end
end

function [x, meanCurve, stdCurve, exists] = ...
        getChannelCurve(sessionItem, channelLabel)
    channelRow = find(strcmpi(sessionItem.Labels, channelLabel), 1);
    exists = ~isempty(channelRow);
    if ~exists
        x = [];
        meanCurve = [];
        stdCurve = [];
        return;
    end
    x = sessionItem.GaitPct(:)';
    meanCurve = sessionItem.Mean(channelRow,:);
    stdCurve = sessionItem.Std(channelRow,:);
end

function sessionName = getSessionName(filePath)
    normalizedPath = strrep(char(filePath), '\', '/');
    tokens = regexp(normalizedPath, '(?i)(ses-[^/]+)', 'tokens');
    if ~isempty(tokens)
        sessionName = string(tokens{end}{1});
        return;
    end

    [~, fileName] = fileparts(normalizedPath);
    token = regexp(fileName, '(?i)(ses-[^_]+)', 'tokens', 'once');
    if ~isempty(token)
        sessionName = string(token{1});
    else
        sessionName = string(fileName);
    end
end

function [conditionName, colorValue, lineStyle, styleOrder, isKnown] = ...
        getSessionStyle(sessionName)
    % Remove separators so names such as aqua-plus, aqua_plus and aquaplus
    % are treated identically. Check aquaplus before aqua.
    key = lower(regexprep(char(sessionName), '[^A-Za-z0-9]', ''));
    conditionName = "";
    colorValue = [0.45 0.45 0.45];
    lineStyle = '-';
    styleOrder = 99;
    isKnown = true;

    if contains(key, 'noexopre') || endsWith(key, 'pre')
        conditionName = "NoExoPre";
        colorValue = [0.00 0.00 0.00];
        lineStyle = '-';
        styleOrder = 1;
    elseif contains(key, 'noexopost') || endsWith(key, 'post')
        conditionName = "NoExoPost";
        colorValue = [0.00 0.00 0.00];
        lineStyle = '--';
        styleOrder = 2;
    elseif contains(key, 'aquaplus')
        conditionName = "aqua plus";
        colorValue = [0.55 0.00 0.00];
        styleOrder = 3;
    elseif contains(key, 'aqua')
        conditionName = "aqua";
        colorValue = [0.95 0.20 0.20];
        styleOrder = 4;
    elseif contains(key, 'transparent')
        conditionName = "transparent";
        colorValue = [0.15 0.60 0.25];
        styleOrder = 5;
    elseif contains(key, 'eco')
        conditionName = "eco";
        colorValue = [0.55 0.78 1.00];
        styleOrder = 6;
    elseif contains(key, 'sport')
        conditionName = "sport";
        colorValue = [0.00 0.40 0.85];
        styleOrder = 7;
    elseif contains(key, 'boost')
        conditionName = "boost";
        colorValue = [0.00 0.10 0.55];
        styleOrder = 8;
    else
        isKnown = false;
    end
end

function hideAxesToolbars(fig)
    axesHandles = findall(fig, 'Type', 'axes');
    for ii = 1:numel(axesHandles)
        try
            axesHandles(ii).Toolbar.Visible = 'off';
        catch
        end
    end
    drawnow;
end