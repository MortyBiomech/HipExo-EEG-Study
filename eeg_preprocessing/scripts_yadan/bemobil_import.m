% Goal:
% Import one EEG-containing XDF file, convert it to BIDS format,
% and then convert the BIDS EEG data to EEGLAB .set/.fdt format.
%
% Current test file:
% sub-Pilot2_1_day2_ses-Exo1_sport_task-Default_run-001_eeg.xdf
%
% Real EEG stream:
% LiveAmpSN-102108-1139
% 
% Note:
% This is an EEG-only import test. Motion data and preprocessing are not included now.


clear; clc;

%% USER SETTINGS: paths for this project
% These lines are added for the current project.

projectFolder   = '/Users/dydan/master_thesis/HipExo-EEG-Study/eeg_preprocessing';

eeglabFolder    = '/Users/dydan/master_thesis/eeglab2026.0.0';
fieldtripFolder = '/Users/dydan/master_thesis/fieldtrip-20260617';
rawDataFolder   = '/Users/dydan/master_thesis/PilotTest2';

bemobilFolder   = fullfile(projectFolder, 'BeMoBIL');
scriptsFolder   = fullfile(projectFolder, 'scripts_yadan');
outputFolder    = fullfile(projectFolder, 'output_data');

if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

addpath(eeglabFolder);
addpath(genpath(bemobilFolder));
addpath(scriptsFolder);
addpath(fieldtripFolder);


% initialize EEGLAB 
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
% ftPath      = fileparts(which('ft_defaults')); 
% addpath(fullfile(ftPath, 'external','xdf')); 

% fprintf('Using ft_defaults from:\n%s\n', which('ft_defaults'));
% fprintf('Using load_xdf from:\n%s\n', which('load_xdf'));

% if isempty(which('load_xdf'))
%    error('load_xdf was not found. Please check FieldTrip external/xdf path.');
% end


%% [OPTIONAL] enter metadata about the data set, data modalities, and participants

% general metadata shared across all modalities
% will be saved in BIDS-folder/data_description.json
% see "https://bids-specification.readthedocs.io/en/stable/03-modality-agnostic-files.html#:~:text=LICENSE-,dataset_description.json,-The%20file%20dataset_description"
%--------------------------------------------------------------------------
%--------------------------------------------------------------------------
generalInfo = [];

% required for dataset_description.json
generalInfo.dataset_description.Name                = 'HipExo EEG PilotTest2';
generalInfo.dataset_description.BIDSVersion         = '1.8.0'; % if sharing motion data, use "unofficial extension"

% optional for dataset_description.json
generalInfo.dataset_description.License             = 'n/a';
generalInfo.dataset_description.Authors             = {"Yadan Deng"};
generalInfo.dataset_description.Acknowledgements    = 'n/a';
generalInfo.dataset_description.Funding             = {"n/a"};
generalInfo.dataset_description.ReferencesAndLinks  = {"n/a"};
generalInfo.dataset_description.DatasetDOI          = 'n/a';

% general information shared across modality specific json files 
generalInfo.InstitutionName                         = 'TU Darmstadt';
generalInfo.InstitutionalDepartmentName             = 'n/a';
generalInfo.InstitutionAddress                      = 'Darmstadt, Germany';
generalInfo.TaskDescription                         = 'EEG recording during exoskeleton walking task';
 

% information about the eeg recording system 
% will be saved in BIDS-folder/sub-XX/[ses-XX]/eeg/*_eeg.json and *_coordsystem.json
% see "https://bids-specification.readthedocs.io/en/stable/04-modality-specific-files/03-electroencephalography.html#:~:text=MAY%20be%20specified.-,Sidecar%20JSON%20(*_eeg.json),-Generic%20fields%20MUST"
% and "https://bids-specification.readthedocs.io/en/stable/04-modality-specific-files/03-electroencephalography.html#:~:text=after%20the%20recording.-,Coordinate%20System%20JSON,-(*_coordsystem.json"
%--------------------------------------------------------------------------
%--------------------------------------------------------------------------
eegInfo     = [];
eegInfo.coordsystem.EEGCoordinateSystem     = 'n/a'; % only needed when you share eloc
eegInfo.coordsystem.EEGCoordinateUnits      = 'n/a'; % only needed when you share eloc
eegInfo.coordsystem.EEGCoordinateSystemDescription = 'n/a'; % only needed when you share eloc
eegInfo.eeg.SamplingFrequency               = 500; % nominal sampling frequency  
                                                  

% information about the motion recording system 
% will be saved in BIDS-folder/sub-XX/[ses-XX]/motion/*_motion.json 
% see "https://docs.google.com/document/d/1iaaLKgWjK5pcISD1MVxHKexB3PZWfE2aAC5HF_pCZWo/edit?usp=sharing"
%--------------------------------------------------------------------------
%--------------------------------------------------------------------------
% Motion is not used in the current EEG-only import test.
% The original template code is kept here, but commented out.
%
% motionInfo  = []; 
%
% tracking_systems = {'System1', 'System2'}; % enter the names of your tracking systems 
%
% motion specific fields in json
% motionInfo.motion = [];
%
% system 1 information
% motionInfo.motion.TrackingSystems(1).TrackingSystemName               = tracking_systems{1};
% motionInfo.motion.TrackingSystems(1).Manufacturer                     = 'HTC'; % manufacturer of the motion capture system
% motionInfo.motion.TrackingSystems(1).ManufacturersModelName           = 'Vive Pro'; % model name of the tracking system
% motionInfo.motion.TrackingSystems(1).SamplingFrequency                = 90; %  If no nominal Fs exists, n/a entry returns 'n/a'. If it exists, n/a entry returns nominal Fs from motion stream.
% motionInfo.motion.TrackingSystems(1).DeviceSerialNumber               = 'n/a'; 
% motionInfo.motion.TrackingSystems(1).SoftwareVersions                 = 'n/a'; 
% motionInfo.motion.TrackingSystems(1).SpatialAxes                      = 'FRU'; % XYZ spatial axes description 
% motionInfo.motion.TrackingSystems(1).RotationRule                     = 'left-hand'; % if rotation is present, does it follow the left-hand or right-hand rule?
% motionInfo.motion.TrackingSystems(1).RotationOrder                    = 'ZXY'; % order of euler angles' extrinsic rotation
%
% system 2 information
% motionInfo.motion.TrackingSystems(2).TrackingSystemName               = tracking_systems{2};
% motionInfo.motion.TrackingSystems(2).Manufacturer                     = 'Impuls X2';
% motionInfo.motion.TrackingSystems(2).ManufacturersModelName           = 'PhaseSpace';
% motionInfo.motion.TrackingSystems(2).SamplingFrequency                = 90;
% motionInfo.motion.TrackingSystems(2).DeviceSerialNumber               = 'n/a'; 
% motionInfo.motion.TrackingSystems(2).SoftwareVersions                 = 'n/a';
% motionInfo.motion.TrackingSystems(2).SpatialAxes                      = 'FRU'; 
% motionInfo.motion.TrackingSystems(2).RotationRule                     = 'left-hand'; 
% motionInfo.motion.TrackingSystems(2).RotationOrder                    = 'ZXY'; 



% participant information 
%--------------------------------------------------------------------------
%--------------------------------------------------------------------------
% here describe the fields in the participant file
% see "https://bids-specification.readthedocs.io/en/stable/03-modality-agnostic-files.html#participants-file:~:text=UTF%2D8%20encoding.-,Participants%20file,-Template%3A"
% for numerical values  : 
%       subjectData.fields.[insert your field name here].Description    = 'describe what the field contains';
%       subjectData.fields.[insert your field name here].Unit           = 'write the unit of the quantity';
% for values with discrete levels :
%       subjectData.fields.[insert your field name here].Description    = 'describe what the field contains';
%       subjectData.fields.[insert your field name here].Levels.[insert the name of the first level] = 'describe what the level means';
%       subjectData.fields.[insert your field name here].Levels.[insert the name of the Nth level]   = 'describe what the level means';
%--------------------------------------------------------------------------
subjectInfo.fields.nr.Description       = 'numerical ID of the participant'; 
subjectInfo.fields.age.Description      = 'age of the participant'; 
subjectInfo.fields.age.Unit             = 'years'; 
subjectInfo.fields.sex.Description      = 'sex of the participant'; 
subjectInfo.fields.sex.Levels.M         = 'male'; 
subjectInfo.fields.sex.Levels.F         = 'female'; 
subjectInfo.fields.handedness.Description    = 'handedness of the participant';
subjectInfo.fields.handedness.Levels.R       = 'right-handed';
subjectInfo.fields.handedness.Levels.L       = 'left-handed';

% names of the columns - 'nr' column is just the numerical IDs of subjects
% do not change the name of this column
subjectInfo.cols = {'nr',   'age',  'sex',  'handedness'};

% For the current EEG-only test, only one subject is imported.
subjectInfo.data = {1,     'n/a',  'n/a',  'n/a'};

% Original template participant table is kept here, but commented out.
%
% subjectInfo.data = {1,     30,     'F',     'R' ; ...
%                     2,     22,     'M',     'R'; ...
%                     3,     23,     'F',     'R'; ...
%                     4,     34,     'M',     'R'; ...
%                     5,     25,     'F',     'R'; ...
%                     6,     21,     'F',     'R' ; ...
%                     7,     28,     'M',     'R'; ...
%                     8,     28,     'M',     'R'; ...
%                     9,     24,     'F',     'R'; ...
%                     10,    25,     'F',     'L'; ...
%                     11,    30,     'F',     'R'; ...
%                     12,    22,     'M',     'R'; ...
%                     13,    23,     'F',     'R'; ...
%                     14,    34,     'M',     'R'; ...
%                     15,    25,     'F',     'R'; ...
%                     16,    21,     'F',     'R' ; ...
%                     17,    28,     'M',     'R'; ...
%                     18,    28,     'M',     'R'; ...
%                     19,    24,     'F',     'R'; ...
%                     20,    25,     'F',     'L';};
               

                
%% iterate over participants, sessions, and runs to import file-by-file
studyFolder = outputFolder; % full path to your study folder  

% IMPORTANT:
% BIDS session labels must NOT contain spaces or underscores.
% So do not use day2_Exo1_sport.
sessionNames = {'day2Exo1Sport'}; % replace with names of your sessions (if there are no multiple sessions, remove confg.ses and the session loop in the following)

% loop over participants
for subject = 1
    
    % loop over sessions 
    for session = 1
        
        config                        = []; % reset for each loop ´
        config.bids_target_folder     = fullfile(studyFolder, '1_BIDS-data'); % required, replace with the folder where you want to store your bids data
        
        config.filename               = fullfile(rawDataFolder, ...
                                                'Sub-P2_1', 'day2', 'data', 'ses-Exo1_sport', 'eeg', ...
                                                'sub-Pilot2_1_day2_ses-Exo1_sport_task-Default_run-001_eeg.xdf'); % required, replace with your .xdf file full path
        
        config.eeg.chanloc            = [];   % optional, if you have electrode location file, replace with the full patht to the file. 
        
        config.task                   = 'Default'; % optional, replace with your task name
        config.subject                = subject;% required
        config.session                = sessionNames{session};% optional
        config.overwrite              = 'on';% optional
        
        config.eeg.stream_name        = 'LiveAmpSN-102108-1139'; % required, replace with the unique keyword in your eeg stream in the .xdf file
        
        %------------------------------------------------------------------
        
        % Motion is not used in the current EEG-only import test.
        % The original template code is kept here, but commented out.
        %
        % config.motion.streams{1}.xdfname            = 'YourStreamNameInXDF'; % replace with name of the stream corresponding to the first tracking system
        % config.motion.streams{1}.bidsname           = tracking_systems{1};  % a comprehensible name to represent the tracking system 
        % config.motion.streams{1}.tracked_points     = 'headRigid';          % name of the point that is being tracked in the tracking system, the keyword has to be containted in the channel name (see "bemobil_bids_motionconvert")
        % config.motion.streams{1}.tracked_points_anat= 'head';               % example of how the tracked point can be renamed to body part name for metadata
        % 
        % names of position and quaternion channels in each stream
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
        

        % Original template call with motion metadata:
        %
        % bemobil_xdf2bids(config, ...
        %     'general_metadata', generalInfo,...
        %     'participant_metadata', subjectInfo,...
        %     'motion_metadata', motionInfo, ...
        %     'eeg_metadata', eegInfo);

        % Current EEG-only import test:
        bemobil_xdf2bids(config, ...
            'general_metadata', generalInfo,...
            'participant_metadata', subjectInfo,...
            'eeg_metadata', eegInfo);
    end
    
    fclose all
    
    %% configuration for bemobil bids2set
    %----------------------------------------------------------------------
    config.set_folder               = fullfile(studyFolder,'2_raw-EEGLAB');
    config.session_names            = sessionNames;
    
    % Original template:
    % config.other_data_types = {'motion'};  % specify which other data type than eeg is there (only 'motion' and 'physio' supported atm)
    
    % Current EEG-only import test:
    config.other_data_types = {}; % specify which other data type than eeg is there (only 'motion' and 'physio' supported atm)
    
    bemobil_bids2set(config);

end