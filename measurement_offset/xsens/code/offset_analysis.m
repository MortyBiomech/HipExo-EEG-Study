%% XDF offset analysis workflow
% 1. Scan all XDF files.
% 2. Find the Arduino_TTL_Markers and Xsens_TriggerIn streams.
% 3. Calculate the offset between Xsens and Arduino timestamps.
% 4. Compute offset statistics for each file.
% 5. Plot TTL pulse alignment and per-file mean offset with STD error bars.

clear; clc; close all;

projectFolder = 'E:\master_thesis\imu_to_lsl';
addpath(genpath(fullfile(projectFolder, 'xdf-Matlab')));

dataFolder = fullfile(projectFolder, 'sub-P001');
files = dir(fullfile(dataFolder, '**', '*.xdf'));

fprintf('Found %d XDF files.\n', length(files));

if isempty(files)
    error('No XDF files found. Please check dataFolder path.');
end

all_stats = table();
valid_files = struct('filename', {}, 'name', {}, 'arduino_ts', {}, 'xsens_ts', {}, 'offset_ms', {});

for f = 1:length(files)

    filename = fullfile(files(f).folder, files(f).name);
    fprintf('\nAnalyzing file %d/%d: %s\n', f, length(files), files(f).name);

    try
        streams = load_xdf(filename);
    catch
        fprintf('Skipped: cannot load file.\n');
        continue;
    end

    arduino_ts = [];% arduino timestamp
    xsens_ts = [];%xsens timestamp

    for i = 1:length(streams)

        name = streams{i}.info.name;

        if iscell(name)
            name = name{1};
        end

        if isstring(name)
            name = char(name);
        end

        if strcmp(name, 'Arduino_TTL_Markers')
            arduino_ts = streams{i}.time_stamps(:);
        end

        if strcmp(name, 'Xsens_TriggerIn')
            xsens_ts = streams{i}.time_stamps(:);
        end
    end

    if isempty(arduino_ts) || isempty(xsens_ts)

        fprintf('Skipped: missing Arduino_TTL_Markers or Xsens_TriggerIn\n');

        temp = table( ...
            string(files(f).name), ...
            NaN, NaN, NaN, ...
            NaN, NaN, NaN, NaN, NaN, ...
            NaN, NaN, NaN, NaN, NaN, ...
            'VariableNames', {'FileName',...
            'N_Total', 'N_Outliers', 'N_AfterOutlierRemoval', ...
            'Mean_ms', 'Median_ms', 'Std_ms', 'Min_ms', 'Max_ms', ...
            'Mean_ms_NoOutlier', 'Median_ms_NoOutlier', 'Std_ms_NoOutlier', ...
            'Min_ms_NoOutlier', 'Max_ms_NoOutlier'});

        all_stats = [all_stats; temp];
        continue;
    end

    % assume the first Arduino pulse corresponds to the first Xsens pulse.
    % truncate the longer array to match the shorter one.
    n = min(length(arduino_ts), length(xsens_ts));

    arduino_ts = arduino_ts(1:n);
    xsens_ts = xsens_ts(1:n);

    offset_ms = (xsens_ts - arduino_ts) * 1000;

    if n >= 3
        outlier_idx = isoutlier(offset_ms, 'median');
    else
        outlier_idx = false(size(offset_ms));
    end

    offset_ms_clean = offset_ms(~outlier_idx);

    n_outliers = sum(outlier_idx);
    n_clean = length(offset_ms_clean);
   

    if n_clean > 0
        mean_ms_clean = mean(offset_ms_clean);
        median_ms_clean = median(offset_ms_clean);
        std_ms_clean = std(offset_ms_clean);
        min_ms_clean = min(offset_ms_clean);
        max_ms_clean = max(offset_ms_clean);
    else
        mean_ms_clean = NaN;
        median_ms_clean = NaN;
        std_ms_clean = NaN;
        min_ms_clean = NaN;
        max_ms_clean = NaN;
    end

    temp = table( ...
        string(files(f).name), ...
        n, n_outliers, ...
        mean(offset_ms), median(offset_ms), std(offset_ms), min(offset_ms), max(offset_ms), ...
        mean_ms_clean, median_ms_clean, std_ms_clean, min_ms_clean, max_ms_clean, ...
        'VariableNames', {'FileName', ...
        'N_Total', 'N_Outliers', ...
        'Mean_ms', 'Median_ms', 'Std_ms', 'Min_ms', 'Max_ms', ...
        'Mean_ms_NoOutlier', 'Median_ms_NoOutlier', 'Std_ms_NoOutlier', ...
        'Min_ms_NoOutlier', 'Max_ms_NoOutlier'});

    all_stats = [all_stats; temp];

    % Store valid file information and offset data for later plots
    valid_files(end+1).filename = filename;              % Full XDF file path
    valid_files(end).name = files(f).name;               % XDF file name
    valid_files(end).arduino_ts = arduino_ts;            % Arduino marker timestamps
    valid_files(end).xsens_ts = xsens_ts;                % Xsens TriggerIn timestamps
    valid_files(end).offset_ms = offset_ms;              % Raw Xsens-Arduino offsets in ms
    valid_files(end).offset_ms_clean = offset_ms_clean;  % Offsets after outlier removal
    valid_files(end).arduino_ts_clean = arduino_ts(~outlier_idx); % Arduino timestamps after removing outlier markers
end

disp(all_stats);

outputFile = fullfile(projectFolder, 'xsens_arduino_offset_statistics.csv');
writetable(all_stats, outputFile);

fprintf('\nSaved result file:\n%s\n', outputFile);

%% plot TTL-Pulse

if isempty(valid_files)
    error('No valid files with both Arduino_TTL_Markers and Xsens_TriggerIn were found.');
end

randomFileIndex = randi(length(valid_files));

selectedName = valid_files(randomFileIndex).name;
selectedFile = valid_files(randomFileIndex).filename;
arduino_ts = valid_files(randomFileIndex).arduino_ts;
xsens_ts = valid_files(randomFileIndex).xsens_ts;
offset_ms = valid_files(randomFileIndex).offset_ms;

n = length(offset_ms);

fprintf('\nRandomly selected file for TTL pulse plot:\n%s\n', selectedFile);
fprintf('Number of paired markers: %d\n', n);
fprintf('Mean offset: %.3f ms\n', mean(offset_ms));
fprintf('Median offset: %.3f ms\n', median(offset_ms));
fprintf('Std offset: %.3f ms\n', std(offset_ms));

ttlWidthMs = 100;
windowMs = 6000;

markerIndex = randi(n);

windowBeforeMs = 200;% to start 200ms before the selected Marker

centerTime = arduino_ts(markerIndex);

segmentStart = centerTime - windowBeforeMs / 1000;
segmentEnd = segmentStart + windowMs / 1000;

idxInWindow = find(arduino_ts >= segmentStart & arduino_ts <= segmentEnd);

%Convert the absolute timestamp to a relative time within the window, ms.
relative_arduino_ms = (arduino_ts - segmentStart) * 1000;
relative_xsens_ms = (xsens_ts - segmentStart) * 1000;

figure('Position', [100, 100, 1000, 500]);
hold on; grid on;

plot([0 windowMs], [0 0], 'k', 'LineWidth', 0.8, 'HandleVisibility', 'off');
plot([0 windowMs], [1.5 1.5], 'k', 'LineWidth', 0.8, 'HandleVisibility', 'off');

hArduino = [];
hXsens = [];

for j = 1:length(idxInWindow)

    k = idxInWindow(j);

    % XDF only stores a single timestamp per trigger. 
    % create a square wave (4 points) to visually simulate a TTL pulse.
    arduino_start_ms = relative_arduino_ms(k);
    arduino_end_ms = arduino_start_ms + ttlWidthMs;

    xsens_start_ms = relative_xsens_ms(k);
    xsens_end_ms = xsens_start_ms + ttlWidthMs;

    t_arduino = [arduino_start_ms, arduino_start_ms, arduino_end_ms, arduino_end_ms];
    y_arduino = [0, 1, 1, 0];

    t_xsens = [xsens_start_ms, xsens_start_ms, xsens_end_ms, xsens_end_ms];
    y_xsens = [1.5, 2.5, 2.5, 1.5];

    if j == 1
        hArduino = plot(t_arduino, y_arduino, 'b', 'LineWidth', 2);
        hXsens = plot(t_xsens, y_xsens, 'r', 'LineWidth', 2);
    else
        plot(t_arduino, y_arduino, 'b', 'LineWidth', 2, 'HandleVisibility', 'off');
        plot(t_xsens, y_xsens, 'r', 'LineWidth', 2, 'HandleVisibility', 'off');
    end

    plot([arduino_start_ms xsens_start_ms], [1.15 1.15], 'k-', ...
        'LineWidth', 1.2, 'HandleVisibility', 'off');

    text(arduino_start_ms, 1.25, sprintf('%.1f ms', offset_ms(k)), ...
        'FontSize', 9, 'Color', 'k');
end

xline(windowBeforeMs, '--k', 'LineWidth', 1.2, 'HandleVisibility', 'off');

xlim([0 windowMs]);
ylim([-0.3, 2.8]);

yticks([0.5, 2.0]);
yticklabels({'Arduino TTL', 'Xsens TriggerIn'});

xlabel(sprintf('Time within randomly selected %d ms segment [ms]', windowMs));
ylabel('TTL pulse');

title(sprintf('marker %d, offset = %.3f ms',...
       markerIndex, offset_ms(markerIndex)));

fprintf('\nTTL pulse plot information:\n');
fprintf('Selected file: %s\n', selectedName);
fprintf('Selected marker index: %d\n', markerIndex);
fprintf('Window length: %d ms\n', windowMs);
fprintf('Arduino pulses in window: %d\n', length(idxInWindow));
fprintf('Offset at selected marker: %.3f ms\n', offset_ms(markerIndex));

%% plot mean offset with STD error bar for each valid file

% Remove any files that resulted in NaN (e.g., files missing one of the streams)
% to prevent the errorbar function from failing.
valid_idx = ~isnan(all_stats.Mean_ms_NoOutlier) & ...
            ~isnan(all_stats.Std_ms_NoOutlier);

file_names = all_stats.FileName(valid_idx);
mean_offsets = all_stats.Mean_ms_NoOutlier(valid_idx);
std_offsets = all_stats.Std_ms_NoOutlier(valid_idx);

x = 1:length(mean_offsets);

figure('Position', [200, 200, 1000, 500]);
hold on; grid on;

errorbar(x, mean_offsets, std_offsets, 'o', ...
    'LineWidth', 1.5, ...
    'MarkerSize', 6, ...
    'CapSize', 8);

yline(mean(mean_offsets), '--k', 'LineWidth', 1.2);

xlim([0.5, length(x) + 0.5]);

xticks(x);
xticklabels(file_names);
xtickangle(45);

xlabel('XDF file');
ylabel('Offset [ms]');

title('Mean Xsens-Arduino offset per file with STD error bars', ...
    'Interpreter', 'none');

legend('Mean offset ± STD per file', ...
       'Average mean offset across files', ...
       'Location', 'eastoutside');

fprintf('\nError bar plot across files:\n');
fprintf('Number of valid files: %d\n', length(mean_offsets));
fprintf('Average mean offset across files: %.3f ms\n', mean(mean_offsets));
fprintf('STD of file mean offsets: %.3f ms\n', std(mean_offsets));