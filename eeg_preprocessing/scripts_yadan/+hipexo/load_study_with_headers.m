function [STUDY, ALLEEG] = load_study_with_headers(studyPath, outputFolder, referenceALLEEG)
% GOAL
%   Load a STUDY and resolve its current dataset paths and headers.
% INPUT
%   STUDY path, output root and optional headers already loaded for these files.
% APPROACH
%   Resolve missing paths uniquely, verify file correspondence and reuse headers.
% OUTPUT
%   STUDY and matching ALLEEG headers for shared-ICA analysis.
% USED BY
%   Steps13 and 14 when reviewing multiple ROI representations of the same data.

    [studyFolder, studyName, studyExtension] = fileparts(studyPath);
    assert(strcmpi(studyExtension, '.study'), ...
        'Expected an EEGLAB .study file: %s', ...
        studyPath);
    assert(exist(studyPath, 'file') == 2, ...
        'STUDY file was not found: %s', ...
        studyPath);
    assert(exist(outputFolder, 'dir') == 7, ...
        'Current output folder was not found: %s', ...
        outputFolder);

    % EEGLAB STUDY files are MATLAB v7.3/HDF5 files. On Windows, a long
    % absolute path can exceed the HDF5 path limit even when the file exists.
    % Load by filename from inside its folder so HDF5 receives a short path.
    originalFolder = pwd;
    restoreFolder = onCleanup(@() cd(originalFolder));
    cd(studyFolder);
    loadedStudy = load([studyName studyExtension], '-mat', 'STUDY');
    clear restoreFolder;

    assert(isfield(loadedStudy, 'STUDY') && isstruct(loadedStudy.STUDY), ...
        'The STUDY file does not contain a valid STUDY structure: %s', ...
        studyPath);

    STUDY = loadedStudy.STUDY;
    STUDY.filename = [studyName studyExtension];
    STUDY.filepath = studyFolder;

    repairedCount = 0;

    for datasetIndex = 1:numel(STUDY.datasetinfo)

        datasetFilename = char(string(STUDY.datasetinfo(datasetIndex).filename));
        assert(~isempty(datasetFilename), ...
            'STUDY dataset %d has an empty filename.', ...
            datasetIndex);

        recordedFolder = char(string(STUDY.datasetinfo(datasetIndex).filepath));
        recordedPath = fullfile(recordedFolder, datasetFilename);

        if exist(recordedPath, 'file') == 2
            continue;
        end

        matches = dir(fullfile(outputFolder, '**', datasetFilename));
        matches = matches(~[matches.isdir]);

        assert(~isempty(matches), ...
            ['Dataset referenced by the STUDY was not found.\n' ...
             'Dataset: %s\n' ...
             'Recorded path: %s\n' ...
             'Searched below: %s'], ...
            datasetFilename, ...
            recordedPath, ...
            outputFolder);

        assert(numel(matches) == 1, ...
            ['Dataset path is invalid and %d files with the same filename ' ...
             'were found below the current output folder. Refusing to guess.\n' ...
             'Dataset: %s\nSearched below: %s'], ...
            numel(matches), ...
            datasetFilename, ...
            outputFolder);

        STUDY.datasetinfo(datasetIndex).filepath = matches(1).folder;
        repairedCount = repairedCount + 1;
    end

    if repairedCount > 0
        fprintf('Repaired %d outdated STUDY dataset path(s) using current output folder.\n', ...
            repairedCount);
    end

    if nargin >= 3
        assert(numel(referenceALLEEG) == numel(STUDY.datasetinfo), ...
            'ROI dataset counts differ.');
        for index = 1:numel(referenceALLEEG)
            assert(strcmp(fullfile(STUDY.datasetinfo(index).filepath, ...
                    STUDY.datasetinfo(index).filename), ...
                fullfile(referenceALLEEG(index).filepath, referenceALLEEG(index).filename)), ...
                'ROI studies reference different epoch files.');
        end
        ALLEEG = referenceALLEEG;
    else
        ALLEEG = std_loadalleeg(STUDY);
    end

    assert(numel(ALLEEG) == numel(STUDY.datasetinfo), ...
        'Loaded dataset count does not match STUDY.datasetinfo.');

    for datasetIndex = 1:numel(STUDY.datasetinfo)
        STUDY.datasetinfo(datasetIndex).index = datasetIndex;
        STUDY.datasetinfo(datasetIndex).filename = ALLEEG(datasetIndex).filename;
        STUDY.datasetinfo(datasetIndex).filepath = ALLEEG(datasetIndex).filepath;
    end

    [STUDY, ALLEEG] = std_checkset(STUDY, ALLEEG);
end

