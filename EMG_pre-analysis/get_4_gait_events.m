% Combining automatic interval segmentation with a custom gait detection algorithm.
clc;
clear;

%% 1. Load Configurations
run('config_paths.m');
derivativesContainer = bids_root;
assert(contains(string(data_path),'PilotTest3','IgnoreCase',true), ...
    'PilotTest3 only: do not use this file for PilotTest2.');
save_path=directDataset(derivativesContainer,'p3gaitevents');
run([current_subject, '_infos.m']); 

%% 2. Dynamic Session Order Setup
d=dir(fullfile(data_path,'ses-*'));
order_sessions={d([d.isdir]).name};
order_sessions=order_sessions(~contains(lower(string(order_sessions)),{'calib','setup'}));
num_sessions=numel(order_sessions); p3Sources={};

% Force plate (GRF) channel definition
Left_leg_indx  = [2 3 6 7];     
Right_leg_indx = [1 4 5 8];    

%% 3. Main Loop
fprintf('Starting GRF Gait Event Extraction for subject %s...\n', subject_id);

for s = 1:num_sessions
    current_session = order_sessions{s};
    
    if contains(current_session, 'Missing')
        continue;
    end
    
    fprintf('\n========================================================\n');
    fprintf('Processing [%d/%d]: %s\n', s, num_sessions, current_session);
    
    session_eeg_dir = fullfile(data_path, current_session, 'eeg');
    xdf_files=dir(fullfile(session_eeg_dir,sprintf('*run-%s*_eeg.xdf',run_id)));
    xdf_files=xdf_files(~contains(lower(string({xdf_files.name})),'old'));
    if isempty(xdf_files), warning('No selected run in %s',session_eeg_dir); continue; end
    assert(isscalar(xdf_files),'Ambiguous XDF run in %s',session_eeg_dir);
    filename=xdf_files(1).name;
    full_file_path=fullfile(xdf_files(1).folder,filename);

    fprintf('>> Loading target XDF file: %s...\n', filename);
    
    % Load XDF streams 
    [streams, ~] = load_xdf(full_file_path);
    
    grf_idx = find(strcmp(cellfun(@(x) x.info.name, streams, 'UniformOutput', false), 'GRF'));
    stream_names = string(cellfun(@(x) x.info.name, streams, 'UniformOutput', false));

    % PilotTest3 uses IMU_Markers. PilotTest2 uses GRF_Marker/GRF_Markers.
    % If both streams exist, prefer IMU_Markers.
    marker_idx = find(strcmpi(strtrim(stream_names), 'IMU_Markers'), 1);
    if isempty(marker_idx)
        marker_idx = find(contains(stream_names, 'GRF_Marker', ...
            'IgnoreCase', true), 1);
    end
    
    if isempty(grf_idx)
        warning('Missing GRF stream for %s. Skipping.', current_session);
        continue;
    end
    
    GRF = streams{grf_idx(1)};
    
    % 2. Handle cases where markers are missing and guide the system into manual mode
    if isempty(marker_idx)
        fprintf('>> No IMU_Markers or GRF_Marker(s) stream found. Will default to manual selection.\n');
        marker_labels = strings(0, 1);
        marker_times = zeros(0, 1);
        marker_stream_name = "";
    else
        Marker_Stream = streams{marker_idx(1)};
        marker_stream_name = stream_names(marker_idx(1));
        marker_labels = flattenMarkerLabels(Marker_Stream.time_series);
        marker_times = double(Marker_Stream.time_stamps(:));

        n_markers = min(numel(marker_labels), numel(marker_times));
        marker_labels = marker_labels(1:n_markers);
        marker_times = marker_times(1:n_markers);
        fprintf('>> Using marker stream: %s\n', char(marker_stream_name));
    end
    
    %% 4. Define Walking Window (Auto via Markers or Manual)
    % Remove all standing markers, then pair Start_xxx with the later
    % End_xxx that has exactly the same suffix.
    [idx_start, idx_end] = findNonStandingMarkerPair( ...
        marker_labels, marker_times);

    auto_success = false;
    
    if ~isempty(idx_start) && ~isempty(idx_end)
        final_start = marker_times(idx_start);
        final_end   = marker_times(idx_end);
        start_label = char(marker_labels(idx_start));
        end_label   = char(marker_labels(idx_end));
        fprintf('>> Auto-detection successful. Using markers: [%s] to [%s]\n', start_label, end_label);
        auto_success = true;
    else
        fprintf(['>> No complete non-standing Start_xxx/End_xxx pair was ' ...
            'found in %s. Manual selection required.\n'], ...
            char(marker_stream_name));
    end
    
    % Manual Selection Fallback 
    if ~auto_success
        % Calculate quick Summed GRF for manual plotting
        t_all = GRF.time_stamps;
        Fz_R_total = sum(abs(GRF.time_series(Right_leg_indx, :)), 1);
        Fz_L_total = sum(abs(GRF.time_series(Left_leg_indx, :)), 1);
        
        h_fig = figure('Name', sprintf('Manual Selection - %s', current_session), 'Position', [50, 50, 1400, 700]);
        plot(t_all, Fz_L_total, 'b'); hold on;
        plot(t_all, Fz_R_total, 'r');
        xlabel('LSL Time (s)'); ylabel('Total Amplitude');
        title({'[MANUAL SELECTION]', ...
               '1. Use zoom/pan to find the stable walking start/end.', ...
               '2. Go to the Command Window and type the exact timestamps.'}, 'Color', 'red', 'FontSize', 12);
        grid on;
        
        disp('--- Manual Input Required ---');
        valid_input = false;
        while ~valid_input
            try
                user_start_str = input('Enter START timestamp (e.g., 577872.5) : ', 's');
                user_end_str   = input('Enter END timestamp   (e.g., 578115.2) : ', 's');
                final_start = str2double(user_start_str);
                final_end   = str2double(user_end_str);
                
                if ~isnan(final_start) && ~isnan(final_end) && final_start < final_end
                    valid_input = true;
                else
                    disp('Invalid input. Start must be < End and both must be numbers.');
                end
            catch
                disp('Invalid input format.');
            end
        end
        close(h_fig);
        
        start_label = 'Manual_Start';
        end_label   = 'Manual_End';
        fprintf('>> Proceeding with manual window: %.2f to %.2f\n', final_start, final_end);
    end
    
    %% 5. Crop GRF and detect gait events
    % Here, we crop the raw GRF structure based on final_start and final_end
    % so that your detect_gait_events function does not process invalid data
    valid_idx = GRF.time_stamps >= final_start & GRF.time_stamps <= final_end;
    
    GRF_cropped = GRF;
    GRF_cropped.time_stamps = GRF.time_stamps(valid_idx);
    GRF_cropped.time_series = GRF.time_series(:, valid_idx);
    
    fprintf('>> Calling optimize_thresholds and detect_gait_events...\n');
    % 5.1 Call threshold optimization function.
    [best_on, best_off] = optimize_thresholds_V1(GRF_cropped, Right_leg_indx, Left_leg_indx);
    
    % 5.2 Call event detection function (set `Plot` to `true` so can view the validation plot).
    [HS_R, TO_R, HS_L, TO_L] = detect_gait_events(GRF_cropped, Right_leg_indx, Left_leg_indx, ...
                                'ThresholdOn', best_on, ...
                                'ThresholdOff', best_off, ...
                                'Plot', true, 'Verbose', true);
                            
    % 5.3 Call the gait histogram function.
    plot_gait_histograms(HS_R, TO_R, HS_L, TO_L);
    
    % % --- Optional: Remove the first and last points to ensure a clean steady state ---
    % % Note: Function returns a struct containing .samples and .timestamps
    % if length(HS_L.timestamps) > 3
    %     HS_L.timestamps = HS_L.timestamps(2:end-1);
    %     TO_L.timestamps = TO_L.timestamps(2:end-1);
    % end
    % if length(HS_R.timestamps) > 3
    %     HS_R.timestamps = HS_R.timestamps(2:end-1);
    %     TO_R.timestamps = TO_R.timestamps(2:end-1);
    % end
    
    %% 6. Compile Events and Save into .mat
    % Package the output of function into the struct format we standardly use for EMG and EEG data.
    all_events = struct('type', {}, 'time', {});
    count = 0;
    
    count = count + 1; all_events(count).type = start_label; all_events(count).time = final_start;
    count = count + 1; all_events(count).type = end_label;   all_events(count).time = final_end;
    
    for i = 1:length(HS_L.timestamps)
        count=count+1; all_events(count).type = 'HS_L'; all_events(count).time = HS_L.timestamps(i);
    end
    for i = 1:length(TO_L.timestamps)
        count=count+1; all_events(count).type = 'TO_L'; all_events(count).time = TO_L.timestamps(i);
    end
    for i = 1:length(HS_R.timestamps)
        count=count+1; all_events(count).type = 'HS_R'; all_events(count).time = HS_R.timestamps(i);
    end
    for i = 1:length(TO_R.timestamps)
        count=count+1; all_events(count).type = 'TO_R'; all_events(count).time = TO_R.timestamps(i);
    end
    
    [~, sort_order] = sort([all_events.time]);
    all_events = all_events(sort_order);
    
    % DYNAMIC SAVE PATH
    identity=directIdentity(full_file_path,struct('fallbackDay',experiment_day));
    sessionRoot=fullfile(save_path,['sub-' identity.Subject],['ses-' identity.Session]);
    save_dir=fullfile(sessionRoot,'emg');
    figureDir=fullfile(sessionRoot,'figures');
    if ~isfolder(figureDir), mkdir(figureDir); end
    
    if ~exist(save_dir, 'dir')
        mkdir(save_dir);
    end
    
    p3Base=identity.Prefix;
    save_name=fullfile(save_dir,[p3Base '_desc-gait_events.mat']);
    p3EventOrigin=double(GRF.time_stamps(1));
    p3EventReference='First sample of the source GRF stream, shared XDF clock; not EMG sample zero';
    save(save_name,'all_events','p3EventOrigin','p3EventReference');
    onset=double([all_events.time]')-p3EventOrigin;
    duration=zeros(size(onset)); trial_type=string({all_events.type})';
    lsl_time=double([all_events.time]');
    writeDerivativeTable(table(onset,duration,trial_type,lsl_time), ...
        fullfile(save_dir,[p3Base '_desc-gait_events.tsv']));
    directJSON(fullfile(save_dir,[p3Base '_desc-gait_events.json']), ...
        struct('SourceFiles',{{full_file_path}},'TimeReference',p3EventReference, ...
        'ReferenceXDFSeconds',p3EventOrigin,'Identity',identity, ...
        'onset',struct('Description','Seconds relative to first source GRF sample','Units','s'), ...
        'duration',struct('Description','Instantaneous gait event','Units','s'), ...
        'trial_type',struct('Description','Gait event type'), ...
        'lsl_time',struct('Description','Absolute shared XDF timestamp','Units','s')));
    p3Sources{end+1}=full_file_path;
    p3Figures=findall(groot,'Type','figure');
    for p3f=1:numel(p3Figures)
        exportgraphics(p3Figures(p3f),fullfile(figureDir,sprintf('%s_desc-gaitDiagnostic%02d_figure.png',p3Base,p3f)),'Resolution',150);
    end 
    fprintf('>> Saved %d combined events to: %s\n', length(all_events), save_name);
    
    % Wait for user to check your function's plots before closing and moving to next
    disp('Review your custom function plots. Press any key in the Command Window to continue...');
    pause; 
    close all; % Close the generated image and proceed to the next session
end

fprintf('Final gait events output: %s\n',save_path);

function labels = flattenMarkerLabels(timeSeries)
    labels = strings(numel(timeSeries), 1);
    for ii = 1:numel(timeSeries)
        if iscell(timeSeries)
            value = timeSeries{ii};
        else
            value = timeSeries(ii);
        end
        while iscell(value) && ~isempty(value)
            value = value{1};
        end
        textValue = string(value);
        if ~isempty(textValue)
            labels(ii) = textValue(1);
        end
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

function root=directDataset(container,pipeline)
% Final destination: no staging, restoration, copying or migration.
root=fullfile(char(container),'derivatives',char(pipeline));
if ~isfolder(root), mkdir(root); end
description=struct('Name',['PilotTest3 ' pipeline], ...
    'BIDSVersion','1.11.2','DatasetType','derivative', ...
    'GeneratedBy',{{struct('Name',pipeline)}});
directJSON(fullfile(root,'dataset_description.json'),description);
end

function directJSON(path,value)
fid=fopen(path,'w','n','UTF-8');
assert(fid>=0,'Cannot write: %s',path);
cleaner=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end

function id=directIdentity(source,cfg)
% Reversible source-label mapping is written into every export manifest.
source=char(source); [~,name,~]=fileparts(strrep(source,'\','/'));
s=regexp(name,'sub-(.*?)_ses-','tokens','once');
c=regexp(name,'_ses-(.*?)_task-','tokens','once');
r=regexp(name,'_run-(\d+)(?:_|$)','tokens','once');
t=regexp(name,'_task-([A-Za-z0-9]+)','tokens','once');
assert(~isempty(s)&&~isempty(c)&&~isempty(r),'Cannot identify source: %s',source);
sub=s{1};
assert(~isempty(regexp(sub,'^(?:Pilot3_\d+|Pilot3\d+|P3_\d+)$','once')), ...
    'PilotTest3 source required, got subject %s. PilotTest2 is excluded.',sub);
d=regexp(strrep(source,'\','/'),'(?:^|/)(day\d+)(?:/|$)','tokens','once');
if isempty(d)
    d=regexp(c{1},'^(day\d+)(?=[A-Z])','tokens','once');
end
if isempty(d)
    assert(isfield(cfg,'fallbackDay')&&~isempty(cfg.fallbackDay), ...
        'Experiment day missing from source path. Set cfg.fallbackDay explicitly: %s',source);
    day=char(cfg.fallbackDay);
else, day=d{1}; 
end
assert(~isempty(regexp(day,'^day\d+$','once')),'Day must be day1, day2, etc.');
condition=regexprep(c{1},['^' day],'');
if isempty(t), task='Default'; else, task=t{1}; end
id=struct('OriginalSubject',sub,'Subject',regexprep(sub,'[^A-Za-z0-9]',''), ...
    'Day',day,'OriginalSession',condition,'Session',[day regexprep(condition,'[^A-Za-z0-9]','')], ...
    'Task',task,'Run',sprintf('%03d',str2double(r{1})), 'SourceFile',source);
id.Prefix=sprintf('sub-%s_ses-%s_task-%s_run-%s',id.Subject,id.Session,id.Task,id.Run);
end

function writeDerivativeTable(T,path,varargin)
writetable(T,path,'FileType','text','Delimiter','\t',varargin{:});
end
