%% Batch EMG Preprocessing Script (BIDS & BDF Version)
clc;
clear;

%% 1. Load Configurations
run('config_paths.m');
run([current_subject, '_infos.m']); 

% Set the BIDS root directory
subj_dir  = fullfile(bids_root, ['sub-', bids_subject_id]); 

eeglab nogui;

%% 2. Dynamic Session Order Setup (BIDS compliant)
% Automatically scan all 'ses-*' folders under the subject directory
d = dir(fullfile(subj_dir, 'ses-*'));
session_folders = {d([d.isdir]).name};
num_sessions = length(session_folders);

%% 3. Main Loop: Iterate and Process each Session
for s = 1:num_sessions
    current_session_folder = session_folders{s}; 
    
    fprintf('\n========================================================\n');
    fprintf('Processing Session [%d/%d]: %s...\n', s, num_sessions, current_session_folder);
    
    % Construct the BIDS-compliant emg folder path
    session_emg_dir = fullfile(subj_dir, current_session_folder, 'emg');
    bdf_files = dir(fullfile(session_emg_dir, '*.bdf'));
    
    if isempty(bdf_files)
        warning('No BDF file found in %s. Skipping.', session_emg_dir);
        continue;
    end
    
    filename = bdf_files(1).name;
    full_file_path = fullfile(session_emg_dir, filename);
    
    fprintf('>> Loading target BDF file: %s...\n', filename);
    EEG = pop_biosig(full_file_path);
    
    % Parse events.tsv natively and inject into EEG.event
    tsv_filename = strrep(filename, '_emg.bdf', '_events.tsv');
    tsv_path = fullfile(session_emg_dir, tsv_filename);
    EEG.event = []; 
    
    if exist(tsv_path, 'file')
        fprintf('>> Parsing Python-generated BIDS events from: %s\n', tsv_filename);
        try
            opts = detectImportOptions(tsv_path, 'FileType', 'text', 'Delimiter', '\t');
            events_tbl = readtable(tsv_path, opts);
            
           for i = 1:height(events_tbl)
                latency_pts = events_tbl.onset(i) * EEG.srate + 1;
                
                % Handle cell array vs string array robustly
                if iscell(events_tbl.trial_type)
                    ev_type = strtrim(char(events_tbl.trial_type{i}));
                else
                    ev_type = strtrim(char(string(events_tbl.trial_type(i))));
                end
                
                EEG.event(i).type = ev_type;
                EEG.event(i).latency = latency_pts;
                EEG.event(i).urevent = i;
                
                if ismember('duration', events_tbl.Properties.VariableNames)
                    EEG.event(i).duration = events_tbl.duration(i) * EEG.srate;
                end
            end
            fprintf('>> Successfully injected %d events into EEG structure.\n', height(events_tbl));
        catch ME
            fprintf(' ⚠️ Error parsing events.tsv: %s\n', ME.message);
        end
    else
        warning('Events TSV file not found at: %s', tsv_path);
    end
    
    if ~isempty(EEG.event)
        EEG = eeg_checkset(EEG, 'eventconsistency');
    end
    
    %% 4. EEGLAB EMG Data Preprocessing
    fprintf('>> Applying 20-450 Hz bandpass filter...\n');
    EEG = pop_eegfiltnew(EEG, 'locutoff', 20, 'hicutoff', 450);
    
    % Define the target directory for derivatives early for log saving
    pipeline_name = 'eeglab_emg_prep';
    save_dir = fullfile(bids_root, 'derivatives', pipeline_name, ['sub-', bids_subject_id], current_session_folder, 'emg');
    if ~exist(save_dir, 'dir'), mkdir(save_dir); end
      
    fprintf('>> Computing linear envelope (Full-wave Rectification + 8Hz Low-pass)...\n');
    EEG.data = abs(EEG.data);
    EEG = pop_eegfiltnew(EEG, 'hicutoff', 8);
    EEG.data(EEG.data < 0) = 0;
    EEG.etc.is_envelope = true;
    
    % Save Preprocessing data
    save_filename_cont = strrep(filename, '_emg.bdf', '_desc-Preprocessing_emg.set');
    EEG = pop_saveset(EEG, 'filename', save_filename_cont, 'filepath', save_dir);
    fprintf('>> [SAVE 1] Saved Continuous Envelope dataset to: %s\n', fullfile(save_dir, save_filename_cont));
    
    %% 5. Dynamic Epoching (Keeping all original events)
    target_event = 'HS_R'; 
    
    % Retrieve events safely without hidden trailing spaces
    current_events = strtrim(string({EEG.event.type})); 
    target_idx = find(strcmp(current_events, target_event));
    
    if length(target_idx) > 1
        % Calculate max(RHS to the next RHS) in seconds
        latencies = [EEG.event(target_idx).latency];
        inter_event_secs = diff(latencies) / EEG.srate;
        max_duration = max(inter_event_secs);
        
        % Determine time interval: [-600 ms, max + 600 ms] -> [-0.6 s, max_duration + 0.6 s]
        epoch_window = [-0.6, max_duration + 0.6];
        
        fprintf('>> Max %s-to-%s duration found: %.3f seconds.\n', target_event, target_event, max_duration);
        fprintf('>> Setting epoch window to [%.3f, %.3f] seconds...\n', epoch_window(1), epoch_window(2));
        
        % Perform pop_epoch
        EEG = pop_epoch(EEG, {target_event}, epoch_window, 'newname', [bids_subject_id '_Epoched'], 'epochinfo', 'yes');
        EEG = eeg_checkset(EEG);
        EEG.setname = strcat(bids_subject_id, '_Epoched');
        EEG = eeg_checkset(EEG);
    else
        warning('Not enough %s events found to perform dynamic epoching. Skipping epoch step.', target_event);
    end
    
    %% 6. Save the preprocessed and epoched .set file (BIDS standard)
    % Update filename suffix to reflect the Epoched state
    save_filename = strrep(filename, '_emg.bdf', '_desc-Epoched_emg.set');
    EEG = pop_saveset(EEG, 'filename', save_filename, 'filepath', save_dir);
    fprintf('>> [SAVE 2] Saved Epoched dataset to: %s\n', fullfile(save_dir, save_filename));
end

fprintf('\n========================================================\n');
fprintf('Pipeline with dynamic Epoching finished successfully!\n');