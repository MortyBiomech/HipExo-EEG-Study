%% Subject Data XDF Info Extractor (Single Session)
clc;
clear;

%% 1. Load Configurations
% Run the external config file to load paths and subject variables
run('config_paths.m');

%% 2. Find the first session (NoExoPre) to extract info
subjectDir = data_path;   
d = dir(subjectDir);
folderNames = {d([d.isdir]).name};
folderNames(ismember(folderNames, {'.','..'})) = [];

% Just pick the NoExoPre folder
current_session = folderNames{contains(folderNames, 'NoExoPre')};

% Assemble file path
filename = sprintf('sub-%s_%s_%s_task-Default_run-001_eeg.xdf', subject_id, experiment_day, current_session);
filepath = fullfile(data_path, current_session, 'eeg');
full_file_path = fullfile(filepath, filename);

if ~exist(full_file_path, 'file')
    error('File not found: %s. Please check your data path.', full_file_path);
end

%% 3. Load only ONE XDF file
fprintf('>> Loading ONE XDF file (%s) to extract hardware info...\n   Please wait...\n', current_session);
[streams, ~] = load_xdf(full_file_path);
num_streams = length(streams);

%% 4. Extract data safely
stream_indices = (1:num_streams)';
stream_names   = cell(num_streams, 1);
stream_types   = cell(num_streams, 1);
stream_uids    = cell(num_streams, 1);

for i = 1:num_streams
    % --- Extract Name ---
    if isfield(streams{i}.info, 'name') && ~isempty(streams{i}.info.name)
        if iscell(streams{i}.info.name)
            stream_names{i} = strtrim(streams{i}.info.name{1});
        else
            stream_names{i} = strtrim(streams{i}.info.name);
        end
    else
        stream_names{i} = 'N/A';
    end

    % --- Extract Type ---
    if isfield(streams{i}.info, 'type') && ~isempty(streams{i}.info.type)
        if iscell(streams{i}.info.type)
            stream_types{i} = strtrim(streams{i}.info.type{1});
        else
            stream_types{i} = strtrim(streams{i}.info.type);
        end
    else
        stream_types{i} = 'N/A';
    end

    % --- Extract UID ---
    if isfield(streams{i}.info, 'uid') && ~isempty(streams{i}.info.uid)
        if iscell(streams{i}.info.uid)
            stream_uids{i} = strtrim(streams{i}.info.uid{1});
        else
            stream_uids{i} = strtrim(streams{i}.info.uid);
        end
    else
        stream_uids{i} = 'N/A';
    end
end

%% 5. Create and display the Table
xdf_summary_table = table(stream_indices, stream_names, stream_types, stream_uids, ...
    'VariableNames', {'Index', 'Name', 'Type', 'UID'});

fprintf('\n>> Extraction Complete! Found %d streams in %s.\n\n', num_streams, current_session);
disp(xdf_summary_table);

%% 6. Validate with predefined mapping (subject_3_infos.m)
fprintf('\n========================================================\n');
fprintf('>> Validating Signal Names and UIDs for [%s] against subject_3_infos.m...\n', experiment_day);

try
    run('subject_3_infos.m');
    
    mismatch_count = 0;
    
    % Dynamically determine which columns to read based on experiment_day
    if strcmp(experiment_day, 'day1')
        col_signal = 'SignalName_1';
        col_uid    = 'UID_1';
    elseif strcmp(experiment_day, 'day2')
        col_signal = 'SignalName_2';
        col_uid    = 'UID_2';
    else
        error('Unknown experiment_day: %s', experiment_day);
    end
    
    for r = 1:height(subject_3)
        target_name = strtrim(subject_3.(col_signal){r});
        
        % Skip entries explicitly marked as 'None'
        if strcmp(target_name, 'None') || isempty(target_name)
            continue;
        end
        
        target_uid = strtrim(subject_3.(col_uid){r});
        if strcmp(target_uid, 'None')
            target_uid = ''; % Treat 'None' UID as empty to trigger auto-fill prompt
        end
        
        idx = find(strcmp(xdf_summary_table.Name, target_name));
        
        if isempty(idx)
            fprintf('  [Missing] Signal Name "%s" not found in the XDF file!\n', target_name);
            mismatch_count = mismatch_count + 1;
        else
            actual_uid = xdf_summary_table.UID{idx(1)};
            
            if isempty(target_uid)
                fprintf('  [Action Required] Muscle: %s\n', subject_3.MuscleName{r});
                fprintf('    -> Your table has NO UID. Please copy this into subject_3_infos.m:\n');
                fprintf('       ''%s''\n', actual_uid);
                mismatch_count = mismatch_count + 1;
            elseif ~strcmp(target_uid, actual_uid)
                fprintf('  [Mismatch] Muscle: %s (Sensor: %s)\n', subject_3.MuscleName{r}, target_name);
                fprintf('    -> Expected UID in your file: %s\n', target_uid);
                fprintf('    -> Actual UID in XDF file:    %s\n', actual_uid);
                mismatch_count = mismatch_count + 1;
            end
        end
    end
    
    fprintf('\n');
    if mismatch_count == 0
        fprintf('  [Success] Perfect Match! All mapped sensors for %s map exactly to the XDF file.\n', experiment_day);
    else
        fprintf('  [Warning] Found %d missing entries or mismatches. Please check the logs above.\n', mismatch_count);
    end

catch ME
    fprintf('  [Error] Could not run or validate subject_3_infos.m: %s\n', ME.message);
end