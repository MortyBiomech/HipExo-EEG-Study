
% Goal:
% 1. Import one EEG-containing XDF file for testing.
% 2. Convert XDF to BIDS.
% 3. Convert BIDS to EEGLAB .set/.fdt.
%
% Test file:
% Sub-P2_1 day2 ses-Exo1_sport
%
% Real EEG stream:
% LiveAmpSN-102108-1139
%
% Marker stream, NOT EEG:
% LiveAmpSN-102108-1139-DeviceTrigger

clear; clc;

%% Paths

projectFolder = '/Users/dydan/master_thesis/HipExo-EEG-Study/eeg_preprocessing_yadan';

eeglabFolder    = '/Users/dydan/master_thesis/eeglab2026.0.0';
bemobilFolder   = fullfile(projectFolder, 'BeMoBIL');
scriptsFolder   = fullfile(projectFolder, 'scripts_yadan');
fieldtripFolder = '/Users/dydan/master_thesis/fieldtrip-20260617';

rawDataFolder = '/Users/dydan/master_thesis/PilotTest2';
outputFolder  = fullfile(projectFolder, 'output_data');

if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

addpath(eeglabFolder);
addpath(genpath(bemobilFolder));
addpath(scriptsFolder);

addpath(fieldtripFolder);
ft_defaults;

addpath(fullfile(fieldtripFolder, 'external', 'xdf'));

fprintf('Using ft_defaults from:\n%s\n', which('ft_defaults'));
fprintf('Using load_xdf from:\n%s\n', which('load_xdf'));

if isempty(which('load_xdf'))
    error('load_xdf was not found. Please check FieldTrip external/xdf path.');
end

%% initialize EEGLAB

if ~exist('ALLCOM','var')
    eeglab;
end

%% [OPTIONAL] check the .xdf data to explore the structure
% This part is commented out because we already use check_eeg_streams.m.
%
% xdfPath = fullfile(rawDataFolder, ...
%     'Sub-P2_1', 'day2', 'data', 'ses-Exo1_sport', 'eeg', ...
%     'sub-Pilot2_1_day2_ses-Exo1_sport_task-Default_run-001_eeg.xdf');
%
% streams = load_xdf(xdfPath);
% streamnames = cellfun(@(x) x.info.name, streams, 'UniformOutput', 0)'
%
% for Si = 1:numel(streamnames)
%     if isfield(streams{Si}.info.desc, 'channels')
%         channelnames = cellfun(@(x) x.label, streams{Si}.info.desc.channels.channel, 'UniformOutput', 0)'
%     end
% end


%% Metadata

generalInfo = [];

generalInfo.dataset_description.Name                = 'HipExo EEG PilotTest2';
generalInfo.dataset_description.BIDSVersion         = '1.8.0';
generalInfo.dataset_description.License             = 'n/a';
generalInfo.dataset_description.Authors             = {"Yadan Deng"};
generalInfo.dataset_description.Acknowledgements    = 'n/a';
generalInfo.dataset_description.Funding             = {"n/a"};
generalInfo.dataset_description.ReferencesAndLinks  = {"n/a"};
generalInfo.dataset_description.DatasetDOI          = 'n/a';

generalInfo.InstitutionName                         = 'TU Darmstadt';
generalInfo.InstitutionalDepartmentName             = 'n/a';
generalInfo.InstitutionAddress                      = 'Darmstadt, Germany';
generalInfo.TaskDescription                         = 'EEG recording during exoskeleton walking task';


%% EEG metadata

eegInfo = [];

eegInfo.coordsystem.EEGCoordinateSystem              = 'n/a';
eegInfo.coordsystem.EEGCoordinateUnits               = 'n/a';
eegInfo.coordsystem.EEGCoordinateSystemDescription   = 'n/a';

% The LiveAmp EEG stream is 500 Hz.
eegInfo.eeg.SamplingFrequency = 500;


%% Motion metadata
% Motion is commented out for the first EEG-only test.
%
% motionInfo  = [];
%
% tracking_systems = {'System1', 'System2'};
%
% motionInfo.motion = [];
%
% motionInfo.motion.TrackingSystems(1).TrackingSystemName               = tracking_systems{1};
% motionInfo.motion.TrackingSystems(1).Manufacturer                     = 'HTC';
% motionInfo.motion.TrackingSystems(1).ManufacturersModelName           = 'Vive Pro';
% motionInfo.motion.TrackingSystems(1).SamplingFrequency                = 90;
% motionInfo.motion.TrackingSystems(1).DeviceSerialNumber               = 'n/a';
% motionInfo.motion.TrackingSystems(1).SoftwareVersions                 = 'n/a';
% motionInfo.motion.TrackingSystems(1).SpatialAxes                      = 'FRU';
% motionInfo.motion.TrackingSystems(1).RotationRule                     = 'left-hand';
% motionInfo.motion.TrackingSystems(1).RotationOrder                    = 'ZXY';
%
% motionInfo.motion.TrackingSystems(2).TrackingSystemName               = tracking_systems{2};
% motionInfo.motion.TrackingSystems(2).Manufacturer                     = 'Impuls X2';
% motionInfo.motion.TrackingSystems(2).ManufacturersModelName           = 'PhaseSpace';
% motionInfo.motion.TrackingSystems(2).SamplingFrequency                = 90;
% motionInfo.motion.TrackingSystems(2).DeviceSerialNumber               = 'n/a';
% motionInfo.motion.TrackingSystems(2).SoftwareVersions                 = 'n/a';
% motionInfo.motion.TrackingSystems(2).SpatialAxes                      = 'FRU';
% motionInfo.motion.TrackingSystems(2).RotationRule                     = 'left-hand';
% motionInfo.motion.TrackingSystems(2).RotationOrder                    = 'ZXY';


%% Participant information

subjectInfo.fields.nr.Description             = 'numerical ID of the participant';
subjectInfo.fields.age.Description            = 'age of the participant';
subjectInfo.fields.age.Unit                   = 'years';
subjectInfo.fields.sex.Description            = 'sex of the participant';
subjectInfo.fields.sex.Levels.M               = 'male';
subjectInfo.fields.sex.Levels.F               = 'female';
subjectInfo.fields.handedness.Description     = 'handedness of the participant';
subjectInfo.fields.handedness.Levels.R        = 'right-handed';
subjectInfo.fields.handedness.Levels.L        = 'left-handed';

subjectInfo.cols = {'nr', 'age', 'sex', 'handedness'};

% For the first test, only subject 1 is imported.
subjectInfo.data = {1, 'n/a', 'n/a', 'n/a'};

% Original template participant table is not used now.
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


%% Import one XDF file: XDF -> BIDS -> EEGLAB

studyFolder = outputFolder;

% IMPORTANT:
% BIDS session labels must NOT contain spaces or underscores.
% So do not use day2_Exo1_sport.
sessionNames = {'day2Exo1Sport'};

for subject = 1

    for session = 1

        config = [];

        config.bids_target_folder = fullfile(studyFolder, '1_BIDS-data');

        config.filename = fullfile(rawDataFolder, ...
            'Sub-P2_1', 'day2', 'data', 'ses-Exo1_sport', 'eeg', ...
            'sub-Pilot2_1_day2_ses-Exo1_sport_task-Default_run-001_eeg.xdf');

        % No electrode location file for the first import test.
        config.eeg.chanloc = [];

        config.task = 'Default';
        config.subject = subject;
        config.session = sessionNames{session};
        config.overwrite = 'on';

        % Real EEG stream.
        
        config.eeg.stream_name = 'LiveAmpSN-102108-1139';

        %------------------------------------------------------------------
        % Motion configuration is commented out for the first EEG-only test.
        %------------------------------------------------------------------

        % config.motion.streams{1}.xdfname            = 'YourStreamNameInXDF';
        % config.motion.streams{1}.bidsname           = tracking_systems{1};
        % config.motion.streams{1}.tracked_points     = 'headRigid';
        % config.motion.streams{1}.tracked_points_anat= 'head';
        %
        % config.motion.streams{1}.positions.channel_names    = {'headRigid_Rigid_headRigid_X';  'headRigid_Rigid_headRigid_Y' ; 'headRigid_Rigid_headRigid_Z' };
        % config.motion.streams{1}.quaternions.channel_names  = {'headRigid_Rigid_headRigid_quat_W';'headRigid_Rigid_headRigid_quat_Z';...
        %                                                        'headRigid_Rigid_headRigid_quat_X';'headRigid_Rigid_headRigid_quat_Y'};
        %
        % config.motion.streams{2}.xdfname            = 'YourStreamNameInXDF2';
        % config.motion.streams{2}.bidsname           = tracking_systems{2};
        % config.motion.streams{2}.tracked_points     = {'Rigid1', 'Rigid2', 'Rigid3', 'Rigid4'};
        % config.motion.streams{2}.positions.channel_names = {'Rigid1_X', 'Rigid2_X', 'Rigid3_X', 'Rigid4_X';...
        %                                                     'Rigid1_Y', 'Rigid2_Y', 'Rigid3_Y', 'Rigid4_Y';...
        %                                                     'Rigid1_Z', 'Rigid2_Z', 'Rigid3_Z', 'Rigid4_Z'};
        % config.motion.streams{2}.quaternions.channel_names = {'Rigid1_A', 'Rigid2_A', 'Rigid3_A', 'Rigid4_A';...
        %                                                     'Rigid1_B', 'Rigid2_B', 'Rigid3_B', 'Rigid4_B';...
        %                                                     'Rigid1_C', 'Rigid2_C', 'Rigid3_C', 'Rigid4_C'; ...
        %                                                     'Rigid1_D', 'Rigid2_D', 'Rigid3_D', 'Rigid4_D'};

        % Original template with motion metadata:
        %
        % bemobil_xdf2bids(config, ...
        %     'general_metadata', generalInfo,...
        %     'participant_metadata', subjectInfo,...
        %     'motion_metadata', motionInfo, ...
        %     'eeg_metadata', eegInfo);

        % EEG-only import test:
        bemobil_xdf2bids(config, ...
            'general_metadata', generalInfo, ...
            'participant_metadata', subjectInfo, ...
            'eeg_metadata', eegInfo);

    end

    fclose all

    %% BIDS -> EEGLAB .set/.fdt

    config.set_folder = fullfile(studyFolder, '2_raw-EEGLAB');
    config.session_names = sessionNames;

    % Original template:
    % config.other_data_types = {'motion'};

    % EEG only for the first test:
    config.other_data_types = {};

    bemobil_bids2set(config);

end