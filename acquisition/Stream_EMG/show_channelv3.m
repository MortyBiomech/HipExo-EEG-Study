function show_channel_native()
    % ==========================================================
    % Native EEG/XDF/EDF Viewer (No EEGLAB Required)
    % Features: Multi-stream XDF Support, Independent Time Vectors
    % ==========================================================
    
    % 1. Create Main Figure
    fig = figure('Name', 'Native EEG/XDF/EDF Channel Viewer', ...
                 'NumberTitle', 'off', ...
                 'MenuBar', 'none', ...
                 'ToolBar', 'figure', ... 
                 'Position', [200, 150, 900, 650]);
    
    % Universal Data Container 
    % (Upgraded to Cell Arrays to support independent sampling rates per channel)
    appData = struct('data', {cell(0,1)}, 'time_sec', {cell(0,1)}, ...
                     'labels', {cell(0,1)}, 'events', []);
    set(fig, 'UserData', appData);
    
    % 2. Create Plotting Axes
    ax = axes('Parent', fig, 'Units', 'normalized', 'Position', [0.08, 0.25, 0.85, 0.65]);
    title(ax, 'Waiting for data...');
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'Amplitude');
    grid(ax, 'on');
    
    % 3. Create UI Controls
    % --- Top Control Area ---
    uicontrol('Style', 'pushbutton', 'String', '📂 Load Data', ...
              'Units', 'normalized', 'Position', [0.08, 0.93, 0.15, 0.04], ...
              'Callback', @(~,~) loadData());
          
    uicontrol('Style', 'pushbutton', 'String', '🔄 Auto Scale', ...
              'Units', 'normalized', 'Position', [0.24, 0.93, 0.12, 0.04], ...
              'Callback', @(~,~) updatePlot(true));
          
    btnEvents = uicontrol('Style', 'togglebutton', 'String', '🚩 Toggle Events', ...
              'Units', 'normalized', 'Position', [0.37, 0.93, 0.15, 0.04], ...
              'Callback', @(~,~) updatePlot(false));
          
    uicontrol('Style', 'text', 'String', 'Channel:', ...
              'FontWeight', 'bold', 'HorizontalAlignment', 'right', ...
              'Units', 'normalized', 'Position', [0.53, 0.93, 0.08, 0.03]);
          
    ddChan = uicontrol('Style', 'popupmenu', 'String', {'Please load data...'}, ...
                       'Units', 'normalized', 'Position', [0.62, 0.935, 0.31, 0.03], ...
                       'Callback', @(~,~) updatePlot(true));
                   
    % --- Bottom Control Area ---
    uicontrol('Style', 'text', 'String', 'X Min (s):', 'HorizontalAlignment', 'left', ...
              'Units', 'normalized', 'Position', [0.08, 0.12, 0.08, 0.03]);
    edXMin = uicontrol('Style', 'edit', 'String', '0', ...
                       'Units', 'normalized', 'Position', [0.16, 0.12, 0.08, 0.035], ...
                       'Callback', @(~,~) updateLimits());
                   
    uicontrol('Style', 'text', 'String', 'X Max (s):', 'HorizontalAlignment', 'left', ...
              'Units', 'normalized', 'Position', [0.26, 0.12, 0.08, 0.03]);
    edXMax = uicontrol('Style', 'edit', 'String', '10', ...
                       'Units', 'normalized', 'Position', [0.34, 0.12, 0.08, 0.035], ...
                       'Callback', @(~,~) updateLimits());
                   
    uicontrol('Style', 'text', 'String', 'Y Min:', 'HorizontalAlignment', 'left', ...
              'Units', 'normalized', 'Position', [0.08, 0.06, 0.08, 0.03]);
    edYMin = uicontrol('Style', 'edit', 'String', '0', ...
                       'Units', 'normalized', 'Position', [0.16, 0.06, 0.08, 0.035], ...
                       'Callback', @(~,~) updateLimits());
                   
    uicontrol('Style', 'text', 'String', 'Y Max:', 'HorizontalAlignment', 'left', ...
              'Units', 'normalized', 'Position', [0.26, 0.06, 0.08, 0.03]);
    edYMax = uicontrol('Style', 'edit', 'String', '100', ...
                       'Units', 'normalized', 'Position', [0.34, 0.06, 0.08, 0.035], ...
                       'Callback', @(~,~) updateLimits());

    % ==========================================
    % Nested Core Functions
    % ==========================================
    
    function loadData()
        [file, fpath] = uigetfile({ ...
            '*.set;*.edf;*.xdf', 'All Supported Files (*.set, *.edf, *.xdf)'; ...
            '*.set', 'EEGLAB Dataset (*.set)'; ...
            '*.edf', 'EDF File (*.edf)'; ...
            '*.xdf', 'XDF File (*.xdf)'}, 'Select Data File');
            
        if isequal(file, 0); return; end
        set(fig, 'Pointer', 'watch'); drawnow;
        
        try
            [~, ~, ext] = fileparts(file);
            ext = lower(ext);
            
            % Reset data container with empty cells
            appData = struct('data', {cell(0,1)}, 'time_sec', {cell(0,1)}, 'labels', {cell(0,1)}, 'events', []);
            
            % ----------------------------------------------------
            % 1. Native .SET Parser
            % ----------------------------------------------------
            if strcmp(ext, '.set')
                d = load(fullfile(fpath, file), '-mat');
                EEG = d.EEG;
                
                if ischar(EEG.data) 
                    fdt_file = fullfile(fpath, EEG.data);
                    if ~exist(fdt_file, 'file'), fdt_file = fullfile(fpath, [EEG.setname '.fdt']); end
                    fid = fopen(fdt_file, 'r', 'ieee-le');
                    if fid == -1, error('Cannot find .fdt binary file.'); end
                    temp_data = fread(fid, [EEG.nbchan, EEG.pnts], 'float32');
                    fclose(fid);
                else
                    temp_data = EEG.data;
                end
                
                temp_time = (0:size(temp_data,2)-1) / EEG.srate;
                
                % Convert matrix to cells (1 cell per channel)
                appData.data = num2cell(temp_data, 2);
                appData.time_sec = repmat({temp_time}, size(temp_data,1), 1);
                
                if isfield(EEG, 'chanlocs') && ~isempty(EEG.chanlocs) && isfield(EEG.chanlocs, 'labels')
                    appData.labels = {EEG.chanlocs.labels}';
                else
                    appData.labels = arrayfun(@(x) sprintf('Ch %02d', x), (1:size(temp_data,1))', 'UniformOutput', false);
                end
                
                if isfield(EEG, 'event') && ~isempty(EEG.event)
                    for e = 1:length(EEG.event)
                        appData.events(e).time = (EEG.event(e).latency - 1) / EEG.srate;
                        appData.events(e).type = num2str(EEG.event(e).type);
                    end
                end

            % ----------------------------------------------------
            % 2. Native EDF Parser
            % ----------------------------------------------------
            elseif strcmp(ext, '.edf')
                info = edfinfo(fullfile(fpath, file));
                T = edfread(fullfile(fpath, file));
                
                temp_data = T{:,:}'; 
                srate = info.NumSamples(1) / seconds(info.DataRecordDuration(1));
                temp_time = (0:size(temp_data,2)-1) / srate;
                
                appData.data = num2cell(temp_data, 2);
                appData.time_sec = repmat({temp_time}, size(temp_data,1), 1);
                appData.labels = info.SignalLabels(:);

            % ----------------------------------------------------
            % 3. XDF Parser (Extracts ALL Streams & Channels)
            % ----------------------------------------------------
            elseif strcmp(ext, '.xdf')
                if exist('load_xdf', 'file') ~= 2
                    error('Missing "load_xdf.m". Please place it in the same directory.');
                end
                
                streams = load_xdf(fullfile(fpath, file));
                
                % Find global base time to align all streams and events properly
                base_time = inf;
                for i = 1:length(streams)
                    if ~isempty(streams{i}.time_stamps)
                        base_time = min(base_time, streams{i}.time_stamps(1));
                    end
                end
                if isinf(base_time), base_time = 0; end
                
                e_idx = 1;
                for i = 1:length(streams)
                    % If stream is Markers
                    if isfield(streams{i}.info, 'type') && strcmpi(streams{i}.info.type, 'Markers')
                        for k = 1:length(streams{i}.time_stamps)
                            appData.events(e_idx).time = streams{i}.time_stamps(k) - base_time;
                            if iscell(streams{i}.time_series)
                                appData.events(e_idx).type = char(streams{i}.time_series{1, k});
                            else
                                appData.events(e_idx).type = num2str(streams{i}.time_series(1, k));
                            end
                            e_idx = e_idx + 1;
                        end
                        
                    % If stream is numerical data (EEG, EMG, Force, etc.)
                    elseif ~isempty(streams{i}.time_series) && isnumeric(streams{i}.time_series)
                        stream_name = streams{i}.info.name;
                        n_ch = size(streams{i}.time_series, 1);
                        t_vec = streams{i}.time_stamps - base_time;
                        
                        % Iterate through every channel in this stream
                        for c = 1:n_ch
                            appData.data{end+1, 1} = streams{i}.time_series(c, :);
                            appData.time_sec{end+1, 1} = t_vec;
                            appData.labels{end+1, 1} = sprintf('[%s] Ch %02d', stream_name, c);
                        end
                    end
                end
            end
            
            % Update UI Dropdown List
            list_str = cell(1, length(appData.labels));
            for i = 1:length(appData.labels)
                list_str{i} = sprintf('[ID %02d] %s', i, char(appData.labels{i}));
            end
            set(ddChan, 'String', list_str, 'Value', 1);
            set(fig, 'UserData', appData);
            set(fig, 'Pointer', 'arrow');
            
            updatePlot(true);
            
        catch ME
            set(fig, 'Pointer', 'arrow');
            errordlg(['Loading Error: ', ME.message], 'Error');
        end
    end

    function updatePlot(autoScale)
        appData = get(fig, 'UserData');
        if isempty(appData.data); return; end
        
        ch_idx = get(ddChan, 'Value'); 
        
        % Extract data directly from cell arrays
        y_data = appData.data{ch_idx};
        t_data = appData.time_sec{ch_idx};
        
        cla(ax);
        plot(ax, t_data, y_data, 'b-', 'LineWidth', 1.2);
        grid(ax, 'on');
        hold(ax, 'on');
        
        % Vectorized Event Markers
        showEvents = get(btnEvents, 'Value');
        if showEvents && ~isempty(appData.events)
            all_times = [appData.events.time];
            all_types = {appData.events.type};
            xline(ax, all_times, 'r--', all_types, ...
                  'LabelVerticalAlignment', 'top', ...
                  'HandleVisibility', 'off');
        end
        hold(ax, 'off');
        
        chan_strings = get(ddChan, 'String');
        title(ax, chan_strings{ch_idx}, 'Interpreter', 'none');
        xlabel(ax, 'Time (s)');
        ylabel(ax, 'Amplitude');
        
        if autoScale
            y_min = min(y_data); y_max = max(y_data);
            if y_min == y_max, y_min = y_min - 1; y_max = y_max + 1; end
            margin = (y_max - y_min) * 0.05;
            
            set(edYMin, 'String', num2str(y_min - margin));
            set(edYMax, 'String', num2str(y_max + margin));
            set(edXMin, 'String', num2str(t_data(1)));
            set(edXMax, 'String', num2str(t_data(end)));
            updateLimits();
        else
            updateLimits(); 
        end
    end

    function updateLimits()
        appData = get(fig, 'UserData');
        if isempty(appData.data); return; end
        
        x_min = str2double(get(edXMin, 'String'));
        x_max = str2double(get(edXMax, 'String'));
        y_min = str2double(get(edYMin, 'String'));
        y_max = str2double(get(edYMax, 'String'));
        
        if isnan(x_min) || isnan(x_max) || isnan(y_min) || isnan(y_max); return; end
        if x_max <= x_min; x_max = x_min + 1; set(edXMax, 'String', num2str(x_max)); end
        if y_max <= y_min; y_max = y_min + 1; set(edYMax, 'String', num2str(y_max)); end
        
        xlim(ax, [x_min, x_max]);
        ylim(ax, [y_min, y_max]);
    end
end