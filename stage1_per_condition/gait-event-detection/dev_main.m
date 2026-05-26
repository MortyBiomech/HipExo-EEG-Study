clc
clear

%% Change these paths with respect to your system
addpath(genpath('D:\Morteza\MyProjects\X1Dnsys_EEG'))
addpath(genpath('D:\Morteza\LSL\xdf-Matlab-master'))

addpath('D:\Morteza\Toolboxes\Fieldtrip\fieldtrip-20231127')
addpath('D:\Morteza\Toolboxes\Fieldtrip\fieldtrip-20231127\fileio')

data_path = 'D:\Morteza\MyProjects\X1Dnsys_EEG\Pilots\PilotTest2\Sub-P2_1\day2\sub-Pilot2_1_day2\';

processing_path = 'D:\Morteza\MyProjects\ANSYMB2024\Code\Matlab\data_processing\';


%% sub-Pilot2_1_day2 order of sessions
order_sessions = {'NoExoPre', 'Exo1_sport', 'Exo2_aquaplus', 'ExoOff', ...
    'Exo3_eco', 'Exo4_aqua', 'Exo5_boost', 'NoExoPost'};


%% All signals from all sessions concatenated (it takes time!)
subject_id = 17;
rawdata_path = [data_path, '0_source_data\'];
output = runs_concatenated(subject_id, rawdata_path);

All_EEG_time = output.All_EEG_time;
All_Experiment = output.All_Exp;
All_Experiment_time = output.All_Exp_time;


%% Initialize EEGLAB 
if ~exist('ALLCOM','var')
	eeglab;
end

% initialize fieldtrip without adding alternative files to path 
% assuming FT is on your path already or is added via EEGlab plugin manager
global ft_default
ft_default.toolbox.signal = 'matlab';  % can be 'compat' or 'matlab'
ft_default.toolbox.stats  = 'matlab';
ft_default.toolbox.image  = 'matlab';
ft_defaults % this sets up the FieldTrip path


%% [OPTIONAL] check the .xdf data to explore the structure
ftPath = fileparts(which('ft_defaults')); 
addpath(fullfile(ftPath, 'external','xdf')); 
xdfPath = [rawdata_path, 'sub-', num2str(subject_id), filesep, ...
    'ses-S001\eeg\sub-', num2str(subject_id), ...
    '_ses-S001_task-Default_run-001_eeg.xdf']; % enter full path to your .xdf file 

% load .xdf data to check what is in there
streams         = load_xdf(xdfPath);
streamnames     = cellfun(@(x) x.info.name, streams, 'UniformOutput', 0)' % will display names of streams contained in .xdf

% display names of all channels in the .xdf data
for Si = 1:numel(streamnames)
    if isfield( streams{Si}.info.desc, 'channels')
        channelnames    = cellfun(@(x) x.label, streams{Si}.info.desc.channels.channel, 'UniformOutput', 0)'
    end
end


%% [OPTIONAL] enter metadata about the data set, data modalities, and participants

% information about the eeg recording system 
% will be saved in BIDS-folder/sub-XX/[ses-XX]/eeg/*_eeg.json and *_coordsystem.json
% see "https://bids-specification.readthedocs.io/en/stable/04-modality-specific-files/03-electroencephalography.html#:~:text=MAY%20be%20specified.-,Sidecar%20JSON%20(*_eeg.json),-Generic%20fields%20MUST"
% and "https://bids-specification.readthedocs.io/en/stable/04-modality-specific-files/03-electroencephalography.html#:~:text=after%20the%20recording.-,Coordinate%20System%20JSON,-(*_coordsystem.json"
%--------------------------------------------------------------------------
%--------------------------------------------------------------------------
eegInfo     = [];
% eegInfo.coordsystem.EEGCoordinateSystem     = 'enter the name of your coordinate system'; % only needed when you share eloc
% eegInfo.coordsystem.EEGCoordinateUnits      = 'enter the unit of your coordinate system'; % only needed when you share eloc
% eegInfo.coordsystem.EEGCoordinateSystemDescription = 'enter description of your coordinate system'; % only needed when you share eloc
eegInfo.eeg.SamplingFrequency               = 500; % nominal sampling frequency                            


%% Import data

% iterate over sessions to import xdf files one by one
% full path to your study folder  
studyFolder   = data_path(1:end-1);     

% replace with names of your sessions (if there are no multiple sessions, 
% remove confg.ses and the session loop in the following)
sessionNames  = {'S001', 'S002', 'S003'}; %, 'S004'};             

% loop over sessions 
for session = 1:length(sessionNames)
    
    % reset for each loop
    config = [];  
    % required, replace with the folder where you want to store your bids data
    config.bids_target_folder = [data_path, '1_BIDS_data'];  
    
    % required, replace with your xdf file full path
    config.filename  = ...
        fullfile([rawdata_path,'sub-', num2str(subject_id),'\ses-', ...
        sessionNames{session}, '\eeg\sub-', num2str(subject_id), ...
        '_ses-', sessionNames{session}, '_task-Default_run-001_eeg.xdf']);    
    
    % optional, if you have electrode location file, replace with the full 
    % path to the file.
    % config.eeg.chanloc = fullfile([processing_path ,'chanlocs.ced']);
    
    % optional, replace with your task name
    config.task                   = 'KneeSwingingwithExo';  
    config.subject                = subject_id;  % required
    config.session                = sessionNames{session}; % optional
    config.overwrite              = 'on'; % optional
    
    % required, replace with the unique keyword in your eeg stream in 
    % the .xdf file
    config.eeg.stream_name        = 'LiveAmpSN-102108-1125'; 
    
    %------------------------------------------------------------------
    
    % config.motion.streams{1}.xdfname            = 'YourStreamNameInXDF'; % replace with name of the stream corresponding to the first tracking system
    % config.motion.streams{1}.bidsname           = tracking_systems{1};  % a comprehensible name to represent the tracking system 
    % config.motion.streams{1}.tracked_points     = 'headRigid';          % name of the point that is being tracked in the tracking system, the keyword has to be containted in the channel name (see "bemobil_bids_motionconvert")
    % config.motion.streams{1}.tracked_points_anat= 'head';               % example of how the tracked point can be renamed to body part name for metadata
    % 
    % % names of position and quaternion channels in each stream
    % config.motion.streams{1}.positions.channel_names    = {'headRigid_Rigid_headRigid_X';  'headRigid_Rigid_headRigid_Y' ; 'headRigid_Rigid_headRigid_Z' };
    % config.motion.streams{1}.quaternions.channel_names  = {'headRigid_Rigid_headRigid_quat_W';'headRigid_Rigid_headRigid_quat_Z';...
    %                                                        'headRigid_Rigid_headRigid_quat_X';'headRigid_Rigid_headRigid_quat_Y'};
    % 
    % config.motion.streams{2}.xdfname            = 'YourStreamNameInXDF2';
    % config.motion.streams{2}.bidsname           = tracking_systems{2};
    % config.motion.streams{2}.tracked_points     = {'Rigid1', 'Rigid2', 'Rigid3', 'Rigid4'}; % example when there are multiple points tracked by the system
    % config.motion.streams{2}.positions.channel_names = {'Rigid1_X', 'Rigid2_X', 'Rigid3_X', 'Rigid4_X';... % each column is one tracked point and rows are different coordinates
    %                                                     'Rigid1_Y', 'Rigid2_Y', 'Rigid3_Y', 'Rigid4_Y';...
    %                                                     'Rigid1_Z', 'Rigid2_Z', 'Rigid3_Z', 'Rigid4_Z'};
    % config.motion.streams{2}.quaternions.channel_names = {'Rigid1_A', 'Rigid2_A', 'Rigid3_A', 'Rigid4_A';...
    %                                                     'Rigid1_B', 'Rigid2_B', 'Rigid3_B', 'Rigid4_B';...
    %                                                     'Rigid1_C', 'Rigid2_C', 'Rigid3_C', 'Rigid4_C'; ...
    %                                                     'Rigid1_D', 'Rigid2_D', 'Rigid3_D', 'Rigid4_D'};
    % 

    % bemobil_xdf2bids(config, ...
    %     'general_metadata', generalInfo,...
    %     'participant_metadata', subjectInfo,...
    %     'motion_metadata', motionInfo, ...
    %     'eeg_metadata', eegInfo);

    bemobil_xdf2bids(config, ...
        'eeg_metadata', eegInfo);
end

fclose all;


%% configuration for bemobil bids2set
%----------------------------------------------------------------------
config.set_folder               = fullfile(studyFolder,'2_raw-EEGLAB');
config.session_names            = sessionNames;

% config.other_data_types = {'motion'};  % specify which other data type than eeg is there (only 'motion' and 'physio' supported atm)
bemobil_bids2set(config);


%% Configuration of the BeMoBIL pipeline
bemobil_config = BeMoBIL_Configuration(data_path);

% enter all subjects to process here (you can split it up in more MATLAB instances if you have more CPU power and RAM)
subjects = 9; 

% set to 1 if all files should be computed, independently of whether they are present on disk or not
force_recompute = 0; 


%% processing loop

for subject = subjects
    
    %% prepare filepaths and check if already done
    
	disp(['Subject #' num2str(subject)]);
    
	STUDY = []; CURRENTSTUDY = 0; ALLEEG = [];  CURRENTSET=[]; EEG=[]; EEG_interp_avref = []; EEG_single_subject_final = [];
	
	input_filepath = [bemobil_config.study_folder bemobil_config.raw_EEGLAB_data_folder bemobil_config.filename_prefix num2str(subject)];
	output_filepath = [bemobil_config.study_folder bemobil_config.single_subject_analysis_folder bemobil_config.filename_prefix num2str(subject)];
	
	% try
	% 	% load completely processed file
	% 	EEG_single_subject_final = ...
    %         pop_loadset('filename', [ bemobil_config.filename_prefix num2str(subject)...
	% 		'_' bemobil_config.single_subject_cleaned_ICA_filename], 'filepath', output_filepath);
    % catch
    %     disp('...failed. Computing now.')
    % end

	
	% if ~force_recompute && exist('EEG_single_subject_final','var') ...
    %         && ~isempty(EEG_single_subject_final)
	% 	clear EEG_single_subject_final
	% 	disp('Subject is completely preprocessed already.')
	% 	continue
    % end

	%% load data in EEGLAB .set structure
    % make sure the data is stored in double precision, large datafiles are
    % supported, no memory mapped objects are used but data is processed 
    % locally, and two files are used for storing sets (.set and .fdt)
	% try 
    %     pop_editoptions('option_saveversion6', 0, 'option_single', 0, ...
    %         'option_memmapdata', 0, 'option_savetwofiles', 1, ...
    %         'option_storedisk', 0);
    % catch
    %     warning('Could NOT edit EEGLAB memory options!!'); 
    % end
    
    % load files that were created from xdf to BIDS to EEGLAB
    EEG = pop_loadset('filename', ...
        [ bemobil_config.filename_prefix num2str(subject) '_' ...
        bemobil_config.merged_filename],'filepath',input_filepath);
    

    %% reselect EEG channels and remove ACC channels
    EEG = pop_select(EEG, 'rmchannel', [65, 66, 67]);


    %% Load channels location file
    EEG = pop_chanedit(EEG,'load', [processing_path, 'chanlocs.ced']); 


    %% Define and Add events
    [EEG, removeindices] = Main_add_events(EEG, output, ...
        subject, subject_id, processing_path, input_filepath, bemobil_config, data_path);

    % % we don't need to recalculate the AMICA
    % % just add new events on the existing cleaned_with_ICA EEG file
    % new_filename = [processing_path, 'Events\sub-', ...
    %     num2str(subject_id), filesep, 'events_with_FlxExt.txt'];
    % [EEG, ~] = pop_importevent(EEG, 'event', ...
    %           new_filename, 'fields', {'type', 'latency','desc' }, ...
    %           'append', 'no', 'align', NaN, 'skipline', 1, 'timeunit', 1E-3);

    
    %% Reject non-experimental periods
    EEG = eeg_eegrej(EEG, removeindices);

  
    
    %% processing wrappers for basic processing and AMICA
    
    % do basic preprocessing, line noise removal, and channel interpolation
	[ALLEEG, EEG_preprocessed, CURRENTSET] = bemobil_process_all_EEG_preprocessing(subject, bemobil_config, ALLEEG, EEG, CURRENTSET, force_recompute);

    % start the processing pipeline for AMICA
	bemobil_process_all_AMICA(ALLEEG, EEG_preprocessed, CURRENTSET, subject, bemobil_config, force_recompute);

end

bemobil_copy_plots_in_one(bemobil_config)

subjects
subject

disp('PROCESSING DONE! YOU CAN CLOSE THE WINDOW NOW!')


% rmpath(genpath('D:\Morteza\MyProjects\ANSYMB2024'))
