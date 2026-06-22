% Goal:
% 1. Load the imported EEGLAB .set file.
% 2. Run basic BeMoBIL EEG preprocessing.
% 3. Skip event-based trimming because EEG.event is empty.
% 4. Skip AMICA for the first test.

clear; clc; close all;

%% Paths 

projectFolder = '/Users/dydan/master_thesis/HipExo-EEG-Study/eeg_preprocessing';

eeglabFolder    = '/Users/dydan/master_thesis/eeglab2026.0.0';
bemobilFolder   = fullfile(projectFolder, 'BeMoBIL');
scriptsFolder   = fullfile(projectFolder, 'scripts_yadan');
fieldtripFolder = '/Users/dydan/master_thesis/fieldtrip-20260617';
zaplineFolder   = '/Users/dydan/master_thesis/zapline-plus';

addpath(genpath(zaplineFolder));
addpath(eeglabFolder);
addpath(genpath(bemobilFolder));
addpath(scriptsFolder);

addpath(fieldtripFolder);
ft_defaults;
addpath(fullfile(fieldtripFolder, 'external', 'xdf'));

fprintf('Using ft_defaults from:\n%s\n', which('ft_defaults'));
fprintf('Using load_xdf from:\n%s\n', which('load_xdf'));

%% Initialize EEGLAB

if ~exist('ALLCOM','var')
    eeglab;
end

%% Load configuration

run(fullfile(scriptsFolder, 'bemobil_config_.m'));

% Force correct study folder
bemobil_config.study_folder = [fullfile(projectFolder, 'output_data') filesep];

%% Subjects to process

% Original template:
% subjects = [1 2];

% First test: only subject 1
subjects = 1;

% Set to 1 if you want to recompute even if output already exists.
% First test can stay 0. If a previous failed run created partial files, change this to 1.
force_recompute = 1;

% Imported session label from bemobil_import.m
sessionLabel = 'day2Exo1Sport';

%% Processing loop

for subject = subjects

    %% Prepare filepaths

    disp(['Subject #' num2str(subject)]);

    STUDY = [];
    CURRENTSTUDY = 0;
    ALLEEG = [];
    CURRENTSET = [];
    EEG = [];
    EEG_interp_avref = [];
    EEG_single_subject_final = [];

    % Original template:
    % input_filepath = [bemobil_config.study_folder bemobil_config.raw_EEGLAB_data_folder bemobil_config.filename_prefix num2str(subject)];
    % output_filepath = [bemobil_config.study_folder bemobil_config.single_subject_analysis_folder bemobil_config.filename_prefix num2str(subject)];

    input_filepath = fullfile( ...
        bemobil_config.study_folder, ...
        bemobil_config.raw_EEGLAB_data_folder, ...
        [bemobil_config.filename_prefix num2str(subject)] ...
    );

    output_filepath = fullfile( ...
        bemobil_config.study_folder, ...
        bemobil_config.single_subject_analysis_folder, ...
        [bemobil_config.filename_prefix num2str(subject)] ...
    );

    if ~exist(output_filepath, 'dir')
        mkdir(output_filepath);
    end

    %% Check if already fully processed
    % Original template checks for cleaned ICA file.
    % This is disabled for the first test because AMICA/ICA is not run yet.
    %
    % try
    %     EEG_single_subject_final = pop_loadset( ...
    %         'filename', [bemobil_config.filename_prefix num2str(subject) '_' bemobil_config.single_subject_cleaned_ICA_filename], ...
    %         'filepath', output_filepath);
    % catch
    %     disp('...failed. Computing now.')
    % end
    %
    % if ~force_recompute && exist('EEG_single_subject_final','var') && ~isempty(EEG_single_subject_final)
    %     clear EEG_single_subject_final
    %     disp('Subject is completely preprocessed already.')
    %     continue
    % end

    %% EEGLAB memory/save options

    try
        pop_editoptions( ...
            'option_saveversion6', 0, ...
            'option_single', 0, ...
            'option_memmapdata', 0, ...
            'option_savetwofiles', 1, ...
            'option_storedisk', 0);
    catch
        warning('Could NOT edit EEGLAB memory options!!');
    end

    %% Load imported EEGLAB .set file

    % Original template:
    % EEG = pop_loadset( ...
    %     'filename', [bemobil_config.filename_prefix num2str(subject) '_' bemobil_config.merged_filename], ...
    %     'filepath', input_filepath);

    % Your actual imported file:
    % sub-1_day2Exo1Sport_EEG.set
    input_filename = [bemobil_config.filename_prefix num2str(subject) '_' sessionLabel '_EEG.set'];

    fprintf('\nLoading EEGLAB file:\n%s\nfrom:\n%s\n', input_filename, input_filepath);

    EEG = pop_loadset( ...
        'filename', input_filename, ...
        'filepath', input_filepath ...
    );

    EEG = eeg_checkset(EEG);

    fprintf('\nLoaded EEG information:\n');
    %% Check and filter channels_to_remove

    all_labels = {EEG.chanlocs.labels};

    disp('All channel labels in current EEG:');
    disp(all_labels');

    if isfield(bemobil_config, 'channels_to_remove') && ~isempty(bemobil_config.channels_to_remove)

        original_remove_list = bemobil_config.channels_to_remove;

        existing_remove_list = original_remove_list( ...
            ismember(original_remove_list, all_labels) ...
            );

        missing_remove_list = setdiff(original_remove_list, all_labels);

        disp('Requested channels to remove:');
        disp(original_remove_list');

        disp('Actually existing channels to remove:');
        disp(existing_remove_list');

        disp('Requested but missing channels, will be ignored:');
        disp(missing_remove_list');

        bemobil_config.channels_to_remove = existing_remove_list;

    else
        disp('No channels_to_remove specified.');
    end
    fprintf('Channels: %d\n', EEG.nbchan);
    fprintf('Sampling rate: %.2f Hz\n', EEG.srate);
    fprintf('Samples: %d\n', EEG.pnts);
    fprintf('Duration: %.2f seconds\n', EEG.pnts / EEG.srate);
    fprintf('Events: %d\n', length(EEG.event));

    %% Individual EEG processing to remove non-experiment segments
    % Original template removes everything before the first event and after the last event.
    % This cannot be used now because EEG.event is empty.
    %
    % Original template:
    %
    % allevents = {EEG.event.type}';
    %
    % removeindices = [0 EEG.event(1).latency-EEG.srate];
    %
    % removeindices(end+1,:) = [EEG.event(end).latency+EEG.srate EEG.pnts];
    %
    % EEG_plot = pop_eegfiltnew(EEG, 'locutoff',0.5,'plotfreqz',0);
    %
    % fig1 = figure;
    % set(gcf,'Color','w','InvertHardCopy','off', 'units','normalized','outerposition',[0 0 1 1])
    % plot(normalize(EEG_plot.data') + [1:10:10*EEG_plot.nbchan], 'color', [78 165 216]/255)
    % yticks([])
    %
    % xlim([0 EEG.pnts])
    % ylim([-10 10*EEG_plot.nbchan+10])
    %
    % hold on
    %
    % for i = 1:size(removeindices,1)
    %     plot([removeindices(i,1) removeindices(i,1)],ylim,'r')
    %     plot([removeindices(i,2) removeindices(i,2)],ylim,'g')
    % end
    %
    % print(gcf,fullfile(input_filepath,[bemobil_config.filename_prefix num2str(subject) '_raw-full_EEG.png']),'-dpng')
    % close
    %
    % EEG = eeg_eegrej(EEG, removeindices);

    disp('Skipping event-based trimming because EEG.event is empty.');
    disp('Using the whole EEG recording for this first preprocessing test.');

    %% Basic EEG preprocessing

    % Do basic preprocessing, line noise removal, bad channel detection,
    % channel interpolation, and average reference.
    [ALLEEG, EEG_preprocessed, CURRENTSET] = bemobil_process_all_EEG_preprocessing( ...
        subject, ...
        bemobil_config, ...
        ALLEEG, ...
        EEG, ...
        CURRENTSET, ...
        force_recompute);

    %% AMICA
    % Original template:
    % bemobil_process_all_AMICA(ALLEEG, EEG_preprocessed, CURRENTSET, subject, bemobil_config, force_recompute);
    %
    % For the first test, AMICA is disabled.
    % Run AMICA only after basic preprocessing works.
    disp('Skipping AMICA for the first test.');

end

%% Copy plots
% Original template:
% bemobil_copy_plots_in_one(bemobil_config)
%
% Disabled for the first test because not all expected final plots exist yet.
% bemobil_copy_plots_in_one(bemobil_config)

subjects
subject

disp('PROCESSING DONE FOR BASIC EEG PREPROCESSING TEST!')