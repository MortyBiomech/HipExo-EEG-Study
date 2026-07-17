%% Central path settings
% Only edit this file when paths change.

projectRoot = '/Users/dydan/master_thesis/HipExo-EEG-Study';

projectFolder = fullfile(projectRoot, 'eeg_preprocessing');

eeglabFolder    = '/Users/dydan/master_thesis/eeglab2026.0.0';
fieldtripFolder = '/Users/dydan/master_thesis/fieldtrip-20260617';

rawDataFolder = fullfile(projectFolder, 'raw_data_PilotTest2');
bemobilFolder = fullfile(projectFolder, 'BeMoBIL');
scriptsFolder = fullfile(projectFolder, 'scripts_yadan');
outputFolder  = fullfile(projectFolder, 'output_data');

summaryFile = fullfile(outputFolder, 'xdf_file_stream_summary.csv');
detailFile  = fullfile(outputFolder, 'xdf_stream_detail_table.csv');

importTableFile = fullfile(outputFolder, 'bemobil_import_table.csv');
mappingFile     = importTableFile;

importLogFile = fullfile(outputFolder, 'bemobil_xdf2bids_import_log.csv');

amicaTempFolder = '/Users/dydan/master_thesis/amica_tmp';

addpath(eeglabFolder);
addpath(genpath(bemobilFolder));
addpath(scriptsFolder);
addpath(fieldtripFolder);
addpath(fullfile(fieldtripFolder, 'external', 'xdf'));
